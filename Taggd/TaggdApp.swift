//
//  TaggdApp.swift
//  Taggd
//

import SwiftUI

@main
struct TaggdApp: App {
    @State private var tagStore = TagStore()
    @State private var offlineStore = OfflineStore.shared

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tagStore)
                .environment(offlineStore)
        }
    }
}
