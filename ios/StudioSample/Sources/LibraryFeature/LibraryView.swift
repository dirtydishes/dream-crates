import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: SampleLibraryStore

    var body: some View {
        NavigationStack {
            Group {
                if store.savedSamples.isEmpty {
                    ContentUnavailableView("No Saved Samples", systemImage: "bookmark")
                } else {
                    List(store.savedSamples) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .foregroundStyle(AppTheme.label)
                                Text(item.savedAt ?? item.publishedAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(downloadLabel(for: item.downloadState))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                Task {
                                    await store.download(sampleID: item.id)
                                }
                            } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    await store.toggleSaved(sampleID: item.id)
                                }
                            } label: {
                                Image(systemName: "bookmark.slash")
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.select(item.id)
                        }
                        .listRowBackground(AppTheme.bg)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.bg)
            .navigationTitle("Library")
        }
    }

    private func downloadLabel(for state: DownloadState) -> String {
        switch state {
        case .notDownloaded: return "Not downloaded"
        case .queued: return "Queued"
        case .downloading: return "Downloading..."
        case .downloaded: return "Available offline"
        case .failed: return "Download failed"
        }
    }
}
