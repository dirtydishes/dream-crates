import SwiftUI

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
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
                                    .font(theme.font(.body, weight: .medium))
                                    .foregroundStyle(theme.label)
                                Text(item.savedAt ?? item.publishedAt, style: .date)
                                    .font(theme.font(.caption))
                                    .foregroundStyle(theme.secondaryLabel)
                                Text(downloadLabel(for: item.downloadState))
                                    .font(theme.font(.caption2))
                                    .foregroundStyle(theme.secondaryLabel)
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
                        .listRowBackground(theme.bg)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(theme.bg)
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
