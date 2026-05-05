#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel

RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/user-{os.getuid()}"))
SIGNAL_FILE = RUNTIME_DIR / "noctalia-dictation-signal"
PID_FILE = RUNTIME_DIR / "noctalia-dictation-pid"
TEMP_DIR = Path(tempfile.gettempdir())
MIN_RECORDING_SEC = 0.5
_cuda_available: bool | None = None

_stop_event = threading.Event()
_recording_thread: threading.Thread | None = None
_start_lock = threading.Lock()


def send_status(state: str, message: str = "", text: str = "") -> None:
    payload = json.dumps({"state": state, "message": message, "text": text})
    try:
        subprocess.run(
            ["qs", "ipc", "-c", "noctalia-shell", "call", "plugin:dictation", "setStatus", payload],
            capture_output=True, timeout=2, check=False,
        )
    except Exception:
        pass


def _has_cuda() -> bool:
    global _cuda_available
    if _cuda_available is not None:
        return _cuda_available
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True, timeout=2, check=False,
        )
    except Exception:
        _cuda_available = False
        return False
    _cuda_available = result.returncode == 0
    return _cuda_available


def _type_text(text: str) -> None:
    try:
        subprocess.run(["wl-copy"], input=text.encode(), check=True, timeout=2)
    except Exception:
        return

    time.sleep(0.1)

    for cmd in [
        ["wtype", "-M", "ctrl", "v", "-m", "ctrl"],
        ["ydotool", "key", "29:1", "47:1", "47:0", "29:0"],
    ]:
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=5, check=False)
            if result.returncode == 0:
                break
        except Exception:
            continue


def _get_new_text(full_text: str, previous_text: str) -> str:
    if not full_text:
        return ""
    if not previous_text:
        return full_text
    if full_text.startswith(previous_text):
        return full_text[len(previous_text):]
    return full_text


def _transcribe_accumulated(
    model: WhisperModel, language: str, chunks: list[np.ndarray], fs: int,
) -> str:
    audio = np.concatenate(chunks, axis=0).flatten()
    opts: dict[str, Any] = {"beam_size": 5}
    if language and language != "auto":
        opts["language"] = language
    segments, _info = model.transcribe(audio, **opts)
    return " ".join(s.text for s in segments).strip()


def _copy_to_clipboard(text: str) -> None:
    try:
        subprocess.run(["wl-copy"], input=text.encode(), check=True, timeout=2)
    except Exception:
        pass


def cmd_start(model: WhisperModel, language: str, vad: bool, timeout: float) -> None:
    global _recording_thread
    with _start_lock:
        if _recording_thread and _recording_thread.is_alive():
            return
        _stop_event.clear()
        send_status("recording", "")
        _recording_thread = threading.Thread(
            target=_record_and_transcribe_streaming,
            args=(model, language, vad, timeout),
            daemon=True,
        )
        _recording_thread.start()


def cmd_stop() -> None:
    _stop_event.set()


def cmd_exit() -> None:
    _stop_event.set()
    if _recording_thread:
        _recording_thread.join(timeout=5)
    send_status("stopped", "")


