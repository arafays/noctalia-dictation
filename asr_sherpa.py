"""sherpa-onnx two-pass streaming ASR (Zipformer + Whisper/SenseVoice)."""

from __future__ import annotations

import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

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
CHUNK_SEC = 0.1

VAD_MODEL_NAME = "silero_vad.int8.onnx"
VAD_THRESHOLD = 0.4
VAD_MIN_SPEECH_SEC = 0.2
VAD_MIN_SILENCE_SEC = 0.3
VAD_HANGOVER_SEC = 0.35
MIN_SEGMENT_SPEECH_SEC = 0.15

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


def vad_model_path(models_dir: Path) -> Path:
    return models_dir / VAD_MODEL_NAME


def models_ready(models_dir: Path, profile: str) -> bool:
    try:
        resolve_model_paths(models_dir, profile)
        return vad_model_path(models_dir).is_file()
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

    vad = vad_model_path(models_dir)
    if not vad.is_file():
        raise FileNotFoundError(f"Missing VAD model: {vad}")

    return {"first": first, "second": second, "second_type": pack["second_type"], "vad": vad}  # type: ignore[return-value]


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


def _create_vad(vad_path: Path) -> tuple[Any, int]:
    config = sherpa_onnx.VadModelConfig()
    config.silero_vad.model = str(vad_path)
    config.silero_vad.threshold = VAD_THRESHOLD
    config.silero_vad.min_speech_duration = VAD_MIN_SPEECH_SEC
    config.silero_vad.min_silence_duration = VAD_MIN_SILENCE_SEC
    config.sample_rate = SAMPLE_RATE
    if not config.validate():
        raise ValueError("Invalid Silero VAD config")
    window_size = config.silero_vad.window_size
    return sherpa_onnx.VoiceActivityDetector(config, buffer_size_in_seconds=100), window_size


class SpeechGate:
    """Silero VAD pre-gate with hangover to suppress noise-only decode."""

    def __init__(self, vad: Any, window_size: int, hangover_sec: float = VAD_HANGOVER_SEC) -> None:
        self.vad = vad
        self.window_size = window_size
        self.hangover_sec = hangover_sec
        self._pending = np.array([], dtype=np.float32)
        self._gate_open = False
        self._hangover_remaining = 0.0
        self._segment_speech_samples = 0
        self._session_speech_samples = 0

    def reset_segment(self) -> None:
        self._segment_speech_samples = 0

    @property
    def session_has_speech(self) -> bool:
        return self._session_speech_samples > int(MIN_SEGMENT_SPEECH_SEC * SAMPLE_RATE)

    def accept_chunk(self, samples: np.ndarray) -> bool:
        """Feed audio to VAD; return True when ASR should process this chunk."""
        flat = samples.reshape(-1).astype(np.float32, copy=False)
        self._pending = np.concatenate([self._pending, flat])
        while len(self._pending) >= self.window_size:
            self.vad.accept_waveform(self._pending[: self.window_size])
            self._pending = self._pending[self.window_size :]

        speech_now = self.vad.is_speech_detected()
        chunk_samples = len(flat)
        if speech_now:
            self._hangover_remaining = self.hangover_sec
            self._gate_open = True
            self._segment_speech_samples += chunk_samples
            self._session_speech_samples += chunk_samples
        elif self._hangover_remaining > 0:
            self._hangover_remaining = max(0.0, self._hangover_remaining - chunk_samples / SAMPLE_RATE)
            self._gate_open = True
        else:
            self._gate_open = False

        return self._gate_open

    def segment_has_speech(self) -> bool:
        return self._segment_speech_samples >= int(MIN_SEGMENT_SPEECH_SEC * SAMPLE_RATE)


@dataclass
class SherpaEngine:
    models_dir: Path
    profile: str
    provider: str = "cpu"
    language: str = "auto"
    num_threads: int = 2
    first: Any = field(default=None, repr=False)
    second: Any = field(default=None, repr=False)
    vad: Any = field(default=None, repr=False)
    vad_window_size: int = 512

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
        self.vad, self.vad_window_size = _create_vad(paths["vad"])

    def describe(self) -> str:
        return f"sherpa-onnx two-pass + VAD ({self.profile}, {self.provider})"


