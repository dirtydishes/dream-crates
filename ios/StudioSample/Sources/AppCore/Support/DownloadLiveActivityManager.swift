import ActivityKit
import Foundation

@MainActor
final class DownloadLiveActivityManager {
    enum UpdateOutcome: Equatable {
        case created
        case updated
        case ended
        case disabled
        case failed(String)
        case notFound
    }

    static let shared = DownloadLiveActivityManager()

    private var activitiesBySampleID: [String: Activity<DownloadLiveActivityAttributes>] = [:]

    func update(sample: SampleItem, statusText: String, progress: Double?, isFinished: Bool = false) async -> UpdateOutcome {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .disabled
        }

        let contentState = DownloadLiveActivityAttributes.ContentState(
            statusText: statusText,
            progress: progress,
            isFinished: isFinished
        )

        if let existing = activitiesBySampleID[sample.id]
            ?? Activity<DownloadLiveActivityAttributes>.activities.first(where: { $0.attributes.sampleID == sample.id }) {
            activitiesBySampleID[sample.id] = existing
            await existing.update(ActivityContent(state: contentState, staleDate: nil))
            return .updated
        }

        let attributes = DownloadLiveActivityAttributes(
            sampleID: sample.id,
            title: sample.title,
            uploaderName: sample.uploaderName,
            uploaderImageURLString: sample.channelAvatarURL?.absoluteString ?? sample.artworkURL?.absoluteString
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: nil),
                pushType: nil
            )
            activitiesBySampleID[sample.id] = activity
            return .created
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func end(
        sampleID: String,
        finalStatusText: String,
        progress: Double?,
        dismissalPolicy: ActivityUIDismissalPolicy = .default
    ) async -> UpdateOutcome {
        let activity = activitiesBySampleID[sampleID] ?? Activity<DownloadLiveActivityAttributes>.activities.first {
            $0.attributes.sampleID == sampleID
        }
        guard let activity else { return .notFound }

        let finalState = DownloadLiveActivityAttributes.ContentState(
            statusText: finalStatusText,
            progress: progress,
            isFinished: true
        )

        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: dismissalPolicy
        )
        activitiesBySampleID.removeValue(forKey: sampleID)
        return .ended
    }
}
