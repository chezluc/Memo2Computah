import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
final class CompanionViewModel: ObservableObject {
    @Published private(set) var status = WatcherStatus.stopped
    @Published private(set) var isBusy = false
    @Published var routeDrafts: [RouteDefinition] = []
    @Published private(set) var routeMessage = ""
    @Published private(set) var setupTestMessage = ""
    @Published private(set) var isRunningSetupTest = false
    @Published private(set) var whisperModel = "tiny"
    @Published private(set) var transcriptionSettingsMessage = ""
    @Published var basePathString: String {
        didSet {
            let normalized = Self.normalizedPath(basePathString)
            if normalized != basePathString {
                basePathString = normalized
                return
            }

            UserDefaults.standard.set(normalized, forKey: Self.basePathDefaultsKey)
            loadTranscriptionSettings()
            loadRoutes()
            Task { await refresh() }
        }
    }

    private var pollingTask: Task<Void, Never>?

    private static let defaultBasePath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Dropbox/auto.transcribe.agent")
        .path
    private static let basePathDefaultsKey = "autoTranscribeCompanion.basePath"
    private let appSupportPath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/auto.transcribe.agent")
    private var basePath: URL {
        URL(fileURLWithPath: Self.normalizedPath(basePathString), isDirectory: true)
    }
    private var routesConfigURL: URL {
        basePath.appending(path: "config/routes.json")
    }
    private var transcriptionConfigURL: URL {
        basePath.appending(path: "config/transcription.env")
    }
    private var statePath: URL {
        appSupportPath.appending(path: "state")
    }
    private var statusURL: URL {
        statePath.appending(path: "watcher_status.json")
    }
    private var pidURL: URL {
        statePath.appending(path: "watcher.pid")
    }

    init() {
        self.basePathString = Self.normalizedPath(
            UserDefaults.standard.string(forKey: Self.basePathDefaultsKey) ?? Self.defaultBasePath
        )
        loadTranscriptionSettings()
        loadRoutes()
        startPolling()
    }

    var isRunning: Bool {
        status.pid > 0 && status.status != "stopped"
    }

    var menuBarSymbolName: String {
        isRunning ? "waveform.circle.fill" : "waveform.circle"
    }

    var isTranscribing: Bool {
        status.status.lowercased() == "transcribing"
    }

    var isProcessing: Bool {
        ["transcribing", "routing", "activating"].contains(status.status.lowercased())
    }

    var progressValue: Double {
        if let progress = status.progress {
            return min(1.0, max(0.0, progress))
        }
        return isProcessing ? 0.08 : 0
    }

    var progressLabel: String {
        switch status.status.lowercased() {
        case "transcribing":
            return "Transcribing"
        case "routing":
            return "Routing"
        case "activating":
            return "Activating"
        default:
            return isRunning ? "Listening" : "Stopped"
        }
    }

    var effectiveWhisperModel: String {
        status.whisperModel ?? whisperModel
    }

    var whisperModelDisplayName: String {
        Self.displayName(forWhisperModel: whisperModel)
    }

