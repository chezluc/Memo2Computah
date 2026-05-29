# TestFlight Release Plan

## Targets

- iPhone app: `MobileRecorder`
- iPhone Control Center widget/extension: `MobileRecorderControl`
- Mac companion: `AutoTranscribeCompanion`

## Current Packaging State

- The iPhone app records audio and uploads to Dropbox.
- The Mac companion runs as a menu-bar app and controls the watcher.
- Route/setup editing now lives in a separate SwiftUI settings window inside the Mac companion.
- The watcher currently depends on local scripts, Dropbox folder access, Whisper, AppleScript routing, and accessibility permissions.

## TestFlight Requirements

1. Active Apple Developer Program membership.
2. App Store Connect app records for the iOS app and the macOS companion.
3. Stable bundle IDs:
   - `com.garnetuniverse.MobileRecorder`
   - `com.garnetuniverse.MobileRecorder.Control`
   - `com.garnetuniverse.AutoTranscribeCompanion`
4. Archive builds from Xcode using App Store distribution signing.
5. Upload archives to App Store Connect.
6. Wait for build processing, then add internal or external testers in TestFlight.

## Mac Companion Risks Before External Testing

- App Store sandboxing may block the current script-based watcher unless we redesign file access and automation permissions.
- Apple Events/accessibility routing into apps such as Codex, Chrome, iA Writer, and terminals needs clear user permission flow.
- The watcher should eventually be bundled or installed by the companion instead of depending on loose scripts in the Dropbox project folder.
- The app needs onboarding for selecting the Dropbox folder and explaining the Mac watcher relationship.

## Practical Next Build Step

Use Xcode Archive for both schemes:

```sh
xcodebuild -project project/MobileRecorder.xcodeproj -scheme MobileRecorder -configuration Release archive
xcodebuild -project project/MobileRecorder.xcodeproj -scheme AutoTranscribeCompanion -configuration Release archive
```

Then upload the resulting archives through Xcode Organizer or `xcodebuild -exportArchive` / Transporter once App Store Connect app records exist.

## Apple References

- TestFlight overview: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Xcode distribution: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
