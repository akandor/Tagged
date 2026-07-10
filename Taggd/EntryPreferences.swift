//
//  EntryPreferences.swift
//  Taggd
//
//  User preferences for how the entries overview presents a week. Stored in
//  UserDefaults via @AppStorage and shared by Settings and EntriesView.
//

import SwiftUI

/// Which weekday a week starts on. Raw value is the `Calendar.firstWeekday`
/// convention (1 = Sunday … 7 = Saturday) so it maps straight onto a calendar.
enum WeekStart: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case saturday = 7

    var id: Int { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .sunday:   return "Sunday"
        case .monday:   return "Monday"
        case .saturday: return "Saturday"
        }
    }
}

/// The stretch of days considered working days. `weekdays` uses `Calendar`
/// weekday numbers (1 = Sunday … 7 = Saturday).
enum Workdays: String, CaseIterable, Identifiable {
    case mondayToFriday
    case mondayToSaturday
    case sundayToThursday
    case everyDay

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .mondayToFriday:   return "Monday – Friday"
        case .mondayToSaturday: return "Monday – Saturday"
        case .sundayToThursday: return "Sunday – Thursday"
        case .everyDay:         return "Every day"
        }
    }

    var weekdays: Set<Int> {
        switch self {
        case .mondayToFriday:   return [2, 3, 4, 5, 6]
        case .mondayToSaturday: return [2, 3, 4, 5, 6, 7]
        case .sundayToThursday: return [1, 2, 3, 4, 5]
        case .everyDay:         return [1, 2, 3, 4, 5, 6, 7]
        }
    }

    func isWorkday(_ weekday: Int) -> Bool { weekdays.contains(weekday) }
}
