"""Silero VAD pre-gate with hangover to suppress noise-only decode."""

from __future__ import annotations

from typing import Any

import numpy as np

SAMPLE_RATE = 16000
VAD_THRESHOLD = 0.4
VAD_MIN_SPEECH_SEC = 0.2
VAD_MIN_SILENCE_SEC = 0.3
VAD_HANGOVER_SEC = 0.35
MIN_SEGMENT_SPEECH_SEC = 0.15


def create_vad(
    sherpa_onnx: Any,
    vad_path: Any,
    threshold: float = VAD_THRESHOLD,
    min_speech_sec: float = VAD_MIN_SPEECH_SEC,
    min_silence_sec: float = VAD_MIN_SILENCE_SEC,
) -> tuple[Any, int]:
    config = sherpa_onnx.VadModelConfig()
    config.silero_vad.model = str(vad_path)
    config.silero_vad.threshold = max(0.1, min(0.9, threshold))
    config.silero_vad.min_speech_duration = max(0.05, min(1.0, float(min_speech_sec)))
    config.silero_vad.min_silence_duration = max(0.05, min(2.0, float(min_silence_sec)))
    config.sample_rate = SAMPLE_RATE
    if not config.validate():
        raise ValueError("Invalid Silero VAD config")
    window_size = config.silero_vad.window_size
    return sherpa_onnx.VoiceActivityDetector(config, buffer_size_in_seconds=100), window_size


class SpeechGate:
    def __init__(self, vad: Any | None, window_size: int, hangover_sec: float = VAD_HANGOVER_SEC) -> None:
        self.vad = vad
        self.window_size = window_size
        self.hangover_sec = hangover_sec
        self._bypass = vad is None
        self._pending = np.array([], dtype=np.float32)
        self._gate_open = False
        self._hangover_remaining = 0.0
        self._segment_speech_samples = 0
        self._session_speech_samples = 0

    def reset_segment(self) -> None:
        self._segment_speech_samples = 0

    @property
    def session_has_speech(self) -> bool:
        return self._session_speech_samples > int(MIN_SEGMENT_SPEECH_SEC * SAMPLE_RATE)

    def accept_chunk(self, samples: np.ndarray) -> bool:
        flat = samples.reshape(-1).astype(np.float32, copy=False)
        if self._bypass:
            chunk_samples = len(flat)
            self._segment_speech_samples += chunk_samples
            self._session_speech_samples += chunk_samples
            return True

        self._pending = np.concatenate([self._pending, flat])
        while len(self._pending) >= self.window_size:
            self.vad.accept_waveform(self._pending[: self.window_size])
            self._pending = self._pending[self.window_size :]

        speech_now = self.vad.is_speech_detected()
        chunk_samples = len(flat)
        if speech_now:
            self._hangover_remaining = self.hangover_sec
            self._gate_open = True
            self._segment_speech_samples += chunk_samples
            self._session_speech_samples += chunk_samples
        elif self._hangover_remaining > 0:
            self._hangover_remaining = max(0.0, self._hangover_remaining - chunk_samples / SAMPLE_RATE)
            self._gate_open = True
        else:
            self._gate_open = False

        return self._gate_open

    def segment_has_speech(self) -> bool:
        return self._segment_speech_samples >= int(MIN_SEGMENT_SPEECH_SEC * SAMPLE_RATE)
