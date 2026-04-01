import ActivityKit
import Foundation

struct DownloadLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var statusText: String
        var progress: Double?
        var isFinished: Bool
    }

    var sampleID: String
    var title: String
    var uploaderName: String
    var uploaderImageURLString: String?
}
