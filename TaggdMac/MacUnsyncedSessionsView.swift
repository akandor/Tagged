//
//  MacUnsyncedSessionsView.swift
//  TaggdMac
//
//  Sessions saved offline because the server was unreachable. Hosted in its own
//  window (opened from the cloud button in the menu-bar popover). Mirrors the iOS
//  UnsyncedSessionsView: a grouped table of pending sessions with per-row retry,
//  Retry All, and delete. Standard traffic-light controls close the window.
//

import SwiftUI

struct MacUnsyncedSessionsView: View {
    @Environment(OfflineStore.self) private var store
    @State private var retryingAll = false

    var body: some View {
        Group {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "All Synced",
                    systemImage: "checkmark.icloud",
                    description: Text("No sessions are waiting to be uploaded.")
                )
            } else {
                Form {
                    Section {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session, isRetrying: store.retrying.contains(session.id)) {
                                Task { await store.retry(session) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.remove(session.id) }
                            }
                        }
                    } footer: {
                        Text("These sessions are stored on this Mac and will not sync automatically. Click a session — or Retry All — to upload it to your server.")
                            .font(.mono(11, .regular))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .overlayScrollbars()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .overlay(alignment: .bottomTrailing) {
            if !store.sessions.isEmpty { retryAllButton }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    /// A big round "Retry All" button, matching the entries window's add button.
    private var retryAllButton: some View {
        RoundActionButton(
            systemImage: "arrow.trianglehead.clockwise.icloud",
            isBusy: retryingAll,
            help: "Retry All",
            action: retryAll
        )
    }

    private func retryAll() {
        guard !retryingAll else { return }
        retryingAll = true
        Task {
            _ = await store.retryAll()
            retryingAll = false
        }
    }
}

/// A single unsynced session: title, duration + timestamp, tags, and a retry
/// button. Matches the iOS SessionRow layout.
private struct SessionRow: View {
    let session: UnsyncedSession
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.mono(15, .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(durationText)
                        .foregroundStyle(Theme.accent)
                    Text(session.stoppedAt, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.mono(12, .regular))
                if !session.tags.isEmpty {
                    Text(session.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.mono(12, .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onRetry) {
                if isRetrying {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                } else {
                    Image(systemName: "arrow.clockwise.icloud")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            .help("Retry")
        }
        .padding(.vertical, 4)
    }

    private var durationText: String {
        let total = session.totalSeconds
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm %02ds", m, s)
    }
}
