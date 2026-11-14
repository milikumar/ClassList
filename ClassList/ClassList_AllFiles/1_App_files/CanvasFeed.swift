import SwiftUI
import Combine
import Security

// App only. Reads your Canvas "Calendar Feed" link and shows the assignments
// as a reminder when you log a class. It only reads. It never changes anything in Canvas.

// MARK: - Keeps your calendar link in the iPhone's secure storage (Keychain)

nonisolated enum Keychain {
    private static let service = "classlist.canvas"

    static func save(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - An assignment from Canvas

nonisolated struct CanvasAssignment: Identifiable, Codable, Hashable {
    var id: String          // Canvas's own id for it
    var title: String
    var course: String      // like "Algebra 2"
    var due: Date
}

// MARK: - Reading the calendar file (.ics)

nonisolated enum ICSParser {
    static func assignments(from text: String) -> [CanvasAssignment] {
        // Long lines are split across lines that start with a space. Join them back up.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        for piece in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = piece.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(piece.dropFirst())
            } else {
                lines.append(String(piece))
            }
        }

        struct RawEvent {
            var summary = ""
            var uid = ""
            var start: Date?
        }

        var events: [RawEvent] = []
        var current: RawEvent?

        for line in lines {
            if line == "BEGIN:VEVENT" {
                current = RawEvent()
                continue
            }
            if line == "END:VEVENT" {
                if let finished = current { events.append(finished) }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }

            let left = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let name = left.split(separator: ";", maxSplits: 1).first.map { String($0).uppercased() } ?? ""
            let params = left.contains(";") ? String(left[left.index(after: left.firstIndex(of: ";")!)...]) : ""

            switch name {
            case "SUMMARY": current?.summary = unescape(value)
            case "UID": current?.uid = value
            case "DTSTART": current?.start = parseDate(value, params: params)
            default: break
            }
        }

        // Canvas marks assignments with an id that starts with "event-assignment".
        let marked = events.filter { $0.uid.hasPrefix("event-assignment") }
        let chosen = marked.isEmpty ? events : marked

        var result: [CanvasAssignment] = []
        var seen = Set<String>()
        for event in chosen {
            guard let due = event.start, !event.summary.isEmpty else { continue }
            let parts = splitSummary(event.summary)
            let id = event.uid.isEmpty ? "\(parts.title)-\(due.timeIntervalSince1970)" : event.uid
            if seen.insert(id).inserted {
                result.append(CanvasAssignment(id: id, title: parts.title, course: parts.course, due: due))
            }
        }
        return result
    }

    /// "Homework 3 [Algebra 2]" -> ("Homework 3", "Algebra 2")
    private static func splitSummary(_ summary: String) -> (title: String, course: String) {
        let text = summary.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("]"), let open = text.lastIndex(of: "[") {
            let title = String(text[..<open]).trimmingCharacters(in: .whitespaces)
            let inner = text[text.index(after: open)..<text.index(before: text.endIndex)]
            return (title, String(inner).trimmingCharacters(in: .whitespaces))
        }
        return (text, "")
    }

    /// Turns calendar-file escapes like \, and \n into normal text.
    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                result.append((character == "n" || character == "N") ? " " : character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func parseDate(_ value: String, params: String) -> Date? {
        let digits = value.filter { $0.isNumber }
        guard digits.count >= 8 else { return nil }

        func number(_ start: Int, _ length: Int) -> Int? {
            guard digits.count >= start + length else { return nil }
            let begin = digits.index(digits.startIndex, offsetBy: start)
            let end = digits.index(begin, offsetBy: length)
            return Int(digits[begin..<end])
        }

        var zone = TimeZone.current
        if value.hasSuffix("Z"), let utc = TimeZone(secondsFromGMT: 0) {
            zone = utc
        } else if let range = params.range(of: "TZID=") {
            let name = params[range.upperBound...].prefix { $0 != ";" }
            if let named = TimeZone(identifier: String(name)) { zone = named }
        }

        var parts = DateComponents()
        parts.timeZone = zone
        parts.year = number(0, 4)
        parts.month = number(4, 2)
        parts.day = number(6, 2)
        if digits.count >= 14 {
            parts.hour = number(8, 2)
            parts.minute = number(10, 2)
            parts.second = number(12, 2)
        } else {
            parts.hour = 12   // a date with no time
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: parts)
    }
}

// MARK: - Canvas data and settings

private struct CanvasCache: Codable {
    var assignments: [CanvasAssignment]
    var updated: Date
}

@MainActor
final class CanvasStore: ObservableObject {
    @Published private(set) var assignments: [CanvasAssignment] = []
    @Published private(set) var isConnected = false
    @Published private(set) var lastUpdated: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// class id -> the Canvas course name you matched it to
    @Published private(set) var mapping: [String: String] = [:]

    private let account = "calendarFeed"
    private let cacheKey = "classlist.canvasCache"
    private let mappingKey = "classlist.canvasMapping"

    init() {
        isConnected = Keychain.load(account: account) != nil

        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(CanvasCache.self, from: data) {
            assignments = cache.assignments
            lastUpdated = cache.updated
        }
        if let data = UserDefaults.standard.data(forKey: mappingKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            mapping = saved
        }
    }

    /// The Canvas course names found in your calendar.
    var courses: [String] {
        Array(Set(assignments.map { $0.course }.filter { !$0.isEmpty })).sorted()
    }

    /// How many assignments were found for each course (shown in settings so you can see what Canvas sent).
    var courseCounts: [(course: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in assignments {
            let name = item.course.isEmpty ? "No course name" : item.course
            counts[name, default: 0] += 1
        }
        return counts
            .map { (course: $0.key, count: $0.value) }
            .sorted { $0.course < $1.course }
    }

    func course(for classID: UUID) -> String? {
        mapping[classID.uuidString]
    }

    func setCourse(_ course: String?, for classID: UUID) {
        mapping[classID.uuidString] = course
        if let data = try? JSONEncoder().encode(mapping) {
            UserDefaults.standard.set(data, forKey: mappingKey)
        }
    }

    /// Guess matches by class name (you can change them).
    func autoMatch(_ classes: [SchoolClass]) {
        for schoolClass in classes where course(for: schoolClass.id) == nil {
            let name = schoolClass.trimmedName.lowercased()
            guard !name.isEmpty else { continue }
            if let found = courses.first(where: { $0.lowercased().contains(name) }) {
                setCourse(found, for: schoolClass.id)
            }
        }
    }

    /// Upcoming assignments for one of your classes.
    func upcoming(for classID: UUID, limit: Int = 5) -> [CanvasAssignment] {
        guard let course = mapping[classID.uuidString] else { return [] }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let matches = assignments
            .filter { $0.course == course && $0.due >= startOfToday }
            .sorted { $0.due < $1.due }
        return Array(matches.prefix(limit))
    }

    // MARK: Connecting

    func connect(_ text: String) async {
        errorMessage = nil
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("webcal://") {
            cleaned = "https://" + cleaned.dropFirst("webcal://".count)
        }

        guard let url = URL(string: cleaned),
              url.scheme?.lowercased() == "https",
              cleaned.contains("feeds/calendars") else {
            errorMessage = "That doesn't look like a Canvas calendar feed link. In Canvas, open Calendar, then Calendar Feed, and copy the whole link."
            return
        }

        Keychain.save(url.absoluteString, account: account)
        isConnected = true
        await refresh(force: true)
    }

    func disconnect() {
        Keychain.delete(account: account)
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: mappingKey)
        isConnected = false
        assignments = []
        mapping = [:]
        lastUpdated = nil
        errorMessage = nil
    }

    // MARK: Reading the feed

    func refresh(force: Bool = false) async {
        guard let saved = Keychain.load(account: account), let url = URL(string: saved) else { return }
        if isLoading { return }
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < 600 { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                errorMessage = "Canvas didn't accept the link (error \(http.statusCode)). Try copying the Calendar Feed link again."
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                errorMessage = "I couldn't read what Canvas sent back."
                return
            }

            let parsed = ICSParser.assignments(from: text)
            assignments = parsed
            lastUpdated = Date()

            if let encoded = try? JSONEncoder().encode(CanvasCache(assignments: parsed, updated: Date())) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
            }
            if parsed.isEmpty {
                errorMessage = "Connected, but no assignments were found in the feed yet."
            }
        } catch {
            errorMessage = "I couldn't reach Canvas. Check your internet connection and try again."
        }
    }
}

