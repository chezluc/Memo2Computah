import Foundation

@MainActor
final class RecordingLaunchCoordinator: ObservableObject {
    static let shared = RecordingLaunchCoordinator()

    @Published private(set) var autoStartNonce = UUID()
    private(set) var pendingAutoStart = false

    private init() {}

    func handle(url: URL) {
        guard url.scheme == "memo2computah" else { return }

        let host = url.host?.lowercased()
        let path = url.path.lowercased()

        if host == "record" || path == "/record" {
            pendingAutoStart = true
            autoStartNonce = UUID()
        }
    }

    func requestAutoStart() {
        pendingAutoStart = true
        autoStartNonce = UUID()
    }

    func consumePendingAutoStart() -> Bool {
        guard pendingAutoStart else { return false }
        pendingAutoStart = false
        return true
    }
}
