import XCTest
@testable import StudioSampleApp

@MainActor
private final class FakeRepository: SampleRepository {
    let items: [SampleItem]

    init(items: [SampleItem]) {
        self.items = items
    }

    func loadInitialFeed() async throws -> [SampleItem] {
        items
    }

    func refreshFeed() async throws -> [SampleItem] {
        items
    }
}

final class AppCoreTests: XCTestCase {
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

        let store = SampleLibraryStore(repository: FakeRepository(items: [base]))
        await store.load()

        store.toggleSaved(sampleID: base.id)

        let updated = try! XCTUnwrap(store.samples.first)
        XCTAssertTrue(updated.isSaved)
        XCTAssertNotNil(updated.savedAt)
        XCTAssertEqual(updated.downloadState, .downloaded)
    }

    @MainActor
    func testSavedSamplesSortedByRecentlySaved() async {
        let older = makeSample(id: "older", savedAt: Date(timeIntervalSinceNow: -3600))
        let newer = makeSample(id: "newer", savedAt: Date())

        let store = SampleLibraryStore(repository: FakeRepository(items: [older, newer]))
        await store.load()

        XCTAssertEqual(store.savedSamples.first?.id, "newer")
        XCTAssertEqual(store.savedSamples.last?.id, "older")
    }
}
