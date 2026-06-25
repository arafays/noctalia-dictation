#!/usr/bin/env bash
# Download sherpa-onnx model packs for offline two-pass dictation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
BASE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models"

profile="${1:-all}"

if ! command -v curl >/dev/null 2>&1; then
  echo "dictation-models: error: curl not found" >&2
  echo "dictation-models: fix: install curl (e.g. pacman -S curl), then re-run this script" >&2
  exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "dictation-models: error: tar not found" >&2
  echo "dictation-models: fix: install tar, then re-run this script" >&2
  exit 1
fi

download_vad() {
  local name="silero_vad.int8.onnx"
  if [[ -f "${MODELS_DIR}/${name}" ]]; then
    echo "dictation-models: ${name} already present"
    return 0
  fi
  echo "dictation-models: downloading ${name} (~200 KB)..."
  mkdir -p "${MODELS_DIR}"
  if ! curl -fL --retry 3 --retry-delay 2 -o "${MODELS_DIR}/${name}" "${BASE_URL}/${name}"; then
    echo "dictation-models: error: failed to download ${name}" >&2
    echo "dictation-models: fix: check network, then: cd ${SCRIPT_DIR} && ./download_models.sh ${profile}" >&2
    exit 1
  fi
  echo "dictation-models: installed ${name}"
}

download_pack() {
  local archive="$1"
  local dir="$2"
  if [[ -d "${MODELS_DIR}/${dir}" ]]; then
    echo "dictation-models: ${dir} already present"
    return 0
  fi
  echo "dictation-models: downloading ${archive} (this may take a few minutes)..."
  mkdir -p "${MODELS_DIR}"
  tmp="${MODELS_DIR}/${archive}"
  if ! curl -fL --retry 3 --retry-delay 2 -o "${tmp}" "${BASE_URL}/${archive}"; then
    echo "dictation-models: error: failed to download ${archive}" >&2
    echo "dictation-models: fix: check network/disk space, then: cd ${SCRIPT_DIR} && ./download_models.sh ${profile}" >&2
    rm -f "${tmp}"
    exit 1
  fi
  if ! tar -xjf "${tmp}" -C "${MODELS_DIR}"; then
    echo "dictation-models: error: failed to extract ${archive}" >&2
    echo "dictation-models: fix: remove partial files in ${MODELS_DIR} and re-run" >&2
    rm -f "${tmp}"
    exit 1
  fi
  rm -f "${tmp}"
  echo "dictation-models: installed ${dir}"
}

install_english() {
  download_pack "sherpa-onnx-streaming-zipformer-en-20M-2023-02-17.tar.bz2" \
    "sherpa-onnx-streaming-zipformer-en-20M-2023-02-17"
  download_pack "sherpa-onnx-whisper-tiny.en.tar.bz2" \
    "sherpa-onnx-whisper-tiny.en"
}

install_multilingual() {
  download_pack "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2" \
    "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
  download_pack "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2" \
    "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
}

case "${profile}" in
  english|en)
    download_vad
    install_english
    ;;
  multilingual|multi)
    download_vad
    install_multilingual
    ;;
  all)
    download_vad
    install_english
    install_multilingual
    ;;
  *)
    echo "Usage: $0 [english|multilingual|all]" >&2
    echo "  english       ~150 MB, Zipformer + Whisper + VAD (recommended)" >&2
    echo "  multilingual  ~700 MB, bilingual Zipformer + SenseVoice + VAD" >&2
    echo "  all           both profiles + VAD (~850 MB)" >&2
    exit 1
    ;;
esac

echo "models-ready"
