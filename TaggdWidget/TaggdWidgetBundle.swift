//
//  TaggdWidgetBundle.swift
//  TaggdWidget
//

import WidgetKit
import SwiftUI

@main
struct TaggdWidgetBundle: WidgetBundle {
    var body: some Widget {
        TaggdLiveActivity()
        QuickTimerWidget()
        TodayOverviewWidget()
        TimelineWidget()
        if #available(iOS 18.0, *) {
            TrackingControl()
        }
    }
}
