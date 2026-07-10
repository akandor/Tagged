//
//  Theme.swift
//  Taggd
//
//  Design tokens: dark palette, gold accent, Roboto Mono type ramp.
//

import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Create a color from a 0xRRGGBB hex literal.
    init(hex: UInt, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Create a color from an "RRGGBB" (or "#RRGGBB") string. Returns nil if unparseable.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt(s, radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// The color's "RRGGBB" hex string. Falls back to the accent hex if it can't be resolved.
    func toHexString() -> String {
        let r: CGFloat, g: CGFloat, b: CGFloat
        #if canImport(UIKit)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        guard UIColor(self).getRed(&rr, green: &gg, blue: &bb, alpha: &aa) else { return "DEAA22" }
        (r, g, b) = (rr, gg, bb)
        #elseif canImport(AppKit)
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return "DEAA22" }
        (r, g, b) = (ns.redComponent, ns.greenComponent, ns.blueComponent)
        #else
        return "DEAA22"
        #endif
        func channel(_ v: CGFloat) -> Int { min(255, max(0, Int(round(v * 255)))) }
        return String(format: "%02X%02X%02X", channel(r), channel(g), channel(b))
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
