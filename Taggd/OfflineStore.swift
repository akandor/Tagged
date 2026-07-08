//
//  OfflineStore.swift
//  Taggd
//
//  Sessions that couldn't reach the server are stored here (persisted to disk)
//  so they survive relaunches and can be retried later.
//

import Foundation
import Observation

struct UnsyncedSession: Identifiable, Codable {
    var id = UUID()
    var stoppedAt: Date
    var descriptionText: String
    var tags: [String]
    var records: [TimeTaggerClient.Record]

    /// Total tracked seconds across the session's segments.
    var totalSeconds: Int {
        records.reduce(0) { $0 + max(0, $1.t2 - $1.t1) }
    }

    var title: String {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        if let first = tags.first { return "#\(first)" }
        return "Untitled session"
    }
}

@Observable
@MainActor
final class OfflineStore {
    static let shared = OfflineStore()
    private static let storageKey = "unsyncedSessions"

    private(set) var sessions: [UnsyncedSession]
    /// IDs currently being retried (drives per-row spinners).
    private(set) var retrying: Set<UUID> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([UnsyncedSession].self, from: data) {
            sessions = decoded
        } else {
            sessions = []
        }
    }

    var hasSessions: Bool { !sessions.isEmpty }

    func add(_ session: UnsyncedSession) {
        sessions.append(session)
        save()
    }

    func remove(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        retrying.remove(id)
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where sessions.indices.contains(index) {
            sessions.remove(at: index)
        }
        save()
    }

    /// Attempts to upload one session. Returns true on success (and removes it).
    @discardableResult
    func retry(_ session: UnsyncedSession) async -> Bool {
        guard !retrying.contains(session.id),
              let client = TimeTaggerClient.fromStoredSettings() else { return false }
        retrying.insert(session.id)
        defer { retrying.remove(session.id) }

        if case .success = await client.pushRecords(session.records) {
            remove(session.id)
            return true
        }
        return false
    }

    /// Retries every stored session. Returns true if the store ends up empty.
    @discardableResult
    func retryAll() async -> Bool {
        for session in sessions {
            _ = await retry(session)
        }
        return sessions.isEmpty
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
