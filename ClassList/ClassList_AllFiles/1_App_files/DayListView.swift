import SwiftUI

// Column widths for the table: P | F | Class | HW | Due
private enum Col {
    static let p: CGFloat = 34
    static let f: CGFloat = 76
    static let hw: CGFloat = 58
    static let due: CGFloat = 56
}

// MARK: - Day list

struct DayListView: View {
    @EnvironmentObject private var store: DataStore
    let listID: UUID

    struct EditTarget: Identifiable {
        let id: UUID
    }

    @State private var editMode = false
    @State private var collapsed: Set<UUID> = []
    @State private var editTarget: EditTarget?

    var body: some View {
        Group {
            if let list = store.list(withID: listID) {
                content(for: list)
            } else {
                Text("This list is no longer available.")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for list: DayList) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleRow(list)

                if list.isNoSchool {
                    noSchoolCard
                } else {
                    if editMode {
                        Text("Tap a class to change it.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                    table(list)
                    footer(list)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sheet(item: $editTarget) { target in
            if let current = store.list(withID: listID),
               let entry = current.entries.first(where: { $0.id == target.id }) {
                EditEntrySheet(listID: listID, original: entry, baseDate: current.date)
            }
        }
    }

    // MARK: Title

    private func titleRow(_ list: DayList) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(.largeTitle.bold())
                Text(list.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !list.isNoSchool {
                Button {
                    withAnimation { editMode.toggle() }
                } label: {
                    Image(systemName: editMode ? "checkmark" : "pencil")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(width: 42, height: 42)
                        .background(editMode ? Theme.accent : Theme.card, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noSchoolCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.largeTitle)
            Text("No school")
                .font(.title2.bold())
            Text("Nothing was tracked for this day.")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 28)
    }

    private func footer(_ list: DayList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if list.totalCount == 0 && list.skippedCount == 0 {
                Text("No homework for any class.")
            } else if list.skippedCount > 0 {
                Text("\(list.doneCount) of \(list.totalCount) finished  ·  \(list.skippedCount) not doing today")
            } else {
                Text("\(list.doneCount) of \(list.totalCount) finished")
            }
            Text("P = priority (1 is most important)   F = finished or not doing today (red –)")
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 4)
    }

    // MARK: Table

    private func table(_ list: DayList) -> some View {
        VStack(spacing: 0) {
            headerRow

            ForEach(list.entries) { entry in
                entryView(entry, list: list)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell("P", width: Col.p)
            headerCell("F", width: Col.f)
            Text("Class")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            headerCell("HW", width: Col.hw)
            headerCell("Due", width: Col.due)
        }
        .padding(.vertical, 10)
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.footnote.weight(.bold))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: width)
    }

    @ViewBuilder
    private func entryView(_ entry: ClassEntry, list: DayList) -> some View {
        let name = store.displayName(for: entry)

        Theme.line.frame(height: 1)

        if entry.assignments.isEmpty {
            emptyRow(entry, name: name)
        } else if entry.assignments.count == 1, let only = entry.assignments.first {
            assignmentRow(only, entry: entry, list: list, title: name, isSub: false)
        } else {
            groupRows(entry, list: list, name: name)
        }
    }

    // A class with nothing to do
    private func emptyRow(_ entry: ClassEntry, name: String) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Col.p, height: 1)
            Color.clear.frame(width: Col.f, height: 1)
            classCell(title: name, entry: entry, strike: false, chevron: nil, isSub: false)
            hwCell("No")
            Color.clear.frame(width: Col.due, height: 1)
        }
        .padding(.vertical, 12)
        .opacity(0.6)
    }

