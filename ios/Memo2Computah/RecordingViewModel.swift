import AVFoundation
import Foundation
import Security
import Speech
import UIKit

struct VoiceThreadMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
        case status
    }

    let id = UUID()
    let role: Role
    let text: String
    let createdAt = Date()
}

@MainActor
final class RecordingViewModel: NSObject, ObservableObject {
    enum RouteTarget: String, CaseIterable, Identifiable {
        case automatic
        case clipboard
        case codex
        case plexi
        case chrome
        case iaWriter
        case textEdit
        case terminal
        case iTerm
        case iTerm1
        case iTerm2
        case iTerm3
        case iTerm4
        case wezTerm
        case kitty
        case tabby
        case termius
        case termiusPrimeMinister
        case termiusDirectorChezLuc

        var id: String { rawValue }

        var label: String {
            switch self {
            case .automatic: return "Auto"
            case .clipboard: return "Clipboard"
            case .codex: return "Codex"
            case .plexi: return "Plexi"
            case .chrome: return "Google Chrome"
            case .iaWriter: return "iA Writer"
            case .textEdit: return "TextEdit"
            case .terminal: return "Terminal"
            case .iTerm: return "iTerm"
            case .iTerm1: return "iTerm 1"
            case .iTerm2: return "iTerm 2"
            case .iTerm3: return "iTerm 3"
            case .iTerm4: return "iTerm 4"
            case .wezTerm: return "WezTerm"
            case .kitty: return "Kitty"
            case .tabby: return "Tabby"
            case .termius: return "Termius"
            case .termiusPrimeMinister: return "Prime Minister / Termius"
            case .termiusDirectorChezLuc: return "Director Chez Luc / Termius"
            }
        }

        var metadataValue: String? {
            switch self {
            case .automatic: return nil
            case .clipboard: return "clipboard"
            case .codex: return "codex"
            case .plexi: return "plexi"
            case .chrome: return "chrome"
            case .iaWriter: return "iawriter"
            case .textEdit: return "textedit"
            case .terminal: return "terminal"
            case .iTerm: return "iterm"
            case .iTerm1: return "iterm:1"
            case .iTerm2: return "iterm:2"
            case .iTerm3: return "iterm:3"
            case .iTerm4: return "iterm:4"
            case .wezTerm: return "wezterm"
            case .kitty: return "kitty"
            case .tabby: return "tabby"
            case .termius: return "termius"
            case .termiusPrimeMinister: return "termius-prime-minister"
            case .termiusDirectorChezLuc: return "termius-director-chez-luc"
            }
        }
    }

    enum RecordingState: Equatable {
        case idle
        case recording
        case paused
        case uploading
    }

