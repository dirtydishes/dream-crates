import SwiftUI

struct SampleFeedRow: View {
    @Environment(\.appTheme) private var theme

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
                        .font(theme.font(.subheadline, weight: .semibold))
                        .foregroundStyle(theme.label)

                    if let subtitle = item.uploaderSubtitle {
                        Text(subtitle)
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.secondaryLabel)
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
                .font(theme.font(.title3, weight: .semibold))
                .foregroundStyle(theme.label)
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
                        colors: theme.cardGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(isActive ? theme.activeStroke : theme.chromeStroke, lineWidth: 1)
        )
        .shadow(color: theme.shadow, radius: 16, x: 0, y: 10)
    }

    private var relativeTimestamp: String {
        item.publishedAt.formatted(.relative(presentation: .named))
    }

    private func metaLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(theme.font(.caption, weight: .medium))
            .foregroundStyle(theme.secondaryLabel)
    }

    private func statusPill(_ text: String, systemImage: String, isEmphasized: Bool = false) -> some View {
        Label(text, systemImage: systemImage)
            .font(theme.font(.caption, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(isEmphasized ? theme.accentLabel : theme.label.opacity(0.84))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isEmphasized ? theme.accent : theme.surfaceFill)
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private func iconPill(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(theme.font(.caption, weight: .semibold))
            .foregroundStyle(theme.label.opacity(0.82))
            .padding(9)
            .background(
                Capsule()
                    .fill(theme.surfaceFill)
            )
    }

    private func formatDuration(_ durationSeconds: Int) -> String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SampleArtworkView: View {
    @Environment(\.appTheme) private var theme

    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: theme.artworkGradient,
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
                        .tint(theme.label)
                }
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.label.opacity(0.88))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.chromeStroke, lineWidth: 1)
        )
    }
}

struct UploaderAvatarView: View {
    @Environment(\.appTheme) private var theme

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
        .overlay(Circle().stroke(theme.chromeStroke, lineWidth: 1))
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: theme.avatarGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initials(from: fallbackText))
                .font(theme.font(.caption, weight: .bold))
                .foregroundStyle(theme.accentLabel)
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
