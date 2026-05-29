import Foundation
import GoogleSignIn
import UIKit

struct LANReceiverProfile: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var urlString: String
}

@MainActor
final class GoogleDriveFolderManager {
    static let shared = GoogleDriveFolderManager()

    private static let folderIDDefaultsKey = "memo2Computah.googleDrive.folderID"
    private static let folderNameDefaultsKey = "memo2Computah.googleDrive.folderName"
    private static let folderName = "auto.transcribe"
    private static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var isConfigured = false

    private(set) var lastErrorMessage: String?

    private init() {}

    var folderDisplayName: String {
        UserDefaults.standard.string(forKey: Self.folderNameDefaultsKey) ?? Self.folderName
    }

    var accountDisplayName: String? {
        GIDSignIn.sharedInstance.currentUser?.profile?.email
    }

    var isReadyForUpload: Bool {
        GIDSignIn.sharedInstance.currentUser != nil && configuredClientID != nil
    }

    func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let clientID = configuredClientID else {
            lastErrorMessage = "Google Drive OAuth client ID is missing from the build."
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        isConfigured = true
    }

    func restorePreviousSignIn() async {
        configureIfNeeded()
        guard isConfigured, GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }

        do {
            let _: GIDGoogleUser = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
                GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let user {
                        continuation.resume(returning: user)
                    } else {
                        continuation.resume(throwing: GoogleDriveFolderError.notLinked)
                    }
                }
            }
            UserDefaults.standard.set(Self.folderName, forKey: Self.folderNameDefaultsKey)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func handleRedirectURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func connect() async throws {
        configureIfNeeded()
        guard isConfigured else {
            throw GoogleDriveFolderError.missingOAuthClient
        }
        guard let presentingViewController = UIApplication.shared.memo2TopViewController else {
            throw GoogleDriveFolderError.noPresenter
        }

        do {
            let _: GIDGoogleUser = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
                GIDSignIn.sharedInstance.signIn(
                    withPresenting: presentingViewController,
                    hint: nil,
                    additionalScopes: [Self.driveFileScope],
                    nonce: nil
                ) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result.user)
                    } else {
                        continuation.resume(throwing: GoogleDriveFolderError.notLinked)
                    }
                }
            }
            _ = try await ensureUploadFolderID()
            UserDefaults.standard.set(Self.folderName, forKey: Self.folderNameDefaultsKey)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func clearFolder() {
        GIDSignIn.sharedInstance.signOut()
        UserDefaults.standard.removeObject(forKey: Self.folderIDDefaultsKey)
        UserDefaults.standard.set(Self.folderName, forKey: Self.folderNameDefaultsKey)
        lastErrorMessage = nil
    }

    func uploadRecording(
        fileURL: URL,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) async throws -> String {
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        let uploadedName = try await uploadData(
            fileData,
            name: filename,
            mimeType: mimeType(for: fileURL),
            folderID: try await ensureUploadFolderID()
        )
        let metadata = try encoder.encode(
            GoogleDriveRouteMetadata(
                submit_after_paste: submitAfterPaste,
                route_target: routeTarget,
                response_mode: responseMode,
                call_session: callSession
            )
        )
        _ = try await uploadData(
            metadata,
            name: uploadedName + ".route.json",
            mimeType: "application/json",
            folderID: try await ensureUploadFolderID()
        )
        lastErrorMessage = nil
        return uploadedName
    }

    func uploadTypedMessage(
        message: String,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) async throws -> String {
        let jobID = "ios_text_\(timestampString())_\(UUID().uuidString.prefix(8).lowercased())"
        let metadata = try encoder.encode(
            GoogleDriveTextJobMetadata(
                job_id: jobID,
                message: message,
                submit_after_paste: submitAfterPaste,
                route_target: routeTarget,
                response_mode: responseMode,
                call_session: callSession
            )
        )
        _ = try await uploadData(
            metadata,
            name: "\(jobID).text.json",
            mimeType: "application/json",
            folderID: try await ensureUploadFolderID()
        )
        lastErrorMessage = nil
        return jobID
    }

    private var configuredClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private func accessToken() async throws -> String {
        configureIfNeeded()
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleDriveFolderError.notLinked
        }

        let refreshedUser: GIDGoogleUser = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let refreshedUser {
                    continuation.resume(returning: refreshedUser)
                } else {
                    continuation.resume(throwing: GoogleDriveFolderError.notLinked)
                }
            }
        }
        return refreshedUser.accessToken.tokenString
    }

    private func ensureUploadFolderID() async throws -> String {
        if let storedID = UserDefaults.standard.string(forKey: Self.folderIDDefaultsKey), !storedID.isEmpty {
            return storedID
        }

        let token = try await accessToken()
        if let existingID = try await findFolderID(accessToken: token) {
            UserDefaults.standard.set(existingID, forKey: Self.folderIDDefaultsKey)
            UserDefaults.standard.set(Self.folderName, forKey: Self.folderNameDefaultsKey)
            return existingID
        }

        let createdID = try await createFolder(accessToken: token)
        UserDefaults.standard.set(createdID, forKey: Self.folderIDDefaultsKey)
        UserDefaults.standard.set(Self.folderName, forKey: Self.folderNameDefaultsKey)
        return createdID
    }

    private func findFolderID(accessToken: String) async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(Self.folderName)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "10")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data = try await validatedData(for: request)
        return try decoder.decode(GoogleDriveFileList.self, from: data).files.first?.id
    }

    private func createFolder(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id,name")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            GoogleDriveCreateFileRequest(
                name: Self.folderName,
                mimeType: "application/vnd.google-apps.folder",
                parents: nil
            )
        )

        let data = try await validatedData(for: request)
        return try decoder.decode(GoogleDriveFile.self, from: data).id
    }

    private func uploadData(_ data: Data, name: String, mimeType: String, folderID: String) async throws -> String {
        let token = try await accessToken()
        let boundary = "Memo2Computah-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(
            boundary: boundary,
            metadata: GoogleDriveCreateFileRequest(name: name, mimeType: nil, parents: [folderID]),
            data: data,
            mimeType: mimeType
        )

        let responseData = try await validatedData(for: request)
        return try decoder.decode(GoogleDriveFile.self, from: responseData).name
    }

    private func multipartBody(
        boundary: String,
        metadata: GoogleDriveCreateFileRequest,
        data: Data,
        mimeType: String
    ) throws -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(try encoder.encode(metadata))
        body.append("\r\n--\(boundary)\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveFolderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8) ?? "No response body."
            throw GoogleDriveFolderError.api("Google Drive returned \(httpResponse.statusCode): \(responseText)")
        }
        return data
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        default:
            return "application/octet-stream"
        }
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension UIApplication {
    var memo2TopViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .memo2TopMostViewController
    }
}

