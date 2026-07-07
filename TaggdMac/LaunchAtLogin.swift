//
//  LaunchAtLogin.swift
//  TaggdMac
//
//  Thin wrapper over SMAppService for the "Launch at Login" toggle. Registering
//  the main app as a login item is the modern (macOS 13+) replacement for the
//  old login-items API and needs no helper bundle.
//

import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Taggd: Launch-at-Login toggle failed: \(error.localizedDescription)")
        }
    }
}
