//
//  MacSettingsView.swift
//  TaggdMac
//
//  Settings shown in a standalone window (which is what brings up the Dock
//  icon). Ported from the iOS SettingsView with macOS-native chrome and an
//  Updates section wired to Sparkle. iOS-only rows (haptics, keep-screen-awake,
//  App Store review) are dropped; Launch-at-Login and Quit are added.
//
//  Navigation into the tag manager uses an explicit route rather than
//  NavigationStack: a plain NSWindow-hosted NavigationStack doesn't render a
//  reliable back button, so we drive a simple two-screen switch and draw our
//  own back / done controls in a header bar that matches the dark theme.
//

import SwiftUI
import AppKit

struct MacSettingsView: View {
    @Environment(TagStore.self) private var tagStore
    @EnvironmentObject private var updater: UpdaterViewModel

    let onClose: () -> Void

    private enum Route { case settings, tags }
    @State private var route: Route = .settings

    private let githubURL = URL(string: "https://github.com/akandor/Tagged")!
    private let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/toepper.rocks")!

    @AppStorage("confirmBeforeStop") private var confirmBeforeStop = false
    @AppStorage("automaticallyChecksForUpdates") private var autoUpdates = true

    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("apiToken") private var apiToken = ""

    @State private var revealToken = false
    @State private var connection: ConnectionState = .idle
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private enum ConnectionState: Equatable {
        case idle, testing, ok, unauthorized, invalidURL, error(String)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch route {
            case .settings:
                settingsScreen
                    .transition(.opacity)
            case .tags:
                MacTagManagerView(onBack: { withAnimation(.snappy) { route = .settings } })
                    .environment(tagStore)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: autoUpdates) { _, newValue in
            updater.controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    // MARK: - Settings screen

    private var settingsScreen: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Settings") {
                Button("Done", action: onClose)
                    .font(.mono(14, .semiBold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
            Form {
                serverSection
                timerSection
                tagsSection
                updatesSection
                supportSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .overlayScrollbars()
        }
    }

    // MARK: - Server

    private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                settingLabel("Server URL", "server.rack")
                TextField(
                    "",
                    text: $serverURL,
                    prompt: Text("Enter your server address")
                        .foregroundColor(Theme.textTertiary)
                )
                .font(.mono(13, .regular))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .autocorrectionDisabled()
                .onChange(of: serverURL) { connection = .idle }
                .themedField()
            }
            .listRowSeparator(.hidden)

            VStack(alignment: .leading, spacing: 8) {
                settingLabel("API Token", "key")
                HStack(spacing: 8) {
                    Group {
                        let prompt = Text("Paste your TimeTagger API token")
                            .foregroundColor(Theme.textTertiary)
                        if revealToken {
                            TextField("", text: $apiToken, prompt: prompt)
                        } else {
                            SecureField("", text: $apiToken, prompt: prompt)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .autocorrectionDisabled()
                    .onChange(of: apiToken) { connection = .idle }

                    Button {
                        revealToken.toggle()
                    } label: {
                        Image(systemName: revealToken ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(FieldBackground())
            }
            .listRowSeparator(.hidden)

            Button(action: runTest) {
                HStack {
                    settingLabel("Test Connection", "antenna.radiowaves.left.and.right")
                    Spacer()
                    connectionStatus
                }
            }
            .buttonStyle(.plain)
            .disabled(serverURL.isEmpty || apiToken.isEmpty || connection == .testing)
        } header: {
            Text("Server")
        } footer: {
            Text("Sync with a self-hosted TimeTagger backend, e.g. https://timetagger.example.com. Create an API token in TimeTagger under Account → API token.")
                .font(.mono(11, .regular))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch connection {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small).tint(Theme.accent)
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.mono(12, .medium))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .unauthorized:
            Label("Invalid token", systemImage: "xmark.circle.fill")
                .font(.mono(12, .medium))
                .foregroundStyle(Theme.danger)
                .labelStyle(.titleAndIcon)
        case .invalidURL:
            Label("Invalid URL", systemImage: "xmark.circle.fill")
                .font(.mono(12, .medium))
                .foregroundStyle(Theme.danger)
                .labelStyle(.titleAndIcon)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.mono(11, .regular))
                .foregroundStyle(Theme.danger)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
    }

    private func runTest() {
        connection = .testing
        let client = TimeTaggerClient(serverURL: serverURL, token: apiToken)
        Task {
            let result = await client.testConnection()
            await MainActor.run {
                switch result {
                case .success:      connection = .ok
                case .unauthorized: connection = .unauthorized
                case .badURL:       connection = .invalidURL
                case .failure(let message): connection = .error(message)
                }
            }
        }
    }

    // MARK: - Timer

    private var timerSection: some View {
        Section("Timer") {
            Toggle(isOn: $confirmBeforeStop) {
                settingLabel("Confirm Before Stop", "hand.raised")
            }
            .tint(Theme.accent)
            Toggle(isOn: $launchAtLogin) {
                settingLabel("Launch at Login", "power")
            }
            .tint(Theme.accent)
            .onChange(of: launchAtLogin) { _, on in
                LaunchAtLogin.setEnabled(on)
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section("Tags") {
            Button {
                withAnimation(.snappy) { route = .tags }
            } label: {
                HStack {
                    settingLabel("Manage Tags", "tag")
                    Spacer()
                    Text("\(tagStore.tags.count)")
                        .font(.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        Section {
            Button {
                updater.checkForUpdates()
            } label: {
                settingLabel("Check for Updates…", "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
            .disabled(!updater.canCheckForUpdates)

            Toggle(isOn: $autoUpdates) {
                settingLabel("Automatically Check for Updates", "clock.arrow.circlepath")
            }
            .tint(Theme.accent)
        } header: {
            Text("Updates")
        } footer: {
            Text("Updates are delivered from GitHub Releases, verified with a signature. The app is not distributed through the Mac App Store.")
                .font(.mono(11, .regular))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        Section("Support") {
            VStack(spacing: 12) {
                Text("Enjoying Tagged? Fuel the next update.")
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Link(destination: buyMeACoffeeURL) {
                    Image("Buy Me a Coffee")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Buy me a coffee")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                settingLabel("Version", "info.circle")
                Spacer()
                Text(appVersion)
                    .font(.mono(12, .regular))
                    .foregroundStyle(Theme.textSecondary)
            }

            Link(destination: githubURL) {
                HStack {
                    settingLabel("GitHub", asset: "GitHubMark")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label {
                    Text("Quit Tagged")
                        .font(.mono(14, .regular))
                        .foregroundStyle(Theme.danger)
                        .offset(x: 5)
                } icon: {
                    Image(systemName: "power")
                        .foregroundStyle(Theme.danger)
                        .font(.mono(18, .regular))
                        .offset(x: 2)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("About")
        } footer: {
            Text(verbatim: "© \(currentYear) Toepper.Rocks")
                .font(.mono(11, .regular))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
        }
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    // MARK: - Row labels

    private func settingLabel(_ title: LocalizedStringKey, _ icon: String) -> some View {
        Label {
            Text(title)
                .font(.mono(14, .regular))
                .foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .font(.mono(18, .regular))
        }
    }

    private func settingLabel(_ title: LocalizedStringKey, asset: String) -> some View {
        Label {
            Text(title)
                .font(.mono(14, .regular))
                .foregroundStyle(Theme.textPrimary)
                .offset(x: 6)
        } icon: {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .foregroundStyle(Theme.accent)
                .offset(x: 3)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Header bar

/// A slim title bar drawn in-content (below the window's traffic lights) so the
/// Settings and Tags screens get consistent dark-themed navigation controls.
struct HeaderBar<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading?
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, leading: Leading?, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.mono(16, .semiBold))
                .foregroundStyle(Theme.textPrimary)
            HStack {
                if let leading { leading }
                Spacer()
                trailing()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }
}

extension HeaderBar where Leading == EmptyView {
    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, leading: nil, trailing: trailing)
    }
}
