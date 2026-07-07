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

    let tracker = TimeTracker()
    let tagStore = TagStore()

    private init() {}
}
