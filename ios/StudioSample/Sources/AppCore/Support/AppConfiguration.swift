import Foundation

enum AppConfiguration {
    private static let infoPlistKey = "DreamCratesAPIBaseURL"
    private static let environmentKey = "DREAM_CRATES_API_BASE_URL"
    private static let defaultAPIBaseURL = "https://samples.dpdrm.com"

    static var apiBaseURL: URL {
        let rawValue =
            ProcessInfo.processInfo.environment[environmentKey]
            ?? Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
            ?? defaultAPIBaseURL

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedValue.isEmpty,
            !trimmedValue.hasPrefix("$("),
            let url = URL(string: trimmedValue)
        else {
            preconditionFailure("Invalid API base URL configuration: \(rawValue)")
        }

        return url
    }
}
