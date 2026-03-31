import XCTest
@testable import StudioSampleApp

@MainActor
private final class FakePlaybackEngine: PlaybackEngine {
    struct LoadCall {
        let sourceURL: URL
        let startTime: Double
        let settings: PlaybackSettings
        let autoplay: Bool
    }

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 120
    var hasItem = false
    var currentURL: URL?
    var onPlaybackEnded: (() -> Void)?
    var onPlaybackFailed: (() -> Void)?

    private(set) var loadCalls: [LoadCall] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekCalls: [Double] = []
    private(set) var stopCallCount = 0
    private(set) var updateCalls: [PlaybackSettings] = []

    func load(sourceURL: URL, startTime: Double, settings: PlaybackSettings, autoplay: Bool) throws {
        currentURL = sourceURL
        currentTime = startTime
        hasItem = true
        isPlaying = autoplay
        loadCalls.append(
            LoadCall(
                sourceURL: sourceURL,
                startTime: startTime,
                settings: settings,
                autoplay: autoplay
            )
        )
    }

    func play() {
        guard hasItem else { return }
        isPlaying = true
        playCallCount += 1
    }

    func pause() {
        isPlaying = false
        pauseCallCount += 1
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        seekCalls.append(seconds)
    }

    func stop() {
        isPlaying = false
        hasItem = false
        currentURL = nil
        currentTime = 0
        stopCallCount += 1
    }

    func update(settings: PlaybackSettings) {
        updateCalls.append(settings)
    }
}

private final class DownloadCounter: @unchecked Sendable {
    var count = 0
}

@MainActor
private final class FakeRepository: SampleRepository {
    struct OfflineError: Error {}

    let items: [SampleItem]
    var savedLibrary: [SampleItem]
    var updatedSavedStates: [(String, Bool)] = []
    var playbackURL = URL(string: "https://example.com/playback.m4a")!
    var downloadURL = URL(string: "https://example.com/download.m4a")!
    var shouldFailUpdates = false
    var resolvePlaybackCalls = 0
    var prepareDownloadCalls = 0

    init(items: [SampleItem], savedLibrary: [SampleItem]? = nil) {
        self.items = items
        self.savedLibrary = savedLibrary ?? items.filter(\.isSaved)
    }

    func loadInitialFeed() async throws -> [SampleItem] {
        items
    }

    func refreshFeed() async throws -> [SampleItem] {
        items
    }

    func loadSavedLibrary() async throws -> [SampleItem] {
        savedLibrary
    }

    func updateSaved(sampleID: String, saved: Bool) async throws {
        if shouldFailUpdates {
            throw OfflineError()
        }
        updatedSavedStates.append((sampleID, saved))
    }

    func resolvePlayback(sampleID: String) async throws -> URL {
        _ = sampleID
        resolvePlaybackCalls += 1
        return playbackURL
    }

    func prepareDownload(sampleID: String) async throws -> URL {
        _ = sampleID
        prepareDownloadCalls += 1
        return downloadURL
    }
}

final class AppCoreTests: XCTestCase {
    private func makeLocalStateStore(testName: String = #function) -> LocalSampleStateStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DreamCratesTests")
            .appendingPathComponent(testName)
        try? FileManager.default.removeItem(at: url)
        return LocalSampleStateStore(baseDirectory: url)
    }

    private func makeDownloadManager(testName: String = #function) -> DownloadManager {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DreamCratesTests")
            .appendingPathComponent(testName)
        try? FileManager.default.removeItem(at: url)
        return DownloadManager(baseDirectory: url)
    }

    private func makePlaybackRoot(testName: String = #function) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DreamCratesTests")
            .appendingPathComponent(testName)
        try? FileManager.default.removeItem(at: url)
        return url
    }

    private func writeAudioFixture(to url: URL, durationSeconds: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeWaveData(durationSeconds: durationSeconds).write(to: url)
    }

