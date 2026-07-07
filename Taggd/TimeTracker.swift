//
//  TimeTracker.swift
//  Taggd
//
//  Observable stopwatch driving the main screen.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class TimeTracker {
    enum Phase {
        case idle, running, paused
    }

    enum SyncStatus: Equatable {
        case disabled          // no server configured
        case syncing
        case synced
        case failed(String)
    }

    var phase: Phase = .idle
    var taskDescription: String = ""
    var selectedTags: [Tag] = []
    private(set) var syncStatus: SyncStatus = .disabled

    /// Elapsed seconds shown on screen. Updated on a tick while running.
    private(set) var elapsed: TimeInterval = 0

    private var accumulated: TimeInterval = 0
    private var startDate: Date?
    @ObservationIgnored private var timer: Timer?

    /// Active work segments in the current session (unix seconds). The app owns the
    /// running clock; nothing is written to the server until the session is stopped.
    @ObservationIgnored private var segments: [(start: Int, end: Int)] = []
    @ObservationIgnored private var currentSegmentStart: Int = 0

    /// Finished records that still need to reach the server (kept across failures so a
    /// dropped connection never loses a session; retryable via `retrySync()`).
    @ObservationIgnored private var pendingRecords: [TimeTaggerClient.Record] = []

    // MARK: - Controls

    func start() {
        guard phase != .running else { return }
        startDate = Date()
        currentSegmentStart = Int(startDate!.timeIntervalSince1970)
        segments = []
        // Clear a "saved" badge for the new session, but keep an unresolved failure visible.
        if pendingRecords.isEmpty { syncStatus = .disabled }
        phase = .running
        startTicking()
        LiveActivityController.shared.start(elapsed: 0, description: taskDescription, tags: tagNames)
    }

    func pause() {
        guard phase == .running else { return }
        accumulated += intervalSinceStart()
        closeCurrentSegment()
        startDate = nil
        elapsed = accumulated
        phase = .paused
        stopTicking()
        LiveActivityController.shared.update(isRunning: false, elapsed: accumulated, description: taskDescription, tags: tagNames)
    }

    func resume() {
        guard phase == .paused else { return }
        startDate = Date()
        currentSegmentStart = Int(startDate!.timeIntervalSince1970)
        phase = .running
        startTicking()
        LiveActivityController.shared.update(isRunning: true, elapsed: accumulated, description: taskDescription, tags: tagNames)
    }

    /// Stops the session, builds one finished record per work segment, and uploads them.
    func stop() {
        if phase == .running {
            closeCurrentSegment()
        }
        enqueueSessionRecords()

        stopTicking()
        accumulated = 0
        startDate = nil
        elapsed = 0
        segments = []
        phase = .idle

        LiveActivityController.shared.end()
        flush()
    }

    /// Selected tag names, for the Live Activity.
    private var tagNames: [String] { selectedTags.map(\.name) }

    private func closeCurrentSegment() {
        let now = Int(Date().timeIntervalSince1970)
        segments.append((currentSegmentStart, max(now, currentSegmentStart + 1)))
    }

    // MARK: - Server sync

    /// Builds a client from the latest saved settings, or nil if the server isn't configured.
    private func makeClient() -> TimeTaggerClient? {
        let defaults = UserDefaults.standard
        let url = defaults.string(forKey: "serverURL")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = defaults.string(forKey: "apiToken")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty, !token.isEmpty else { return nil }
        return TimeTaggerClient(serverURL: url, token: token)
    }

    /// `<description> #tag1 #tag2`, with tag names sanitized into valid TimeTagger tags.
    private func recordDescription() -> String {
        var parts: [String] = []
        let text = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { parts.append(text) }
        for tag in selectedTags {
            let cleaned = tag.name
                .split(whereSeparator: { $0.isWhitespace || $0 == "#" })
                .joined(separator: "-")
            if !cleaned.isEmpty { parts.append("#" + cleaned) }
        }
        return parts.joined(separator: " ")
    }

    /// Turns the finished session's segments into records queued for upload.
    /// Skipped entirely when no server is configured (the app stays local-only).
    private func enqueueSessionRecords() {
        guard makeClient() != nil, !segments.isEmpty else { return }
        let ds = recordDescription()
        let mt = Int(Date().timeIntervalSince1970)
        let records = segments.map {
            TimeTaggerClient.Record(key: Self.generateKey(), t1: $0.start, t2: $0.end, mt: mt, ds: ds)
        }
        pendingRecords.append(contentsOf: records)
    }

    /// Uploads any pending records. Keeps them on failure so nothing is lost.
    private func flush() {
        guard !pendingRecords.isEmpty else { return }
        guard let client = makeClient() else {
            syncStatus = .disabled
            return
        }
        let batch = pendingRecords
        let keys = Set(batch.map(\.key))
        syncStatus = .syncing
        Task {
            let result = await client.pushRecords(batch)
            switch result {
            case .success:
                pendingRecords.removeAll { keys.contains($0.key) }
                syncStatus = .synced
            case .unauthorized:
                syncStatus = .failed("Invalid token")
            case .rejected(let message):
                syncStatus = .failed(message)
            case .badURL:
                syncStatus = .failed("Invalid server URL")
            case .failure(let message):
                syncStatus = .failed(message)
            }
        }
    }

    /// Retries a previously failed upload (wired to the sync badge).
    func retrySync() {
        flush()
    }

    /// Short random record key (TimeTagger keys are compact alphanumeric strings).
    private static func generateKey() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<10).map { _ in alphabet.randomElement()! })
    }

    // MARK: - Tags

    func addTag(_ tag: Tag) {
        guard !selectedTags.contains(where: { $0.name.caseInsensitiveCompare(tag.name) == .orderedSame }) else { return }
        selectedTags.append(tag)
    }

    func removeTag(_ tag: Tag) {
        selectedTags.removeAll { $0.id == tag.id }
    }

    // MARK: - Ticking

    private func intervalSinceStart() -> TimeInterval {
        guard let startDate else { return 0 }
        return Date().timeIntervalSince(startDate)
    }

    private func startTicking() {
        stopTicking()
        elapsed = accumulated + intervalSinceStart()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = self.accumulated + self.intervalSinceStart()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Formatting

extension TimeInterval {
    /// Split into (hours, minutes, seconds) clamped at non-negative.
    var hms: (h: Int, m: Int, s: Int) {
        let total = Int(max(0, self))
        return (total / 3600, (total % 3600) / 60, total % 60)
    }
}
