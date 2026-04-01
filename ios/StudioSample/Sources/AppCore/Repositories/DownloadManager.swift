import Foundation
import UniformTypeIdentifiers

actor DownloadManager {
    typealias ProgressHandler = @Sendable (Double) async -> Void
    typealias EventHandler = @Sendable (DownloadTransportEvent) async -> Void
    typealias DownloadOperation = @Sendable (_ sourceURL: URL, _ onProgress: ProgressHandler?) async throws -> (temporaryURL: URL, response: URLResponse)

    enum DownloadError: LocalizedError {
        case invalidResponse
        case httpFailure(statusCode: Int, bodyPreview: String?)
        case unsupportedOfflineMediaType(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The download did not return a valid server response."
            case let .httpFailure(statusCode, bodyPreview):
                if let bodyPreview, !bodyPreview.isEmpty {
                    return "The download server returned HTTP \(statusCode): \(bodyPreview)"
                }
                return "The download server returned HTTP \(statusCode)."
            case let .unsupportedOfflineMediaType(mimeType):
                return "The download finished, but the media type \(mimeType) is not supported for offline playback on iPhone."
            }
        }
    }

    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let downloadOperation: DownloadOperation

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        downloadOperation: DownloadOperation? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
        self.downloadOperation = downloadOperation ?? Self.makeDownloadOperation()
    }

    func download(
        sampleID: String,
        from sourceURL: URL,
        onProgress: ProgressHandler? = nil,
        onEvent: EventHandler? = nil
    ) async throws -> URL {
        await onEvent?(
            DownloadTransportEvent(
                level: .info,
                message: "Starting transfer from \(Self.redactedURLString(sourceURL))."
            )
        )

        let (tmpURL, response) = try await downloadOperation(sourceURL, onProgress)
        try await validate(response: response, temporaryURL: tmpURL, onEvent: onEvent)
        let dir = try sampleDirectory(for: sampleID, createDirectory: true)
        try removeExistingFiles(in: dir)
        try removeLegacyFiles(for: sampleID)

        let destination = dir.appendingPathComponent(destinationFilename(sourceURL: sourceURL, response: response))
        if fileManager.fileExists(atPath: destination.path()) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tmpURL, to: destination)
        await onEvent?(
            DownloadTransportEvent(
                level: .info,
                message: "Stored download as \(destination.lastPathComponent)."
            )
        )

        return destination
    }

    func removeDownload(sampleID: String) throws {
        let directory = try sampleDirectory(for: sampleID, createDirectory: false)
        if fileManager.fileExists(atPath: directory.path()) {
            try fileManager.removeItem(at: directory)
        }
        try removeLegacyFiles(for: sampleID)
    }

    func existingDownloads() throws -> [String: URL] {
        let dir = try downloadsDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var result: [String: URL] = [:]
        for url in urls {
            if url.hasDirectoryPath {
                if let storedFile = try firstRegularFile(in: url) {
                    result[url.lastPathComponent] = storedFile
                }
            } else {
                result[url.deletingPathExtension().lastPathComponent] = url
            }
        }
        return result
    }

    private func sampleDirectory(for sampleID: String, createDirectory: Bool) throws -> URL {
        let directory = try downloadsDirectory().appendingPathComponent(sampleID, isDirectory: true)
        if createDirectory {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func firstRegularFile(in directory: URL) throws -> URL? {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.first(where: { !$0.hasDirectoryPath })
    }

    private func removeExistingFiles(in directory: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            try fileManager.removeItem(at: url)
        }
    }

    private func removeLegacyFiles(for sampleID: String) throws {
        let dir = try downloadsDirectory()
        let contents = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in contents
        where !url.hasDirectoryPath && url.deletingPathExtension().lastPathComponent == sampleID {
            try fileManager.removeItem(at: url)
        }
    }

    private func destinationFilename(sourceURL: URL, response: URLResponse) -> String {
        let ext = preferredExtension(sourceURL: sourceURL, response: response)
        let filename: String
        if let suggested = response.suggestedFilename, !suggested.isEmpty {
            let base = URL(fileURLWithPath: suggested).deletingPathExtension().lastPathComponent
            filename = base.isEmpty ? "download" : base
        } else {
            filename = sourceURL.deletingPathExtension().lastPathComponent.isEmpty
                ? "download"
                : sourceURL.deletingPathExtension().lastPathComponent
        }

        guard !ext.isEmpty else {
            return filename
        }
        return "\(filename).\(ext)"
    }

    private func preferredExtension(sourceURL: URL, response: URLResponse) -> String {
        if let mimeType = response.mimeType,
           let type = UTType(mimeType: mimeType),
           let ext = type.preferredFilenameExtension {
            return ext.lowercased()
        }

        if let suggested = response.suggestedFilename {
            let ext = URL(fileURLWithPath: suggested).pathExtension
            if !ext.isEmpty {
                return ext.lowercased()
            }
        }

        return sourceURL.pathExtension.lowercased()
    }

    private func validate(
        response: URLResponse,
        temporaryURL: URL,
        onEvent: EventHandler?
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            await onEvent?(
                DownloadTransportEvent(
                    level: .error,
                    message: "The download response was not an HTTP response."
                )
            )
            throw DownloadError.invalidResponse
        }

        let mimeType = httpResponse.mimeType ?? "unknown"
        let expectedLength = httpResponse.expectedContentLength
        let lengthDescription = expectedLength > 0 ? ByteCountFormatter.string(fromByteCount: expectedLength, countStyle: .file) : "unknown size"
        await onEvent?(
            DownloadTransportEvent(
                level: .info,
                message: "Received HTTP \(httpResponse.statusCode) (\(mimeType), \(lengthDescription))."
            )
        )

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let preview = bodyPreview(from: temporaryURL)
            await onEvent?(
                DownloadTransportEvent(
                    level: .error,
                    message: "Transfer failed with HTTP \(httpResponse.statusCode)."
                )
            )
            throw DownloadError.httpFailure(statusCode: httpResponse.statusCode, bodyPreview: preview)
        }

        if let mimeType = httpResponse.mimeType, !isExpectedMediaType(mimeType) {
            await onEvent?(
                DownloadTransportEvent(
                    level: .warning,
                    message: "Unexpected MIME type \(mimeType). Continuing with local validation."
                )
            )
        }

        if let mimeType = httpResponse.mimeType, isKnownUnsupportedOfflineMediaType(mimeType) {
            await onEvent?(
                DownloadTransportEvent(
                    level: .error,
                    message: "Offline playback does not support MIME type \(mimeType) on iOS."
                )
            )
            throw DownloadError.unsupportedOfflineMediaType(mimeType)
        }
    }

    private func bodyPreview(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        let text = String(decoding: data.prefix(180), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func isExpectedMediaType(_ mimeType: String) -> Bool {
        let normalized = mimeType.lowercased()
        if normalized.hasPrefix("audio/") {
            return true
        }

        return [
            "application/octet-stream",
            "application/mp4",
            "video/mp4",
            "video/quicktime",
            "video/webm",
        ].contains(normalized)
    }

    private func isKnownUnsupportedOfflineMediaType(_ mimeType: String) -> Bool {
        let normalized = mimeType.lowercased()
        return normalized == "audio/webm" || normalized == "video/webm"
    }

    private func downloadsDirectory() throws -> URL {
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("DreamCratesDownloads", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        return components.string ?? url.absoluteString
    }

    nonisolated private static func makeDownloadOperation() -> DownloadOperation {
        { sourceURL, onProgress in
            let session = URLSession(configuration: .ephemeral)

            return try await withCheckedThrowingContinuation { continuation in
                var observation: NSKeyValueObservation?
                let task = session.downloadTask(with: sourceURL) { temporaryURL, response, error in
                    observation?.invalidate()
                    session.finishTasksAndInvalidate()

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let temporaryURL, let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }

                    continuation.resume(returning: (temporaryURL, response))
                }

                if let onProgress {
                    observation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                        let totalUnitCount = progress.totalUnitCount
                        let fraction = totalUnitCount > 0 ? progress.fractionCompleted : 0
                        Task {
                            await onProgress(fraction)
                        }
                    }
                }

                task.resume()
            }
        }
    }
}
