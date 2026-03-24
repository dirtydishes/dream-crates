import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var notifications: NotificationPreferencesStore

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Notifications", isOn: $notifications.notificationsEnabled)
                Toggle("Quiet Hours", isOn: $notifications.quietHoursEnabled)
                Text("Dream Crates v1 (internal)")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .task {
                await notifications.bootstrap()
            }
        }
    }
}
