#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="$repo_root/project/MobileRecorder.xcodeproj"
scheme="Memo2ComputahDesktop"
configuration="${CONFIGURATION:-Release}"
derived_data="${DERIVED_DATA_PATH:-$repo_root/build/DerivedData/Memo2ComputahDesktop}"
app_name="Memo2ComputahDesktop.app"
install_path="/Applications/$app_name"
bundle_id="com.garnetuniverse.Memo2ComputahDesktop"
launch_label="com.garnetuniverse.memo2computah-desktop-app"
launch_domain="gui/$(id -u)"
launch_agents_dir="$HOME/Library/LaunchAgents"
launch_plist="$launch_agents_dir/$launch_label.plist"
log_dir="$HOME/Library/Application Support/Memo2Computah/logs"
stdout_log="$log_dir/desktop-app.log"
stderr_log="$log_dir/desktop-app.err.log"

mkdir -p "$derived_data" "$launch_agents_dir" "$log_dir"

xcodebuild \
    -project "$project_path" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "platform=macOS" \
    -derivedDataPath "$derived_data" \
    build

built_app="$derived_data/Build/Products/$configuration/$app_name"
if [[ ! -d "$built_app" ]]; then
    echo "Built app not found at $built_app" >&2
    exit 1
fi

if launchctl print "$launch_domain/$launch_label" >/dev/null 2>&1; then
    launchctl bootout "$launch_domain/$launch_label" >/dev/null 2>&1 || true
fi
launchctl bootout "$launch_domain" "$launch_plist" >/dev/null 2>&1 || true

osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! pgrep -x "Memo2ComputahDesktop" >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done
stale_pids="$(pgrep -x "Memo2ComputahDesktop" || true)"
if [[ -n "$stale_pids" ]]; then
    kill $stale_pids >/dev/null 2>&1 || true
fi

ditto "$built_app" "$install_path"

python3 - "$launch_plist" "$launch_label" "$install_path" "$stdout_log" "$stderr_log" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path, label, install_path, stdout_log, stderr_log = sys.argv[1:]
payload = {
    "Label": label,
    "ProgramArguments": [
        f"{install_path}/Contents/MacOS/Memo2ComputahDesktop",
    ],
    "RunAtLoad": True,
    "KeepAlive": False,
    "LimitLoadToSessionType": "Aqua",
    "StandardOutPath": stdout_log,
    "StandardErrorPath": stderr_log,
}
Path(plist_path).write_bytes(plistlib.dumps(payload, sort_keys=False))
PY

launchctl bootstrap "$launch_domain" "$launch_plist"

echo "Installed $install_path"
echo "Registered login launcher $launch_plist"
