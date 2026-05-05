# Dictation Plugin — Development Guide

A Noctalia plugin providing local voice dictation via [faster-whisper](https://github.com/SYSTRAN/faster-whisper). (v0.0.3)

## Architecture

```
BarWidget.qml  ←→  Main.qml (shared state, IPC)  ←→  Python backend (signal files)
   ↑                      ↑                              ↑
   |                IpcHandler                      `qs ipc` CLI
   |              plugin:dictation                  sends status JSON
Panel.qml      Settings.qml                        back to IpcHandler
```

The Python backend runs as a long-lived server process. Communication flows:

- **QML → Python**: atomic file rename writes into `$XDG_RUNTIME_DIR/noctalia-dictation-signal`
- **Python → QML**: `qs ipc -c noctalia-shell call plugin:dictation setStatus '<json>'`
- **Backend PID file**: `$XDG_RUNTIME_DIR/noctalia-dictation-pid` (holds PID, flock'd for singleton enforcement)

## Python backend

- `dictation_backend.py` — standalone CLI with subcommands: `server`, `start`, `stop`, `exit`, `update_settings`, `status`
- Dependencies (in `requirements.txt`): `faster-whisper`, `sounddevice`, `numpy`
- Uses `wl-copy` + `wtype` (fallback: `ydotool`) to type transcribed text into the focused window
- Settings read from `~/.config/noctalia/plugins/dictation/settings.json`
- Venv at `<pluginDir>/.venv/` — created by `executable_setup.sh`

## Plugin startup flow

1. `Component.onCompleted` in Main.qml kills any orphaned backend, then waits 2s
2. If venv missing → runs `executable_setup.sh` → outputs `venv-ready` on stdout when done
3. Launches backend via `venvPython backendScript server`
4. Backend loads the Whisper model, sends `{"state": "idle", "message": "ready"}` via IPC
5. Plugin is now ready for recording

## Settings

Defaults live in `manifest.json` → `metadata.defaultSettings`. Runtime values in `Settings.qml` use edit-copy properties (e.g. `editModel`) and persist via `saveSettings()`.

Settings that require a backend restart to take effect: `model`, `device`, `computeType`.
Settings applied on `update_settings` signal: `language`, `vadEnabled`, `recordingTimeout`.

## Conventions

- QML logging uses `Logger.i/w/e/d("Dictation", ...)` — never `console.log`
- Python logging goes to stderr with a `dictation-setup:` / `Dictation:` prefix convention
- `i18n/en.json` holds all user-facing strings accessed via `pluginApi?.tr(key)`

## Gotchas

- The backend will **fail to start if another instance is running** (flock on PID file). Kill stale backends with `python dictation_backend.py exit`.
- Recording is captured at **16 kHz mono** — `MIN_RECORDING_SEC = 0.5` rejects too-short clips.
- `faster-whisper` model is downloaded on first use (cached by the library). Expect a delay on the first cold start.
- VAD uses RMS-based silence detection (0.01 threshold, 1.5s window). False triggers are expected in noisy environments.
- If `computeType=float16` and device is CPU, it auto-falls back to `int8`.
- The transcription typing uses Ctrl+V paste — make sure your compositor/mappings don't intercept this.
