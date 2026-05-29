# Mobile Recorder App Store Prep

Created: 2026-05-06

## Release Shape

- iPhone app is recorder-only. The experimental Text and Call screens are removed from the visible release UI.
- iPhone app uploads recordings directly to the selected Dropbox folder when Dropbox is linked.
- Mac companion is the desktop-side control surface for the watcher, route configuration, logs, and progress.
- ngrok/direct-text testing has been removed from the release UI and active iPhone resources.

## Runtime Flow

1. User records audio in Mobile Recorder on iPhone.
2. App uploads the audio file to the configured Dropbox folder.
3. Mac companion starts/stops the local watcher.
4. Watcher transcribes incoming audio and applies routing rules.
5. Mac companion menu bar shows agent state and a circular progress indicator while work is active.

## Route Ownership

Default route definitions live in the Mac companion code:

- `macos/AutoTranscribeCompanion/RouteConfiguration.swift`

The companion can write those defaults to:

- `config/routes.json`

This should become the source of truth for future route editing. The next product step is a companion UI for adding/editing routes instead of hard-coding them in Swift.

## Backup

The pre-release prototype backup is here:

- `backups/pre-appstore-prototype-20260506-185352`

That backup includes a source archive, manifest, and SHA-256 checksums.

## Active Xcode Schemes

- `MobileRecorder`: iPhone app plus Control Center extension.
- `AutoTranscribeCompanion`: macOS menu-bar helper.

Regenerate the Xcode project after editing `project/project.yml`:

```sh
cd /Users/garnetuniverse/Dropbox/auto.transcribe.agent/project
xcodegen generate --spec project.yml
```

Build iPhone:

```sh
xcodebuild -project /Users/garnetuniverse/Dropbox/auto.transcribe.agent/project/MobileRecorder.xcodeproj -scheme MobileRecorder -configuration Debug -destination 'generic/platform=iOS' build
```

Build Mac companion:

```sh
xcodebuild -project /Users/garnetuniverse/Dropbox/auto.transcribe.agent/project/MobileRecorder.xcodeproj -scheme AutoTranscribeCompanion -configuration Debug -destination 'platform=macOS' build
```

## Deferred Before App Store Submission

- Replace local absolute Mac paths in `CompanionViewModel` with a user-selected folder or first-run setup flow.
- Add a real Mac route editor for `routes.json`.
- Decide whether local-network upload fallback should remain for development only.
- Move any remaining prototype Text/Call code into a separate experiment target or archive after the release baseline is stable.
- Complete production signing, bundle IDs, privacy strings, and App Store metadata.
