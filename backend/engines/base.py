"""ASR engine protocol — implement this to add a new speech backend."""

from __future__ import annotations

import threading
from typing import Any, Protocol, runtime_checkable


@runtime_checkable
class AsrEngine(Protocol):
    """Loaded speech engine instance."""

    def load(self) -> None: ...
    def describe(self) -> str: ...


@runtime_checkable
class AsrEngineModule(Protocol):
    """Per-engine module registered in backend/engines/registry.py."""

    ENGINE_ID: str

    def available(self) -> bool: ...
    def import_error(self) -> Exception | None: ...
    def create_engine(self, settings: dict[str, Any], models_dir: Any) -> AsrEngine: ...
    def record_session(self, engine: AsrEngine, stop_event: threading.Event, timeout: float) -> None: ...
    def diagnose_checks(self, settings: dict[str, Any], models_dir: Any, plugin_dir: Any) -> list[dict[str, Any]]: ...
