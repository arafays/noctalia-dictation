"""Drop model tags and common non-speech hallucinations from ASR output."""

from __future__ import annotations

import re

_TAG_RE = re.compile(r"<\|[^|]+\|>")
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


_FILLER_PHRASES = (
    r"\byou know\b,?",
    r"\bi mean\b,?",
    r"\bkind of\b",
    r"\bsort of\b",
)
_FILLER_STANDALONE = re.compile(
    r"(?i)\b(?:um+|uh+|er+|ah+|hmm+|hm+|mm+|mhm+)\b,?\s*",
)
_FILLER_PHRASE_RES = [re.compile(p, re.IGNORECASE) for p in _FILLER_PHRASES]


def _strip_filler_words(text: str) -> str:
    for pattern in _FILLER_PHRASE_RES:
        text = pattern.sub(" ", text)
    text = _FILLER_STANDALONE.sub(" ", text)
    return text


def clean_transcript(text: str) -> str:
    if not text:
        return ""
    text = _TAG_RE.sub("", text)
    text = _strip_bracketed_noise(text)
    text = re.sub(r"[♪♫]+", " ", text)
    text = _strip_filler_words(text)
    text = re.sub(r"\s+", " ", text).strip()
    if _phrase_is_noise_only(text):
        return ""
    return text
