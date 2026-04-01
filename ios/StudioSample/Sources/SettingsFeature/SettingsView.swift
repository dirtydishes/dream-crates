import SwiftUI

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var appShell: AppShellStore
    @EnvironmentObject private var notifications: NotificationPreferencesStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AppThemeOption.allCases) { option in
                        Button {
                            appShell.selectedThemeOption = option
                        } label: {
                            ThemeChoiceRow(
                                option: option,
                                isSelected: option == appShell.selectedThemeOption
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(theme.bg)
                    }
                } header: {
                    Text("Appearance")
                }

                Section("Notifications") {
                    Toggle("Notifications", isOn: $notifications.notificationsEnabled)
                        .listRowBackground(theme.panel)
                    Toggle("Quiet Hours", isOn: $notifications.quietHoursEnabled)
                        .listRowBackground(theme.panel)
                }

                Section("About") {
                    Text("Dream Crates v1 (internal)")
                        .foregroundStyle(theme.secondaryLabel)
                        .listRowBackground(theme.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Settings")
            .tint(theme.accent)
            .task {
                await notifications.bootstrap()
            }
        }
    }
}

private struct ThemeChoiceRow: View {
    let option: AppThemeOption
    let isSelected: Bool

    private var previewTheme: AppTheme {
        option.theme
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0 ..< previewColors.count, id: \.self) { index in
                    Circle()
                        .fill(previewColors[index])
                        .frame(width: index == 0 ? 18 : 14, height: index == 0 ? 18 : 14)
                }
            }
            .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(option.displayName)
                    .font(previewTheme.font(.headline, weight: .semibold))
                    .foregroundStyle(previewTheme.label)

                Text(option.detail)
                    .font(previewTheme.font(.caption))
                    .foregroundStyle(previewTheme.secondaryLabel)
            }

            Spacer(minLength: 12)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? previewTheme.accent : previewTheme.secondaryLabel)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(previewTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? previewTheme.activeStroke : previewTheme.chromeStroke, lineWidth: 1)
        )
    }

    private var previewColors: [Color] {
        [previewTheme.accent, previewTheme.panel, previewTheme.bg]
    }
}
