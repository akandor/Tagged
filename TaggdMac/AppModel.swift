//
//  AppModel.swift
//  TaggdMac
//
//  Holds the single, long-lived instances shared by every window and the
//  status-bar popover. The popover view is rebuilt each time it opens, so the
//  tracker and tag library must live here, above it, to survive.
//

import SwiftUI

@MainActor
final class AppModel {
    static let shared = AppModel()

    // Use the shared tracker so widget/Shortcuts intents (which reach
    // `TimeTracker.shared`) drive the very same session the menu bar shows.
    let tracker = TimeTracker.shared
    let tagStore = TagStore()

    private init() {}
}
