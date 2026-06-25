# Dictation Plugin — Development Guide (v0.3.0)

## Architecture

```
BarWidget / TranscriptOverlay / Panel
        ↕ Main.qml (IPC)
        ↕ dictation_backend.py
        ├─ asr_sherpa.py   ← two-pass (Zipformer + Whisper/SenseVoice) + Silero VAD gate
        └─ asr_common.py   ← transcript cleaning, wtype injection, clipboard, IPC
```

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

## IPC

- Signal file: `$XDG_RUNTIME_DIR/noctalia-dictation-signal`
- Status: `qs ipc -c noctalia-shell call plugin:dictation setStatus '<json>'`
- JSON fields: `state`, `message`, `liveTranscript`, `partialTranscript`, `text`, `engine`
- Messages: `copied`, `silence`, `no_speech`, `cancelled`, `finishing`

## Deploy paths

- Live: `~/.config/noctalia/plugins/dictation/`
- Chezmoi: `~/.local/share/chezmoi/private_dot_config/noctalia/plugins/dictation/`
