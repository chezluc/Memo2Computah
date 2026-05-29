import Foundation
import SwiftyDropbox
import UIKit

@MainActor
final class DropboxSessionManager: ObservableObject {
    static let shared = DropboxSessionManager()

    @Published private(set) var isLinked = false
    @Published private(set) var accountName: String?
    @Published var defaultFolderPath: String
    @Published private(set) var authErrorMessage: String?

    private let appKey = "5ly9ju548yuntzq"
    private let scopes = ["files.metadata.read", "files.content.read", "files.content.write"]
    private static let defaultFolderDefaultsKey = "memo2Computah.dropbox.defaultFolderPath"
    private static let memo2DefaultFolderPath = "/Memo2Computah"
    private static let legacyLukeMobileFolderPath = "/auto.transcribe.agent"

    private init() {
        let storedPath = UserDefaults.standard.string(forKey: Self.defaultFolderDefaultsKey)
        let initialPath = storedPath == Self.legacyLukeMobileFolderPath || storedPath == nil
            ? Self.memo2DefaultFolderPath
            : storedPath!
        self.defaultFolderPath = initialPath
        UserDefaults.standard.set(initialPath, forKey: Self.defaultFolderDefaultsKey)
        refreshAuthorizationState()
    }

    var isReadyForUpload: Bool {
        isLinked && !normalizedFolderPath(defaultFolderPath).isEmpty
    }

    func configureIfNeeded() {
        DropboxClientsManager.setupWithAppKey(appKey)
        refreshAuthorizationState()
    }

    func connect() {
        guard let topController = UIApplication.shared.topViewController() else {
            authErrorMessage = "Could not open Dropbox sign-in."
            return
        }

        let scopeRequest = ScopeRequest(scopeType: .user, scopes: scopes, includeGrantedScopes: false)
        DropboxClientsManager.authorizeFromControllerV2(
            UIApplication.shared,
            controller: topController,
            loadingStatusDelegate: nil,
            openURL: { url in UIApplication.shared.open(url) },
            scopeRequest: scopeRequest
        )
    }

    func unlink() {
        DropboxClientsManager.unlinkClients()
        accountName = nil
        authErrorMessage = nil
        refreshAuthorizationState()
    }

    @discardableResult
    func handleRedirectURL(_ url: URL) -> Bool {
        DropboxClientsManager.handleRedirectURL(url) { [weak self] authResult in
            guard let self, let authResult else { return }

            Task { @MainActor in
                switch authResult {
                case .success:
                    self.authErrorMessage = nil
                    self.refreshAuthorizationState()
                    await self.refreshAccountName()
                case .cancel:
                    self.authErrorMessage = "Dropbox sign-in canceled."
                    self.refreshAuthorizationState()
                case .error(_, let description):
                    self.authErrorMessage = description ?? "Dropbox sign-in failed."
                    self.refreshAuthorizationState()
                }
            }
        }
    }

    func persistDefaultFolder() {
        let normalized = normalizedFolderPath(defaultFolderPath)
        defaultFolderPath = normalized
        UserDefaults.standard.set(normalized, forKey: Self.defaultFolderDefaultsKey)
    }

    func refreshAccountName() async {
        guard let client = DropboxClientsManager.authorizedClient else { return }
        do {
            let account = try await rpcResponse(client.users.getCurrentAccount())
            accountName = account.name.displayName
        } catch {
            accountName = nil
        }
    }

    func listFolders(at path: String) async throws -> [DropboxFolderEntry] {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxRecorderError.notLinked
        }

        let requestPath = path == "/" ? "" : path
        do {
            let response = try await rpcResponse(client.files.listFolder(path: requestPath))
            return response.entries.compactMap { entry -> DropboxFolderEntry? in
                guard let folderMetadata = entry as? Files.FolderMetadata else { return nil }
                return DropboxFolderEntry(
                    name: folderMetadata.name,
                    path: folderMetadata.pathDisplay ?? "/\(folderMetadata.name)"
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            throw DropboxRecorderError.sdk(String(describing: error))
        }
    }

    func uploadRecording(
        fileURL: URL,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) async throws -> String {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxRecorderError.notLinked
        }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let normalizedFolder = normalizedFolderPath(defaultFolderPath)
        let remotePath = dropboxPath(for: filename, folderPath: normalizedFolder)
        let metadataPath = remotePath + ".route.json"
        let metadata = try JSONEncoder().encode(
            RouteMetadata(
                submit_after_paste: submitAfterPaste,
                route_target: routeTarget,
                response_mode: responseMode,
                call_session: callSession
            )
        )

        try await upload(data: fileData, to: remotePath, client: client)
        try await upload(data: metadata, to: metadataPath, client: client)
        return filename
    }

    func uploadTypedMessage(
        message: String,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) async throws -> String {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxRecorderError.notLinked
        }

        let normalizedFolder = normalizedFolderPath(defaultFolderPath)
        let jobID = "ios_text_\(timestampString())_\(UUID().uuidString.prefix(8).lowercased())"
        let remotePath = dropboxPath(for: "\(jobID).text.json", folderPath: normalizedFolder)
        let metadata = try JSONEncoder().encode(
            TextJobMetadata(
                job_id: jobID,
                message: message,
                submit_after_paste: submitAfterPaste,
                route_target: routeTarget,
                response_mode: responseMode,
                call_session: callSession
            )
        )

