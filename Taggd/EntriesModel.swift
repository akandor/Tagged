//
//  EntriesModel.swift
//  Taggd
//
//  Platform-agnostic logic for the time-entries overview: parsing/serializing
//  TimeTagger records and formatting durations/dates. Shared by the iOS
//  EntriesView and the macOS MacEntriesView. Foundation-only, no UI.
//

import Foundation

/// One parsed server record: description text and `#tags` split out of `ds`.
struct TimeEntry: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let text: String
    let tags: [String]
    let raw: String

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// Rebuilds the server record for delete/edit round-trips (mt refreshed on push).
    var record: TimeTaggerClient.Record {
        TimeTaggerClient.Record(
            key: id,
            t1: Int(start.timeIntervalSince1970),
            t2: Int(end.timeIntervalSince1970),
            mt: Int(Date().timeIntervalSince1970),
            ds: raw
        )
    }

    init(_ record: TimeTaggerClient.Record) {
        id = record.key
        start = Date(timeIntervalSince1970: TimeInterval(record.t1))
        end = Date(timeIntervalSince1970: TimeInterval(max(record.t2, record.t1)))
        raw = record.ds
        var textWords: [String] = []
        var parsedTags: [String] = []
        for word in record.ds.split(separator: " ") {
            if word.hasPrefix("#"), word.count > 1 {
                parsedTags.append(String(word.dropFirst()))
            } else {
                textWords.append(String(word))
            }
        }
        text = textWords.joined(separator: " ")
        tags = parsedTags
    }
}

/// Builds a TimeTagger `ds` from free text plus tags, sanitizing tag names into
/// valid `#tag` tokens (whitespace/`#` become hyphens).
func composeDescription(text: String, tags: [String]) -> String {
    var parts: [String] = []
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { parts.append(trimmed) }
    for tag in tags {
        let cleaned = tag
            .split(whereSeparator: { $0.isWhitespace || $0 == "#" })
            .joined(separator: "-")
        if !cleaned.isEmpty { parts.append("#" + cleaned) }
    }
    return parts.joined(separator: " ")
}

/// `"2h 30m"` from a duration; hours are shown even when zero.
func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(max(0, interval))
    return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
}

extension DateFormatter {
    /// A reused formatter per format string (formatters are expensive to build).
    static func cached(_ format: String) -> DateFormatter {
        if let existing = cache[format] { return existing }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = format
        cache[format] = formatter
        return formatter
    }

    private static var cache: [String: DateFormatter] = [:]
}
