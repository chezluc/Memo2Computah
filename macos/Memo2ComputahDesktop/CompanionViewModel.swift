import AppKit
import Darwin
import Foundation
import Security
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
    @Published private(set) var isReceiverRunning = false
    @Published private(set) var receiverMessage = "Receiver not checked."
    @Published var receiverPortString: String {
        didSet {
            let normalized = receiverPortString.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized != receiverPortString {
                receiverPortString = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.receiverPortDefaultsKey)
        }
    }
    @Published var receiverAPIToken: String {
        didSet {
            let normalized = receiverAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized != receiverAPIToken {
                receiverAPIToken = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.receiverAPITokenDefaultsKey)
        }
    }
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
    private var receiverProcess: Process?
    private var lastReceiverHealthCheckAt = Date.distantPast

    private static let defaultProjectPath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Dropbox/auto.transcribe.agent")
        .path
    private static let defaultWatchFolderPath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Dropbox/Memo2Computah")
        .path
    private static let basePathDefaultsKey = "memo2ComputahDesktop.basePath"
    private static let watcherLaunchLabel = "com.garnetuniverse.memo2computah-dropbox-watcher"
    private static let receiverPortDefaultsKey = "memo2ComputahDesktop.receiverPort"
    private static let receiverAPITokenDefaultsKey = "memo2ComputahDesktop.receiverAPIToken"
    private static let bundledReceiverAPIToken = "888455e5fad152b8f90abacd391487922e8c7dea4c6411148c24802b58370d79"
    private static let defaultReceiverPort = "8943"
    private let appSupportPath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/auto.transcribe.agent")
    private var basePath: URL {
        URL(fileURLWithPath: Self.normalizedPath(basePathString), isDirectory: true)
    }
    private var watchFolder: URL {
        URL(fileURLWithPath: Self.defaultWatchFolderPath, isDirectory: true)
    }
    private var memo2AppSupportPath: URL {
        appSupportPath.appending(path: "memo2computah")
    }
    private var statePath: URL {
        memo2AppSupportPath.appending(path: "state")
    }
    private var statusURL: URL {
        statePath.appending(path: "watcher_status.json")
    }
    private var pidURL: URL {
        statePath.appending(path: "watcher.pid")
    }
    private var routesConfigURL: URL {
        basePath.appending(path: "config/routes.json")
    }
    private var transcriptionConfigURL: URL {
        basePath.appending(path: "config/transcription.env")
    }

    init() {
        self.basePathString = Self.normalizedPath(
            UserDefaults.standard.string(forKey: Self.basePathDefaultsKey) ?? Self.defaultProjectPath
        )
        self.receiverPortString = UserDefaults.standard.string(forKey: Self.receiverPortDefaultsKey) ?? Self.defaultReceiverPort
        let storedReceiverAPIToken = UserDefaults.standard.string(forKey: Self.receiverAPITokenDefaultsKey) ?? ""
        self.receiverAPIToken = storedReceiverAPIToken.isEmpty ? Self.bundledReceiverAPIToken : storedReceiverAPIToken
        UserDefaults.standard.set(self.receiverAPIToken, forKey: Self.receiverAPITokenDefaultsKey)
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
        return isRunning ? "Memo2Computah watching" : "Memo2Computah stopped"
    }

    var receiverLocalURLString: String {
        "http://127.0.0.1:\(receiverPort)"
    }

    var receiverLANURLString: String {
        "http://\(Self.primaryLANAddress()):\(receiverPort)"
    }

    private var receiverPort: Int {
        Int(receiverPortString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Int(Self.defaultReceiverPort)!
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

        if Date().timeIntervalSince(lastReceiverHealthCheckAt) > receiverHealthCheckInterval() {
            lastReceiverHealthCheckAt = Date()
            await refreshReceiverStatus()
        }
    }

    func startAgent() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try Self.ensureMemo2WatchFolder()
            try Self.ensureMemo2WatcherPlist(basePath: basePath.path, whisperModel: whisperModel)
            try? await launchctl(["bootout", "gui/\(getuid())", Self.memo2WatcherPlistPath])
            try await launchctl(["bootstrap", "gui/\(getuid())", Self.memo2WatcherPlistPath])
        } catch {
            status = WatcherStatus(status: "error", message: error.localizedDescription)
            return
        }

        do {
            try await launchctl(["kickstart", "-k", "gui/\(getuid())/\(Self.watcherLaunchLabel)"])
            await refresh()
        } catch {
            status = WatcherStatus(status: "error", message: error.localizedDescription)
        }
    }

    func stopAgent() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await launchctl(["bootout", "gui/\(getuid())", Self.memo2WatcherPlistPath])
            status = .stopped
        } catch {
            status = WatcherStatus(status: "error", message: error.localizedDescription)
        }
    }

    func skipCurrentTranscription() async {
        await runAction(scriptName: "skip_current_transcription.sh")
    }

    func startReceiver() async {
        if receiverProcess?.isRunning == true {
            await refreshReceiverStatus()
            return
        }

        let scriptURL = basePath.appending(path: "scripts/start_mobile_recorder.sh")
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = scriptURL
        process.currentDirectoryURL = basePath
        process.environment = Self.processEnvironment(
            basePath: basePath.path,
            receiverPort: String(receiverPort),
            receiverAPIToken: receiverAPIToken
        )
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] process in
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let message = [output, errorOutput]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            Task { @MainActor in
                guard let self, self.receiverProcess === process else { return }
                self.receiverProcess = nil
                self.isReceiverRunning = false
                self.receiverMessage = message.isEmpty ? "Receiver stopped." : message
            }
        }

        do {
            try process.run()
            receiverProcess = process
            receiverMessage = "Starting receiver on \(receiverLANURLString)..."
            try? await Task.sleep(for: .seconds(1))
            await refreshReceiverStatus()
        } catch {
            receiverProcess = nil
            isReceiverRunning = false
            receiverMessage = "Could not start receiver: \(error.localizedDescription)"
        }
    }

    func stopReceiver() {
        guard let receiverProcess, receiverProcess.isRunning else {
            isReceiverRunning = false
            receiverMessage = "Receiver is not managed by this app."
            return
        }

        receiverProcess.terminate()
        receiverMessage = "Stopping receiver..."
    }

    func generateReceiverAPIToken() {
        receiverAPIToken = Self.makeReceiverAPIToken()
        receiverMessage = "Token updated. Restart the receiver, then copy this token into Memo2 on iPhone."
    }

    func refreshReceiverStatus() async {
        guard let url = URL(string: "\(receiverLocalURLString)/health") else {
            isReceiverRunning = false
            receiverMessage = "Invalid receiver URL."
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) {
                isReceiverRunning = true
                receiverMessage = "Receiver ready at \(receiverLANURLString)"
            } else {
                isReceiverRunning = false
                receiverMessage = "Receiver health check failed."
            }
        } catch {
            isReceiverRunning = receiverProcess?.isRunning == true
            receiverMessage = isReceiverRunning ? "Receiver starting..." : "Receiver offline."
        }
    }

    func openReceiverURL() {
        guard let url = URL(string: receiverLocalURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    func setWhisperModel(_ model: String) {
        let normalizedModel = Self.normalizedWhisperModel(model)
        guard whisperModel != normalizedModel else { return }
        whisperModel = normalizedModel
        saveTranscriptionSettings()
    }

    func chooseBaseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Shared Project Folder"
        panel.message = "Choose the folder that contains the shared scripts and config. Memo2Computah memos still land in ~/Dropbox/Memo2Computah."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = basePath

        if panel.runModal() == .OK, let url = panel.url {
            basePathString = url.path
        }
    }

    func resetBaseFolder() {
        basePathString = Self.defaultProjectPath
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
            # Written by Memo2Computah Desktop
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
        NSWorkspace.shared.open(watchFolder)
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
            try Self.ensureMemo2WatchFolder()
            let jobURL = watchFolder.appending(path: "\(jobID).text.json")
            let message = "Memo2Computah setup test. If this appears in TextEdit, the watcher and routing are working."
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

    private func pollingDelay() -> Duration {
        if isBusy || isProcessing {
            return .milliseconds(250)
        }

        if isRunning {
            return .seconds(2)
        }

        return .seconds(5)
    }

    private func receiverHealthCheckInterval() -> TimeInterval {
        isReceiverRunning ? 10 : 5
    }

    private func readWatcherStatus() throws -> WatcherStatus {
        var decodedStatus = WatcherStatus(
            status: "stopped",
            message: "Watcher stopped",
            watchFolder: watchFolder.path
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

    private static func processEnvironment(
        basePath: String,
        receiverPort: String? = nil,
        receiverAPIToken: String? = nil
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["AUTO_TRANSCRIBE_BASE_PATH"] = basePath
        environment["AUTO_TRANSCRIBE_WATCH_FOLDER"] = Self.defaultWatchFolderPath
        environment["WATCHER_LOG_DIR"] = "\(Self.memo2AppSupportPathString)/logs"
        environment["WATCHER_STATE_DIR"] = "\(Self.memo2AppSupportPathString)/state"
        environment["WATCHER_LOOP_SLEEP"] = "2"
        environment["HEARTBEAT_INTERVAL"] = "30"
        environment["MOBILE_RECORDER_APP_ROOT"] = basePath
        environment["MOBILE_RECORDER_WATCH_FOLDER"] = Self.defaultWatchFolderPath
        if let receiverPort {
            environment["PORT"] = receiverPort
        }
        if let receiverAPIToken = receiverAPIToken?.trimmingCharacters(in: .whitespacesAndNewlines), !receiverAPIToken.isEmpty {
            environment["MOBILE_RECORDER_API_TOKEN"] = receiverAPIToken
        }
        return environment
    }

    private static func makeReceiverAPIToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return [UUID().uuidString, UUID().uuidString].joined(separator: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static var memo2WatcherPlistPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(watcherLaunchLabel).plist")
            .path
    }

    private static var memo2AppSupportPathString: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/auto.transcribe.agent/memo2computah")
            .path
    }

    private static func ensureMemo2WatchFolder() throws {
        for folder in [
            defaultWatchFolderPath,
            "\(defaultWatchFolderPath)/processed",
            "\(defaultWatchFolderPath)/transcriptions",
            "\(defaultWatchFolderPath)/transcriptions_tmp",
            "\(defaultWatchFolderPath)/responses",
            "\(defaultWatchFolderPath)/uploads_staging",
            "\(memo2AppSupportPathString)/logs",
            "\(memo2AppSupportPathString)/state"
        ] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
    }

    private static func ensureMemo2WatcherPlist(basePath: String, whisperModel: String) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logPath = "\(memo2AppSupportPathString)/logs/watcher.log"
        let agentScriptPath = "\(basePath)/scripts/auto_transcribe_agent.sh"
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: memo2WatcherPlistPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "Label": watcherLaunchLabel,
            "ProgramArguments": ["/bin/bash", agentScriptPath],
            "WorkingDirectory": basePath,
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
            "EnvironmentVariables": [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "AUTO_TRANSCRIBE_BASE_PATH": basePath,
                "AUTO_TRANSCRIBE_WATCH_FOLDER": defaultWatchFolderPath,
                "WATCHER_LOG_DIR": "\(memo2AppSupportPathString)/logs",
                "WATCHER_STATE_DIR": "\(memo2AppSupportPathString)/state",
                "VOICE_RETURN_TMUX_TARGET": "voice_return",
                "WHISPER_MODEL": normalizedWhisperModel(whisperModel),
                "WHISPER_LANGUAGE": "auto",
                "WHISPER_BEAM_SIZE": "5",
                "WHISPER_TEMPERATURE": "0",
                "WHISPER_CONDITION_ON_PREVIOUS_TEXT": "False",
                "WHISPER_INITIAL_PROMPT": "Voice command dictation. Preserve the original spoken language; do not translate. Preserve names, app names, and spelled-out letters exactly when possible. Routing terms include Codex, Claude Code, iA Writer, iTerm, WezTerm, Kitty, Tabby, Google Chrome, TextEdit, Messages, WhatsApp, Mail, Cursor, clipboard. Common phrases include thank you, main thank you, main number one, main number two, main number three, compose thank you.",
                "FILE_STABLE_WAIT": "0.5",
                "AUDIO_UPLOADING_SLEEP": "1",
                "WATCHER_LOOP_SLEEP": "2",
                "HEARTBEAT_INTERVAL": "30",
                "WHISPER_TIMEOUT_SECONDS": "0"
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: memo2WatcherPlistPath), options: .atomic)
    }

    private func launchctl(_ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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

    private static func primaryLANAddress() -> String {
        for interface in ["en0", "en1"] {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
            process.arguments = ["getifaddr", interface]
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0, !output.isEmpty {
                    return output
                }
            } catch {
                continue
            }
        }

        return "127.0.0.1"
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
