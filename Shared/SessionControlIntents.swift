//
//  SessionControlIntents.swift
//  Taggd — shared between the app and the widget extension.
//
//  Live Activity buttons trigger these intents. A LiveActivityIntent runs in the
//  app's process, so each intent simply posts a notification that the app's
//  TimeTracker observes — keeping this file free of app-only types so it can also
//  compile into the widget extension.
//

import AppIntents
import Foundation

extension Notification.Name {
    static let taggdPauseSession = Notification.Name("rocks.toepper.tagged.pauseSession")
    static let taggdResumeSession = Notification.Name("rocks.toepper.tagged.resumeSession")
    static let taggdStopSession = Notification.Name("rocks.toepper.tagged.stopSession")
}

struct PauseSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause session"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .taggdPauseSession, object: nil)
        return .result()
    }
}

struct ResumeSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume session"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .taggdResumeSession, object: nil)
        return .result()
    }
}

struct StopSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop session"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .taggdStopSession, object: nil)
        return .result()
    }
}
