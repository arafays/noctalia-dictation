"""Install health checks for the settings UI."""

from __future__ import annotations

import sys
from typing import Any

from backend.config import read_settings
from backend.engines.registry import get_engine_module, resolve_engine_id
from backend.output.injection import check_injection_tools, injection_tools_error_message
from backend.paths import models_dir, plugin_dir


def diagnose_install() -> dict[str, Any]:
    settings = read_settings()
    pd = plugin_dir()
    engine_id = resolve_engine_id(settings)
    mod = get_engine_module(settings)

    checks: list[dict[str, Any]] = []

    py_ok = sys.version_info >= (3, 10)
    checks.append(
        {
            "id": "python",
            "ok": py_ok,
            "label": "Python 3.10+",
            "detail": f"{sys.version.split()[0]} ({sys.executable})",
            "fix": "Install Python 3.10 or newer, then run ./setup.sh in the plugin directory",
        }
    )

    checks.extend(mod.diagnose_checks(settings, models_dir(), pd))

    try:
        import sounddevice  # noqa: F401

        sd_ok, sd_detail = True, "installed"
    except Exception as exc:
        sd_ok, sd_detail = False, str(exc)
    checks.append(
        {
            "id": "sounddevice",
            "ok": sd_ok,
            "label": "sounddevice (microphone)",
            "detail": sd_detail,
            "fix": "Install PortAudio (e.g. pacman -S portaudio), then re-run ./setup.sh",
        }
    )

    missing_tools = check_injection_tools()
    inj_ok = not missing_tools
    checks.append(
        {
            "id": "typing",
            "ok": inj_ok,
            "label": "wtype + wl-copy",
            "detail": "available" if inj_ok else f"missing: {', '.join(missing_tools)}",
            "fix": injection_tools_error_message(missing_tools) if missing_tools else "",
        }
    )

    profile = getattr(mod, "resolve_profile", lambda s: engine_id)(settings)

    return {
        "ready": all(c["ok"] for c in checks),
        "pluginDir": str(pd),
        "engine": engine_id,
        "profile": profile,
        "checks": checks,
    }
