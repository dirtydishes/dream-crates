import Foundation

actor PlaybackCache {
    typealias DownloadOperation = @Sendable (URL) async throws -> URL

    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let downloadOperation: DownloadOperation
    private var inflightDownloads: [String: Task<URL, Error>] = [:]

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        downloadOperation: @escaping DownloadOperation = { url in
            let (tmpURL, _) = try await URLSession.shared.download(from: url)
            return tmpURL
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
            let tmpURL = try await downloadOperation(remoteURL)
            return try await self.storeDownloadedFile(
                sampleID: sampleID,
                temporaryURL: tmpURL,
                remoteURL: remoteURL
            )
        }
        inflightDownloads[sampleID] = task

        defer { inflightDownloads[sampleID] = nil }
        return try await task.value
    }

    private func storeDownloadedFile(sampleID: String, temporaryURL: URL, remoteURL: URL) async throws -> URL {
        let directory = try sampleDirectory(for: sampleID, createDirectory: true)
        try removeExistingFiles(in: directory)

        let destination = directory.appendingPathComponent(destinationFilename(remoteURL: remoteURL))
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

    private func destinationFilename(remoteURL: URL) -> String {
        let ext = remoteURL.pathExtension
        guard !ext.isEmpty else {
            return "playback"
        }
        return "playback.\(ext)"
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
