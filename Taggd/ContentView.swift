//
//  ContentView.swift
//  Taggd
//

import SwiftUI

struct ContentView: View {
    @Environment(TagStore.self) private var tagStore
    @State private var tracker = TimeTracker()
    @State private var showSettings = false
    @State private var showNewTag = false
    @State private var newTagName = ""
    @State private var showStopConfirm = false
    @State private var toast: ToastKind?
    @State private var toastTask: Task<Void, Never>?
    @AppStorage("confirmBeforeStop") private var confirmBeforeStop = false
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer(minLength: 8)

                    TimerDisplay(elapsed: tracker.elapsed, running: tracker.phase == .running)

                    Spacer(minLength: 8)

                    VStack(spacing: 16) {
                        descriptionField
                        tagSection
                    }

                    Spacer(minLength: 8)

                    controls
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("TAGGED")
                        .font(.mono(15, .bold))
                        .tracking(3)
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        descriptionFocused = false
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .tint(Theme.textPrimary)
                    .accessibilityLabel("Settings")
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(tagStore)
                .presentationDetents([.medium, .large])
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
        .overlay(alignment: .top) {
            if let toast {
                ToastView(kind: toast) {
                    tracker.retrySync()
                }
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .onChange(of: tracker.syncStatus) { _, status in
            switch status {
            case .synced: presentToast(.saved)
            case .failed: presentToast(.notSaved)
            case .syncing, .disabled: break
            }
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

    // MARK: - Description

    private var descriptionField: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.line")
                .foregroundStyle(Theme.textTertiary)
            TextField(
                "",
                text: $tracker.taskDescription,
                prompt: Text("What are you working on?")
                    .foregroundColor(Theme.textTertiary)
            )
            .font(.mono(16, .regular))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .focused($descriptionFocused)
            .submitLabel(.done)
            .onSubmit { descriptionFocused = false }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(cardBackground)
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TAGS")
                    .font(.mono(12, .medium))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                tagMenu
            }

            if tracker.selectedTags.isEmpty {
                Text("No tags yet — add one to categorize this session.")
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tracker.selectedTags) { tag in
                        TagChip(tag: tag) { tracker.removeTag(tag) }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var tagMenu: some View {
        // Read the library here (during body evaluation) so ContentView observes
        // tagStore.tags and rebuilds the menu whenever the library changes.
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
                    .font(.mono(13, .medium))
            }
            .foregroundStyle(Theme.accent)
        }
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
        // Persist to the library and select it for this session.
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
            HStack(spacing: 12) {
                SecondaryButton(title: "Pause", systemImage: "pause.fill", tint: Theme.accent) {
                    tracker.pause()
                }
                SecondaryButton(title: "Stop", systemImage: "stop.fill", tint: Theme.danger) {
                    requestStop()
                }
            }
        case .paused:
            HStack(spacing: 12) {
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

    // MARK: - Shared background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

// MARK: - Timer display

private struct TimerDisplay: View {
    let elapsed: TimeInterval
    let running: Bool

    var body: some View {
        let t = elapsed.hms
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            unit(t.h, "h")
            unit(t.m, "m")
            unit(t.s, "s")
        }
        .foregroundStyle(running ? Theme.accent : Theme.textPrimary)
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.2), value: t.s)
        .animation(.default, value: running)
        .accessibilityLabel("\(t.h) hours \(t.m) minutes \(t.s) seconds")
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(String(format: "%02d", value))
                .font(.mono(52, .medium))
            Text(label)
                .font(.mono(22, .regular))
                .foregroundStyle(running ? Theme.accent.opacity(0.65) : Theme.textTertiary)
        }
    }
}

// MARK: - Sync toast

enum ToastKind: Equatable {
    case saved, notSaved
}

private struct ToastView: View {
    let kind: ToastKind
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind == .saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(kind == .saved ? Color.green : Theme.danger)
            Text(kind == .saved ? "Saved" : "Not saved")
                .font(.mono(14, .medium))
                .foregroundStyle(Theme.textPrimary)
            if kind == .notSaved {
                Divider().frame(height: 16).overlay(Theme.stroke)
                Button("Retry", action: onRetry)
                    .font(.mono(13, .semiBold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
    }
}

// MARK: - Tag chip

private struct TagChip: View {
    let tag: Tag
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(tag.name)
                    .font(.mono(14, .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove tag \(tag.name)")
    }
}

// MARK: - Buttons

private struct PrimaryButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.mono(18, .semiBold))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .foregroundStyle(Color.black)
    }
}

private struct SecondaryButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.mono(18, .semiBold))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .foregroundStyle(tint)
        }
        .buttonStyle(.glass)
        .tint(tint)
    }
}

#Preview {
    ContentView()
        .environment(TagStore())
}
