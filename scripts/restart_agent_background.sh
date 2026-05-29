#!/usr/bin/env bash

set -euo pipefail

base_path="${AUTO_TRANSCRIBE_BASE_PATH:-$HOME/Dropbox/auto.transcribe.agent}"

AUTO_TRANSCRIBE_BASE_PATH="$base_path" "$base_path/scripts/stop_agent_background.sh" >/dev/null 2>&1 || true
sleep 1
AUTO_TRANSCRIBE_BASE_PATH="$base_path" "$base_path/scripts/start_agent_background.sh"
