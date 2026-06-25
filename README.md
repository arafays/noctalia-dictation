# noctalia-dictation

Local offline voice dictation for [Noctalia Shell](https://docs.noctalia.dev/) using **sherpa-onnx two-pass streaming**.

## Why sherpa-onnx two-pass?

| Pass | Model | Role |
|------|-------|------|
| 1st (streaming) | Zipformer transducer | ~100ms partial updates for live UI |
| 2nd (offline) | Whisper (EN) or SenseVoice (multilingual) | Accurate finals typed + clipboard |

Lower latency live feedback, better segment accuracy, Silero VAD noise gating, and true streaming without re-transcribing the whole buffer every second.

## Features

- **Session toggle** — hotkey or mic; no silence auto-stop (optional safety timeout)
- **Silero VAD** — gates mic input before ASR; reduces noise hallucinations
- **Transcript cleaning** — strips model tags and non-speech annotations on partials and finals
- **Live transcript** — bar, overlay, panel with committed vs partial styling
- **Text injection** — `wtype` for committed text; clipboard paste fallback
- **Full-session clipboard** on stop

## Installation

```bash
git clone https://github.com/arafays/noctalia-dictation.git
cp -r noctalia-dictation ~/.config/noctalia/plugins/dictation
cd ~/.config/noctalia/plugins/dictation
./setup.sh
./download_models.sh english    # ~150MB + VAD, recommended first
# ./download_models.sh multilingual   # ~700MB, for non-English
```

Restart Noctalia and enable the plugin in **Settings → Plugins**.

## Usage

1. Focus any input field.
2. Press `Mod+Shift+D` (or your hotkey) or click the mic.
3. Speak — partial text in overlay; refined text typed at phrase boundaries.
4. Toggle again to stop — full session copied to clipboard.

### Hotkey (Niri example)

```kdl
bind=Mod+Shift+D { spawn-sh "qs -c noctalia-shell ipc call plugin:dictation toggle"; }
```

### Reload after updates

```bash
~/.config/noctalia/plugins/dictation/.venv/bin/python dictation_backend.py exit
# restart Noctalia or disable/re-enable plugin
```

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Engine | auto | sherpa-onnx two-pass (auto = same as sherpa) |
| sherpa profile | auto | english / multilingual model pack |
| sherpa provider | auto | CPU or CUDA ONNX Runtime |
| Language | auto | Influences profile + second-pass language |
| Safety timeout | 0 | 0 = unlimited session |

## System requirements

- `wtype`, `wl-copy` (or `ydotool` paste fallback)
- Python 3.10+ with `sherpa-onnx`, `sounddevice`, `numpy`
- Optional: CUDA for faster ONNX inference

## Changelog

### v0.3.0

- Silero VAD pre-ASR speech gating with hangover (silero_vad.int8.onnx)
- `clean_transcript()` applied to second-pass commits before wtype injection
- Reject short/no-speech segments; distinguish `no_speech` vs `silence` session outcomes
- UX: committed vs partial transcript styling in overlay and panel; finishing state on stop

### v0.2.0

- sherpa-onnx two-pass streaming (Zipformer live + Whisper/SenseVoice finals)
- Live transcript overlay aligned with Noctalia shell theme and icon set
- Removed faster-whisper backend; models downloaded via `download_models.sh`
- Session clipboard, wtype injection, optional safety timeout

## License

MIT
