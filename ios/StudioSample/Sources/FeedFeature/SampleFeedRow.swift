import SwiftUI

struct SampleFeedRow: View {
    let item: SampleItem
    let isActive: Bool
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                UploaderAvatarView(
                    imageURL: item.channelAvatarURL,
                    fallbackText: item.uploaderName
                )
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.uploaderName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.label)

                    if let subtitle = item.uploaderSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if item.isSaved {
                    iconPill(systemImage: "bookmark.fill")
                }

                statusPill(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isActive && isPlaying ? "pause.fill" : "play.fill",
                    isEmphasized: isActive
                )
            }

            Text(item.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.label)
                .lineLimit(3)

            SampleArtworkView(url: item.artworkURL)
                .frame(maxWidth: .infinity)
                .frame(height: item.artworkURL == nil ? 140 : 180)

            HStack(spacing: 12) {
                if let durationSeconds = item.durationSeconds {
                    metaLabel(formatDuration(durationSeconds), systemImage: "waveform")
                }

                metaLabel(relativeTimestamp, systemImage: "clock")

                if item.downloadState == .downloaded {
                    metaLabel("Offline", systemImage: "arrow.down.circle.fill")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.18, blue: 0.17),
                            Color(red: 0.14, green: 0.14, blue: 0.13),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(isActive ? AppTheme.accent.opacity(0.7) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 10)
    }

    private var relativeTimestamp: String {
        item.publishedAt.formatted(.relative(presentation: .named))
    }

    private func metaLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.label.opacity(0.72))
    }

    private func statusPill(_ text: String, systemImage: String, isEmphasized: Bool = false) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isEmphasized ? Color.black.opacity(0.82) : AppTheme.label.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isEmphasized ? AppTheme.accent : Color.white.opacity(0.07))
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private func iconPill(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.label.opacity(0.82))
            .padding(9)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
            )
    }

    private func formatDuration(_ durationSeconds: Int) -> String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SampleArtworkView: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.accent.opacity(0.18),
                            AppTheme.panel,
                            Color.black.opacity(0.84),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                        .tint(AppTheme.label)
                }
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.label.opacity(0.88))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct UploaderAvatarView: View {
    let imageURL: URL?
    let fallbackText: String

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarFallback
                }
            } else {
                avatarFallback
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.9), Color.orange.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initials(from: fallbackText))
                .font(.caption.weight(.bold))
                .foregroundStyle(.black.opacity(0.78))
        }
    }

    private func initials(from text: String) -> String {
        let parts = text
            .replacingOccurrences(of: "@", with: "")
            .split(separator: " ")
            .prefix(2)

        let letters = parts.compactMap { $0.first }
        return letters.isEmpty ? "DC" : String(letters).uppercased()
    }
}
