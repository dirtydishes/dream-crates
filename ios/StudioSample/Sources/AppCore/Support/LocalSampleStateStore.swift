import Foundation

struct PersistedSampleState: Codable, Equatable {
    enum SyncStatus: String, Codable {
        case synced
        case pending
    }

    var isSaved: Bool
    var savedAt: Date?
    var syncStatus: SyncStatus
}

final class LocalSampleStateStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = root.appendingPathComponent("dream-crates-sample-state.json")
    }

    func allStates() -> [String: PersistedSampleState] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: PersistedSampleState].self, from: data)) ?? [:]
    }

    func state(for sampleID: String) -> PersistedSampleState? {
        allStates()[sampleID]
    }

    func setState(_ state: PersistedSampleState, for sampleID: String) {
        var states = allStates()
        states[sampleID] = state
        write(states)
    }

    func removeState(for sampleID: String) {
        var states = allStates()
        states.removeValue(forKey: sampleID)
        write(states)
    }

    private func write(_ states: [String: PersistedSampleState]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(states)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to persist sample state: \(error)")
        }
    }
}
