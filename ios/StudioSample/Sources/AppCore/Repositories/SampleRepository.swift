import Foundation

@MainActor
protocol SampleRepository {
    func loadInitialFeed() async throws -> [SampleItem]
    func refreshFeed() async throws -> [SampleItem]
    func loadSavedLibrary() async throws -> [SampleItem]
    func updateSaved(sampleID: String, saved: Bool) async throws
    func resolvePlayback(sampleID: String) async throws -> URL
    func prepareDownload(sampleID: String) async throws -> URL
}

@MainActor
final class HybridSampleRepository: SampleRepository {
    private let client: APIClient
    private(set) var cachedItems: [SampleItem]
    private var hasAttemptedBootstrapPoll = false
    private let pageSize = 100
    private let maxPageCount = 10

    init(client: APIClient, cachedItems: [SampleItem] = []) {
        self.client = client
        self.cachedItems = cachedItems
    }

    func loadInitialFeed() async throws -> [SampleItem] {
        cachedItems = try await loadRemoteFeed()
        return cachedItems
    }

    func refreshFeed() async throws -> [SampleItem] {
        do {
            cachedItems = try await loadRemoteFeed()
        } catch {
            // Keep the last known feed for resilient UX.
        }
        return cachedItems
    }

    func loadSavedLibrary() async throws -> [SampleItem] {
        try await client.fetchLibrary()
    }

    func updateSaved(sampleID: String, saved: Bool) async throws {
        try await client.updateLibrary(sampleID: sampleID, saved: saved)
    }

    func resolvePlayback(sampleID: String) async throws -> URL {
        try await client.resolvePlayback(sampleID: sampleID).playbackURL
    }

    func prepareDownload(sampleID: String) async throws -> URL {
        try await client.prepareDownload(sampleID: sampleID).downloadURL
    }

    private func loadRemoteFeed() async throws -> [SampleItem] {
        let response = try await fetchAllFeedPages()
        if response.isEmpty, !hasAttemptedBootstrapPoll {
            hasAttemptedBootstrapPoll = true
            _ = try? await client.runPollerOnce()
            return try await fetchAllFeedPages()
        }
        return response
    }

    private func fetchAllFeedPages() async throws -> [SampleItem] {
        var cursor = 0
        var pageCount = 0
        var items: [SampleItem] = []
        var seenIDs = Set<String>()

        while pageCount < maxPageCount {
            let response = try await client.fetchFeed(limit: pageSize, cursor: cursor)
            for item in response.items where seenIDs.insert(item.id).inserted {
                items.append(item)
            }

            guard let nextCursor = response.nextCursor, !response.items.isEmpty else {
                break
            }

            cursor = nextCursor
            pageCount += 1
        }

        return items
    }
}
