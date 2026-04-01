import AVFoundation
import Foundation

@MainActor
final class SampleLibraryStore: ObservableObject {
    private struct CachedPlaybackURL {
        let url: URL
        let cachedAt: Date
    }

    private enum LocalAudioAssetError: Error, Equatable {
        case invalidFile
    }

    @Published private(set) var samples: [SampleItem] = []
    @Published var currentSampleID: String?
    @Published var isLoading = false
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadRuntime: [String: DownloadRuntimeSnapshot] = [:]
    @Published private(set) var downloadLogs: [String: [DownloadLogEntry]] = [:]

    private let repository: SampleRepository
    private let downloadManager: DownloadManager
    private let playbackCache: PlaybackCache
    private let downloadLiveActivityManager: DownloadLiveActivityManager
    private let localStateStore: LocalSampleStateStore
    private var localFiles: [String: URL] = [:]
    private var cachedPlaybackURLs: [String: CachedPlaybackURL] = [:]
    private var preloadingPlaybackIDs = Set<String>()
    private let playbackCacheLifetime: TimeInterval = 15 * 60
    private let maxDownloadLogEntriesPerSample = 80
    private var lastLoggedProgressDecile: [String: Int] = [:]
    private var liveActivityDiagnosticCache: [String: Set<String>] = [:]

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

