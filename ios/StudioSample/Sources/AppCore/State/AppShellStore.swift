import SwiftUI

enum AppTab: Hashable {
    case feed
    case player
    case library
    case settings
}

@MainActor
final class AppShellStore: ObservableObject {
    @Published var selectedTab: AppTab = .feed
}
