import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playbackPreferences: PlaybackPreferencesStore
    @EnvironmentObject private var store: SampleLibraryStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(store.samples) { item in
                        Button {
                            Task {
                                await play(item)
                            }
                        } label: {
                            SampleFeedRow(
                                item: item,
                                isActive: store.currentSampleID == item.id,
                                isPlaying: playback.isPlaying && store.currentSampleID == item.id
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task {
                                    await store.download(sampleID: item.id)
                                }
                            } label: {
                                Label(downloadLabel(for: item.downloadState), systemImage: downloadIcon(for: item.downloadState))
                            }

                            Button {
                                Task {
                                    await store.toggleSaved(sampleID: item.id)
                                }
                            } label: {
                                Label(item.isSaved ? "Remove from Library" : "Save to Library", systemImage: item.isSaved ? "bookmark.slash" : "bookmark.fill")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(AppTheme.bg)
            .navigationTitle("Fresh Samples")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let current = store.currentSample {
                        Menu {
                            Button {
                                Task {
                                    await store.download(sampleID: current.id)
                                }
                            } label: {
                                Label(downloadLabel(for: current.downloadState), systemImage: downloadIcon(for: current.downloadState))
                            }

                            Button {
                                Task {
                                    await store.toggleSaved(sampleID: current.id)
                                }
                            } label: {
                                Label(current.isSaved ? "Remove from Library" : "Save to Library", systemImage: current.isSaved ? "bookmark.slash" : "bookmark.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(AppTheme.label)
                        }
                    }
                }
            }
            .overlay {
                if store.isLoading {
                    ProgressView()
                } else if store.samples.isEmpty {
                    ContentUnavailableView(
                        "No Samples Yet",
                        systemImage: "waveform.badge.exclamationmark",
                        description: Text("Dream Crates is connected, but the backend has not ingested any channel uploads yet.")
                    )
                }
            }
            .task {
                await store.load()
            }
            .refreshable {
                await store.refresh()
            }
        }
    }

    private func play(_ item: SampleItem) async {
        let isCurrentSelection = store.currentSampleID == item.id
        store.select(item.id)

        if isCurrentSelection, playback.canResumeCurrentItem {
            playback.togglePlayback()
            return
        }

        do {
            let sourceURL = try await store.preparePlaybackURL(
                for: item.id,
                mode: playbackPreferences.mode
            )
            playback.configureIfNeeded()
            playback.play(
                title: item.title,
                sourceURL: sourceURL,
                settings: playbackPreferences.currentSettings
            )
        } catch {
            playback.stopAndReset()
        }
    }

    private func downloadLabel(for state: DownloadState) -> String {
        switch state {
        case .notDownloaded: return "Download"
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .downloaded: return "Redownload"
        case .failed: return "Retry"
        }
    }

    private func downloadIcon(for state: DownloadState) -> String {
        switch state {
        case .notDownloaded: return "arrow.down.circle"
        case .queued: return "clock.arrow.circlepath"
        case .downloading: return "arrow.down.circle"
        case .downloaded: return "arrow.trianglehead.clockwise"
        case .failed: return "exclamationmark.arrow.circlepath"
        }
    }
}
