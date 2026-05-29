#!/usr/bin/env python3

import json
import os
import signal
from pathlib import Path

BASE_PATH = Path(os.environ.get("AUTO_TRANSCRIBE_BASE_PATH", str(Path.home() / "Dropbox" / "auto.transcribe.agent")))
APP_SUPPORT_DIR = Path(os.environ.get("WATCHER_APP_SUPPORT_DIR", str(Path.home() / "Library" / "Application Support" / "auto.transcribe.agent")))
STATE_DIR = Path(os.environ.get("WATCHER_STATE_DIR", str(APP_SUPPORT_DIR / "state")))
STATUS_FILE = STATE_DIR / "watcher_status.json"
PID_FILE = STATE_DIR / "watcher.pid"


def pid_is_running(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def main() -> None:
    data = {
        "status": "stopped",
        "currentFile": "",
        "message": "Watcher stopped",
        "lastRoute": "",
        "lastTranscriptPreview": "",
        "queueCount": 0,
        "filesProcessed": 0,
        "watchFolder": str(BASE_PATH),
        "pid": 0,
    }

    if STATUS_FILE.exists():
        try:
            data.update(json.loads(STATUS_FILE.read_text(encoding="utf-8")))
        except Exception:
            data["status"] = "error"
            data["message"] = "Status file unreadable"

    pid = 0
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text(encoding="utf-8").strip() or "0")
        except Exception:
            pid = 0

    if not pid_is_running(pid):
        data["status"] = "stopped"
        data["pid"] = 0
        if data.get("message") in ("Watcher starting", "Waiting for files", "Heartbeat SCAN", "Heartbeat SYNC", "Heartbeat LISTEN", "Heartbeat ROUTE"):
            data["message"] = "Watcher stopped"
    else:
        data["pid"] = pid

    print(json.dumps(data))


if __name__ == "__main__":
    main()
