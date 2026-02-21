import SwiftUI

@main
struct StudioSampleApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootTabView: View {
    @StateObject private var store = SampleLibraryStore(
        repository: HybridSampleRepository(
            client: APIClient(baseURL: URL(string: "http://127.0.0.1:8000")!)
        )
    )

    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "waveform")
                }

            PlayerView()
                .tabItem {
                    Label("Player", systemImage: "record.circle")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(AppTheme.accent)
        .environmentObject(store)
    }
}
