//
//  MacEntriesView.swift
//  TaggdMac
//
//  Server-backed time-entries overview shown in a standalone window. Ported from
//  the iOS EntriesView with macOS-native chrome (in-content HeaderBar, bordered
//  buttons) and the shared entries model / preferences.
//

import SwiftUI
import AppKit

private enum MacLoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

struct MacEntriesView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(TagStore.self) private var tagStore

    let onClose: () -> Void

    @AppStorage("weekStartsOn") private var weekStart: WeekStart = .monday
    @AppStorage("workdays") private var workdays: Workdays = .mondayToFriday

    @State private var anchor = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var entries: [TimeEntry] = []
    @State private var state: MacLoadState = .idle
    @State private var loadToken = 0
    @State private var editingEntry: TimeEntry?
    @State private var pendingDelete: TimeEntry?
    @State private var showNewEntry = false

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = weekStart.rawValue
        return c
    }

    var body: some View {
        VStack(spacing: 16) {
            weekCard
            entryList
        }
        .padding(20)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .background(Theme.background)
        .overlay(alignment: .bottomTrailing) { addButton }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task(id: loadToken) { await load() }
        .onChange(of: weekStart) { loadToken += 1 }
        .sheet(item: $editingEntry) { entry in
            MacEditEntrySheet(entry: entry) { loadToken += 1 }
                .environment(tagStore)
        }
        .sheet(isPresented: $showNewEntry) {
            MacNewEntrySheet(
                tracker: tracker,
                onStarted: { onClose() },
                onCreated: { loadToken += 1 }
            )
            .environment(tagStore)
        }
        .alert(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { Task { await delete(entry) } }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This removes it from the server and can't be undone here.")
        }
    }

    // MARK: - Week card

    private var days: [Date] {
        let start = weekStartDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekStartDate: Date {
        calendar.dateInterval(of: .weekOfYear, for: anchor)?.start
            ?? calendar.startOfDay(for: anchor)
    }

    private var weekCard: some View {
        VStack(spacing: 14) {
            HStack {
                circleButton("chevron.left") { shiftWeek(by: -1) }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: goToToday) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to this week")
                    Text(weekRangeLabel)
                        .font(.mono(14, .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                circleButton("chevron.right") { shiftWeek(by: 1) }
            }

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    dayColumn(day)
                }
            }

            Divider().overlay(Theme.stroke)

            HStack {
                Text("Total")
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(formatDuration(weekTotal))
                    .font(.mono(15, .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .background(CardBackground())
    }

    private func dayColumn(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isWorkday = workdays.isWorkday(calendar.component(.weekday, from: day))
        let total = dayTotal(day)
        let numberColor = isSelected
            ? Color.black
            : (isWorkday || total > 0 ? Theme.textPrimary : Theme.textTertiary)
        return Button {
            withAnimation(.snappy) { selectedDay = calendar.startOfDay(for: day) }
        } label: {
            VStack(spacing: 6) {
                Text(weekdaySymbol(day))
                    .font(.mono(12, .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                Text(dayNumber(day))
                    .font(.mono(19, .medium))
                    .foregroundStyle(numberColor)
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected { Circle().fill(Theme.accent) }
                    }
                Text(total > 0 ? formatDuration(total) : "0:00")
                    .font(.mono(12, .regular))
                    .foregroundStyle(total > 0 ? Theme.textSecondary : Theme.textTertiary)
                Circle()
                    .fill(total > 0 ? Theme.accent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entry list

    private var selectedEntries: [TimeEntry] {
        entries
            .filter { calendar.isDate($0.start, inSameDayAs: selectedDay) }
            .sorted { $0.start < $1.start }
    }

    @ViewBuilder
    private var entryList: some View {
        switch state {
        case .failed(let message):
            placeholder("exclamationmark.icloud", "Couldn't load entries", message) {
                Button("Try Again") { loadToken += 1 }
                    .font(.mono(13, .medium))
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
            }
        case .loading where entries.isEmpty:
            Spacer()
            ProgressView().tint(Theme.accent)
            Spacer()
        default:
            if selectedEntries.isEmpty {
                placeholder("tray", "No entries", "Nothing tracked on \(dayHeaderLabel).") { EmptyView() }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        HStack {
                            Text(dayHeaderLabel)
                                .font(.mono(14, .regular))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(formatDuration(dayTotal(selectedDay)))
                                .font(.mono(14, .regular))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(selectedEntries) { entry in
                            MacEntryRow(
                                entry: entry,
                                onResume: { resume(entry) },
                                onEdit: { editingEntry = entry },
                                onDelete: { pendingDelete = entry }
                            )
                        }
                    }
                    .padding(.bottom, 8)
                }
                .overlayScrollbars()
            }
        }
    }

    private func placeholder<Action: View>(
        _ icon: String, _ title: LocalizedStringKey, _ message: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.mono(15, .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.mono(12, .regular))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            action()
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading & actions

    private func load() async {
        guard let client = TimeTaggerClient.fromStoredSettings() else {
            state = .failed("Connect a server in Settings to see your entries.")
            return
        }
        state = .loading
        let start = Int(weekStartDate.timeIntervalSince1970)
        let end = Int((calendar.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate).timeIntervalSince1970)
        switch await client.fetchRecords(from: start, to: end) {
        case .success(let records):
            entries = records.map(TimeEntry.init)
            state = .loaded
        case .unauthorized:
            state = .failed("Your token was rejected. Check it in Settings.")
        case .badURL:
            state = .failed("The server address looks invalid.")
        case .failure(let message):
            state = .failed(message)
        }
    }

    private func goToToday() {
        anchor = Date()
        selectedDay = calendar.startOfDay(for: Date())
        loadToken += 1
    }

    /// Starts a fresh session pre-filled with this entry's description and tags.
    private func resume(_ entry: TimeEntry) {
        guard tracker.phase == .idle else { onClose(); return }
        tracker.taskDescription = entry.text
        tracker.selectedTags = entry.tags.map { Tag(name: $0) }
        tracker.start()
        onClose()
    }

    private func delete(_ entry: TimeEntry) async {
        guard let client = TimeTaggerClient.fromStoredSettings() else { return }
        entries.removeAll { $0.id == entry.id }
        _ = await client.deleteRecord(entry.record)
        loadToken += 1
    }

    private func shiftWeek(by delta: Int) {
        guard let moved = calendar.date(byAdding: .weekOfYear, value: delta, to: anchor) else { return }
        anchor = moved
        let newStart = calendar.dateInterval(of: .weekOfYear, for: moved)?.start ?? moved
        let offset = calendar.dateComponents([.day], from: weekStartDate, to: selectedDay).day ?? 0
        selectedDay = calendar.date(byAdding: .day, value: max(0, min(6, offset)), to: newStart) ?? newStart
        loadToken += 1
    }

    // MARK: - Aggregates

    private func dayTotal(_ day: Date) -> TimeInterval {
        entries
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + $1.duration }
    }

    private var weekTotal: TimeInterval {
        days.reduce(0) { $0 + dayTotal($1) }
    }

    // MARK: - Formatting

    private var weekRangeLabel: String {
        guard let last = days.last else { return "" }
        let first = weekStartDate
        let yearFmt = DateFormatter.cached("yyyy")
        let monthDay = DateFormatter.cached("MMM d")
        let dayOnly = DateFormatter.cached("d")
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let left = monthDay.string(from: first)
        let right = sameMonth ? dayOnly.string(from: last) : monthDay.string(from: last)
        return "\(left) – \(right), \(yearFmt.string(from: last))"
    }

    private var dayHeaderLabel: String {
        DateFormatter.cached("EEEE, MMM d").string(from: selectedDay)
    }

    private func weekdaySymbol(_ day: Date) -> String {
        DateFormatter.cached("EEE").string(from: day).uppercased()
    }

    private func dayNumber(_ day: Date) -> String {
        DateFormatter.cached("d").string(from: day)
    }

    private func circleButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }

    /// A big round "New entry" button, floating in the bottom-trailing corner.
    private var addButton: some View {
        RoundActionButton(systemImage: "plus", help: "New entry") {
            showNewEntry = true
        }
    }
}

// MARK: - Row

private struct MacEntryRow: View {
    @Environment(TagStore.self) private var tagStore
    let entry: TimeEntry
    let onResume: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// The library color for a tag name, falling back to the accent for unknown tags.
    private func color(for tag: String) -> Color {
        tagStore.tags.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }?.color ?? Theme.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(timeString(entry.start))
                    .font(.mono(14, .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(timeString(entry.end))
                    .font(.mono(12, .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.text.isEmpty ? "No description" : entry.text)
                    .font(.mono(14, .regular))
                    .foregroundStyle(entry.text.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            let tagColor = color(for: tag)
                            Text(tag)
                                .font(.mono(11, .medium))
                                .foregroundStyle(tagColor)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(tagColor.opacity(0.14))
                                        .overlay(Capsule(style: .continuous).strokeBorder(tagColor.opacity(0.3), lineWidth: 1))
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatDuration(entry.duration))
                .font(.mono(13, .medium))
                .foregroundStyle(Theme.textSecondary)

            Menu {
                Button { onResume() } label: { Label("Resume", systemImage: "play.fill") }
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash").foregroundStyle(Theme.danger)
                }
                .tint(Theme.danger)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(14)
        .background(CardBackground())
    }

    private func timeString(_ date: Date) -> String {
        DateFormatter.cached("HH:mm").string(from: date)
    }
}

// MARK: - Tag editing (shared by New/Edit sheets)

private struct MacTagEditor: View {
    @Binding var tags: [String]
    let library: [Tag]
    @Binding var showNewTag: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("TAGS")
                Spacer()
                addMenu
            }
            if tags.isEmpty {
                Text("No tags yet.")
                    .font(.mono(12, .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        let libraryTag = library.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }
                        TagChip(tag: libraryTag ?? Tag(name: tag)) { tags.removeAll { $0 == tag } }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private var addMenu: some View {
        let taken = Set(tags.map { $0.lowercased() })
        let available = library.filter { !taken.contains($0.name.lowercased()) }
        return Menu {
            if !available.isEmpty {
                ForEach(available) { tag in
                    Button(tag.name) { add(tag.name) }
                }
                Divider()
            }
            Button { showNewTag = true } label: { Label("New Tag…", systemImage: "plus") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                Text("Add").font(.mono(12, .medium))
            }
            .foregroundStyle(Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        tags.append(trimmed)
    }
}

private func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.mono(11, .medium))
        .tracking(1.5)
        .foregroundStyle(Theme.textTertiary)
}

// MARK: - Edit sheet

private struct MacEditEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TagStore.self) private var tagStore

    let entry: TimeEntry
    let onSaved: () -> Void

    @State private var text: String
    @State private var tags: [String]
    @State private var start: Date
    @State private var end: Date
    @State private var saving = false
    @State private var error: String?
    @State private var showNewTag = false
    @State private var newTagName = ""

    init(entry: TimeEntry, onSaved: @escaping () -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        _text = State(initialValue: entry.text)
        _tags = State(initialValue: entry.tags)
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end)
    }

    var body: some View {
        SheetScaffold(
            title: "Edit Entry",
            confirmTitle: "Save",
            saving: saving,
            onCancel: { dismiss() },
            onConfirm: { Task { await save() } }
        ) {
            descriptionCard(text: $text, prompt: "What were you working on?")
            MacTagEditor(tags: $tags, library: tagStore.tags, showNewTag: $showNewTag)
            timeCard
            errorText(error)
        }
        .alert("New Tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("TIME")
            dateRow("Start", selection: $start)
            Divider().overlay(Theme.stroke)
            dateRow("End", selection: $end, in: start...)
        }
        .tint(Theme.accent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !trimmed.isEmpty else { return }
        _ = tagStore.add(trimmed)
        if !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            tags.append(trimmed)
        }
    }

    private func save() async {
        guard end > start else { error = "The end time must be after the start time."; return }
        guard let client = TimeTaggerClient.fromStoredSettings() else { error = "No server is configured."; return }
        saving = true
        error = nil
        let record = TimeTaggerClient.Record(
            key: entry.id,
            t1: Int(start.timeIntervalSince1970),
            t2: Int(end.timeIntervalSince1970),
            mt: Int(Date().timeIntervalSince1970),
            ds: composeDescription(text: text, tags: tags)
        )
        error = await push(record, client: client)
        saving = false
        if error == nil { onSaved(); dismiss() }
    }
}

// MARK: - New sheet

private struct MacNewEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TagStore.self) private var tagStore

    let tracker: TimeTracker
    let onStarted: () -> Void
    let onCreated: () -> Void

    private enum Mode: Hashable { case now, earlier, done }

    @State private var mode: Mode = .now
    @State private var text = ""
    @State private var tags: [String] = []
    @State private var earlierStart = Date()
    @State private var doneStart = Date().addingTimeInterval(-3600)
    @State private var doneEnd = Date()
    @State private var saving = false
    @State private var error: String?
    @State private var showNewTag = false
    @State private var newTagName = ""

    var body: some View {
        SheetScaffold(
            title: "New Entry",
            confirmTitle: confirmTitle,
            confirmIcon: mode == .done ? "checkmark" : "play.fill",
            saving: saving,
            onCancel: { dismiss() },
            onConfirm: primaryAction
        ) {
            modeCard
            descriptionCard(text: $text, prompt: "What are you working on?")
            MacTagEditor(tags: $tags, library: tagStore.tags, showNewTag: $showNewTag)
            if mode != .now { timeCard }
            errorText(error)
        }
        .alert("New Tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("WHEN")
            Picker("When", selection: $mode) {
                Text("Start now").tag(Mode.now)
                Text("Earlier").tag(Mode.earlier)
                Text("Done").tag(Mode.done)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .earlier {
                sectionTitle("STARTED AT")
                dateRow("Start", selection: $earlierStart, in: ...Date())
            } else {
                sectionTitle("TIME")
                dateRow("Start", selection: $doneStart)
                Divider().overlay(Theme.stroke)
                dateRow("End", selection: $doneEnd, in: doneStart...)
            }
        }
        .tint(Theme.accent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }

    private var confirmTitle: LocalizedStringKey {
        switch mode {
        case .now:     return "Start Now"
        case .earlier: return "Start"
        case .done:    return "Save Entry"
        }
    }

    private func primaryAction() {
        error = nil
        switch mode {
        case .now:
            startLive(at: Date())
        case .earlier:
            guard earlierStart <= Date() else { error = "The start time can't be in the future."; return }
            startLive(at: earlierStart)
        case .done:
            Task { await saveDone() }
        }
    }

    private func startLive(at date: Date) {
        guard tracker.phase == .idle else { error = "A session is already running — stop it first."; return }
        tracker.taskDescription = text
        tracker.selectedTags = tags.map { Tag(name: $0) }
        tracker.start(at: date)
        dismiss()
        onStarted()
    }

    private func saveDone() async {
        guard doneEnd > doneStart else { error = "The end time must be after the start time."; return }
        guard let client = TimeTaggerClient.fromStoredSettings() else { error = "No server is configured."; return }
        saving = true
        error = nil
        let record = TimeTaggerClient.Record(
            key: TimeTaggerClient.generateKey(),
            t1: Int(doneStart.timeIntervalSince1970),
            t2: Int(doneEnd.timeIntervalSince1970),
            mt: Int(Date().timeIntervalSince1970),
            ds: composeDescription(text: text, tags: tags)
        )
        error = await push(record, client: client)
        saving = false
        if error == nil { onCreated(); dismiss() }
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !trimmed.isEmpty else { return }
        _ = tagStore.add(trimmed)
        if !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            tags.append(trimmed)
        }
    }
}

// MARK: - Sheet scaffolding & shared bits

/// A titled sheet with Cancel / confirm buttons and a scrolling card body, sized
/// for the window-hosted macOS presentation. The title and button areas share
/// the sheet's background color (no dividers) so they blend into one surface.
struct SheetScaffold<Content: View>: View {
    let title: String
    var confirmTitle: LocalizedStringKey
    var confirmIcon: String? = nil
    var saving: Bool
    var width: CGFloat = 460
    var height: CGFloat = 560
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — same color as the sheet, no divider so it blends in.
            Text(title)
                .font(.mono(15, .semiBold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 16) {
                    content()
                }
                .padding(20)
            }
            .overlayScrollbars()

            // Action bar — native buttons, same color as the sheet, no divider.
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(action: onConfirm) {
                    HStack(spacing: 6) {
                        if let confirmIcon { Image(systemName: confirmIcon) }
                        Text(confirmTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .tint(Theme.accent)
                .disabled(saving)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: width, height: height)
        .background(Theme.background)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

private func descriptionCard(text: Binding<String>, prompt: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        sectionTitle("DESCRIPTION")
        TextField(
            "",
            text: text,
            prompt: Text(prompt).foregroundColor(Theme.textTertiary),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.mono(15, .regular))
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .lineLimit(1...6)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CardBackground())
}

/// A labelled date/time row
private func dateRow(_ label: LocalizedStringKey, selection: Binding<Date>) -> some View {
    dateRowBody(label) {
        MacDatePickerField(selection: selection)
    }
}

private func dateRow(_ label: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>) -> some View {
    dateRowBody(label) {
        MacDatePickerField(selection: selection, lowerBound: range)
    }
}

private func dateRow(_ label: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>) -> some View {
    dateRowBody(label) {
        MacDatePickerField(selection: selection, upperBound: range)
    }
}

private func dateRowBody<P: View>(_ label: LocalizedStringKey, @ViewBuilder _ picker: () -> P) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(label)
            .font(.mono(13, .regular))
            .foregroundStyle(Theme.textSecondary)

        Spacer(minLength: 20)

        picker()
    }
    .padding(.vertical, 4)
}

/// Date + time shown as two separate pills, mirroring the iOS compact
/// `DatePicker`. Each pill opens its own native picker in a popover.
private struct MacDatePickerField: View {
    @Binding var selection: Date
    var lowerBound: PartialRangeFrom<Date>? = nil
    var upperBound: PartialRangeThrough<Date>? = nil

    var body: some View {
        HStack(spacing: 8) {
            DatePill(kind: .date, selection: $selection, lowerBound: lowerBound, upperBound: upperBound)
            DatePill(kind: .time, selection: $selection, lowerBound: lowerBound, upperBound: upperBound)
        }
    }
}

/// A single pill (date or time) that reveals the matching native picker on click.
private struct DatePill: View {
    enum Kind { case date, time }

    let kind: Kind
    @Binding var selection: Date
    var lowerBound: PartialRangeFrom<Date>? = nil
    var upperBound: PartialRangeThrough<Date>? = nil
    @State private var showing = false

    private var label: String {
        switch kind {
        case .date: return selection.formatted(date: .abbreviated, time: .omitted)
        case .time: return selection.formatted(date: .omitted, time: .shortened)
        }
    }

    private var components: DatePickerComponents {
        kind == .date ? [.date] : [.hourAndMinute]
    }

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Text(label)
                .font(.mono(13, .medium))
                .foregroundStyle(showing ? Theme.accent : Theme.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(showing ? Theme.accent.opacity(0.16) : Theme.surfaceRaised)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing) {
            // Graphical calendar for the date; a precise, typeable stepper field
            // for the time (the macOS graphical clock is imprecise for minutes).
            Group {
                if kind == .date {
                    picker.datePickerStyle(.graphical)
                } else {
                    picker
                        .datePickerStyle(.stepperField)
                        .controlSize(.large)
                }
            }
            .labelsHidden()
            .padding()
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let lowerBound {
            DatePicker("", selection: $selection, in: lowerBound, displayedComponents: components)
        } else if let upperBound {
            DatePicker("", selection: $selection, in: upperBound, displayedComponents: components)
        } else {
            DatePicker("", selection: $selection, displayedComponents: components)
        }
    }
}

@ViewBuilder
private func errorText(_ error: String?) -> some View {
    if let error {
        Text(error)
            .font(.mono(12, .regular))
            .foregroundStyle(Theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pushes a record and maps the result to an optional error message (nil = ok).
private func push(_ record: TimeTaggerClient.Record, client: TimeTaggerClient) async -> String? {
    switch await client.pushRecords([record]) {
    case .success:               return nil
    case .unauthorized:          return "Your token was rejected. Check it in Settings."
    case .rejected(let message): return message
    case .badURL:                return "The server address looks invalid."
    case .failure(let message):  return message
    }
}
