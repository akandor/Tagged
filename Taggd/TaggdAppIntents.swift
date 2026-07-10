//
//  TaggdAppIntents.swift
//  Taggd
//
//  Siri / Shortcuts-facing App Intents. Unlike the widget/Live Activity control
//  intents (which are non-discoverable and only wake the app to relay a
//  notification), these are invoked by Shortcuts in the app's process, so they
//  drive TimeTracker.shared directly and speak a confirmation back.
//

import AppIntents
import Foundation

// MARK: - Tag resolution

/// Resolves a spoken/typed tag name to a library tag (keeping its color) or an
/// ad-hoc tag if it isn't in the library yet.
@MainActor
private func resolveTag(_ name: String) -> Tag {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let library = TagStore().tags
    if let match = library.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        return match
    }
    return Tag(name: trimmed)
}

// MARK: - Start

struct StartTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Tracking"
    static let description = IntentDescription("Starts a new time-tracking session.")
    static let openAppWhenRun = false

    @Parameter(title: "Description", requestValueDialog: "What are you working on?")
    var taskDescription: String?

    @Parameter(title: "Tag")
    var tag: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start tracking \(\.$taskDescription) with tag \(\.$tag)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tracker = TimeTracker.shared
        guard tracker.phase != .running else {
            return .result(dialog: "You're already tracking.")
        }
        if let taskDescription, !taskDescription.isEmpty {
            tracker.taskDescription = taskDescription
        }
        if let tag, !tag.isEmpty {
            tracker.addTag(resolveTag(tag))
        }
        tracker.start()

        let label = tracker.taskDescription.isEmpty ? "" : " “\(tracker.taskDescription)”"
        return .result(dialog: "Started tracking\(label).")
    }
}

// MARK: - Stop

struct StopTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Tracking"
    static let description = IntentDescription("Stops the current session and saves it.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tracker = TimeTracker.shared
        guard tracker.phase != .idle else {
            return .result(dialog: "Nothing is being tracked.")
        }
        let elapsed = tracker.elapsed
        tracker.stop()
        return .result(dialog: "Stopped. You tracked \(formatDuration(elapsed)).")
    }
}

// MARK: - Pause / Resume

struct PauseTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Tracking"
    static let description = IntentDescription("Pauses the running session.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tracker = TimeTracker.shared
        guard tracker.phase == .running else {
            return .result(dialog: "There's no running session to pause.")
        }
        tracker.pause()
        return .result(dialog: "Paused at \(formatDuration(tracker.elapsed)).")
    }
}

struct ResumeTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Tracking"
    static let description = IntentDescription("Resumes a paused session.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tracker = TimeTracker.shared
        guard tracker.phase == .paused else {
            return .result(dialog: "There's no paused session to resume.")
        }
        tracker.resume()
        return .result(dialog: "Resumed.")
    }
}

// MARK: - Status query

struct TrackingStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Tracking Status"
    static let description = IntentDescription("Reports whether a session is running and for how long.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tracker = TimeTracker.shared
        let label = tracker.taskDescription.isEmpty ? "" : " on “\(tracker.taskDescription)”"
        switch tracker.phase {
        case .idle:
            return .result(dialog: "No session is running.")
        case .running:
            return .result(dialog: "Tracking\(label) for \(formatDuration(tracker.elapsed)).")
        case .paused:
            return .result(dialog: "Paused\(label) at \(formatDuration(tracker.elapsed)).")
        }
    }
}

// MARK: - Siri phrases

struct TaggdShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTrackingIntent(),
            phrases: [
                "Start tracking in \(.applicationName)",
                "Start a \(.applicationName) session",
                "Begin tracking with \(.applicationName)"
            ],
            shortTitle: "Start Tracking",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopTrackingIntent(),
            phrases: [
                "Stop tracking in \(.applicationName)",
                "Stop my \(.applicationName) session",
                "End \(.applicationName) session"
            ],
            shortTitle: "Stop Tracking",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: PauseTrackingIntent(),
            phrases: [
                "Pause tracking in \(.applicationName)",
                "Pause my \(.applicationName) session"
            ],
            shortTitle: "Pause Tracking",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeTrackingIntent(),
            phrases: [
                "Resume tracking in \(.applicationName)",
                "Resume my \(.applicationName) session"
            ],
            shortTitle: "Resume Tracking",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: TrackingStatusIntent(),
            phrases: [
                "What am I tracking in \(.applicationName)",
                "\(.applicationName) status"
            ],
            shortTitle: "Tracking Status",
            systemImageName: "clock"
        )
    }
}
