import XCTest
@testable import StudioSampleApp

@MainActor
private final class FakeRepository: SampleRepository {
    struct OfflineError: Error {}

    let items: [SampleItem]
    var savedLibrary: [SampleItem]
    var updatedSavedStates: [(String, Bool)] = []
    var playbackURL = URL(string: "https://example.com/playback.mp3")!
    var downloadURL = URL(string: "https://example.com/download.mp3")!
    var shouldFailUpdates = false

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
        return playbackURL
    }

    func prepareDownload(sampleID: String) async throws -> URL {
        _ = sampleID
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

    private func makeSample(id: String, savedAt: Date?) -> SampleItem {
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
            durationSeconds: 60,
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
        let sample = makeSample(id: "base", savedAt: nil)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DreamCratesTests")
            .appendingPathComponent(#function)
        try? FileManager.default.removeItem(at: root)
        let downloadsDir = root.appendingPathComponent("DreamCratesDownloads")
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        try Data("test".utf8).write(to: downloadsDir.appendingPathComponent("base.mp3"))

        let store = SampleLibraryStore(
            repository: FakeRepository(items: [sample]),
            downloadManager: DownloadManager(baseDirectory: root),
            localStateStore: LocalSampleStateStore(baseDirectory: root)
        )
        await store.load()

        XCTAssertEqual(store.samples.first?.downloadState, .downloaded)
        let resolved = try await store.resolvedPlaybackURL(for: "base")
        XCTAssertTrue(resolved.path.hasSuffix("base.mp3"))
    }

    @MainActor
    func testPlaybackSpeedPersistsAcrossStoreInstances() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let first = PlaybackPreferencesStore(userDefaults: defaults)
        first.speed = 1.75

        let second = PlaybackPreferencesStore(userDefaults: defaults)
        XCTAssertEqual(second.speed, 1.75)
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
