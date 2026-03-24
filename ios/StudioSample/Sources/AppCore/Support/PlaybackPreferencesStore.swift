import Foundation

@MainActor
final class PlaybackPreferencesStore: ObservableObject {
    private enum Keys {
        static let speed = "dreamCrates.playbackSpeed"
    }

    @Published var speed: Double {
        didSet {
            userDefaults.set(speed, forKey: Keys.speed)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let stored = userDefaults.object(forKey: Keys.speed) as? Double
        self.speed = stored ?? 1.0
    }
}
