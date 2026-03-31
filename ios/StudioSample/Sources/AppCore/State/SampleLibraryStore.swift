import Foundation

@MainActor
final class SampleLibraryStore: ObservableObject {
    private struct CachedPlaybackURL {
        let url: URL
        let cachedAt: Date
    }

    @Published private(set) var samples: [SampleItem] = []
    @Published var currentSampleID: String?
    @Published var isLoading = false

    private let repository: SampleRepository
    private let downloadManager: DownloadManager
    private let playbackCache: PlaybackCache
    private let localStateStore: LocalSampleStateStore
    private var localFiles: [String: URL] = [:]
    private var cachedPlaybackURLs: [String: CachedPlaybackURL] = [:]
    private var preloadingPlaybackIDs = Set<String>()
    private let playbackCacheLifetime: TimeInterval = 15 * 60

    init(
        repository: SampleRepository,
        downloadManager: DownloadManager = DownloadManager(),
        playbackCache: PlaybackCache = PlaybackCache(),
        localStateStore: LocalSampleStateStore = LocalSampleStateStore()
    ) {
        self.repository = repository
        self.downloadManager = downloadManager
        self.playbackCache = playbackCache
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
            preloadInitialPlaybackWindow()
        } catch {
            print("DreamCrates SampleLibraryStore load failed: \(error)")
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
            preloadInitialPlaybackWindow()
        } catch {
            print("DreamCrates SampleLibraryStore refresh failed: \(error)")
            // Keep current snapshot on refresh errors.
        }
    }

    func select(_ sampleID: String) {
        currentSampleID = sampleID
        preloadPlaybackWindow(around: sampleID)
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

        do {
            let sourceURL = try await repository.prepareDownload(sampleID: sampleID)
            let localURL = try await downloadManager.download(sampleID: sampleID, from: sourceURL)
            localFiles[sampleID] = localURL
            samples[idx].downloadState = .downloaded
        } catch {
            samples[idx].downloadState = .failed
        }
    }

    func resolvedPlaybackURL(for sampleID: String) async throws -> URL {
        if let local = localFiles[sampleID] {
            return local
        }

        if let cached = cachedPlaybackURLs[sampleID], Date().timeIntervalSince(cached.cachedAt) < playbackCacheLifetime {
            return cached.url
        }

        let resolved = try await repository.resolvePlayback(sampleID: sampleID)
        cachedPlaybackURLs[sampleID] = CachedPlaybackURL(url: resolved, cachedAt: .now)
        return resolved
    }

    func preparePlaybackURL(for sampleID: String, mode: PlaybackMode) async throws -> URL {
        switch mode {
        case .turntable:
            return try await resolvedPlaybackURL(for: sampleID)
        case .warp:
            if let local = localFiles[sampleID] {
                return local
            }
            if let cached = try await playbackCache.cachedURL(for: sampleID) {
                return cached
            }
            let downloadURL = try await repository.prepareDownload(sampleID: sampleID)
            return try await playbackCache.cache(sampleID: sampleID, from: downloadURL)
        }
    }

    func preloadPlayback(sampleID: String) async {
        guard localFiles[sampleID] == nil else { return }
        guard cachedPlaybackURLs[sampleID] == nil else { return }
        guard !preloadingPlaybackIDs.contains(sampleID) else { return }

        preloadingPlaybackIDs.insert(sampleID)
        defer { preloadingPlaybackIDs.remove(sampleID) }

        do {
            let resolved = try await repository.resolvePlayback(sampleID: sampleID)
            cachedPlaybackURLs[sampleID] = CachedPlaybackURL(url: resolved, cachedAt: .now)
        } catch {
            // Ignore preload failures and resolve on demand later.
        }
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

    private func preloadInitialPlaybackWindow() {
        for sampleID in samples.prefix(3).map(\.id) {
            Task { await preloadPlayback(sampleID: sampleID) }
        }
    }

    private func preloadPlaybackWindow(around sampleID: String) {
        guard let index = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        let lowerBound = max(samples.startIndex, index - 1)
        let upperBound = min(samples.index(before: samples.endIndex), index + 2)
        for idx in lowerBound ... upperBound {
            let preloadID = samples[idx].id
            Task { await preloadPlayback(sampleID: preloadID) }
        }
    }
}