def _record_and_transcribe_streaming(
    model: WhisperModel, language: str, vad: bool, timeout: float,
) -> None:
    all_chunks: list[np.ndarray] = []
    full_text = ""
    previous_text = ""
    chunk_sec = 0.3
    fs = 16000
    silence_threshold = 0.01
    consecutive_silence = 0
    max_silence_chunks = int(1.5 / chunk_sec)
    transcription_interval = 3.0
    last_transcribe_time = 0.0
    transcribed_up_to_chunks = 0
    was_speech = False

    try:
        recording_start = time.monotonic()
        while True:
            if _stop_event.is_set():
                break
            if time.monotonic() - recording_start >= timeout:
                break

            chunk = sd.rec(int(fs * chunk_sec), samplerate=fs, channels=1, dtype="float32")
            sd.wait()

            if _stop_event.is_set():
                break

            all_chunks.append(chunk)
            elapsed = time.monotonic() - recording_start

            if vad:
                rms = float(np.sqrt(np.mean(chunk ** 2)))
                is_speech = rms >= silence_threshold

                if is_speech:
                    consecutive_silence = 0
                    was_speech = True
                else:
                    consecutive_silence += 1

                if was_speech and consecutive_silence >= max_silence_chunks and len(all_chunks) > transcribed_up_to_chunks:
                    full_text = _transcribe_accumulated(model, language, all_chunks, fs)
                    if full_text:
                        new_text = _get_new_text(full_text, previous_text)
                        if new_text:
                            _type_text(new_text)
                        previous_text = full_text
                    transcribed_up_to_chunks = len(all_chunks)
                    was_speech = False
            else:
                if elapsed - last_transcribe_time >= transcription_interval and len(all_chunks) > transcribed_up_to_chunks:
                    full_text = _transcribe_accumulated(model, language, all_chunks, fs)
                    if full_text:
                        new_text = _get_new_text(full_text, previous_text)
                        if new_text:
                            _type_text(new_text)
                        previous_text = full_text
                    transcribed_up_to_chunks = len(all_chunks)
                    last_transcribe_time = elapsed

        if all_chunks and len(all_chunks) * chunk_sec < MIN_RECORDING_SEC:
            msg = "cancelled" if _stop_event.is_set() else "too short"
            send_status("idle", msg)
            return

        if len(all_chunks) > transcribed_up_to_chunks:
            full_text = _transcribe_accumulated(model, language, all_chunks, fs)
            if full_text and full_text != previous_text:
                new_text = _get_new_text(full_text, previous_text)
                if new_text:
                    _type_text(new_text)
                previous_text = full_text

        if full_text:
            _copy_to_clipboard(full_text)
            send_status("idle", "copied", full_text)
        else:
            send_status("idle", "silence", "")
    except Exception as e:
        send_status("error", f"{e!r}")


def read_settings() -> dict[str, Any]:
    config_dir = Path(os.environ.get(
        "XDG_CONFIG_HOME", Path.home() / ".config",
    ))
    path = config_dir / "noctalia" / "plugins" / "dictation" / "settings.json"
    defaults: dict[str, Any] = {
        "model": "base",
        "language": "auto",
        "device": "auto",
        "computeType": "int8",
        "vadEnabled": True,
        "recordingTimeout": 30,
    }
    if path.exists():
        return {**defaults, **json.loads(path.read_text())}
    return defaults


def _check_tools() -> list[str]:
    missing = [t for t in ["wl-copy", "wtype"] if not shutil.which(t)]
    if not missing:
        return []
    if shutil.which("ydotool"):
        return []
    return missing


def _is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except (OSError, ProcessLookupError):
        return False
    else:
        return True


def _kill_stale_backend() -> bool:
    """Kill any stale backend process. Returns True if cleanup was performed."""
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text().strip())
        if _is_process_alive(pid):
            os.kill(pid, 15)  # SIGTERM
            time.sleep(0.5)
            if _is_process_alive(pid):
                os.kill(pid, 9)  # SIGKILL
                time.sleep(0.2)
        PID_FILE.unlink(missing_ok=True)
        SIGNAL_FILE.unlink(missing_ok=True)
        return True
    except Exception:
        return False


