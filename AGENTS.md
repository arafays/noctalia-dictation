# Dictation Plugin — Development Guide (v0.4.5)

## Layout

```
manifest.json, i18n/          ← Noctalia plugin metadata (no Python install)
ui/                           ← QML frontend (BarWidget, Main, Settings, …)
backend/                      ← Python backend (requires ./setup.sh venv)
  server.py                   ← process entry + signal IPC
  config.py, paths.py         ← settings + plugin root paths
  ipc/                        ← qs IPC status to QML
  output/                     ← wtype + clipboard injection
  transcript/                 ← ASR output cleaning
  engines/
    registry.py               ← register engines here
    sherpa/                   ← default (two-pass Zipformer + Whisper/SenseVoice)
    faster_whisper/           ← CTranslate2 Whisper with pause segmentation
dictation_backend.py          ← thin CLI shim (Main.qml invokes this)
setup.sh, download_models.sh  ← install scripts (venv + ONNX models)
models/, .venv/               ← local artifacts (gitignored)
```

## Architecture

```
ui/Main.qml (IPC)
        ↕ dictation_backend.py → backend/server.py
        ↕ backend/engines/registry.py
        ├─ sherpa/  ← two-pass (Zipformer + Whisper/SenseVoice) + Silero VAD
        │    ├─ engine.py, session.py, vad.py, packs.py
        └─ faster_whisper/  ← CTranslate2 Whisper, RMS silence gate, pause re-decode
           ├─ engine.py, session.py
           └─ transcript/ + output/ for cleaning and typing
```

## Adding a new ASR engine

1. Create `backend/engines/<name>/` with:
   - `ENGINE_ID`, `available()`, `import_error()`, `create_engine()`, `record_session()`, `diagnose_checks()`
2. Register in `backend/engines/registry.py` (`ENGINES` dict)
3. Expose in `ui/Settings.qml` if users should pick it in the UI

## Settings UI (Noctalia entry points)

| Entry point | File | Where it opens | Contents |
|-------------|------|----------------|----------|
| `settings` | `ui/Settings.qml` | Settings → Plugins, bar widget gear (Settings → Bar), context menu **Plugin settings** | Speech engine, model profiles, language, behavior, hotkeys, install checks, debug |
| `barWidgetSettings` | `ui/BarWidgetSettings.qml` | Context menu **Bar quick settings** only (not the bar-layout gear — Noctalia opens `settings` for plugin widgets) | Overlay, auto-type, VAD toggles |

Bar context menu also exposes one-click toggles for overlay, auto-type, and VAD. Both settings dialogs use `pluginApi.pluginSettings` (global per plugin, not per bar instance).

## STT engine: sherpa-onnx two-pass + Silero VAD

Based on [sherpa-onnx two-pass microphone example](https://github.com/k2-fsa/sherpa-onnx/blob/master/python-api-examples/two-pass-speech-recognition-from-microphone.py):

1. **Silero VAD** — pre-ASR speech gating; skips decode/UI on non-speech; hangover preserves word endings
2. **Streaming Zipformer** — partial results every ~100ms → `partialTranscript` in UI
3. **Endpoint detection** — phrase boundary (not session stop) triggers second pass
4. **Offline Whisper/SenseVoice** — refined segment → `clean_transcript()` → `wtype` + `liveTranscript`

Models in `<pluginDir>/models/`, downloaded via `download_models.sh`.

| Profile | 1st pass | 2nd pass | VAD |
|---------|----------|----------|-----|
| english | streaming-zipformer-en-20M | whisper-tiny.en (ONNX via sherpa) | silero_vad.int8.onnx |
| multilingual | streaming-zipformer-bilingual-zh-en | sense-voice int8 | silero_vad.int8.onnx |

VAD defaults: threshold 0.4, min speech 0.2s, min silence 0.3s, hangover 0.35s.

The second-pass Whisper models are **sherpa-onnx ONNX exports**, not the `faster-whisper` Python library.

## Dependencies

| Layer | Requires install? | What |
|-------|-------------------|------|
| **Noctalia / QML** | No (ships with plugin) | `ui/*.qml`, `manifest.json`, `i18n/` |
| **System** | Yes | Python 3.10+, `wtype`, `wl-copy`, PortAudio, `curl`, `tar` |
| **Python venv** | Yes (`./setup.sh`) | `sherpa-onnx`, `faster-whisper`, `sounddevice`, `numpy` |
| **Models** | Yes (`./download_models.sh`) | ONNX files in `models/` (sherpa only; fw uses Hugging Face cache) |

## IPC

- Signal file: `$XDG_RUNTIME_DIR/noctalia-dictation-signal`
- Status: `qs ipc -c noctalia-shell call plugin:dictation setStatus '<json>'`
- JSON fields: `state`, `message`, `liveTranscript`, `partialTranscript`, `text`, `engine`
- Messages: `copied`, `silence`, `no_speech`, `cancelled`, `finishing`

## Deploy paths

### Development (this repo)

Symlink the clone into Noctalia so edits are instant — **do not copy or rsync the plugin into `~/.config` during development**:

```bash
ln -sfn /home/arafays/projects/noctalia-dictation ~/.config/noctalia/plugins/dictation
```

- **User settings:** `settings.json` in the repo root (gitignored); resolved via the symlink path above
- **Local artifacts:** `models/` and `.venv/` live in the repo; run `./setup.sh` and `./download_models.sh <profile>` once after clone
- **Test changes:** edit files in this repo directly, then reload the plugin in Noctalia (development mode or disable/re-enable)

### End users

Clone or copy from GitHub per [README.md](./README.md) install guide — a plain directory at `~/.config/noctalia/plugins/dictation/` is fine when not developing.

### Chezmoi

Do **not** store the full plugin in chezmoi. Only manage the symlink target file `private_dot_config/noctalia/plugins/symlink_dictation` (contents: absolute path to this repo). Apply with:

```bash
chezmoi apply --source-path "private_dot_config/noctalia/plugins/symlink_dictation"
```

### Rules for AI agents

- **Never** `rsync`, `cp -r`, or otherwise copy this repo into `~/.config/noctalia/plugins/dictation/` when a dev symlink exists
- Edit the repo directly; reload the plugin in Noctalia to test
- Do not add the plugin sources back into chezmoi — symlink only

## Noctalia plugin install (v4)

- Discovery: `PluginRegistry` scans `~/.config/noctalia/plugins/*/manifest.json`; enable in **Settings → Plugins → Installed**.
- Official source (default): `https://github.com/noctalia-dev/noctalia-plugins` — plugins install as plain ids (`dictation/`).
- Custom sources: added in **Settings → Plugins → Sources**; install to `<6-char-hash>:<id>/` folders.
- State file: `~/.config/noctalia/plugins.json` (v2: `sources` + `states`).
- This repo is standalone (files at repo root). End users copy from GitHub; developers symlink until merged into `noctalia-plugins` as `dictation/`.
- Official listing: PR to [noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins) (+ `preview.png` 960×540 for noctalia.dev).
- Post-install (not done by shell): `./setup.sh`, `./download_models.sh <profile>`.
