import Foundation

@MainActor
final class SampleLibraryStore: ObservableObject {
    @Published private(set) var samples: [SampleItem] = []
    @Published var currentSampleID: String?
    @Published var isLoading = false

    private let repository: SampleRepository
    private let downloadManager = DownloadManager()
    private var localFiles: [String: URL] = [:]

    init(repository: SampleRepository) {
        self.repository = repository
    }

    var currentSample: SampleItem? {
        guard let id = currentSampleID else { return samples.first }
        return samples.first(where: { $0.id == id })
    }

    var savedSamples: [SampleItem] {
        samples
            .filter(\.isSaved)
            .sorted { (lhs, rhs) in
                (lhs.savedAt ?? .distantPast) > (rhs.savedAt ?? .distantPast)
            }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            samples = try await repository.loadInitialFeed()
            if currentSampleID == nil {
                currentSampleID = samples.first?.id
            }
        } catch {
            samples = []
        }
    }

    func refresh() async {
        do {
            let fresh = try await repository.refreshFeed()
            samples = mergeSavedState(old: samples, new: fresh)
            if currentSampleID == nil {
                currentSampleID = samples.first?.id
            }
        } catch {
            // Keep current snapshot on refresh errors.
        }
    }

    func select(_ sampleID: String) {
        currentSampleID = sampleID
    }

    func toggleSaved(sampleID: String) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else {
            return
        }
        samples[idx].isSaved.toggle()
        samples[idx].savedAt = samples[idx].isSaved ? .now : nil
    }

    func download(sampleID: String) async {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }

        samples[idx].downloadState = .downloading
        let sourceURL = URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!

        do {
            let localURL = try await downloadManager.download(sampleID: sampleID, from: sourceURL)
            localFiles[sampleID] = localURL
            samples[idx].downloadState = .downloaded
        } catch {
            samples[idx].downloadState = .failed
        }
    }

    func playbackURL(for sampleID: String) -> URL {
        if let local = localFiles[sampleID] {
            return local
        }
        return URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!
    }

    private func mergeSavedState(old: [SampleItem], new: [SampleItem]) -> [SampleItem] {
        let savedLookup = Dictionary(uniqueKeysWithValues: old.map { ($0.id, ($0.isSaved, $0.savedAt)) })
        return new.map { item in
            guard let prior = savedLookup[item.id] else {
                return item
            }
            var updated = item
            updated.isSaved = prior.0
            updated.savedAt = prior.1
            return updated
        }
    }
}
