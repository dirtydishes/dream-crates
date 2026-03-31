import AVFoundation
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var effectiveVisualRate: Double = 1.0

    private let turntableEngine: PlaybackEngine
    private let warpEngine: PlaybackEngine

    private var remoteConfigured = false
    private var currentTitle = "Dream Crates"
    private var currentSourceURL: URL?
    private var currentSettings = PlaybackSettings()
    private var activeMode: PlaybackMode?
    private var progressTimer: Timer?

    init() {
        self.turntableEngine = TurntablePlaybackEngine()
        self.warpEngine = WarpPlaybackEngine()
        wire(engine: turntableEngine)
        wire(engine: warpEngine)
    }

    init(turntableEngine: PlaybackEngine, warpEngine: PlaybackEngine) {
        self.turntableEngine = turntableEngine
        self.warpEngine = warpEngine
        wire(engine: turntableEngine)
        wire(engine: warpEngine)
    }

    deinit {
        progressTimer?.invalidate()
    }

    var hasCurrentItem: Bool {
        activeEngine?.hasItem == true
    }

    var canResumeCurrentItem: Bool {
        currentSourceURL != nil && hasCurrentItem && (isPlaying || currentTime > 0 || duration > 0)
    }

    func configureIfNeeded() {
        guard !remoteConfigured else { return }
        configureAudioSession()
        configureRemoteCommands()
        configureProgressTimer()
        remoteConfigured = true
    }

    func play(
        title: String,
        sourceURL: URL,
        settings: PlaybackSettings,
        startTime: Double = 0,
        autoplay: Bool = true
    ) {
        currentTitle = title
        currentSettings = normalized(settings, for: settings.mode)
        let shouldReuseCurrentItem = currentSourceURL == sourceURL && activeMode == currentSettings.mode && hasCurrentItem

        if !shouldReuseCurrentItem {
            switchActiveEngine(to: currentSettings.mode)
            do {
                try activeEngine?.load(
                    sourceURL: sourceURL,
                    startTime: startTime,
                    settings: currentSettings,
                    autoplay: autoplay
                )
            } catch {
                stopAndReset()
                return
            }
        } else {
            activeEngine?.update(settings: currentSettings)
            if abs(startTime - currentTime) > 0.05 {
                activeEngine?.seek(to: startTime)
            }
            autoplay ? activeEngine?.play() : activeEngine?.pause()
        }

        currentSourceURL = sourceURL
        syncState()
    }

    func pause() {
        activeEngine?.pause()
        syncState()
    }

    func resume() {
        guard hasCurrentItem else { return }
        if duration > 0, currentTime >= max(duration - 0.25, 0) {
            seek(to: 0)
        }
        activeEngine?.update(settings: currentSettings)
        activeEngine?.play()
        syncState()
    }

    func togglePlayback() {
        isPlaying ? pause() : resume()
    }

    func seek(to seconds: Double) {
        guard hasCurrentItem else { return }
        activeEngine?.seek(to: seconds)
        syncState()
    }

    func stopAndReset() {
        turntableEngine.stop()
        warpEngine.stop()
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSourceURL = nil
        activeMode = nil
        updateNowPlaying(title: currentTitle)
    }

    func applyPreferences(_ settings: PlaybackSettings) {
        currentSettings = normalized(settings, for: activeMode ?? settings.mode)
        activeEngine?.update(settings: currentSettings)
        syncState()
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
            self.applyPreferences(self.currentSettings.with(speed: Double(rateEvent.playbackRate)))
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

    private var activeEngine: PlaybackEngine? {
        switch activeMode {
        case .warp:
            warpEngine
        case .turntable:
            turntableEngine
        case nil:
            nil
        }
    }

    private func wire(engine: PlaybackEngine) {
        engine.onPlaybackEnded = { [weak self] in
            guard let self else { return }
            self.syncState()
            self.currentTime = self.duration
            self.isPlaying = false
            self.updateNowPlaying(title: self.currentTitle)
        }

        engine.onPlaybackFailed = { [weak self] in
            self?.stopAndReset()
        }
    }

    private func switchActiveEngine(to mode: PlaybackMode) {
        guard activeMode != mode else { return }
        activeEngine?.stop()
        activeMode = mode
    }

    private func configureProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncState()
            }
        }
    }

    private func syncState() {
        guard let activeEngine else {
            isPlaying = false
            currentTime = 0
            duration = 0
            effectiveVisualRate = currentSettings.speed
            updateNowPlaying(title: currentTitle)
            return
        }

        isPlaying = activeEngine.isPlaying
        currentTime = activeEngine.currentTime
        duration = activeEngine.duration
        effectiveVisualRate = currentSettings.speed
        updateNowPlaying(title: currentTitle)
    }

    private func normalized(_ settings: PlaybackSettings, for mode: PlaybackMode) -> PlaybackSettings {
        let adjusted = settings.with(mode: mode)
        return mode == .turntable ? adjusted.with(transposeSemitones: 0) : adjusted
    }

    private func updateNowPlaying(title: String?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "Dream Crates",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? currentSettings.speed : 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
        ]
        if duration > 0, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
