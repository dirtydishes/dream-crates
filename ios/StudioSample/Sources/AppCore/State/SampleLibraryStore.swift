import AVFoundation
import Foundation

@MainActor
final class SampleLibraryStore: ObservableObject {
    private struct CachedPlaybackURL {
        let url: URL
        let cachedAt: Date
    }

    private enum LocalAudioAssetError: Error {
        case invalidFile
    }

    @Published private(set) var samples: [SampleItem] = []
    @Published var currentSampleID: String?
    @Published var isLoading = false
    @Published private(set) var downloadProgress: [String: Double] = [:]

    private let repository: SampleRepository
    private let downloadManager: DownloadManager
    private let playbackCache: PlaybackCache
    private let downloadLiveActivityManager: DownloadLiveActivityManager
    private let localStateStore: LocalSampleStateStore
    private var localFiles: [String: URL] = [:]
    private var cachedPlaybackURLs: [String: CachedPlaybackURL] = [:]
    private var preloadingPlaybackIDs = Set<String>()
    private let playbackCacheLifetime: TimeInterval = 15 * 60

    init(
        repository: SampleRepository,
        downloadManager: DownloadManager = DownloadManager(),
        playbackCache: PlaybackCache = PlaybackCache(),
        downloadLiveActivityManager: DownloadLiveActivityManager? = nil,
        localStateStore: LocalSampleStateStore = LocalSampleStateStore()
    ) {
        self.repository = repository
        self.downloadManager = downloadManager
        self.playbackCache = playbackCache
        self.downloadLiveActivityManager = downloadLiveActivityManager ?? .shared
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
        guard let currentSample = sample(for: sampleID) else { return }
        guard currentSample.downloadState != .queued, currentSample.downloadState != .downloading else { return }

        setDownloadState(.queued, for: sampleID)
        downloadProgress[sampleID] = 0
        if let sample = sample(for: sampleID) {
            await downloadLiveActivityManager.update(sample: sample, statusText: "Queued", progress: 0)
        }

        do {
            let sourceURL = try await repository.prepareDownload(sampleID: sampleID)
            setDownloadState(.downloading, for: sampleID)
            if let sample = sample(for: sampleID) {
                await downloadLiveActivityManager.update(sample: sample, statusText: "Downloading", progress: 0)
            }
            let localURL = try await downloadManager.download(sampleID: sampleID, from: sourceURL) { [weak self] progress in
                guard let self else { return }
                await self.handleDownloadProgress(sampleID: sampleID, progress: progress)
            }
            guard await isUsableLocalAudioAsset(at: localURL, sampleID: sampleID) else {
                try await downloadManager.removeDownload(sampleID: sampleID)
                throw LocalAudioAssetError.invalidFile
            }
            localFiles[sampleID] = localURL
            downloadProgress.removeValue(forKey: sampleID)
            setDownloadState(.downloaded, for: sampleID)
            await downloadLiveActivityManager.end(sampleID: sampleID, finalStatusText: "Download complete", progress: 1)
        } catch {
            localFiles.removeValue(forKey: sampleID)
            downloadProgress.removeValue(forKey: sampleID)
            setDownloadState(.failed, for: sampleID)
            await downloadLiveActivityManager.end(sampleID: sampleID, finalStatusText: "Download failed", progress: nil)
        }
    }

    func toggleDownload(sampleID: String) async {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }

        switch samples[idx].downloadState {
        case .downloaded:
            await removeDownload(sampleID: sampleID)
        case .queued, .downloading:
            return
        case .notDownloaded, .failed:
            await download(sampleID: sampleID)
        }
    }

    func removeDownload(sampleID: String) async {
        try? await downloadManager.removeDownload(sampleID: sampleID)
        try? await playbackCache.removeCachedURL(for: sampleID)
        localFiles.removeValue(forKey: sampleID)
        downloadProgress.removeValue(forKey: sampleID)
        await downloadLiveActivityManager.end(
            sampleID: sampleID,
            finalStatusText: "Download removed",
            progress: nil,
            dismissalPolicy: .immediate
        )

        setDownloadState(.notDownloaded, for: sampleID)
    }

    func resolvedPlaybackURL(for sampleID: String) async throws -> URL {
        if let local = await validatedDownloadedURL(for: sampleID) {
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
            if let local = await validatedDownloadedURL(for: sampleID) {
                return local
            }
            if let cached = try await playbackCache.cachedURL(for: sampleID) {
                if await isUsableLocalAudioAsset(at: cached, sampleID: sampleID) {
                    return cached
                }
                try? await playbackCache.removeCachedURL(for: sampleID)
            }
            let downloadURL = try await repository.prepareDownload(sampleID: sampleID)
            let cachedURL = try await playbackCache.cache(sampleID: sampleID, from: downloadURL)
            guard await isUsableLocalAudioAsset(at: cachedURL, sampleID: sampleID) else {
                try? await playbackCache.removeCachedURL(for: sampleID)
                throw LocalAudioAssetError.invalidFile
            }
            return cachedURL
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
        var validated: [String: URL] = [:]

        for (sampleID, url) in restored {
            if await isUsableLocalAudioAsset(at: url, sampleID: sampleID) {
                validated[sampleID] = url
            } else {
                try? await downloadManager.removeDownload(sampleID: sampleID)
            }
        }

        localFiles = validated
        downloadProgress = [:]
        samples = samples.map { item in
            var updated = item
            if validated[item.id] != nil {
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

    private func validatedDownloadedURL(for sampleID: String) async -> URL? {
        guard let local = localFiles[sampleID] else { return nil }
        guard await isUsableLocalAudioAsset(at: local, sampleID: sampleID) else {
            await invalidateDownloadedAsset(for: sampleID)
            return nil
        }
        return local
    }

    private func sample(for sampleID: String) -> SampleItem? {
        samples.first(where: { $0.id == sampleID })
    }

    private func setDownloadState(_ state: DownloadState, for sampleID: String) {
        guard let idx = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        samples[idx].downloadState = state
    }

    private func handleDownloadProgress(sampleID: String, progress: Double) async {
        downloadProgress[sampleID] = progress
        guard let sample = sample(for: sampleID) else { return }
        await downloadLiveActivityManager.update(
            sample: sample,
            statusText: progress >= 0.995 ? "Finishing" : "Downloading",
            progress: progress
        )
    }

    private func invalidateDownloadedAsset(for sampleID: String) async {
        try? await downloadManager.removeDownload(sampleID: sampleID)
        localFiles.removeValue(forKey: sampleID)
        downloadProgress.removeValue(forKey: sampleID)
        setDownloadState(.notDownloaded, for: sampleID)
    }

    private func isUsableLocalAudioAsset(at url: URL, sampleID: String) async -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resourceValues?.isRegularFile == true,
              let fileSize = resourceValues?.fileSize,
              fileSize > 1_024
        else {
            return false
        }

        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        do {
            let loadedDuration = try await asset.load(.duration)
            let duration = loadedDuration.seconds
            guard duration.isFinite, duration > 0 else {
                return false
            }

            if let expectedDuration = expectedDuration(for: sampleID), expectedDuration > 0 {
                let tolerance = max(3, expectedDuration * 0.25)
                guard abs(duration - expectedDuration) <= tolerance else {
                    return false
                }
            }

            return true
        } catch {
            return false
        }
    }

    private func expectedDuration(for sampleID: String) -> Double? {
        samples.first(where: { $0.id == sampleID })?.durationSeconds.map(Double.init)
    }
}
