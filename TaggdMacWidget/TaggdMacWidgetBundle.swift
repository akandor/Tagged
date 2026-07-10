//
//  TaggdMacWidgetBundle.swift
//  TaggdMacWidget
//
//  macOS widget extension. Shows the same three widgets as iOS (Quick Timer,
//  Today's Overview, Timeline) in Notification Center / on the desktop. No Live
//  Activity or Control Center here — those are iOS-only.
//

import WidgetKit
import SwiftUI

@main
struct TaggdMacWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickTimerWidget()
        TodayOverviewWidget()
        TimelineWidget()
    }
}
