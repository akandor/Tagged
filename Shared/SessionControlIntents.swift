//
//  SessionControlIntents.swift
//  Taggd — shared between the app and the widget extension.
//
//  Live Activity (iOS) and home-screen / Notification Center widget buttons
//  trigger these intents.
//
//  • iOS: they're LiveActivityIntents, so they run in the app's process and post
//    an in-process notification the app's TimeTracker observes.
//  • macOS: plain AppIntents run in the widget extension process, so they post a
//    cross-process DistributedNotification that the always-running menu-bar app
//    observes.
//
//  Either way they also write an optimistic snapshot + a pending action (so the
//  widget updates instantly and the app can reconcile). The notification names
//  live in WidgetSharedStore so both platforms share them without pulling in
//  ActivityKit.
//

import AppIntents
import Foundation
import WidgetKit

#if os(iOS)
typealias SessionControlIntent = LiveActivityIntent
#else
typealias SessionControlIntent = AppIntent
#endif

/// Shared side effects for a control tap: optimistic snapshot, pending action,
/// app notification, and a widget (+ Control Center, iOS) reload.
func dispatchSessionAction(_ kind: PendingWidgetAction.Kind, notification: Notification.Name) {
    let now = Date()
    WidgetSharedStore.mutate { $0 = $0.applying(kind, at: now) }
    WidgetSharedStore.setPending(PendingWidgetAction(id: UUID(), kind: kind, date: now))
    #if os(iOS)
    NotificationCenter.default.post(name: notification, object: nil)
    #elseif os(macOS)
    DistributedNotificationCenter.default().post(name: notification, object: nil)
    #endif
    WidgetCenter.shared.reloadAllTimelines()
    #if os(iOS)
    if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    #endif
}

struct StartSessionIntent: SessionControlIntent {
    static let title: LocalizedStringResource = "Start session"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        dispatchSessionAction(.start, notification: .taggdStartSession)
        return .result()
    }
}

struct PauseSessionIntent: SessionControlIntent {
    static let title: LocalizedStringResource = "Pause session"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        dispatchSessionAction(.pause, notification: .taggdPauseSession)
        return .result()
    }
}

struct ResumeSessionIntent: SessionControlIntent {
    static let title: LocalizedStringResource = "Resume session"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        dispatchSessionAction(.resume, notification: .taggdResumeSession)
        return .result()
    }
}

struct StopSessionIntent: SessionControlIntent {
    static let title: LocalizedStringResource = "Stop session"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        dispatchSessionAction(.stop, notification: .taggdStopSession)
        return .result()
    }
}