    private func makeWaveData(durationSeconds: Int, sampleRate: Int = 8_000) -> Data {
        let frameCount = max(durationSeconds, 1) * sampleRate
        let bytesPerSample = 2
        let dataSize = frameCount * bytesPerSample
        var data = Data(capacity: 44 + dataSize)

        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * bytesPerSample))
        append(UInt16(bytesPerSample))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))

        for frame in 0 ..< frameCount {
            let amplitude: Int16 = frame % 32 < 16 ? 2_400 : -2_400
            append(amplitude)
        }

        return data
    }

    private func makeSample(id: String, savedAt: Date?, durationSeconds: Int? = 60) -> SampleItem {
        SampleItem(
            id: id,
            youtubeVideoId: "yt-\(id)",
            channelId: "channel",
            channelTitle: "Channel Title",
            channelHandle: "@channel",
            channelAvatarURL: nil,
            title: "Sample \(id)",
            descriptionText: "",
            publishedAt: .now,
            artworkURL: nil,
            durationSeconds: durationSeconds,
            genreTags: [],
            toneTags: [],
            isSaved: savedAt != nil,
            savedAt: savedAt,
            downloadState: .notDownloaded,
            streamState: .ready
        )
    }

    @MainActor
    func testSavingDoesNotChangeDownloadState() async {
        let base = makeSample(id: "base", savedAt: nil)

        let store = SampleLibraryStore(
            repository: FakeRepository(items: [base]),
            localStateStore: makeLocalStateStore()
        )
        await store.load()

        await store.toggleSaved(sampleID: base.id)

        let updated = try! XCTUnwrap(store.samples.first)
        XCTAssertTrue(updated.isSaved)
        XCTAssertNotNil(updated.savedAt)
        XCTAssertEqual(updated.downloadState, .notDownloaded)
    }

    @MainActor
    func testSavedSamplesSortedByRecentlySaved() async {
        let older = makeSample(id: "older", savedAt: Date(timeIntervalSinceNow: -3600))
        let newer = makeSample(id: "newer", savedAt: Date())

        let store = SampleLibraryStore(
            repository: FakeRepository(items: [older, newer]),
            localStateStore: makeLocalStateStore()
        )
        await store.load()

        XCTAssertEqual(store.savedSamples.first?.id, "newer")
        XCTAssertEqual(store.savedSamples.last?.id, "older")
    }

    @MainActor
    func testPendingSavedStatePersistsAcrossRelaunch() async {
        let base = makeSample(id: "base", savedAt: nil)
        let stateStore = makeLocalStateStore()

        let firstRepo = FakeRepository(items: [base])
        firstRepo.shouldFailUpdates = true
        let firstStore = SampleLibraryStore(repository: firstRepo, localStateStore: stateStore)
        await firstStore.load()
        await firstStore.toggleSaved(sampleID: base.id)

        let secondRepo = FakeRepository(items: [base])
        let secondStore = SampleLibraryStore(repository: secondRepo, localStateStore: stateStore)
        await secondStore.load()

        XCTAssertTrue(secondStore.samples.first?.isSaved == true)
    }

    @MainActor
    func testDownloadedFilesRestoreAcrossRelaunch() async throws {
        let sample = makeSample(id: "base", savedAt: nil, durationSeconds: 2)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DreamCratesTests")
            .appendingPathComponent(#function)
        try? FileManager.default.removeItem(at: root)
        let downloadsDir = root.appendingPathComponent("DreamCratesDownloads")
        let sampleDir = downloadsDir.appendingPathComponent("base", isDirectory: true)
        try writeAudioFixture(to: sampleDir.appendingPathComponent("base.wav"), durationSeconds: 2)

        let store = SampleLibraryStore(
            repository: FakeRepository(items: [sample]),
            downloadManager: DownloadManager(baseDirectory: root),
            localStateStore: LocalSampleStateStore(baseDirectory: root)
        )
        await store.load()

        XCTAssertEqual(store.samples.first?.downloadState, .downloaded)
        let resolved = try await store.resolvedPlaybackURL(for: "base")
        XCTAssertTrue(resolved.path.hasSuffix("base/base.wav"))
    }

    @MainActor
    func testPlaybackPreferencesPersistAcrossStoreInstances() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let first = PlaybackPreferencesStore(userDefaults: defaults)
        first.mode = .turntable
        first.speed = 1.75
        first.transposeSemitones = 5

        let second = PlaybackPreferencesStore(userDefaults: defaults)
        XCTAssertEqual(second.mode, .turntable)
        XCTAssertEqual(second.speed, 1.75)
        XCTAssertEqual(second.transposeSemitones, 5)
    }

    @MainActor
    func testNotificationPreferencesPersistLocally() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let client = APIClient(baseURL: URL(string: "http://127.0.0.1:8000")!, deviceID: "device")

        let first = NotificationPreferencesStore(apiClient: client, userDefaults: defaults)
        first.notificationsEnabled = false
        first.quietHoursEnabled = false

        let second = NotificationPreferencesStore(apiClient: client, userDefaults: defaults)
        XCTAssertFalse(second.notificationsEnabled)
        XCTAssertFalse(second.quietHoursEnabled)
    }

    @MainActor
    func testResolvedPlaybackURLUsesSessionCache() async throws {
        let sample = makeSample(id: "base", savedAt: nil)
        let repository = FakeRepository(items: [sample])
        let store = SampleLibraryStore(repository: repository, localStateStore: makeLocalStateStore())
        await store.load()

        _ = try await store.resolvedPlaybackURL(for: sample.id)
        _ = try await store.resolvedPlaybackURL(for: sample.id)

        XCTAssertEqual(repository.resolvePlaybackCalls, 1)
    }

    @MainActor
    func testWarpPlaybackUsesDownloadedFileFirst() async throws {
        let sample = makeSample(id: "base", savedAt: nil, durationSeconds: 2)
        let root = makePlaybackRoot()
        let downloadsDir = root.appendingPathComponent("DreamCratesDownloads")
        let sampleDir = downloadsDir.appendingPathComponent("base", isDirectory: true)
        try writeAudioFixture(to: sampleDir.appendingPathComponent("base.wav"), durationSeconds: 2)

        let downloadCounter = DownloadCounter()
        let cachedWaveData = makeWaveData(durationSeconds: 2)
        let playbackCache = PlaybackCache(baseDirectory: root) { _ in
            downloadCounter.count += 1
            let temporaryURL = root.appendingPathComponent("unused.wav")
            try cachedWaveData.write(to: temporaryURL)
            return (
                temporaryURL,
                URLResponse(url: temporaryURL, mimeType: "audio/wav", expectedContentLength: 0, textEncodingName: nil)
            )
        }

        let repository = FakeRepository(items: [sample])
        let store = SampleLibraryStore(
            repository: repository,
            downloadManager: DownloadManager(baseDirectory: root),
            playbackCache: playbackCache,
            localStateStore: LocalSampleStateStore(baseDirectory: root)
        )
        await store.load()

        let resolved = try await store.preparePlaybackURL(for: sample.id, mode: .warp)

        XCTAssertTrue(resolved.path.hasSuffix("DreamCratesDownloads/base/base.wav"))
        XCTAssertEqual(downloadCounter.count, 0)
        XCTAssertEqual(repository.prepareDownloadCalls, 0)
        XCTAssertEqual(store.samples.first?.downloadState, .downloaded)
    }

    @MainActor
    func testWarpPlaybackCacheReusesTransientFile() async throws {
        let sample = makeSample(id: "base", savedAt: nil, durationSeconds: 2)
        let root = makePlaybackRoot()
        let repository = FakeRepository(items: [sample])
        let downloadCounter = DownloadCounter()
        let cachedWaveData = makeWaveData(durationSeconds: 2)

        let playbackCache = PlaybackCache(baseDirectory: root) { _ in
            downloadCounter.count += 1
            let temporaryURL = root.appendingPathComponent("tmp-\(downloadCounter.count).wav")
            try cachedWaveData.write(to: temporaryURL)
            return (
                temporaryURL,
                URLResponse(url: temporaryURL, mimeType: "audio/wav", expectedContentLength: 0, textEncodingName: nil)
            )
        }

        let store = SampleLibraryStore(
            repository: repository,
            playbackCache: playbackCache,
            localStateStore: LocalSampleStateStore(baseDirectory: root)
        )
        await store.load()
        let first = try await store.preparePlaybackURL(for: sample.id, mode: .warp)
        let second = try await store.preparePlaybackURL(for: sample.id, mode: .warp)

        XCTAssertEqual(first, second)
        XCTAssertEqual(downloadCounter.count, 1)
        XCTAssertEqual(repository.prepareDownloadCalls, 1)
        XCTAssertLessThanOrEqual(repository.resolvePlaybackCalls, 1)
        XCTAssertEqual(store.samples.first?.downloadState, .notDownloaded)
    }

    @MainActor
    func testRemovingDownloadDeletesStoredFileAndResetsState() async throws {
        let sample = makeSample(id: "base", savedAt: nil, durationSeconds: 2)
        let root = makePlaybackRoot()
        let manager = DownloadManager(baseDirectory: root)
        let sampleDir = root
            .appendingPathComponent("DreamCratesDownloads")
            .appendingPathComponent("base", isDirectory: true)
        try writeAudioFixture(to: sampleDir.appendingPathComponent("base.wav"), durationSeconds: 2)

        let store = SampleLibraryStore(
            repository: FakeRepository(items: [sample]),
            downloadManager: manager,
            localStateStore: LocalSampleStateStore(baseDirectory: root)
        )
        await store.load()

        await store.removeDownload(sampleID: sample.id)

        XCTAssertEqual(store.samples.first?.downloadState, .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sampleDir.path()))
    }

    @MainActor
    func testApplyingSpeedWhilePlayingUpdatesActiveEngineImmediately() {
        let turntable = FakePlaybackEngine()
        let warp = FakePlaybackEngine()
        let controller = PlaybackController(turntableEngine: turntable, warpEngine: warp)
        let sourceURL = URL(string: "https://example.com/sample.mp3")!

        controller.play(
            title: "Sample",
            sourceURL: sourceURL,
            settings: PlaybackSettings(mode: .turntable, speed: 1.0)
        )
        controller.applyPreferences(PlaybackSettings(mode: .turntable, speed: 1.5, transposeSemitones: 7))

        XCTAssertEqual(turntable.loadCalls.count, 1)
        XCTAssertEqual(turntable.updateCalls.last?.speed, 1.5)
        XCTAssertEqual(turntable.updateCalls.last?.transposeSemitones, 0)
        XCTAssertEqual(warp.loadCalls.count, 0)
    }

    @MainActor
    func testPausedSpeedChangesApplyOnResume() {
        let turntable = FakePlaybackEngine()
        let warp = FakePlaybackEngine()
        let controller = PlaybackController(turntableEngine: turntable, warpEngine: warp)
        let sourceURL = URL(string: "https://example.com/sample.mp3")!

        controller.play(
            title: "Sample",
            sourceURL: sourceURL,
            settings: PlaybackSettings(mode: .turntable, speed: 1.0)
        )
        controller.pause()
        controller.applyPreferences(PlaybackSettings(mode: .turntable, speed: 1.75))
        controller.resume()

        XCTAssertEqual(turntable.pauseCallCount, 1)
        XCTAssertEqual(turntable.updateCalls.last?.speed, 1.75)
        XCTAssertEqual(turntable.playCallCount, 1)
    }

    @MainActor
    func testModeSwitchChoosesWarpEngineAndPreservesStartTime() {
        let turntable = FakePlaybackEngine()
        let warp = FakePlaybackEngine()
        let controller = PlaybackController(turntableEngine: turntable, warpEngine: warp)
        let streamURL = URL(string: "https://example.com/sample.mp3")!
        let localURL = URL(fileURLWithPath: "/tmp/sample.mp3")

        controller.play(
            title: "Sample",
            sourceURL: streamURL,
            settings: PlaybackSettings(mode: .turntable, speed: 1.0)
        )
        turntable.currentTime = 18.5
        controller.play(
            title: "Sample",
            sourceURL: localURL,
            settings: PlaybackSettings(mode: .warp, speed: 0.9, transposeSemitones: -3),
            startTime: 18.5
        )

        XCTAssertEqual(turntable.stopCallCount, 1)
        XCTAssertEqual(warp.loadCalls.count, 1)
        XCTAssertEqual(warp.loadCalls.last?.startTime, 18.5)
        XCTAssertEqual(warp.loadCalls.last?.settings.transposeSemitones, -3)
    }

    func testBackendFeedPayloadDecodesWithSnakeCaseFields() throws {
        let payload = """
        {
          "items": [
            {
              "id": "sample-abc",
              "youtube_video_id": "abc",
              "channel_id": "UCs_1dV9bN0wQhQ_a9W8wO4Q",
              "channel_title": "andrenavarroII",
              "channel_handle": "@andrenavarroII",
              "channel_avatar_url": "https://example.com/avatar.jpg",
              "title": "Dark sample pack",
              "description_text": "Fresh from the backend",
              "published_at": "2026-03-29T10:00:00Z",
              "artwork_url": "https://example.com/thumb.jpg",
              "duration_seconds": 95,
              "genre_tags": [
                { "key": "trap", "confidence": 0.9 }
              ],
              "tone_tags": [
                { "key": "gritty", "confidence": 0.8 }
              ],
              "is_saved": true,
              "saved_at": "2026-03-29T10:05:00Z",
              "download_state": "not_downloaded",
              "stream_state": "ready"
            }
          ],
          "nextCursor": 1
        }
        """.data(using: .utf8)!

        let response = try APIClient.makeDecoder().decode(FeedResponse.self, from: payload)

        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.youtubeVideoId, "abc")
        XCTAssertEqual(response.items.first?.channelId, "UCs_1dV9bN0wQhQ_a9W8wO4Q")
        XCTAssertEqual(response.items.first?.channelTitle, "andrenavarroII")
        XCTAssertEqual(response.items.first?.channelHandle, "@andrenavarroII")
        XCTAssertEqual(response.items.first?.channelAvatarURL?.absoluteString, "https://example.com/avatar.jpg")
        XCTAssertEqual(response.items.first?.artworkURL?.absoluteString, "https://example.com/thumb.jpg")
        XCTAssertEqual(response.items.first?.downloadState, .notDownloaded)
        XCTAssertEqual(response.items.first?.streamState, .ready)
        XCTAssertEqual(response.nextCursor, 1)
    }

    func testDevicePreferencesPayloadDecodesSnakeCaseDeviceID() throws {
        let payload = """
        {
          "device_id": "device-123",
          "notifications_enabled": true,
          "quiet_start_hour": 22,
          "quiet_end_hour": 8
        }
        """.data(using: .utf8)!

        let preferences = try APIClient.makeDecoder().decode(DevicePreferencesPayload.self, from: payload)

        XCTAssertEqual(preferences.deviceID, "device-123")
        XCTAssertTrue(preferences.notificationsEnabled)
        XCTAssertEqual(preferences.quietStartHour, 22)
        XCTAssertEqual(preferences.quietEndHour, 8)
    }
}
