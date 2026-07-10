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
    private var entriesWindow: NSWindow?
    private var tagManagerWindow: NSWindow?
    private var unsyncedWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as an accessory: status bar only, no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)

        statusController = StatusBarController(
            content: MenuBarRootView(
                onOpenSettings: { [weak self] in self?.showSettings() },
                onOpenEntries: { [weak self] in self?.showEntries() },
                onOpenUnsynced: { [weak self] in self?.showUnsynced() }
            )
                .environment(AppModel.shared.tracker)
                .environment(AppModel.shared.tagStore)
                .environment(OfflineStore.shared)
        )

        // Apply anything tapped on a widget while the app was closed, then seed the
        // widgets with the current session + today's overview.
        AppModel.shared.tracker.applyPendingWidgetAction()
        Task { await WidgetBridge.refreshToday() }
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
            present(window)
            return
        }

        let root = MacSettingsView(onManageTags: { [weak self] in self?.showTagManager() })
            .environment(AppModel.shared.tracker)
            .environment(AppModel.shared.tagStore)
            .environmentObject(updater)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Let the dark content run up under the native titlebar so it reads as
        // one surface rather than content below a system-gray bar.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.background)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 720))
        window.contentMinSize = NSSize(width: 640, height: 600)
        window.center()
        window.delegate = self

        settingsWindow = window
        present(window)
    }

    // MARK: - Tag manager window

    /// Shows the tag library in its own window so the standard traffic-light
    /// controls handle closing it.
    func showTagManager() {
        if let window = tagManagerWindow {
            present(window)
            return
        }

        let root = MacTagManagerView()
            .environment(AppModel.shared.tagStore)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Tags"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.background)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 620))
        window.contentMinSize = NSSize(width: 420, height: 480)
        window.center()
        window.delegate = self

        tagManagerWindow = window
        present(window)
    }

    // MARK: - Unsynced sessions window

    /// Shows sessions saved offline in their own window so the standard
    /// traffic-light controls handle closing it.
    func showUnsynced() {
        statusController.closePopover()

        if let window = unsyncedWindow {
            present(window)
            return
        }

        let root = MacUnsyncedSessionsView()
            .environment(OfflineStore.shared)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Unsynced"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.background)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 560))
        window.contentMinSize = NSSize(width: 420, height: 420)
        window.center()
        window.delegate = self

        unsyncedWindow = window
        present(window)
    }

    // MARK: - Entries window

    /// Shows the Time Entries window, promoting the app to a regular (Dock-visible)
    /// app for as long as a window is open.
    func showEntries() {
        statusController.closePopover()

        if let window = entriesWindow {
            present(window)
            return
        }

        let root = MacEntriesView(onClose: { [weak self] in self?.entriesWindow?.close() })
            .environment(AppModel.shared.tracker)
            .environment(AppModel.shared.tagStore)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Time Entries"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.background)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 720))
        window.contentMinSize = NSSize(width: 560, height: 600)
        window.center()
        window.delegate = self

        entriesWindow = window
        present(window)
    }

    /// Promotes the accessory app to a regular (Dock-visible) app and brings the
    /// window fully to the front with focus. Ordering matters: the window must be
    /// ordered front *after* the policy change and *before* activation, or it can
    /// open behind other apps.
    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }
}

// MARK: - Window lifecycle

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              closing === settingsWindow || closing === entriesWindow
                || closing === tagManagerWindow || closing === unsyncedWindow else { return }
        // Drop back to a status-bar-only accessory once no managed window remains
        // open (the closing one is still counted as visible at this point).
        let others = [settingsWindow, entriesWindow, tagManagerWindow, unsyncedWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if others.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
