import AVFoundation

struct PlaybackTimeline {
    let speed: Double

    private var effectiveSpeed: Double {
        max(speed, 0.01)
    }

    func displayTime(fromSourceTime sourceTime: Double) -> Double {
        sourceTime / effectiveSpeed
    }

    func sourceTime(fromDisplayTime displayTime: Double) -> Double {
        displayTime * effectiveSpeed
    }

    func displayDuration(fromSourceDuration sourceDuration: Double) -> Double {
        sourceDuration / effectiveSpeed
    }

    static func sourceTime(
        scheduledStartTime: Double,
        playerSampleTime: AVAudioFramePosition,
        playerSampleRate: Double
    ) -> Double {
        guard playerSampleRate > 0 else { return scheduledStartTime }
        return scheduledStartTime + (Double(playerSampleTime) / playerSampleRate)
    }
}

@MainActor
protocol PlaybackEngine: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var hasItem: Bool { get }
    var currentURL: URL? { get }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onPlaybackFailed: (() -> Void)? { get set }

    func load(
        sourceURL: URL,
        startTime: Double,
        settings: PlaybackSettings,
        expectedDuration: Double?,
        autoplay: Bool
    ) throws
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()
    func update(settings: PlaybackSettings)
}

@MainActor
final class TurntablePlaybackEngine: PlaybackEngine {
    var onPlaybackEnded: (() -> Void)?
    var onPlaybackFailed: (() -> Void)?

    private let player: AVPlayer
    private var currentRate: Float = 1.0
    private var sourceDuration: Double = 0
    private var expectedSourceDuration: Double?
    private var playbackEndedObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
    }

    deinit {
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
    }

    var isPlaying: Bool {
        player.rate != 0
    }

    var currentTime: Double {
        let seconds = player.currentTime().seconds
        let sourceTime = seconds.isFinite ? seconds : 0
        return timeline.displayTime(fromSourceTime: sourceTime)
    }

    var duration: Double {
        let sourceTime = preferredSourceDuration
        return timeline.displayDuration(fromSourceDuration: sourceTime)
    }

    private var timeline: PlaybackTimeline {
        PlaybackTimeline(speed: Double(currentRate))
    }

    private var rawDuration: Double {
        let itemDuration = player.currentItem?.duration.seconds
        if itemDuration?.isFinite == true {
            return itemDuration!
        }
        return sourceDuration
    }

    private var preferredSourceDuration: Double {
        if let expectedSourceDuration, expectedSourceDuration > 0 {
            return expectedSourceDuration
        }
        return rawDuration
    }

    var hasItem: Bool {
        player.currentItem != nil
    }

    var currentURL: URL? {
        (player.currentItem?.asset as? AVURLAsset)?.url
    }

    func load(
        sourceURL: URL,
        startTime: Double,
        settings: PlaybackSettings,
        expectedDuration: Double?,
        autoplay: Bool
    ) throws {
        let asset = AVURLAsset(
            url: sourceURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5
        item.audioTimePitchAlgorithm = .varispeed
        observeStatus(for: item)
        observePlaybackEnded(for: item)

        player.replaceCurrentItem(with: item)
        sourceDuration = 0
        expectedSourceDuration = expectedDuration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let duration = try await asset.load(.duration).seconds
                if duration.isFinite {
                    self.sourceDuration = duration
                }
            } catch {
                // Keep the player usable even if duration metadata loads late or fails.
            }
        }
        update(settings: settings)
        if startTime > 0 {
            seek(to: startTime)
        }
        autoplay ? play() : pause()
    }

    func play() {
        guard hasItem else { return }
        player.playImmediately(atRate: currentRate)
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        guard hasItem else { return }
        let target = max(0, min(seconds, duration.isFinite && duration > 0 ? duration : seconds))
        let sourceTarget = timeline.sourceTime(fromDisplayTime: target)
        let maxSourceDuration = preferredSourceDuration
        let clampedSourceTarget = max(
            0,
            min(sourceTarget, maxSourceDuration.isFinite && maxSourceDuration > 0 ? maxSourceDuration : sourceTarget)
        )
        player.seek(
            to: CMTime(seconds: clampedSourceTarget, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        sourceDuration = 0
        expectedSourceDuration = nil
        itemStatusObserver = nil
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
            self.playbackEndedObserver = nil
        }
    }

    func update(settings: PlaybackSettings) {
        currentRate = Float(settings.speed)
        player.currentItem?.audioTimePitchAlgorithm = .varispeed
        if isPlaying {
            player.rate = currentRate
        }
    }

    private func observeStatus(for item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self else { return }
            Task { @MainActor in
                if observedItem.status == .readyToPlay {
                    let duration = observedItem.duration.seconds
                    if duration.isFinite {
                        self.sourceDuration = duration
                    }
                } else if observedItem.status == .failed {
                    self.onPlaybackFailed?()
                }
            }
        }
    }

    private func observePlaybackEnded(for item: AVPlayerItem) {
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.onPlaybackEnded?()
            }
        }
    }
}

@MainActor
final class WarpPlaybackEngine: PlaybackEngine {
    var onPlaybackEnded: (() -> Void)?
    var onPlaybackFailed: (() -> Void)?

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let timePitch: AVAudioUnitTimePitch