    // A class with 2 or more assignments: a summary row plus one row each
    @ViewBuilder
    private func groupRows(_ entry: ClassEntry, list: DayList, name: String) -> some View {
        let isCollapsed = collapsed.contains(entry.id)
        let unfinished = entry.assignments.filter { !$0.isFinished && !$0.isSkippedToday }
        let bestPriority = unfinished.compactMap { $0.priority }.min()
        let nextDue = unfinished.compactMap { $0.dueDate }.min()

        HStack(spacing: 0) {
            Text(bestPriority.map { "\($0)" } ?? "–")
                .font(.headline)
                .foregroundStyle(bestPriority == nil ? Theme.textSecondary : Theme.accent)
                .frame(width: Col.p, height: 34)

            Group {
                if entry.allDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.success)
                } else {
                    Text("\(entry.doneCount)/\(entry.activeCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: Col.f, height: 34)

            classCell(
                title: name,
                entry: entry,
                strike: entry.allDone,
                chevron: isCollapsed ? "chevron.down" : "chevron.up",
                isSub: false
            )

            hwCell("\(entry.assignments.count) items")
            dueCell(nextDue)
        }
        .padding(.vertical, 12)
        .opacity(entry.allDone ? 0.6 : 1)

        if !isCollapsed {
            ForEach(Array(entry.assignments.enumerated()), id: \.element.id) { index, item in
                let word = item.kind == .study ? "Test" : "Assignment"

                Theme.line.opacity(0.5)
                    .frame(height: 1)
                    .padding(.leading, Col.p + Col.f)

                assignmentRow(
                    item,
                    entry: entry,
                    list: list,
                    title: "↳ " + (item.trimmedTitle ?? "\(word) \(index + 1)"),
                    isSub: true
                )
            }
        }
    }

    // One assignment row (or the only row of a single-assignment class)
    private func assignmentRow(
        _ item: Assignment,
        entry: ClassEntry,
        list: DayList,
        title: String,
        isSub: Bool
    ) -> some View {
        HStack(spacing: 0) {
            priorityCell(item, total: list.totalCount)
            finishedCell(item)

            HStack(spacing: 0) {
                classCell(
                    title: title,
                    entry: entry,
                    strike: item.isFinished,
                    chevron: nil,
                    isSub: isSub,
                    caption: isSub ? nil : item.trimmedTitle,
                    subTime: isSub ? store.studySeconds(forAssignment: item.id) : nil
                )
                hwCell(item.kind.tableLabel)
                dueCell(item.dueDate)
            }
            .opacity((item.isFinished || item.isSkippedToday) ? 0.55 : 1)
        }
        .padding(.vertical, 12)
    }

    // MARK: Cells

    private func classCell(
        title: String,
        entry: ClassEntry,
        strike: Bool,
        chevron: String?,
        isSub: Bool,
        caption: String? = nil,
        subTime: Double? = nil
    ) -> some View {
        Button {
            classTapped(entry)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(isSub ? Font.subheadline : Font.body.weight(.semibold))
                        .foregroundStyle(isSub ? Theme.textSecondary : Color.white)
                        .strikethrough(strike)
                        .lineLimit(2)
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    if let seconds = (isSub ? subTime : studiedSeconds(for: entry)), seconds >= 30 {
                        StudyTimeTag(seconds: seconds)
                    }
                }
                if !isSub && title != String(entry.period) {
                    PeriodTag(period: entry.period)
                }
                if editMode {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
                if let chevron {
                    Image(systemName: chevron)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, isSub ? 22 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hwCell(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Col.hw)
    }

    private func dueCell(_ date: Date?) -> some View {
        Text(dueText(date))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Col.due)
    }

    private func dueText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.isToday ? "Today" : date.weekdayShort
    }

    private func priorityCell(_ item: Assignment, total: Int) -> some View {
        Menu {
            Button("None") {
                store.setPriority(nil, assignmentID: item.id, in: listID)
            }
            ForEach(1...max(1, min(total, 12)), id: \.self) { number in
                Button {
                    store.setPriority(number, assignmentID: item.id, in: listID)
                } label: {
                    if item.priority == number {
                        Label("\(number)", systemImage: "checkmark")
                    } else {
                        Text("\(number)")
                    }
                }
            }
        } label: {
            Text(item.priority.map { "\($0)" } ?? "–")
                .font(.headline)
                .foregroundStyle(item.priority == nil ? Theme.textSecondary : Theme.accent)
                .frame(width: Col.p, height: 34)
                .contentShape(Rectangle())
        }
    }

    // Check = finished, red minus = not doing this one today
    private func finishedCell(_ item: Assignment) -> some View {
        HStack(spacing: 0) {
            Button {
                store.toggleFinished(assignmentID: item.id, in: listID)
            } label: {
                Image(systemName: item.isFinished ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isFinished ? Theme.success : Theme.textSecondary)
                    .frame(width: 38, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.toggleSkipped(assignmentID: item.id, in: listID)
            } label: {
                Image(systemName: item.isSkippedToday ? "minus.circle.fill" : "minus.circle")
                    .font(.title2)
                    .foregroundStyle(item.isSkippedToday ? Theme.danger : Theme.textSecondary)
                    .frame(width: 38, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: Col.f)
    }

    // MARK: Actions

    private func classTapped(_ entry: ClassEntry) {
        if editMode {
            editTarget = EditTarget(id: entry.id)
        } else if entry.assignments.count > 1 {
            toggleCollapsed(entry.id)
        }
        // Stage 2 will add: tap a class to start a timer.
    }

    private func studiedSeconds(for entry: ClassEntry) -> Double? {
        guard let date = store.list(withID: listID)?.date else { return nil }
        return store.studySeconds(for: entry.classID, on: date)
    }

    private func toggleCollapsed(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if collapsed.contains(id) {
                collapsed.remove(id)
            } else {
                collapsed.insert(id)
            }
        }
    }
}

// MARK: - Edit one class

struct EditEntrySheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let listID: UUID
    let baseDate: Date

    @State private var draft: ClassEntry

    init(listID: UUID, original: ClassEntry, baseDate: Date) {
        self.listID = listID
        self.baseDate = baseDate
        _draft = State(initialValue: original)
    }

    private var days: [Date] {
        (0..<7).map { baseDate.startOfDay.adding(days: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.displayName(for: draft))
                        .font(.largeTitle.bold())

                    if draft.assignments.isEmpty {
                        Text("No homework for this class. Add something below if that changed.")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    ForEach($draft.assignments) { $item in
                        assignmentEditor($item)
                    }

                    HStack(spacing: 12) {
                        addButton("Add homework", kind: .homework)
                        addButton("Add study/test", kind: .study)
                    }
                }
                .padding(20)
            }
            .background { AppBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.replaceEntry(draft, in: listID)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func assignmentEditor(_ item: Binding<Assignment>) -> some View {
        let id = item.wrappedValue.id
        let isStudy = item.wrappedValue.kind == .study

        return VStack(alignment: .leading, spacing: 12) {
            TextField("Name (optional)", text: titleBinding(item))
                .font(.headline)

            HStack {
                Picker("Type", selection: item.kind) {
                    Text("Homework").tag(AssignmentKind.homework)
                    Text("Study / Test").tag(AssignmentKind.study)
                }
                .pickerStyle(.segmented)

                Button(role: .destructive) {
                    draft.assignments.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "trash")
                        .padding(.leading, 8)
                }
            }

            Text(isStudy ? "Test date" : "Due")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            DayChips(selection: item.dueDate, days: days)
        }
        .card()
    }

    private func titleBinding(_ item: Binding<Assignment>) -> Binding<String> {
        Binding(
            get: { item.wrappedValue.title ?? "" },
            set: { item.wrappedValue.title = $0.isEmpty ? nil : $0 }
        )
    }

    private func addButton(_ title: String, kind: AssignmentKind) -> some View {
        Button {
            draft.assignments.append(Assignment(kind: kind, dueDate: nil))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
