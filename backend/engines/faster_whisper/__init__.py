"""faster-whisper engine — CTranslate2 Whisper with silence segmentation."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from backend.engines.faster_whisper.engine import (
    _IMPORT_ERROR,
    VALID_COMPUTE_TYPES,
    VALID_DEVICES,
    VALID_MODELS,
    FasterWhisperEngine,
    WhisperModel,
)

ENGINE_ID = "faster_whisper"


def available() -> bool:
    return WhisperModel is not None


def import_error() -> Exception | None:
    return _IMPORT_ERROR


def has_cuda() -> bool:
    try:
        return (
            subprocess.run(
                ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
                capture_output=True,
                timeout=2,
                check=False,
            ).returncode
            == 0
        )
    except Exception:
        return False


def resolve_device(settings: dict[str, Any]) -> str:
    device = settings.get("fwDevice", "auto")
    if device == "auto":
        return "cuda" if has_cuda() else "cpu"
    if device not in VALID_DEVICES:
        raise RuntimeError(f"Unknown fwDevice '{device}'. Use: auto, cpu, cuda")
    return device


def resolve_compute_type(settings: dict[str, Any], device: str) -> str:
    compute = settings.get("fwComputeType", "auto")
    if compute == "auto":
        return "int8_float16" if device == "cuda" else "int8"
    if compute not in VALID_COMPUTE_TYPES:
        raise RuntimeError(f"Unknown fwComputeType '{compute}'. Use: auto, int8, int8_float16, float16, float32")
    if device == "cpu" and compute in ("float16", "int8_float16"):
        return "int8"
    return compute


def resolve_model(settings: dict[str, Any]) -> str:
    model = settings.get("fwModel", "small")
    if model not in VALID_MODELS:
        raise RuntimeError(f"Unknown fwModel '{model}'. Use: {', '.join(VALID_MODELS)}")
    return model


def create_engine(settings: dict[str, Any], models_dir: Path) -> FasterWhisperEngine:
    del models_dir  # faster-whisper downloads models to Hugging Face cache
    if not available():
        raise RuntimeError(f"faster-whisper Python package not installed ({import_error()})")

    device = resolve_device(settings)
    compute_type = resolve_compute_type(settings, device)
    model_size = resolve_model(settings)

    try:
        engine = FasterWhisperEngine(
            model_size=model_size,
            device=device,
            compute_type=compute_type,
            language=settings.get("language", "auto"),
            auto_type=bool(settings.get("autoType", True)),
            vad_enabled=bool(settings.get("vadEnabled", True)),
            beam_size=int(settings.get("fwBeamSize", 5)),
            temperature=float(settings.get("fwTemperature", 0.0)),
            initial_prompt=str(settings.get("fwInitialPrompt", "") or ""),
            condition_on_previous_text=bool(settings.get("fwConditionOnPreviousText", True)),
            no_speech_threshold=float(settings.get("fwNoSpeechThreshold", 0.6)),
            compression_ratio_threshold=float(settings.get("fwCompressionRatioThreshold", 2.4)),
            silence_rms=float(settings.get("fwSilenceRms", 0.01)),
            pause_sec=float(settings.get("fwPauseSec", 1.5)),
            partial_interval_sec=float(settings.get("fwPartialIntervalSec", 2.5)),
            internal_vad=bool(settings.get("fwInternalVad", False)),
        )
        engine.load()
    except Exception as exc:
        if device == "cuda":
            raise RuntimeError(
                f"Failed to load faster-whisper with CUDA ({exc}). "
                "Set fw device to CPU in plugin settings, or fix your NVIDIA/CUDA install."
            ) from exc
        raise
    return engine


def diagnose_checks(settings: dict[str, Any], models_dir: Path, plugin_dir: Path) -> list[dict[str, Any]]:
    del models_dir
    checks: list[dict[str, Any]] = []

    fw_ok = available()
    checks.append(
        {
            "id": "faster_whisper",
            "ok": fw_ok,
            "label": "faster-whisper package",
            "detail": "installed" if fw_ok else str(import_error()),
            "fix": f"cd {plugin_dir} && ./setup.sh",
        }
    )

    if fw_ok:
        model = resolve_model(settings)
        device = resolve_device(settings)
        compute = resolve_compute_type(settings, device)
        checks.append(
            {
                "id": "fw_model",
                "ok": True,
                "label": f"Whisper model ({model})",
                "detail": f"downloads on first use ({device}, {compute})",
                "fix": "",
            }
        )

    return checks


def record_session(engine: FasterWhisperEngine, stop_event: Any, timeout: float) -> None:
    from backend.engines.faster_whisper.session import record_session as _record

    _record(engine, stop_event, timeout)


__all__ = [
    "ENGINE_ID",
    "FasterWhisperEngine",
    "available",
    "create_engine",
    "diagnose_checks",
    "import_error",
    "record_session",
    "resolve_model",
]
