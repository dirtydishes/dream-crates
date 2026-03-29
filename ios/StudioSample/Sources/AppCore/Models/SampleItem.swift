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

    enum CodingKeys: String, CodingKey {
        case id
        case youtubeVideoId = "youtube_video_id"
        case channelId = "channel_id"
        case title
        case descriptionText = "description_text"
        case publishedAt = "published_at"
        case artworkURL = "artwork_url"
        case durationSeconds = "duration_seconds"
        case genreTags = "genre_tags"
        case toneTags = "tone_tags"
        case isSaved = "is_saved"
        case savedAt = "saved_at"
        case downloadState = "download_state"
        case streamState = "stream_state"
    }
}

struct TagScore: Hashable, Codable {
    let key: String
    let confidence: Double
}

enum DownloadState: String, Hashable, Codable {
    case notDownloaded = "not_downloaded"
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
