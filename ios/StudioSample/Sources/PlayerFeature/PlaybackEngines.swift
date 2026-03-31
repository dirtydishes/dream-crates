import AVFoundation

@MainActor
protocol PlaybackEngine: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var hasItem: Bool { get }
    var currentURL: URL? { get }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onPlaybackFailed: (() -> Void)? { get set }

    func load(sourceURL: URL, startTime: Double, settings: PlaybackSettings, autoplay: Bool) throws
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
    private var currentDuration: Double = 0
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
        return seconds.isFinite ? seconds : 0
    }

    var duration: Double {
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
            return itemDuration
        }
        return currentDuration
    }

    var hasItem: Bool {
        player.currentItem != nil
    }

    var currentURL: URL? {
        (player.currentItem?.asset as? AVURLAsset)?.url
    }

    func load(sourceURL: URL, startTime: Double, settings: PlaybackSettings, autoplay: Bool) throws {
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
        currentDuration = 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let duration = try await asset.load(.duration).seconds
                if duration.isFinite {
                    self.currentDuration = duration
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
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentDuration = 0
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
                        self.currentDuration = duration
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
    private var pausedTime: Double = 0
    private var durationSeconds: Double = 0
    private var scheduledStartFrame: AVAudioFramePosition = 0
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
        guard let currentFile else { return 0 }
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else {
            return pausedTime
        }

        let sampleRate = currentFile.processingFormat.sampleRate
        let elapsed = Double(scheduledStartFrame + AVAudioFramePosition(playerTime.sampleTime)) / sampleRate
        return min(max(elapsed, 0), durationSeconds)
    }

    var duration: Double {
        durationSeconds
    }

    var hasItem: Bool {
        currentFile != nil
    }

    var currentURL: URL? {
        currentFileURL
    }

    func load(sourceURL: URL, startTime: Double, settings: PlaybackSettings, autoplay: Bool) throws {
        if currentFileURL != sourceURL {
            currentFile = try AVAudioFile(forReading: sourceURL)
            currentFileURL = sourceURL
            if let currentFile {
                durationSeconds = Double(currentFile.length) / currentFile.processingFormat.sampleRate
            } else {
                durationSeconds = 0
            }
        }

        update(settings: settings)
        try ensureEngineRunning()
        try schedulePlayback(at: startTime, autoplay: autoplay)
    }

    func play() {
        guard hasItem else { return }
        if currentTime >= max(durationSeconds - 0.05, 0), durationSeconds > 0 {
            seek(to: 0)
        }
        do {
            try ensureEngineRunning()
            playerNode.play()
        } catch {
            onPlaybackFailed?()
        }
    }

    func pause() {
        pausedTime = currentTime
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
        pausedTime = 0
        durationSeconds = 0
        scheduledStartFrame = 0
        currentFile = nil
        currentFileURL = nil
    }

    func update(settings: PlaybackSettings) {
        timePitch.rate = Float(settings.speed)
        timePitch.pitch = Float(settings.effectiveTransposeSemitones * 100)
    }

    private func ensureEngineRunning() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    private func schedulePlayback(at seconds: Double, autoplay: Bool) throws {
        guard let currentFile else { return }

        let sampleRate = currentFile.processingFormat.sampleRate
        let clampedTime = max(0, min(seconds, durationSeconds))
        let startFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let remainingFrameCount = max(currentFile.length - startFrame, 0)

        completionToken = UUID()
        pausedTime = clampedTime
        scheduledStartFrame = startFrame
        playerNode.stop()
        playerNode.reset()

        guard remainingFrameCount > 0 else {
            pausedTime = durationSeconds
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
                self.pausedTime = self.durationSeconds
                self.onPlaybackEnded?()
            }
        }

        if autoplay {
            playerNode.play()
        }
    }
}
