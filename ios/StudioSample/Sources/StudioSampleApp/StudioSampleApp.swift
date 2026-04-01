import SwiftUI

@main
struct StudioSampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appShell = AppShellStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appShell)
                .environment(\.appTheme, appShell.theme)
                .font(appShell.theme.font(.body))
                .preferredColorScheme(appShell.theme.colorScheme)
        }
    }
}

private struct RootTabView: View {
    @EnvironmentObject private var appShell: AppShellStore
    @StateObject private var playback = PlaybackController()
    @StateObject private var store: SampleLibraryStore
    @StateObject private var playbackPreferences = PlaybackPreferencesStore()
    @StateObject private var notificationPreferences: NotificationPreferencesStore

    init() {
        let apiBaseURL = AppConfiguration.apiBaseURL
        print("DreamCrates App configured API base URL -> \(apiBaseURL.absoluteString)")
        let client = APIClient(
            baseURL: apiBaseURL,
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
        let theme = appShell.theme

        TabView(selection: $appShell.selectedTab) {
            FeedView()
                .tag(AppTab.feed)
                .tabItem {
                    Label("Feed", systemImage: "waveform")
                }

            PlayerView()
                .tag(AppTab.player)
                .tabItem {
                    Label("Player", systemImage: "record.circle")
                }

            LibraryView()
                .tag(AppTab.library)
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
        }
        .tint(theme.accent)
        .environmentObject(playback)
        .environmentObject(store)
        .environmentObject(playbackPreferences)
        .environmentObject(notificationPreferences)
    }
}
