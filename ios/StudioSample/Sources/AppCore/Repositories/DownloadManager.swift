import Foundation

actor DownloadManager {
    private let fileManager = FileManager.default

    func download(sampleID: String, from sourceURL: URL) async throws -> URL {
        let (tmpURL, _) = try await URLSession.shared.download(from: sourceURL)

        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudioSampleDownloads", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let destination = dir.appendingPathComponent("\(sampleID).mp3")
        if fileManager.fileExists(atPath: destination.path()) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tmpURL, to: destination)

        return destination
    }
}
