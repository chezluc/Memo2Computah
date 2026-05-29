import AppIntents
import SwiftyDropbox
import SwiftUI

@main
struct MobileRecorderApp: App {
    @StateObject private var dropboxManager = DropboxSessionManager.shared
    @StateObject private var launchCoordinator = RecordingLaunchCoordinator.shared

    init() {
        let launchCoordinator = RecordingLaunchCoordinator.shared
        AppDependencyManager.shared.add {
            launchCoordinator
        }
        DropboxSessionManager.shared.configureIfNeeded()
        GoogleDriveFolderManager.shared.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dropboxManager)
                .environmentObject(launchCoordinator)
                .onOpenURL { url in
                    if GoogleDriveFolderManager.shared.handleRedirectURL(url) {
                        return
                    }
                    if !dropboxManager.handleRedirectURL(url) {
                        launchCoordinator.handle(url: url)
                    }
                }
                .task {
                    await GoogleDriveFolderManager.shared.restorePreviousSignIn()
                }
        }
    }
}
