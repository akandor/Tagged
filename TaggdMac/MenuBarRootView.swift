//
//  MenuBarRootView.swift
//  TaggdMac
//
//  The content shown in the status-bar popover: timer, description, tags and
//  the start/stop/pause/resume controls. Ported from the iOS ContentView with
//  macOS-appropriate chrome (a plain header row instead of a navigation bar).
//

import SwiftUI
import AppKit

struct MenuBarRootView: View {
    @Environment(TagStore.self) private var tagStore
    @Environment(TimeTracker.self) private var tracker
    @Environment(OfflineStore.self) private var offlineStore

    /// Opens the standalone Settings window (and shows the Dock icon).
    let onOpenSettings: () -> Void
    /// Opens the standalone Time Entries window.
    let onOpenEntries: () -> Void
    /// Opens the standalone Unsynced sessions window.
    let onOpenUnsynced: () -> Void

    @State private var showNewTag = false
    @State private var newTagName = ""
    @State private var showStopConfirm = false
    @State private var toast: ToastKind?
    @State private var toastTask: Task<Void, Never>?
    @AppStorage("confirmBeforeStop") private var confirmBeforeStop = false
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("apiToken") private var apiToken = ""
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        ZStack {
            Theme.background

            VStack(spacing: 20) {
                header

                TimerDisplay(elapsed: tracker.elapsed, running: tracker.phase == .running)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                VStack(spacing: 12) {
                    descriptionField
                    tagSection
                }
                .padding(.bottom, 18)

                controls
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(width: 340)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let toast {
                ToastView(kind: toast) { tracker.retrySync() }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .alert("New Tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagName = "" }
        } message: {
            Text("Create a custom tag for this session.")
        }
        .alert("Stop this session?", isPresented: $showStopConfirm) {
            Button("Keep going", role: .cancel) { }
            Button("Stop", role: .destructive) { tracker.stop() }
        } message: {
            Text("The current time will be saved and the timer reset.")
        }
        .onChange(of: tracker.syncStatus) { _, status in
            switch status {
            case .synced: presentToast(.saved)
            case .failed: presentToast(.notSaved)
            case .syncing, .disabled: break
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("TAGGED")
                .font(.mono(14, .bold))
                .tracking(3)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 14) {
                if offlineStore.hasSessions {
                    Button {
                        descriptionFocused = false
                        onOpenUnsynced()
                    } label: {
                        Image(systemName: "exclamationmark.icloud.fill")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("^[\(offlineStore.sessions.count) session](inflect: true) not synced")
                    .accessibilityLabel("Unsynced sessions")
                }

                if serverConfigured {
                    Button {
                        descriptionFocused = false
                        onOpenEntries()
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Time entries")
                    .accessibilityLabel("Time entries")
                }

                Button {
                    descriptionFocused = false
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .help("Quit Tagged")
                .accessibilityLabel("Quit Tagged")
            }
        }
    }

    /// Whether a server URL + token are set, gating the entries button.
    private var serverConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Description

    private var descriptionField: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.line")
                .foregroundStyle(Theme.textTertiary)
            TextField(
                "",
                text: Binding(
                    get: { tracker.taskDescription },
                    set: { tracker.taskDescription = $0 }
                ),
                prompt: Text("What are you working on?")
                    .foregroundColor(Theme.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(.mono(15, .regular))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .focused($descriptionFocused)
            .onSubmit { descriptionFocused = false }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(CardBackground())
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TAGS")
                    .font(.mono(11, .medium))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                tagMenu
            }

            if tracker.selectedTags.isEmpty {
                Text("No tags yet — add one to categorize this session.")
                    .font(.mono(12, .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tracker.selectedTags) { tag in
                        TagChip(tag: tag) { tracker.removeTag(tag) }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private var tagMenu: some View {
        let available = availableTags()
        return Menu {
            if !available.isEmpty {
                ForEach(available) { tag in
                    Button(tag.name) { withAnimation(.snappy) { tracker.addTag(tag) } }
                }
                Divider()
            }
            Button {
                showNewTag = true
            } label: {
                Label("New Tag…", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                Text("Add")
                    .font(.mono(12, .medium))
            }
            .foregroundStyle(Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Library tags not already selected for this session.
    private func availableTags() -> [Tag] {
        let taken = Set(tracker.selectedTags.map { $0.name.lowercased() })
        return tagStore.tags.filter { !taken.contains($0.name.lowercased()) }
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !trimmed.isEmpty else { return }
        if let tag = tagStore.add(trimmed) {
            withAnimation(.snappy) { tracker.addTag(tag) }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch tracker.phase {
        case .idle:
            PrimaryButton(title: "Start", systemImage: "play.fill") {
                descriptionFocused = false
                tracker.start()
            }
        case .running:
            HStack(spacing: 10) {
                SecondaryButton(title: "Pause", systemImage: "pause.fill", tint: Theme.accent) {
                    tracker.pause()
                }
                SecondaryButton(title: "Stop", systemImage: "stop.fill", tint: Theme.danger) {
                    requestStop()
                }
            }
        case .paused:
            HStack(spacing: 10) {
                PrimaryButton(title: "Resume", systemImage: "play.fill") {
                    tracker.resume()
                }
                SecondaryButton(title: "Stop", systemImage: "stop.fill", tint: Theme.danger) {
                    requestStop()
                }
            }
        }
    }

    private func requestStop() {
        descriptionFocused = false
        if confirmBeforeStop {
            showStopConfirm = true
        } else {
            tracker.stop()
        }
    }

    private func presentToast(_ kind: ToastKind) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.35)) { toast = kind }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(kind == .saved ? 2.5 : 5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { toast = nil }
        }
    }
}
