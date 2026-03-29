import Foundation

struct Channel: Identifiable, Hashable, Codable {
    let id: String
    let handle: String
    let title: String
    let avatarURL: URL?
    var isTracked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case title
        case avatarURL = "avatar_url"
        case isTracked = "is_tracked"
    }
}
