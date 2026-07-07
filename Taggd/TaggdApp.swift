//
//  TaggdApp.swift
//  Taggd
//

import SwiftUI

@main
struct TaggdApp: App {
    @State private var tagStore = TagStore()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tagStore)
        }
    }
}
