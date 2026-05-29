# Auto Transcribe Companion

Menu-bar macOS companion for Mobile Recorder.

## Current MVP

- Shows watcher status from `scripts/print_watcher_status.py`.
- Starts the background watcher with `scripts/start_agent_background.sh`.
- Stops the background watcher with `scripts/stop_agent_background.sh`.
- Opens the watch folder and logs folder.
- Writes the default route contract to `config/routes.json`.

## Product Direction

The companion app should become the desktop source of truth for:

- Dropbox watch folder and OAuth state.
- User-editable routes.
- AppleScript/Accessibility permissions.
- Logs, queue state, and setup diagnostics.

The existing shell scripts remain the execution backend for now. Replace them incrementally after the menu-bar shell is stable.

## Route Contract

`config/routes.json` is the first shared route contract. The iPhone app can later read this from Dropbox and render route pills dynamically instead of hardcoding route names.
