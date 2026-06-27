"""Recording session: mic capture, periodic Whisper decode, typing, clipboard."""

from __future__ import annotations

import queue
import sys
import threading
import time

import numpy as np

from backend.engines.faster_whisper.engine import FasterWhisperEngine
from backend.ipc.status import send_live, send_status
from backend.output.injection import copy_to_clipboard, type_committed
from backend.transcript.clean import append_transcript, clean_transcript, compression_ratio

SAMPLE_RATE = 16000
MIN_RECORDING_SEC = 0.5
MIN_COMMIT_SEC = 0.8
CHUNK_SEC = 0.3
DECODER_JOIN_TIMEOUT_SEC = 120.0
MIN_COMMIT_SAMPLES = int(MIN_COMMIT_SEC * SAMPLE_RATE)


def _transcribe_audio(engine: FasterWhisperEngine, audio: np.ndarray) -> str:
    segments, info = engine.model.transcribe(audio, **engine.transcribe_options())
    if getattr(info, "no_speech_prob", 0.0) >= engine.no_speech_threshold:
        return ""
    text = clean_transcript(" ".join(s.text for s in segments).strip())
    if text and compression_ratio(text) >= engine.compression_ratio_threshold:
        return ""
    return text


class FasterWhisperSession:
    def __init__(self, engine: FasterWhisperEngine) -> None:
        self.engine = engine
        self._lock = threading.Lock()
        self.chunks: list[np.ndarray] = []
        self.committed_text = ""
        self.current_partial = ""
        self.session_has_speech = False
        self.segment_has_speech = False
        self.consecutive_silence = 0
        self.silence_rms = max(0.001, float(engine.silence_rms))
        self.max_silence_chunks = max(1, int(float(engine.pause_sec) / CHUNK_SEC))
        self.partial_interval_sec = max(0.5, float(engine.partial_interval_sec))
        self.last_partial_time = 0.0
        self._decode_wake = threading.Event()
        self._shutdown = False
        self._closed = False
        self._abandoned = False
        self._decode_queue: queue.Queue[tuple[np.ndarray, bool]] = queue.Queue()
        self._latest_partial: np.ndarray | None = None
        self._decoder = threading.Thread(target=self._decode_loop, daemon=True)
        self._decoder.start()

    def _segment_audio_locked(self) -> np.ndarray:
        if not self.chunks:
            return np.array([], dtype=np.float32)
        return np.concatenate(self.chunks, axis=0).flatten()

    def _commit_segment(self, segment_text: str) -> None:
        if self._abandoned:
            return
        text = clean_transcript(segment_text)
        if not text:
            return
        previous = self.committed_text
        updated = append_transcript(previous, text)
        if updated == previous:
            return
        to_type = updated[len(previous) :]
        if to_type and self.engine.auto_type:
            type_committed(to_type)
        self.committed_text = updated

    def _reset_segment_locked(self) -> None:
        self.chunks = []
        self.segment_has_speech = False
        self.current_partial = ""
        self.consecutive_silence = 0
        self.last_partial_time = 0.0

    def _drain_decode_queue_locked(self) -> None:
        while True:
            try:
                self._decode_queue.get_nowait()
            except queue.Empty:
                break

    def _enqueue_commit_locked(self, *, force: bool = False) -> None:
        audio = self._segment_audio_locked().copy()
        if not force and 0 < len(audio) < MIN_COMMIT_SAMPLES:
            return
        self._reset_segment_locked()
        self._latest_partial = None
        self._drain_decode_queue_locked()
        if len(audio) > 0:
            self._decode_queue.put((audio, True))
            self._decode_wake.set()

    def _enqueue_partial_locked(self) -> None:
        audio = self._segment_audio_locked().copy()
        if len(audio) == 0:
            return
        self._latest_partial = audio
        self._decode_wake.set()

    def _flush_partial_locked(self) -> None:
        if self._latest_partial is not None:
            self._decode_queue.put((self._latest_partial, False))
            self._latest_partial = None

    def _decode_loop(self) -> None:
        while True:
            self._decode_wake.wait(timeout=0.25)
            with self._lock:
                self._flush_partial_locked()
                if self._shutdown and self._decode_queue.empty():
                    return

            while True:
                try:
                    audio, do_commit = self._decode_queue.get_nowait()
                except queue.Empty:
                    break

                try:
                    text = _transcribe_audio(self.engine, audio)
                except Exception:
                    text = ""

                with self._lock:
                    if self._abandoned:
                        continue
                    if do_commit:
                        self._commit_segment(text)
                        send_live(self.committed_text, "")
                    else:
                        self.current_partial = text
                        send_live(self.committed_text, self.current_partial)

            with self._lock:
                if self._shutdown and self._decode_queue.empty() and self._latest_partial is None:
                    return

    def accept_chunk(self, samples: np.ndarray) -> None:
        with self._lock:
            self.chunks.append(samples.copy())
            rms = float(np.sqrt(np.mean(samples**2)))
            is_speech = rms >= self.silence_rms

            if is_speech:
                self.session_has_speech = True
                self.segment_has_speech = True
                self.consecutive_silence = 0
            elif self.segment_has_speech:
                self.consecutive_silence += 1

            now = time.monotonic()
            should_partial = (
                is_speech and self.segment_has_speech and now - self.last_partial_time >= self.partial_interval_sec
            )
            # Pause-based phrase boundaries (RMS silence), independent of vad_enabled.
            should_commit = self.segment_has_speech and self.consecutive_silence >= self.max_silence_chunks

            if should_commit:
                self._enqueue_commit_locked()
            elif should_partial:
                self.last_partial_time = now
                self._enqueue_partial_locked()

    def finish(self) -> str:
        with self._lock:
            if self.chunks:
                self._enqueue_commit_locked(force=True)
        self.close()
        return self.committed_text.strip()

    def close(self) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            self._shutdown = True
            self._flush_partial_locked()
        self._decode_wake.set()
        self._decoder.join(timeout=DECODER_JOIN_TIMEOUT_SEC)
        if self._decoder.is_alive():
            with self._lock:
                self._abandoned = True
            print(
                "dictation: decode thread did not finish in time; skipping late output",
                file=sys.stderr,
                flush=True,
            )


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
            session.close()
            send_status("idle", "cancelled", live_transcript="", partial_transcript="")
            return

        send_status(
            "transcribing",
            "finishing",
            live_transcript="",
            partial_transcript="",
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
        elif session.session_has_speech:
            send_status("idle", "silence", live_transcript="", partial_transcript="", engine=engine.describe())
        else:
            send_status("idle", "no_speech", live_transcript="", partial_transcript="", engine=engine.describe())
    except Exception as exc:
        session.close()
        send_status("error", str(exc), live_transcript="", partial_transcript="")
