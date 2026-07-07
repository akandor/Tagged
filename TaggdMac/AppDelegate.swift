//
//  AppDelegate.swift
//  TaggdMac
//
//  Owns the app-wide AppKit objects: the status-bar controller, the Sparkle
//  updater, and the Settings window. Also flips the activation policy so the
//  Dock icon appears only while Settings is open.
//

import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updater = UpdaterViewModel()

    private var statusController: StatusBarController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as an accessory: status bar only, no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)

        statusController = StatusBarController(
            content: MenuBarRootView(onOpenSettings: { [weak self] in self?.showSettings() })
                .environment(AppModel.shared.tracker)
                .environment(AppModel.shared.tagStore)
        )
    }

    // MARK: - Quit confirmation

    /// Every quit path (the popover power button, the Settings "Quit" button,
    /// and ⌘Q) routes through here, so a single confirmation covers them all.
    /// Sparkle's install-and-relaunch also terminates the app; that case is
    /// waved through so updates aren't interrupted.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if updater.isRelaunchingForUpdate { return .terminateNow }

        statusController?.closePopover()

        let alert = NSAlert()
        alert.messageText = "Quit Tagged?"
        alert.informativeText = AppModel.shared.tracker.phase == .idle
            ? "Are you sure you want to quit?"
            : "A timer is currently running. Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        // The app can be a status-bar accessory with no key window, so bring the
        // alert to the front explicitly.
        NSApp.activate(ignoringOtherApps: true)

        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    // MARK: - Settings window

    /// Shows the Settings window, promoting the app to a regular (Dock-visible)
    /// app for as long as the window is open.
    func showSettings() {
        statusController.closePopover()

        if let window = settingsWindow {
            promoteToRegular()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = MacSettingsView(onClose: { [weak self] in self?.settingsWindow?.close() })
            .environment(AppModel.shared.tracker)
            .environment(AppModel.shared.tagStore)
            .environmentObject(updater)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Tagged Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 720))
        window.contentMinSize = NSSize(width: 640, height: 600)
        window.center()
        window.delegate = self

        settingsWindow = window
        promoteToRegular()
        window.makeKeyAndOrderFront(nil)
    }

    private func promoteToRegular() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings window lifecycle

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        // Back to a status-bar-only accessory: the Dock icon disappears again.
        NSApp.setActivationPolicy(.accessory)
    }
}
