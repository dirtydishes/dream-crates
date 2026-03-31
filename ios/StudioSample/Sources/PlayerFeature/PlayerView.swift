import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var store: SampleLibraryStore
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playbackPreferences: PlaybackPreferencesStore

    private let baseSpinDuration = 3.2

    @State private var rotation: Double = 0
    @State private var spinner: Task<Void, Never>?
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false
    @State private var showingPlaybackControls = false

    var body: some View {
        let selected = store.currentSample

        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text("Studio Deck")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.label)

                Text(selected?.title ?? "No sample selected")
                    .font(.headline)
                    .foregroundStyle(AppTheme.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                if let selected {
                    uploaderBadge(for: selected)
                }

                recordView(for: selected)

                progressSection

                playbackControlsButton

                transportSection(for: selected)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showingPlaybackControls) {
            playbackControlsSheet
        }
        .onAppear {
            playback.configureIfNeeded()
            playback.applyPreferences(playbackPreferences.currentSettings)
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
        .onChange(of: playbackPreferences.speed) { _, _ in
            playback.applyPreferences(playbackPreferences.currentSettings)
            if playback.isPlaying {
                startSpinning()
            }
        }
        .onChange(of: playbackPreferences.transposeSemitones) { _, _ in
            playback.applyPreferences(playbackPreferences.currentSettings)
        }
        .onChange(of: playbackPreferences.mode) { _, newMode in
            Task {
                await updatePlaybackMode(to: newMode)
            }
        }
    }

    private func uploaderBadge(for selected: SampleItem) -> some View {
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

    private func recordView(for selected: SampleItem?) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.black, AppTheme.panel],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 260, height: 260)

            Group {
                if let artworkURL = selected?.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                            .tint(AppTheme.label)
                    }
                } else {
                    ZStack {
                        AppTheme.panel.opacity(0.7)
                        Image(systemName: "music.note")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(AppTheme.label.opacity(0.8))
                    }
                }
            }
            .frame(width: 252, height: 252)
            .clipShape(Circle())

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.clear, Color.black.opacity(0.62)],
                        center: .center,
                        startRadius: 32,
                        endRadius: 126
                    )
                )
                .frame(width: 252, height: 252)

            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .frame(width: 252, height: 252)

            Circle()
                .stroke(Color.black.opacity(0.28), lineWidth: 1)
                .frame(width: 228, height: 228)

            Circle()
                .stroke(Color.black.opacity(0.22), lineWidth: 1)
                .frame(width: 194, height: 194)

            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                .frame(width: 160, height: 160)

            Circle()
                .fill(AppTheme.accent)
                .frame(width: 54, height: 54)
                .overlay(
                    Circle()
                        .fill(Color.black.opacity(0.84))
                        .frame(width: 14, height: 14)
                )

            Circle()
                .stroke(AppTheme.accent.opacity(0.65), lineWidth: 2)
                .frame(width: 260, height: 260)
        }
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 12)
    }

    private var progressSection: some View {
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
    }

    private var playbackControlsButton: some View {
        Button {
            showingPlaybackControls = true
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Playback")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.label)

                    Text(playbackSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(playbackPreferences.mode.displayName.uppercased())
                        .font(.caption2.weight(.bold))
                        .kerning(0.8)
                        .foregroundStyle(AppTheme.accent)

                    Image(systemName: "slider.horizontal.3")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.label)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.panel, AppTheme.panel.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func transportSection(for selected: SampleItem?) -> some View {
        HStack(spacing: 16) {
            Button {
                if playback.isPlaying {
                    playback.pause()
                } else if playback.canResumeCurrentItem {
                    playback.resume()
                } else if let selected {
                    Task {
                        await play(selected)
                    }
                }
            } label: {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(selected == nil)

            if let selected {
                Button {
                    Task {
                        await store.toggleSaved(sampleID: selected.id)
                    }
                } label: {
                    Image(systemName: selected.isSaved ? "bookmark.fill" : "bookmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var playbackControlsSheet: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Playback")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.label)

                Text(playbackHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                Picker("Mode", selection: $playbackPreferences.mode) {
                    ForEach(PlaybackMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                sliderSection(
                    title: "Speed",
                    valueLabel: String(format: "%.2fx", playbackPreferences.speed),
                    resetLabel: "Reset",
                    resetAction: { playbackPreferences.speed = 1.0 }
                ) {
                    Slider(
                        value: $playbackPreferences.speed,
                        in: PlaybackSettings.speedRange,
                        step: 0.05
                    )
                    .tint(AppTheme.accent)
                }

                if playbackPreferences.mode == .warp {
                    sliderSection(
                        title: "Transpose",
                        valueLabel: String(format: "%+.0f st", playbackPreferences.transposeSemitones),
                        resetLabel: "Reset",
                        resetAction: { playbackPreferences.transposeSemitones = 0 }
                    ) {
                        Slider(
                            value: $playbackPreferences.transposeSemitones,
                            in: PlaybackSettings.transposeRange,
                            step: 1
                        )
                        .tint(AppTheme.accent)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.bg.ignoresSafeArea())
        .presentationDetents([.height(playbackControlsHeight)])
        .presentationDragIndicator(.hidden)
    }

    private func sliderSection<Content: View>(
        title: String,
        valueLabel: String,
        resetLabel: String,
        resetAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.label)

                Spacer()

                Button(resetLabel, action: resetAction)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)

                Text(valueLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content()
        }
    }

    private var playbackSummary: String {
        switch playbackPreferences.mode {
        case .turntable:
            return String(format: "Turntable keeps pitch tied to speed at %.2fx.", playbackPreferences.speed)
        case .warp:
            return String(
                format: "Warp runs at %.2fx with %@.",
                playbackPreferences.speed,
                String(format: "%+.0f st transpose", playbackPreferences.transposeSemitones)
            )
        }
    }

    private var playbackHint: String {
        switch playbackPreferences.mode {
        case .turntable:
            return "Turntable keeps playback immediate and moves pitch with speed."
        case .warp:
            return "Warp keeps tempo and pitch independent using local on-device processing."
        }
    }

    private var playbackControlsHeight: CGFloat {
        playbackPreferences.mode == .warp ? 336 : 272
    }

    private func play(_ item: SampleItem) async {
        do {
            let sourceURL = try await store.preparePlaybackURL(
                for: item.id,
                mode: playbackPreferences.mode
            )
            playback.configureIfNeeded()
            playback.play(
                title: item.title,
                sourceURL: sourceURL,
                settings: playbackPreferences.currentSettings
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
                    withAnimation(.linear(duration: spinDuration)) {
                        rotation += 360
                    }
                }
                try? await Task.sleep(for: .seconds(spinDuration))
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

    private var spinDuration: Double {
        let effectiveRate = max(playback.effectiveVisualRate, 0.25)
        return baseSpinDuration / effectiveRate
    }

    private func updatePlaybackMode(to mode: PlaybackMode) async {
        guard playback.hasCurrentItem, let selected = store.currentSample else {
            playback.applyPreferences(playbackPreferences.currentSettings)
            return
        }

        let wasPlaying = playback.isPlaying
        let startTime = playback.currentTime

        do {
            let sourceURL = try await store.preparePlaybackURL(for: selected.id, mode: mode)
            playback.play(
                title: selected.title,
                sourceURL: sourceURL,
                settings: playbackPreferences.currentSettings,
                startTime: startTime,
                autoplay: wasPlaying
            )
        } catch {
            playback.stopAndReset()
        }
    }
}
