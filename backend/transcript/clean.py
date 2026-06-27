"""Drop model tags and common non-speech hallucinations from ASR output."""

from __future__ import annotations

import re
import zlib

_TAG_RE = re.compile(r"<\|[^|]+\|>")
_BRACKETED_RE = re.compile(r"[\[\(\{]([^\]\)\}]+)[\]\)\}]")

_NOISE_KEYWORDS = frozenset(
    {
        "mumbling",
        "inaudible",
        "unintelligible",
        "indistinct",
        "unclear",
        "silence",
        "silent",
        "blank",
        "audio",
        "nospeech",
        "speech",
        "background",
        "noise",
        "static",
        "wind",
        "howling",
        "blowing",
        "rustling",
        "music",
        "musical",
        "applause",
        "laughter",
        "laughing",
        "coughing",
        "cough",
        "sneezing",
        "sneeze",
        "breathing",
        "breath",
        "sigh",
        "sighing",
        "whispering",
        "whisper",
        "humming",
        "screaming",
        "shouting",
        "door",
        "slam",
        "slamming",
        "knock",
        "knocking",
        "phone",
        "ringing",
        "beep",
        "beeping",
        "click",
        "clicking",
        "tap",
        "tapping",
        "subtitle",
        "subtitles",
        "subscribe",
        "watching",
        "crowd",
        "talking",
        "chatter",
        "murmur",
        "murmuring",
        "water",
        "running",
        "rain",
        "thunder",
        "traffic",
        "sounds",
        "sound",
        "effects",
        "effect",
        "ambient",
    }
)

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


def compression_ratio(text: str) -> float:
    """Whisper-style ratio; high values indicate repetitive hallucination loops."""
    data = text.encode("utf-8")
    if not data:
        return 0.0
    compressed = zlib.compress(data)
    return len(data) / len(compressed)


def _normalize_token(word: str) -> str:
    return re.sub(r"[^\w']+", "", word.lower())


def _collapse_word_loops(words: list[str], min_repeats: int = 3) -> list[str]:
    if len(words) < min_repeats * 2:
        return words
    max_phrase = min(12, len(words) // min_repeats)
    for size in range(max_phrase, 1, -1):
        out: list[str] = []
        i = 0
        changed = False
        while i < len(words):
            if i + size * min_repeats <= len(words):
                phrase = [_normalize_token(w) for w in words[i : i + size]]
                repeats = 1
                j = i + size
                while j + size <= len(words):
                    next_phrase = [_normalize_token(w) for w in words[j : j + size]]
                    if next_phrase != phrase:
                        break
                    repeats += 1
                    j += size
                if repeats >= min_repeats:
                    out.extend(words[i : i + size])
                    i = j
                    changed = True
                    continue
            out.append(words[i])
            i += 1
        if changed:
            return _collapse_word_loops(out, min_repeats)
    return words


def _normalize_clause(clause: str) -> str:
    return re.sub(r"[^\w']+", " ", clause.lower()).strip()


def _collapse_clause_loops(text: str, min_repeats: int = 1) -> str:
    parts = [part.strip() for part in re.split(r",\s*", text) if part.strip()]
    if len(parts) < min_repeats + 1:
        return text
    out: list[str] = []
    i = 0
    while i < len(parts):
        clause = parts[i]
        norm = _normalize_clause(clause)
        repeats = 1
        j = i + 1
        while j < len(parts) and _normalize_clause(parts[j]) == norm:
            repeats += 1
            j += 1
        if repeats >= min_repeats + 1:
            out.append(clause)
            i = j
        else:
            out.append(clause)
            i += 1
    return ", ".join(out)


def _collapse_repetitions(text: str) -> str:
    """Collapse Whisper stutter loops like 'and it's a, and it's a, ...'."""
    collapsed = " ".join(_collapse_word_loops(text.split(), min_repeats=2))
    collapsed = _collapse_clause_loops(collapsed)
    collapsed = " ".join(_collapse_word_loops(collapsed.split()))
    clause_re = re.compile(
        r"(\b[\w']+(?:[\s,]+[\w']+){0,7}[\.,]?\s*)(?:\1){2,}",
        re.IGNORECASE,
    )
    for _ in range(4):
        next_text = clause_re.sub(r"\1", collapsed)
        if next_text == collapsed:
            break
        collapsed = next_text
    return re.sub(r"\s+", " ", collapsed).strip()


def append_transcript(committed: str, new: str) -> str:
    """Append cleaned ASR text, dropping overlap with the committed tail."""
    new = clean_transcript(new)
    if not new:
        return committed
    if not committed:
        return new
    if new in committed:
        return committed
    max_overlap = min(len(committed), len(new))
    for overlap in range(max_overlap, 0, -1):
        if committed[-overlap:] == new[:overlap]:
            suffix = new[overlap:].lstrip()
            if not suffix:
                return committed
            sep = "" if committed.endswith((" ", "\n")) or suffix[0] in ",.!?;:" else " "
            return committed + sep + suffix
    sep = "" if committed.endswith((" ", "\n")) else " "
    return committed + sep + new


def clean_transcript(text: str) -> str:
    if not text:
        return ""
    text = _TAG_RE.sub("", text)
    text = _strip_bracketed_noise(text)
    text = re.sub(r"[♪♫]+", " ", text)
    text = _strip_filler_words(text)
    text = re.sub(r"\s+", " ", text).strip()
    text = _collapse_repetitions(text)
    if _phrase_is_noise_only(text):
        return ""
    return text
