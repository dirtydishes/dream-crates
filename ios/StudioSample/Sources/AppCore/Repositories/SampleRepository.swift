import Foundation

@MainActor
protocol SampleRepository {
    func loadInitialFeed() async throws -> [SampleItem]
    func refreshFeed() async throws -> [SampleItem]
    func loadSavedLibrary() async throws -> [SampleItem]
    func updateSaved(sampleID: String, saved: Bool) async throws
}

@MainActor
final class HybridSampleRepository: SampleRepository {
    private let client: APIClient
    private(set) var cachedItems: [SampleItem]
    private var hasAttemptedBootstrapPoll = false

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

    private func loadRemoteFeed() async throws -> [SampleItem] {
        let response = try await client.fetchFeed(limit: 30, cursor: 0)
        if response.items.isEmpty, !hasAttemptedBootstrapPoll {
            hasAttemptedBootstrapPoll = true
            _ = try? await client.runPollerOnce()
            let refreshed = try await client.fetchFeed(limit: 30, cursor: 0)
            return refreshed.items
        }
        return response.items
    }
}
