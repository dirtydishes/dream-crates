import Foundation
import UniformTypeIdentifiers

actor DownloadManager {
    typealias ProgressHandler = @Sendable (Double) async -> Void

    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func download(
        sampleID: String,
        from sourceURL: URL,
        onProgress: ProgressHandler? = nil
    ) async throws -> URL {
        let (tmpURL, response) = try await performDownload(from: sourceURL, onProgress: onProgress)
        let dir = try sampleDirectory(for: sampleID, createDirectory: true)
        try removeExistingFiles(in: dir)
        try removeLegacyFiles(for: sampleID)

        let destination = dir.appendingPathComponent(destinationFilename(sourceURL: sourceURL, response: response))
        if fileManager.fileExists(atPath: destination.path()) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tmpURL, to: destination)

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
        if let suggested = response.suggestedFilename, !suggested.isEmpty {
            return suggested
        }

        let ext = preferredExtension(sourceURL: sourceURL, response: response)
        guard !ext.isEmpty else {
            return "download"
        }
        return "download.\(ext)"
    }

    private func preferredExtension(sourceURL: URL, response: URLResponse) -> String {
        if let suggested = response.suggestedFilename {
            let ext = URL(fileURLWithPath: suggested).pathExtension
            if !ext.isEmpty {
                return ext.lowercased()
            }
        }

        if let mimeType = response.mimeType,
           let type = UTType(mimeType: mimeType),
           let ext = type.preferredFilenameExtension {
            return ext.lowercased()
        }

        return sourceURL.pathExtension.lowercased()
    }

    private func performDownload(
        from sourceURL: URL,
        onProgress: ProgressHandler?
    ) async throws -> (temporaryURL: URL, response: URLResponse) {
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

    private func downloadsDirectory() throws -> URL {
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("DreamCratesDownloads", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
