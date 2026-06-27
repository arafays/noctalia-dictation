"""Model pack definitions and path resolution for sherpa-onnx."""

from __future__ import annotations

from pathlib import Path

VAD_MODEL_NAME = "silero_vad.int8.onnx"

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


def profile_for_language(language: str) -> str:
    if language and language not in ("auto", "en"):
        return "multilingual"
    return "english"


def vad_model_path(models_dir: Path) -> Path:
    return models_dir / VAD_MODEL_NAME


def models_missing_reason(models_dir: Path, profile: str) -> str | None:
    if profile not in MODEL_PACKS:
        return f"Unknown sherpa profile '{profile}'"

    missing: list[str] = []
    if not vad_model_path(models_dir).is_file():
        missing.append(VAD_MODEL_NAME)

    pack = MODEL_PACKS[profile]
    if not (models_dir / pack["dir"]).is_dir():
        missing.append(pack["dir"])
    if not (models_dir / pack["second_dir"]).is_dir():
        missing.append(pack["second_dir"])

    if missing:
        fix = f"cd {models_dir.parent} && ./download_models.sh {profile}"
        return f"Missing model files ({', '.join(missing)}). Run: {fix}"

    try:
        resolve_model_paths(models_dir, profile)
    except FileNotFoundError as exc:
        fix = f"cd {models_dir.parent} && ./download_models.sh {profile}"
        return f"{exc}. Re-run: {fix}"
    return None


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
