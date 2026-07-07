//
//  TagManagerView.swift
//  Taggd
//
//  Add, rename, delete, and reorder the tag library. Pushed from Settings.
//

import SwiftUI

struct TagManagerView: View {
    @Environment(TagStore.self) private var store
    @State private var newTag = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .foregroundStyle(Theme.accent)
                    TextField(
                        "",
                        text: $newTag,
                        prompt: Text("Add a tag").foregroundColor(Theme.textTertiary)
                    )
                    .font(.mono(15))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($addFocused)
                    .submitLabel(.done)
                    .onSubmit(add)

                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(canAdd ? Theme.accent : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                }
            }

            Section {
                if store.tags.isEmpty {
                    Text("No tags yet. Add one above.")
                        .font(.mono(13))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(store.tags) { tag in
                        TagRow(tag: tag) { store.rename(tag.id, to: $0) }
                    }
                    .onDelete { store.remove(at: $0) }
                    .onMove { store.move(from: $0, to: $1) }
                }
            } header: {
                Text("Your Tags")
            } footer: {
                Text("Tap a name to rename · swipe to delete · use Edit to reorder.")
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
}

/// A single editable tag row. Local state so typing feels responsive; commits to the store on change.
private struct TagRow: View {
    let tag: Tag
    let onRename: (String) -> Void
    @State private var name: String

    init(tag: Tag, onRename: @escaping (String) -> Void) {
        self.tag = tag
        self.onRename = onRename
        _name = State(initialValue: tag.name)
    }

    var body: some View {
        TextField("Tag name", text: $name)
            .font(.mono(15))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onChange(of: name) { _, newValue in onRename(newValue) }
    }
}
