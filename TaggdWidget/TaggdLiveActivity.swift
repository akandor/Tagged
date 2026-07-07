//
//  TaggdLiveActivity.swift
//  TaggdWidget
//
//  Lock Screen banner + Dynamic Island for a running Taggd session.
//

import ActivityKit
import WidgetKit
import SwiftUI

private extension Color {
    /// #DEAA22 — matches the app accent. (Roboto Mono isn't bundled in the
    /// extension, so the widget uses the system monospaced design.)
    static let taggdAccent = Color(red: 0xDE / 255, green: 0xAA / 255, blue: 0x22 / 255)
    static let taggdBackground = Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x0E / 255)
}

/// "1:02:03" style, used for the frozen (paused) value.
private func formattedElapsed(_ interval: TimeInterval) -> String {
    let total = Int(max(0, interval))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}

/// Live timer text: counts up while running, frozen while paused.
private struct TimerText: View {
    let state: SessionActivityAttributes.ContentState
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Group {
            if state.isRunning {
                Text(state.startDate, style: .timer)
            } else {
                Text(formattedElapsed(state.elapsed))
            }
        }
        .font(.system(size: size, weight: weight, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(state.isRunning ? Color.taggdAccent : .primary)
    }
}

struct TaggdLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.taggdBackground)
                .activitySystemActionForegroundColor(Color.taggdAccent)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.isRunning ? "record.circle" : "pause.circle")
                        .font(.title2)
                        .foregroundStyle(Color.taggdAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: state, size: 20)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.descriptionText.isEmpty ? "Tracking" : state.descriptionText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !state.tags.isEmpty {
                        Text(state.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.taggdAccent)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: state.isRunning ? "record.circle" : "pause.circle")
                    .foregroundStyle(Color.taggdAccent)
            } compactTrailing: {
                TimerText(state: state, size: 14)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.taggdAccent)
            }
            .keylineTint(Color.taggdAccent)
        }
    }
}

private struct LockScreenView: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TAGGED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text(state.descriptionText.isEmpty ? "Tracking…" : state.descriptionText)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !state.tags.isEmpty {
                    Text(state.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.taggdAccent)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            TimerText(state: state, size: 26)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(16)
    }
}
