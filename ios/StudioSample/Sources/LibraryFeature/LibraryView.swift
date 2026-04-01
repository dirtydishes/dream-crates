import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: SampleLibraryStore
    @State private var isShowingDownloadMonitor = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.hasActiveDownloads {
                        Button {
                            isShowingDownloadMonitor = true
                        } label: {
                            DownloadMonitorToolbarIcon(count: store.activeDownloads.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $isShowingDownloadMonitor) {
                DownloadMonitorSheet()
                    .environmentObject(store)
            }
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

private struct DownloadMonitorToolbarIcon: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 38, height: 38)

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.bg)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(AppTheme.label, in: Capsule())
                .offset(x: 4, y: -4)
        }
        .frame(width: 44, height: 44)
    }
}

private struct DownloadMonitorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SampleLibraryStore

    var body: some View {
        NavigationStack {
            List {
                if !store.activeDownloads.isEmpty {
                    Section("Active Downloads") {
                        ForEach(store.activeDownloads) { download in
                            DownloadMonitorRow(download: download)
                                .listRowBackground(AppTheme.bg)
                        }
                    }
                }

                Section(store.recentDownloadLogEntries.isEmpty ? "Download Logs" : "Recent Logs") {
                    if store.recentDownloadLogEntries.isEmpty {
                        Text("Logs will appear here while downloads are running.")
                            .foregroundStyle(.secondary)
                            .listRowBackground(AppTheme.bg)
                    } else {
                        ForEach(Array(store.recentDownloadLogEntries.prefix(80))) { entry in
                            DownloadLogRow(
                                entry: entry,
                                sampleTitle: store.downloadTitle(for: entry.sampleID)
                            )
                            .listRowBackground(AppTheme.bg)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("Download Monitor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct DownloadMonitorRow: View {
    let download: DownloadRuntimeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DownloadMonitorAvatar(url: download.uploaderAvatarURL)

                VStack(alignment: .leading, spacing: 3) {
                    Text(download.title)
                        .foregroundStyle(AppTheme.label)
                        .lineLimit(2)

                    Text(download.uploaderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(progressLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.label)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(download.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)

                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)
                    .tint(AppTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private var progressValue: Double {
        min(max(download.progress ?? 0, 0), 1)
    }

    private var progressLabel: String {
        if let progress = download.progress {
            return progress.formatted(.percent.precision(.fractionLength(0)))
        }
        return download.state == .queued ? "Queued" : "Waiting"
    }
}

private struct DownloadMonitorAvatar: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.accent.opacity(0.8), AppTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "person.crop.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.7))
        }
    }
}

private struct DownloadLogRow: View {
    let entry: DownloadLogEntry
    let sampleTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(sampleTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.label)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(entry.timestamp, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text(levelLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(levelTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(levelTint.opacity(0.14), in: Capsule())

                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.label.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }

    private var levelLabel: String {
        switch entry.level {
        case .info:
            return "INFO"
        case .warning:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }

    private var levelTint: Color {
        switch entry.level {
        case .info:
            return AppTheme.accent
        case .warning:
            return Color(red: 0.93, green: 0.76, blue: 0.36)
        case .error:
            return Color(red: 0.89, green: 0.34, blue: 0.31)
        }
    }
}
