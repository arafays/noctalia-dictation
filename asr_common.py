"""Shared dictation helpers: IPC status, typing, clipboard."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import threading
import time

# SenseVoice / Whisper control tokens, e.g. <|Speech|><|NEUTRAL|>
_TAG_RE = re.compile(r"<\|[^|]+\|>")

# Bracketed non-speech annotations, e.g. [wind howling], (mumbling)
_BRACKETED_RE = re.compile(r"[\[\(\{]([^\]\)\}]+)[\]\)\}]")

_NOISE_KEYWORDS = frozenset({
    "mumbling", "inaudible", "unintelligible", "indistinct", "unclear",
    "silence", "silent", "blank", "audio", "nospeech", "speech",
    "background", "noise", "static", "wind", "howling", "blowing", "rustling",
    "music", "musical", "applause", "laughter", "laughing", "coughing", "cough",
    "sneezing", "sneeze", "breathing", "breath", "sigh", "sighing",
    "whispering", "whisper", "humming", "screaming", "shouting",
    "door", "slam", "slamming", "knock", "knocking", "phone", "ringing",
    "beep", "beeping", "click", "clicking", "tap", "tapping",
    "subtitle", "subtitles", "subscribe", "watching",
    "crowd", "talking", "chatter", "murmur", "murmuring",
    "water", "running", "rain", "thunder", "traffic",
    "sounds", "sound", "effects", "effect", "ambient",
})

_NOISE_ONLY_RE = re.compile(
    r"(?i)^(?:"
    r"\[?\s*blank\s*audio\s*\]?|"
    r"\[?\s*inaudible\s*\]?|"
    r"\[?\s*silence\s*\]?|"
    r"♪+|♫+|\.\.\.|"
    r"thank\s+you\s+for\s+watching\.?|"
    r"please\s+subscribe\.?"
    r")$",
)


def _normalize_noise_phrase(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[_\-]+", " ", text.strip().lower()))


def _phrase_is_noise_only(text: str) -> bool:
    cleaned = _normalize_noise_phrase(text)
    if not cleaned:
        return True
    if _NOISE_ONLY_RE.match(cleaned):
        return True
    words = re.findall(r"[a-z']+", cleaned)
    if not words:
        return True
    if all(word in _NOISE_KEYWORDS for word in words):
        return True
    speech_markers = {"i", "a", "an", "the", "is", "are", "was", "were", "you", "we", "they", "it", "to", "and", "or"}
    if len(words) <= 6 and not any(word in speech_markers for word in words):
        noise_hits = sum(1 for word in words if word in _NOISE_KEYWORDS)
        if noise_hits >= (len(words) + 1) // 2:
            return True
    return False


def _strip_bracketed_noise(text: str) -> str:
    def repl(match: re.Match[str]) -> str:
        return " " if _phrase_is_noise_only(match.group(1)) else match.group(0)

    return _BRACKETED_RE.sub(repl, text)


def clean_transcript(text: str) -> str:
    """Drop model tags and common non-speech hallucinations from ASR output."""
    if not text:
        return ""
    text = _TAG_RE.sub("", text)
    text = _strip_bracketed_noise(text)
    text = re.sub(r"[♪♫]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if _phrase_is_noise_only(text):
        return ""
    return text

_typing_lock = threading.Lock()
_last_live_sent = 0.0
_WTYPE_CHUNK = 256


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
            capture_output=True, timeout=2, check=False,
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


def _type_with_wtype(text: str) -> bool:
    if not shutil.which("wtype") or not text:
        return False
    try:
        for i in range(0, len(text), _WTYPE_CHUNK):
            chunk = text[i:i + _WTYPE_CHUNK]
            args = ["wtype"]
            if chunk.startswith("-"):
                args.extend(["--", chunk])
            else:
                args.append(chunk)
            if subprocess.run(args, capture_output=True, timeout=10, check=False).returncode != 0:
                return False
            if i + _WTYPE_CHUNK < len(text):
                time.sleep(0.02)
        return True
    except Exception:
        return False


def type_committed(text: str) -> None:
    if not text:
        return
    with _typing_lock:
        if _needs_paste(text):
            _type_text_paste(text)
        elif not _type_with_wtype(text):
            _type_text_paste(text)


def copy_to_clipboard(text: str) -> None:
    try:
        subprocess.run(["wl-copy"], input=text.encode(), check=True, timeout=2)
    except Exception:
        pass


def check_injection_tools() -> list[str]:
    missing = [t for t in ["wl-copy", "wtype"] if not shutil.which(t)]
    if not missing:
        return []
    if shutil.which("ydotool"):
        return []
    return missing
