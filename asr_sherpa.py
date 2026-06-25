"""sherpa-onnx two-pass streaming ASR (Zipformer + Whisper/SenseVoice)."""

from __future__ import annotations

import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import numpy as np
import sounddevice as sd

from asr_common import clean_transcript, copy_to_clipboard, send_live, send_status, type_committed

try:
    import sherpa_onnx
except ImportError as _exc:
    sherpa_onnx = None  # type: ignore[assignment]
    _IMPORT_ERROR = _exc
else:
    _IMPORT_ERROR = None

SAMPLE_RATE = 16000
SEGMENT_TAIL_SAMPLES = 8000
MIN_RECORDING_SEC = 0.5

MODEL_PACKS: dict[str, dict[str, str]] = {
    "english": {
        "archive": "sherpa-onnx-streaming-zipformer-en-20M-2023-02-17.tar.bz2",
        "dir": "sherpa-onnx-streaming-zipformer-en-20M-2023-02-17",
        "second_archive": "sherpa-onnx-whisper-tiny.en.tar.bz2",
        "second_dir": "sherpa-onnx-whisper-tiny.en",
        "second_type": "whisper",
    },
    "multilingual": {
        "archive": "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2",
        "dir": "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20",
        "second_archive": "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2",
        "second_dir": "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17",
        "second_type": "sensevoice",
    },
}


def available() -> bool:
    return sherpa_onnx is not None


def has_cuda() -> bool:
    try:
        return subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, timeout=2, check=False,
        ).returncode == 0
    except Exception:
        return False


def import_error() -> Exception | None:
    return _IMPORT_ERROR


def profile_for_language(language: str) -> str:
    if language and language not in ("auto", "en"):
        return "multilingual"
    return "english"


def models_ready(models_dir: Path, profile: str) -> bool:
    try:
        resolve_model_paths(models_dir, profile)
        return True
    except FileNotFoundError:
        return False


def resolve_model_paths(models_dir: Path, profile: str) -> dict[str, Path]:
    pack = MODEL_PACKS[profile]
    first_dir = models_dir / pack["dir"]
    if not first_dir.is_dir():
        raise FileNotFoundError(f"Missing first-pass model dir: {first_dir}")

    first = {
        "tokens": first_dir / "tokens.txt",
        "encoder": _pick_first(first_dir, "encoder"),
        "decoder": _pick_first(first_dir, "decoder"),
        "joiner": _pick_first(first_dir, "joiner"),
    }
    for key, path in first.items():
        if not path.is_file():
            raise FileNotFoundError(f"Missing {key}: {path}")

    second_dir = models_dir / pack["second_dir"]
    if not second_dir.is_dir():
        raise FileNotFoundError(f"Missing second-pass model dir: {second_dir}")

    second: dict[str, Path] = {"tokens": second_dir / "tokens.txt"}
    if pack["second_type"] == "whisper":
        second["encoder"] = _pick_whisper(second_dir, "encoder")
        second["decoder"] = _pick_whisper(second_dir, "decoder")
        if not second["tokens"].is_file():
            second["tokens"] = second_dir / "tiny.en-tokens.txt"
    else:
        second["model"] = _pick_sensevoice(second_dir)

    for path in second.values():
        if not path.is_file():
            raise FileNotFoundError(f"Missing second-pass file: {path}")

    return {"first": first, "second": second, "second_type": pack["second_type"]}  # type: ignore[return-value]


def _pick_first(model_dir: Path, role: str) -> Path:
    for name in sorted(model_dir.iterdir()):
        if name.suffix == ".onnx" and role in name.name.lower():
            if role == "decoder" and "int8" in name.name:
                continue
            return name
    raise FileNotFoundError(f"No {role} onnx in {model_dir}")


def _pick_whisper(model_dir: Path, role: str) -> Path:
    for name in sorted(model_dir.iterdir()):
        if name.suffix == ".onnx" and role in name.name.lower():
            return name
    raise FileNotFoundError(f"No whisper {role} in {model_dir}")


def _pick_sensevoice(model_dir: Path) -> Path:
    for name in sorted(model_dir.iterdir()):
        if name.suffix == ".onnx" and "model" in name.name.lower():
            return name
    raise FileNotFoundError(f"No sensevoice model in {model_dir}")


