//
//  SettingsView.swift
//  Taggd
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(TagStore.self) private var tagStore

    private let githubURL = URL(string: "https://github.com/akandor/Tagged")!
    private let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/toepper.rocks")!

    @AppStorage("keepScreenAwake") private var keepScreenAwake = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("confirmBeforeStop") private var confirmBeforeStop = false

    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("apiToken") private var apiToken = ""

    @State private var revealToken = false
    @State private var connection: ConnectionState = .idle

    private enum ConnectionState: Equatable {
        case idle, testing, ok, unauthorized, invalidURL, error(String)
    }

    var body: some View {
        NavigationStack {
            List {
                serverSection

                Section("Timer") {
                    Toggle(isOn: $keepScreenAwake) {
                        settingLabel("Keep Screen Awake", "sun.max")
                    }
                    Toggle(isOn: $confirmBeforeStop) {
                        settingLabel("Confirm Before Stop", "hand.raised")
                    }
                }

                Section("Feedback") {
                    Toggle(isOn: $hapticsEnabled) {
                        settingLabel("Haptic Feedback", "waveform")
                    }
                }

                Section("Tags") {
                    NavigationLink {
                        TagManagerView()
                    } label: {
                        HStack {
                            settingLabel("Manage Tags", "tag")
                            Spacer()
                            Text("\(tagStore.tags.count)")
                                .font(.mono(13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                supportSection

                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.mono(15, .semiBold))
                        .tint(Theme.accent)
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    // MARK: - Server

    private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                settingLabel("Server URL", "server.rack")
                TextField(
                    "",
                    text: $serverURL,
                    prompt: Text("Enter your server address")
                        .foregroundColor(Theme.textTertiary)
                )
                    .font(.mono(14, .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onChange(of: serverURL) { connection = .idle }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
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
                    .font(.mono(14, .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .textInputAutocapitalization(.never)
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
            }
            .padding(.vertical, 2)

            Button(action: runTest) {
                HStack {
                    settingLabel("Test Connection", "antenna.radiowaves.left.and.right")
                    Spacer()
                    connectionStatus
                }
            }
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
            ProgressView().tint(Theme.accent)
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.mono(13, .medium))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .unauthorized:
            Label("Invalid token", systemImage: "xmark.circle.fill")
                .font(.mono(13, .medium))
                .foregroundStyle(Theme.danger)
                .labelStyle(.titleAndIcon)
        case .invalidURL:
            Label("Invalid URL", systemImage: "xmark.circle.fill")
                .font(.mono(13, .medium))
                .foregroundStyle(Theme.danger)
                .labelStyle(.titleAndIcon)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.mono(12, .regular))
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

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                settingLabel("Version", "info.circle")
                Spacer()
                Text(appVersion)
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                requestReview()
            } label: {
                settingLabel("Rate This App", "star")
            }

            ShareLink(item: githubURL) {
                settingLabel("Share This App", "square.and.arrow.up")
            }

            Link(destination: githubURL) {
                HStack {
                    settingLabel("GitHub", asset: "GitHubMark")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
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

    // MARK: - Support

    private var supportSection: some View {
        Section {
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
                        .frame(height: 46)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Buy me a coffee")
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
        } header: {
            Text("Support")
        }
    }

    private func settingLabel(_ title: LocalizedStringKey, _ icon: String) -> some View {
        Label {
            Text(title)
                .font(.mono(15, .regular))
                .foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
        }
    }

    /// Row label variant that uses an asset image (e.g. the GitHub mark) as the icon.
    private func settingLabel(_ title: LocalizedStringKey, asset: String) -> some View {
        Label {
            Text(title)
                .font(.mono(15, .regular))
                .foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .foregroundStyle(Theme.accent)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

#Preview {
    SettingsView()
        .environment(TagStore())
}
