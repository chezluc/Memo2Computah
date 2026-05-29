#!/usr/bin/env bash

set -euo pipefail

base_path="${AUTO_TRANSCRIBE_BASE_PATH:-$HOME/Dropbox/auto.transcribe.agent}"
app_support_dir="${WATCHER_APP_SUPPORT_DIR:-$HOME/Library/Application Support/auto.transcribe.agent}"
state_dir="${WATCHER_STATE_DIR:-$app_support_dir/state}"
status_file="$state_dir/watcher_status.json"
skip_file="$state_dir/skip_current.flag"

mkdir -p "$state_dir"

python3 - "$status_file" "$skip_file" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

status_path = Path(sys.argv[1])
skip_path = Path(sys.argv[2])

try:
    status = json.loads(status_path.read_text(encoding="utf-8"))
except Exception:
    status = {}

if str(status.get("status", "")).lower() != "transcribing":
    print("No active transcription to skip.")
    raise SystemExit(0)

current_file = str(status.get("currentFile", "")).strip()
if not current_file:
    print("No current transcription file to skip.")
    raise SystemExit(0)

skip_path.write_text(
    json.dumps(
        {
            "requestedAt": datetime.now(timezone.utc).isoformat(),
            "currentFile": current_file,
        },
        indent=2,
    ),
    encoding="utf-8",
)
print(f"Skip requested for {current_file}.")
PY
