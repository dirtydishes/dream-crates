import SwiftUI

enum AppTab: Hashable {
    case feed
    case player
    case library
    case settings
}

@MainActor
final class AppShellStore: ObservableObject {
    private enum Keys {
        static let selectedTheme = "dreamCrates.selectedTheme"
    }

    @Published var selectedTab: AppTab = .feed
    @Published var selectedThemeOption: AppThemeOption {
        didSet {
            userDefaults.set(selectedThemeOption.rawValue, forKey: Keys.selectedTheme)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedValue = userDefaults.string(forKey: Keys.selectedTheme)
        let storedTheme = storedValue.flatMap(AppThemeOption.init(rawValue:))
            ?? (storedValue == "all-light" ? .diddyParty : nil)
            ?? (storedValue == "white-party" ? .diddyParty : nil)
        self.selectedThemeOption = storedTheme ?? .allDark
    }

    var theme: AppTheme {
        selectedThemeOption.theme
    }
}
