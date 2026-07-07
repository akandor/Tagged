//
//  UpdaterViewModel.swift
//  TaggdMac
//
//  Wraps Sparkle's standard updater so SwiftUI can drive "Check for Updates…".
//  The app is distributed outside the Mac App Store; updates are delivered from
//  the GitHub Releases appcast configured via SUFeedURL / SUPublicEDKey in the
//  Info.plist.
//

import SwiftUI
import Combine
import Sparkle

@MainActor
final class UpdaterViewModel: ObservableObject {
    /// Sparkle disables checking briefly while an update session is already in
    /// flight; we mirror that so the menu item can disable itself.
    @Published var canCheckForUpdates = false

    let controller: SPUStandardUpdaterController

    init() {
        // `startingUpdater: true` begins the background scheduler immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
