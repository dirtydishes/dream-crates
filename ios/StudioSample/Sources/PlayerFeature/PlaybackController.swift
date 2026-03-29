import AVFoundation
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Float = 1.0

    private let player = AVPlayer()
    private var remoteConfigured = false

    func configureIfNeeded() {
        guard !remoteConfigured else { return }
        configureAudioSession()
        configureRemoteCommands()
        remoteConfigured = true
    }

    func play(title: String, sourceURL: URL, rate: Float) {
        self.rate = rate

        player.replaceCurrentItem(with: AVPlayerItem(url: sourceURL))

        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying(title: title)
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func updateRate(_ value: Float) {
        rate = value
        if isPlaying {
            player.rate = value
        }
        updateNowPlaying(title: MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // `allowBluetooth` is available on older CI Xcode SDKs, unlike `allowBluetoothHFP`.
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
        } catch {
            // Keep player functional even if background session setup fails.
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard let sourceURL = URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3") else {
                return .commandFailed
            }
            self.play(title: "Dream Crates", sourceURL: sourceURL, rate: self.rate)
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, let rateEvent = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            self.updateRate(rateEvent.playbackRate)
            return .success
        }
    }

    private func updateNowPlaying(title: String?) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title ?? "Dream Crates",
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]
    }
}
