# noctalia-dictation

A Noctalia Shell plugin that provides local voice dictation using [faster-whisper](https://github.com/SYSTRAN/faster-whisper).

## Features

- Local, offline speech-to-text — no cloud services needed
- Bar widget with mic icon that pulses during recording
- Transcription history panel with copy and re-type actions
- Configurable Whisper model (tiny through large-v3)
- VAD (Voice Activity Detection) to auto-stop on silence
- Multi-language support (auto-detect or pick from 20+ languages)

## Requirements

- [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) >= 4.0.0
- Python 3.9+ (deps auto-installed via setup.sh)
- `wtype` or `ydotool` for text input
- `wl-copy` for clipboard integration
- (Optional) NVIDIA GPU + CUDA for faster transcription

Then restart Noctalia and enable the plugin in Settings > Plugins.

## Usage

Click the microphone icon in the bar to start recording. Speak, then click again (or let VAD silence detection stop it). Your transcribed text will be typed into the currently focused input field.

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Model | base | Whisper model size (tiny, base, small, medium, large-v3) |
| Language | auto | Auto-detect or specify a language |
| Device | auto | CPU/CUDA compute device |
| Compute type | int8 | Quantization (int8, float16, float32) |
| VAD | enabled | Auto-stop during silence |
| Timeout | 30s | Max recording duration |

## License

MIT