        try await upload(data: metadata, to: remotePath, client: client)
        return jobID
    }

    func waitForTextResponse(for filename: String, timeout: TimeInterval = 120) async throws -> DropboxTextResponse {
        let jobID = (filename as NSString).deletingPathExtension
        return try await waitForTextResponse(jobID: jobID, timeout: timeout)
    }

    func waitForTextResponse(jobID: String, timeout: TimeInterval = 120) async throws -> DropboxTextResponse {
        guard DropboxClientsManager.authorizedClient != nil else {
            throw DropboxRecorderError.notLinked
        }

        let responsePath = dropboxPath(for: "responses/\(jobID).response.json", folderPath: normalizedFolderPath(defaultFolderPath))
        let deadline = Date().addingTimeInterval(timeout)
        var latestWaitingResponse: DropboxTextResponse?

        while Date() < deadline {
            do {
                let response = try await downloadTextResponse(at: responsePath)
                if response.status != "waiting" {
                    return response
                }
                latestWaitingResponse = response
            } catch {
                // Dropbox sync may not have uploaded the response file yet.
            }

            try await Task.sleep(for: .milliseconds(700))
        }

        if let latestWaitingResponse {
            return latestWaitingResponse
        }

        throw DropboxRecorderError.sdk("Timed out waiting for text response.")
    }

    func sendImmediateControl(routeTarget: String) async throws {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxRecorderError.notLinked
        }

        let normalizedFolder = normalizedFolderPath(defaultFolderPath)
        let filename = "Mobile Recorder Control \(timestampString())_\(UUID().uuidString.prefix(8)).control.json"
        let remotePath = dropboxPath(for: filename, folderPath: normalizedFolder)
        let data = try JSONEncoder().encode(ControlMetadata(action: "activate", route_target: routeTarget))
        try await upload(data: data, to: remotePath, client: client)
    }

    private func upload(data: Data, to path: String, client: DropboxClient) async throws {
        _ = try await uploadResponse(client.files.upload(path: path, mode: .overwrite, autorename: false, input: data))
    }

    private func downloadTextResponse(at path: String) async throws -> DropboxTextResponse {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw DropboxRecorderError.notLinked
        }

        do {
            let (_, data) = try await downloadResponse(client.files.download(path: path))
            return try JSONDecoder().decode(DropboxTextResponse.self, from: data)
        } catch {
            throw DropboxRecorderError.sdk(String(describing: error))
        }
    }

    private func rpcResponse<RSerial: JSONSerializer, ESerial: JSONSerializer>(
        _ request: RpcRequest<RSerial, ESerial>
    ) async throws -> RSerial.ValueType {
        try await withCheckedThrowingContinuation { continuation in
            request.response { value, error in
                if let error {
                    continuation.resume(throwing: DropboxRecorderError.sdk(String(describing: error)))
                    return
                }

                guard let value else {
                    continuation.resume(throwing: DropboxRecorderError.sdk("Dropbox returned no response."))
                    return
                }

                continuation.resume(returning: value)
            }
        }
    }

    private func uploadResponse<RSerial: JSONSerializer, ESerial: JSONSerializer>(
        _ request: UploadRequest<RSerial, ESerial>
    ) async throws -> RSerial.ValueType {
        try await withCheckedThrowingContinuation { continuation in
            request.response { value, error in
                if let error {
                    continuation.resume(throwing: DropboxRecorderError.sdk(String(describing: error)))
                    return
                }

                guard let value else {
                    continuation.resume(throwing: DropboxRecorderError.sdk("Dropbox upload returned no response."))
                    return
                }

                continuation.resume(returning: value)
            }
        }
    }

    private func downloadResponse<RSerial: JSONSerializer, ESerial: JSONSerializer>(
        _ request: DownloadRequestMemory<RSerial, ESerial>
    ) async throws -> (RSerial.ValueType, Data) {
        try await withCheckedThrowingContinuation { continuation in
            request.response { value, error in
                if let error {
                    continuation.resume(throwing: DropboxRecorderError.sdk(String(describing: error)))
                    return
                }

                guard let value else {
                    continuation.resume(throwing: DropboxRecorderError.sdk("Dropbox download returned no response."))
                    return
                }

                continuation.resume(returning: value)
            }
        }
    }

    private func refreshAuthorizationState() {
        isLinked = DropboxClientsManager.authorizedClient != nil
    }

    private func normalizedFolderPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        if trimmed == "/" { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    private func dropboxPath(for filename: String, folderPath: String) -> String {
        let folder = normalizedFolderPath(folderPath)
        if folder == "/" {
            return "/\(filename)"
        }
        return folder + "/\(filename)"
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

struct DropboxFolderEntry: Identifiable, Hashable {
    let name: String
    let path: String

    var id: String { path }
}

private struct RouteMetadata: Encodable {
    let submit_after_paste: Bool
    let route_target: String?
    let response_mode: String?
    let call_session: Bool
}

private struct TextJobMetadata: Encodable {
    let job_id: String
    let message: String
    let submit_after_paste: Bool
    let route_target: String?
    let response_mode: String?
    let call_session: Bool
}

private struct ControlMetadata: Encodable {
    let action: String
    let route_target: String
}

struct DropboxTextResponse: Decodable, Equatable {
    let version: Int?
    let jobID: String?
    let status: String
    let routeTarget: String?
    let routeLabel: String?
    let transcript: String?
    let responseText: String?
    let message: String?
    let source: String?
    let tmuxTarget: String?
    let audioFilename: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case version
        case jobID = "job_id"
        case status
        case routeTarget = "route_target"
        case routeLabel = "route_label"
        case transcript
        case responseText = "response_text"
        case message
        case source
        case tmuxTarget = "tmux_target"
        case audioFilename = "audio_filename"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum DropboxRecorderError: LocalizedError {
    case notLinked
    case sdk(String)

    var errorDescription: String? {
        switch self {
        case .notLinked:
            return "Dropbox is not connected."
        case .sdk(let message):
            return message
        }
    }
}

private extension UIApplication {
    func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return topViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = base as? UITabBarController, let selected = tabBarController.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
