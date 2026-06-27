"""IPC status updates to the Noctalia QML plugin."""

from __future__ import annotations

import contextlib
import json
import subprocess
import time

from backend.paths import STATUS_FILE

_last_live_sent = 0.0
_last_file_payload = ""


def _write_status_file(payload: dict[str, str]) -> None:
    global _last_file_payload
    try:
        body = json.dumps(payload, separators=(",", ":"))
        if body == _last_file_payload:
            return
        _last_file_payload = body
        tmp = STATUS_FILE.with_suffix(".tmp")
        tmp.write_text(body)
        tmp.rename(STATUS_FILE)
    except Exception:
        pass


def clear_status_file() -> None:
    global _last_file_payload
    _last_file_payload = ""
    with contextlib.suppress(Exception):
        STATUS_FILE.unlink(missing_ok=True)


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
    _write_status_file(payload)

    # Live transcript ticks go via status file only — qs ipc would activate the shell
    # and steal keyboard focus from the window being dictated into.
    if state == "recording" and message == "live":
        return

    if state in ("idle", "stopped", "error"):
        clear_status_file()

    with contextlib.suppress(Exception):
        subprocess.run(
            ["qs", "ipc", "-c", "noctalia-shell", "call", "plugin:dictation", "setStatus", json.dumps(payload)],
            capture_output=True,
            timeout=2,
            check=False,
        )


def send_live(live_transcript: str, partial_transcript: str) -> None:
    global _last_live_sent
    now = time.monotonic()
    if now - _last_live_sent < 0.25:
        return
    _last_live_sent = now
    _write_status_file(
        {
            "state": "recording",
            "message": "live",
            "liveTranscript": live_transcript,
            "partialTranscript": partial_transcript,
        }
    )
