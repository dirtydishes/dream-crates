import SwiftUI

struct SettingsView: View {
    @State private var notificationsEnabled = true
    @State private var quietHoursEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Notifications", isOn: $notificationsEnabled)
                Toggle("Quiet Hours", isOn: $quietHoursEnabled)
                Text("StudioSample v1 (internal)")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
        }
    }
}
