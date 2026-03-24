import Foundation

actor DownloadManager {
    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func download(sampleID: String, from sourceURL: URL) async throws -> URL {
        let (tmpURL, _) = try await URLSession.shared.download(from: sourceURL)
        let dir = try downloadsDirectory()

        let destination = dir.appendingPathComponent("\(sampleID).mp3")
        if fileManager.fileExists(atPath: destination.path()) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tmpURL, to: destination)

        return destination
    }

    func existingDownloads() throws -> [String: URL] {
        let dir = try downloadsDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var result: [String: URL] = [:]
        for url in urls where url.pathExtension == "mp3" {
            result[url.deletingPathExtension().lastPathComponent] = url
        }
        return result
    }

    private func downloadsDirectory() throws -> URL {
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("DreamCratesDownloads", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
