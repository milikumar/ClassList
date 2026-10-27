import SwiftUI
import Combine

// MARK: - Date helpers

nonisolated extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isYesterday: Bool { Calendar.current.isDateInYesterday(self) }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    var weekdayName: String { formatted(.dateTime.weekday(.wide)) }
    var weekdayShort: String { formatted(.dateTime.weekday(.abbreviated)) }
}

// MARK: - Models

nonisolated enum AssignmentKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case homework
    case study

    var id: String { rawValue }

    /// What shows in the HW column of the table.
    var tableLabel: String { self == .homework ? "Yes" : "Study" }
}

/// One of your classes (period 1, 2, 3...).
nonisolated struct SchoolClass: Identifiable, Codable, Hashable {
    var id = UUID()
    var period: Int
    var name: String = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What shows in the table: the name, or just the period number.
    var displayName: String { trimmedName.isEmpty ? "\(period)" : trimmedName }

    /// Big title used when asking about the class.
    var flowTitle: String { trimmedName.isEmpty ? "Period \(period)" : trimmedName }

    /// Small line above the title (only when the class has a name).
    var flowSubtitle: String? { trimmedName.isEmpty ? nil : "Period \(period)" }
}

/// A single homework assignment or test to study for.
nonisolated struct Assignment: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: AssignmentKind
    var dueDate: Date?
    var priority: Int?
    var isFinished = false
    /// true = "I'm not doing this one today" (left out of the done count)
    var skippedToday: Bool?
    /// An optional name you give it, like "Chapter 3 worksheet".
    var title: String?

    var isSkippedToday: Bool { skippedToday ?? false }

    var trimmedTitle: String? {
        let cleaned = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Its name, or "Homework 2" / "Study / test 1" if you didn't name it.
    func label(index: Int, of count: Int) -> String {
        if let trimmedTitle { return trimmedTitle }
        let base = kind == .study ? "Study / test" : "Homework"
        return count > 1 ? "\(base) \(index + 1)" : base
    }
}

/// One class's row in a day's list. No assignments = "No homework".
nonisolated struct ClassEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var classID: UUID
    var nameSnapshot: String
    var period: Int
    var assignments: [Assignment] = []
    /// true = "I didn't have this class today" (different from "no homework")
    var noClass: Bool?

    var didntHaveClass: Bool { noClass ?? false }
    /// Assignments you're actually doing today (skipped ones don't count).
    var activeCount: Int { assignments.filter { !$0.isSkippedToday }.count }
    var doneCount: Int { assignments.filter { $0.isFinished }.count }
    var allDone: Bool { activeCount > 0 && doneCount == activeCount }
}

/// Everything for one day.
nonisolated struct DayList: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var isNoSchool = false
    var entries: [ClassEntry] = []

    /// Everything you're doing today (assignments marked "not today" are left out).
    var totalCount: Int { entries.reduce(0) { $0 + $1.activeCount } }
    var doneCount: Int { entries.reduce(0) { $0 + $1.doneCount } }
    var skippedCount: Int {
        entries.reduce(0) { $0 + ($1.assignments.count - $1.activeCount) }
    }

    var title: String {
        if date.isToday { return "Today's List" }
        if date.isYesterday { return "Yesterday's List" }
        return date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }

    var subtitle: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// One class meeting on one weekday (1 = Sunday ... 7 = Saturday).
nonisolated struct ScheduleSlot: Identifiable, Codable, Hashable {
    var id = UUID()
    var classID: UUID
    var weekday: Int
    var startMinutes: Int   // minutes after midnight
    var endMinutes: Int
}

/// A named schedule you can switch to, like "Normal week" or "Short week".
nonisolated struct SavedSchedule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var slots: [ScheduleSlot]
}

/// One finished study session for a class on a day.
nonisolated struct StudyLog: Identifiable, Codable, Hashable {
    var id = UUID()
    var classID: UUID
    var date: Date          // start of the day the session began
    var studySeconds: Double
    var breakSeconds: Double
    /// Which assignment the timer was for (nil = just the class).
    var assignmentID: UUID?
}

// MARK: - Store (saves automatically)

@MainActor
final class DataStore: ObservableObject {
    @Published var classes: [SchoolClass] {
        didSet { save(classes, key: Keys.classes) }
    }

    @Published var lists: [DayList] {
        didSet { save(lists, key: Keys.lists) }
    }

