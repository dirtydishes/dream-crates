import Foundation

enum PlaybackMode: String, CaseIterable, Identifiable {
    case warp
    case turntable

    var id: Self { self }

    var displayName: String {
        switch self {
        case .warp:
            "Warp"
        case .turntable:
            "Turntable"
        }
    }
}

struct PlaybackSettings: Equatable {
    static let speedRange: ClosedRange<Double> = 0.5 ... 2.0
    static let transposeRange: ClosedRange<Double> = -12 ... 12

    var mode: PlaybackMode = .turntable
    var speed: Double = 1.0
    var transposeSemitones: Double = 0

    init(mode: PlaybackMode = .turntable, speed: Double = 1.0, transposeSemitones: Double = 0) {
        self.mode = mode
        self.speed = Self.clampSpeed(speed)
        self.transposeSemitones = Self.clampTranspose(transposeSemitones)
    }

    var effectiveTransposeSemitones: Double {
        mode == .warp ? transposeSemitones : 0
    }

    func with(
        mode: PlaybackMode? = nil,
        speed: Double? = nil,
        transposeSemitones: Double? = nil
    ) -> PlaybackSettings {
        PlaybackSettings(
            mode: mode ?? self.mode,
            speed: speed ?? self.speed,
            transposeSemitones: transposeSemitones ?? self.transposeSemitones
        )
    }

    static func clampSpeed(_ value: Double) -> Double {
        min(max(value, speedRange.lowerBound), speedRange.upperBound)
    }

    static func clampTranspose(_ value: Double) -> Double {
        min(max(value, transposeRange.lowerBound), transposeRange.upperBound)
    }
}
