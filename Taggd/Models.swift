//
//  Models.swift
//  Taggd
//

import SwiftUI

struct Tag: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String = Tag.defaultColorHex) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorHex = colorHex
    }

    /// SwiftUI color for this tag, falling back to the accent if the stored hex is invalid.
    var color: Color { Color(hexString: colorHex) ?? Theme.accent }

    // Backward-compatible decoding: tags saved before colors existed have no `colorHex`,
    // so we default it instead of failing the whole decode (which would wipe the library).
    enum CodingKeys: String, CodingKey { case id, name, colorHex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? Tag.defaultColorHex
    }
}

extension Tag {
    /// Gold accent, used as the default for tags without an explicit color.
    static let defaultColorHex = "DEAA22"

    /// Quick-pick colors offered in the tag editor.
    static let palette: [String] = [
        "DEAA22", // gold (accent)
        "E5484D", // red
        "F76808", // orange
        "F5D90A", // yellow
        "46A758", // green
        "12A594", // teal
        "3E9EFF", // blue
        "8E4EC6", // purple
        "E93D82", // pink
        "9A9AA0", // gray
    ]

    /// Tags offered by default in the selector.
    static let presets: [Tag] = []
}