@dataclass
class SherpaEngine:
    models_dir: Path
    profile: str
    provider: str = "cpu"
    language: str = "auto"
    num_threads: int = 2
    first: Any = field(default=None, repr=False)
    second: Any = field(default=None, repr=False)

    def load(self) -> None:
        if sherpa_onnx is None:
            raise RuntimeError(f"sherpa-onnx not installed: {_IMPORT_ERROR}")
        paths = resolve_model_paths(self.models_dir, self.profile)
        first = paths["first"]
        self.first = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=str(first["tokens"]),
            encoder=str(first["encoder"]),
            decoder=str(first["decoder"]),
            joiner=str(first["joiner"]),
            num_threads=self.num_threads,
            sample_rate=SAMPLE_RATE,
            feature_dim=80,
            decoding_method="greedy_search",
            max_active_paths=4,
            provider=self.provider,
            enable_endpoint_detection=True,
            rule1_min_trailing_silence=2.4,
            rule2_min_trailing_silence=1.2,
            rule3_min_utterance_length=20,
        )
        second_paths = paths["second"]
        if paths["second_type"] == "whisper":
            lang = "" if self.language in ("auto", "") else self.language
            self.second = sherpa_onnx.OfflineRecognizer.from_whisper(
                encoder=str(second_paths["encoder"]),
                decoder=str(second_paths["decoder"]),
                tokens=str(second_paths["tokens"]),
                num_threads=self.num_threads,
                decoding_method="greedy_search",
                language=lang,
                task="transcribe",
                tail_paddings=-1,
            )
        else:
            self.second = sherpa_onnx.OfflineRecognizer.from_sense_voice(
                model=str(second_paths["model"]),
                tokens=str(second_paths["tokens"]),
                num_threads=self.num_threads,
                sample_rate=SAMPLE_RATE,
                feature_dim=80,
                use_itn=True,
                decoding_method="greedy_search",
            )

    def describe(self) -> str:
        return f"sherpa-onnx two-pass ({self.profile}, {self.provider})"


def _run_second_pass(recognizer: Any, samples: np.ndarray) -> str:
    stream = recognizer.create_stream()
    stream.accept_waveform(SAMPLE_RATE, samples)
    recognizer.decode_stream(stream)
    return (stream.result.text or "").strip()


def _with_space_prefix(text: str, committed: str) -> str:
    if not text:
        return ""
    if committed and not committed.endswith((" ", "\n")):
        return " " + text
    return text


class SherpaSession:
    def __init__(self, engine: SherpaEngine) -> None:
        self.engine = engine
        self.stream = engine.first.create_stream()
        self.sample_buffers: list[np.ndarray] = []
        self.committed_text = ""
        self.current_partial = ""

    def _second_pass(self, samples: np.ndarray) -> str:
        return _run_second_pass(self.engine.second, samples)

    def accept_chunk(self, samples: np.ndarray) -> None:
        self.stream.accept_waveform(SAMPLE_RATE, samples)
        self.sample_buffers.append(samples.copy())
        while self.engine.first.is_ready(self.stream):
            self.engine.first.decode_stream(self.stream)

        partial = clean_transcript((self.engine.first.get_result(self.stream) or "").strip())
        self.current_partial = partial
        send_live(self.committed_text, partial)

        if not self.engine.first.is_endpoint(self.stream):
            return

        if not partial and not self.sample_buffers:
            self.engine.first.reset(self.stream)
            return

        samples_all = np.concatenate(self.sample_buffers) if self.sample_buffers else samples
        if len(samples_all) <= SEGMENT_TAIL_SAMPLES:
            self.engine.first.reset(self.stream)
            self.sample_buffers = []
            self.current_partial = ""
            return

        self.sample_buffers = [samples_all[-SEGMENT_TAIL_SAMPLES:]]
        segment_audio = samples_all[:-SEGMENT_TAIL_SAMPLES]
        refined = self._second_pass(segment_audio) if len(segment_audio) > 0 else partial
        if not refined:
            refined = partial

        to_type = _with_space_prefix(refined, self.committed_text)
        if to_type:
            type_committed(to_type)
            self.committed_text += to_type

        self.current_partial = ""
        send_live(self.committed_text, "")
        self.engine.first.reset(self.stream)

    def finish(self) -> str:
        if self.sample_buffers:
            tail = np.concatenate(self.sample_buffers)
            if len(tail) > SEGMENT_TAIL_SAMPLES:
                refined = self._second_pass(tail)
                to_type = _with_space_prefix(refined, self.committed_text)
                if to_type:
                    type_committed(to_type)
                    self.committed_text += to_type
            elif self.current_partial:
                to_type = _with_space_prefix(self.current_partial, self.committed_text)
                if to_type:
                    type_committed(to_type)
                    self.committed_text += to_type
        return self.committed_text.strip()


def record_session(
    engine: SherpaEngine,
    stop_event: threading.Event,
    timeout: float,
) -> None:
    session = SherpaSession(engine)
    chunk_samples = int(0.1 * SAMPLE_RATE)
    recording_start = None

    try:
        with sd.InputStream(channels=1, dtype="float32", samplerate=SAMPLE_RATE) as mic:
            recording_start = __import__("time").monotonic()
            send_status("recording", "", live_transcript="", partial_transcript="", engine=engine.describe())
            while not stop_event.is_set():
                if timeout > 0 and __import__("time").monotonic() - recording_start >= timeout:
                    break
                samples, _ = mic.read(chunk_samples)
                session.accept_chunk(samples.reshape(-1))

        duration = __import__("time").monotonic() - (recording_start or 0)
        if duration < MIN_RECORDING_SEC:
            send_status("idle", "cancelled", live_transcript="", partial_transcript="")
            return

        full_text = session.finish()
        if full_text:
            copy_to_clipboard(full_text)
            send_status("idle", "copied", full_text, live_transcript="", partial_transcript="", engine=engine.describe())
        else:
            send_status("idle", "silence", live_transcript="", partial_transcript="", engine=engine.describe())
    except Exception as exc:
        send_status("error", f"{exc!r}", live_transcript="", partial_transcript="")
