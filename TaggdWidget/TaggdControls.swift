//
//  TaggdControls.swift
//  TaggdWidget
//
//  Control Center control (iOS 18+): a single Start/Stop toggle for the current
//  session. It reflects the shared snapshot's tracking state and drives the same
//  optimistic-snapshot + pending-action machinery as the widget buttons, so the
//  app reconciles it into the real tracker.
//

import WidgetKit
import SwiftUI
import AppIntents

/// Toggling the control sets `value` to the desired state; true → start, false → stop.
struct TrackingToggleIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Tagged Timer"
    static let description = IntentDescription("Starts or stops a Tagged session.")

    @Parameter(title: "Tracking")
    var value: Bool

    func perform() async throws -> some IntentResult {
        dispatchSessionAction(
            value ? .start : .stop,
            notification: value ? .taggdStartSession : .taggdStopSession
        )
        return .result()
    }
}

@available(iOS 18.0, *)
struct TrackingControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetSharedStore.loadSnapshot().isTracking
    }
}

@available(iOS 18.0, *)
struct TrackingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.toepper.rocks.Tagged.TrackingControl",
            provider: TrackingControlProvider()
        ) { isTracking in
            ControlWidgetToggle(
                "Tagged Timer",
                isOn: isTracking,
                action: TrackingToggleIntent()
            ) { isOn in
                Label(isOn ? "Tracking" : "Start Timer",
                      systemImage: isOn ? "stop.fill" : "play.fill")
            }
            .tint(Color(red: 0xDE / 255, green: 0xAA / 255, blue: 0x22 / 255))
        }
        .displayName("Tagged Timer")
        .description("Start or stop a Tagged session.")
    }
}