def backend_server() -> None:
    send_status("idle", "starting")

    while True:
        pid_fd = os.open(PID_FILE, os.O_CREAT | os.O_RDWR, 0o644)
        try:
            fcntl.flock(pid_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            os.close(pid_fd)
            try:
                existing_pid = int(PID_FILE.read_text().strip())
                if not _is_process_alive(existing_pid):
                    _kill_stale_backend()
                    send_status("idle", "cleaned up stale backend, restarting...")
                    time.sleep(0.3)
                    continue
            except Exception:
                pass
            send_status("stopped", "another instance is running")
            return

    os.ftruncate(pid_fd, 0)
    os.write(pid_fd, str(os.getpid()).encode())
    os.fsync(pid_fd)

    settings = read_settings()
    model_size = settings["model"]
    language = settings["language"]
    vad = settings["vadEnabled"]
    timeout = settings["recordingTimeout"]

    device = settings["device"]
    if device == "auto":
        device = "cuda" if _has_cuda() else "cpu"

    compute_type = settings["computeType"]
    if device == "cpu" and compute_type == "float16":
        compute_type = "int8"

    try:
        send_status("idle", f"loading model ({model_size} on {device}, {compute_type})")
        model = WhisperModel(model_size, device=device, compute_type=compute_type)

        missing_tools = _check_tools()
        if missing_tools:
            send_status(
                "error",
                f"Missing tools: {', '.join(missing_tools)}. Install wl-clipboard and wtype.",
            )
            os.close(pid_fd)
            with contextlib.suppress(Exception):
                PID_FILE.unlink()
            return

        send_status("idle", "ready")
    except Exception as e:
        send_status("error", f"Failed to load model: {e!r}")
        os.close(pid_fd)
        with contextlib.suppress(Exception):
            PID_FILE.unlink()
        return

    if SIGNAL_FILE.exists():
        SIGNAL_FILE.unlink()

    try:
        while True:
            try:
                if not SIGNAL_FILE.exists():
                    time.sleep(0.1)
                    continue

                tmp = SIGNAL_FILE.with_suffix(f".{os.getpid()}.{int(time.time() * 1000000)}")
                try:
                    SIGNAL_FILE.rename(tmp)
                except FileNotFoundError:
                    continue
                content = tmp.read_text().strip()
                with contextlib.suppress(OSError):
                    tmp.unlink()

                if content == "start":
                    cmd_start(model, language, vad, timeout)
                elif content == "stop":
                    cmd_stop()
                elif content == "exit":
                    cmd_exit()
                    break
                elif content == "update_settings":
                    old_model = settings["model"]
                    old_device = settings["device"]
                    old_compute = settings["computeType"]
                    settings = read_settings()
                    language = settings["language"]
                    vad = settings["vadEnabled"]
                    timeout = settings["recordingTimeout"]
                    if (settings["model"] != old_model or
                            settings["device"] != old_device or
                            settings["computeType"] != old_compute):
                        send_status(
                            "idle",
                            "restart required for model/device/compute changes",
                        )
                    else:
                        send_status("idle", "settings updated")
                elif content == "status":
                    pass
            except Exception as e:
                send_status("error", f"server error: {e!r}")
                time.sleep(1)
    finally:
        with contextlib.suppress(Exception):
            os.close(pid_fd)
        with contextlib.suppress(Exception):
            PID_FILE.unlink()


def send_signal(cmd: str) -> None:
    tmp = SIGNAL_FILE.with_suffix(".tmp")
    tmp.write_text(cmd)
    tmp.rename(SIGNAL_FILE)


def main() -> None:
    parser = argparse.ArgumentParser(description="Noctalia Dictation Backend")
    parser.add_argument(
        "command", nargs="?", default="server",
        choices=["server", "start", "stop", "status", "exit", "update_settings"],
    )
    args = parser.parse_args()

    if args.command == "server":
        backend_server()
    elif args.command == "start":
        if not PID_FILE.exists():
            print("error: backend not running")
            sys.exit(1)
        send_signal("start")
        print("ok")
    elif args.command == "stop":
        send_signal("stop")
        print("ok")
    elif args.command == "exit":
        # Send signal first
        send_signal("exit")
        # Also try to kill directly in case signal mechanism isn't working
        if PID_FILE.exists():
            try:
                pid = int(PID_FILE.read_text().strip())
                if _is_process_alive(pid):
                    time.sleep(0.3)  # Give signal a chance
                    if _is_process_alive(pid):
                        os.kill(pid, 15)  # SIGTERM
            except Exception:
                pass
        print("ok")
    elif args.command == "update_settings":
        send_signal("update_settings")
        print("ok")
    elif args.command == "status":
        if PID_FILE.exists():
            try:
                pid = int(PID_FILE.read_text().strip())
                if _is_process_alive(pid):
                    print(json.dumps({"state": "running", "message": ""}))
                else:
                    print(json.dumps({"state": "stopped", "message": "process died"}))
            except Exception as e:
                print(json.dumps({"state": "error", "message": f"{e!r}"}))
        else:
            print(json.dumps({"state": "stopped", "message": "not running"}))


if __name__ == "__main__":
    main()
              