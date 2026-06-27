"""Recording session: mic capture, periodic Whisper decode, typing, clipboard."""

from __future__ import annotations

import threading
import time

import numpy as np

from backend.engines.faster_whisper.engine import FasterWhisperEngine
from backend.ipc.status import send_live, send_status
from backend.output.injection import copy_to_clipboard, type_committed
from backend.transcript.clean import clean_transcript

SAMPLE_RATE = 16000
MIN_RECORDING_SEC = 0.5
CHUNK_SEC = 0.3


def _transcribe_audio(engine: FasterWhisperEngine, audio: np.ndarray) -> str:
    segments, _info = engine.model.transcribe(audio, **engine.transcribe_options())
    return clean_transcript(" ".join(s.text for s in segments).strip())


def _delta_text(full_text: str, committed: str) -> str:
    if not full_text:
        return ""
    if not committed:
        return full_text
    if full_text.startswith(committed):
        return full_text[len(committed) :].lstrip()
    return full_text


def _with_space_prefix(text: str, committed: str) -> str:
    if not text:
        return ""
    if committed and not committed.endswith((" ", "\n")):
        return " " + text
    return text


class FasterWhisperSession:
    def __init__(self, engine: FasterWhisperEngine) -> None:
        self.engine = engine
        self.chunks: list[np.ndarray] = []
        self.committed_text = ""
        self.current_partial = ""
        self.session_has_speech = False
        self.consecutive_silence = 0
        self.silence_rms = max(0.001, float(engine.silence_rms))
        self.max_silence_chunks = max(1, int(float(engine.pause_sec) / CHUNK_SEC))
        self.partial_interval_sec = max(0.5, float(engine.partial_interval_sec))
        self.last_partial_time = 0.0

    def _all_audio(self) -> np.ndarray:
        if not self.chunks:
            return np.array([], dtype=np.float32)
        return np.concatenate(self.chunks, axis=0).flatten()

    def _decode_all(self) -> str:
        audio = self._all_audio()
        if len(audio) == 0:
            return ""
        return _transcribe_audio(self.engine, audio)

    def _commit_delta(self, full_text: str) -> None:
        delta = _delta_text(full_text, self.committed_text)
        if not delta:
            return
        to_type = _with_space_prefix(delta, self.committed_text)
        if to_type:
            if self.engine.auto_type:
                type_committed(to_type)
            self.committed_text += to_type

    def accept_chunk(self, samples: np.ndarray) -> None:
        self.chunks.append(samples.copy())
        rms = float(np.sqrt(np.mean(samples**2)))
        is_speech = rms >= self.silence_rms

        if is_speech:
            self.session_has_speech = True
            self.consecutive_silence = 0
        elif self.session_has_speech:
            self.consecutive_silence += 1

        now = time.monotonic()
        should_partial = (
            is_speech
            and self.session_has_speech
            and now - self.last_partial_time >= self.partial_interval_sec
        )
        should_commit = (
            self.engine.vad_enabled
            and self.session_has_speech
            and self.consecutive_silence >= self.max_silence_chunks
        )

        if should_partial or should_commit:
            full_text = self._decode_all()
            if should_commit:
                self._commit_delta(full_text)
                self.current_partial = ""
                self.consecutive_silence = 0
                send_live(self.committed_text, "")
            else:
                self.current_partial = _delta_text(full_text, self.committed_text)
                self.last_partial_time = now
                send_live(self.committed_text, self.current_partial)

    def finish(self) -> str:
        if self.chunks:
            full_text = self._decode_all()
            self._commit_delta(full_text)
        return self.committed_text.strip()


def record_session(
    engine: FasterWhisperEngine,
    stop_event: threading.Event,
    timeout: float,
) -> None:
    session = FasterWhisperSession(engine)
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
                "idle", "copied", full_text,
                live_transcript="", partial_transcript="", engine=engine.describe(),
            )
        elif session.session_has_speech:
            send_status("idle", "silence", live_transcript="", partial_transcript="", engine=engine.describe())
        else:
            send_status("idle", "no_speech", live_transcript="", partial_transcript="", engine=engine.describe())
    except Exception as exc:
        send_status("error", str(exc), live_transcript="", partial_transcript="")
