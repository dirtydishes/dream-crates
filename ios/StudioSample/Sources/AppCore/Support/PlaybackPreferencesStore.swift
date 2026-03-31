import Foundation

@MainActor
final class PlaybackPreferencesStore: ObservableObject {
    private enum Keys {
        static let mode = "dreamCrates.playbackMode"
        static let speed = "dreamCrates.playbackSpeed"
        static let transposeSemitones = "dreamCrates.playbackTransposeSemitones"
    }

    @Published var mode: PlaybackMode {
        didSet {
            userDefaults.set(mode.rawValue, forKey: Keys.mode)
        }
    }

    @Published var speed: Double {
        didSet {
            let clamped = PlaybackSettings.clampSpeed(speed)
            guard speed == clamped else {
                speed = clamped
                return
            }
            userDefaults.set(speed, forKey: Keys.speed)
        }
    }

    @Published var transposeSemitones: Double {
        didSet {
            let clamped = PlaybackSettings.clampTranspose(transposeSemitones)
            guard transposeSemitones == clamped else {
                transposeSemitones = clamped
                return
            }
            userDefaults.set(transposeSemitones, forKey: Keys.transposeSemitones)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedMode = userDefaults.string(forKey: Keys.mode).flatMap(PlaybackMode.init(rawValue:))
        let storedSpeed = userDefaults.object(forKey: Keys.speed) as? Double
        let storedTranspose = userDefaults.object(forKey: Keys.transposeSemitones) as? Double
        self.mode = storedMode ?? .turntable
        self.speed = PlaybackSettings.clampSpeed(storedSpeed ?? 1.0)
        self.transposeSemitones = PlaybackSettings.clampTranspose(storedTranspose ?? 0)
    }

    var currentSettings: PlaybackSettings {
        PlaybackSettings(
            mode: mode,
            speed: speed,
            transposeSemitones: transposeSemitones
        )
    }
}