    /// The schedule that's in use right now (a working copy of the active saved schedule).
    @Published var schedule: [ScheduleSlot] {
        didSet {
            save(schedule, key: Keys.schedule)
            syncActiveSchedule()
        }
    }

    @Published var savedSchedules: [SavedSchedule] {
        didSet { save(savedSchedules, key: Keys.savedSchedules) }
    }

    @Published var activeScheduleID: UUID? {
        didSet { UserDefaults.standard.set(activeScheduleID?.uuidString, forKey: Keys.activeSchedule) }
    }

    @Published var studyLogs: [StudyLog] {
        didSet { save(studyLogs, key: Keys.studyLogs) }
    }

    private enum Keys {
        static let classes = "classlist.classes"
        static let lists = "classlist.lists"
        static let schedule = "classlist.schedule"
        static let savedSchedules = "classlist.savedSchedules"
        static let activeSchedule = "classlist.activeSchedule"
        static let studyLogs = "classlist.studyLogs"
    }

    init() {
        classes = DataStore.load([SchoolClass].self, key: Keys.classes) ?? []
        lists = DataStore.load([DayList].self, key: Keys.lists) ?? []
        let loadedSlots = DataStore.load([ScheduleSlot].self, key: Keys.schedule) ?? []
        var sets = DataStore.load([SavedSchedule].self, key: Keys.savedSchedules) ?? []
        var activeID = UserDefaults.standard
            .string(forKey: Keys.activeSchedule)
            .flatMap { UUID(uuidString: $0) }

        if sets.isEmpty {
            // First time with named schedules: keep the schedule you already entered.
            let first = SavedSchedule(name: "My schedule", slots: loadedSlots)
            sets = [first]
            activeID = first.id
        }
        if activeID == nil || !sets.contains(where: { $0.id == activeID }) {
            activeID = sets[0].id
        }

        savedSchedules = sets
        activeScheduleID = activeID
        schedule = sets.first(where: { $0.id == activeID })?.slots ?? loadedSlots
        studyLogs = DataStore.load([StudyLog].self, key: Keys.studyLogs) ?? []
    }

    // MARK: Saving / loading

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: Classes

    func setClasses(names: [String]) {
        var result: [SchoolClass] = []
        for (index, name) in names.enumerated() {
            result.append(SchoolClass(period: index + 1, name: name))
        }
        classes = result
    }

    func resizeClasses(to count: Int) {
        let target = max(1, min(count, 10))
        var updated = classes
        if target > updated.count {
            for period in (updated.count + 1)...target {
                updated.append(SchoolClass(period: period))
            }
        } else if target < updated.count {
            updated.removeLast(updated.count - target)
        }
        classes = updated
        let validIDs = Set(updated.map { $0.id })
        schedule.removeAll { !validIDs.contains($0.classID) }
    }

    func displayName(for entry: ClassEntry) -> String {
        classes.first(where: { $0.id == entry.classID })?.displayName ?? entry.nameSnapshot
    }

    // MARK: Schedule

    var activeScheduleName: String {
        savedSchedules.first(where: { $0.id == activeScheduleID })?.name ?? "My schedule"
    }

    /// Keeps the saved copy of the active schedule matching what you're editing.
    private func syncActiveSchedule() {
        guard let id = activeScheduleID,
              let index = savedSchedules.firstIndex(where: { $0.id == id }) else { return }
        if savedSchedules[index].slots != schedule {
            savedSchedules[index].slots = schedule
        }
    }

    func switchSchedule(to id: UUID) {
        guard let target = savedSchedules.first(where: { $0.id == id }) else { return }
        // Set the active one first so the edit below is saved into the right schedule.
        activeScheduleID = id
        let validIDs = Set(classes.map { $0.id })
        schedule = target.slots.filter { validIDs.contains($0.classID) }
    }

    func createSchedule(named name: String, copyCurrent: Bool) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var slots: [ScheduleSlot] = []
        if copyCurrent {
            for slot in schedule {
                slots.append(
                    ScheduleSlot(
                        classID: slot.classID,
                        weekday: slot.weekday,
                        startMinutes: slot.startMinutes,
                        endMinutes: slot.endMinutes
                    )
                )
            }
        }

