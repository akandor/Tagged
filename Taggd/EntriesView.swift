//
//  EntriesView.swift
//  Taggd
//
//  Read-only overview of the time entries stored on the server, grouped by day
//  inside a scrollable weekly list.
//

import SwiftUI

private enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

struct EntriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TagStore.self) private var tagStore

    @AppStorage("weekStartsOn") private var weekStart: WeekStart = .monday
    @AppStorage("workdays") private var workdays: Workdays = .mondayToFriday

    /// Anchor date for the visible week (any day inside it).
    @State private var anchor = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var entries: [TimeEntry] = []
    @State private var state: LoadState = .idle
    @State private var loadToken = 0
    @State private var editingEntry: TimeEntry?
    @State private var pendingDelete: TimeEntry?
    @State private var showNewEntry = false

    /// Gregorian calendar honoring the user's chosen first weekday.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = weekStart.rawValue
        return c
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    weekCard
                    entryList
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationTitle("Time Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                        .tint(Theme.textSecondary)
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Text("Time Entries")
                        .font(.mono(16, .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewEntry = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .tint(Theme.accent)
                    .accessibilityLabel("New entry")
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .task(id: loadToken) { await load() }
        .onChange(of: weekStart) { loadToken += 1 }
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(entry: entry) { loadToken += 1 }
                .environment(tagStore)
        }
        .sheet(isPresented: $showNewEntry) {
            NewEntrySheet(
                onStarted: { dismiss() },
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to this week")
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
        .background(cardBackground)
    }

    private func dayColumn(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isWorkday = workdays.isWorkday(calendar.component(.weekday, from: day))
        let total = dayTotal(day)
        // Non-work days are de-emphasized unless they hold time or are selected.
        let numberColor = isSelected
            ? Color.black
            : (isWorkday || total > 0 ? Theme.textPrimary : Theme.textTertiary)
        return Button {
            withAnimation(.snappy) { selectedDay = calendar.startOfDay(for: day) }
        } label: {
            VStack(spacing: 6) {
                Text(weekdaySymbol(day))
                    .font(.mono(10, .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                Text(dayNumber(day))
                    .font(.mono(19, .medium))
                    .foregroundStyle(numberColor)
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(Theme.accent)
                        }
                    }
                Text(total > 0 ? formatDuration(total) : "0:00")
                    .font(.mono(9, .regular))
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
        case .idle, .loading:
            loadingOrList
        case .failed(let message):
            errorState(message)
        case .loaded:
            loadingOrList
        }
    }

    @ViewBuilder
    private var loadingOrList: some View {
        if state == .loading && entries.isEmpty {
            Spacer()
            ProgressView().tint(Theme.accent)
            Spacer()
        } else if selectedEntries.isEmpty {
            emptyState
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
                        EntryRow(
                            entry: entry,
                            onResume: { resume(entry) },
                            onEdit: { editingEntry = entry },
                            onDelete: { pendingDelete = entry }
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            ContentUnavailableView {
                Label("No entries", systemImage: "tray")
            } description: {
                Text("Nothing tracked on \(dayHeaderLabel).")
                    .font(.mono(13, .regular))
            }
            Spacer()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack {
            Spacer()
            ContentUnavailableView {
                Label("Couldn't load entries", systemImage: "exclamationmark.icloud")
            } description: {
                Text(message).font(.mono(13, .regular))
            } actions: {
                Button("Try Again") { loadToken += 1 }
                    .font(.mono(14, .medium))
                    .tint(Theme.accent)
            }
            Spacer()
        }
    }

    // MARK: - Loading

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
    /// Won't clobber an in-progress session — it just returns to it.
    private func resume(_ entry: TimeEntry) {
        let tracker = TimeTracker.shared
        guard tracker.phase == .idle else { dismiss(); return }
        tracker.taskDescription = entry.text
        tracker.selectedTags = entry.tags.map { Tag(name: $0) }
        tracker.start()
        dismiss()
    }

    private func delete(_ entry: TimeEntry) async {
        guard let client = TimeTaggerClient.fromStoredSettings() else { return }
        // Optimistically drop it; reload reconciles with the server.
        entries.removeAll { $0.id == entry.id }
        _ = await client.deleteRecord(entry.record)
        loadToken += 1
    }

    private func shiftWeek(by delta: Int) {
        guard let moved = calendar.date(byAdding: .weekOfYear, value: delta, to: anchor) else { return }
        anchor = moved
        // Keep the selection on the same weekday within the new week.
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
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

// MARK: - Row

private struct EntryRow: View {
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
                    .font(.mono(15, .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(timeString(entry.end))
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.text.isEmpty ? "No description" : entry.text)
                    .font(.mono(15, .regular))
                    .foregroundStyle(entry.text.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            let tagColor = color(for: tag)
                            Text(tag)
                                .font(.mono(12, .medium))
                                .foregroundStyle(tagColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(tagColor.opacity(0.14))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(tagColor.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                Text(formatDuration(entry.duration))
                    .font(.mono(14, .medium))
                    .foregroundStyle(Theme.textSecondary)
                Menu {
                    Button { onResume() } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    Button { onEdit() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        // Force red: the view's accent tint otherwise recolors even
                        // destructive menu items.
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(Theme.danger)
                    }
                    .tint(Theme.danger)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private func timeString(_ date: Date) -> String {
        DateFormatter.cached("HH:mm").string(from: date)
    }
}

// MARK: - Edit sheet

private struct EditEntrySheet: View {
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
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        descriptionCard
                        tagsCard
                        timeCard
                        if let error {
                            Text(error)
                                .font(.mono(13, .regular))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Entry")
                        .font(.mono(16, .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                        .tint(Theme.textSecondary)
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                        .tint(Theme.accent)
                        .disabled(saving)
                        .accessibilityLabel("Save")
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .alert("New Tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Text("DESCRIPTION"))
            TextField(
                "",
                text: $text,
                prompt: Text("What were you working on?").foregroundColor(Theme.textTertiary),
                axis: .vertical
            )
            .font(.mono(16, .regular))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .lineLimit(1...6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(Text("TAGS"))
                Spacer()
                addTagMenu
            }
            if tags.isEmpty {
                Text("No tags.")
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        let tagColor = tagStore.tags.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }?.color ?? Theme.accent
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: 6) {
                                Text(tag).font(.mono(14, .medium))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(tagColor)
                            .padding(.leading, 12)
                            .padding(.trailing, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tagColor.opacity(0.14))
                                    .overlay(Capsule(style: .continuous).strokeBorder(tagColor.opacity(0.35), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var addTagMenu: some View {
        let taken = Set(tags.map { $0.lowercased() })
        let available = tagStore.tags.filter { !taken.contains($0.name.lowercased()) }
        return Menu {
            if !available.isEmpty {
                ForEach(available) { tag in
                    Button(tag.name) { withAnimation(.snappy) { addTag(tag.name) } }
                }
                Divider()
            }
            Button { showNewTag = true } label: { Label("New Tag…", systemImage: "plus") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                Text("Add").font(.mono(13, .medium))
            }
            .foregroundStyle(Theme.accent)
        }
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(Text("TIME"))
            DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                .font(.mono(14, .regular))
                .tint(Theme.accent)
            Divider().overlay(Theme.stroke)
            DatePicker("End", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                .font(.mono(14, .regular))
                .tint(Theme.accent)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(.mono(12, .medium))
            .tracking(1.5)
            .foregroundStyle(Theme.textTertiary)
    }

    private func addTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        tags.append(trimmed)
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !trimmed.isEmpty else { return }
        _ = tagStore.add(trimmed)   // remember it in the library too
        withAnimation(.snappy) { addTag(trimmed) }
    }

    private func save() async {
        guard end > start else {
            error = "End time must be after the start time."
            return
        }
        guard let client = TimeTaggerClient.fromStoredSettings() else {
            error = "No server is configured."
            return
        }
        saving = true
        error = nil
        let record = TimeTaggerClient.Record(
            key: entry.id,
            t1: Int(start.timeIntervalSince1970),
            t2: Int(end.timeIntervalSince1970),
            mt: Int(Date().timeIntervalSince1970),
            ds: composeDescription(text: text, tags: tags)
        )
        switch await client.pushRecords([record]) {
        case .success:
            onSaved()
            dismiss()
        case .unauthorized:
            error = "Your token was rejected. Check it in Settings."
        case .rejected(let message):
            error = message
        case .badURL:
            error = "The server address looks invalid."
        case .failure(let message):
            error = message
        }
        saving = false
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

// MARK: - New entry sheet

private struct NewEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TagStore.self) private var tagStore

    /// Called after a live session is started — the parent dismisses the whole
    /// overview so the user lands back on the running timer.
    let onStarted: () -> Void
    /// Called after a finished ("already done") entry is saved to reload the list.
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
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            modeCard
                            descriptionCard
                            tagsCard
                            if mode != .now { timeCard }
                            if let error {
                                Text(error)
                                    .font(.mono(13, .regular))
                                    .foregroundStyle(Theme.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(20)
                    }
                    actionButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Entry")
                        .font(.mono(16, .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                        .font(.mono(15, .regular))
                        .tint(Theme.textSecondary)
                        .accessibilityLabel("Close")
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .alert("New Tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Text("WHEN"))
            Picker("When", selection: $mode) {
                Text("Start now").tag(Mode.now)
                Text("Earlier").tag(Mode.earlier)
                Text("Done").tag(Mode.done)
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(Text("DESCRIPTION"))
            TextField(
                "",
                text: $text,
                prompt: Text("What are you working on?").foregroundColor(Theme.textTertiary),
                axis: .vertical
            )
            .font(.mono(16, .regular))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .lineLimit(1...6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(Text("TAGS"))
                Spacer()
                addTagMenu
            }
            if tags.isEmpty {
                Text("No tags yet.")
                    .font(.mono(13, .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        let tagColor = tagStore.tags.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }?.color ?? Theme.accent
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: 6) {
                                Text(tag).font(.mono(14, .medium))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(tagColor)
                            .padding(.leading, 12)
                            .padding(.trailing, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tagColor.opacity(0.14))
                                    .overlay(Capsule(style: .continuous).strokeBorder(tagColor.opacity(0.35), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var addTagMenu: some View {
        let taken = Set(tags.map { $0.lowercased() })
        let available = tagStore.tags.filter { !taken.contains($0.name.lowercased()) }
        return Menu {
            if !available.isEmpty {
                ForEach(available) { tag in
                    Button(tag.name) { withAnimation(.snappy) { addTag(tag.name) } }
                }
                Divider()
            }
            Button { showNewTag = true } label: { Label("New Tag…", systemImage: "plus") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                Text("Add").font(.mono(13, .medium))
            }
            .foregroundStyle(Theme.accent)
        }
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .earlier {
                sectionTitle(Text("STARTED AT"))
                DatePicker("Start", selection: $earlierStart, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .font(.mono(14, .regular))
            } else {
                sectionTitle(Text("TIME"))
                DatePicker("Start", selection: $doneStart, displayedComponents: [.date, .hourAndMinute])
                    .font(.mono(14, .regular))
                Divider().overlay(Theme.stroke)
                DatePicker("End", selection: $doneEnd, in: doneStart..., displayedComponents: [.date, .hourAndMinute])
                    .font(.mono(14, .regular))
            }
        }
        .tint(Theme.accent)
        .foregroundStyle(Theme.textPrimary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var actionButton: some View {
        Button(action: primaryAction) {
            Label(actionTitle, systemImage: mode == .done ? "checkmark" : "play.fill")
                .font(.mono(18, .semiBold))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .foregroundStyle(Color.black)
        .disabled(saving)
    }

    private var actionTitle: LocalizedStringKey {
        switch mode {
        case .now:     return "Start Now"
        case .earlier: return "Start"
        case .done:    return "Save Entry"
        }
    }

    // MARK: Actions

    private func primaryAction() {
        error = nil
        switch mode {
        case .now:
            startLive(at: Date())
        case .earlier:
            guard earlierStart <= Date() else {
                error = "The start time can't be in the future."
                return
            }
            startLive(at: earlierStart)
        case .done:
            Task { await saveDone() }
        }
    }

    private func startLive(at date: Date) {
        let tracker = TimeTracker.shared
        guard tracker.phase == .idle else {
            error = "A session is already running — stop it first."
            return
        }
        tracker.taskDescription = text
        tracker.selectedTags = tags.map { Tag(name: $0) }
        tracker.start(at: date)
        onStarted()
    }

    private func saveDone() async {
        guard doneEnd > doneStart else {
            error = "The end time must be after the start time."
            return
        }
        guard let client = TimeTaggerClient.fromStoredSettings() else {
            error = "No server is configured."
            return
        }
        saving = true
        error = nil
        let record = TimeTaggerClient.Record(
            key: TimeTaggerClient.generateKey(),
            t1: Int(doneStart.timeIntervalSince1970),
            t2: Int(doneEnd.timeIntervalSince1970),
            mt: Int(Date().timeIntervalSince1970),
            ds: composeDescription(text: text, tags: tags)
        )
        switch await client.pushRecords([record]) {
        case .success:
            onCreated()
            dismiss()
        case .unauthorized:
            error = "Your token was rejected. Check it in Settings."
        case .rejected(let message):
            error = message
        case .badURL:
            error = "The server address looks invalid."
        case .failure(let message):
            error = message
        }
        saving = false
    }

    private func sectionTitle(_ text: Text) -> some View {
        text
            .font(.mono(12, .medium))
            .tracking(1.5)
            .foregroundStyle(Theme.textTertiary)
    }

    private func addTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        tags.append(trimmed)
    }

    private func commitNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        guard !trimmed.isEmpty else { return }
        _ = tagStore.add(trimmed)
        withAnimation(.snappy) { addTag(trimmed) }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

#Preview {
    EntriesView()
        .environment(TagStore())
}
