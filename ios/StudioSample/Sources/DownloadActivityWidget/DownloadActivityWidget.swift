import ActivityKit
import SwiftUI
import WidgetKit

private enum DownloadActivityTheme {
    static let background = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let panel = Color(red: 0.18, green: 0.17, blue: 0.16)
    static let accent = Color(red: 0.92, green: 0.56, blue: 0.22)
    static let label = Color(red: 0.92, green: 0.91, blue: 0.87)
    static let secondary = Color.white.opacity(0.62)
}

@main
struct DownloadActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        DownloadActivityWidget()
    }
}

struct DownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadLiveActivityAttributes.self) { context in
            DownloadActivityLockScreenView(context: context)
                .activityBackgroundTint(DownloadActivityTheme.background)
                .activitySystemActionForegroundColor(DownloadActivityTheme.label)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DownloadActivityArtwork(context: context, size: 52)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    DownloadActivityBadge(context: context)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(DownloadActivityTheme.label)
                            .lineLimit(2)

                        Text(context.attributes.uploaderName)
                            .font(.caption)
                            .foregroundStyle(DownloadActivityTheme.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    DownloadActivityProgress(context: context, showLabel: true)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(DownloadActivityTheme.accent)
            } compactTrailing: {
                DownloadActivityCompactTrailing(context: context)
            } minimal: {
                ZStack {
                    Circle()
                        .fill(DownloadActivityTheme.panel)

                    Image(systemName: context.state.isFinished ? "checkmark" : "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(context.state.isFinished ? DownloadActivityTheme.label : DownloadActivityTheme.accent)
                }
            }
            .keylineTint(DownloadActivityTheme.accent)
        }
    }
}

private struct DownloadActivityLockScreenView: View {
    let context: ActivityViewContext<DownloadLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            DownloadActivityArtwork(context: context, size: 56)

            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DownloadActivityTheme.label)
                    .lineLimit(2)

                Text(context.attributes.uploaderName)
                    .font(.caption)
                    .foregroundStyle(DownloadActivityTheme.secondary)
                    .lineLimit(1)

                DownloadActivityProgress(context: context, showLabel: true)
            }

            Spacer(minLength: 12)

            DownloadActivityBadge(context: context)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct DownloadActivityProgress: View {
    let context: ActivityViewContext<DownloadLiveActivityAttributes>
    let showLabel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(context.state.statusText.uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(0.7)
                    .foregroundStyle(DownloadActivityTheme.accent)

                if showLabel, let progress = context.state.progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(DownloadActivityTheme.label)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [DownloadActivityTheme.accent, DownloadActivityTheme.accent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * max(progressValue, 0.04))
                }
            }
            .frame(height: 6)
        }
    }

    private var progressValue: Double {
        min(max(context.state.progress ?? (context.state.isFinished ? 1 : 0), 0), 1)
    }
}

private struct DownloadActivityArtwork: View {
    let context: ActivityViewContext<DownloadLiveActivityAttributes>
    let size: CGFloat

    var body: some View {
        Group {
            if let artworkURLString = context.attributes.artworkURLString,
               let artworkURL = URL(string: artworkURLString) {
                AsyncImage(url: artworkURL) { image in
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [DownloadActivityTheme.accent.opacity(0.75), DownloadActivityTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.72))
        }
    }
}

private struct DownloadActivityBadge: View {
    let context: ActivityViewContext<DownloadLiveActivityAttributes>

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: context.state.isFinished ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(context.state.isFinished ? DownloadActivityTheme.label : DownloadActivityTheme.accent)

            if let progress = context.state.progress {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DownloadActivityTheme.secondary)
            }
        }
        .frame(minWidth: 42)
    }
}

private struct DownloadActivityCompactTrailing: View {
    let context: ActivityViewContext<DownloadLiveActivityAttributes>

    var body: some View {
        if let progress = context.state.progress, !context.state.isFinished {
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(DownloadActivityTheme.label)
        } else {
            Image(systemName: context.state.isFinished ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(context.state.isFinished ? DownloadActivityTheme.label : DownloadActivityTheme.accent)
        }
    }
}
