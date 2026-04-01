import Foundation

struct SampleItem: Identifiable, Hashable, Codable {
    let id: String
    let youtubeVideoId: String
    let channelId: String
    let channelTitle: String?
    let channelHandle: String?
    let channelAvatarURL: URL?
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
        case channelTitle = "channel_title"
        case channelHandle = "channel_handle"
        case channelAvatarURL = "channel_avatar_url"
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

    var uploaderName: String {
        if let channelTitle, !channelTitle.isEmpty {
            return channelTitle
        }
        if let channelHandle, !channelHandle.isEmpty {
            return normalizedHandle(channelHandle).replacingOccurrences(of: "@", with: "")
        }
        return "YouTube Channel"
    }

    var uploaderSubtitle: String? {
        guard let channelHandle, !channelHandle.isEmpty else {
            return nil
        }
        let handle = normalizedHandle(channelHandle)
        guard handle.caseInsensitiveCompare(uploaderName) != .orderedSame else {
            return nil
        }
        return handle
    }

    private func normalizedHandle(_ handle: String) -> String {
        handle.hasPrefix("@") ? handle : "@\(handle)"
    }
}

struct TagScore: Hashable, Codable {
    let key: String
    let confidence: Double
}

enum DownloadState: String, Hashable, Codable, Sendable {
    case notDownloaded = "not_downloaded"
    case queued
    case downloading
    case downloaded
    case failed
}

enum StreamState: String, Hashable, Codable, Sendable {
    case idle
    case resolving
    case ready
    case expired
    case failed
}

enum DownloadLogLevel: String, Hashable, Codable, Sendable {
    case info
    case warning
    case error
}

struct DownloadLogEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let sampleID: String
    let timestamp: Date
    let level: DownloadLogLevel
    let message: String

    init(
        id: UUID = UUID(),
        sampleID: String,
        timestamp: Date = .now,
        level: DownloadLogLevel,
        message: String
    ) {
        self.id = id
        self.sampleID = sampleID
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

struct DownloadRuntimeSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let uploaderName: String
    let uploaderAvatarURL: URL?
    let statusText: String
    let progress: Double?
    let state: DownloadState
    let startedAt: Date
    let updatedAt: Date
}

struct DownloadTransportEvent: Hashable, Sendable {
    let level: DownloadLogLevel
    let message: String
}
