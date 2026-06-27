"""ASR engine registry — register new backends here to try them in code."""

from __future__ import annotations

import threading
from typing import Any

from backend.engines import faster_whisper, sherpa
from backend.paths import models_dir, plugin_dir

# Map settings["engine"] values to engine modules.
# "auto" resolves to the default (sherpa) until more engines are added.
ENGINES: dict[str, Any] = {
    "sherpa": sherpa,
    "faster_whisper": faster_whisper,
    "auto": sherpa,
}

DEFAULT_ENGINE = "sherpa"


def resolve_engine_id(settings: dict[str, Any]) -> str:
    engine_id = settings.get("engine", "auto")
    if engine_id == "auto":
        return DEFAULT_ENGINE
    if engine_id not in ENGINES:
        known = ", ".join(sorted(k for k in ENGINES if k != "auto"))
        raise RuntimeError(f"Unknown engine '{engine_id}'. Available: {known}")
    return engine_id


def get_engine_module(settings: dict[str, Any]) -> Any:
    return ENGINES[resolve_engine_id(settings)]


def load_engine(settings: dict[str, Any]) -> tuple[Any, str, str]:
    """Load the configured ASR engine. Returns (engine, engine_id, label)."""
    mod = get_engine_module(settings)
    pd = plugin_dir()

    if not mod.available():
        err = mod.import_error()
        raise RuntimeError(
            f"{mod.ENGINE_ID} dependencies not installed ({err}). "
            f"Fix: cd {pd} && ./setup.sh"
        )

    engine = mod.create_engine(settings, models_dir())
    return engine, mod.ENGINE_ID, engine.describe()


def record_session(engine: Any, stop_event: threading.Event, timeout: float, engine_id: str) -> None:
    mod = ENGINES.get(engine_id, sherpa)
    mod.record_session(engine, stop_event, timeout)
