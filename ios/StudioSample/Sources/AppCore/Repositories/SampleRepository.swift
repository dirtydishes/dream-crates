import Foundation

@MainActor
protocol SampleRepository {
    func loadInitialFeed() async throws -> [SampleItem]
    func refreshFeed() async throws -> [SampleItem]
}

@MainActor
final class HybridSampleRepository: SampleRepository {
    private let client: APIClient
    private let fallback: [SampleItem]
    private(set) var cachedItems: [SampleItem]

    init(client: APIClient, fallback: [SampleItem] = MockData.samples) {
        self.client = client
        self.fallback = fallback
        self.cachedItems = fallback
    }

    func loadInitialFeed() async throws -> [SampleItem] {
        do {
            let response = try await client.fetchFeed(limit: 30, cursor: 0)
            cachedItems = response.items
        } catch {
            cachedItems = fallback
        }
        return cachedItems
    }

    func refreshFeed() async throws -> [SampleItem] {
        do {
            let response = try await client.fetchFeed(limit: 30, cursor: 0)
            cachedItems = response.items
        } catch {
            // Keep the last known feed for resilient UX.
        }
        return cachedItems
    }
}
