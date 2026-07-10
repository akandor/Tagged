//
//  MacTagManagerView.swift
//  TaggdMac
//
//  Add, edit, delete, and reorder the tag library. Hosted in its own window
//  (opened from Settings → Manage Tags), so the standard traffic-light controls
//  close it. Mirrors the iOS tag manager: a grouped table with an "Add a tag"
//  row and a "Your Tags" section, plus a sheet (name + color picker) for adding
//  or editing. macOS List has no swipe-to-delete, so each row carries its own
//  trash button and reordering is drag-based via `.onMove`.
//

import SwiftUI

/// What the editor sheet is doing: creating a new tag, or editing an existing one.
private enum TagEditorTarget: Identifiable {
    case new
    case edit(Tag)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let tag): return tag.id.uuidString
        }
    }
}

struct MacTagManagerView: View {
    @Environment(TagStore.self) private var store

    @State private var editing: TagEditorTarget?

    var body: some View {
        Form {
            Section {
                if store.tags.isEmpty {
                    Text("No tags yet. Tap + to add one.")
                        .font(.mono(13))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(store.tags) { tag in
                        TagRow(tag: tag,
                               onEdit: { editing = .edit(tag) },
                               onDelete: { delete(tag) })
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
            } header: {
                Text("Your Tags")
            } footer: {
                Text("Click a tag to edit · drag to reorder · trash to delete.")
                    .font(.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlayScrollbars()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            RoundActionButton(systemImage: "plus", help: "Add a tag") {
                editing = .new
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(item: $editing) { target in
            MacTagEditorSheet(target: target)
                .environment(store)
        }
    }

    private func delete(_ tag: Tag) {
        if let index = store.tags.firstIndex(where: { $0.id == tag.id }) {
            store.remove(at: IndexSet(integer: index))
        }
    }
}

/// A single tag row: color swatch, name (click to edit), and a trash button.
private struct TagRow: View {
    let tag: Tag
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    Text(tag.name)
                        .font(.mono(14))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete tag \(tag.name)")
        }
    }
}

/// Sheet for creating or editing a tag: a name field plus a color palette and a
/// custom color picker. Uses a NavigationStack so Cancel / Save render as native
/// macOS toolbar buttons, matching the iOS editor.
private struct MacTagEditorSheet: View {
    @Environment(TagStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: TagEditorTarget

    @State private var name: String
    @State private var color: Color

    init(target: TagEditorTarget) {
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: "")
            _color = State(initialValue: Color(hexString: Tag.defaultColorHex) ?? Theme.accent)
        case .edit(let tag):
            _name = State(initialValue: tag.name)
            _color = State(initialValue: tag.color)
        }
    }

    var body: some View {
        SheetScaffold(
            title: isEditing ? "Edit Tag" : "New Tag",
            confirmTitle: "Save",
            saving: !canSave,
            width: 420,
            height: 450,
            onCancel: { dismiss() },
            onConfirm: save
        ) {
            nameCard
            colorCard
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("NAME")
            TextField("Tag name", text: $name)
                .font(.mono(15, .regular))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .onSubmit(save)
                .themedField()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("COLOR")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 40), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Tag.palette, id: \.self) { hex in
                    let swatch = Color(hexString: hex) ?? Theme.accent
                    Button {
                        color = swatch
                    } label: {
                        Circle()
                            .fill(swatch)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                            .overlay {
                                if isSelected(swatch) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.black.opacity(0.85))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(Theme.stroke)

            ColorPicker(selection: $color, supportsOpacity: false) {
                Text("Custom color")
                    .font(.mono(14, .regular))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isSelected(_ swatch: Color) -> Bool {
        swatch.toHexString() == color.toHexString()
    }

    private func save() {
        guard canSave else { return }
        let hex = color.toHexString()
        switch target {
        case .new:
            store.add(name, colorHex: hex)
        case .edit(let tag):
            store.update(tag.id, name: name, colorHex: hex)
        }
        dismiss()
    }
}

private func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.mono(11, .medium))
        .tracking(1.5)
        .foregroundStyle(Theme.textTertiary)
}
