#!/usr/bin/env bash

set -euo pipefail

base_path="${AUTO_TRANSCRIBE_BASE_PATH:-$HOME/Dropbox/auto.transcribe.agent}"
app_support_dir="${WATCHER_APP_SUPPORT_DIR:-$HOME/Library/Application Support/auto.transcribe.agent}"
state_dir="${WATCHER_STATE_DIR:-$app_support_dir/state}"
pid_file="$state_dir/watcher.pid"
status_file="$state_dir/watcher_status.json"
agent_script="$base_path/scripts/auto_transcribe_agent.sh"
launch_label="com.garnetuniverse.auto-transcribe-agent"
launch_domain="gui/$(id -u)"
launch_plist="$HOME/Library/LaunchAgents/$launch_label.plist"

launchctl bootout "$launch_domain/$launch_label" 2>/dev/null || true
if [[ -f "$launch_plist" ]]; then
    launchctl bootout "$launch_domain" "$launch_plist" 2>/dev/null || true
fi

if [[ -f "$pid_file" ]]; then
    pid=$(cat "$pid_file" 2>/dev/null || true)

    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        for _ in {1..20}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 0.25
        done
    fi
fi

rm -f "$pid_file"

python3 - "$status_file" "$base_path" <<'PY'
import json, os, sys
status_file, base_path = sys.argv[1:]
data = {
    "status": "stopped",
    "currentFile": "",
    "message": "Watcher stopped",
    "lastRoute": "",
    "lastTranscriptPreview": "",
    "queueCount": 0,
    "filesProcessed": 0,
    "watchFolder": base_path,
    "pid": 0,
}
os.makedirs(os.path.dirname(status_file), exist_ok=True)
with open(status_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

echo "Stopped watcher."
