//
//  StatusBarController.swift
//  TaggdMac
//
//  Manages the NSStatusItem and the popover that hosts the SwiftUI timer UI.
//
//  The status-bar glyph comes from the "Taggd-White" SVG asset. That artwork is
//  550×551, which the status bar would render far too large, so it's redrawn
//  into a compact 18-pt template image (macOS then tints it for light/dark).
//

import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init<Content: View>(content: Content) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.imageScaling = .scaleProportionallyUpOrDown
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.setAccessibilityLabel("Tagged")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: content)
    }

    // MARK: - Icon

    /// Loads the template SVG and redraws it at status-bar size.
    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        guard let source = NSImage(named: "Taggd-White") else {
            // Fallback so the item is never invisible if the asset is missing.
            return NSImage(systemSymbolName: "timer", accessibilityDescription: "Tagged")
                ?? NSImage(size: size)
        }
        let resized = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        resized.isTemplate = true
        return resized
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Bring the popover to the front and give it key focus for text entry.
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() {
        popover.performClose(nil)
    }
}
