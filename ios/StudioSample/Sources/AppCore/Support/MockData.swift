import Foundation

enum MockData {
    static let samples: [SampleItem] = [
        SampleItem(
            id: "sample-1",
            youtubeVideoId: "yt-1",
            channelId: "andre",
            title: "Dark Vinyl Texture Sample Pack",
            descriptionText: "Fresh textures for late-night sessions.",
            publishedAt: .now.addingTimeInterval(-3600),
            artworkURL: nil,
            durationSeconds: 124,
            genreTags: [.init(key: "trap", confidence: 0.84)],
            toneTags: [.init(key: "gritty", confidence: 0.78)],
            isSaved: true,
            savedAt: .now.addingTimeInterval(-1800),
            downloadState: .downloaded,
            streamState: .ready
        ),
        SampleItem(
            id: "sample-2",
            youtubeVideoId: "yt-2",
            channelId: "andre",
            title: "Warm Tape Keys One-Shots",
            descriptionText: "Dusty melodic one-shots.",
            publishedAt: .now.addingTimeInterval(-7200),
            artworkURL: nil,
            durationSeconds: 93,
            genreTags: [.init(key: "lo_fi", confidence: 0.73)],
            toneTags: [.init(key: "warm", confidence: 0.92)],
            isSaved: false,
            savedAt: nil,
            downloadState: .notDownloaded,
            streamState: .ready
        )
    ]
}
