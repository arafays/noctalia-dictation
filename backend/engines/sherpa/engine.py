"""Sherpa-onnx two-pass engine (Zipformer streaming + Whisper/SenseVoice offline)."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from backend.engines.sherpa.packs import resolve_model_paths
from backend.engines.sherpa.vad import (
    SAMPLE_RATE,
    VAD_MIN_SILENCE_SEC,
    VAD_MIN_SPEECH_SEC,
    VAD_THRESHOLD,
    create_vad,
)

try:
    import sherpa_onnx
except ImportError as _exc:
    sherpa_onnx = None  # type: ignore[assignment]
    _IMPORT_ERROR = _exc
else:
    _IMPORT_ERROR = None


@dataclass
class SherpaEngine:
    models_dir: Path
    profile: str
    provider: str = "cpu"
    language: str = "auto"
    num_threads: int = 2
    vad_enabled: bool = True
    vad_threshold: float = VAD_THRESHOLD
    vad_min_speech_sec: float = VAD_MIN_SPEECH_SEC
    vad_min_silence_sec: float = VAD_MIN_SILENCE_SEC
    vad_hangover_sec: float = 0.35
    endpoint_silence1: float = 2.4
    endpoint_silence2: float = 1.2
    max_active_paths: int = 4
    auto_type: bool = True
    first: Any = field(default=None, repr=False)
    second: Any = field(default=None, repr=False)
    vad: Any = field(default=None, repr=False)
    vad_window_size: int = 512

    def load(self) -> None:
        if sherpa_onnx is None:
            raise RuntimeError(f"sherpa-onnx not installed: {_IMPORT_ERROR}")
        paths = resolve_model_paths(self.models_dir, self.profile)
        first = paths["first"]
        self.first = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=str(first["tokens"]),
            encoder=str(first["encoder"]),
            decoder=str(first["decoder"]),
            joiner=str(first["joiner"]),
            num_threads=max(1, min(8, int(self.num_threads))),
            sample_rate=SAMPLE_RATE,
            feature_dim=80,
            decoding_method="greedy_search",
            max_active_paths=max(1, min(8, int(self.max_active_paths))),
            provider=self.provider,
            enable_endpoint_detection=True,
            rule1_min_trailing_silence=max(0.5, min(6.0, float(self.endpoint_silence1))),
            rule2_min_trailing_silence=max(0.3, min(4.0, float(self.endpoint_silence2))),
            rule3_min_utterance_length=20,
        )
        second_paths = paths["second"]
        if paths["second_type"] == "whisper":
            lang = "" if self.language in ("auto", "") else self.language
            self.second = sherpa_onnx.OfflineRecognizer.from_whisper(
                encoder=str(second_paths["encoder"]),
                decoder=str(second_paths["decoder"]),
                tokens=str(second_paths["tokens"]),
                num_threads=self.num_threads,
                decoding_method="greedy_search",
                language=lang,
                task="transcribe",
                tail_paddings=-1,
            )
        else:
            self.second = sherpa_onnx.OfflineRecognizer.from_sense_voice(
                model=str(second_paths["model"]),
                tokens=str(second_paths["tokens"]),
                num_threads=self.num_threads,
                sample_rate=SAMPLE_RATE,
                feature_dim=80,
                use_itn=True,
                decoding_method="greedy_search",
            )
        self.vad, self.vad_window_size = (
            create_vad(
                sherpa_onnx,
                paths["vad"],
                self.vad_threshold,
                self.vad_min_speech_sec,
                self.vad_min_silence_sec,
            )
            if self.vad_enabled
            else (None, 512)
        )

    def describe(self) -> str:
        return f"sherpa-onnx two-pass + VAD ({self.profile}, {self.provider})"
