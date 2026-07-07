//
//  TaggdMacApp.swift
//  TaggdMac
//
//  Menu-bar (status bar) time tracker. The app runs as an accessory (no Dock
//  icon) and lives entirely in the status bar; opening Settings promotes it to
//  a regular app so the Settings window gets a Dock icon. All of the AppKit
//  wiring — status item, popover, settings window — lives in AppDelegate.
//

import SwiftUI

@main
struct TaggdMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        // The UI is driven from AppKit (status-bar popover + settings window).
        // An agent app has no visible app menu, so this empty Settings scene is
        // just an inert placeholder to satisfy the `App` protocol.
        Settings { EmptyView() }
    }
}
