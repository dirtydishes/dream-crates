import Foundation

enum DeviceIdentity {
    private static let key = "dreamCrates.deviceID"

    static func current(userDefaults: UserDefaults = .standard) -> String {
        if let existing = userDefaults.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString.lowercased()
        userDefaults.set(created, forKey: key)
        return created
    }
}
