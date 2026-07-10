//
//  TaggdEntryWidgets.swift
//  TaggdWidget
//
//  Home-screen widgets: a small Quick Timer, a medium Today's Overview, and a
//  large Timeline. All three read the shared snapshot the app writes into the App
//  Group (see WidgetSharedStore / WidgetBridge) and drive the session with the
//  same interactive AppIntents as the Live Activity.
//
//  Roboto Mono isn't bundled in the extension, so — like the Live Activity — these
//  use the system monospaced design to match the app's type ramp.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Palette (mirrors Theme.swift, which is app-only)

private extension Color {
    /// From an "RRGGBB" string, falling back to the gold accent.
    init(taggdHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0xDEAA22
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

private enum W {
    static let accent        = Color(taggdHex: "DEAA22")
    static let background     = Color(taggdHex: "0C0C0E")
    static let surface        = Color(taggdHex: "161618")
    static let surfaceRaised  = Color(taggdHex: "1E1E21")
    static let stroke         = Color.white.opacity(0.08)
    static let textPrimary    = Color(taggdHex: "F5F5F7")
    static let textSecondary  = Color(taggdHex: "9A9AA0")
    static let textTertiary   = Color(taggdHex: "5E5E63")
    static let running        = Color(taggdHex: "46A758")
}

// MARK: - Formatting

private func widgetDuration(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
}

/// Frozen "H:MM:SS" (or "M:SS"), matching the running `Text(timerInterval:)` look.
private func frozenClock(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

private let timeOfDayFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("j:mm"); return f
}()

private let weekdayFormatter: DateFormatter = {
    let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("EEEEMMMd"); return f
}()

// MARK: - Shared pieces

private struct Wordmark: View {
    var body: some View {
        Text("TAGGED")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(W.textSecondary)
    }
}

/// Self-updating timer: counts up while running, frozen while paused.
private struct SessionTimer: View {
    let snapshot: WidgetSnapshot
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Group {
            if snapshot.isRunning {
                Text(timerInterval: snapshot.startDate...Date.distantFuture, countsDown: false)
            } else {
                Text(frozenClock(snapshot.currentElapsed()))
            }
        }
        .font(.system(size: size, weight: weight, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(snapshot.isRunning ? W.accent : W.textPrimary)
    }
}

private struct TagDot: View {
    let colorHex: String
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(Color(taggdHex: colorHex)).frame(width: size, height: size)
    }
}

/// The app's tag chip: capsule tinted with the tag's own color.
private struct TagChip: View {
    let tag: WidgetTag
    var body: some View {
        let color = Color(taggdHex: tag.colorHex)
        Text(tag.name)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
                    .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
            )
    }
}

/// Accent-filled control button backed by one of the session intents.
private struct AccentButton<I: AppIntent>: View {
    let title: String
    let systemImage: String
    let intent: I

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: 7) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Capsule(style: .continuous).fill(W.accent))
        }
        .buttonStyle(.plain)
    }
}

/// A start OR stop button chosen from the session state.
private struct SessionControlButton: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        if snapshot.isTracking {
            AccentButton(title: "Stop", systemImage: "stop.fill", intent: StopSessionIntent())
        } else {
            AccentButton(title: "Start", systemImage: "play.fill", intent: StartSessionIntent())
        }
    }
}

/// Compact, icon-only accent button — used where horizontal room is tight so the
/// data columns get more width.
private struct AccentIconButton<I: AppIntent>: View {
    let systemImage: String
    let intent: I

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(W.accent))
        }
        .buttonStyle(.plain)
    }
}

private struct SessionIconButton: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        if snapshot.isTracking {
            AccentIconButton(systemImage: "stop.fill", intent: StopSessionIntent())
        } else {
            AccentIconButton(systemImage: "play.fill", intent: StartSessionIntent())
        }
    }
}

private struct StatusLabel: View {
    let running: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(running ? W.running : W.textTertiary).frame(width: 7, height: 7)
            Text(running ? "Running" : "Ready")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(running ? W.textPrimary : W.textSecondary)
        }
    }
}

private struct VDivider: View {
    var body: some View { Rectangle().fill(W.stroke).frame(width: 1) }
}

// MARK: - Small · Quick Timer

private struct SmallQuickTimer: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer(minLength: 6)

            if snapshot.isTracking {
                SessionTimer(snapshot: snapshot, size: 30, weight: .medium)
                Text(snapshot.descriptionText.isEmpty ? "Tracking…" : snapshot.descriptionText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(W.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 2)
                if let tag = snapshot.sessionTags.first {
                    TagChip(tag: tag)
                        .padding(.top, 5)
                }
                Spacer(minLength: 8)
                SessionControlButton(snapshot: snapshot)
            } else {
                Text("Ready")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(W.textPrimary)
                if let last = snapshot.lastSessionSeconds, last > 0 {
                    Text("Last: \(widgetDuration(last))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(W.textSecondary)
                        .padding(.top, 3)
                }
                Spacer(minLength: 8)
                SessionControlButton(snapshot: snapshot)
            }
        }
    }
}

// MARK: - Medium · Today's Overview

