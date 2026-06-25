#!/usr/bin/env bash
# Download sherpa-onnx model packs for offline two-pass dictation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
BASE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models"

profile="${1:-all}"

download_pack() {
  local archive="$1"
  local dir="$2"
  if [[ -d "${MODELS_DIR}/${dir}" ]]; then
    echo "dictation-models: ${dir} already present"
    return 0
  fi
  echo "dictation-models: downloading ${archive}..."
  mkdir -p "${MODELS_DIR}"
  tmp="${MODELS_DIR}/${archive}"
  curl -fL --retry 3 --retry-delay 2 -o "${tmp}" "${BASE_URL}/${archive}"
  tar -xjf "${tmp}" -C "${MODELS_DIR}"
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
    install_english
    ;;
  multilingual|multi)
    install_multilingual
    ;;
  all)
    install_english
    install_multilingual
    ;;
  *)
    echo "Usage: $0 [english|multilingual|all]" >&2
    exit 1
    ;;
esac

echo "models-ready"
