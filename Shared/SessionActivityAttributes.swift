//
//  SessionActivityAttributes.swift
//  Taggd — shared between the app and the widget extension.
//
//  Defines the Live Activity's static attributes and its dynamic content state.
//

import Foundation
import ActivityKit

struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Whether the session is currently running (vs. paused).
        var isRunning: Bool
        /// A virtual start instant such that `Date.now - startDate == elapsed`.
        /// Used to render a self-updating timer while running.
        var startDate: Date
        /// Frozen elapsed seconds, shown while paused.
        var elapsed: TimeInterval
        /// The session description (may be empty).
        var descriptionText: String
        /// Selected tag names (without the leading `#`).
        var tags: [String]
    }

    /// Static label for the activity.
    var sessionName: String
}