private extension UIViewController {
    var memo2TopMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.memo2TopMostViewController
        }
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.memo2TopMostViewController ?? navigationController
        }
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.memo2TopMostViewController ?? tabBarController
        }
        return self
    }
}

private struct GoogleDriveCreateFileRequest: Encodable {
    let name: String
    let mimeType: String?
    let parents: [String]?
}

private struct GoogleDriveFileList: Decodable {
    let files: [GoogleDriveFile]
}

private struct GoogleDriveFile: Decodable {
    let id: String
    let name: String
}

private struct GoogleDriveRouteMetadata: Encodable {
    let submit_after_paste: Bool
    let route_target: String?
    let response_mode: String?
    let call_session: Bool
}

private struct GoogleDriveTextJobMetadata: Encodable {
    let job_id: String
    let message: String
    let submit_after_paste: Bool
    let route_target: String?
    let response_mode: String?
    let call_session: Bool
}

enum GoogleDriveFolderError: LocalizedError {
    case api(String)
    case invalidResponse
    case missingOAuthClient
    case noPresenter
    case notLinked

    var errorDescription: String? {
        switch self {
        case .api(let message):
            return message
        case .invalidResponse:
            return "Google Drive returned an invalid response."
        case .missingOAuthClient:
            return "Google Drive OAuth is not configured in this build."
        case .noPresenter:
            return "Could not open Google sign-in from the current screen."
        case .notLinked:
            return "Google Drive is not connected."
        }
    }
}
