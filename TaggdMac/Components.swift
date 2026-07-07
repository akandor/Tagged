//
//  Components.swift
//  TaggdMac
//
//  Small reusable pieces ported from the iOS ContentView so the menu-bar
//  popover keeps the same styling.
//

import SwiftUI
import AppKit

// MARK: - Timer display

struct TimerDisplay: View {
    let elapsed: TimeInterval
    let running: Bool

    var body: some View {
        let t = elapsed.hms
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            unit(t.h, "h")
            unit(t.m, "m")
            unit(t.s, "s")
        }
        .foregroundStyle(running ? Theme.accent : Theme.textPrimary)
        .contentTransition(.numericText())
        .animation(.snappy(duration: 0.2), value: t.s)
        .animation(.default, value: running)
        .accessibilityLabel("\(t.h) hours \(t.m) minutes \(t.s) seconds")
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(String(format: "%02d", value))
                .font(.mono(46, .medium))
            Text(label)
                .font(.mono(20, .regular))
                .foregroundStyle(running ? Theme.accent.opacity(0.65) : Theme.textTertiary)
        }
    }
}

// MARK: - Tag chip

struct TagChip: View {
    let tag: Tag
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(tag.name)
                    .font(.mono(13, .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove tag \(tag.name)")
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.mono(16, .semiBold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.accent)
        .foregroundStyle(Color.black)
    }
}

struct SecondaryButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.mono(16, .semiBold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .foregroundStyle(tint)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(tint)
    }
}

// MARK: - Sync toast

enum ToastKind: Equatable {
    case saved, notSaved
}

struct ToastView: View {
    let kind: ToastKind
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind == .saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(kind == .saved ? Color.green : Theme.danger)
            Text(kind == .saved ? "Saved" : "Not saved")
                .font(.mono(13, .medium))
                .foregroundStyle(Theme.textPrimary)
            if kind == .notSaved {
                Divider().frame(height: 16).overlay(Theme.stroke)
                Button("Retry", action: onRetry)
                    .font(.mono(12, .semiBold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(Capsule(style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
    }
}

// MARK: - Shared card background

struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

// MARK: - Text field styling

/// The raised, dark input surface used for the Server URL / API token fields so
/// they read as editable affordances against the grouped section background
/// instead of the light system `.roundedBorder` bezel.
struct FieldBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps a plain text field in the themed `FieldBackground` with consistent
    /// inset padding.
    func themedField() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(FieldBackground())
    }
}

// MARK: - Overlay scrollbars

/// Switches the enclosing scroll views to the thin, auto-hiding overlay
/// scroller style. macOS otherwise renders a legacy full-width scroller when the
/// system "Show scroll bars" preference is set to "Always", which looks heavy
/// against the dark theme. We walk the window's view tree (rather than relying
/// on `enclosingScrollView`, which a SwiftUI `.background` host doesn't resolve
/// reliably) and reconfigure every scroll view we find.
private struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let content = nsView.window?.contentView else { return }
            configure(content)
        }
    }

    private func configure(_ view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.knobStyle = .light
            scrollView.horizontalScroller?.knobStyle = .light
        }
        for sub in view.subviews { configure(sub) }
    }
}

extension View {
    /// Makes scroll bars in the current window thin and visible only while
    /// scrolling.
    func overlayScrollbars() -> some View {
        background(OverlayScrollerConfigurator().frame(width: 0, height: 0))
    }
}
