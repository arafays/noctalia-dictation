"""faster-whisper engine (CTranslate2 Whisper)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

try:
    from faster_whisper import WhisperModel
except ImportError as _exc:
    WhisperModel = None  # type: ignore[assignment,misc]
    _IMPORT_ERROR = _exc
else:
    _IMPORT_ERROR = None

VALID_MODELS = ("tiny", "base", "small", "medium", "large-v2", "large-v3")
VALID_DEVICES = ("cpu", "cuda")
VALID_COMPUTE_TYPES = ("int8", "int8_float16", "float16", "float32", "default")


@dataclass
class FasterWhisperEngine:
    model_size: str = "small"
    device: str = "cpu"
    compute_type: str = "int8"
    language: str = "auto"
    auto_type: bool = True
    vad_enabled: bool = True
    beam_size: int = 5
    temperature: float = 0.0
    initial_prompt: str = ""
    condition_on_previous_text: bool = True
    no_speech_threshold: float = 0.6
    compression_ratio_threshold: float = 2.4
    silence_rms: float = 0.01
    pause_sec: float = 1.5
    partial_interval_sec: float = 2.5
    internal_vad: bool = False
    model: Any = field(default=None, repr=False)

    def transcribe_options(self) -> dict[str, Any]:
        opts: dict[str, Any] = {
            "beam_size": max(1, min(10, int(self.beam_size))),
            "temperature": max(0.0, min(1.0, float(self.temperature))),
            "condition_on_previous_text": bool(self.condition_on_previous_text),
            "no_speech_threshold": max(0.1, min(0.95, float(self.no_speech_threshold))),
            "compression_ratio_threshold": max(1.0, min(4.0, float(self.compression_ratio_threshold))),
            "vad_filter": bool(self.internal_vad),
        }
        if self.language and self.language not in ("auto", ""):
            opts["language"] = self.language
        prompt = (self.initial_prompt or "").strip()
        if prompt:
            opts["initial_prompt"] = prompt
        return opts

    def load(self) -> None:
        if WhisperModel is None:
            raise RuntimeError(f"faster-whisper not installed: {_IMPORT_ERROR}")
        self.model = WhisperModel(
            self.model_size,
            device=self.device,
            compute_type=self.compute_type,
        )

    def describe(self) -> str:
        lang = self.language if self.language not in ("auto", "") else "auto-detect"
        return f"faster-whisper {self.model_size} ({self.device}, {self.compute_type}, {lang}, beam={self.beam_size})"