private struct TotalBar: View {
    let total: WidgetTagTotal
    let fraction: Double
    var body: some View {
        let color = Color(taggdHex: total.colorHex)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                TagDot(colorHex: total.colorHex)
                Text(total.name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                Text(widgetDuration(total.seconds))
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(W.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.surfaceRaised)
                    Capsule().fill(color)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct MediumOverview: View {
    let snapshot: WidgetSnapshot

    private var maxSeconds: TimeInterval {
        max(1, snapshot.todayTotals.map(\.seconds).max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left — today's breakdown
            VStack(alignment: .leading, spacing: 8) {
                Wordmark()
                Text("Today")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(W.textSecondary)

                if snapshot.todayTotals.isEmpty {
                    Spacer(minLength: 0)
                    Text("No entries yet")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(W.textTertiary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(snapshot.todayTotals.prefix(2)) { total in
                        TotalBar(total: total, fraction: total.seconds / maxSeconds)
                    }
                    Spacer(minLength: 2)
                    Rectangle().fill(W.stroke).frame(height: 1)
                    HStack {
                        Text("Total")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(W.textSecondary)
                        Spacer()
                        Text(widgetDuration(snapshot.todayTotalSeconds))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(W.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VDivider()

            // Right — running session (compact, centered)
            VStack(alignment: .center, spacing: 6) {
                StatusLabel(running: snapshot.isRunning)
                Text(sessionLine)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(snapshot.isTracking ? W.textPrimary : W.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                SessionTimer(snapshot: snapshot, size: 22)
                Spacer(minLength: 4)
                SessionIconButton(snapshot: snapshot)
            }
            .frame(width: 88)
        }
    }

    private var sessionLine: String {
        if snapshot.isTracking {
            return snapshot.descriptionText.isEmpty ? "Tracking…" : snapshot.descriptionText
        }
        return "Nothing running"
    }
}

// MARK: - Large · Timeline

private struct TimelineRow: View {
    let item: WidgetTimelineItem
    var body: some View {
        HStack(spacing: 8) {
            TagDot(colorHex: item.tags.first?.colorHex ?? "DEAA22")
            Text(timeOfDayFormatter.string(from: item.start))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(W.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Text(item.text)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(W.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(widgetDuration(item.seconds))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(W.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

private struct LargeTimeline: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Wordmark()
                Text(weekdayFormatter.string(from: snapshot.dayStart))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(W.accent)
            }

            // Timeline — full width
            VStack(alignment: .leading, spacing: 10) {
                if snapshot.timeline.isEmpty {
                    Text("No entries today")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(W.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(snapshot.timeline.prefix(6)) { TimelineRow(item: $0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)
            Rectangle().fill(W.stroke).frame(height: 1)

            // Running session — full width, below the timeline
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    StatusLabel(running: snapshot.isRunning)
                    Text(snapshot.isTracking
                         ? (snapshot.descriptionText.isEmpty ? "Tracking…" : snapshot.descriptionText)
                         : "Nothing running")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(snapshot.isTracking ? W.textPrimary : W.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                SessionTimer(snapshot: snapshot, size: 28)
                SessionIconButton(snapshot: snapshot)
            }
        }
    }
}

// MARK: - Timeline provider

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? .sample : WidgetSharedStore.loadSnapshot()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSharedStore.loadSnapshot())
        // A running timer self-updates via Text(timerInterval:); we still refresh
        // periodically so "today" totals and the idle "Last:" value don't go stale.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Container

private struct WidgetContainer<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(W.background, for: .widget)
            .widgetURL(URL(string: "taggd://open"))
    }
}

// MARK: - Widgets

struct QuickTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TaggdQuickTimer", provider: Provider()) { entry in
            WidgetContainer { SmallQuickTimer(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Quick Timer")
        .description("Start or stop tracking and watch the running timer.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TaggdTodayOverview", provider: Provider()) { entry in
            WidgetContainer { MediumOverview(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Today's Overview")
        .description("Time per tag today, plus the running session.")
        .supportedFamilies([.systemMedium])
    }
}

struct TimelineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TaggdTimeline", provider: Provider()) { entry in
            WidgetContainer { LargeTimeline(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Timeline")
        .description("Today's entries and the running session.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Sample data (placeholder / gallery)

private extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let day = Calendar.current.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int) -> Date { day.addingTimeInterval(TimeInterval(h * 3600 + m * 60)) }
        return WidgetSnapshot(
            isTracking: true,
            isRunning: true,
            startDate: Date().addingTimeInterval(-2838),   // 00:47:18
            elapsed: 2838,
            descriptionText: "Writing blog post",
            sessionTags: [WidgetTag(name: "Work", colorHex: "DEAA22")],
            lastSessionSeconds: 8000,
            todayTotals: [
                WidgetTagTotal(name: "Work", colorHex: "DEAA22", seconds: 19200),
                WidgetTagTotal(name: "Personal", colorHex: "3E9EFF", seconds: 4200)
            ],
            todayTotalSeconds: 23400,
            timeline: [
                WidgetTimelineItem(id: "1", start: at(9, 0), text: "Writing blog post", seconds: 9000, tags: [WidgetTag(name: "Work", colorHex: "46A758")]),
                WidgetTimelineItem(id: "2", start: at(13, 0), text: "Code review", seconds: 8100, tags: [WidgetTag(name: "Work", colorHex: "DEAA22")]),
                WidgetTimelineItem(id: "3", start: at(15, 30), text: "Design overview screen", seconds: 6000, tags: [WidgetTag(name: "Design", colorHex: "E5484D")]),
                WidgetTimelineItem(id: "4", start: at(18, 0), text: "Plan next sprint", seconds: 2700, tags: [WidgetTag(name: "Personal", colorHex: "3E9EFF")])
            ],
            dayStart: day,
            updatedAt: Date()
        )
    }
}
