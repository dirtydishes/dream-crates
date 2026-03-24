import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var store: SampleLibraryStore

    @State private var speed: Double = 1.0
    @State private var rotation: Double = 0
    @State private var spinner: Task<Void, Never>?
    @StateObject private var playback = PlaybackController()

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
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 26, height: 26)
            }
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)

            HStack(spacing: 20) {
                Button(playback.isPlaying ? "Pause" : "Play") {
                    if playback.isPlaying {
                        playback.pause()
                        stopSpinning()
                    } else {
                        let selectedID = selected?.id ?? ""
                        let sourceURL = store.playbackURL(for: selectedID)
                        playback.play(
                            title: selected?.title ?? "Dream Crates",
                            sourceURL: sourceURL,
                            rate: Float(speed)
                        )
                        startSpinning()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)

                Menu {
                    ForEach(stride(from: 0.5, through: 2.0, by: 0.25).map { $0 }, id: \.self) { value in
                        Button(String(format: "%.2fx", value)) {
                            speed = value
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
        withAnimation(.easeOut(duration: 0.85)) {
            rotation += 45
        }
    }
}
