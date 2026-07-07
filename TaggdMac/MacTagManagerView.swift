//
//  MacTagManagerView.swift
//  TaggdMac
//
//  Add, rename, delete, and reorder the tag library. Presented as the second
//  screen of the Settings window; `onBack` returns to the settings list. macOS
//  List has no EditButton/swipe-to-delete, so each row carries its own delete
//  button and reordering is drag-based via `.onMove`.
//

import SwiftUI

struct MacTagManagerView: View {
    @Environment(TagStore.self) private var store
    let onBack: () -> Void

    @State private var newTag = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Tags", leading: backButton) { EmptyView() }

            VStack(alignment: .leading, spacing: 10) {
                addRow

                Text("Your Tags")
                    .font(.mono(12, .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            tagList

            Spacer(minLength: 0)

            Text("Click a name to rename · drag to reorder · trash to delete.")
                .font(.mono(11))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    /// The tag rows as a single grouped card. Backed by a real `List` (clipped
    /// into the card shape) so native `.onMove` drag-reordering keeps working.
    @ViewBuilder
    private var tagList: some View {
        if store.tags.isEmpty {
            Text("No tags yet. Add one above.")
                .font(.mono(13))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(CardBackground())
                .padding(.horizontal, 16)
                .padding(.top, 8)
        } else {
            List {
                ForEach(store.tags) { tag in
                    TagRow(tag: tag,
                           onRename: { store.rename(tag.id, to: $0) },
                           onDelete: { delete(tag) })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    .listRowSeparatorTint(Theme.stroke)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 42)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .overlayScrollbars()
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Settings")
                    .font(.mono(14, .medium))
            }
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Settings")
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .foregroundStyle(Theme.accent)
            TextField(
                "",
                text: $newTag,
                prompt: Text("Add a tag").foregroundColor(Theme.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(.mono(14))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .autocorrectionDisabled()
            .focused($addFocused)
            .onSubmit(add)

            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(canAdd ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(CardBackground())
    }

    private var canAdd: Bool {
        !newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        store.add(newTag)
        newTag = ""
        addFocused = true
    }

    private func delete(_ tag: Tag) {
        if let index = store.tags.firstIndex(where: { $0.id == tag.id }) {
            store.remove(at: IndexSet(integer: index))
        }
    }
}

/// A single editable tag row. Local state so typing feels responsive; commits
/// to the store on change.
private struct TagRow: View {
    let tag: Tag
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var name: String

    init(tag: Tag, onRename: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.tag = tag
        self.onRename = onRename
        self.onDelete = onDelete
        _name = State(initialValue: tag.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("Tag name", text: $name)
                .textFieldStyle(.plain)
                .font(.mono(14))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .autocorrectionDisabled()
                .onChange(of: name) { _, newValue in onRename(newValue) }

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
