import Foundation

struct WatcherStatus: Codable {
    var status: String
    var currentFile: String
    var message: String
    var lastRoute: String
    var lastTranscriptPreview: String
    var queueCount: Int
    var progress: Double?
    var filesProcessed: Int
    var watchFolder: String
    var pid: Int
    var whisperModel: String?

    private static let defaultWatchFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Dropbox/auto.transcribe.agent")
        .path

    static let stopped = WatcherStatus(status: "stopped", message: "Watcher stopped")

    init(
        status: String,
        currentFile: String = "",
        message: String,
        lastRoute: String = "",
        lastTranscriptPreview: String = "",
        queueCount: Int = 0,
        progress: Double? = nil,
        filesProcessed: Int = 0,
        watchFolder: String = WatcherStatus.defaultWatchFolder,
        pid: Int = 0,
        whisperModel: String? = nil
    ) {
        self.status = status
        self.currentFile = currentFile
        self.message = message
        self.lastRoute = lastRoute
        self.lastTranscriptPreview = lastTranscriptPreview
        self.queueCount = queueCount
        self.progress = progress
        self.filesProcessed = filesProcessed
        self.watchFolder = watchFolder
        self.pid = pid
        self.whisperModel = whisperModel
    }
}
