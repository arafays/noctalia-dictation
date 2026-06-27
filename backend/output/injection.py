"""Text injection (wtype) and clipboard helpers."""

from __future__ import annotations

import contextlib
import os
import shutil
import subprocess
import sys
import threading
import time

_typing_lock = threading.Lock()
_WTYPE_CHUNK = 256


def _needs_paste(text: str) -> bool:
    if not text.isascii():
        return True
    return any(ord(c) < 32 or ord(c) == 127 for c in text)


def _type_text_paste(text: str) -> None:
    try:
        subprocess.run(["wl-copy"], input=text.encode(), check=True, timeout=2)
    except Exception:
        return
    time.sleep(0.12)
    for cmd in [
        ["wtype", "-M", "ctrl", "v", "-m", "ctrl"],
        ["ydotool", "key", "29:1", "47:1", "47:0", "29:0"],
    ]:
        try:
            if subprocess.run(cmd, capture_output=True, timeout=5, check=False).returncode == 0:
                break
        except Exception:
            continue


def _log_injection(msg: str) -> None:
    print(f"dictation: {msg}", file=sys.stderr, flush=True)


def _type_with_wtype(text: str) -> bool:
    if not shutil.which("wtype") or not text:
        return False
    env = os.environ.copy()
    try:
        for i in range(0, len(text), _WTYPE_CHUNK):
            chunk = text[i : i + _WTYPE_CHUNK]
            args = ["wtype"]
            if chunk.startswith("-"):
                args.extend(["--", chunk])
            else:
                args.append(chunk)
            result = subprocess.run(args, capture_output=True, timeout=10, check=False, env=env)
            if result.returncode != 0:
                err = (result.stderr or b"").decode(errors="replace").strip()
                _log_injection(f"wtype failed ({result.returncode}): {err or 'unknown error'}")
                return False
            if i + _WTYPE_CHUNK < len(text):
                time.sleep(0.02)
        return True
    except Exception as exc:
        _log_injection(f"wtype error: {exc}")
        return False


def type_committed(text: str) -> None:
    if not text:
        return
    with _typing_lock:
        if _needs_paste(text) or not _type_with_wtype(text):
            _type_text_paste(text)


def copy_to_clipboard(text: str) -> None:
    with contextlib.suppress(Exception):
        subprocess.run(["wl-copy"], input=text.encode(), check=True, timeout=2)


def check_injection_tools() -> list[str]:
    missing = [t for t in ["wl-copy", "wtype"] if not shutil.which(t)]
    if not missing:
        return []
    if shutil.which("ydotool"):
        return []
    return missing


def injection_tools_error_message(missing: list[str]) -> str:
    parts: list[str] = []
    if "wtype" in missing:
        parts.append(
            "wtype not found (types text into focused windows). "
            "Install: pacman -S wtype, apt install wtype, or dnf install wtype"
        )
    if "wl-copy" in missing:
        parts.append(
            "wl-copy not found (session clipboard). "
            "Install wl-clipboard: pacman -S wl-clipboard, apt install wl-clipboard"
        )
    if parts:
        parts.append("Alternatively install ydotool for paste fallback, or disable auto-type in plugin settings")
    return " ".join(parts)