    private var currentFile: AVAudioFile?
    private var currentFileURL: URL?
    private var currentSettings = PlaybackSettings(mode: .warp)
    private var pausedSourceTime: Double = 0
    private var sourceDurationSeconds: Double = 0
    private var pausedDisplayTime: Double = 0
    private var playbackAnchorDisplayTime: Double = 0
    private var playbackAnchorHostTime: CFTimeInterval?
    private var completionToken = UUID()

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        playerNode: AVAudioPlayerNode = AVAudioPlayerNode(),
        timePitch: AVAudioUnitTimePitch = AVAudioUnitTimePitch()
    ) {
        self.engine = engine
        self.playerNode = playerNode
        self.timePitch = timePitch
        timePitch.overlap = 16

        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.connect(playerNode, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    var currentTime: Double {
        let displayTime: Double
        if isPlaying, let playbackAnchorHostTime {
            displayTime = playbackAnchorDisplayTime + max(CACurrentMediaTime() - playbackAnchorHostTime, 0)
        } else {
            displayTime = pausedDisplayTime
        }
        return min(max(displayTime, 0), duration)
    }

    var duration: Double {
        timeline.displayDuration(fromSourceDuration: sourceDurationSeconds)
    }

    var hasItem: Bool {
        currentFile != nil
    }

    var currentURL: URL? {
        currentFileURL
    }

    func load(
        sourceURL: URL,
        startTime: Double,
        settings: PlaybackSettings,
        expectedDuration _: Double?,
        autoplay: Bool
    ) throws {
        if currentFileURL != sourceURL {
            currentFile = try AVAudioFile(forReading: sourceURL)
            currentFileURL = sourceURL
            if let currentFile {
                sourceDurationSeconds = Double(currentFile.length) / currentFile.processingFormat.sampleRate
            } else {
                sourceDurationSeconds = 0
            }
        }

        currentSettings = settings
        applyNodeSettings(settings)
        try ensureEngineRunning()
        try schedulePlayback(at: startTime, autoplay: autoplay)
    }

    func play() {
        guard hasItem else { return }
        if currentTime >= max(duration - 0.05, 0), duration > 0 {
            seek(to: 0)
        }
        do {
            try ensureEngineRunning()
            playerNode.play()
            playbackAnchorDisplayTime = pausedDisplayTime
            playbackAnchorHostTime = CACurrentMediaTime()
        } catch {
            onPlaybackFailed?()
        }
    }

    func pause() {
        pausedDisplayTime = currentTime
        pausedSourceTime = timeline.sourceTime(fromDisplayTime: pausedDisplayTime)
        playbackAnchorHostTime = nil
        playerNode.pause()
    }

    func seek(to seconds: Double) {
        guard hasItem else { return }
        let shouldAutoplay = isPlaying
        do {
            try schedulePlayback(at: seconds, autoplay: shouldAutoplay)
        } catch {
            onPlaybackFailed?()
        }
    }

    func stop() {
        completionToken = UUID()
        playerNode.stop()
        pausedSourceTime = 0
        sourceDurationSeconds = 0
        pausedDisplayTime = 0
        playbackAnchorDisplayTime = 0
        playbackAnchorHostTime = nil
        currentFile = nil
        currentFileURL = nil
    }

    func update(settings: PlaybackSettings) {
        let displayTime = currentTime
        let sourceTime = timeline.sourceTime(fromDisplayTime: displayTime)
        let shouldAutoplay = isPlaying
        let previousSettings = currentSettings
        currentSettings = settings
        applyNodeSettings(settings)

        guard hasItem else { return }
        let needsReschedule =
            previousSettings.speed != settings.speed ||
            previousSettings.effectiveTransposeSemitones != settings.effectiveTransposeSemitones
        guard needsReschedule else { return }

        do {
            try ensureEngineRunning()
            try schedulePlayback(atSourceTime: sourceTime, autoplay: shouldAutoplay)
        } catch {
            onPlaybackFailed?()
        }
    }

    private var timeline: PlaybackTimeline {
        PlaybackTimeline(speed: currentSettings.speed)
    }

    private func ensureEngineRunning() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    private func schedulePlayback(at seconds: Double, autoplay: Bool) throws {
        let clampedTime = max(0, min(seconds, duration))
        let startSourceTime = timeline.sourceTime(fromDisplayTime: clampedTime)
        try schedulePlayback(atSourceTime: startSourceTime, autoplay: autoplay)
    }

    private func applyNodeSettings(_ settings: PlaybackSettings) {
        timePitch.rate = Float(settings.speed)
        timePitch.pitch = Float(settings.effectiveTransposeSemitones * 100)
    }

    private func schedulePlayback(atSourceTime sourceTime: Double, autoplay: Bool) throws {
        if let currentFileURL {
            currentFile = try AVAudioFile(forReading: currentFileURL)
        }
        guard let currentFile else { return }

        let sampleRate = currentFile.processingFormat.sampleRate
        let clampedSourceTime = max(0, min(sourceTime, sourceDurationSeconds))
        let clampedDisplayTime = timeline.displayTime(fromSourceTime: clampedSourceTime)
        let startFrame = AVAudioFramePosition(clampedSourceTime * sampleRate)
        let remainingFrameCount = max(currentFile.length - startFrame, 0)

        completionToken = UUID()
        pausedSourceTime = clampedSourceTime
        pausedDisplayTime = clampedDisplayTime
        playbackAnchorDisplayTime = clampedDisplayTime
        playbackAnchorHostTime = nil
        playerNode.stop()
        playerNode.reset()

        guard remainingFrameCount > 0 else {
            pausedSourceTime = sourceDurationSeconds
            pausedDisplayTime = duration
            onPlaybackEnded?()
            return
        }

        let token = completionToken
        playerNode.scheduleSegment(
            currentFile,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrameCount),
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.completionToken == token else { return }
                self.pausedSourceTime = self.sourceDurationSeconds
                self.pausedDisplayTime = self.duration
                self.playbackAnchorHostTime = nil
                self.onPlaybackEnded?()
            }
        }

        if autoplay {
            playerNode.play()
            playbackAnchorDisplayTime = clampedDisplayTime
            playbackAnchorHostTime = CACurrentMediaTime()
        }
    }
}