// MARK: - The reminder card on the "Do you have homework?" screen

struct CanvasReminderCard: View {
    @EnvironmentObject private var canvas: CanvasStore
    let classID: UUID

    var body: some View {
        let items = canvas.upcoming(for: classID)

        if canvas.isConnected && !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("From Canvas", systemImage: "checklist")
                    .font(.headline)

                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(dueText(item.due))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text("Coming up in Canvas, as a reminder. It can't tell which ones you've already finished.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func dueText(_ date: Date) -> String {
        if date.isToday { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.weekdayName
    }
}

// MARK: - Settings: connect Canvas and match your classes

struct CanvasSettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var canvas: CanvasStore

    @State private var linkText = ""
    @State private var confirmDisconnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Canvas")
                    .font(.largeTitle.bold())

                if canvas.isConnected {
                    connectedSection
                } else {
                    connectSection
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Disconnect Canvas?",
            isPresented: $confirmDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                canvas.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved link and your class matches. Nothing changes in Canvas.")
        }
    }

    // MARK: Not connected yet

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Show your Canvas assignments as a reminder when you log a class.")
                    .font(.headline)
                Text("1. Sign in to your school's Canvas in a web browser.\n2. Open Calendar.\n3. Click Calendar Feed (near the bottom right) and copy the link.\n4. Paste it below.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            TextField("Paste your calendar feed link", text: $linkText, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .card()

            Button(canvas.isLoading ? "Connecting…" : "Connect") {
                Task {
                    await canvas.connect(linkText)
                    canvas.autoMatch(store.classes)
                    if canvas.isConnected { linkText = "" }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty || canvas.isLoading)

            if let message = canvas.errorMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
            }

            Text("Treat this link like a password: anyone who has it can see your Canvas calendar. ClassList keeps it in your iPhone's secure storage and only reads from it.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Connected

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.success)

                if let last = canvas.lastUpdated {
                    Text("\(canvas.assignments.count) assignments found. Updated \(last.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let message = canvas.errorMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            Button(canvas.isLoading ? "Refreshing…" : "Refresh now") {
                Task {
                    await canvas.refresh(force: true)
                    canvas.autoMatch(store.classes)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(canvas.isLoading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Found in your Canvas calendar")
                    .font(.headline)

                ForEach(canvas.courseCounts, id: \.course) { entry in
                    HStack {
                        Text(entry.course)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.count)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text("Missing a class? ClassList only sees what Canvas puts in the feed. Make sure the course is ticked on Canvas's Calendar page (the list on the left), then tap Refresh now.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            Text("Match your classes")
                .font(.title3.bold())
                .padding(.top, 4)

            Text("Pick the Canvas course for each class. Only courses with assignments in your calendar show up.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            ForEach(store.classes) { schoolClass in
                matchRow(schoolClass)
            }

            Button("Disconnect Canvas", role: .destructive) {
                confirmDisconnect = true
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
        .onAppear {
            canvas.autoMatch(store.classes)
        }
    }

    private func matchRow(_ schoolClass: SchoolClass) -> some View {
        HStack(spacing: 10) {
            Text(schoolClass.flowTitle)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Menu {
                Button("None") {
                    canvas.setCourse(nil, for: schoolClass.id)
                }
                ForEach(canvas.courses, id: \.self) { course in
                    Button(course) {
                        canvas.setCourse(course, for: schoolClass.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(canvas.course(for: schoolClass.id) ?? "Choose course")
                        .font(.subheadline)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(canvas.course(for: schoolClass.id) == nil ? Theme.textSecondary : Theme.accent)
            }
        }
        .card(padding: 12)
    }
}
