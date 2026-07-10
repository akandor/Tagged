//
//  WidgetBridge.swift
//  Taggd
//
//  App-side writer for the home-screen widgets. The widgets can't run the app's
//  network client or reach its in-memory tracker, so the app pushes a compact
//  snapshot into the shared App Group whenever something they show changes:
//    • the running session (from TimeTracker transitions), and
//    • today's finished entries (fetched from the server on launch / after stop).
//

import Foundation
import WidgetKit

enum WidgetBridge {

    // MARK: - Tag colors

    /// name (lowercased) → hex, read from the tag library so server-side entries
    /// (which only carry names) can be drawn in their configured color.
    static func tagColorMap() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: "tagLibrary"),
              let tags = try? JSONDecoder().decode([Tag].self, from: data)
        else { return [:] }
        return Dictionary(tags.map { ($0.name.lowercased(), $0.colorHex) },
                          uniquingKeysWith: { first, _ in first })
    }

    static func colorHex(for tagName: String, in map: [String: String]) -> String {
        map[tagName.lowercased()] ?? Tag.defaultColorHex
    }

    // MARK: - Session slice

    /// Mirrors the live stopwatch into the snapshot's session fields.
    static func updateSession(
        isTracking: Bool,
        isRunning: Bool,
        startDate: Date,
        elapsed: TimeInterval,
        description: String,
        tags: [Tag],
        lastSessionSeconds: TimeInterval?
    ) {
        let widgetTags = tags.map { WidgetTag(name: $0.name, colorHex: $0.colorHex) }
        WidgetSharedStore.mutate { snapshot in
            snapshot.isTracking = isTracking
            snapshot.isRunning = isRunning
            snapshot.startDate = startDate
            snapshot.elapsed = elapsed
            snapshot.descriptionText = description
            snapshot.sessionTags = widgetTags
            if let lastSessionSeconds { snapshot.lastSessionSeconds = lastSessionSeconds }
        }
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        #endif
    }

    // MARK: - Today slice

    /// Fetches today's entries and writes the overview + timeline slices. No-op
    /// (but clears stale data) when no server is configured.
    static func refreshToday() async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())

        guard let client = TimeTaggerClient.fromStoredSettings() else {
            WidgetSharedStore.mutate { snapshot in
                snapshot.todayTotals = []
                snapshot.todayTotalSeconds = 0
                snapshot.timeline = []
                snapshot.dayStart = dayStart
            }
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let start = Int(dayStart.timeIntervalSince1970)
        let end = Int(Date().timeIntervalSince1970)
        guard case let .success(records) = await client.fetchRecords(from: start, to: end) else {
            return   // keep the last-known-good snapshot on a fetch failure
        }

        let colors = tagColorMap()
        // Only finished entries that actually started today, newest first is built below.
        let entries = records
            .map(TimeEntry.init)
            .filter { $0.end > $0.start && $0.start >= dayStart }
            .sorted { $0.start < $1.start }

        // Timeline rows.
        let timeline = entries.map { entry in
            WidgetTimelineItem(
                id: entry.id,
                start: entry.start,
                text: entry.text.isEmpty ? "Untitled" : entry.text,
                seconds: entry.duration,
                tags: entry.tags.map { WidgetTag(name: $0, colorHex: colorHex(for: $0, in: colors)) }
            )
        }

        // Totals: attribute each entry's whole duration to its primary (first) tag,
        // so the bars always sum to the grand total.
        var totalsByTag: [String: TimeInterval] = [:]
        var order: [String] = []
        for entry in entries {
            let key = entry.tags.first ?? "Untagged"
            if totalsByTag[key] == nil { order.append(key) }
            totalsByTag[key, default: 0] += entry.duration
        }
        let totals = order
            .map { name in
                WidgetTagTotal(
                    name: name,
                    colorHex: name == "Untagged" ? Tag.defaultColorHex : colorHex(for: name, in: colors),
                    seconds: totalsByTag[name] ?? 0
                )
            }
            .sorted { $0.seconds > $1.seconds }
        let grandTotal = entries.reduce(0) { $0 + $1.duration }

        WidgetSharedStore.mutate { snapshot in
            snapshot.todayTotals = totals
            snapshot.todayTotalSeconds = grandTotal
            snapshot.timeline = timeline
            snapshot.dayStart = dayStart
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
