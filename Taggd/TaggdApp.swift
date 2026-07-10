//
//  TaggdApp.swift
//  Taggd
//

import SwiftUI

@main
struct TaggdApp: App {
    @State private var tagStore = TagStore()
    @State private var offlineStore = OfflineStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tagStore)
                .environment(offlineStore)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Apply anything the user tapped on a widget while we were away, then
            // refresh the day's overview so the widgets show current data.
            TimeTracker.shared.applyPendingWidgetAction()
            Task { await WidgetBridge.refreshToday() }
        }
    }
}
