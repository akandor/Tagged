//
//  WidgetSharedStore.swift
//  Taggd — shared between the app and the widget extension.
//
//  Home-screen widgets can't reach the app's in-memory TimeTracker or its
//  network client, so the app writes a compact snapshot of "what to show" into a
//  shared App Group container after every relevant change, and the widgets read
//  it in their timeline provider.
//
//  Interactive buttons write an optimistic snapshot plus a *pending action* into
//  the same container; the app reconciles that pending action into the real
//  tracker the next time it runs (see TimeTracker.applyPendingWidgetAction()).
//

import Foundation
import WidgetKit

enum TaggdAppGroup {
    /// Must match the App Group capability enabled on both the app and the
    /// widget extension targets. macOS requires the team-id prefix (the widget
    /// extension is sandboxed); iOS uses the plain `group.` form.
    #if os(macOS)
    static let identifier = "UE57845B3R.group.com.toepper.rocks.Tagged"
    #else
    static let identifier = "group.com.toepper.rocks.Tagged"
    #endif

    /// App Group defaults, falling back to standard defaults if the group isn't
    /// provisioned (e.g. in previews) so reads/writes never crash.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

extension Notification.Name {
    static let taggdStartSession = Notification.Name("rocks.toepper.tagged.startSession")
    static let taggdPauseSession = Notification.Name("rocks.toepper.tagged.pauseSession")
    static let taggdResumeSession = Notification.Name("rocks.toepper.tagged.resumeSession")
    static let taggdStopSession = Notification.Name("rocks.toepper.tagged.stopSession")
}

// MARK: - Snapshot models

/// A tag reduced to what a widget needs to draw its dot / chip.
struct WidgetTag: Codable, Hashable {
    var name: String
    var colorHex: String
}

/// One tag's rolled-up time for the medium widget's "Today" breakdown.
struct WidgetTagTotal: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var colorHex: String
    var seconds: TimeInterval
}

/// One finished entry in the large widget's timeline.
struct WidgetTimelineItem: Codable, Hashable, Identifiable {
    var id: String
    var start: Date
    var text: String
    var seconds: TimeInterval
    var tags: [WidgetTag]
}

/// Everything the home-screen widgets render. Written by the app, read by the
/// extension. Session fields describe the live stopwatch; the `today*` fields
/// describe the current day's finished entries.
struct WidgetSnapshot: Codable, Hashable {
    // Running session
    var isTracking: Bool          // running or paused (a session exists)
    var isRunning: Bool           // running (not paused)
    var startDate: Date           // virtual start: now - startDate == elapsed while running
    var elapsed: TimeInterval     // frozen elapsed, used while paused
    var descriptionText: String
    var sessionTags: [WidgetTag]
    var lastSessionSeconds: TimeInterval?   // for the idle small widget's "Last: …"

    // Today's finished entries
    var todayTotals: [WidgetTagTotal]
    var todayTotalSeconds: TimeInterval
    var timeline: [WidgetTimelineItem]
    var dayStart: Date
    var updatedAt: Date

    static let empty = WidgetSnapshot(
        isTracking: false,
        isRunning: false,
        startDate: Date(),
        elapsed: 0,
        descriptionText: "",
        sessionTags: [],
        lastSessionSeconds: nil,
        todayTotals: [],
        todayTotalSeconds: 0,
        timeline: [],
        dayStart: Calendar.current.startOfDay(for: Date()),
        updatedAt: .distantPast
    )

    /// Live elapsed seconds for the current session as of `now`.
    func currentElapsed(asOf now: Date = Date()) -> TimeInterval {
        guard isTracking else { return 0 }
        return isRunning ? max(0, now.timeIntervalSince(startDate)) : elapsed
    }

    /// Returns a copy with an interactive action applied optimistically, so the
    /// widget reflects the tap immediately (the app reconciles the real tracker
    /// afterwards).
    func applying(_ kind: PendingWidgetAction.Kind, at now: Date) -> WidgetSnapshot {
        var s = self
        switch kind {
        case .start:
            s.isTracking = true
            s.isRunning = true
            s.startDate = now
            s.elapsed = 0
        case .pause:
            s.elapsed = currentElapsed(asOf: now)
            s.isRunning = false
            s.startDate = now
        case .resume:
            s.isRunning = true
            s.startDate = now.addingTimeInterval(-elapsed)
        case .stop:
            s.lastSessionSeconds = currentElapsed(asOf: now)
            s.isTracking = false
            s.isRunning = false
            s.elapsed = 0
        }
        return s
    }
}

// MARK: - Pending interactive action

/// An interactive button's request, recorded so the app can apply it to the real
/// tracker even if the tap woke only the widget process.
struct PendingWidgetAction: Codable, Hashable {
    enum Kind: String, Codable { case start, pause, resume, stop }
    var id: UUID
    var kind: Kind
    var date: Date
}

// MARK: - Store

enum WidgetSharedStore {
    private static let snapshotKey = "widget.snapshot"
    private static let pendingKey = "widget.pendingAction"
    private static let handledKey = "widget.lastHandledActionID"

    // Snapshot -------------------------------------------------------------

    static func loadSnapshot() -> WidgetSnapshot {
        guard let data = TaggdAppGroup.defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot) {
        var snapshot = snapshot
        snapshot.updatedAt = Date()
        if let data = try? JSONEncoder().encode(snapshot) {
            TaggdAppGroup.defaults.set(data, forKey: snapshotKey)
        }
    }

    /// Read-modify-write so callers can update just one slice (session vs. today).
    static func mutate(_ transform: (inout WidgetSnapshot) -> Void) {
        var snapshot = loadSnapshot()
        transform(&snapshot)
        save(snapshot)
    }

    // Pending action -------------------------------------------------------

    static func setPending(_ action: PendingWidgetAction) {
        if let data = try? JSONEncoder().encode(action) {
            TaggdAppGroup.defaults.set(data, forKey: pendingKey)
        }
    }

    static func pendingAction() -> PendingWidgetAction? {
        guard let data = TaggdAppGroup.defaults.data(forKey: pendingKey),
              let action = try? JSONDecoder().decode(PendingWidgetAction.self, from: data)
        else { return nil }
        return action
    }

    static func markHandled(_ id: UUID) {
        TaggdAppGroup.defaults.set(id.uuidString, forKey: handledKey)
    }

    static var lastHandledID: UUID? {
        TaggdAppGroup.defaults.string(forKey: handledKey).flatMap(UUID.init)
    }

    /// True when `action` hasn't yet been applied to the real tracker.
    static func isUnhandled(_ action: PendingWidgetAction) -> Bool {
        action.id != lastHandledID
    }
}
