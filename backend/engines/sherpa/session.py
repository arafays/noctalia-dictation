"""Recording session: mic capture, two-pass decode, typing, and clipboard."""

from __future__ import annotations

import threading
import time
from typing import Any

import numpy as np

from backend.engines.sherpa.engine import SherpaEngine
from backend.engines.sherpa.vad import SAMPLE_RATE, SpeechGate
from backend.ipc.status import send_live, send_status
from backend.output.injection import copy_to_clipboard, type_committed
from backend.transcript.clean import clean_transcript

SEGMENT_TAIL_SAMPLES = 8000
MIN_RECORDING_SEC = 0.5
CHUNK_SEC = 0.1


def _run_second_pass(recognizer: Any, samples: np.ndarray) -> str:
    stream = recognizer.create_stream()
    stream.accept_waveform(SAMPLE_RATE, samples)
    recognizer.decode_stream(stream)
    return clean_transcript((stream.result.text or "").strip())


def _with_space_prefix(text: str, committed: str) -> str:
    if not text:
        return ""
    if committed and not committed.endswith((" ", "\n")):
        return " " + text
    return text


class SherpaSession:
    def __init__(self, engine: SherpaEngine) -> None:
        self.engine = engine
        self.stream = engine.first.create_stream()
        self.gate = SpeechGate(
            engine.vad,
            engine.vad_window_size,
            hangover_sec=max(0.05, min(1.5, float(engine.vad_hangover_sec))),
        )
        self.sample_buffers: list[np.ndarray] = []
        self.committed_text = ""
        self.current_partial = ""

    def _second_pass(self, samples: np.ndarray) -> str:
        return _run_second_pass(self.engine.second, samples)

    def _commit_refined(self, refined: str, fallback_partial: str = "") -> None:
        text = clean_transcript(refined) or clean_transcript(fallback_partial)
        if not text:
            return
        if not self.gate.segment_has_speech():
            return
        to_type = _with_space_prefix(text, self.committed_text)
        if to_type:
            if self.engine.auto_type:
                type_committed(to_type)
            self.committed_text += to_type

    def accept_chunk(self, samples: np.ndarray) -> None:
        if not self.gate.accept_chunk(samples):
            if self.current_partial:
                self.current_partial = ""
                send_live(self.committed_text, "")
            return

        self.stream.accept_waveform(SAMPLE_RATE, samples)
        self.sample_buffers.append(samples.copy())
        while self.engine.first.is_ready(self.stream):
            self.engine.first.decode_stream(self.stream)

        partial = clean_transcript((self.engine.first.get_result(self.stream) or "").strip())
        self.current_partial = partial
        send_live(self.committed_text, partial)

        if not self.engine.first.is_endpoint(self.stream):
            return

        if not partial and not self.sample_buffers:
            self.engine.first.reset(self.stream)
            self.gate.reset_segment()
            return

        samples_all = np.concatenate(self.sample_buffers) if self.sample_buffers else samples
        if len(samples_all) <= SEGMENT_TAIL_SAMPLES:
            self.engine.first.reset(self.stream)
            self.sample_buffers = []
            self.current_partial = ""
            self.gate.reset_segment()
            return

        self.sample_buffers = [samples_all[-SEGMENT_TAIL_SAMPLES:]]
        segment_audio = samples_all[:-SEGMENT_TAIL_SAMPLES]
        refined = self._second_pass(segment_audio) if len(segment_audio) > 0 else partial
        self._commit_refined(refined, partial)

        self.current_partial = ""
        send_live(self.committed_text, "")
        self.engine.first.reset(self.stream)
        self.gate.reset_segment()

    def finish(self) -> str:
        if self.sample_buffers:
            tail = np.concatenate(self.sample_buffers)
            if len(tail) > SEGMENT_TAIL_SAMPLES:
                refined = self._second_pass(tail)
                self._commit_refined(refined, self.current_partial)
            elif self.current_partial:
                self._commit_refined(self.current_partial)
        return self.committed_text.strip()


def record_session(
    engine: SherpaEngine,
    stop_event: threading.Event,
    timeout: float,
) -> None:
    session = SherpaSession(engine)
    chunk_samples = int(CHUNK_SEC * SAMPLE_RATE)
    recording_start = None

    import sounddevice as sd

    try:
        with sd.InputStream(channels=1, dtype="float32", samplerate=SAMPLE_RATE) as mic:
            recording_start = time.monotonic()
            send_status("recording", "", live_transcript="", partial_transcript="", engine=engine.describe())
            while not stop_event.is_set():
                if timeout > 0 and time.monotonic() - recording_start >= timeout:
                    break
                samples, _ = mic.read(chunk_samples)
                session.accept_chunk(samples.reshape(-1))

        duration = time.monotonic() - (recording_start or 0)
        if duration < MIN_RECORDING_SEC:
            send_status("idle", "cancelled", live_transcript="", partial_transcript="")
            return

        send_status(
            "transcribing",
            "finishing",
            live_transcript=session.committed_text,
            partial_transcript=session.current_partial,
            engine=engine.describe(),
        )
        full_text = session.finish()
        if full_text:
            copy_to_clipboard(full_text)
            send_status(
                "idle",
                "copied",
                full_text,
                live_transcript="",
                partial_transcript="",
                engine=engine.describe(),
            )
        elif session.gate.session_has_speech:
            send_status("idle", "silence", live_transcript="", partial_transcript="", engine=engine.describe())
        else:
            send_status("idle", "no_speech", live_transcript="", partial_transcript="", engine=engine.describe())
    except Exception as exc:
        send_status("error", str(exc), live_transcript="", partial_transcript="")
