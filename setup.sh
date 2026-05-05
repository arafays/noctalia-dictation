#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
REQUIREMENTS="$SCRIPT_DIR/requirements.txt"

echo "dictation-setup: SCRIPT_DIR=$SCRIPT_DIR" >&2
echo "dictation-setup: VENV_DIR=$VENV_DIR" >&2

if [ -f "$VENV_DIR/bin/python" ]; then
  echo "dictation-setup: venv already exists, skipping" >&2
  echo "venv-ready"
  exit 0
fi

echo "dictation-setup: creating venv..." >&2

if command -v uv >/dev/null 2>&1; then
  echo "dictation-setup: using uv to create venv" >&2
  uv venv "$VENV_DIR" >&2
elif command -v python3 >/dev/null 2>&1; then
  echo "dictation-setup: using python3 -m venv" >&2
  python3 -m venv "$VENV_DIR" >&2
else
  echo "dictation-setup: error: neither uv nor python3 found" >&2
  exit 1
fi

echo "dictation-setup: installing dependencies..." >&2

if command -v uv >/dev/null 2>&1; then
  echo "dictation-setup: using uv pip install" >&2
  uv pip install -r "$REQUIREMENTS" --python "$VENV_DIR/bin/python" >&2
elif [ -f "$VENV_DIR/bin/pip" ]; then
  echo "dictation-setup: using venv pip install" >&2
  "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS" >&2
else
  echo "dictation-setup: error: no pip available in venv" >&2
  exit 1
fi

echo "dictation-setup: done" >&2
echo "venv-ready"
