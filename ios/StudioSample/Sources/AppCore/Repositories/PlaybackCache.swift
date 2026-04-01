import Foundation
import UniformTypeIdentifiers

actor PlaybackCache {
    typealias DownloadOperation = @Sendable (URL) async throws -> (temporaryURL: URL, response: URLResponse)

    enum CacheError: LocalizedError {
        case invalidResponse
        case unsupportedOfflineMediaType(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The playback cache did not receive a valid server response."
            case let .unsupportedOfflineMediaType(mimeType):
                return "Warp playback cannot open \(mimeType) as a local audio file on iPhone."
            }
        }
    }

    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let downloadOperation: DownloadOperation
    private var inflightDownloads: [String: Task<URL, Error>] = [:]

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        downloadOperation: @escaping DownloadOperation = { url in
            let (tmpURL, response) = try await URLSession.shared.download(from: url)
            return (tmpURL, response)
        }
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
        self.downloadOperation = downloadOperation
    }

    func cachedURL(for sampleID: String) throws -> URL? {
        let directory = try sampleDirectory(for: sampleID, createDirectory: false)
        guard fileManager.fileExists(atPath: directory.path()) else {
            return nil
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.first(where: { !$0.hasDirectoryPath })
    }

    func cache(sampleID: String, from remoteURL: URL) async throws -> URL {
        if let cached = try cachedURL(for: sampleID) {
            return cached
        }

        if let inflight = inflightDownloads[sampleID] {
            return try await inflight.value
        }

        let task = Task { [downloadOperation] in
            let download = try await downloadOperation(remoteURL)
            try self.validate(response: download.response)
            return try await self.storeDownloadedFile(
                sampleID: sampleID,
                temporaryURL: download.temporaryURL,
                remoteURL: remoteURL,
                response: download.response
            )
        }
        inflightDownloads[sampleID] = task

        defer { inflightDownloads[sampleID] = nil }
        return try await task.value
    }

    func removeCachedURL(for sampleID: String) throws {
        let directory = try sampleDirectory(for: sampleID, createDirectory: false)
        if fileManager.fileExists(atPath: directory.path()) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func storeDownloadedFile(
        sampleID: String,
        temporaryURL: URL,
        remoteURL: URL,
        response: URLResponse
    ) async throws -> URL {
        let directory = try sampleDirectory(for: sampleID, createDirectory: true)
        try removeExistingFiles(in: directory)

        let destination = directory.appendingPathComponent(
            destinationFilename(remoteURL: remoteURL, response: response)
        )
        if fileManager.fileExists(atPath: destination.path()) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func sampleDirectory(for sampleID: String, createDirectory: Bool) throws -> URL {
        let directory = try cacheDirectory(createIfNeeded: createDirectory)
            .appendingPathComponent(sampleID, isDirectory: true)
        if createDirectory {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
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

    private func destinationFilename(remoteURL: URL, response: URLResponse) -> String {
        let ext = preferredExtension(remoteURL: remoteURL, response: response)
        let filename: String
        if let suggested = response.suggestedFilename, !suggested.isEmpty {
            let base = URL(fileURLWithPath: suggested).deletingPathExtension().lastPathComponent
            filename = base.isEmpty ? "playback" : base
        } else {
            filename = remoteURL.deletingPathExtension().lastPathComponent.isEmpty
                ? "playback"
                : remoteURL.deletingPathExtension().lastPathComponent
        }

        guard !ext.isEmpty else {
            return filename
        }
        return "\(filename).\(ext)"
    }

    private func preferredExtension(remoteURL: URL, response: URLResponse) -> String {
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

        return remoteURL.pathExtension.lowercased()
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CacheError.invalidResponse
        }

        if let mimeType = httpResponse.mimeType, isKnownUnsupportedOfflineMediaType(mimeType) {
            throw CacheError.unsupportedOfflineMediaType(mimeType)
        }
    }

    private func isKnownUnsupportedOfflineMediaType(_ mimeType: String) -> Bool {
        let normalized = mimeType.lowercased()
        return normalized == "audio/webm" || normalized == "video/webm"
    }

    private func cacheDirectory(createIfNeeded: Bool) throws -> URL {
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent("DreamCratesPlaybackCache", isDirectory: true)
        if createIfNeeded {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
