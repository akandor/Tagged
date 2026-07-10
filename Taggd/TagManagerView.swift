//
//  TagManagerView.swift
//  Taggd
//
//  Add, edit, delete, and reorder the tag library. Pushed from Settings.
//  Adding and editing happen in a sheet with a name field and a color picker.
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

struct TagManagerView: View {
    @Environment(TagStore.self) private var store
    @State private var editing: TagEditorTarget?

    var body: some View {
        List {
            Section {
                Button {
                    editing = .new
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.accent)
                        Text("Add a tag")
                            .font(.mono(15))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                if store.tags.isEmpty {
                    Text("No tags yet. Add one above.")
                        .font(.mono(13))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(store.tags) { tag in
                        Button {
                            editing = .edit(tag)
                        } label: {
                            TagRow(tag: tag)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { store.remove(at: $0) }
                    .onMove { store.move(from: $0, to: $1) }
                }
            } header: {
                Text("Your Tags")
            } footer: {
                Text("Tap a tag to edit · swipe to delete · use Edit to reorder.")
                    .font(.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().tint(Theme.accent)
            }
        }
        .tint(Theme.accent)
        .sheet(item: $editing) { target in
            TagEditorSheet(target: target)
                .environment(store)
        }
    }
}

/// A single tag row: color swatch, name, and a chevron hinting it's tappable.
private struct TagRow: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tag.color)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            Text(tag.name)
                .font(.mono(15))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Sheet for creating or editing a tag: a name field plus a color palette and a custom color picker.
private struct TagEditorSheet: View {
    @Environment(TagStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: TagEditorTarget

    @State private var name: String
    @State private var color: Color
    @FocusState private var nameFocused: Bool

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
        NavigationStack {
            List {
                Section {
                    TextField(
                        "",
                        text: $name,
                        prompt: Text("Tag name").foregroundColor(Theme.textTertiary)
                    )
                    .font(.mono(16))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                } header: {
                    Text("Name")
                }

                Section {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Tag.palette, id: \.self) { hex in
                            let swatch = Color(hexString: hex) ?? Theme.accent
                            Button {
                                color = swatch
                            } label: {
                                Circle()
                                    .fill(swatch)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .overlay {
                                        if isSelected(swatch) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color.black.opacity(0.85))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    ColorPicker(selection: $color, supportsOpacity: false) {
                        Text("Custom color")
                            .font(.mono(15))
                            .foregroundStyle(Theme.textPrimary)
                    }
                } header: {
                    Text("Color")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Tag" : "New Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                        .tint(Theme.textSecondary)
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                        .tint(Theme.accent)
                        .disabled(!canSave)
                }
            }
            .tint(Theme.accent)
            .onAppear {
                if !isEditing { nameFocused = true }
            }
        }
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
