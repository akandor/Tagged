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
final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// Sparkle disables checking briefly while an update session is already in
    /// flight; we mirror that so the menu item can disable itself.
    @Published var canCheckForUpdates = false

    /// Set while Sparkle is quitting the app to install and relaunch an update.
    /// The AppDelegate reads this to skip the quit confirmation for that
    /// programmatic termination.
    private(set) var isRelaunchingForUpdate = false

    // Implicitly-unwrapped so we can pass `self` as the delegate: the controller
    // must be created after `super.init()`.
    private(set) var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        // `startingUpdater: true` begins the background scheduler immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    /// Sparkle calls this on the main thread just before it terminates the app
    /// to install an update and relaunch.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            isRelaunchingForUpdate = true
        }
    }
}