    enum NormalTranscriptionMode: String, CaseIterable, Identifiable {
        case dropboxAudio
        case appleSpeechOnDevice

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dropboxAudio: return "Desktop audio"
            case .appleSpeechOnDevice: return "Apple Speech on device"
            }
        }

        var detail: String {
            switch self {
            case .dropboxAudio:
                return "Record audio, send it through the selected delivery mode, and let the desktop companion transcribe and route it."
            case .appleSpeechOnDevice:
                return "Use iPhone speech recognition locally, then send the captured text through the selected delivery mode for routing."
            }
        }
    }

    enum DeliveryMode: String, CaseIterable, Identifiable {
        case dropbox
        case googleDriveFiles
        case lanHTTP
        case cloudflareHTTP

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dropbox: return "Dropbox"
            case .googleDriveFiles: return "Google Drive"
            case .lanHTTP: return "LAN HTTP"
            case .cloudflareHTTP: return "Cloudflare HTTP"
            }
        }

        var detail: String {
            switch self {
            case .dropbox:
                return "Use the existing Dropbox folder handoff."
            case .googleDriveFiles:
                return "Sign in to Google Drive and upload jobs into the `auto.transcribe` folder."
            case .lanHTTP:
                return "Upload directly to Memo2Computah Desktop on the same Wi-Fi network."
            case .cloudflareHTTP:
                return "Upload to the same desktop receiver through a Cloudflare tunnel URL."
            }
        }
    }

    enum ReceiverReachability: Equatable {
        case notChecked
        case checking
        case ready(String)
        case offline(String)

        var label: String {
            switch self {
            case .notChecked: return "Not checked"
            case .checking: return "Checking..."
            case .ready: return "Ready"
            case .offline: return "Offline"
            }
        }

        var detail: String {
            switch self {
            case .notChecked:
                return "Use Check Receiver after setting the delivery URL."
            case .checking:
                return "Checking selected receiver..."
            case .ready(let message), .offline(let message):
                return message
            }
        }

        var isReady: Bool {
            if case .ready = self {
                return true
            }
            return false
        }
    }

    struct ReceiverCheckPrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct ReceiverCheckSuccessPrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published var state: RecordingState = .idle
    @Published var statusText = "Ready"
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var deliveryMode: DeliveryMode
    @Published private(set) var receiverReachability: ReceiverReachability = .notChecked
    @Published var receiverCheckPrompt: ReceiverCheckPrompt?
    @Published var receiverCheckSuccessPrompt: ReceiverCheckSuccessPrompt?
    @Published var serverURLString: String
    @Published var cloudflareServerURLString: String
    @Published var directTextServerURLString: String
    @Published var directTextAPIToken: String
    @Published var lanReceiverProfiles: [LANReceiverProfile]
    @Published var selectedLANReceiverID: String
    @Published private(set) var googleDriveFolderDisplayName: String
    @Published private(set) var googleDriveFolderIsReady: Bool
    @Published private(set) var googleDriveFolderError: String?
    @Published var submitAfterPaste: Bool
    @Published var textResponseModeEnabled: Bool
    @Published var routeTarget: RouteTarget
    @Published var showRouteSelectorOnRecorder: Bool
    @Published var showRouteButtonsOnRecorder: Bool
    @Published var quickRouteTargets: [RouteTarget]
    @Published var voiceCallModeEnabled: Bool
    @Published var callSessionActive = false
    @Published var normalTranscriptionMode: NormalTranscriptionMode
    @Published var liveTranscriptPreviewEnabled: Bool
    @Published var lastUploadedFilename: String?
    @Published var threadMessages: [VoiceThreadMessage] = []
    @Published var isWaitingForTextResponse = false
    @Published var isWaitingForCallResponse = false
    @Published var queuedCallSpeechCount = 0
    @Published var waveformSamples: [CGFloat] = Array(repeating: 0.08, count: 33)
    @Published var liveTranscript = ""
    @Published private(set) var pendingBackgroundUploadCount = 0
    @Published private(set) var lastBackgroundUploadError: String?
    @Published var speakCallResponsesEnabled: Bool
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let liveSpeechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent) ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let liveSpeechAudioEngine = AVAudioEngine()
    private var liveSpeechRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var liveSpeechRecognitionTask: SFSpeechRecognitionTask?
    private var liveSpeechTranscriptPrefix = ""
    private var liveSpeechCurrentPartial = ""
    private var liveSpeechSessionID = 0
    private var lastLiveTranscriptChangedAt: Date?
    private var liveSpeechTapInstalled = false
    private var liveSpeechAuthorizationDenied = false
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartedAt: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var currentRecordingURL: URL?
    private var speechDetectedInCurrentTurn = false
    private var lastSpeechDetectedAt: Date?
    private var isHandlingCallTurn = false
    private var manualCallTurnSendRequested = false
    private var liveTranscriptionRequiredForCurrentTurn = false
    private var liveTranscriptionReadyForCurrentTurn = false
    private var currentRecordingUsesAppleSpeechNormalMode = false
    private var currentRecordingRequiresOnDeviceSpeech = false
    private var endingCallAfterCurrentTurn = false
    private var pausedByAudioInterruption = false
    private var pendingTextResponseCount = 0
    private var pendingCallResponseCount = 0
    private var queuedCallSpeech: [String] = []
    private var callViewVisible = false
    private var appIsActive = true
    private var notificationObservers: [NSObjectProtocol] = []
    private let dropboxManager = DropboxSessionManager.shared
    private let googleDriveManager = GoogleDriveFolderManager.shared

    override init() {
        let storedDeliveryMode = UserDefaults.standard.string(forKey: Self.deliveryModeDefaultsKey).flatMap(DeliveryMode.init(rawValue:)) ?? .dropbox
        self.deliveryMode = storedDeliveryMode
        let storedServerURL = UserDefaults.standard.string(forKey: Self.serverURLDefaultsKey)
        let normalizedStoredServerURL = Self.normalizedLANServerURL(storedServerURL)
        let storedLANReceiverProfiles = Self.storedLANReceiverProfiles(defaultURL: normalizedStoredServerURL)
        let storedSelectedLANReceiverID = UserDefaults.standard.string(forKey: Self.selectedLANReceiverIDDefaultsKey)
        let selectedLANReceiverID = storedLANReceiverProfiles.contains { $0.id == storedSelectedLANReceiverID }
            ? storedSelectedLANReceiverID!
            : storedLANReceiverProfiles[0].id
        self.lanReceiverProfiles = storedLANReceiverProfiles
        self.selectedLANReceiverID = selectedLANReceiverID
        self.serverURLString = storedLANReceiverProfiles.first { $0.id == selectedLANReceiverID }?.urlString.nonEmpty ?? normalizedStoredServerURL
        self.cloudflareServerURLString = UserDefaults.standard.string(forKey: Self.cloudflareServerURLDefaultsKey) ?? ""
        self.directTextServerURLString = UserDefaults.standard.string(forKey: Self.directTextServerURLDefaultsKey) ?? ""
        self.directTextAPIToken = Self.readDirectTextAPITokenWithBundledFallback()
        self.googleDriveFolderDisplayName = googleDriveManager.folderDisplayName
        self.googleDriveFolderIsReady = googleDriveManager.isReadyForUpload
        self.googleDriveFolderError = googleDriveManager.lastErrorMessage
        self.submitAfterPaste = UserDefaults.standard.object(forKey: Self.submitAfterPasteDefaultsKey) as? Bool ?? true
        self.textResponseModeEnabled = false
        let storedRoute = UserDefaults.standard.string(forKey: Self.routeTargetDefaultsKey).flatMap(RouteTarget.init(rawValue:)) ?? .automatic
        self.routeTarget = storedRoute
        self.showRouteSelectorOnRecorder = UserDefaults.standard.object(forKey: Self.showRouteSelectorOnRecorderDefaultsKey) as? Bool ?? true
        self.showRouteButtonsOnRecorder = UserDefaults.standard.object(forKey: Self.showRouteButtonsOnRecorderDefaultsKey) as? Bool ?? true
        self.quickRouteTargets = Self.storedQuickRouteTargets()
        self.voiceCallModeEnabled = false
        let storedNormalMode = UserDefaults.standard.string(forKey: Self.normalTranscriptionModeDefaultsKey).flatMap(NormalTranscriptionMode.init(rawValue:)) ?? .dropboxAudio
        self.normalTranscriptionMode = storedNormalMode
        self.liveTranscriptPreviewEnabled = UserDefaults.standard.object(forKey: Self.liveTranscriptPreviewDefaultsKey) as? Bool ?? false
        self.speakCallResponsesEnabled = UserDefaults.standard.object(forKey: Self.speakCallResponsesDefaultsKey) as? Bool ?? true
        super.init()
        persistTextResponseMode()
        persistVoiceCallMode()
        speechSynthesizer.delegate = self
        registerAudioSessionObservers()
        Task {
            await dropboxManager.refreshAccountName()
        }
    }

    private static let deliveryModeDefaultsKey = "memo2Computah.deliveryMode"
    private static let serverURLDefaultsKey = "memo2Computah.serverURL"
    private static let lanReceiverProfilesDefaultsKey = "memo2Computah.lanReceiverProfiles"
    private static let selectedLANReceiverIDDefaultsKey = "memo2Computah.selectedLANReceiverID"
    private static let cloudflareServerURLDefaultsKey = "memo2Computah.cloudflareServerURL"
    private static let directTextServerURLDefaultsKey = "memo2Computah.directTextServerURL"
    private static let directTextAPITokenService = "com.garnetuniverse.Memo2Computah.directTextAPIToken"
    private static let directTextAPITokenAccount = "default"
    private static let bundledReceiverAPIToken = "888455e5fad152b8f90abacd391487922e8c7dea4c6411148c24802b58370d79"
    private static let submitAfterPasteDefaultsKey = "memo2Computah.submitAfterPaste"
    private static let textResponseModeDefaultsKey = "memo2Computah.textResponseMode"
    private static let routeTargetDefaultsKey = "memo2Computah.routeTarget"
    private static let showRouteSelectorOnRecorderDefaultsKey = "memo2Computah.showRouteSelectorOnRecorder"
    private static let showRouteButtonsOnRecorderDefaultsKey = "memo2Computah.showRouteButtonsOnRecorder"
    private static let quickRouteTargetsDefaultsKey = "memo2Computah.quickRouteTargets"
    private static let defaultQuickRouteTargets: [RouteTarget] = [.kitty, .codex, .plexi, .termius, .termiusPrimeMinister, .termiusDirectorChezLuc]
    private static let termiusQuickRouteMigrationDefaultsKey = "memo2Computah.quickRouteTargets.addedTermius"
    private static let termiusPaneQuickRouteMigrationDefaultsKey = "memo2Computah.quickRouteTargets.addedTermiusPanes"
    private static let voiceCallModeDefaultsKey = "memo2Computah.voiceCallMode"
    private static let normalTranscriptionModeDefaultsKey = "memo2Computah.normalTranscriptionMode"
    private static let liveTranscriptPreviewDefaultsKey = "memo2Computah.liveTranscriptPreview"
    private static let speakCallResponsesDefaultsKey = "memo2Computah.speakCallResponses"
    private static let callSpeechThreshold: CGFloat = 0.10
    private static let callSilenceDuration: TimeInterval = 1.45
    private static let callMinimumTurnDuration: TimeInterval = 0.8
    private static let liveTranscriptPauseDuration: TimeInterval = 1.9
    private static let callMaximumTurnDuration: TimeInterval = 45
    private static let callIdleRecycleDuration: TimeInterval = 90
    static let defaultLANServerURLString = "http://192.168.8.113:8943"
    private static let retiredLANServerURLStrings = [
        "http://192.168.15.4:8943",
        "http://192.168.15.3:8943",
        "http://192.168.15.14:8943"
    ]

    private var shouldUsePhoneTranscriptionForNewRecording: Bool {
        canSubmitTextJob
            && deliveryMode != .googleDriveFiles
            && appIsActive
            && (textResponseModeEnabled || voiceCallModeEnabled || callSessionActive)
    }

    private var shouldUseAppleSpeechForNormalRecording: Bool {
        normalTranscriptionMode == .appleSpeechOnDevice
            && appIsActive
            && !textResponseModeEnabled
            && !voiceCallModeEnabled
            && !callSessionActive
    }

    private var shouldShowLiveTranscriptPreviewForNewRecording: Bool {
        (liveTranscriptPreviewEnabled || normalTranscriptionMode == .appleSpeechOnDevice)
            && appIsActive
            && !textResponseModeEnabled
            && !voiceCallModeEnabled
            && !callSessionActive
    }

    private var shouldUseLiveTranscriptionMetering: Bool {
        textResponseModeEnabled || voiceCallModeEnabled || callSessionActive
    }

    private var canSubmitTextJob: Bool {
        isDirectTextTransportReady || dropboxManager.isReadyForUpload || isGoogleDriveFilesTransportReady
    }

    private var isDirectTextTransportReady: Bool {
        deliveryMode == .lanHTTP || deliveryMode == .cloudflareHTTP
            ? activeHTTPBaseURL() != nil
            : false
    }

    private var isGoogleDriveFilesTransportReady: Bool {
        deliveryMode == .googleDriveFiles && googleDriveManager.isReadyForUpload
    }

    var selectedHTTPDeliveryURLString: String {
        switch deliveryMode {
        case .dropbox, .googleDriveFiles:
            return ""
        case .lanHTTP:
            return serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        case .cloudflareHTTP:
            return cloudflareServerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func persistDeliveryMode() {
        UserDefaults.standard.set(deliveryMode.rawValue, forKey: Self.deliveryModeDefaultsKey)
        receiverReachability = .notChecked
        if deliveryMode == .lanHTTP {
            statusText = "Check receiver before recording"
        } else if deliveryMode == .googleDriveFiles, !googleDriveManager.isReadyForUpload {
            statusText = "Choose Google Drive folder"
        }
    }

    func persistServerURL() {
        UserDefaults.standard.set(serverURLString, forKey: Self.serverURLDefaultsKey)
        updateSelectedLANReceiverURL(serverURLString)
        if deliveryMode == .lanHTTP {
            receiverReachability = .notChecked
        }
    }

    func persistCloudflareServerURL() {
        UserDefaults.standard.set(cloudflareServerURLString, forKey: Self.cloudflareServerURLDefaultsKey)
        if deliveryMode == .cloudflareHTTP {
            receiverReachability = .notChecked
        }
    }

    func checkSelectedReceiver() async {
        if deliveryMode == .dropbox {
            receiverReachability = dropboxManager.isReadyForUpload
                ? .ready("Dropbox is connected.")
                : .offline("Dropbox is not connected.")
            return
        }

        if deliveryMode == .googleDriveFiles {
            refreshGoogleDriveFolderStatus()
            receiverReachability = googleDriveFolderIsReady
                ? .ready("Google Drive folder is selected.")
                : .offline("Choose a Google Drive folder in Files.")
            return
        }

        guard let baseURL = activeHTTPBaseURL() else {
            receiverReachability = .offline("Missing or invalid receiver URL.")
            return
        }

        var healthURL = baseURL
        healthURL.append(path: "health")
        receiverReachability = .checking

        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                receiverReachability = .offline("Receiver returned an invalid response.")
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                receiverReachability = .offline("Receiver returned HTTP \(httpResponse.statusCode).")
                return
            }

            let payload = (try? JSONDecoder().decode(ReceiverHealthResponse.self, from: data)) ?? ReceiverHealthResponse(ok: true, service: nil, watchFolder: nil, apiAuthRequired: nil)
            let service = payload.service ?? "receiver"
            let folder = payload.watchFolder.map { " Watching \($0)." } ?? ""
            if payload.ok {
                if payload.apiAuthRequired == true {
                    do {
                        try await checkReceiverAPIAuth(baseURL: baseURL)
                    } catch {
                        receiverReachability = .offline("Receiver requires a valid API token.")
                        return
                    }
                }

                receiverReachability = .ready("\(service) is reachable.\(folder)")
                receiverCheckSuccessPrompt = ReceiverCheckSuccessPrompt(
                    title: "Receiver Checked",
                    message: "The \(deliveryMode.label) receiver is reachable. You are good to record."
                )
            } else {
                receiverReachability = .offline("\(service) is reachable but not ready.")
            }
        } catch {
            receiverReachability = .offline(Self.receiverCheckFailureMessage(for: error))
        }
    }

    private func checkReceiverAPIAuth(baseURL: URL) async throws {
        let pingURL = baseURL.appending(path: "api/ping")
        var request = URLRequest(url: pingURL)
        request.timeoutInterval = 10
        setDirectTextAuthorizationHeader(on: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw RecorderError.invalidResponse
        }
    }

    func dismissReceiverCheckPrompt() {
        receiverCheckPrompt = nil
    }

    func dismissReceiverCheckSuccessPrompt() {
        receiverCheckSuccessPrompt = nil
    }

    private static func normalizedLANServerURL(_ storedValue: String?) -> String {
        let trimmed = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return defaultLANServerURLString }
        return retiredLANServerURLStrings.contains(trimmed) ? defaultLANServerURLString : trimmed
    }

    private static func receiverCheckFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
            return "The request timed out. Confirm the LAN URL exactly matches Memo2Computah Desktop and both devices are on the same Wi-Fi."
        }
        return error.localizedDescription
    }

    func persistDirectTextSettings() {
        UserDefaults.standard.set(directTextServerURLString, forKey: Self.directTextServerURLDefaultsKey)
        Self.saveDirectTextAPIToken(directTextAPIToken)
    }

    func selectLANReceiver(id: String) {
        guard let profile = lanReceiverProfiles.first(where: { $0.id == id }) else { return }
        selectedLANReceiverID = id
        serverURLString = profile.urlString
        UserDefaults.standard.set(id, forKey: Self.selectedLANReceiverIDDefaultsKey)
        persistServerURL()
        receiverReachability = .notChecked
    }

    func addLANReceiverProfile() {
        let number = lanReceiverProfiles.count + 1
        let profile = LANReceiverProfile(
            id: UUID().uuidString,
            name: "Computer \(number)",
            urlString: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        lanReceiverProfiles.append(profile)
        selectedLANReceiverID = profile.id
        persistLANReceiverProfiles()
        UserDefaults.standard.set(profile.id, forKey: Self.selectedLANReceiverIDDefaultsKey)
    }

    func updateSelectedLANReceiverURL(_ urlString: String) {
        guard let index = lanReceiverProfiles.firstIndex(where: { $0.id == selectedLANReceiverID }) else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lanReceiverProfiles[index].urlString != trimmedURL else { return }
        lanReceiverProfiles[index].urlString = trimmedURL
        persistLANReceiverProfiles()
    }

    func setGoogleDriveFolder(url: URL) {
        _ = url
        googleDriveFolderError = "Google Drive now uses sign-in instead of the Files folder picker."
        refreshGoogleDriveFolderStatus()
        if deliveryMode == .googleDriveFiles {
            statusText = "Connect Google Drive"
        }
    }

    func connectGoogleDrive() async {
        deliveryMode = .googleDriveFiles
        persistDeliveryMode()
        statusText = "Connecting Google Drive..."
        do {
            try await googleDriveManager.connect()
            refreshGoogleDriveFolderStatus()
            statusText = "Google Drive connected"
        } catch {
            refreshGoogleDriveFolderStatus()
            googleDriveFolderError = error.localizedDescription
            statusText = "Google Drive failed"
        }
    }

    func clearGoogleDriveFolder() {
        googleDriveManager.clearFolder()
        refreshGoogleDriveFolderStatus()
        if deliveryMode == .googleDriveFiles {
            statusText = "Connect Google Drive"
        }
    }

    func refreshGoogleDriveFolderStatus() {
        googleDriveFolderDisplayName = googleDriveManager.folderDisplayName
        googleDriveFolderIsReady = googleDriveManager.isReadyForUpload
        googleDriveFolderError = googleDriveManager.lastErrorMessage
    }

    func restoreBundledDirectTextSettings() {
        directTextServerURLString = ""
        directTextAPIToken = ""
        persistDirectTextSettings()
    }

    func persistSubmitAfterPaste() {
        UserDefaults.standard.set(submitAfterPaste, forKey: Self.submitAfterPasteDefaultsKey)
    }

    func persistTextResponseMode() {
        UserDefaults.standard.set(textResponseModeEnabled, forKey: Self.textResponseModeDefaultsKey)
    }

    func persistRouteTarget() {
        UserDefaults.standard.set(routeTarget.rawValue, forKey: Self.routeTargetDefaultsKey)
    }

    func persistShowRouteSelectorOnRecorder() {
        UserDefaults.standard.set(showRouteSelectorOnRecorder, forKey: Self.showRouteSelectorOnRecorderDefaultsKey)
    }

    func persistShowRouteButtonsOnRecorder() {
        UserDefaults.standard.set(showRouteButtonsOnRecorder, forKey: Self.showRouteButtonsOnRecorderDefaultsKey)
    }

    func persistQuickRouteTargets() {
        let routeValues = quickRouteTargets.map(\.rawValue)
        UserDefaults.standard.set(routeValues, forKey: Self.quickRouteTargetsDefaultsKey)
    }

    func isQuickRouteTarget(_ route: RouteTarget) -> Bool {
        quickRouteTargets.contains(route)
    }

    func setQuickRouteTarget(_ route: RouteTarget, isIncluded: Bool) {
        if isIncluded {
            guard !quickRouteTargets.contains(route) else { return }
            quickRouteTargets.append(route)
        } else {
            quickRouteTargets.removeAll { $0 == route }
        }
        persistQuickRouteTargets()
    }

    func selectAllQuickRoutes() {
        quickRouteTargets = RouteTarget.allCases
        persistQuickRouteTargets()
    }

    func resetQuickRoutesToDefaults() {
        quickRouteTargets = Self.defaultQuickRouteTargets
        persistQuickRouteTargets()
    }

    func persistVoiceCallMode() {
        UserDefaults.standard.set(voiceCallModeEnabled, forKey: Self.voiceCallModeDefaultsKey)
    }

    func persistNormalTranscriptionMode() {
        UserDefaults.standard.set(normalTranscriptionMode.rawValue, forKey: Self.normalTranscriptionModeDefaultsKey)
    }

    func persistLiveTranscriptPreviewEnabled() {
        UserDefaults.standard.set(liveTranscriptPreviewEnabled, forKey: Self.liveTranscriptPreviewDefaultsKey)
    }

    func persistSpeakCallResponsesEnabled() {
        UserDefaults.standard.set(speakCallResponsesEnabled, forKey: Self.speakCallResponsesDefaultsKey)
    }

    private static func storedQuickRouteTargets() -> [RouteTarget] {
        guard UserDefaults.standard.object(forKey: quickRouteTargetsDefaultsKey) != nil else {
            return defaultQuickRouteTargets
        }
        let storedValues = UserDefaults.standard.stringArray(forKey: quickRouteTargetsDefaultsKey) ?? []
        var routes = storedValues.compactMap(RouteTarget.init(rawValue:))
        if UserDefaults.standard.object(forKey: termiusQuickRouteMigrationDefaultsKey) == nil {
            if !routes.contains(.termius) {
                routes.append(.termius)
            }
            UserDefaults.standard.set(true, forKey: termiusQuickRouteMigrationDefaultsKey)
            UserDefaults.standard.set(routes.map(\.rawValue), forKey: quickRouteTargetsDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: termiusPaneQuickRouteMigrationDefaultsKey) == nil {
            for route in [RouteTarget.termiusPrimeMinister, .termiusDirectorChezLuc] where !routes.contains(route) {
                routes.append(route)
            }
            UserDefaults.standard.set(true, forKey: termiusPaneQuickRouteMigrationDefaultsKey)
            UserDefaults.standard.set(routes.map(\.rawValue), forKey: quickRouteTargetsDefaultsKey)
        }
        return routes
    }

    private static func storedLANReceiverProfiles(defaultURL: String) -> [LANReceiverProfile] {
        if let data = UserDefaults.standard.data(forKey: lanReceiverProfilesDefaultsKey),
           let profiles = try? JSONDecoder().decode([LANReceiverProfile].self, from: data),
           !profiles.isEmpty {
            let normalizedProfiles = profiles.map { profile in
                LANReceiverProfile(
                    id: profile.id,
                    name: profile.name,
                    urlString: normalizedLANServerURL(profile.urlString)
                )
            }
            if normalizedProfiles != profiles,
               let data = try? JSONEncoder().encode(normalizedProfiles) {
                UserDefaults.standard.set(data, forKey: lanReceiverProfilesDefaultsKey)
            }
            return normalizedProfiles
        }

        return [
            LANReceiverProfile(id: "primary", name: "Computer 1", urlString: defaultURL),
            LANReceiverProfile(id: "secondary", name: "Computer 2", urlString: "")
        ]
    }

    private func persistLANReceiverProfiles() {
        if let data = try? JSONEncoder().encode(lanReceiverProfiles) {
            UserDefaults.standard.set(data, forKey: Self.lanReceiverProfilesDefaultsKey)
        }
    }

    func toggleSpeakCallResponses() {
        speakCallResponsesEnabled.toggle()
        persistSpeakCallResponsesEnabled()

        if !speakCallResponsesEnabled {
            stopSpokenCallResponse(restartListening: true)
        } else {
            playQueuedCallSpeechIfPossible()
        }
    }

    func toggleTextResponseMode() {
        textResponseModeEnabled.toggle()
        if textResponseModeEnabled && !callSessionActive {
            voiceCallModeEnabled = false
            persistVoiceCallMode()
        }
        persistTextResponseMode()
    }

    func openRecorderView() {
        stopSpokenCallResponse(restartListening: false)
        textResponseModeEnabled = false
        voiceCallModeEnabled = false
        persistTextResponseMode()
        persistVoiceCallMode()

        if callSessionActive {
            switch state {
            case .recording, .paused:
                cancelRecording()
            case .uploading:
                endingCallAfterCurrentTurn = true
                callSessionActive = false
            case .idle:
                callSessionActive = false
                endingCallAfterCurrentTurn = false
            }
        }

        if state == .idle {
            statusText = "Ready"
        }
    }

    func openTextThreadView() {
        stopSpokenCallResponse(restartListening: false)
        textResponseModeEnabled = true
        voiceCallModeEnabled = false
        persistTextResponseMode()
        persistVoiceCallMode()

        if callSessionActive {
            switch state {
            case .recording, .paused:
                cancelRecording()
            case .uploading:
                endingCallAfterCurrentTurn = true
                callSessionActive = false
            case .idle:
                callSessionActive = false
                endingCallAfterCurrentTurn = false
            }
        }
    }

    var effectiveRouteMetadataValue: String? {
        (textResponseModeEnabled || voiceCallModeEnabled || callSessionActive) ? RouteTarget.wezTerm.metadataValue : routeTarget.metadataValue
    }

    var effectiveRouteLabel: String {
        (textResponseModeEnabled || voiceCallModeEnabled || callSessionActive) ? RouteTarget.wezTerm.label : routeTarget.label
    }

    func toggleVoiceCallSession() async {
        if callSessionActive {
            await stopVoiceCallSession()
        } else {
            await startVoiceCallSession()
        }
    }

    func toggleCallView() async {
        if callSessionActive || voiceCallModeEnabled {
            voiceCallModeEnabled = false
            persistVoiceCallMode()
            await stopVoiceCallSession()
        } else {
            openCallView()
            await startVoiceCallSession()
        }
    }

    func openCallView() {
        textResponseModeEnabled = false
        persistTextResponseMode()
        voiceCallModeEnabled = true
        persistVoiceCallMode()
        playQueuedCallSpeechIfPossible()
    }

    func openCallViewAndStart() async {
        openCallView()
        await startVoiceCallSession()
    }

    func closeCallView() {
        guard !callSessionActive else { return }
        voiceCallModeEnabled = false
        persistVoiceCallMode()
        if state == .idle {
            statusText = "Ready"
        }
    }

    func setCallViewVisible(_ visible: Bool) {
        callViewVisible = visible
        if visible {
            playQueuedCallSpeechIfPossible()
        }
    }

    func stopSpokenCallResponse(restartListening: Bool) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        queuedCallSpeech.removeAll()
        queuedCallSpeechCount = 0

        guard restartListening else { return }
        voiceCallModeEnabled = true
        callSessionActive = true
        pendingCallResponseCount = 0
        isWaitingForCallResponse = false
        statusText = "Listening"
        persistVoiceCallMode()

        Task {
            await restartCallListeningWhenReady()
        }
    }

    func handleSceneBecameActive() async {
        appIsActive = true
        await recoverLiveTranscriptionIfNeeded()
        await recoverCallListeningIfNeeded()
    }

    func handleSceneMovedFromActive() {
        appIsActive = false
        if state == .recording || state == .paused {
            // Keep the recorder running in background, but tear down live speech services.
            stopLiveTranscription(keepTranscript: true)
        }
    }

    private func recoverLiveTranscriptionIfNeeded() async {
        guard state == .recording,
              audioRecorder?.isRecording == true,
              liveSpeechRecognitionTask == nil,
              !liveSpeechAudioEngine.isRunning
        else { return }

        let shouldResumeLiveTranscription = shouldUsePhoneTranscriptionForNewRecording
            || shouldUseAppleSpeechForNormalRecording
            || shouldShowLiveTranscriptPreviewForNewRecording

        guard shouldResumeLiveTranscription else { return }
        await startLiveTranscription(
            reset: false,
            requiresOnDevice: currentRecordingRequiresOnDeviceSpeech
        )
    }

    func recoverCallListeningIfNeeded() async {
        guard voiceCallModeEnabled || callSessionActive else { return }

        callSessionActive = true

        if speechSynthesizer.isSpeaking || !queuedCallSpeech.isEmpty {
            await restartCallListeningWhenReady()
            return
        }

        if state == .uploading || isWaitingForCallResponse {
            return
        }

        if state == .recording {
            if audioRecorder?.isRecording == true {
                if appIsActive && liveSpeechRecognitionTask == nil {
                    await startLiveTranscription(reset: false, requiresOnDevice: currentRecordingRequiresOnDeviceSpeech)
                }
                return
            }
            discardCurrentRecordingWithoutStoppingCall()
        } else if state == .paused {
            discardCurrentRecordingWithoutStoppingCall()
        }

        guard state == .idle else { return }
        await startRecording()
    }

    func sendTypedMessage(_ message: String) async {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        guard canSubmitTextJob else {
            appendThreadMessage(.status, "Connect Dropbox or configure direct text before sending typed messages.")
            statusText = "Text transport required"
            return
        }

        appendThreadMessage(.user, trimmedMessage)
        statusText = "Sending typed message..."

        if deliveryMode == .googleDriveFiles {
            await withUploadBackgroundTask {
                do {
                    let job = try await submitTextJob(
                        message: trimmedMessage,
                        submitAfterPaste: submitAfterPaste,
                        routeTarget: effectiveRouteMetadataValue,
                        responseMode: nil,
                        callSession: false
                    )
                    appendThreadMessage(.status, "Sent to Google Drive as \(job.jobID).text.json.")
                    statusText = "Sent to Google Drive"
                } catch {
                    appendThreadMessage(.status, "Typed message failed: \(error.localizedDescription)")
                    statusText = "Typed message failed"
                }
            }
            return
        }

        beginWaitingForResponse(.text)

        await withUploadBackgroundTask {
            do {
                let job = try await submitTextJob(
                    message: trimmedMessage,
                    submitAfterPaste: submitAfterPaste,
                    routeTarget: effectiveRouteMetadataValue,
                    responseMode: "text",
                    callSession: callSessionActive
                )
                appendThreadMessage(.status, "Waiting for response...")
                let response = try await waitForTextResponse(jobID: job.jobID, transport: job.transport)
                handleTextResponse(response, appendTranscript: false, context: .text)
            } catch {
                appendThreadMessage(.status, "Typed message failed: \(error.localizedDescription)")
                statusText = "Typed message failed"
            }
        }

        endWaitingForResponse(.text)
    }

    func startVoiceCallSession() async {
        voiceCallModeEnabled = true
        textResponseModeEnabled = false
        endingCallAfterCurrentTurn = false
        persistVoiceCallMode()
        persistTextResponseMode()

        if speechSynthesizer.isSpeaking || !queuedCallSpeech.isEmpty {
            callSessionActive = true
            statusText = "Playing response"
            Task {
                await restartCallListeningWhenReady()
            }
            return
        }

        guard state == .idle else {
            callSessionActive = true
            statusText = "Call active"
            return
        }

        callSessionActive = true
        await startRecording()
    }

    func stopVoiceCallSession() async {
        isHandlingCallTurn = false
        manualCallTurnSendRequested = false

        switch state {
        case .recording, .paused:
            cancelRecording()
            voiceCallModeEnabled = false
            persistVoiceCallMode()
            statusText = "Ready"
        case .uploading:
            endingCallAfterCurrentTurn = true
            callSessionActive = false
            voiceCallModeEnabled = false
            persistVoiceCallMode()
            statusText = "Ready"
        case .idle:
            callSessionActive = false
            endingCallAfterCurrentTurn = false
            voiceCallModeEnabled = false
            persistVoiceCallMode()
            statusText = "Ready"
        }
    }

    func activateRouteTarget(_ route: RouteTarget) async {
        guard let routeValue = route.metadataValue, route != .clipboard else { return }

        let priorStatus = statusText
        statusText = "Switching to \(route.label)"

        do {
            if deliveryMode != .dropbox {
                try await sendImmediateControlToServer(routeTarget: routeValue)
            } else if dropboxManager.isLinked {
                try await dropboxManager.sendImmediateControl(routeTarget: routeValue)
            } else {
                throw RecorderError.invalidServerURL
            }
            try? await Task.sleep(for: .seconds(1.2))
            if state == .idle && statusText == "Switching to \(route.label)" {
                statusText = priorStatus == "Ready" ? "Ready" : priorStatus
            }
        } catch {
            if dropboxManager.isLinked {
                do {
                    try await dropboxManager.sendImmediateControl(routeTarget: routeValue)
                    try? await Task.sleep(for: .seconds(1.2))
                    if state == .idle && statusText == "Switching to \(route.label)" {
                        statusText = priorStatus == "Ready" ? "Ready" : priorStatus
                    }
                    return
                } catch {
                    statusText = "Activation failed"
                }
            } else {
                statusText = "Activation failed"
            }
        }
    }

    func toggleRecording() async {
        switch state {
        case .idle:
            if voiceCallModeEnabled {
                await startVoiceCallSession()
                return
            }
            await startRecording()
        case .recording:
            if callSessionActive {
                await stopVoiceCallSession()
                return
            }
            await stopRecording()
        case .paused:
            resumeRecording()
        case .uploading:
            break
        }
    }

    func sendCurrentCallTurnNow() async {
        guard callSessionActive, state == .recording || state == .paused else { return }
        isHandlingCallTurn = true
        manualCallTurnSendRequested = true
        endingCallAfterCurrentTurn = false
        statusText = "Sending turn..."
        await stopRecording()
    }

    func togglePause() {
        switch state {
        case .recording:
            pauseRecording()
        case .paused:
            resumeRecording()
        case .idle, .uploading:
            break
        }
    }

    func startRecordingFromExternalTrigger() async {
        guard state == .idle else { return }
        if voiceCallModeEnabled {
            callSessionActive = true
            endingCallAfterCurrentTurn = false
        }
        await startRecording()
    }

    func cancelRecording() {
        guard state == .recording || state == .paused else { return }

        callSessionActive = false
        endingCallAfterCurrentTurn = false
        isHandlingCallTurn = false
        manualCallTurnSendRequested = false
        stopLiveTranscription(keepTranscript: false)
        stopTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        deactivateAudioSession()

        if let recordingURL = currentRecordingURL {
            cleanupRecordingFile(at: recordingURL)
        }

        currentRecordingURL = nil
        recordingStartedAt = nil
        accumulatedDuration = 0
        elapsedSeconds = 0
        speechDetectedInCurrentTurn = false
        lastSpeechDetectedAt = nil
        lastLiveTranscriptChangedAt = nil
        liveTranscriptionRequiredForCurrentTurn = false
        liveTranscriptionReadyForCurrentTurn = false
        currentRecordingUsesAppleSpeechNormalMode = false
        currentRecordingRequiresOnDeviceSpeech = false
        pausedByAudioInterruption = false
        liveTranscript = ""
        liveSpeechTranscriptPrefix = ""
        liveSpeechCurrentPartial = ""
        waveformSamples = Array(repeating: 0.08, count: 33)
        statusText = "Canceled"
        state = .idle
    }

    func cancelCallInteraction() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        queuedCallSpeech.removeAll()
        queuedCallSpeechCount = 0
        manualCallTurnSendRequested = false

        switch state {
        case .recording, .paused:
            cancelRecording()
            voiceCallModeEnabled = true
            persistVoiceCallMode()
            statusText = "Call ready"
        case .uploading:
            callSessionActive = false
            endingCallAfterCurrentTurn = true
            statusText = "Finishing current turn"
        case .idle:
            callSessionActive = false
            endingCallAfterCurrentTurn = false
            statusText = "Call ready"
        }
    }

    private func startRecording() async {
        if deliveryMode == .lanHTTP && !receiverReachability.isReady {
            statusText = "Receiver not checked"
        }

        do {
            try configureAudioSession()
            let granted = await requestMicrophonePermission()
            guard granted else {
                statusText = "Microphone permission was denied."
                return
            }

            let shouldStartPhoneTranscription = shouldUsePhoneTranscriptionForNewRecording
            let shouldUseAppleSpeechNormalMode = shouldUseAppleSpeechForNormalRecording
            let shouldShowLiveTranscriptPreview = shouldShowLiveTranscriptPreviewForNewRecording
            let shouldStartLiveTranscription = shouldStartPhoneTranscription
                || shouldUseAppleSpeechNormalMode
                || shouldShowLiveTranscriptPreview
            let shouldRequireLiveTranscription = shouldStartPhoneTranscription || shouldUseAppleSpeechNormalMode
            let fileURL = makeRecordingURL()
            let settings = recordingSettings(forPhoneWhisper: fileURL.pathExtension.lowercased() == "wav")

            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            guard audioRecorder?.record() == true else {
                statusText = "Recorder failed to start."
                return
            }

            currentRecordingURL = fileURL
            recordingStartedAt = Date()
            accumulatedDuration = 0
            elapsedSeconds = 0
            speechDetectedInCurrentTurn = false
            lastSpeechDetectedAt = nil
            lastLiveTranscriptChangedAt = nil
            isHandlingCallTurn = false
            liveTranscriptionRequiredForCurrentTurn = shouldRequireLiveTranscription
            liveTranscriptionReadyForCurrentTurn = !shouldRequireLiveTranscription
            currentRecordingUsesAppleSpeechNormalMode = shouldUseAppleSpeechNormalMode
            currentRecordingRequiresOnDeviceSpeech = shouldUseAppleSpeechNormalMode
            pausedByAudioInterruption = false
            waveformSamples = Array(repeating: 0.08, count: 33)
            state = .recording
            statusText = shouldStartPhoneTranscription
                ? (callSessionActive ? "Starting listener..." : "Starting speech...")
                : (shouldUseAppleSpeechNormalMode ? "Starting on-device speech..." : (callSessionActive ? "Call listening..." : "Recording..."))
            startTimer()
            if shouldStartLiveTranscription {
                await startLiveTranscription(reset: true, requiresOnDevice: shouldUseAppleSpeechNormalMode)
                liveTranscriptionReadyForCurrentTurn = !shouldRequireLiveTranscription || liveSpeechRecognitionTask != nil || liveSpeechAudioEngine.isRunning
                if state == .recording {
                    statusText = liveTranscriptionReadyForCurrentTurn
                        ? (callSessionActive ? "Call listening..." : "Recording...")
                        : statusText
                }
            } else {
                liveTranscript = ""
                liveSpeechTranscriptPrefix = ""
                liveSpeechCurrentPartial = ""
            }
        } catch {
            statusText = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        guard let recorder = audioRecorder, let recordingURL = currentRecordingURL else { return }
        let shouldTreatAsCallTurn = callSessionActive || endingCallAfterCurrentTurn
        let shouldEndCallAfterUpload = endingCallAfterCurrentTurn
        let shouldUseAppleSpeechNormalMode = !shouldTreatAsCallTurn && !textResponseModeEnabled && currentRecordingUsesAppleSpeechNormalMode
        let shouldClearNormalModeTranscript = !shouldTreatAsCallTurn && !textResponseModeEnabled && !shouldUseAppleSpeechNormalMode
        pausedByAudioInterruption = false
        stopLiveTranscription(keepTranscript: !shouldClearNormalModeTranscript)
        let isTextDrivenMode = shouldTreatAsCallTurn || textResponseModeEnabled
        let shouldUsePhoneTranscription = canSubmitTextJob && isTextDrivenMode
        var uploadedFilenameForResponse: String?
        var uploadedJobIDForResponse: String?
        var uploadedTextResponseTransport: TextResponseTransport = .dropbox
        var responseAlreadyHasTranscript = true
        let hasLiveTranscript = !cleanedTranscript(liveTranscript).isEmpty
        let shouldDiscardMissingTextTurn = isTextDrivenMode && !hasLiveTranscript

        if shouldDiscardMissingTextTurn {
            stopTimer()
            recorder.stop()
            audioRecorder = nil
            cleanupRecordingFile(at: recordingURL)
            currentRecordingURL = nil
            elapsedSeconds = 0
            accumulatedDuration = 0
            recordingStartedAt = nil
            speechDetectedInCurrentTurn = false
            lastSpeechDetectedAt = nil
            lastLiveTranscriptChangedAt = nil
            isHandlingCallTurn = false
            manualCallTurnSendRequested = false
            liveTranscriptionRequiredForCurrentTurn = false
            liveTranscriptionReadyForCurrentTurn = false
            currentRecordingUsesAppleSpeechNormalMode = false
            currentRecordingRequiresOnDeviceSpeech = false
            waveformSamples = Array(repeating: 0.08, count: 33)
            liveTranscript = ""
            liveSpeechTranscriptPrefix = ""
            liveSpeechCurrentPartial = ""
            state = .idle
            endingCallAfterCurrentTurn = false
            if shouldTreatAsCallTurn {
                if shouldEndCallAfterUpload {
                    callSessionActive = false
                    statusText = "Ready"
                } else {
                    statusText = "Listening"
                    await restartCallListeningWhenReady()
                }
            } else {
                statusText = "Ready"
            }
            return
        }

        if isTextDrivenMode && !canSubmitTextJob {
            stopTimer()
            recorder.stop()
            audioRecorder = nil
            cleanupRecordingFile(at: recordingURL)
            currentRecordingURL = nil
            elapsedSeconds = 0
            accumulatedDuration = 0
            recordingStartedAt = nil
            speechDetectedInCurrentTurn = false
            lastSpeechDetectedAt = nil
            lastLiveTranscriptChangedAt = nil
            isHandlingCallTurn = false
            manualCallTurnSendRequested = false
            liveTranscriptionRequiredForCurrentTurn = false
            liveTranscriptionReadyForCurrentTurn = false
            currentRecordingUsesAppleSpeechNormalMode = false
            currentRecordingRequiresOnDeviceSpeech = false
            waveformSamples = Array(repeating: 0.08, count: 33)
            liveTranscript = ""
            liveSpeechTranscriptPrefix = ""
            liveSpeechCurrentPartial = ""
            state = .idle
            endingCallAfterCurrentTurn = false
            statusText = "Text transport required"
            if shouldTreatAsCallTurn && !shouldEndCallAfterUpload {
                await restartCallListeningWhenReady()
            }
            return
        }

        if shouldUseAppleSpeechNormalMode {
            let routeTargetValue = effectiveRouteMetadataValue
            let submitAfterPasteValue = submitAfterPaste
            let transcript = currentLiveTranscriptForSubmission()

            stopTimer()
            recorder.stop()
            audioRecorder = nil
            deactivateAudioSession()
            cleanupRecordingFile(at: recordingURL)
            currentRecordingURL = nil
            elapsedSeconds = 0
            accumulatedDuration = 0
            recordingStartedAt = nil
            speechDetectedInCurrentTurn = false
            lastSpeechDetectedAt = nil
            lastLiveTranscriptChangedAt = nil
            isHandlingCallTurn = false
            manualCallTurnSendRequested = false
            liveTranscriptionRequiredForCurrentTurn = false
            liveTranscriptionReadyForCurrentTurn = false
            currentRecordingUsesAppleSpeechNormalMode = false
            currentRecordingRequiresOnDeviceSpeech = false
            waveformSamples = Array(repeating: 0.08, count: 33)
            liveTranscript = ""
            liveSpeechTranscriptPrefix = ""
            liveSpeechCurrentPartial = ""
            state = .idle
            endingCallAfterCurrentTurn = false

            guard !transcript.isEmpty else {
                statusText = "No transcript captured"
                return
            }

            statusText = "Ready"
            startBackgroundTranscriptUpload(
                transcript: transcript,
                routeTargetValue: routeTargetValue,
                submitAfterPasteValue: submitAfterPasteValue
            )
            return
        }

        if !isTextDrivenMode {
            let routeTargetValue = effectiveRouteMetadataValue
            let submitAfterPasteValue = submitAfterPaste

            stopTimer()
            recorder.stop()
            audioRecorder = nil
            deactivateAudioSession()
            currentRecordingURL = nil
            elapsedSeconds = 0
            accumulatedDuration = 0
            recordingStartedAt = nil
            speechDetectedInCurrentTurn = false
            lastSpeechDetectedAt = nil
            lastLiveTranscriptChangedAt = nil
            isHandlingCallTurn = false
            manualCallTurnSendRequested = false
            liveTranscriptionRequiredForCurrentTurn = false
            liveTranscriptionReadyForCurrentTurn = false
            currentRecordingUsesAppleSpeechNormalMode = false
            currentRecordingRequiresOnDeviceSpeech = false
            waveformSamples = Array(repeating: 0.08, count: 33)
            liveTranscript = ""
            liveSpeechTranscriptPrefix = ""
            liveSpeechCurrentPartial = ""
            state = .idle
            endingCallAfterCurrentTurn = false
            statusText = "Ready"

            startBackgroundRecordingUpload(
                fileURL: recordingURL,
                routeTargetValue: routeTargetValue,
                submitAfterPasteValue: submitAfterPasteValue
            )
            return
        }

        state = .uploading
        statusText = shouldUsePhoneTranscription
            ? (hasLiveTranscript ? "Sending transcript..." : "Transcribing on iPhone...")
            : (shouldTreatAsCallTurn ? "Call sending..." : "Uploading...")
        stopTimer()
        recorder.stop()
        audioRecorder = nil
        if shouldTreatAsCallTurn {
            try? configureCallAudioSessionForPlayback()
        } else {
            deactivateAudioSession()
        }

        await withUploadBackgroundTask {
            do {
                if shouldUsePhoneTranscription {
                    let job = try await uploadPhoneTranscribedTurn(
                        fileURL: recordingURL,
                        shouldTreatAsCallTurn: shouldTreatAsCallTurn
                    )
                    lastUploadedFilename = "\(job.jobID).text.json"
                    uploadedJobIDForResponse = job.jobID
                    uploadedTextResponseTransport = job.transport
                    responseAlreadyHasTranscript = false
                    statusText = shouldTreatAsCallTurn ? "Call turn sent" : "Transcript sent"
                } else {
                    let filename = try await uploadRecording(
                        fileURL: recordingURL,
                        forceTextResponse: shouldTreatAsCallTurn,
                        forcedRouteTarget: shouldTreatAsCallTurn ? .wezTerm : nil,
                        callSessionMetadata: shouldTreatAsCallTurn
                    )
                    lastUploadedFilename = filename
                    uploadedFilenameForResponse = filename
                    statusText = shouldTreatAsCallTurn ? "Call turn sent" : "Uploaded: \(filename)"
                }
            } catch {
                statusText = shouldUsePhoneTranscription ? "Phone transcription failed" : (shouldTreatAsCallTurn ? "Call upload failed" : "Upload failed: \(error.localizedDescription)")
            }
        }

        cleanupRecordingFile(at: recordingURL)
        currentRecordingURL = nil
        elapsedSeconds = 0
        accumulatedDuration = 0
        recordingStartedAt = nil
        speechDetectedInCurrentTurn = false
        lastSpeechDetectedAt = nil
        lastLiveTranscriptChangedAt = nil
        isHandlingCallTurn = false
        manualCallTurnSendRequested = false
        liveTranscriptionRequiredForCurrentTurn = false
        liveTranscriptionReadyForCurrentTurn = false
        currentRecordingUsesAppleSpeechNormalMode = false
        currentRecordingRequiresOnDeviceSpeech = false
        waveformSamples = Array(repeating: 0.08, count: 33)
        state = .idle
        endingCallAfterCurrentTurn = false

        if shouldClearNormalModeTranscript {
            liveTranscript = ""
            liveSpeechTranscriptPrefix = ""
            liveSpeechCurrentPartial = ""
        }

        if shouldTreatAsCallTurn {
            if let jobID = uploadedJobIDForResponse {
                Task {
                    await withBackgroundTask(named: "Wait for call response") {
                        await waitForTextResponse(
                            jobID: jobID,
                            context: .call,
                            appendTranscript: responseAlreadyHasTranscript,
                            transport: uploadedTextResponseTransport
                        )
                        if shouldEndCallAfterUpload {
                            callSessionActive = false
                            statusText = voiceCallModeEnabled ? "Call ready" : "Ready"
                            return
                        }
                        await restartCallListeningWhenReady()
                    }
                }
            } else if dropboxManager.isReadyForUpload, let filename = uploadedFilenameForResponse {
                Task {
                    await withBackgroundTask(named: "Wait for call response") {
                        await waitForTextResponse(filename: filename, context: .call)
                        if shouldEndCallAfterUpload {
                            callSessionActive = false
                            statusText = voiceCallModeEnabled ? "Call ready" : "Ready"
                            return
                        }
                        await restartCallListeningWhenReady()
                    }
                }
            } else {
                if shouldEndCallAfterUpload {
                    callSessionActive = false
                    statusText = voiceCallModeEnabled ? "Call ready" : "Ready"
                    return
                }
                await restartCallListeningWhenReady()
            }
            return
        }

        if textResponseModeEnabled, let jobID = uploadedJobIDForResponse {
            Task {
                await waitForTextResponse(
                    jobID: jobID,
                    context: .text,
                    appendTranscript: responseAlreadyHasTranscript,
                    transport: uploadedTextResponseTransport
                )
            }
        } else if textResponseModeEnabled, dropboxManager.isReadyForUpload, let filename = uploadedFilenameForResponse {
            Task {
                await waitForTextResponse(filename: filename, context: .text)
            }
        }
    }

    private func pauseRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        pausedByAudioInterruption = false
        recorder.pause()
        stopLiveTranscription(keepTranscript: true)
        accumulatedDuration = elapsedSeconds
        recordingStartedAt = nil
        stopTimer()
        state = .paused
        statusText = "Paused"
    }

    private func resumeRecording() {
        guard let recorder = audioRecorder else { return }
        try? configureAudioSession()
        guard recorder.record() else {
            statusText = "Could not resume recording."
            return
        }

        recordingStartedAt = Date()
        state = .recording
        statusText = callSessionActive ? "Call listening..." : "Recording..."
        startTimer()
        if appIsActive {
            Task {
                await startLiveTranscription(reset: false, requiresOnDevice: currentRecordingRequiresOnDeviceSpeech)
            }
        }
    }

    private func configureAudioSession() throws {
        try configureCallAudioSessionForRecording()
    }

    private func configureCallAudioSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        let shouldUseExternalAudio = shouldPreferExternalAudio(session)
        let options = audioSessionOptions(duckOthers: false, defaultToSpeaker: !shouldUseExternalAudio)

        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: options
        )
        try preferExternalAudioInputIfAvailable(session)
        try session.setActive(true)
        applyPreferredCallOutputRoute(session)
    }

    private func configureCallAudioSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        let shouldUseExternalAudio = shouldPreferExternalAudio(session)
        let options = audioSessionOptions(duckOthers: true, defaultToSpeaker: !shouldUseExternalAudio)

        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: options
        )
        try preferExternalAudioInputIfAvailable(session)
        try session.setActive(true)
        applyPreferredCallOutputRoute(session)
    }

    private func applyPreferredCallOutputRoute(_ session: AVAudioSession) {
        let hasExternalOutput = currentRouteUsesExternalAudio(session)

        do {
            try session.overrideOutputAudioPort(hasExternalOutput ? .none : .speaker)
        } catch {
            // Route changes can fail transiently while AirPods connect/disconnect; the route-change observer will retry.
        }
    }

    private func audioSessionOptions(duckOthers: Bool, defaultToSpeaker: Bool) -> AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        if duckOthers {
            options.insert(.duckOthers)
        }
        if defaultToSpeaker {
            options.insert(.defaultToSpeaker)
        }
        return options
    }

    private func shouldPreferExternalAudio(_ session: AVAudioSession) -> Bool {
        currentRouteUsesExternalAudio(session) || availableInputsContainExternalAudio(session)
    }

    private func currentRouteUsesExternalAudio(_ session: AVAudioSession) -> Bool {
        session.currentRoute.outputs.contains { externalOutputPorts.contains($0.portType) }
    }

    private func availableInputsContainExternalAudio(_ session: AVAudioSession) -> Bool {
        session.availableInputs?.contains { externalInputPorts.contains($0.portType) } == true
    }

    private func preferExternalAudioInputIfAvailable(_ session: AVAudioSession) throws {
        guard let input = session.availableInputs?.first(where: { externalInputPorts.contains($0.portType) }) else {
            return
        }

        try session.setPreferredInput(input)
    }

    private var externalOutputPorts: Set<AVAudioSession.Port> {
        [
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE,
            .headphones
        ]
    }

    private var externalInputPorts: Set<AVAudioSession.Port> {
        [
            .bluetoothHFP,
            .bluetoothLE,
            .headsetMic
        ]
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechRecognitionPermission() async -> Bool {
        if liveSpeechAuthorizationDenied {
            return false
        }

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let authorized = status == .authorized
        liveSpeechAuthorizationDenied = !authorized
        return authorized
    }

    private func makeRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let filename = "ios_recording_\(formatter.string(from: Date()))_\(suffix).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    private func recordingSettings(forPhoneWhisper: Bool) -> [String: Any] {
        if forPhoneWhisper {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        }

        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let liveDuration = self.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                self.elapsedSeconds = self.accumulatedDuration + liveDuration
                self.captureMeterSample()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startLiveTranscription(reset: Bool, requiresOnDevice: Bool = false) async {
        guard liveSpeechRecognitionTask == nil,
              !liveSpeechAudioEngine.isRunning
        else { return }

        guard let liveSpeechRecognizer, liveSpeechRecognizer.isAvailable else {
            if callSessionActive || textResponseModeEnabled {
                statusText = "Speech recognition unavailable"
            }
            return
        }

        if requiresOnDevice, !liveSpeechRecognizer.supportsOnDeviceRecognition {
            statusText = "On-device speech unavailable"
            return
        }

        guard await requestSpeechRecognitionPermission() else {
            if callSessionActive || textResponseModeEnabled {
                statusText = "Speech permission needed"
            }
            return
        }

        if reset {
            liveSpeechTranscriptPrefix = ""
            liveSpeechCurrentPartial = ""
            liveTranscript = ""
            lastLiveTranscriptChangedAt = nil
        } else {
            preserveLiveTranscriptForContinuation()
        }

        liveSpeechSessionID += 1
        let sessionID = liveSpeechSessionID
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        if requiresOnDevice {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        liveSpeechRecognitionRequest = recognitionRequest

        liveSpeechRecognitionTask = liveSpeechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.liveSpeechSessionID == sessionID else { return }

                if let result {
                    let partialTranscript = self.cleanedTranscript(result.bestTranscription.formattedString)
                    if !partialTranscript.isEmpty {
                        self.updateLiveSpeechPartial(partialTranscript)
                    }

                    if result.isFinal {
                        self.commitLiveSpeechPartial()
                    }
                }

                if error != nil || result?.isFinal == true {
                    if error != nil, self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.statusText = "Speech recognition stopped"
                    }
                    let shouldRestart = self.shouldRestartLiveTranscriptionAfterSegment
                    self.finishLiveTranscriptionSession(cancelTask: false, sessionID: sessionID)
                    if shouldRestart {
                        try? await Task.sleep(for: .milliseconds(120))
                        if self.shouldRestartLiveTranscriptionAfterSegment {
                            await self.startLiveTranscription(
                                reset: false,
                                requiresOnDevice: self.currentRecordingRequiresOnDeviceSpeech
                            )
                        }
                    }
                }
            }
        }

        let inputNode = liveSpeechAudioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            if callSessionActive || textResponseModeEnabled {
                statusText = "Speech input unavailable"
            }
            finishLiveTranscriptionSession(cancelTask: true)
            return
        }

        if liveSpeechTapInstalled {
            inputNode.removeTap(onBus: 0)
            liveSpeechTapInstalled = false
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self, weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)

            let normalizedPower = Self.normalizedMeterLevel(from: buffer)
            Task { @MainActor [weak self] in
                guard let self, self.shouldUseLiveTranscriptionMetering else { return }
                self.appendWaveformSample(normalizedPower)
            }
        }
        liveSpeechTapInstalled = true

        do {
            liveSpeechAudioEngine.prepare()
            try liveSpeechAudioEngine.start()
        } catch {
            if callSessionActive || textResponseModeEnabled {
                statusText = "Speech engine failed"
            }
            finishLiveTranscriptionSession(cancelTask: true)
        }
    }

    private func stopLiveTranscription(keepTranscript: Bool) {
        if keepTranscript {
            preserveLiveTranscriptForContinuation()
        } else {
            liveSpeechTranscriptPrefix = ""
            liveSpeechCurrentPartial = ""
            liveTranscript = ""
            lastLiveTranscriptChangedAt = nil
        }

        finishLiveTranscriptionSession(cancelTask: true)
    }

    private var shouldRestartLiveTranscriptionAfterSegment: Bool {
        currentRecordingUsesAppleSpeechNormalMode
            && state == .recording
            && audioRecorder?.isRecording == true
            && currentRecordingURL != nil
    }

    private func currentLiveTranscriptForSubmission() -> String {
        let displayed = cleanedTranscript(liveTranscript)
        if !displayed.isEmpty {
            return cleanedTranscript(squashedRepeatedLiveTranscript(displayed))
        }
        return cleanedTranscript(squashedRepeatedLiveTranscript(
            joinedLiveTranscript(prefix: liveSpeechTranscriptPrefix, partial: liveSpeechCurrentPartial)
        ))
    }

    private func finishLiveTranscriptionSession(cancelTask: Bool, sessionID: Int? = nil) {
        if let sessionID, sessionID != liveSpeechSessionID {
            return
        }

        if liveSpeechAudioEngine.isRunning {
            liveSpeechAudioEngine.stop()
        }

        if liveSpeechTapInstalled {
            liveSpeechAudioEngine.inputNode.removeTap(onBus: 0)
            liveSpeechTapInstalled = false
        }

        liveSpeechRecognitionRequest?.endAudio()
        if cancelTask {
            liveSpeechRecognitionTask?.cancel()
        }
        liveSpeechRecognitionRequest = nil
        liveSpeechRecognitionTask = nil

        if cancelTask {
            liveSpeechSessionID += 1
        }
    }

    private func joinedLiveTranscript(prefix: String, partial: String) -> String {
        let cleanPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanPrefix.isEmpty {
            return cleanPartial
        }
        if cleanPartial.isEmpty {
            return cleanPrefix
        }
        if cleanPartial.localizedCaseInsensitiveCompare(cleanPrefix) == .orderedSame {
            return cleanPrefix
        }
        if cleanPartial.localizedCaseInsensitiveContains(cleanPrefix),
           cleanPartial.lowercased().hasPrefix(cleanPrefix.lowercased()) {
            return cleanPartial
        }
        return "\(cleanPrefix) \(cleanPartial)"
    }

    private func updateLiveSpeechPartial(_ partial: String) {
        let incoming = liveSpeechPartialWithoutCommittedPrefix(partial)
        guard !incoming.isEmpty else { return }

        let currentPartial = liveSpeechCurrentPartial.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentPartial.isEmpty {
            liveSpeechCurrentPartial = incoming
        } else if incoming.localizedCaseInsensitiveCompare(currentPartial) == .orderedSame {
            liveSpeechCurrentPartial = currentPartial
        } else if incoming.localizedCaseInsensitiveContains(currentPartial),
                  incoming.lowercased().hasPrefix(currentPartial.lowercased()) {
            liveSpeechCurrentPartial = incoming
        } else if currentPartial.localizedCaseInsensitiveContains(incoming) {
            liveSpeechCurrentPartial = currentPartial
        } else if isLikelyLiveSpeechRevision(current: currentPartial, incoming: incoming) {
            liveSpeechCurrentPartial = incoming.count + 12 >= currentPartial.count ? incoming : currentPartial
        } else {
            commitLiveSpeechPartial()
            liveSpeechCurrentPartial = incoming
        }

        liveTranscript = joinedLiveTranscript(prefix: liveSpeechTranscriptPrefix, partial: liveSpeechCurrentPartial)
        lastLiveTranscriptChangedAt = Date()
    }

    private func commitLiveSpeechPartial() {
        let currentPartial = liveSpeechCurrentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentPartial.isEmpty {
            liveSpeechTranscriptPrefix = joinedLiveTranscript(prefix: liveSpeechTranscriptPrefix, partial: currentPartial)
            liveSpeechCurrentPartial = ""
            liveTranscript = liveSpeechTranscriptPrefix
            return
        }

        preserveLiveTranscriptForContinuation()
    }

    private func preserveLiveTranscriptForContinuation() {
        let display = cleanedTranscript(liveTranscript)
        if !display.isEmpty {
            liveSpeechTranscriptPrefix = display
        }
        liveSpeechCurrentPartial = ""
        liveTranscript = liveSpeechTranscriptPrefix
    }

    private func liveSpeechPartialWithoutCommittedPrefix(_ partial: String) -> String {
        let cleanPartial = cleanedTranscript(partial)
        let prefix = liveSpeechTranscriptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prefix.isEmpty else {
            return cleanPartial
        }

        if cleanPartial.localizedCaseInsensitiveCompare(prefix) == .orderedSame {
            return ""
        }

        if cleanPartial.localizedCaseInsensitiveContains(prefix),
           cleanPartial.lowercased().hasPrefix(prefix.lowercased()),
           cleanPartial.count > prefix.count {
            let remainderStart = cleanPartial.index(cleanPartial.startIndex, offsetBy: prefix.count)
            return cleanPartial[remainderStart...]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:")))
        }

        return cleanPartial
    }

    private func isLikelyLiveSpeechRevision(current: String, incoming: String) -> Bool {
        let currentWords = normalizedSpeechWords(current)
        let incomingWords = normalizedSpeechWords(incoming)
        let sharedWordCount = commonPrefixWordCount(currentWords, incomingWords)
        let shorterWordCount = min(currentWords.count, incomingWords.count)

        if shorterWordCount >= 4, sharedWordCount >= 4 {
            return true
        }
        if shorterWordCount >= 3, sharedWordCount >= 3 {
            return true
        }

        let currentNormalized = currentWords.joined(separator: " ")
        let incomingNormalized = incomingWords.joined(separator: " ")
        let sharedCharacterCount = commonPrefixCharacterCount(currentNormalized, incomingNormalized)
        let shorterCharacterCount = min(currentNormalized.count, incomingNormalized.count)

        if shorterCharacterCount >= 24, sharedCharacterCount >= 24 {
            return true
        }
        return shorterCharacterCount >= 12
            && Double(sharedCharacterCount) / Double(shorterCharacterCount) >= 0.45
    }

    private func squashedRepeatedLiveTranscript(_ transcript: String) -> String {
        let rawWords = transcript.split(whereSeparator: { $0.isWhitespace })
        guard rawWords.count >= 18 else { return transcript }

        let normalizedWords = rawWords.map { normalizedSpeechToken(String($0)) }
        let seedLength = min(5, normalizedWords.count)
        guard seedLength >= 3 else { return transcript }

        let seed = Array(normalizedWords.prefix(seedLength))
        var repeatedStartIndices: [Int] = []
        for index in 0...(normalizedWords.count - seedLength) {
            if Array(normalizedWords[index..<(index + seedLength)]) == seed {
                repeatedStartIndices.append(index)
            }
        }

        guard repeatedStartIndices.count >= 3, let lastStart = repeatedStartIndices.last, lastStart > 0 else {
            return transcript
        }

        return rawWords[lastStart...].joined(separator: " ")
    }

    private func normalizedSpeechWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { normalizedSpeechToken(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func normalizedSpeechToken(_ token: String) -> String {
        token.lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private func commonPrefixWordCount(_ lhs: [String], _ rhs: [String]) -> Int {
        var count = 0
        for (left, right) in zip(lhs, rhs) {
            guard left == right else { break }
            count += 1
        }
        return count
    }

    private func commonPrefixCharacterCount(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        var leftIndex = lhs.startIndex
        var rightIndex = rhs.startIndex
        while leftIndex < lhs.endIndex, rightIndex < rhs.endIndex {
            guard lhs[leftIndex] == rhs[rightIndex] else { break }
            count += 1
            leftIndex = lhs.index(after: leftIndex)
            rightIndex = rhs.index(after: rightIndex)
        }
        return count
    }

    private nonisolated static func normalizedMeterLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0.08 }

        let samples = channels[0]
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = samples[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))
        guard rms.isFinite, rms > 0 else { return 0.06 }
        let db = 20 * log10(rms)
        return normalizedMeterLevel(from: db)
    }

    private func captureMeterSample() {
        guard let recorder = audioRecorder else { return }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalizedPower = Self.normalizedMeterLevel(from: averagePower)
        appendWaveformSample(normalizedPower)

        evaluateCallTurn(with: normalizedPower)
    }

    private func appendWaveformSample(_ normalizedPower: CGFloat) {
        waveformSamples.append(normalizedPower)
        if waveformSamples.count > 33 {
            waveformSamples.removeFirst(waveformSamples.count - 33)
        }
    }

    private func evaluateCallTurn(with normalizedPower: CGFloat) {
        guard callSessionActive, state == .recording, !isHandlingCallTurn else { return }
        if liveTranscriptionRequiredForCurrentTurn, !liveTranscriptionReadyForCurrentTurn {
            return
        }

        let now = Date()
        let currentDuration = elapsedSeconds
        if normalizedPower >= Self.callSpeechThreshold {
            speechDetectedInCurrentTurn = true
            lastSpeechDetectedAt = now
        }

        if speechDetectedInCurrentTurn,
           let lastSpeechDetectedAt,
           currentDuration >= Self.callMinimumTurnDuration,
           now.timeIntervalSince(lastSpeechDetectedAt) >= Self.callSilenceDuration {
            isHandlingCallTurn = true
            Task { await stopRecording() }
            return
        }

        if !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let lastLiveTranscriptChangedAt,
           currentDuration >= Self.callMinimumTurnDuration,
           now.timeIntervalSince(lastLiveTranscriptChangedAt) >= Self.liveTranscriptPauseDuration {
            isHandlingCallTurn = true
            Task { await stopRecording() }
            return
        }

        if speechDetectedInCurrentTurn && currentDuration >= Self.callMaximumTurnDuration {
            isHandlingCallTurn = true
            Task { await stopRecording() }
            return
        }

        if !speechDetectedInCurrentTurn && currentDuration >= Self.callIdleRecycleDuration {
            isHandlingCallTurn = true
            Task { await recycleSilentCallTurn() }
        }
    }

    private func recycleSilentCallTurn() async {
        guard callSessionActive, let recorder = audioRecorder, let recordingURL = currentRecordingURL else {
            isHandlingCallTurn = false
            return
        }

        stopTimer()
        recorder.stop()
        audioRecorder = nil
        deactivateAudioSession()
        cleanupRecordingFile(at: recordingURL)

        currentRecordingURL = nil
        elapsedSeconds = 0
        accumulatedDuration = 0
        recordingStartedAt = nil
        speechDetectedInCurrentTurn = false
        lastSpeechDetectedAt = nil
        lastLiveTranscriptChangedAt = nil
        liveTranscriptionRequiredForCurrentTurn = false
        liveTranscriptionReadyForCurrentTurn = false
        waveformSamples = Array(repeating: 0.08, count: 33)
        state = .idle
        isHandlingCallTurn = false
        manualCallTurnSendRequested = false

        try? await Task.sleep(for: .milliseconds(250))
        guard callSessionActive else { return }
        await startRecording()
    }

    private nonisolated static func normalizedMeterLevel(from averagePower: Float) -> CGFloat {
        guard averagePower.isFinite else { return 0.08 }
        let minDb: Float = -50
        if averagePower <= minDb { return 0.06 }
        let scaled = (averagePower - minDb) / abs(minDb)
        return CGFloat(max(0.06, min(1.0, scaled)))
    }

    private func uploadRecording(
        fileURL: URL,
        forceTextResponse: Bool = false,
        forcedRouteTarget: RouteTarget? = nil,
        callSessionMetadata: Bool? = nil
    ) async throws -> String {
        let shouldRequestTextResponse = forceTextResponse || textResponseModeEnabled || callSessionActive || voiceCallModeEnabled
        let routeTargetValue = forcedRouteTarget?.metadataValue ?? effectiveRouteMetadataValue
        let callSessionValue = callSessionMetadata ?? callSessionActive

        if deliveryMode == .dropbox {
            guard dropboxManager.isReadyForUpload else {
                throw RecorderError.serverError("Dropbox is not connected.")
            }

            return try await dropboxManager.uploadRecording(
                fileURL: fileURL,
                submitAfterPaste: submitAfterPaste,
                routeTarget: routeTargetValue,
                responseMode: shouldRequestTextResponse ? "text" : nil,
                callSession: callSessionValue
            )
        }

        if deliveryMode == .googleDriveFiles {
            return try await googleDriveManager.uploadRecording(
                fileURL: fileURL,
                submitAfterPaste: submitAfterPaste,
                routeTarget: routeTargetValue,
                responseMode: shouldRequestTextResponse ? "text" : nil,
                callSession: callSessionValue
            )
        }

        return try await uploadRecordingToServer(
            fileURL: fileURL,
            routeTargetValue: routeTargetValue,
            shouldRequestTextResponse: shouldRequestTextResponse,
            callSessionValue: callSessionValue
        )
    }

    private func startBackgroundRecordingUpload(
        fileURL: URL,
        routeTargetValue: String?,
        submitAfterPasteValue: Bool
    ) {
        pendingBackgroundUploadCount += 1
        lastBackgroundUploadError = nil

        Task {
            var didUpload = false
            await withUploadBackgroundTask {
                do {
                    let filename = try await uploadFinishedRecording(
                        fileURL: fileURL,
                        routeTargetValue: routeTargetValue,
                        submitAfterPasteValue: submitAfterPasteValue
                    )
                    didUpload = true
                    lastUploadedFilename = filename
                    if state == .idle {
                        statusText = "Ready"
                    }
                } catch {
                    lastBackgroundUploadError = error.localizedDescription
                    if state == .idle {
                        statusText = "Upload failed: \(error.localizedDescription)"
                    }
                }
            }

            if didUpload {
                cleanupRecordingFile(at: fileURL)
            }
            pendingBackgroundUploadCount = max(0, pendingBackgroundUploadCount - 1)
        }
    }

    private func startBackgroundTranscriptUpload(
        transcript: String,
        routeTargetValue: String?,
        submitAfterPasteValue: Bool
    ) {
        pendingBackgroundUploadCount += 1
        lastBackgroundUploadError = nil

        Task {
            var didUpload = false
            await withUploadBackgroundTask {
                do {
                    let job = try await submitTextJob(
                        message: transcript,
                        submitAfterPaste: submitAfterPasteValue,
                        routeTarget: routeTargetValue,
                        responseMode: nil,
                        callSession: false
                    )
                    didUpload = true
                    lastUploadedFilename = "\(job.jobID).text.json"
                    if state == .idle {
                        statusText = "Ready"
                    }
                } catch {
                    lastBackgroundUploadError = error.localizedDescription
                    if state == .idle {
                        statusText = "Text upload failed: \(error.localizedDescription)"
                    }
                }
            }

            if !didUpload, state == .idle {
                statusText = lastBackgroundUploadError.map { "Text upload failed: \($0)" } ?? "Text upload failed"
            }
            pendingBackgroundUploadCount = max(0, pendingBackgroundUploadCount - 1)
        }
    }

    private func uploadFinishedRecording(
        fileURL: URL,
        routeTargetValue: String?,
        submitAfterPasteValue: Bool
    ) async throws -> String {
        if deliveryMode == .lanHTTP || deliveryMode == .cloudflareHTTP {
            return try await uploadRecordingToServer(
                fileURL: fileURL,
                routeTargetValue: routeTargetValue,
                shouldRequestTextResponse: false,
                callSessionValue: false,
                submitAfterPasteValue: submitAfterPasteValue
            )
        }

        if deliveryMode == .googleDriveFiles {
            return try await googleDriveManager.uploadRecording(
                fileURL: fileURL,
                submitAfterPaste: submitAfterPasteValue,
                routeTarget: routeTargetValue,
                responseMode: nil,
                callSession: false
            )
        }

        guard dropboxManager.isReadyForUpload else {
            throw RecorderError.serverError("Dropbox is not connected.")
        }
        return try await dropboxManager.uploadRecording(
            fileURL: fileURL,
            submitAfterPaste: submitAfterPasteValue,
            routeTarget: routeTargetValue,
            responseMode: nil,
            callSession: false
        )
    }

    private func uploadRecordingToServer(
        fileURL: URL,
        routeTargetValue: String?,
        shouldRequestTextResponse: Bool,
        callSessionValue: Bool,
        submitAfterPasteValue: Bool? = nil
    ) async throws -> String {
        let serverConfig = try uploadServerConfiguration()
        let baseURL = serverConfig.baseURL
        let apiToken = serverConfig.apiToken

        guard !baseURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecorderError.invalidServerURL
        }

        let uploadURL = baseURL.appending(path: "api/upload")
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let apiToken, !apiToken.isEmpty {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/mp4\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"submit_after_paste\"\r\n\r\n")
        body.append((submitAfterPasteValue ?? submitAfterPaste) ? "1" : "0")
        body.append("\r\n--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"call_session\"\r\n\r\n")
        body.append(callSessionValue ? "1" : "0")
        if shouldRequestTextResponse {
            body.append("\r\n--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"response_mode\"\r\n\r\n")
            body.append("text")
        }
        if let routeTarget = routeTargetValue {
            body.append("\r\n--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"route_target\"\r\n\r\n")
            body.append(routeTarget)
        }
        body.append("\r\n--\(boundary)--\r\n")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecorderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw RecorderError.serverError(serverMessage)
        }

        let payload = try JSONDecoder().decode(UploadResponse.self, from: data)
        return payload.filename
    }

    private func uploadServerConfiguration() throws -> (baseURL: URL, apiToken: String?) {
        guard let baseURL = activeHTTPBaseURL() else {
            throw RecorderError.invalidServerURL
        }
        let apiToken = directTextAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return (baseURL, apiToken.isEmpty ? nil : apiToken)
    }

    private func activeHTTPBaseURL() -> URL? {
        let rawURL: String
        switch deliveryMode {
        case .dropbox, .googleDriveFiles:
            return nil
        case .lanHTTP:
            rawURL = serverURLString
        case .cloudflareHTTP:
            rawURL = cloudflareServerURLString
        }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return nil }
        return URL(string: trimmedURL)
    }

    private func uploadPhoneTranscribedTurn(fileURL _: URL, shouldTreatAsCallTurn: Bool) async throws -> SubmittedTextJob {
        let transcript = currentLiveTranscriptForSubmission()
        guard !transcript.isEmpty else {
            throw LocalWhisperError.transcriptionFailed
        }

        appendThreadMessage(.user, transcript)
        liveTranscript = ""
        liveSpeechTranscriptPrefix = ""
        liveSpeechCurrentPartial = ""
        lastLiveTranscriptChangedAt = nil
        statusText = "Sending transcript..."

        return try await submitTranscriptTextJob(transcript, shouldTreatAsCallTurn: shouldTreatAsCallTurn)
    }

    private func submitTranscriptTextJob(_ transcript: String, shouldTreatAsCallTurn: Bool) async throws -> SubmittedTextJob {
        return try await submitTextJob(
            message: transcript,
            submitAfterPaste: submitAfterPaste,
            routeTarget: shouldTreatAsCallTurn ? RouteTarget.wezTerm.metadataValue : effectiveRouteMetadataValue,
            responseMode: "text",
            callSession: shouldTreatAsCallTurn
        )
    }

    private enum ResponseContext {
        case text
        case call
    }

    private enum TextResponseTransport {
        case dropbox
        case direct
        case googleDrive
    }

    private struct SubmittedTextJob {
        let jobID: String
        let transport: TextResponseTransport
    }

    private func submitTextJob(
        message: String,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) async throws -> SubmittedTextJob {
        if deliveryMode == .googleDriveFiles {
            guard responseMode == nil else {
                throw RecorderError.serverError("Google Drive delivery is one-way for now. Use Dropbox, LAN, or Cloudflare for response mode.")
            }

            let jobID = try await googleDriveManager.uploadTypedMessage(
                message: message,
                submitAfterPaste: submitAfterPaste,
                routeTarget: routeTarget,
                responseMode: responseMode,
                callSession: callSession
            )
            return SubmittedTextJob(jobID: jobID, transport: .googleDrive)
        }

        if isDirectTextTransportReady {
            do {
                let jobID = try await submitDirectTextJob(
                    message: message,
                    submitAfterPaste: submitAfterPaste,
                    routeTarget: routeTarget,
                    responseMode: responseMode,
                    callSession: callSession
                )
                return SubmittedTextJob(jobID: jobID, transport: .direct)
            } catch {
                throw error
            }
        }

        guard deliveryMode == .dropbox else {
            throw RecorderError.invalidServerURL
        }

        let jobID = try await dropboxManager.uploadTypedMessage(
            message: message,
            submitAfterPaste: submitAfterPaste,
            routeTarget: routeTarget,
            responseMode: responseMode,
            callSession: callSession
        )
        return SubmittedTextJob(jobID: jobID, transport: .dropbox)
    }

    private func submitDirectTextJob(
        message: String,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) async throws -> String {
        let jobID = makeDirectTextJobID()
        let requestURL = try directTextURL(pathComponents: ["api", "text"])
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setDirectTextAuthorizationHeader(on: &request)
        request.httpBody = try JSONEncoder().encode(
            DirectTextJobRequest(
                job_id: jobID,
                message: message,
                submit_after_paste: submitAfterPaste,
                route_target: routeTarget,
                response_mode: responseMode,
                call_session: callSession
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecorderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw RecorderError.serverError(serverMessage)
        }

        let payload = try JSONDecoder().decode(DirectTextJobSubmitResponse.self, from: data)
        return payload.jobID ?? jobID
    }

    private func waitForTextResponse(jobID: String, transport: TextResponseTransport) async throws -> DropboxTextResponse {
        switch transport {
        case .dropbox:
            return try await dropboxManager.waitForTextResponse(jobID: jobID)
        case .direct:
            return try await waitForDirectTextResponse(jobID: jobID)
        case .googleDrive:
            throw RecorderError.serverError("Google Drive delivery does not support waiting for responses yet.")
        }
    }

    private func waitForDirectTextResponse(jobID: String, timeout: TimeInterval = 120) async throws -> DropboxTextResponse {
        let deadline = Date().addingTimeInterval(timeout)
        var latestWaitingResponse: DropboxTextResponse?

        while Date() < deadline {
            let requestURL = try directTextURL(pathComponents: ["api", "text", jobID, "response"])
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            setDirectTextAuthorizationHeader(on: &request)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw RecorderError.invalidResponse
                }

                if httpResponse.statusCode == 202 {
                    latestWaitingResponse = try? JSONDecoder().decode(DropboxTextResponse.self, from: data)
                } else if (200..<300).contains(httpResponse.statusCode) {
                    let responsePayload = try JSONDecoder().decode(DropboxTextResponse.self, from: data)
                    if responsePayload.status != "waiting" {
                        return responsePayload
                    }
                    latestWaitingResponse = responsePayload
                } else {
                    let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                    throw RecorderError.serverError(serverMessage)
                }
            } catch let error as RecorderError {
                throw error
            } catch {
                // The Mac may still be writing the response file.
            }

            try await Task.sleep(for: .milliseconds(350))
        }

        if let latestWaitingResponse {
            return latestWaitingResponse
        }

        throw RecorderError.serverError("Timed out waiting for direct text response.")
    }

    private func waitForTextResponse(filename: String, context: ResponseContext) async {
        let jobID = (filename as NSString).deletingPathExtension
        await waitForTextResponse(jobID: jobID, context: context)
    }

    private func waitForTextResponse(
        jobID: String,
        context: ResponseContext,
        appendTranscript: Bool = true,
        transport: TextResponseTransport = .dropbox
    ) async {
        beginWaitingForResponse(context)

        do {
            let response = try await waitForTextResponse(jobID: jobID, transport: transport)
            handleTextResponse(response, appendTranscript: appendTranscript, context: context)
        } catch {
            appendThreadMessage(.status, "Response failed: \(error.localizedDescription)")
            if context == .call {
                if callViewVisible {
                    statusText = "Response failed"
                }
            } else {
                statusText = "Response failed"
            }
        }

        endWaitingForResponse(context)
    }

    private func handleTextResponse(_ response: DropboxTextResponse, appendTranscript: Bool, context: ResponseContext) {
        if appendTranscript, let transcript = response.transcript, !transcript.isEmpty {
            appendThreadMessage(.user, cleanedTranscript(transcript))
        }

        let responseText = response.responseText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackMessage = response.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !responseText.isEmpty {
            appendThreadMessage(.assistant, responseText)
            if context == .call {
                enqueueCallSpeech(responseText)
                if callViewVisible {
                    statusText = "Response received"
                }
            } else {
                statusText = "Response received"
            }
        } else if !fallbackMessage.isEmpty {
            appendThreadMessage(.status, fallbackMessage)
            if context == .call {
                if callViewVisible {
                    statusText = response.status == "waiting" ? "Response still pending" : "Response updated"
                }
            } else {
                statusText = response.status == "waiting" ? "Response still pending" : "Response updated"
            }
        } else {
            appendThreadMessage(.status, "No response text returned.")
            if context == .call {
                if callViewVisible {
                    statusText = "No response text"
                }
            } else {
                statusText = "No response text"
            }
        }
    }

    private func appendThreadMessage(_ role: VoiceThreadMessage.Role, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if role == .status && isTransientStatusMessage(trimmed) {
            return
        }
        if threadMessages.last?.role == role && threadMessages.last?.text == trimmed {
            return
        }
        threadMessages.append(VoiceThreadMessage(role: role, text: trimmed))
        if threadMessages.count > 12 {
            threadMessages.removeFirst(threadMessages.count - 12)
        }
    }

    private func cleanedTranscript(_ text: String) -> String {
        let parentheticalPattern = #"\s*[\(\[\{][^\)\]\}]{1,100}[\)\]\}]\s*"#
        let withoutParentheticals = text.replacingOccurrences(
            of: parentheticalPattern,
            with: " ",
            options: .regularExpression
        )
        return withoutParentheticals
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTransientStatusMessage(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "waiting for response..."
            || normalized == "waiting for response"
            || normalized == "response still pending"
    }

    private func beginWaitingForResponse(_ context: ResponseContext) {
        switch context {
        case .text:
            pendingTextResponseCount += 1
            isWaitingForTextResponse = true
        case .call:
            pendingCallResponseCount += 1
            isWaitingForCallResponse = true
        }
    }

    private func endWaitingForResponse(_ context: ResponseContext) {
        switch context {
        case .text:
            pendingTextResponseCount = max(0, pendingTextResponseCount - 1)
            isWaitingForTextResponse = pendingTextResponseCount > 0
        case .call:
            pendingCallResponseCount = max(0, pendingCallResponseCount - 1)
            isWaitingForCallResponse = pendingCallResponseCount > 0
        }
    }

    private func enqueueCallSpeech(_ text: String) {
        guard speakCallResponsesEnabled else { return }
        queuedCallSpeech.append(text)
        queuedCallSpeechCount = queuedCallSpeech.count
        playQueuedCallSpeechIfPossible()
    }

    private func playQueuedCallSpeechIfPossible() {
        guard speakCallResponsesEnabled, !speechSynthesizer.isSpeaking, !queuedCallSpeech.isEmpty else { return }
        stopMicForResponsePlaybackIfNeeded()
        let text = queuedCallSpeech.removeFirst()
        queuedCallSpeechCount = queuedCallSpeech.count
        try? configureCallAudioSessionForPlayback()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    private func restartCallListeningWhenReady() async {
        while callSessionActive,
              state == .idle,
              (speechSynthesizer.isSpeaking || !queuedCallSpeech.isEmpty) {
            try? await Task.sleep(for: .milliseconds(250))
        }

        try? await Task.sleep(for: .milliseconds(350))
        guard callSessionActive,
              state == .idle,
              !speechSynthesizer.isSpeaking,
              queuedCallSpeech.isEmpty
        else { return }

        await startRecording()
    }

    private func stopMicForResponsePlaybackIfNeeded() {
        guard state == .recording || state == .paused else { return }

        stopLiveTranscription(keepTranscript: false)
        stopTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        pausedByAudioInterruption = false
        if let recordingURL = currentRecordingURL {
            cleanupRecordingFile(at: recordingURL)
        }

        currentRecordingURL = nil
        recordingStartedAt = nil
        accumulatedDuration = 0
        elapsedSeconds = 0
        speechDetectedInCurrentTurn = false
        lastSpeechDetectedAt = nil
        lastLiveTranscriptChangedAt = nil
        isHandlingCallTurn = false
        manualCallTurnSendRequested = false
        liveTranscriptionRequiredForCurrentTurn = false
        liveTranscriptionReadyForCurrentTurn = false
        currentRecordingUsesAppleSpeechNormalMode = false
        currentRecordingRequiresOnDeviceSpeech = false
        waveformSamples = Array(repeating: 0.08, count: 33)
        liveTranscript = ""
        liveSpeechTranscriptPrefix = ""
        liveSpeechCurrentPartial = ""
        state = .idle
        statusText = "Playing response"
    }

    private func discardCurrentRecordingWithoutStoppingCall() {
        stopLiveTranscription(keepTranscript: false)
        stopTimer()
        audioRecorder?.stop()
        audioRecorder = nil
        if let recordingURL = currentRecordingURL {
            cleanupRecordingFile(at: recordingURL)
        }

        currentRecordingURL = nil
        recordingStartedAt = nil
        accumulatedDuration = 0
        elapsedSeconds = 0
        speechDetectedInCurrentTurn = false
        lastSpeechDetectedAt = nil
        lastLiveTranscriptChangedAt = nil
        isHandlingCallTurn = false
        manualCallTurnSendRequested = false
        liveTranscriptionRequiredForCurrentTurn = false
        liveTranscriptionReadyForCurrentTurn = false
        currentRecordingUsesAppleSpeechNormalMode = false
        currentRecordingRequiresOnDeviceSpeech = false
        waveformSamples = Array(repeating: 0.08, count: 33)
        liveTranscript = ""
        liveSpeechTranscriptPrefix = ""
        liveSpeechCurrentPartial = ""
        state = .idle
        statusText = "Listening"
    }

    private func sendImmediateControlToServer(routeTarget: String) async throws {
        guard let baseURL = activeHTTPBaseURL() else {
            throw RecorderError.invalidServerURL
        }

        let controlURL = baseURL.appending(path: "api/control")
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        setDirectTextAuthorizationHeader(on: &request)
        request.httpBody = try JSONEncoder().encode(ControlRequest(route_target: routeTarget))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw RecorderError.invalidResponse
        }
    }

    private func directTextURL(pathComponents: [String]) throws -> URL {
        let trimmedURL = directTextServerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = trimmedURL.isEmpty ? activeHTTPBaseURL() : URL(string: trimmedURL)
        guard var url = baseURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            throw RecorderError.invalidServerURL
        }

        for component in pathComponents {
            url = url.appendingPathComponent(component)
        }
        return url
    }

    private func setDirectTextAuthorizationHeader(on request: inout URLRequest) {
        let token = directTextAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func makeDirectTextJobID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "ios_text_\(timestamp)_\(UUID().uuidString.prefix(8).lowercased())"
    }

    private static func readDirectTextAPIToken() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: directTextAPITokenService,
            kSecAttrAccount as String: directTextAPITokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return token
    }

    private static func readDirectTextAPITokenWithBundledFallback() -> String {
        let storedToken = readDirectTextAPIToken()
        return storedToken.isEmpty ? bundledReceiverAPIToken : storedToken
    }

    private static func saveDirectTextAPIToken(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: directTextAPITokenService,
            kSecAttrAccount as String: directTextAPITokenAccount,
        ]

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(trimmedToken.utf8)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func cleanupRecordingFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func withUploadBackgroundTask(_ operation: () async -> Void) async {
        await withBackgroundTask(named: "Upload voice turn", operation)
    }

    private func withBackgroundTask(named name: String, _ operation: () async -> Void) async {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: name)
        await operation()
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    private func registerAudioSessionObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    await self?.handleAudioSessionInterruption(notification)
                }
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.recoverCallListeningIfNeeded()
                }
            }
        )
    }

    private func handleAudioSessionInterruption(_ notification: Notification) async {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            if state == .recording {
                stopLiveTranscription(keepTranscript: true)
                stopTimer()
                audioRecorder?.pause()
                state = .paused
                statusText = "Interrupted"
                pausedByAudioInterruption = true
            } else if state == .paused {
                stopLiveTranscription(keepTranscript: true)
            }
        case .ended:
            if voiceCallModeEnabled || callSessionActive {
                await recoverCallListeningIfNeeded()
            } else if pausedByAudioInterruption, state == .paused, currentRecordingURL != nil {
                pausedByAudioInterruption = false
                resumeRecording()
            } else {
                pausedByAudioInterruption = false
            }
        @unknown default:
            break
        }
    }
}

extension RecordingViewModel: AVAudioRecorderDelegate {}

extension RecordingViewModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playQueuedCallSpeechIfPossible()
            if !self.speechSynthesizer.isSpeaking && self.queuedCallSpeech.isEmpty {
                await self.restartCallListeningWhenReady()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.playQueuedCallSpeechIfPossible()
            if !self.speechSynthesizer.isSpeaking && self.queuedCallSpeech.isEmpty {
                await self.restartCallListeningWhenReady()
            }
        }
    }
}

private struct UploadResponse: Decodable {
    let filename: String
}

private struct DirectTextJobRequest: Encodable {
    let job_id: String
    let message: String
    let submit_after_paste: Bool
    let route_target: String?
    let response_mode: String?
    let call_session: Bool
}

private struct DirectTextJobSubmitResponse: Decodable {
    let jobID: String?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
    }
}

private struct ReceiverHealthResponse: Decodable {
    let ok: Bool
    let service: String?
    let watchFolder: String?
    let apiAuthRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case service
        case watchFolder = "watch_folder"
        case apiAuthRequired = "api_auth_required"
    }
}

private struct ControlRequest: Encodable {
    let route_target: String
}

enum RecorderError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Server URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .serverError(let message):
            return message
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
