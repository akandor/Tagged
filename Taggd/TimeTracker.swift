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

    /// Shared instance so Live Activity intents (which run in the app process) can
    /// reach the same tracker the UI uses.
    static let shared = TimeTracker()

    init() {
        // Live Activity buttons (iOS only) post these; the macOS app drives the
        // tracker directly, so it doesn't need — or define — these notifications.
        #if os(iOS)
        let center = NotificationCenter.default
        center.addObserver(forName: .taggdPauseSession, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        center.addObserver(forName: .taggdResumeSession, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        center.addObserver(forName: .taggdStopSession, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        #endif
    }

    // MARK: - Controls

    func start() {
        guard phase != .running else { return }
        startDate = Date()
        currentSegmentStart = Int(startDate!.timeIntervalSince1970)
        segments = []
        syncStatus = .disabled   // clear any "saved/not saved" badge for the new session
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
    /// On failure the session is saved locally (offline) so nothing is lost.
    func stop() {
        if phase == .running {
            closeCurrentSegment()
        }
        let finished = buildFinishedSession()

        stopTicking()
        accumulated = 0
        startDate = nil
        elapsed = 0
        segments = []
        phase = .idle

        LiveActivityController.shared.end()
        if let finished { saveOrSync(finished) }
    }

    /// Selected tag names, for the Live Activity.
    private var tagNames: [String] { selectedTags.map(\.name) }

    private func closeCurrentSegment() {
        let now = Int(Date().timeIntervalSince1970)
        segments.append((currentSegmentStart, max(now, currentSegmentStart + 1)))
    }

    // MARK: - Server sync

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

    /// Bundles the finished session's segments into an uploadable unit, or nil when
    /// there's nothing to save or no server is configured (app stays local-only).
    private func buildFinishedSession() -> UnsyncedSession? {
        guard TimeTaggerClient.fromStoredSettings() != nil, !segments.isEmpty else { return nil }
        let ds = recordDescription()
        let mt = Int(Date().timeIntervalSince1970)
        let records = segments.map {
            TimeTaggerClient.Record(key: Self.generateKey(), t1: $0.start, t2: $0.end, mt: mt, ds: ds)
        }
        return UnsyncedSession(
            stoppedAt: Date(),
            descriptionText: taskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tagNames,
            records: records
        )
    }

    /// Uploads a finished session; on any failure it's stored offline for later retry.
    private func saveOrSync(_ session: UnsyncedSession) {
        guard let client = TimeTaggerClient.fromStoredSettings() else {
            syncStatus = .disabled
            return
        }
        syncStatus = .syncing
        Task {
            if case .success = await client.pushRecords(session.records) {
                syncStatus = .synced
            } else {
                OfflineStore.shared.add(session)
                syncStatus = .failed("Saved offline")
            }
        }
    }

    /// Retries all offline sessions (wired to the sync badge / toast).
    func retrySync() {
        Task {
            syncStatus = .syncing
            let cleared = await OfflineStore.shared.retryAll()
            syncStatus = cleared ? .synced : .failed("Saved offline")
        }
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