    var activeDownloads: [DownloadRuntimeSnapshot] {
        downloadRuntime.values
            .filter { $0.state == .queued || $0.state == .downloading }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    var recentDownloadLogEntries: [DownloadLogEntry] {
        downloadLogs.values
            .flatMap { $0 }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func downloadTitle(for sampleID: String) -> String {
        downloadRuntime[sampleID]?.title
            ?? sample(for: sampleID)?.title
            ?? "Unknown Sample"
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
        beginDownloadRuntime(for: currentSample, state: .queued, statusText: "Queued", progress: 0)
        appendDownloadLog("Queued for offline download.", level: .info, sampleID: sampleID)
        if let sample = sample(for: sampleID) {
            let outcome = await downloadLiveActivityManager.update(sample: sample, statusText: "Queued", progress: 0)
            handleLiveActivityOutcome(outcome, sampleID: sampleID, stage: "queue", includeSuccess: true)
        }

        do {
            let sourceURL = try await repository.prepareDownload(sampleID: sampleID)
            appendDownloadLog(
                "Prepared download URL via \(redactedURLString(sourceURL)).",
                level: .info,
                sampleID: sampleID
            )
            setDownloadState(.downloading, for: sampleID)
            updateDownloadRuntime(for: sampleID, state: .downloading, statusText: "Downloading", progress: 0)
            if let sample = sample(for: sampleID) {
                let outcome = await downloadLiveActivityManager.update(sample: sample, statusText: "Downloading", progress: 0)
                handleLiveActivityOutcome(outcome, sampleID: sampleID, stage: "start", includeSuccess: true)
            }
            let localURL = try await downloadManager.download(
                sampleID: sampleID,
                from: sourceURL,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    await self.handleDownloadProgress(sampleID: sampleID, progress: progress)
                },
                onEvent: { [weak self] event in
                    guard let self else { return }
                    await self.handleDownloadTransportEvent(event, sampleID: sampleID)
                }
            )
            appendDownloadLog("Validating downloaded audio asset.", level: .info, sampleID: sampleID)
            guard await isUsableLocalAudioAsset(at: localURL, sampleID: sampleID) else {
                try await downloadManager.removeDownload(sampleID: sampleID)
                throw LocalAudioAssetError.invalidFile
            }
            localFiles[sampleID] = localURL
            downloadProgress.removeValue(forKey: sampleID)
            setDownloadState(.downloaded, for: sampleID)
            updateDownloadRuntime(for: sampleID, state: .downloaded, statusText: "Download complete", progress: 1)
            appendDownloadLog("Download finished and passed local validation.", level: .info, sampleID: sampleID)
            let outcome = await downloadLiveActivityManager.end(
                sampleID: sampleID,
                finalStatusText: "Download complete",
                progress: 1
            )
            handleLiveActivityOutcome(outcome, sampleID: sampleID, stage: "complete")
        } catch {
            localFiles.removeValue(forKey: sampleID)
            downloadProgress.removeValue(forKey: sampleID)
            setDownloadState(.failed, for: sampleID)
            updateDownloadRuntime(for: sampleID, state: .failed, statusText: "Download failed", progress: nil)
            appendDownloadLog(describeDownloadError(error), level: .error, sampleID: sampleID)
            let outcome = await downloadLiveActivityManager.end(
                sampleID: sampleID,
                finalStatusText: "Download failed",
                progress: downloadRuntime[sampleID]?.progress
            )
            handleLiveActivityOutcome(outcome, sampleID: sampleID, stage: "failure")
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
        appendDownloadLog("Removed the local download.", level: .info, sampleID: sampleID)
        updateDownloadRuntime(for: sampleID, state: .notDownloaded, statusText: "Download removed", progress: nil)
        let outcome = await downloadLiveActivityManager.end(
            sampleID: sampleID,
            finalStatusText: "Download removed",
            progress: nil,
            dismissalPolicy: .immediate
        )
        handleLiveActivityOutcome(outcome, sampleID: sampleID, stage: "remove")

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
        updateDownloadRuntime(
            for: sampleID,
            state: .downloading,
            statusText: progress >= 0.995 ? "Finishing" : "Downloading",
            progress: progress
        )
        logProgressIfNeeded(sampleID: sampleID, progress: progress)
        guard let sample = sample(for: sampleID) else { return }
        let outcome = await downloadLiveActivityManager.update(
            sample: sample,
            statusText: progress >= 0.995 ? "Finishing" : "Downloading",
            progress: progress
        )
        handleLiveActivityOutcome(outcome, sampleID: sampleID, stage: "progress")
    }

    private func invalidateDownloadedAsset(for sampleID: String) async {
        try? await downloadManager.removeDownload(sampleID: sampleID)
        localFiles.removeValue(forKey: sampleID)
        downloadProgress.removeValue(forKey: sampleID)
        appendDownloadLog("Discarded an invalid local audio file.", level: .warning, sampleID: sampleID)
        updateDownloadRuntime(for: sampleID, state: .notDownloaded, statusText: "Removed invalid file", progress: nil)
        setDownloadState(.notDownloaded, for: sampleID)
    }

    private func beginDownloadRuntime(
        for sample: SampleItem,
        state: DownloadState,
        statusText: String,
        progress: Double?
    ) {
        lastLoggedProgressDecile.removeValue(forKey: sample.id)
        liveActivityDiagnosticCache.removeValue(forKey: sample.id)
        let now = Date()
        let startedAt = downloadRuntime[sample.id]?.startedAt ?? now
        downloadRuntime[sample.id] = DownloadRuntimeSnapshot(
            id: sample.id,
            title: sample.title,
            uploaderName: sample.uploaderName,
            uploaderAvatarURL: sample.channelAvatarURL,
            statusText: statusText,
            progress: progress,
            state: state,
            startedAt: startedAt,
            updatedAt: now
        )
    }

    private func updateDownloadRuntime(
        for sampleID: String,
        state: DownloadState,
        statusText: String,
        progress: Double?
    ) {
        guard let sample = sample(for: sampleID) ?? sampleSnapshot(for: sampleID) else { return }
        let now = Date()
        let startedAt = downloadRuntime[sampleID]?.startedAt ?? now
        downloadRuntime[sampleID] = DownloadRuntimeSnapshot(
            id: sampleID,
            title: sample.title,
            uploaderName: sample.uploaderName,
            uploaderAvatarURL: sample.channelAvatarURL,
            statusText: statusText,
            progress: progress,
            state: state,
            startedAt: startedAt,
            updatedAt: now
        )

        if state == .notDownloaded {
            lastLoggedProgressDecile.removeValue(forKey: sampleID)
            liveActivityDiagnosticCache.removeValue(forKey: sampleID)
        }
    }

    private func sampleSnapshot(for sampleID: String) -> SampleItem? {
        guard let runtime = downloadRuntime[sampleID] else { return nil }
        return SampleItem(
            id: sampleID,
            youtubeVideoId: sampleID,
            channelId: sampleID,
            channelTitle: runtime.uploaderName,
            channelHandle: nil,
            channelAvatarURL: runtime.uploaderAvatarURL,
            title: runtime.title,
            descriptionText: "",
            publishedAt: .now,
            artworkURL: nil,
            durationSeconds: nil,
            genreTags: [],
            toneTags: [],
            isSaved: false,
            savedAt: nil,
            downloadState: runtime.state,
            streamState: .idle
        )
    }

    private func appendDownloadLog(_ message: String, level: DownloadLogLevel, sampleID: String) {
        var entries = downloadLogs[sampleID] ?? []
        entries.append(DownloadLogEntry(sampleID: sampleID, level: level, message: message))
        if entries.count > maxDownloadLogEntriesPerSample {
            entries.removeFirst(entries.count - maxDownloadLogEntriesPerSample)
        }
        downloadLogs[sampleID] = entries
    }

    private func logProgressIfNeeded(sampleID: String, progress: Double) {
        guard progress.isFinite else { return }
        let normalized = min(max(progress, 0), 1)
        let decile = min(10, Int((normalized * 100).rounded(.down)) / 10)
        guard lastLoggedProgressDecile[sampleID] != decile else { return }
        lastLoggedProgressDecile[sampleID] = decile

        if decile == 10 {
            appendDownloadLog("Transfer reached 100%. Finalizing file.", level: .info, sampleID: sampleID)
        } else if decile > 0 {
            appendDownloadLog("Transfer reached \(decile * 10)% progress.", level: .info, sampleID: sampleID)
        }
    }

    private func handleDownloadTransportEvent(_ event: DownloadTransportEvent, sampleID: String) async {
        appendDownloadLog(event.message, level: event.level, sampleID: sampleID)
    }

    private func handleLiveActivityOutcome(
        _ outcome: DownloadLiveActivityManager.UpdateOutcome,
        sampleID: String,
        stage: String,
        includeSuccess: Bool = false
    ) {
        switch outcome {
        case .created where includeSuccess:
            appendLiveActivityLogIfNeeded(
                "live-activity-\(stage)-created",
                message: "Started a Live Activity for this download.",
                level: .info,
                sampleID: sampleID
            )
        case .updated where includeSuccess:
            appendLiveActivityLogIfNeeded(
                "live-activity-\(stage)-updated",
                message: "Updated the Live Activity.",
                level: .info,
                sampleID: sampleID
            )
        case .ended where includeSuccess:
            appendLiveActivityLogIfNeeded(
                "live-activity-\(stage)-ended",
                message: "Ended the Live Activity.",
                level: .info,
                sampleID: sampleID
            )
        case .disabled:
            appendLiveActivityLogIfNeeded(
                "live-activity-disabled",
                message: "Live Activities are disabled or unavailable on this device.",
                level: .warning,
                sampleID: sampleID
            )
        case let .failed(reason):
            appendLiveActivityLogIfNeeded(
                "live-activity-failed-\(stage)",
                message: "Live Activity update failed: \(reason)",
                level: .warning,
                sampleID: sampleID
            )
        case .ended, .updated, .created, .notFound:
            break
        }
    }

    private func appendLiveActivityLogIfNeeded(
        _ key: String,
        message: String,
        level: DownloadLogLevel,
        sampleID: String
    ) {
        var keys = liveActivityDiagnosticCache[sampleID] ?? []
        guard keys.insert(key).inserted else { return }
        liveActivityDiagnosticCache[sampleID] = keys
        appendDownloadLog(message, level: level, sampleID: sampleID)
    }

    private func describeDownloadError(_ error: Error) -> String {
        if let error = error as? LocalAudioAssetError, error == .invalidFile {
            return "The downloaded file could not be validated as playable local audio."
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    private func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        return components.string ?? url.absoluteString
    }

    private func isUsableLocalAudioAsset(at url: URL, sampleID: String) async -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resourceValues?.isRegularFile == true,
              let fileSize = resourceValues?.fileSize,
              fileSize > 1_024
        else {
            appendDownloadLog("Downloaded file was missing or too small to validate.", level: .warning, sampleID: sampleID)
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
                appendDownloadLog("Downloaded file did not expose a usable duration.", level: .warning, sampleID: sampleID)
                return false
            }

            if let expectedDuration = expectedDuration(for: sampleID), expectedDuration > 0 {
                let tolerance = max(3, expectedDuration * 0.25)
                guard abs(duration - expectedDuration) <= tolerance else {
                    appendDownloadLog(
                        "Downloaded file duration \(Int(duration.rounded()))s did not match the expected \(Int(expectedDuration.rounded()))s.",
                        level: .warning,
                        sampleID: sampleID
                    )
                    return false
                }
            }

            return true
        } catch {
            appendDownloadLog("AVFoundation could not open the downloaded audio: \(error.localizedDescription)", level: .warning, sampleID: sampleID)
            return false
        }
    }

    private func expectedDuration(for sampleID: String) -> Double? {
        samples.first(where: { $0.id == sampleID })?.durationSeconds.map(Double.init)
    }
}
