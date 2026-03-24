import Foundation

@MainActor
final class SampleLibraryStore: ObservableObject {
    @Published private(set) var samples: [SampleItem] = []
    @Published var currentSampleID: String?
    @Published var isLoading = false

    private let repository: SampleRepository
    private let downloadManager: DownloadManager
    private let localStateStore: LocalSampleStateStore
    private var localFiles: [String: URL] = [:]

    init(
        repository: SampleRepository,
        downloadManager: DownloadManager = DownloadManager(),
        localStateStore: LocalSampleStateStore = LocalSampleStateStore()
    ) {
        self.repository = repository
        self.downloadManager = downloadManager
        self.localStateStore = localStateStore
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
            let fetched = try await repository.loadInitialFeed()
            samples = mergeSavedState(old: samples, new: fetched)
            applyPersistedLocalState()
            await restoreDownloadedState()
            await reconcileSavedStateWithBackend()
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
            applyPersistedLocalState()
            await restoreDownloadedState()
            await reconcileSavedStateWithBackend()
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

    func toggleSaved(sampleID: String) async {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else {
            return
        }

        samples[idx].isSaved.toggle()
        samples[idx].savedAt = samples[idx].isSaved ? .now : nil
        persistCurrentSavedState(for: samples[idx], syncStatus: .pending)

        do {
            try await repository.updateSaved(sampleID: sampleID, saved: samples[idx].isSaved)
            persistCurrentSavedState(for: samples[idx], syncStatus: .synced)
        } catch {
            // Keep the local pending state so the app survives offline changes.
        }
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

    private func applyPersistedLocalState() {
        let localStates = localStateStore.allStates()
        samples = samples.map { item in
            guard let persisted = localStates[item.id] else {
                return item
            }

            var updated = item
            updated.isSaved = persisted.isSaved
            updated.savedAt = persisted.savedAt
            return updated
        }
    }

    private func restoreDownloadedState() async {
        let restored = (try? await downloadManager.existingDownloads()) ?? [:]
        localFiles = restored
        samples = samples.map { item in
            var updated = item
            if restored[item.id] != nil {
                updated.downloadState = .downloaded
            } else if updated.downloadState == .downloaded {
                updated.downloadState = .notDownloaded
            }
            return updated
        }
    }

    private func reconcileSavedStateWithBackend() async {
        do {
            let remoteSavedItems = try await repository.loadSavedLibrary()
            let remoteLookup = Dictionary(uniqueKeysWithValues: remoteSavedItems.map { ($0.id, $0.savedAt) })
            let localStates = localStateStore.allStates()

            samples = samples.map { item in
                let pending = localStates[item.id]?.syncStatus == .pending
                guard !pending else { return item }

                var updated = item
                updated.isSaved = remoteLookup[item.id] != nil
                updated.savedAt = remoteLookup[item.id] ?? nil
                persistCurrentSavedState(for: updated, syncStatus: .synced)
                return updated
            }

            for (sampleID, state) in localStates where state.syncStatus == .pending {
                try await repository.updateSaved(sampleID: sampleID, saved: state.isSaved)
                if let idx = samples.firstIndex(where: { $0.id == sampleID }) {
                    persistCurrentSavedState(for: samples[idx], syncStatus: .synced)
                } else if state.isSaved {
                    localStateStore.setState(
                        PersistedSampleState(isSaved: true, savedAt: state.savedAt, syncStatus: .synced),
                        for: sampleID
                    )
                } else {
                    localStateStore.removeState(for: sampleID)
                }
            }
        } catch {
            // Keep local state if the backend is unavailable.
        }
    }

    private func persistCurrentSavedState(for sample: SampleItem, syncStatus: PersistedSampleState.SyncStatus) {
        if sample.isSaved || syncStatus == .pending {
            localStateStore.setState(
                PersistedSampleState(
                    isSaved: sample.isSaved,
                    savedAt: sample.savedAt,
                    syncStatus: syncStatus
                ),
                for: sample.id
            )
        } else {
            localStateStore.removeState(for: sample.id)
        }
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
