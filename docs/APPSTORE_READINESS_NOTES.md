# App Store Readiness Notes

Created: 2026-05-08

## Product Shape

The release version is a paired iPhone + Mac workflow:

- iPhone records audio and uploads it to a selected Dropbox folder.
- Mac companion watches the folder, starts/stops the watcher, edits routes, and shows processing state.
- Watcher transcribes audio and routes the final text.

## Features Added In This Pass

- Mac companion route editor for `config/routes.json`.
- Menu-bar circular progress indicator for watcher states: transcribing, routing, activating.
- iPhone Settings route/help section explaining how the recorder, Dropbox, Mac helper, and routes work together.
- Generic route support in the watcher for custom Mac companion routes with app targets.

## Missing Before App Store

- First-run onboarding that explains Dropbox, Mac companion, permissions, and the route workflow.
- A signed/distributed Mac companion installer outside Xcode.
- Route sync from Mac companion to iPhone route picker, or a deliberate decision that built-in iPhone routes are the only mobile-selectable routes.
- User-selectable Mac watch folder instead of the current hard-coded local Dropbox path.
- Clear permissions checklist for Accessibility, Automation, Microphone, Dropbox, and local file access.
- Error states visible to normal users: Dropbox disconnected, Mac watcher not running, route app missing, transcription failed.
- App Store privacy labels and review notes explaining Dropbox OAuth and local Mac automation.
