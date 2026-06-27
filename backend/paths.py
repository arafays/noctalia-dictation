"""Plugin root paths — repo root, not the backend/ package directory."""

from __future__ import annotations

import contextlib
import os
from pathlib import Path

# backend/paths.py → plugin root is parent of backend/
PLUGIN_ROOT = Path(__file__).resolve().parent.parent


def plugin_dir() -> Path:
    return PLUGIN_ROOT


def models_dir() -> Path:
    return PLUGIN_ROOT / "models"


def runtime_dir() -> Path:
    d = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/user-{os.getuid()}"))
    with contextlib.suppress(OSError):
        d.mkdir(parents=True, exist_ok=True)
    return d


SIGNAL_FILE = runtime_dir() / "noctalia-dictation-signal"
PID_FILE = runtime_dir() / "noctalia-dictation-pid"
STATUS_FILE = runtime_dir() / "noctalia-dictation-status.json"
