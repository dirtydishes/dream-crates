import Foundation

struct Channel: Identifiable, Hashable, Codable {
    let id: String
    let handle: String
    let title: String
    let avatarURL: URL?
    var isTracked: Bool
}
