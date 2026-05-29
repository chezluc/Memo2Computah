#!/usr/bin/env bash

set -euo pipefail

base_path="${AUTO_TRANSCRIBE_BASE_PATH:-$HOME/Dropbox/auto.transcribe.agent}"
app_support_dir="${WATCHER_APP_SUPPORT_DIR:-$HOME/Library/Application Support/auto.transcribe.agent}"
state_dir="${WATCHER_STATE_DIR:-$app_support_dir/state}"
log_dir="${WATCHER_LOG_DIR:-$app_support_dir/logs}"
pid_file="$state_dir/watcher.pid"
status_file="$state_dir/watcher_status.json"
log_output="$log_dir/watcher_background.log"
agent_script="$base_path/scripts/auto_transcribe_agent.sh"
transcription_config_file="$base_path/config/transcription.env"
launch_label="com.garnetuniverse.auto-transcribe-agent"
launch_domain="gui/$(id -u)"
launch_agents_dir="$HOME/Library/LaunchAgents"
launch_plist="$launch_agents_dir/$launch_label.plist"

mkdir -p "$state_dir" "$log_dir" "$launch_agents_dir" "$(dirname "$transcription_config_file")"

if [[ ! -f "$transcription_config_file" ]]; then
    printf '# Written by Auto Transcribe Companion\nWHISPER_MODEL=tiny\n' > "$transcription_config_file"
fi

whisper_model=""
if [[ -f "$transcription_config_file" ]]; then
    configured_model=$(awk -F= '
        $1 == "WHISPER_MODEL" {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            gsub(/^"|"$/, "", $2)
            print $2
            exit
        }
    ' "$transcription_config_file" 2>/dev/null)
    case "${configured_model:-}" in
        tiny|base)
            whisper_model="$configured_model"
            ;;
        *)
            echo "Invalid WHISPER_MODEL '${configured_model:-}'. Allowed values: tiny, base."
            exit 64
            ;;
    esac
fi

if [[ -f "$pid_file" ]]; then
    existing_pid=$(cat "$pid_file" 2>/dev/null || true)
    if [[ -n "${existing_pid:-}" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Watcher already running (pid $existing_pid)."
        exit 0
    fi
    rm -f "$pid_file"
fi

python3 - "$launch_plist" "$launch_label" "$agent_script" "$base_path" "$log_output" "$log_dir" "$state_dir" "$HOME" "$whisper_model" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path, label, agent_script, base_path, log_output, log_dir, state_dir, home, whisper_model = sys.argv[1:]
payload = {
    "Label": label,
    "ProgramArguments": ["/bin/bash", agent_script],
    "WorkingDirectory": base_path,
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": log_output,
    "StandardErrorPath": log_output,
    "EnvironmentVariables": {
        "PATH": f"/opt/homebrew/bin:/usr/local/bin:{home}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "AUTO_TRANSCRIBE_BASE_PATH": base_path,
        "WATCHER_LOG_DIR": log_dir,
        "WATCHER_STATE_DIR": state_dir,
        "VOICE_RETURN_TMUX_TARGET": "voice_return",
        "WHISPER_MODEL": whisper_model,
        "WHISPER_LANGUAGE": "auto",
        "WHISPER_BEAM_SIZE": "5",
        "WHISPER_TEMPERATURE": "0",
        "WHISPER_CONDITION_ON_PREVIOUS_TEXT": "False",
        "WHISPER_INITIAL_PROMPT": "Voice command dictation. Preserve the original spoken language; do not translate. Preserve names, app names, and spelled-out letters exactly when possible. Routing terms include Codex, Claude Code, iA Writer, iTerm, WezTerm, Kitty, Tabby, Google Chrome, TextEdit, Messages, WhatsApp, Mail, Cursor, clipboard. Common phrases include thank you, main thank you, main number one, main number two, main number three, compose thank you.",
        "FILE_STABLE_WAIT": "0.5",
        "AUDIO_UPLOADING_SLEEP": "1",
        "WATCHER_LOOP_SLEEP": "2",
        "HEARTBEAT_INTERVAL": "30",
        "WHISPER_TIMEOUT_SECONDS": "0",
    },
}
Path(plist_path).write_bytes(plistlib.dumps(payload, sort_keys=False))
PY

if ! launchctl print "$launch_domain/$launch_label" >/dev/null 2>&1; then
    launchctl bootstrap "$launch_domain" "$launch_plist"
fi

launchctl kickstart -k "$launch_domain/$launch_label"

new_pid=""
for _ in {1..20}; do
    new_pid=$(launchctl print "$launch_domain/$launch_label" 2>/dev/null | awk -F= '/^[[:space:]]*pid = / { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' || true)
    if [[ -n "${new_pid:-}" ]] && kill -0 "$new_pid" 2>/dev/null; then
        break
    fi
    new_pid=""
    sleep 0.5
done

if [[ -z "${new_pid:-}" ]]; then
    echo "Watcher did not start. Recent log:"
    tail -40 "$log_output" || true
    exit 1
fi

echo "$new_pid" > "$pid_file"

python3 - "$status_file" "$new_pid" "$base_path" <<'PY'
import json, os, sys
status_file, pid, base_path = sys.argv[1:]
data = {
    "status": "starting",
    "currentFile": "",
    "message": "Background watcher starting",
    "lastRoute": "",
    "lastTranscriptPreview": "",
    "queueCount": 0,
    "filesProcessed": 0,
    "watchFolder": base_path,
    "pid": int(pid),
}
os.makedirs(os.path.dirname(status_file), exist_ok=True)
with open(status_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY

echo "Started watcher with launchd (pid $new_pid)."
