"""Backend process: signal file IPC, engine lifecycle, CLI."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import sys
import threading
import time
from typing import Any

from backend.config import ENGINE_RELOAD_KEYS, read_settings
from backend.diagnostics import diagnose_install
from backend.engines.registry import load_engine, record_session, resolve_engine_id
from backend.ipc.status import send_status
from backend.output.injection import check_injection_tools, injection_tools_error_message
from backend.paths import PID_FILE, SIGNAL_FILE

_stop_event = threading.Event()
_recording_thread: threading.Thread | None = None
_start_lock = threading.Lock()

_engine: Any = None
_engine_id = ""
_engine_label = ""
_loaded_settings: dict[str, Any] | None = None


def cmd_start(timeout: float) -> None:
    global _recording_thread
    with _start_lock:
        if _recording_thread and _recording_thread.is_alive():
            return
        _stop_event.clear()

        def _run() -> None:
            record_session(_engine, _stop_event, timeout, _engine_id)

        _recording_thread = threading.Thread(target=_run, daemon=True)
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


def send_signal(cmd: str) -> None:
    tmp = SIGNAL_FILE.with_suffix(".tmp")
    tmp.write_text(cmd)
    tmp.rename(SIGNAL_FILE)


def _log(msg: str) -> None:
    print(f"dictation: {msg}", file=sys.stderr, flush=True)


def backend_server() -> None:
    global _engine, _engine_id, _engine_label, _loaded_settings

    send_status("idle", "starting")
    _log("backend server starting")

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

    missing_tools = check_injection_tools()
    if missing_tools:
        send_status("error", injection_tools_error_message(missing_tools))
        os.close(pid_fd)
        with contextlib.suppress(Exception):
            PID_FILE.unlink()
        return

    try:
        engine_name = resolve_engine_id(settings)
        send_status("idle", f"loading {engine_name} engine...")
        _log(f"loading engine: {engine_name}")
        _engine, _engine_id, _engine_label = load_engine(settings)
        _loaded_settings = dict(settings)
        send_status("idle", "ready", engine=_engine_label)
        _log(f"ready: {_engine_label}")
    except Exception as exc:
        send_status("error", str(exc))
        _log(f"engine load failed: {exc}")
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

                _log(f"signal: {content}")

                if content == "start":
                    cmd_start(float(read_settings().get("recordingTimeout") or 0))
                elif content == "stop":
                    cmd_stop()
                elif content == "exit":
                    _log("exit requested")
                    cmd_exit()
                    break
                elif content == "update_settings":
                    new = read_settings()
                    old = _loaded_settings or {}
                    if any(old.get(k) != new.get(k) for k in ENGINE_RELOAD_KEYS):
                        if _recording_thread and _recording_thread.is_alive():
                            send_status("idle", "restart required for engine/model changes")
                        else:
                            try:
                                engine_name = resolve_engine_id(new)
                                send_status("idle", f"reloading {engine_name} engine...")
                                _engine, _engine_id, _engine_label = load_engine(new)
                                _loaded_settings = dict(new)
                                send_status("idle", "ready", engine=_engine_label)
                                _log(f"engine reloaded: {_engine_label}")
                            except Exception as exc:
                                send_status("error", str(exc))
                                _log(f"engine reload failed: {exc}")
                    else:
                        send_status("idle", "settings updated")
            except Exception as exc:
                send_status("error", f"server error: {exc}")
                _log(f"server error: {exc}")
                time.sleep(1)
    finally:
        _log("backend server shutting down")
        with contextlib.suppress(Exception):
            os.close(pid_fd)
        with contextlib.suppress(Exception):
            PID_FILE.unlink()


def main() -> None:
    parser = argparse.ArgumentParser(description="Noctalia Dictation Backend")
    parser.add_argument(
        "command",
        nargs="?",
        default="server",
        choices=["server", "start", "stop", "status", "exit", "update_settings", "diagnose"],
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
    elif args.command == "diagnose":
        print(json.dumps(diagnose_install(), indent=2))
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
