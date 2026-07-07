//
//  Models.swift
//  Taggd
//

import Foundation

struct Tag: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Tag {
    /// Tags offered by default in the selector.
    static let presets: [Tag] = [
    ].map { Tag(name: $0) }
}
