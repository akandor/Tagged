//
//  UnsyncedSessionsView.swift
//  Taggd
//
//  Sessions saved offline because the server was unreachable. Retry them here.
//

import SwiftUI

struct UnsyncedSessionsView: View {
    @Environment(OfflineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var retryingAll = false

    var body: some View {
        NavigationStack {
            List {
                if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "All Synced",
                        systemImage: "checkmark.icloud",
                        description: Text("No sessions are waiting to be uploaded.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session, isRetrying: store.retrying.contains(session.id)) {
                                Task { await store.retry(session) }
                            }
                        }
                        .onDelete { store.remove(at: $0) }
                    } footer: {
                        Text("These sessions are stored on your device and will not sync automatically. Tap a session — or Retry All — to upload it to your server.")
                            .font(.mono(11, .regular))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Unsynced")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.mono(15, .semiBold))
                        .tint(Theme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        retryingAll = true
                        Task {
                            _ = await store.retryAll()
                            retryingAll = false
                        }
                    } label: {
                        if retryingAll {
                            ProgressView().tint(Theme.accent)
                        } else {
                            Text("Retry All").font(.mono(15, .semiBold))
                        }
                    }
                    .tint(Theme.accent)
                    .disabled(store.sessions.isEmpty || retryingAll)
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

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
                    ProgressView().tint(Theme.accent)
                } else {
                    Image(systemName: "arrow.clockwise.icloud")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
        }
        .padding(.vertical, 4)
    }

    private var durationText: String {
        let total = session.totalSeconds
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm %02ds", m, s)
    }
}
