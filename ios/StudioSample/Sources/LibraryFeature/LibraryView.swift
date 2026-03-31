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
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .foregroundStyle(AppTheme.label)
                                    .lineLimit(2)

                                Text(item.savedAt ?? item.publishedAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(downloadLabel(for: item.downloadState))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(downloadTint(for: item.downloadState))
                            }

                            Spacer()

                            Button {
                                Task {
                                    await store.toggleDownload(sampleID: item.id)
                                }
                            } label: {
                                downloadAccessory(for: item)
                            }
                            .buttonStyle(.plain)
                            .disabled(item.downloadState == .queued || item.downloadState == .downloading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.select(item.id)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await store.toggleSaved(sampleID: item.id)
                                }
                            } label: {
                                Label("Remove from Library", systemImage: "bookmark.slash")
                            }

                            Button {
                                Task {
                                    await store.toggleDownload(sampleID: item.id)
                                }
                            } label: {
                                Label(downloadActionLabel(for: item.downloadState), systemImage: downloadActionIcon(for: item.downloadState))
                            }
                            .tint(downloadActionTint(for: item.downloadState))
                            .disabled(item.downloadState == .queued || item.downloadState == .downloading)
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

    private func downloadAccessory(for item: SampleItem) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 34, height: 34)

            switch item.downloadState {
            case .queued, .downloading:
                DownloadAccessoryRing(progress: store.downloadProgress[item.id], tint: AppTheme.accent)
                    .frame(width: 22, height: 22)
            default:
                Image(systemName: downloadActionIcon(for: item.downloadState))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(downloadTint(for: item.downloadState))
            }
        }
    }

    private func downloadLabel(for state: DownloadState) -> String {
        switch state {
        case .notDownloaded: return "Download for offline use"
        case .queued: return "Queued for download"
        case .downloading: return "Downloading..."
        case .downloaded: return "Downloaded"
        case .failed: return "Download failed"
        }
    }

    private func downloadActionLabel(for state: DownloadState) -> String {
        switch state {
        case .downloaded:
            return "Remove Download"
        case .queued, .downloading:
            return "Downloading"
        case .notDownloaded:
            return "Download"
        case .failed:
            return "Retry Download"
        }
    }

    private func downloadActionIcon(for state: DownloadState) -> String {
        switch state {
        case .downloaded:
            return "arrow.down.circle.slash"
        case .queued:
            return "clock.arrow.circlepath"
        case .downloading:
            return "arrow.down.circle"
        case .notDownloaded:
            return "arrow.down.circle"
        case .failed:
            return "exclamationmark.arrow.circlepath"
        }
    }

    private func downloadTint(for state: DownloadState) -> Color {
        switch state {
        case .downloaded:
            return AppTheme.accent
        case .failed:
            return .red.opacity(0.9)
        case .queued, .downloading, .notDownloaded:
            return AppTheme.label.opacity(0.8)
        }
    }

    private func downloadActionTint(for state: DownloadState) -> Color {
        switch state {
        case .downloaded:
            return .gray
        case .failed:
            return .red
        case .queued, .downloading, .notDownloaded:
            return AppTheme.accent
        }
    }
}

private struct DownloadAccessoryRing: View {
    let progress: Double?
    let tint: Color

    @State private var rotation = Angle.zero

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if progress == nil || progressValue < 0.02 {
                Circle()
                    .trim(from: 0.1, to: 0.42)
                    .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(rotation)
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                            rotation = .degrees(360)
                        }
                    }
            }
        }
    }

    private var progressValue: Double {
        min(max(progress ?? 0, 0.04), 1)
    }
}
