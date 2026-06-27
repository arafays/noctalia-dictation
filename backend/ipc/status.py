"""IPC status updates to the Noctalia QML plugin."""

from __future__ import annotations

import json
import subprocess
import time

_last_live_sent = 0.0


def send_status(
    state: str,
    message: str = "",
    text: str = "",
    live_transcript: str = "",
    partial_transcript: str = "",
    engine: str = "",
) -> None:
    payload: dict[str, str] = {"state": state, "message": message}
    if text:
        payload["text"] = text
    if live_transcript or partial_transcript or state == "recording":
        payload["liveTranscript"] = live_transcript
        payload["partialTranscript"] = partial_transcript
    if engine:
        payload["engine"] = engine
    try:
        subprocess.run(
            ["qs", "ipc", "-c", "noctalia-shell", "call", "plugin:dictation", "setStatus", json.dumps(payload)],
            capture_output=True,
            timeout=2,
            check=False,
        )
    except Exception:
        pass


def send_live(live_transcript: str, partial_transcript: str) -> None:
    global _last_live_sent
    now = time.monotonic()
    if now - _last_live_sent < 0.25:
        return
    _last_live_sent = now
    send_status("recording", "live", live_transcript=live_transcript, partial_transcript=partial_transcript)
