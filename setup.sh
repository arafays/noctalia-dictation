#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
REQUIREMENTS="$SCRIPT_DIR/requirements.txt"

echo "dictation-setup: SCRIPT_DIR=$SCRIPT_DIR" >&2
echo "dictation-setup: VENV_DIR=$VENV_DIR" >&2

if ! command -v python3 >/dev/null 2>&1 && ! command -v uv >/dev/null 2>&1; then
  echo "dictation-setup: error: neither python3 nor uv found on PATH" >&2
  echo "dictation-setup: fix: install Python 3.10+ (e.g. pacman -S python)" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)')
  PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
  if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]; }; then
    echo "dictation-setup: error: Python 3.10+ required (found ${PY_MAJOR}.${PY_MINOR})" >&2
    echo "dictation-setup: fix: upgrade python3, then re-run: cd $SCRIPT_DIR && ./setup.sh" >&2
    exit 1
  fi
fi

if [ ! -f "$REQUIREMENTS" ]; then
  echo "dictation-setup: error: requirements.txt not found at $REQUIREMENTS" >&2
  exit 1
fi

if [ ! -f "$VENV_DIR/bin/python" ]; then
  echo "dictation-setup: creating venv..." >&2
  if command -v uv >/dev/null 2>&1; then
    uv venv "$VENV_DIR" >&2
  else
    python3 -m venv "$VENV_DIR" >&2
  fi
fi

echo "dictation-setup: installing/updating dependencies..." >&2
if command -v uv >/dev/null 2>&1; then
  if ! uv pip install -r "$REQUIREMENTS" --python "$VENV_DIR/bin/python" >&2; then
    echo "dictation-setup: error: failed to install Python packages" >&2
    echo "dictation-setup: fix: check network, then re-run: cd $SCRIPT_DIR && ./setup.sh" >&2
    exit 1
  fi
elif [ -f "$VENV_DIR/bin/pip" ]; then
  if ! "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS" >&2; then
    echo "dictation-setup: error: pip install failed" >&2
    echo "dictation-setup: fix: check network, then re-run: cd $SCRIPT_DIR && ./setup.sh" >&2
    exit 1
  fi
else
  echo "dictation-setup: error: no pip available in venv" >&2
  echo "dictation-setup: fix: remove .venv and re-run ./setup.sh" >&2
  exit 1
fi

if ! "$VENV_DIR/bin/python" -c 'import sounddevice, numpy' 2>/dev/null; then
  echo "dictation-setup: error: sounddevice or numpy failed to import" >&2
  echo "dictation-setup: fix: install PortAudio (pacman -S portaudio), then re-run ./setup.sh" >&2
  exit 1
fi

if ! "$VENV_DIR/bin/python" -c 'import sherpa_onnx' 2>/dev/null \
    && ! "$VENV_DIR/bin/python" -c 'import faster_whisper' 2>/dev/null; then
  echo "dictation-setup: error: no STT engine installed (need sherpa-onnx and/or faster-whisper)" >&2
  echo "dictation-setup: fix: re-run ./setup.sh and check pip output" >&2
  exit 1
fi

echo "dictation-setup: done" >&2
echo "venv-ready"