    var menuBarAccessibilityLabel: String {
        if isProcessing {
            return "\(progressLabel) \(Int(progressValue * 100)) percent"
        }
        return isRunning ? "Auto Transcribe watching" : "Auto Transcribe stopped"
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let delay = self?.pollingDelay() ?? .seconds(2)
                try? await Task.sleep(for: delay)
            }
        }
    }

    func refresh() async {
        do {
            status = try readWatcherStatus()
        } catch {
            status = WatcherStatus(status: "error", message: error.localizedDescription)
        }
    }

    func startAgent() async {
        await runAction(scriptName: "start_agent_background.sh")
    }

    func stopAgent() async {
        await runAction(scriptName: "stop_agent_background.sh")
    }

    func skipCurrentTranscription() async {
        await runAction(scriptName: "skip_current_transcription.sh")
    }

    func setWhisperModel(_ model: String) {
        let normalizedModel = Self.normalizedWhisperModel(model)
        guard whisperModel != normalizedModel else { return }
        whisperModel = normalizedModel
        saveTranscriptionSettings()
    }

    func chooseBaseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Auto Transcribe Dropbox Folder"
        panel.message = "Choose the Dropbox-synced folder that contains scripts, config, and the audio drop area."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = basePath

        if panel.runModal() == .OK, let url = panel.url {
            basePathString = url.path
        }
    }

    func resetBaseFolder() {
        basePathString = Self.defaultBasePath
    }

    func loadTranscriptionSettings() {
        do {
            let text = try String(contentsOf: transcriptionConfigURL, encoding: .utf8)
            let configuredModel = text
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("WHISPER_MODEL=") else { return nil }
                    return String(trimmed.dropFirst("WHISPER_MODEL=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                }
                .first
            whisperModel = Self.normalizedWhisperModel(configuredModel ?? "tiny")
            transcriptionSettingsMessage = "Loaded \(Self.displayName(forWhisperModel: whisperModel))."
        } catch {
            whisperModel = "tiny"
            saveTranscriptionSettings()
        }
    }

    func saveTranscriptionSettings() {
        do {
            try FileManager.default.createDirectory(
                at: transcriptionConfigURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let text = """
            # Written by Auto Transcribe Companion
            WHISPER_MODEL=\(whisperModel)
            """
            try text.appending("\n").write(to: transcriptionConfigURL, atomically: true, encoding: .utf8)
            transcriptionSettingsMessage = isRunning
                ? "Saved \(Self.displayName(forWhisperModel: whisperModel)). Applies to the next audio file."
                : "Saved \(Self.displayName(forWhisperModel: whisperModel))."
        } catch {
            transcriptionSettingsMessage = "Could not save model setting: \(error.localizedDescription)"
        }
    }

    func loadRoutes() {
        do {
            let data = try Data(contentsOf: routesConfigURL)
            let configuration = try JSONDecoder().decode(RouteConfiguration.self, from: data)
            routeDrafts = configuration.routes
            routeMessage = "Loaded \(configuration.routes.count) routes."
        } catch {
            routeDrafts = RouteConfiguration.defaultConfiguration.routes
            routeMessage = "Loaded default routes."
        }
    }

    func addRoute() {
        let nextNumber = (routeDrafts.count + 1...routeDrafts.count + 100)
            .first { number in !routeDrafts.contains { $0.id == "custom-\(number)" } } ?? routeDrafts.count + 1
        routeDrafts.append(.newAppRoute(number: nextNumber))
        routeMessage = "Added a draft route. Edit and save to activate it."
    }

    func removeRoute(id: String) {
        routeDrafts.removeAll { $0.id == id }
        routeMessage = "Removed route draft. Save to update routes.json."
    }

    func restoreDefaultRoutes() {
        routeDrafts = RouteConfiguration.defaultConfiguration.routes
        routeMessage = "Restored defaults. Save to write routes.json."
    }

    func saveRoutes() {
        let routes = RouteConfiguration.defaultConfiguration

        do {
            try FileManager.default.createDirectory(
                at: routesConfigURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let cleanedRoutes = cleanedRouteDrafts()
            let data = try JSONEncoder.pretty.encode(RouteConfiguration(version: routes.version, routes: cleanedRoutes))
            try data.write(to: routesConfigURL, options: .atomic)
            routeDrafts = cleanedRoutes
            routeMessage = "Saved \(cleanedRoutes.count) routes."
        } catch {
            status = WatcherStatus(status: "error", message: "Could not write routes.json: \(error.localizedDescription)")
            routeMessage = "Could not save routes."
        }
    }

    func revealRoutesFile() {
        NSWorkspace.shared.activateFileViewerSelecting([routesConfigURL])
    }

    func openWatchFolder() {
        NSWorkspace.shared.open(basePath)
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(appSupportPath.appending(path: "logs"))
    }

    func runTextEditSetupTest() async {
        isRunningSetupTest = true
        setupTestMessage = "Checking watcher..."
        defer { isRunningSetupTest = false }

        await refresh()
        if !isRunning {
            setupTestMessage = "Starting watcher..."
            await startAgent()
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }

        guard isRunning else {
            setupTestMessage = "Watcher is not listening. Start the watcher before running the TextEdit test."
            return
        }

        do {
            let jobID = "setup_textedit_\(Self.timestampString())_\(UUID().uuidString.prefix(8).lowercased())"
            let jobURL = basePath.appending(path: "\(jobID).text.json")
            let message = "Auto Transcribe setup test. If this appears in TextEdit, the watcher and routing are working."
            let metadata = SetupTextJobMetadata(
                job_id: jobID,
                message: message,
                submit_after_paste: true,
                route_target: "textedit",
                response_mode: nil,
                call_session: false
            )
            let data = try JSONEncoder.pretty.encode(metadata)
            try data.write(to: jobURL, options: .atomic)
            setupTestMessage = "Queued TextEdit test. TextEdit should open and receive the setup sentence."
            await refresh()
        } catch {
            setupTestMessage = "Could not queue TextEdit test: \(error.localizedDescription)"
        }
    }

    private func cleanedRouteDrafts() -> [RouteDefinition] {
        var seenIDs = Set<String>()

        return routeDrafts.compactMap { route in
            var cleaned = route
            cleaned.id = route.id
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
            cleaned.label = route.label.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.kind = route.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            cleaned.target = route.target?.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.shortcut = route.shortcut?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleaned.id.isEmpty, !cleaned.label.isEmpty, !seenIDs.contains(cleaned.id) else {
                return nil
            }

            if cleaned.kind != "clipboard", cleaned.kind != "automatic" {
                guard let target = cleaned.target, !target.isEmpty else { return nil }
            }

            if cleaned.target?.isEmpty == true {
                cleaned.target = nil
            }

            if cleaned.shortcut?.isEmpty == true {
                cleaned.shortcut = nil
            }

            seenIDs.insert(cleaned.id)
            return cleaned
        }
    }

    private func runAction(scriptName: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await runScript(path: basePath.appending(path: "scripts/\(scriptName)"))
            await refresh()
        } catch {
            status = WatcherStatus(status: "error", message: error.localizedDescription)
        }
    }

    private func pollingDelay() -> Duration {
        if isBusy || isProcessing {
            return .milliseconds(250)
        }

        if isRunning {
            return .seconds(2)
        }

        return .seconds(5)
    }

    private func readWatcherStatus() throws -> WatcherStatus {
        var decodedStatus = WatcherStatus(
            status: "stopped",
            message: "Watcher stopped",
            watchFolder: basePath.path
        )

        if FileManager.default.fileExists(atPath: statusURL.path) {
            let data = try Data(contentsOf: statusURL)
            decodedStatus = try JSONDecoder().decode(WatcherStatus.self, from: data)
        }

        let pid = readWatcherPID()
        if isProcessRunning(pid: pid) {
            decodedStatus.pid = pid
        } else {
            decodedStatus.pid = 0
            decodedStatus.status = "stopped"
            if isIdleWatcherMessage(decodedStatus.message) {
                decodedStatus.message = "Watcher stopped"
            }
        }

        return decodedStatus
    }

    private func readWatcherPID() -> Int {
        guard let rawPID = try? String(contentsOf: pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return 0
        }

        return Int(rawPID) ?? 0
    }

    private func isProcessRunning(pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid_t(pid), 0) == 0
    }

    private func isIdleWatcherMessage(_ message: String) -> Bool {
        message == "Watcher starting"
            || message == "Waiting for files"
            || message.hasPrefix("Heartbeat ")
    }

    private func runScript(path: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = path
            process.currentDirectoryURL = basePath
            process.environment = Self.processEnvironment(basePath: basePath.path)
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: CompanionError.scriptFailed(errorOutput.isEmpty ? output : errorOutput))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private static func normalizedPath(_ path: String) -> String {
        NSString(string: path.trimmingCharacters(in: .whitespacesAndNewlines))
            .expandingTildeInPath
    }

    private static func normalizedWhisperModel(_ model: String) -> String {
        switch model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "base":
            return "base"
        case "tiny":
            return "tiny"
        default:
            return "tiny"
        }
    }

    private static func displayName(forWhisperModel model: String) -> String {
        switch normalizedWhisperModel(model) {
        case "base":
            return "Base"
        default:
            return "Tiny"
        }
    }

    private static func processEnvironment(basePath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["AUTO_TRANSCRIBE_BASE_PATH"] = basePath
        return environment
    }
}

private struct SetupTextJobMetadata: Encodable {
    let job_id: String
    let message: String
    let submit_after_paste: Bool
    let route_target: String
    let response_mode: String?
    let call_session: Bool
}

private enum CompanionError: LocalizedError {
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