        let newSchedule = SavedSchedule(name: cleaned.isEmpty ? "New schedule" : cleaned, slots: slots)
        savedSchedules.append(newSchedule)
        activeScheduleID = newSchedule.id
        schedule = newSchedule.slots
    }

    func renameSchedule(_ id: UUID, to name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let index = savedSchedules.firstIndex(where: { $0.id == id }) else { return }
        savedSchedules[index].name = cleaned
    }

    func deleteSchedule(_ id: UUID) {
        guard savedSchedules.count > 1 else { return }
        savedSchedules.removeAll { $0.id == id }
        if activeScheduleID == id, let first = savedSchedules.first {
            switchSchedule(to: first.id)
        }
    }

    /// Adds times read from a picture. It replaces whatever was on the chosen days.
    func importSlots(_ items: [(classID: UUID, start: Int, end: Int)], onWeekdays days: Set<Int>) {
        var updated = schedule.filter { !days.contains($0.weekday) }
        for day in days.sorted() {
            for item in items {
                updated.append(
                    ScheduleSlot(
                        classID: item.classID,
                        weekday: day,
                        startMinutes: item.start,
                        endMinutes: max(item.end, item.start + 1)
                    )
                )
            }
        }
        schedule = updated
    }

    func slots(on date: Date) -> [ScheduleSlot] {
        let weekday = Calendar.current.component(.weekday, from: date)
        return schedule
            .filter { $0.weekday == weekday }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Classes that meet on a day. With no schedule entered for that day, that's every class.
    func classesMeeting(on date: Date) -> [SchoolClass] {
        let daySlots = slots(on: date)
        if daySlots.isEmpty { return classes }
        let ids = Set(daySlots.map { $0.classID })
        let meeting = classes.filter { ids.contains($0.id) }
        return meeting.isEmpty ? classes : meeting
    }

    func isLogged(_ classID: UUID, on date: Date) -> Bool {
        guard let day = list(for: date) else { return false }
        return day.entries.contains { $0.classID == classID }
    }

    func unloggedClasses(on date: Date) -> [SchoolClass] {
        classes.filter { !isLogged($0.id, on: date) }
    }

    func addSlot(weekday: Int) {
        let existing = schedule
            .filter { $0.weekday == weekday }
            .sorted { $0.startMinutes < $1.startMinutes }
        let used = Set(existing.map { $0.classID })
        guard let nextClass = classes.first(where: { !used.contains($0.id) }) ?? classes.first else { return }

        let previousEnd = existing.last?.endMinutes ?? (8 * 60 - 5)
        let start = min(previousEnd + 5, 22 * 60)
        let end = min(start + 50, 23 * 60 + 59)
        schedule.append(
            ScheduleSlot(classID: nextClass.id, weekday: weekday, startMinutes: start, endMinutes: end)
        )
    }

    func updateSlot(_ id: UUID, _ change: (inout ScheduleSlot) -> Void) {
        guard let index = schedule.firstIndex(where: { $0.id == id }) else { return }
        var copy = schedule[index]
        change(&copy)
        schedule[index] = copy
    }

    func removeSlot(_ id: UUID) {
        schedule.removeAll { $0.id == id }
    }

    func copySchedule(from source: Int, to target: Int) {
        var copies: [ScheduleSlot] = []
        for slot in schedule where slot.weekday == source {
            copies.append(
                ScheduleSlot(
                    classID: slot.classID,
                    weekday: target,
                    startMinutes: slot.startMinutes,
                    endMinutes: slot.endMinutes
                )
            )
        }
        var updated = schedule.filter { $0.weekday != target }
        updated.append(contentsOf: copies)
        schedule = updated
    }

    /// Changes only when a class is logged or a day is marked "no school"
    /// (not on every checkbox tap), so reminders are refreshed at the right times.
    var loggedSignature: [String] {
        var keys: [String] = []
        for list in lists {
            let stamp = Int(list.date.timeIntervalSince1970)
            keys.append("\(stamp)|noSchool:\(list.isNoSchool)")
            for entry in list.entries {
                keys.append("\(stamp)|\(entry.classID.uuidString)")
            }
        }
        return keys
    }

    // MARK: Study time

    func addStudyLog(classID: UUID, assignmentID: UUID?, date: Date, study: Double, breaks: Double) {
        studyLogs.append(
            StudyLog(
                classID: classID,
                date: date.startOfDay,
                studySeconds: study,
                breakSeconds: breaks,
                assignmentID: assignmentID
            )
        )
    }

    func studySeconds(forAssignment id: UUID) -> Double {
        studyLogs
            .filter { $0.assignmentID == id }
            .reduce(0) { $0 + $1.studySeconds }
    }

    func studySeconds(for classID: UUID, on date: Date) -> Double {
        studyLogs
            .filter { $0.classID == classID && $0.date.isSameDay(as: date) }
            .reduce(0) { $0 + $1.studySeconds }
    }

    func breakSeconds(for classID: UUID, on date: Date) -> Double {
        studyLogs
            .filter { $0.classID == classID && $0.date.isSameDay(as: date) }
            .reduce(0) { $0 + $1.breakSeconds }
    }

    // MARK: Lists

    func list(for date: Date) -> DayList? {
        lists.first { $0.date.isSameDay(as: date) }
    }

    func list(withID id: UUID) -> DayList? {
        lists.first { $0.id == id }
    }

    /// Saves a list, replacing any list that already exists for that day.
    func saveNewList(_ list: DayList) {
        var updated = lists.filter { !$0.date.isSameDay(as: list.date) }
        updated.append(list)
        lists = updated
    }

    /// Adds (or replaces) these classes' entries on a day, keeping the other classes as they are.
    func saveEntries(_ newEntries: [ClassEntry], on date: Date) {
        let day = date.startOfDay

        if let existing = list(for: day) {
            updateList(existing.id) { list in
                list.isNoSchool = false
                for entry in newEntries {
                    if let index = list.entries.firstIndex(where: { $0.classID == entry.classID }) {
                        list.entries[index] = entry
                    } else {
                        list.entries.append(entry)
                    }
                }
                list.entries.sort { $0.period < $1.period }
            }
        } else {
            var newList = DayList(date: day, entries: newEntries)
            newList.entries.sort { $0.period < $1.period }
            lists.append(newList)
        }
    }

    func markNoSchool(on date: Date) {
        saveNewList(DayList(date: date.startOfDay, isNoSchool: true))
    }

    func deleteList(_ id: UUID) {
        lists.removeAll { $0.id == id }
    }

    func updateList(_ id: UUID, _ change: (inout DayList) -> Void) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        var copy = lists[index]
        change(&copy)
        lists[index] = copy
    }

    func replaceEntry(_ entry: ClassEntry, in listID: UUID) {
        updateList(listID) { list in
            if let index = list.entries.firstIndex(where: { $0.id == entry.id }) {
                list.entries[index] = entry
            }
        }
    }

    func toggleFinished(assignmentID: UUID, in listID: UUID) {
        updateList(listID) { list in
            for e in list.entries.indices {
                for a in list.entries[e].assignments.indices
                where list.entries[e].assignments[a].id == assignmentID {
                    list.entries[e].assignments[a].isFinished.toggle()
                    if list.entries[e].assignments[a].isFinished {
                        list.entries[e].assignments[a].skippedToday = nil
                    }
                }
            }
        }
    }

    /// The red "–" button: marks an assignment as not being done today.
    func toggleSkipped(assignmentID: UUID, in listID: UUID) {
        updateList(listID) { list in
            for e in list.entries.indices {
                for a in list.entries[e].assignments.indices
                where list.entries[e].assignments[a].id == assignmentID {
                    let nowSkipped = !list.entries[e].assignments[a].isSkippedToday
                    list.entries[e].assignments[a].skippedToday = nowSkipped ? true : nil
                    if nowSkipped {
                        list.entries[e].assignments[a].isFinished = false
                    }
                }
            }
        }
    }

    /// Sets a priority. If another assignment already has that number,
    /// the two swap so every number is only used once.
    func setPriority(_ newValue: Int?, assignmentID: UUID, in listID: UUID) {
        updateList(listID) { list in
            var target: (Int, Int)?
            var holder: (Int, Int)?

            for e in list.entries.indices {
                for a in list.entries[e].assignments.indices {
                    let item = list.entries[e].assignments[a]
                    if item.id == assignmentID {
                        target = (e, a)
                    } else if let value = newValue, item.priority == value {
                        holder = (e, a)
                    }
                }
            }

            guard let target else { return }
            let oldPriority = list.entries[target.0].assignments[target.1].priority
            list.entries[target.0].assignments[target.1].priority = newValue
            if let holder {
                list.entries[holder.0].assignments[holder.1].priority = oldPriority
            }
        }
    }
}
