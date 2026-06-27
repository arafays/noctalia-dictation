"""sherpa-onnx engine — two-pass Zipformer + Whisper/SenseVoice."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from backend.engines.sherpa.engine import _IMPORT_ERROR, SherpaEngine, sherpa_onnx
from backend.engines.sherpa.packs import models_missing_reason, profile_for_language

ENGINE_ID = "sherpa"


def available() -> bool:
    return sherpa_onnx is not None


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


def resolve_profile(settings: dict[str, Any]) -> str:
    profile = settings.get("sherpaProfile", "auto")
    if profile == "auto":
        profile = profile_for_language(settings.get("language", "auto"))
    return profile


def create_engine(settings: dict[str, Any], models_dir: Path) -> SherpaEngine:
    if not available():
        raise RuntimeError(f"sherpa-onnx Python package not installed ({import_error()})")

    profile = resolve_profile(settings)
    reason = models_missing_reason(models_dir, profile)
    if reason:
        raise RuntimeError(reason)

    provider = settings.get("sherpaProvider", "auto")
    if provider == "auto":
        provider = "cuda" if has_cuda() else "cpu"

    try:
        engine = SherpaEngine(
            models_dir=models_dir,
            profile=profile,
            provider=provider,
            language=settings.get("language", "auto"),
            num_threads=int(settings.get("sherpaNumThreads", 2)),
            vad_enabled=bool(settings.get("vadEnabled", True)),
            vad_threshold=float(settings.get("vadThreshold", 0.4)),
            vad_min_speech_sec=float(settings.get("sherpaMinSpeechSec", 0.2)),
            vad_min_silence_sec=float(settings.get("sherpaMinSilenceSec", 0.3)),
            vad_hangover_sec=float(settings.get("sherpaHangoverSec", 0.35)),
            endpoint_silence1=float(settings.get("sherpaEndpointSilence1", 2.4)),
            endpoint_silence2=float(settings.get("sherpaEndpointSilence2", 1.2)),
            max_active_paths=int(settings.get("sherpaMaxActivePaths", 4)),
            auto_type=bool(settings.get("autoType", True)),
        )
        engine.load()
    except Exception as exc:
        if provider == "cuda":
            raise RuntimeError(
                f"Failed to load sherpa engine with CUDA ({exc}). "
                "Set sherpa provider to CPU in plugin settings, or fix your NVIDIA/CUDA install."
            ) from exc
        raise
    return engine


def diagnose_checks(settings: dict[str, Any], models_dir: Path, plugin_dir: Path) -> list[dict[str, Any]]:
    profile = resolve_profile(settings)
    checks: list[dict[str, Any]] = []

    sherpa_ok = available()
    checks.append(
        {
            "id": "sherpa",
            "ok": sherpa_ok,
            "label": "sherpa-onnx package",
            "detail": "installed" if sherpa_ok else str(import_error()),
            "fix": f"cd {plugin_dir} && ./setup.sh",
        }
    )

    models_reason = models_missing_reason(models_dir, profile)
    checks.append(
        {
            "id": "models",
            "ok": models_reason is None,
            "label": f"ONNX models ({profile})",
            "detail": "ready" if models_reason is None else models_reason,
            "fix": f"cd {plugin_dir} && ./download_models.sh {profile}",
        }
    )

    return checks


def record_session(engine: SherpaEngine, stop_event: Any, timeout: float) -> None:
    from backend.engines.sherpa.session import record_session as _record

    _record(engine, stop_event, timeout)


__all__ = [
    "ENGINE_ID",
    "SherpaEngine",
    "available",
    "create_engine",
    "diagnose_checks",
    "import_error",
    "record_session",
    "resolve_profile",
]
