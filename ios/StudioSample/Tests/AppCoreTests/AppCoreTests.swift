import XCTest
@testable import StudioSampleApp

@MainActor
private final class FakeRepository: SampleRepository {
    let items: [SampleItem]
    var savedLibrary: [SampleItem]
    var updatedSavedStates: [(String, Bool)] = []

    init(items: [SampleItem], savedLibrary: [SampleItem] = []) {
        self.items = items
        self.savedLibrary = savedLibrary
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
        updatedSavedStates.append((sampleID, saved))
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
            title: "Sample \(id)",
            descriptionText: "",
            publishedAt: .now,
            artworkURL: nil,
            durationSeconds: 60,
            genreTags: [],
            toneTags: [],
            isSaved: savedAt != nil,
            savedAt: savedAt,
            downloadState: .downloaded,
            streamState: .ready
        )
    }

    func testMockSamplesContainSavedItem() {
        XCTAssertTrue(MockData.samples.contains(where: { $0.isSaved }))
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
        XCTAssertEqual(updated.downloadState, .downloaded)
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
        XCTAssertTrue(store.playbackURL(for: "base").path.hasSuffix("base.mp3"))
    }
}
