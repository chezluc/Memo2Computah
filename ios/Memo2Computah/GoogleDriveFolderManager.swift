import Foundation

struct LANReceiverProfile: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var urlString: String
}

@MainActor
final class GoogleDriveFolderManager {
    static let shared = GoogleDriveFolderManager()

    private static let folderBookmarkDefaultsKey = "memo2Computah.googleDrive.folderBookmark"
    private static let folderDisplayNameDefaultsKey = "memo2Computah.googleDrive.folderDisplayName"
    private let fileManager = FileManager.default

    private(set) var lastErrorMessage: String?

    private init() {}

    var folderDisplayName: String {
        UserDefaults.standard.string(forKey: Self.folderDisplayNameDefaultsKey) ?? "Not selected"
    }

    var isReadyForUpload: Bool {
        resolvedFolderURL() != nil
    }

    func savePickedFolder(_ url: URL) throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmarkData, forKey: Self.folderBookmarkDefaultsKey)
        UserDefaults.standard.set(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, forKey: Self.folderDisplayNameDefaultsKey)
        lastErrorMessage = nil
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: Self.folderBookmarkDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.folderDisplayNameDefaultsKey)
        lastErrorMessage = nil
    }

    func uploadRecording(
        fileURL: URL,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) throws -> String {
        try withWritableFolderURL { folderURL in
            let fileData = try Data(contentsOf: fileURL)
            let filename = uniqueFilename(fileURL.lastPathComponent, in: folderURL)
            let destinationURL = folderURL.appendingPathComponent(filename)
            let metadataURL = folderURL.appendingPathComponent(filename + ".route.json")
            let metadata = try JSONEncoder().encode(
                GoogleDriveRouteMetadata(
                    submit_after_paste: submitAfterPaste,
                    route_target: routeTarget,
                    response_mode: responseMode,
                    call_session: callSession
                )
            )

            try coordinatedWrite(data: fileData, to: destinationURL)
            try coordinatedWrite(data: metadata, to: metadataURL)
            lastErrorMessage = nil
            return filename
        }
    }

    func uploadTypedMessage(
        message: String,
        submitAfterPaste: Bool,
        routeTarget: String?,
        responseMode: String?,
        callSession: Bool
    ) throws -> String {
        try withWritableFolderURL { folderURL in
            let jobID = "ios_text_\(timestampString())_\(UUID().uuidString.prefix(8).lowercased())"
            let filename = "\(jobID).text.json"
            let destinationURL = folderURL.appendingPathComponent(filename)
            let metadata = try JSONEncoder().encode(
                GoogleDriveTextJobMetadata(
                    job_id: jobID,
                    message: message,
                    submit_after_paste: submitAfterPaste,
                    route_target: routeTarget,
                    response_mode: responseMode,
                    call_session: callSession
                )
            )

            try coordinatedWrite(data: metadata, to: destinationURL)
            lastErrorMessage = nil
            return jobID
        }
    }

    private func withWritableFolderURL<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let folderURL = resolvedFolderURL() else {
            throw GoogleDriveFolderError.folderNotSelected
        }

        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        return try operation(folderURL)
    }

    private func resolvedFolderURL() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.folderBookmarkDefaultsKey) else {
            lastErrorMessage = nil
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                let refreshedBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(refreshedBookmark, forKey: Self.folderBookmarkDefaultsKey)
            }
            lastErrorMessage = nil
            return url
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func coordinatedWrite(data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writableURL in
            do {
                try data.write(to: writableURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let writeError {
            throw writeError
        }
        if let coordinatorError {
            throw coordinatorError
        }
    }

    private func uniqueFilename(_ filename: String, in folderURL: URL) -> String {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = filename
        var index = 1

        while fileManager.fileExists(atPath: folderURL.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            index += 1
        }
        return candidate
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
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
    case folderNotSelected

    var errorDescription: String? {
        switch self {
        case .folderNotSelected:
            return "Choose a Google Drive folder first."
        }
    }
}
