import AppIntents
import SwiftyDropbox
import SwiftUI

@main
struct MobileRecorderApp: App {
    @StateObject private var dropboxManager = DropboxSessionManager.shared
    @StateObject private var launchCoordinator = RecordingLaunchCoordinator.shared

    init() {
        AppDependencyManager.shared.add {
            RecordingLaunchCoordinator.shared
        }
        DropboxSessionManager.shared.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dropboxManager)
                .environmentObject(launchCoordinator)
                .onOpenURL { url in
                    if !dropboxManager.handleRedirectURL(url) {
                        launchCoordinator.handle(url: url)
                    }
                }
        }
    }
}
