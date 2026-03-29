import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var appShell: AppShellStore
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playbackPreferences: PlaybackPreferencesStore
    @EnvironmentObject private var store: SampleLibraryStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.samples) { item in
                    Button {
                        Task {
                            await play(item)
                        }
                    } label: {
                        SampleFeedRow(
                            item: item,
                            isActive: playback.isPlaying && store.currentSampleID == item.id
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(AppTheme.bg)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            Task {
                                await store.download(sampleID: item.id)
                            }
                        } label: {
                            Label(downloadLabel(for: item.downloadState), systemImage: downloadIcon(for: item.downloadState))
                        }
                        .tint(.blue)

                        Button {
                            Task {
                                await store.toggleSaved(sampleID: item.id)
                            }
                        } label: {
                            Label(item.isSaved ? "Remove" : "Library", systemImage: item.isSaved ? "bookmark.slash" : "bookmark.fill")
                        }
                        .tint(item.isSaved ? .gray : Color(red: 0.20, green: 0.60, blue: 0.34))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("Fresh Samples")
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
        store.select(item.id)

        do {
            let sourceURL = try await store.resolvedPlaybackURL(for: item.id)
            playback.configureIfNeeded()
            playback.play(
                title: item.title,
                sourceURL: sourceURL,
                rate: Float(playbackPreferences.speed)
            )
            appShell.selectedTab = .player
        } catch {
            playback.pause()
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
