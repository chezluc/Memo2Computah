#!/usr/bin/env bash

set -euo pipefail

base_path="/Users/garnetuniverse/Dropbox/auto.transcribe.agent"
session_name="mobile-recorder"

if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "tmux session '$session_name' already exists."
    exit 0
fi

tmux new-session -d -s "$session_name" -c "$base_path"
if lsof -iTCP:8943 -sTCP:LISTEN >/dev/null 2>&1; then
    tmux send-keys -t "$session_name" "echo 'Mobile recorder server is already running on port 8943.'" C-m
else
    tmux send-keys -t "$session_name" "./scripts/start_mobile_recorder.sh" C-m
fi

echo "Started tmux session '$session_name'."
echo "Attach with: tmux attach -t $session_name"
