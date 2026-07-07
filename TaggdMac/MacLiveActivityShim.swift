//
//  MacLiveActivityShim.swift
//  TaggdMac
//
//  macOS has no ActivityKit / Live Activities. `TimeTracker` (shared with iOS)
//  calls `LiveActivityController.shared` unconditionally, so this stub provides
//  the same interface as no-ops, letting the shared file compile untouched.
//

import Foundation

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    func start(elapsed: TimeInterval, description: String, tags: [String]) {}
    func update(isRunning: Bool, elapsed: TimeInterval, description: String, tags: [String]) {}
    func end() {}
}
