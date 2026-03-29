import Foundation
import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    static let dreamCratesDidRegisterForRemoteNotifications =
        Notification.Name("dreamCratesDidRegisterForRemoteNotifications")
}

@MainActor
final class NotificationPreferencesStore: ObservableObject {
    private enum Keys {
        static let notificationsEnabled = "dreamCrates.notificationsEnabled"
        static let quietHoursEnabled = "dreamCrates.quietHoursEnabled"
        static let quietStartHour = "dreamCrates.quietStartHour"
        static let quietEndHour = "dreamCrates.quietEndHour"
        static let apnsToken = "dreamCrates.apnsToken"
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            userDefaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            Task { await syncPreferences(registerIfNeeded: notificationsEnabled) }
        }
    }

    @Published var quietHoursEnabled: Bool {
        didSet {
            userDefaults.set(quietHoursEnabled, forKey: Keys.quietHoursEnabled)
            Task { await syncPreferences(registerIfNeeded: false) }
        }
    }

    let quietStartHour: Int
    let quietEndHour: Int

    private let apiClient: APIClient
    private let userDefaults: UserDefaults

    init(apiClient: APIClient, userDefaults: UserDefaults = .standard) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
        self.notificationsEnabled = userDefaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.quietHoursEnabled = userDefaults.object(forKey: Keys.quietHoursEnabled) as? Bool ?? true
        self.quietStartHour = userDefaults.object(forKey: Keys.quietStartHour) as? Int ?? 22
        self.quietEndHour = userDefaults.object(forKey: Keys.quietEndHour) as? Int ?? 8

        NotificationCenter.default.addObserver(
            forName: .dreamCratesDidRegisterForRemoteNotifications,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.object as? String else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.userDefaults.set(token, forKey: Keys.apnsToken)
                await self.syncRegistration(tokenHex: token)
            }
        }
    }

    func bootstrap() async {
        await loadRemotePreferences()
        if notificationsEnabled {
            await requestAuthorizationAndRegisterIfNeeded()
        }
    }

    func requestAuthorizationAndRegisterIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await syncRegistration(tokenHex: apnsToken)
        } else {
            notificationsEnabled = false
        }
    }

    var apnsToken: String {
        userDefaults.string(forKey: Keys.apnsToken) ?? ""
    }

    private func loadRemotePreferences() async {
        guard let remote = try? await apiClient.fetchPreferences() else { return }
        notificationsEnabled = remote.notificationsEnabled
        quietHoursEnabled = remote.quietStartHour != nil && remote.quietEndHour != nil
    }

    private func syncPreferences(registerIfNeeded: Bool) async {
        do {
            try await apiClient.updatePreferences(
                notificationsEnabled: notificationsEnabled,
                quietStartHour: quietHoursEnabled ? quietStartHour : nil,
                quietEndHour: quietHoursEnabled ? quietEndHour : nil
            )
        } catch {
            // Keep the latest local preferences for the next sync attempt.
        }

        if registerIfNeeded {
            await requestAuthorizationAndRegisterIfNeeded()
        }
    }

    private func syncRegistration(tokenHex: String) async {
        do {
            try await apiClient.registerDevice(
                apnsToken: tokenHex,
                notificationsEnabled: notificationsEnabled,
                quietStartHour: quietHoursEnabled ? quietStartHour : nil,
                quietEndHour: quietHoursEnabled ? quietEndHour : nil
            )
        } catch {
            // Device registration is best-effort until the backend is reachable.
        }
    }
}
