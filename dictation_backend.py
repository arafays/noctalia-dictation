#!/usr/bin/env python3
"""Noctalia dictation backend — sherpa-onnx two-pass streaming."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import sys
import threading
import time
from pathlib import Path
from typing import Any

from asr_common import check_injection_tools, send_status

RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/user-{os.getuid()}"))
SIGNAL_FILE = RUNTIME_DIR / "noctalia-dictation-signal"
PID_FILE = RUNTIME_DIR / "noctalia-dictation-pid"

_stop_event = threading.Event()
_recording_thread: threading.Thread | None = None
_start_lock = threading.Lock()

_engine: Any = None
_engine_name = ""
_engine_label = ""


def plugin_dir() -> Path:
    return Path(__file__).resolve().parent


def models_dir() -> Path:
    return plugin_dir() / "models"


def read_settings() -> dict[str, Any]:
    config_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = config_dir / "noctalia" / "plugins" / "dictation" / "settings.json"
    defaults: dict[str, Any] = {
        "engine": "auto",
        "language": "auto",
        "recordingTimeout": 0,
        "sherpaProfile": "auto",
        "sherpaProvider": "auto",
        "autoType": True,
        "vadEnabled": True,
        "vadThreshold": 0.4,
    }
    if path.exists():
        stored = json.loads(path.read_text())
        return {**defaults, **stored}
    return defaults


def load_engine(settings: dict[str, Any]) -> tuple[Any, str, str]:
    import asr_sherpa

    if not asr_sherpa.available():
        raise RuntimeError(f"sherpa-onnx not installed: {asr_sherpa.import_error()}")

    profile = settings.get("sherpaProfile", "auto")
    if profile == "auto":
        profile = asr_sherpa.profile_for_language(settings.get("language", "auto"))

    if not asr_sherpa.models_ready(models_dir(), profile):
        raise RuntimeError(
            f"sherpa-onnx models or Silero VAD missing for profile '{profile}'. "
            f"Run: {plugin_dir() / 'download_models.sh'} {profile}"
        )

    provider = settings.get("sherpaProvider", "auto")
    if provider == "auto":
        provider = "cuda" if asr_sherpa.has_cuda() else "cpu"

    engine = asr_sherpa.SherpaEngine(
        models_dir=models_dir(),
        profile=profile,
        provider=provider,
        language=settings.get("language", "auto"),
        vad_enabled=bool(settings.get("vadEnabled", True)),
        vad_threshold=float(settings.get("vadThreshold", 0.4)),
        auto_type=bool(settings.get("autoType", True)),
    )
    engine.load()
    return engine, "sherpa", engine.describe()


def cmd_start(timeout: float) -> None:
    global _recording_thread
    with _start_lock:
        if _recording_thread and _recording_thread.is_alive():
            return
        _stop_event.clear()
        import asr_sherpa

        target = lambda: asr_sherpa.record_session(_engine, _stop_event, timeout)
        _recording_thread = threading.Thread(target=target, daemon=True)
        _recording_thread.start()


def cmd_stop() -> None:
    _stop_event.set()


def cmd_exit() -> None:
    _stop_event.set()
    if _recording_thread:
        _recording_thread.join(timeout=5)
    send_status("stopped", "")


def _is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except (OSError, ProcessLookupError):
        return False
    return True


def _kill_stale_backend() -> bool:
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text().strip())
        if _is_process_alive(pid):
            os.kill(pid, 15)
            time.sleep(0.5)
            if _is_process_alive(pid):
                os.kill(pid, 9)
                time.sleep(0.2)
        PID_FILE.unlink(missing_ok=True)
        SIGNAL_FILE.unlink(missing_ok=True)
        return True
    except Exception:
        return False


def backend_server() -> None:
    global _engine, _engine_name, _engine_label

    send_status("idle", "starting")

    while True:
        pid_fd = os.open(PID_FILE, os.O_CREAT | os.O_RDWR, 0o644)
        try:
            fcntl.flock(pid_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            os.close(pid_fd)
            try:
                if not _is_process_alive(int(PID_FILE.read_text().strip())):
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
    timeout = float(settings.get("recordingTimeout") or 0)

    missing_tools = check_injection_tools()
    if missing_tools:
        send_status("error", f"Missing tools: {', '.join(missing_tools)}. Install wl-clipboard and wtype.")
        os.close(pid_fd)
        with contextlib.suppress(Exception):
            PID_FILE.unlink()
        return

    try:
        send_status("idle", "loading sherpa engine...")
        _engine, _engine_name, _engine_label = load_engine(settings)
        send_status("idle", "ready", engine=_engine_label)
    except Exception as exc:
        send_status("error", f"Failed to load engine: {exc!r}")
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
                    cmd_start(float(read_settings().get("recordingTimeout") or 0))
                elif content == "stop":
                    cmd_stop()
                elif content == "exit":
                    cmd_exit()
                    break
                elif content == "update_settings":
                    old = read_settings()
                    new = read_settings()
                    reload_keys = ("engine", "language", "sherpaProfile", "sherpaProvider", "vadEnabled", "vadThreshold", "autoType")
                    if any(old.get(k) != new.get(k) for k in reload_keys):
                        send_status("idle", "restart required for engine/model changes")
                    else:
                        send_status("idle", "settings updated")
            except Exception as exc:
                send_status("error", f"server error: {exc!r}")
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
        send_signal("exit")
        if PID_FILE.exists():
            try:
                pid = int(PID_FILE.read_text().strip())
                if _is_process_alive(pid):
                    time.sleep(0.3)
                    if _is_process_alive(pid):
                        os.kill(pid, 15)
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
            except Exception as exc:
                print(json.dumps({"state": "error", "message": f"{exc!r}"}))
        else:
            print(json.dumps({"state": "stopped", "message": "not running"}))


if __name__ == "__main__":
    main()
