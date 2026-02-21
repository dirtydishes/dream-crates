import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var items: [SampleItem] = []
    @Published var isLoading = false

    private let repository: SampleRepository

    init(repository: SampleRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await repository.loadInitialFeed()
        } catch {
            items = []
        }
    }

    func refresh() async {
        do {
            items = try await repository.refreshFeed()
        } catch {
            // Keep current snapshot on refresh errors.
        }
    }
}
