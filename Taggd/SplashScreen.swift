//
//  SplashScreen.swift
//  Taggd
//
//  Brief branded splash shown over the main screen at launch, then fades out.
//

import SwiftUI

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeInOut(duration: 0.45)) {
                showSplash = false
            }
        }
    }
}

private struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Image("Taggd-Colored")
                .resizable()
                .scaledToFit()
                .frame(width: 140)
                .foregroundStyle(Theme.accent)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(duration: 0.6)) { appeared = true }
        }
    }
}
