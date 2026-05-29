#!/usr/bin/env bash

set -euo pipefail

base_path="/Users/garnetuniverse/Dropbox/auto.transcribe.agent"
tmux_target="${VOICE_RETURN_TMUX_TARGET:-voice_return}"
claude_command="${VOICE_RETURN_CLAUDE_COMMAND:-claude --dangerously-skip-permissions}"

cd "$base_path"

echo "Starting watcher..."
"$base_path/scripts/restart_agent_background.sh"

echo "Checking tmux target: $tmux_target"
if tmux has-session -t "$tmux_target" 2>/dev/null; then
    pane_text="$(tmux capture-pane -t "$tmux_target" -p -S -80 2>/dev/null || true)"
    if printf '%s' "$pane_text" | grep -Eq "Claude Code|claude --dangerously-skip-permissions|❯"; then
        echo "Claude Code tmux target is ready: $tmux_target"
        exit 0
    fi

    echo "tmux target '$tmux_target' exists, but it does not look like Claude Code."
    echo "Attach and inspect it with: tmux attach -t $tmux_target"
    echo "Not overwriting that session automatically."
    exit 1
fi

echo "Creating Claude Code tmux target: $tmux_target"
tmux new-session -d -s "$tmux_target" -c "$HOME" "$claude_command"
sleep 1

if tmux has-session -t "$tmux_target" 2>/dev/null; then
    echo "Claude Code tmux target is ready: $tmux_target"
else
    echo "Failed to create tmux target: $tmux_target" >&2
    exit 1
fi
