//
//  LiveActivityController.swift
//  Taggd
//
//  Drives the Live Activity from the app. The app owns the running clock;
//  ActivityKit only reflects it, so a crash leaves no orphaned server timer.
//

import Foundation
import ActivityKit

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    private var activity: Activity<SessionActivityAttributes>?

    private func makeState(isRunning: Bool, elapsed: TimeInterval, description: String, tags: [String]) -> SessionActivityAttributes.ContentState {
        SessionActivityAttributes.ContentState(
            isRunning: isRunning,
            startDate: Date().addingTimeInterval(-elapsed),
            elapsed: elapsed,
            descriptionText: description.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags
        )
    }

    /// Starts a Live Activity for a new session (no-op if the user disabled them).
    func start(elapsed: TimeInterval, description: String, tags: [String]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Clear any stale activity from a previous run before requesting a new one.
        endAllExistingActivities()

        let attributes = SessionActivityAttributes(sessionName: "Tagged")
        let state = makeState(isRunning: true, elapsed: elapsed, description: description, tags: tags)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    /// Reflects a pause/resume or edited description/tags into the current activity.
    func update(isRunning: Bool, elapsed: TimeInterval, description: String, tags: [String]) {
        guard let activity else { return }
        let state = makeState(isRunning: isRunning, elapsed: elapsed, description: description, tags: tags)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Ends the current activity immediately.
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }

    private func endAllExistingActivities() {
        for activity in Activity<SessionActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
