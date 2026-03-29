import SwiftUI

@main
struct StudioSampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootTabView: View {
    @StateObject private var store: SampleLibraryStore
    @StateObject private var playbackPreferences = PlaybackPreferencesStore()
    @StateObject private var notificationPreferences: NotificationPreferencesStore

    init() {
        let client = APIClient(
            baseURL: AppConfiguration.apiBaseURL,
            deviceID: DeviceIdentity.current()
        )
        _store = StateObject(
            wrappedValue: SampleLibraryStore(
                repository: HybridSampleRepository(client: client)
            )
        )
        _notificationPreferences = StateObject(
            wrappedValue: NotificationPreferencesStore(apiClient: client)
        )
    }

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
        .environmentObject(playbackPreferences)
        .environmentObject(notificationPreferences)
    }
}
