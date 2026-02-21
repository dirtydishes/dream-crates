import Foundation

struct SampleItem: Identifiable, Hashable, Codable {
    let id: String
    let youtubeVideoId: String
    let channelId: String
    let title: String
    let descriptionText: String
    let publishedAt: Date
    let artworkURL: URL?
    let durationSeconds: Int?
    let genreTags: [TagScore]
    let toneTags: [TagScore]
    var isSaved: Bool
    var savedAt: Date?
    var downloadState: DownloadState
    var streamState: StreamState
}

struct TagScore: Hashable, Codable {
    let key: String
    let confidence: Double
}

enum DownloadState: String, Hashable, Codable {
    case notDownloaded
    case queued
    case downloading
    case downloaded
    case failed
}

enum StreamState: String, Hashable, Codable {
    case idle
    case resolving
    case ready
    case expired
    case failed
}