def _run_second_pass(recognizer: Any, samples: np.ndarray) -> str:
    stream = recognizer.create_stream()
    stream.accept_waveform(SAMPLE_RATE, samples)
    recognizer.decode_stream(stream)
    return clean_transcript((stream.result.text or "").strip())


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
        self.gate = SpeechGate(engine.vad, engine.vad_window_size)
        self.sample_buffers: list[np.ndarray] = []
        self.committed_text = ""
        self.current_partial = ""

    def _second_pass(self, samples: np.ndarray) -> str:
        return _run_second_pass(self.engine.second, samples)

    def _commit_refined(self, refined: str, fallback_partial: str = "") -> None:
        text = clean_transcript(refined) or clean_transcript(fallback_partial)
        if not text:
            return
        if not self.gate.segment_has_speech():
            return
        to_type = _with_space_prefix(text, self.committed_text)
        if to_type:
            type_committed(to_type)
            self.committed_text += to_type

    def accept_chunk(self, samples: np.ndarray) -> None:
        if not self.gate.accept_chunk(samples):
            if self.current_partial:
                self.current_partial = ""
                send_live(self.committed_text, "")
            return

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
            self.gate.reset_segment()
            return

        samples_all = np.concatenate(self.sample_buffers) if self.sample_buffers else samples
        if len(samples_all) <= SEGMENT_TAIL_SAMPLES:
            self.engine.first.reset(self.stream)
            self.sample_buffers = []
            self.current_partial = ""
            self.gate.reset_segment()
            return

        self.sample_buffers = [samples_all[-SEGMENT_TAIL_SAMPLES:]]
        segment_audio = samples_all[:-SEGMENT_TAIL_SAMPLES]
        refined = self._second_pass(segment_audio) if len(segment_audio) > 0 else partial
        self._commit_refined(refined, partial)

        self.current_partial = ""
        send_live(self.committed_text, "")
        self.engine.first.reset(self.stream)
        self.gate.reset_segment()

    def finish(self) -> str:
        if self.sample_buffers:
            tail = np.concatenate(self.sample_buffers)
            if len(tail) > SEGMENT_TAIL_SAMPLES:
                refined = self._second_pass(tail)
                self._commit_refined(refined, self.current_partial)
            elif self.current_partial:
                self._commit_refined(self.current_partial)
        return self.committed_text.strip()


def record_session(
    engine: SherpaEngine,
    stop_event: threading.Event,
    timeout: float,
) -> None:
    session = SherpaSession(engine)
    chunk_samples = int(CHUNK_SEC * SAMPLE_RATE)
    recording_start = None

    try:
        with sd.InputStream(channels=1, dtype="float32", samplerate=SAMPLE_RATE) as mic:
            recording_start = time.monotonic()
            send_status("recording", "", live_transcript="", partial_transcript="", engine=engine.describe())
            while not stop_event.is_set():
                if timeout > 0 and time.monotonic() - recording_start >= timeout:
                    break
                samples, _ = mic.read(chunk_samples)
                session.accept_chunk(samples.reshape(-1))

        duration = time.monotonic() - (recording_start or 0)
        if duration < MIN_RECORDING_SEC:
            send_status("idle", "cancelled", live_transcript="", partial_transcript="")
            return

        send_status(
            "transcribing",
            "finishing",
            live_transcript=session.committed_text,
            partial_transcript=session.current_partial,
            engine=engine.describe(),
        )
        full_text = session.finish()
        if full_text:
            copy_to_clipboard(full_text)
            send_status("idle", "copied", full_text, live_transcript="", partial_transcript="", engine=engine.describe())
        elif session.gate.session_has_speech:
            send_status("idle", "silence", live_transcript="", partial_transcript="", engine=engine.describe())
        else:
            send_status("idle", "no_speech", live_transcript="", partial_transcript="", engine=engine.describe())
    except Exception as exc:
        send_status("error", f"{exc!r}", live_transcript="", partial_transcript="")
