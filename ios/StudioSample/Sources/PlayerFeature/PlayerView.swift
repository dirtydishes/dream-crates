import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var store: SampleLibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playbackPreferences: PlaybackPreferencesStore

    @State private var rotation: Double = 0
    @State private var spinner: Task<Void, Never>?
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        let selected = store.currentSample

        VStack(spacing: 24) {
            Text("Studio Deck")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.label)

            Text(selected?.title ?? "No sample selected")
                .font(.headline)
                .foregroundStyle(AppTheme.label)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let selected {
                HStack(spacing: 10) {
                    UploaderAvatarView(imageURL: selected.channelAvatarURL, fallbackText: selected.uploaderName)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.uploaderName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.label)

                        if let subtitle = selected.uploaderSubtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.panel)
                .clipShape(Capsule())
            }

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.black, AppTheme.panel],
                            center: .center,
                            startRadius: 8,
                            endRadius: 140
                        )
                    )
                    .frame(width: 260, height: 260)
                    .overlay(Circle().stroke(AppTheme.accent.opacity(0.6), lineWidth: 2))
                if let artworkURL = selected?.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                            .tint(AppTheme.label)
                    }
                    .frame(width: 220, height: 220)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 26, height: 26)
            }
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubPosition : playback.currentTime },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0 ... max(playback.duration, 1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            playback.seek(to: scrubPosition)
                        }
                    }
                )
                .tint(AppTheme.accent)
                .disabled(!playback.hasCurrentItem)

                HStack {
                    Text(formatTime(isScrubbing ? scrubPosition : playback.currentTime))
                    Spacer()
                    Text(formatTime(playback.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                Button(playback.isPlaying ? "Pause" : "Play") {
                    if playback.isPlaying {
                        playback.pause()
                    } else if playback.canResumeCurrentItem {
                        playback.resume()
                    } else if let selected {
                        Task {
                            await play(selected)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(selected == nil)

                Menu {
                    ForEach(stride(from: 0.5, through: 2.0, by: 0.25).map { $0 }, id: \.self) { value in
                        Button(String(format: "%.2fx", value)) {
                            playbackPreferences.speed = value
                            playback.updateRate(Float(value))
                        }
                    }
                } label: {
                    Text(String(format: "Speed %.2fx", speed))
                }

                if let selected {
                    Button {
                        Task {
                            await store.toggleSaved(sampleID: selected.id)
                        }
                    } label: {
                        Image(systemName: selected.isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bg)
        .onAppear {
            playback.configureIfNeeded()
            playback.updateRate(Float(speed))
            scrubPosition = playback.currentTime
        }
        .onChange(of: playback.isPlaying) { _, isPlaying in
            if isPlaying {
                startSpinning()
            } else {
                stopSpinning()
            }
        }
        .onChange(of: playback.currentTime) { _, newValue in
            guard !isScrubbing else { return }
            scrubPosition = newValue
        }
        .onChange(of: store.currentSampleID) { _, _ in
            guard !isScrubbing else { return }
            scrubPosition = playback.currentTime
        }
    }

    private var speed: Double { playbackPreferences.speed }

    private func play(_ item: SampleItem) async {
        do {
            let sourceURL = try await store.resolvedPlaybackURL(for: item.id)
            playback.configureIfNeeded()
            playback.play(
                title: item.title,
                sourceURL: sourceURL,
                rate: Float(speed)
            )
        } catch {
            playback.stopAndReset()
        }
    }

    private func startSpinning() {
        spinner?.cancel()
        spinner = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.linear(duration: 1.2 / speed)) {
                        rotation += 360
                    }
                }
                try? await Task.sleep(for: .seconds(1.2 / speed))
            }
        }
    }

    private func stopSpinning() {
        spinner?.cancel()
        guard rotation != 0 else { return }
        withAnimation(.easeOut(duration: 0.85)) {
            rotation += 45
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
