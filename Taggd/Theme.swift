//
//  Theme.swift
//  Taggd
//
//  Design tokens: dark palette, gold accent, Roboto Mono type ramp.
//

import SwiftUI
import CoreText

extension Color {
    /// Create a color from a 0xRRGGBB hex literal.
    init(hex: UInt, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum Theme {
    static let accent         = Color(hex: 0xDEAA22)
    static let background      = Color(hex: 0x0C0C0E)
    static let surface         = Color(hex: 0x161618)
    static let surfaceRaised   = Color(hex: 0x1E1E21)
    static let stroke          = Color.white.opacity(0.08)
    static let textPrimary     = Color(hex: 0xF5F5F7)
    static let textSecondary   = Color(hex: 0x9A9AA0)
    static let textTertiary    = Color(hex: 0x5E5E63)
    static let danger          = Color(hex: 0xE5484D)
}

/// Roboto Mono weights available in the bundle.
enum MonoWeight {
    case thin, extraLight, light, regular, medium, semiBold, bold

    var postScriptName: String {
        switch self {
        case .thin:       return "RobotoMono-Thin"
        case .extraLight: return "RobotoMono-ExtraLight"
        case .light:      return "RobotoMono-Light"
        case .regular:    return "RobotoMono-Regular"
        case .medium:     return "RobotoMono-Medium"
        case .semiBold:   return "RobotoMono-SemiBold"
        case .bold:       return "RobotoMono-Bold"
        }
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: MonoWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }
}

enum FontRegistrar {
    /// Registers every bundled Roboto Mono face so `Font.custom` can resolve it.
    /// Safe to call once at launch; already-registered faces are ignored.
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
