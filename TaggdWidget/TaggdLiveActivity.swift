//
//  TaggdLiveActivity.swift
//  TaggdWidget
//
//  Lock Screen banner + Dynamic Island for a running Tagged session, with the
//  app logo and interactive Pause/Resume/Stop controls.
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
                Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(formattedElapsed(state.elapsed))
            }
        }
        .font(.system(size: size, weight: weight, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(state.isRunning ? Color.taggdAccent : .primary)
    }
}

/// The app mark on an accent tile, like a miniature app icon.
private struct LogoBadge: View {
    var size: CGFloat = 34

    var body: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
            .padding(size * 0.2)
            .frame(width: size, height: size)
            .foregroundStyle(.black)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color.taggdAccent)
            )
    }
}

/// Interactive Pause/Resume + Stop buttons backed by LiveActivityIntents.
private struct ControlButtons: View {
    let isRunning: Bool
    var compact = false

    private var diameter: CGFloat { compact ? 30 : 38 }
    private var glyph: CGFloat { compact ? 12 : 15 }

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            if isRunning {
                Button(intent: PauseSessionIntent()) {
                    icon("pause.fill", fg: .black, bg: Color.taggdAccent)
                }
            } else {
                Button(intent: ResumeSessionIntent()) {
                    icon("play.fill", fg: .black, bg: Color.taggdAccent)
                }
            }
            Button(intent: StopSessionIntent()) {
                icon("stop.fill", fg: Color.taggdAccent, bg: Color.white.opacity(0.14))
            }
        }
        .buttonStyle(.plain)
    }

    private func icon(_ name: String, fg: Color, bg: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: glyph, weight: .bold))
            .foregroundStyle(fg)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(bg))
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
                    LogoBadge(size: 30)
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
                    HStack(spacing: 8) {
                        if !state.tags.isEmpty {
                            Text(state.tags.map { "#\($0)" }.joined(separator: " "))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.taggdAccent)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        ControlButtons(isRunning: state.isRunning, compact: true)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.taggdAccent)
            } compactTrailing: {
                TimerText(state: state, size: 14)
                    .frame(maxWidth: 56)
            } minimal: {
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.taggdAccent)
            }
            .keylineTint(Color.taggdAccent)
        }
    }
}

private struct LockScreenView: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                LogoBadge()
                Text("TAGGED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TimerText(state: state, size: 24)
                    .lineLimit(1)
            }

            Text(state.descriptionText.isEmpty ? "Tracking…" : state.descriptionText)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if state.tags.isEmpty {
                    Text(state.isRunning ? "Running" : "Paused")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.taggdAccent)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                ControlButtons(isRunning: state.isRunning)
            }
        }
        .padding(16)
    }
}
