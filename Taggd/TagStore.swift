//
//  TagStore.swift
//  Taggd
//
//  Persistent, ordered library of the user's tags. Shared by the main screen's
//  tag picker and the Settings tag manager. Backed by UserDefaults (JSON).
//

import SwiftUI
import Observation

@Observable
@MainActor
final class TagStore {
    private static let storageKey = "tagLibrary"

    private(set) var tags: [Tag]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Tag].self, from: data) {
            tags = decoded
        } else {
            tags = Tag.presets
        }
    }

    /// Adds a tag (or returns the existing one for a duplicate name). Returns nil for empty input.
    @discardableResult
    func add(_ name: String) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let tag = Tag(name: trimmed)
        tags.append(tag)
        save()
        return tag
    }

    func rename(_ id: Tag.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tags.firstIndex(where: { $0.id == id }) else { return }
        guard tags[index].name != trimmed else { return }
        tags[index].name = trimmed
        save()
    }

    func remove(at offsets: IndexSet) {
        tags.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
