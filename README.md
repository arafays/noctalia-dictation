# noctalia-dictation

Local offline voice dictation for [Noctalia Shell](https://docs.noctalia.dev/) using **sherpa-onnx two-pass streaming**.

## Why sherpa-onnx two-pass?

| Pass | Model | Role |
|------|-------|------|
| VAD | Silero (int8) | Gates mic input before ASR; reduces noise hallucinations |
| 1st (streaming) | Zipformer transducer | ~100ms partial updates for live UI |
| 2nd (offline) | Whisper (EN) or SenseVoice (multilingual) | Accurate finals typed + clipboard |

Lower latency live feedback, better segment accuracy, and true streaming without re-transcribing the whole buffer every second.

## Features

- **Session toggle** — hotkey or mic; no silence auto-stop (optional safety timeout)
- **Silero VAD** — gates mic input before ASR; reduces noise hallucinations
- **Transcript cleaning** — strips model tags and non-speech annotations on partials and finals
- **Live transcript** — bar, overlay, panel with committed vs partial styling
- **Text injection** — `wtype` for committed text; clipboard paste fallback
- **Full-session clipboard** on stop

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| [Noctalia Shell](https://docs.noctalia.dev/getting-started/installation/) | v4.0.0+ (see `minNoctaliaVersion` in `manifest.json`) |
| Wayland compositor | Niri, Hyprland, Sway, and others supported by Noctalia |
| `wtype` | Types committed text into the focused window |
| `wl-copy` | Session clipboard on stop (`ydotool` paste fallback if `wtype` unavailable) |
| Python 3.10+ | Created automatically by `setup.sh` in a plugin-local venv |
| `curl`, `tar` | Used by `download_models.sh` |
| Microphone | PipeWire/PulseAudio; `sounddevice` needs PortAudio (often via `python-sounddevice` / `portaudio` system package) |
| ~200MB–900MB disk | Depends on model profile (see [Models](#models)) |
| Optional: CUDA | Faster ONNX inference when `sherpa provider` is set to CUDA |

## How Noctalia plugins work

Noctalia discovers plugins from **`~/.config/noctalia/plugins/<plugin-id>/`**. Each plugin folder must contain a valid `manifest.json`; the folder name must match the manifest `id`.

| Source | How it appears | Install path |
|--------|----------------|--------------|
| **Official registry** ([noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins)) | Listed in **Settings → Plugins → Available** by default; marked **Official** | Shell installs via git sparse-checkout into `~/.config/noctalia/plugins/<id>/` |
| **Custom GitHub source** | Listed after you add the repo under **Settings → Plugins → Sources** | Installed as `~/.config/noctalia/plugins/<hash>:<id>/` (hash identifies the source) |
| **Manual copy or symlink** | Shows under **Installed** after restart; not in **Available** unless also published in a configured source | `~/.config/noctalia/plugins/dictation/` |

Plugin enable/disable state and configured sources are stored in **`~/.config/noctalia/plugins.json`** (version 2). After files are on disk, open **Settings → Plugins → Installed**, enable **Dictation**, then add the bar widget under **Settings → Bar**.

> **This repository** is a standalone plugin repo (plugin files live at the repo root). The Noctalia plugin manager expects multi-plugin repos with a `dictation/` subfolder, so **manual install or symlink is the supported path here** until the plugin is merged into [noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins).

## Installation

### 1. Copy or symlink into the Noctalia plugins directory

**Recommended — copy:**

```bash
git clone https://github.com/arafays/noctalia-dictation.git
cp -r noctalia-dictation ~/.config/noctalia/plugins/dictation
cd ~/.config/noctalia/plugins/dictation
```

**Development — symlink** (edits in your clone reload with hot reload; see [Development](#development)):

```bash
git clone https://github.com/arafays/noctalia-dictation.git ~/projects/noctalia-dictation
ln -sfn ~/projects/noctalia-dictation ~/.config/noctalia/plugins/dictation
cd ~/.config/noctalia/plugins/dictation
```

### 2. Install Python dependencies

Creates `.venv/` in the plugin directory and installs `sherpa-onnx`, `sounddevice`, and `numpy`:

```bash
./setup.sh
```

Uses `uv` when available, otherwise `python3 -m venv` + `pip`.

### 3. Download speech models

```bash
./download_models.sh english       # ~150MB + VAD — recommended first
# ./download_models.sh multilingual  # ~700MB — Chinese/English/Japanese/Korean/Yue + VAD
# ./download_models.sh all           # both profiles + VAD
```

Models are stored under `models/` inside the plugin directory (not committed to git).

### 4. Enable in Noctalia

1. Restart Noctalia (or run `killall qs && qs -c noctalia-shell`).
2. Open **Settings → Plugins → Installed**.
3. Find **Dictation** and toggle it **on**.
4. Open **Settings → Bar**, pick a section, and add the **Dictation** widget.

The first enable runs `setup.sh` again if the venv is missing; the bar widget shows progress while dependencies install.

### Alternative: install from the official registry (when listed)

Once this plugin is accepted into [noctalia-dev/noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins):

1. Open **Settings → Plugins → Available**.
2. Search for **Dictation** and click **Install**.
3. Run `./setup.sh` and `./download_models.sh english` in `~/.config/noctalia/plugins/dictation/` (the plugin manager installs QML/Python sources but not ONNX models or the venv).
4. Enable the plugin and add the bar widget.

### Alternative: custom plugin source

To distribute via your own multi-plugin GitHub repo:

1. **Settings → Plugins → Sources → Add source** — paste the repo URL (e.g. `https://github.com/you/noctalia-plugins`).
2. Refresh **Available**, install **Dictation**.
3. Run `setup.sh` and `download_models.sh` in the installed folder (`~/.config/noctalia/plugins/<hash>:dictation/`).

The repo must use the standard layout: `dictation/manifest.json`, `dictation/Main.qml`, etc. A single-plugin repo whose root *is* the plugin (like this one) cannot be installed through **Sources** without that subfolder layout.

## Usage

1. Focus any text field.
2. Press your hotkey (e.g. `Mod+Shift+D`) or click the mic on the bar.
3. Speak — partial text appears in the overlay; refined text is typed at phrase boundaries.
4. Toggle again to stop — the full session is copied to the clipboard.

### Hotkey (Niri example)

```kdl
bind=Mod+Shift+D { spawn-sh "qs -c noctalia-shell ipc call plugin:dictation toggle"; }
```

Other compositors: bind the same IPC command (`plugin:dictation toggle`).

### Reload after updates

```bash
~/.config/noctalia/plugins/dictation/.venv/bin/python dictation_backend.py exit
# then restart Noctalia, or disable/re-enable the plugin
```

## Settings

Open **Settings → Plugins → Installed → Dictation** (gear icon), or use the widget context menu.

| Setting | Default | Description |
|---------|---------|-------------|
| Engine | auto | sherpa-onnx two-pass |
| sherpa profile | auto | `english` / `multilingual` model pack |
| sherpa provider | auto | CPU or CUDA ONNX Runtime |
| Language | auto | Influences profile + second-pass language |
| Safety timeout | 0 | `0` = unlimited session length (seconds) |

## Models

| Profile | Streaming (1st pass) | Offline (2nd pass) | VAD |
|---------|----------------------|--------------------|-----|
| `english` | streaming-zipformer-en-20M | whisper-tiny.en (sherpa ONNX) | silero_vad.int8.onnx |
| `multilingual` | streaming-zipformer-bilingual-zh-en | sense-voice int8 | silero_vad.int8.onnx |

All assets are downloaded from [sherpa-onnx ASR model releases](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models).

## Development

```bash
# Symlink clone into plugins dir (see Installation)
NOCTALIA_DEBUG=1 qs -c noctalia-shell   # optional: verbose logs

# In Noctalia: Settings → Plugins → Installed → Dictation → enable development mode (flask icon)
# Saves QML/i18n reload without full shell restart when NOCTALIA_DEBUG / debug mode is on
```

See [AGENTS.md](./AGENTS.md) for architecture, IPC, and deploy paths.

## Publishing to the official plugin registry

There is no separate app store — official listing is a **pull request** to [noctalia-dev/noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins).

1. Fork [noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins).
2. Add a `dictation/` directory with plugin sources, `manifest.json`, `README.md`, and **`preview.png`** (16:9, 960×540 — required for [noctalia.dev/plugins](https://noctalia.dev/plugins/)).
3. Include registry tags in `manifest.json` (e.g. `Bar`, `Panel`, `Productivity`, `Audio`).
4. Test with Noctalia Shell v4.
5. Open a PR — `registry.json` is updated automatically by GitHub Actions.

Until merged, users install from this repository manually. After merge, the same plugin id (`dictation`) appears in **Available** for all Noctalia users with the default source enabled.

**Gaps for this repo today:** not yet in the official registry; no `preview.png` for the website gallery.

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| Plugin not in **Installed** | Folder must be `~/.config/noctalia/plugins/dictation/` with valid `manifest.json`; `id` must be `dictation`; restart Noctalia |
| Stuck on “Installing dependencies…” | Run `./setup.sh` manually; check `python3` or `uv` is on PATH; read stderr in `journalctl --user` / terminal |
| “Models not found” / backend error | Run `./download_models.sh english` (or your profile); confirm `models/` exists |
| No typing into apps | Install `wtype`; focus a text field before dictating |
| No clipboard on stop | Install `wl-copy` (`wl-clipboard` package) |
| No microphone / no audio | Check PipeWire/PulseAudio; install PortAudio (`libportaudio` / `portaudio`) for `sounddevice` |
| CUDA errors | Set **sherpa provider** to CPU in plugin settings |
| Hot reload not working | Enable debug mode (click Noctalia logo 8× in About, or `NOCTALIA_DEBUG=1`); toggle development mode on the plugin |

Useful paths:

```bash
cat ~/.config/noctalia/plugins.json
cat ~/.config/noctalia/plugins/dictation/manifest.json
cat ~/.config/noctalia/plugins/dictation/settings.json
```

## Changelog

### v0.4.0

- Bar widget context menu: quick toggles for overlay, auto-type, and VAD; open plugin settings and history panel
- Settings **Behavior** section: overlay position, partial transcript, auto-type, VAD enable and sensitivity
- Backend honors `autoType`, `vadEnabled`, and `vadThreshold` (engine reload when VAD/auto-type change)

### v0.3.0

- Silero VAD pre-ASR speech gating with hangover (`silero_vad.int8.onnx`)
- `clean_transcript()` applied to second-pass commits before wtype injection
- Reject short/no-speech segments; distinguish `no_speech` vs `silence` session outcomes
- UX: committed vs partial transcript styling in overlay and panel; finishing state on stop

### v0.2.0

- sherpa-onnx two-pass streaming (Zipformer live + Whisper/SenseVoice finals)
- Live transcript overlay aligned with Noctalia shell theme and icon set
- Removed faster-whisper backend; models downloaded via `download_models.sh`
- Session clipboard, wtype injection, optional safety timeout

## License

MIT — see [LICENSE](./LICENSE).
