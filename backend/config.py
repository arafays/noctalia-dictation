"""User settings loaded from Noctalia plugin config."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

DEFAULTS: dict[str, Any] = {
    "engine": "auto",
    "language": "auto",
    "recordingTimeout": 0,
    "sherpaProfile": "auto",
    "sherpaProvider": "auto",
    "sherpaNumThreads": 2,
    "sherpaMinSpeechSec": 0.2,
    "sherpaMinSilenceSec": 0.3,
    "sherpaHangoverSec": 0.35,
    "sherpaEndpointSilence1": 2.4,
    "sherpaEndpointSilence2": 1.2,
    "sherpaMaxActivePaths": 4,
    "fwModel": "small",
    "fwDevice": "auto",
    "fwComputeType": "auto",
    "fwBeamSize": 5,
    "fwTemperature": 0.0,
    "fwInitialPrompt": "",
    "fwConditionOnPreviousText": True,
    "fwNoSpeechThreshold": 0.6,
    "fwCompressionRatioThreshold": 2.4,
    "fwSilenceRms": 0.01,
    "fwPauseSec": 1.5,
    "fwPartialIntervalSec": 2.5,
    "fwInternalVad": False,
    "autoType": True,
    "vadEnabled": True,
    "vadThreshold": 0.4,
}

# Settings that require backend restart when changed.
ENGINE_RELOAD_KEYS = (
    "engine",
    "language",
    "sherpaProfile",
    "sherpaProvider",
    "sherpaNumThreads",
    "sherpaMinSpeechSec",
    "sherpaMinSilenceSec",
    "sherpaHangoverSec",
    "sherpaEndpointSilence1",
    "sherpaEndpointSilence2",
    "sherpaMaxActivePaths",
    "fwModel",
    "fwDevice",
    "fwComputeType",
    "fwBeamSize",
    "fwTemperature",
    "fwInitialPrompt",
    "fwConditionOnPreviousText",
    "fwNoSpeechThreshold",
    "fwCompressionRatioThreshold",
    "fwSilenceRms",
    "fwPauseSec",
    "fwPartialIntervalSec",
    "fwInternalVad",
    "vadEnabled",
    "vadThreshold",
    "autoType",
)


def settings_path() -> Path:
    config_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_dir / "noctalia" / "plugins" / "dictation" / "settings.json"


def read_settings() -> dict[str, Any]:
    path = settings_path()
    if path.exists():
        stored = json.loads(path.read_text())
        return {**DEFAULTS, **stored}
    return dict(DEFAULTS)
