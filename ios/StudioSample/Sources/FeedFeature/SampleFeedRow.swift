import SwiftUI

struct SampleFeedRow: View {
    let item: SampleItem
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SampleArtworkView(url: item.artworkURL, title: item.title)
                .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.label)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Label {
                                Text(item.publishedAt, style: .relative)
                            } icon: {
                                Image(systemName: "clock")
                            }

                            if let durationSeconds = item.durationSeconds {
                                Label(formatDuration(durationSeconds), systemImage: "waveform")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if isActive {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(8)
                            .background(AppTheme.accent.opacity(0.14))
                            .clipShape(Circle())
                    }
                }

                uploaderBadge

                if !item.genreTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(item.genreTags.prefix(3)), id: \.self) { tag in
                                Text(tag.key.replacingOccurrences(of: "_", with: " ").uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(AppTheme.label.opacity(0.78))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.06)))
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.panel, AppTheme.panel.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isActive ? AppTheme.accent.opacity(0.65) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
    }

    private var uploaderBadge: some View {
        HStack(spacing: 10) {
            UploaderAvatarView(
                imageURL: item.channelAvatarURL,
                fallbackText: item.uploaderName
            )
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.uploaderName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.label)
                    .lineLimit(1)

                if let subtitle = item.uploaderSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if item.isSaved {
                Text("IN LIBRARY")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatDuration(_ durationSeconds: Int) -> String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SampleArtworkView: View {
    let url: URL?
    let title: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.accent.opacity(0.35),
                            AppTheme.panel,
                            Color.black.opacity(0.85),
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
                    .font(.system(size: 34))
                    .foregroundStyle(AppTheme.label.opacity(0.88))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .padding(10)
        }
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
