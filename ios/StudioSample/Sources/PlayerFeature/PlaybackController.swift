import AVFoundation
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Float = 1.0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private let player = AVPlayer()
    private var remoteConfigured = false
    private var currentTitle = "Dream Crates"
    private var currentSourceURL: URL?
    private var timeObserverToken: Any?
    private var playbackEndedObserver: NSObjectProtocol?

    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
    }

    var hasCurrentItem: Bool {
        player.currentItem != nil
    }

    func configureIfNeeded() {
        guard !remoteConfigured else { return }
        configureAudioSession()
        configureRemoteCommands()
        configureObservers()
        remoteConfigured = true
    }

    func play(title: String, sourceURL: URL, rate: Float) {
        self.rate = rate
        currentTitle = title
        if currentSourceURL == sourceURL, hasCurrentItem {
            resume()
            return
        }

        currentSourceURL = sourceURL
        currentTime = 0
        duration = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: sourceURL))
        resume()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying(title: currentTitle)
    }

    func resume() {
        guard hasCurrentItem else { return }
        if duration > 0, currentTime >= max(duration - 0.25, 0) {
            seek(to: 0)
        }
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying(title: currentTitle)
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func seek(to seconds: Double) {
        guard hasCurrentItem else { return }
        let target = max(0, min(seconds, duration.isFinite && duration > 0 ? duration : seconds))
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying(title: currentTitle)
    }

    func updateRate(_ value: Float) {
        rate = value
        if isPlaying {
            player.rate = value
        }
        updateNowPlaying(title: currentTitle)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            // Keep player functional even if background session setup fails.
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.resume()
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

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    private func configureObservers() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite {
                    self.duration = itemDuration
                }
                self.updateNowPlaying(title: self.currentTitle)
            }
        }

        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                guard notification.object as? AVPlayerItem === self.player.currentItem else { return }
                self.isPlaying = false
                self.currentTime = self.duration
                self.updateNowPlaying(title: self.currentTitle)
            }
        }
    }

    private func updateNowPlaying(title: String?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "Dream Crates",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
        ]
        if duration > 0, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
