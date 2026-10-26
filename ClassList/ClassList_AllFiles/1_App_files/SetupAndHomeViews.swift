import SwiftUI

// MARK: - First-time setup

struct SetupView: View {
    @EnvironmentObject private var store: DataStore

    enum LabelMode: String, CaseIterable, Identifiable {
        case names = "Class names"
        case numbers = "Just numbers"
        var id: String { rawValue }
    }

    @State private var step = 0
    @State private var classCount = 6
    @State private var mode: LabelMode = .names
    @State private var names: [String] = Array(repeating: "", count: 10)

    var body: some View {
        ZStack {
            AppBackground()
            if step == 0 {
                welcomeStep
            } else {
                namesStep
            }
        }
    }

    // Step 1: how many classes, and names vs numbers
    private var welcomeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to ClassList")
                        .font(.largeTitle.bold())
                    Text("Let's set up your classes. You can change all of this later.")
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("How many classes do you have?")
                        .font(.headline)
                    Stepper(value: $classCount, in: 1...10) {
                        Text("\(classCount) classes")
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("How do you want to label them?")
                        .font(.headline)
                    Picker("Labels", selection: $mode) {
                        ForEach(LabelMode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(mode == .names
                         ? "You'll type a name for each period, like Math or Science."
                         : "Your classes will just be 1, 2, 3 and so on.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .card()
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button(mode == .names ? "Next" : "Get Started") {
                if mode == .names {
                    withAnimation { step = 1 }
                } else {
                    store.setClasses(names: Array(repeating: "", count: classCount))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // Step 2: type the names
    private var namesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Name your classes")
                    .font(.largeTitle.bold())
                Text("Leave a name blank to just use its number.")
                    .foregroundStyle(Theme.textSecondary)

                ForEach(0..<classCount, id: \.self) { index in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .frame(width: 34, height: 34)
                            .background(Theme.cardHigh, in: Circle())
                        TextField("Class \(index + 1)", text: $names[index])
                            .textInputAutocapitalization(.words)
                    }
                    .card(padding: 12)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top) {
            HStack {
                Button {
                    withAnimation { step = 0 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Finish") {
                store.setClasses(names: Array(names.prefix(classCount)))
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Home screen (a scrolling feed of days, newest first)

nonisolated enum FeedItem: Identifiable {
    case list(DayList)
    case blank(Date)

    var id: String {
        switch self {
        case .list(let list): return list.id.uuidString
        case .blank(let date): return "blank-\(Int(date.timeIntervalSince1970))"
        }
    }

    var date: Date {
        switch self {
        case .list(let list): return list.date
        case .blank(let date): return date
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: DataStore
    @Binding var path: [Route]
    @State private var confirmRedo = false

    private var today: DayList? { store.list(for: Date()) }

    /// Past days, newest first. Skipped school days show as blank cards.
    private var feedItems: [FeedItem] {
        let todayStart = Date().startOfDay
        let past = store.lists.filter { $0.date.startOfDay < todayStart }
        guard let earliest = past.map({ $0.date.startOfDay }).min() else { return [] }

        var items: [FeedItem] = past.map { FeedItem.list($0) }

        let limit = max(earliest, todayStart.adding(days: -90))
        var day = todayStart.adding(days: -1)
        while day >= limit {
            let isWeekend = Calendar.current.isDateInWeekend(day)
            let hasList = past.contains { $0.date.isSameDay(as: day) }
            if !isWeekend && !hasList {
                items.append(.blank(day))
            }
            day = day.adding(days: -1)
        }

        return items.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                todaySection

                let items = feedItems
                if !items.isEmpty {
                    Text("Earlier")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 8)

                    ForEach(items) { item in
                        switch item {
                        case .list(let list):
                            DayCard(list: list, path: $path)
                        case .blank(let date):
                            BlankDayCard(date: date, path: $path)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        path.append(.schedule)
                    } label: {
                        Image(systemName: "clock")
                    }
                    Button {
                        path.append(.settings)
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .confirmationDialog(
            "Start today's list over?",
            isPresented: $confirmRedo,
            titleVisibility: .visible
        ) {
            Button("Start Over", role: .destructive) {
                startTracking()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current answers stay until you finish.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ClassList")
                .font(.largeTitle.bold())
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(spacing: 12) {
            ActiveTimerBanner(path: $path)

            if let list = today {
                DayCard(list: list, path: $path)
                todayButtons(for: list)
            } else {
                untrackedCard
            }
        }
    }

    private var untrackedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title2.bold())
            Text("Nothing tracked yet. Log every class at once, or one at a time.")
                .foregroundStyle(Theme.textSecondary)

            Button("Track Today") {
                startTracking()
            }
            .buttonStyle(PrimaryButtonStyle())

            logOneClassMenu

            Button("Nothing to Track / No School") {
                store.markNoSchool(on: Date())
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    @ViewBuilder
    private func todayButtons(for list: DayList) -> some View {
        let remaining = store.unloggedClasses(on: list.date)

        VStack(spacing: 12) {
            if list.isNoSchool {
                Button("Track Today Anyway") {
                    startTracking()
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                if !remaining.isEmpty {
                    Button("Log Remaining Classes (\(remaining.count))") {
                        logRemaining()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                logOneClassMenu

                Button("Track Today Again") {
                    confirmRedo = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    /// Pick a single class to log (or redo).
    private var logOneClassMenu: some View {
        let day = Date().startOfDay

        return Menu {
            Section("Log a single class") {
                ForEach(store.classes) { schoolClass in
                    logButton(schoolClass, on: day)
                }
            }
        } label: {
            Text("Log One Class")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func logButton(_ schoolClass: SchoolClass, on day: Date) -> some View {
        Button {
            path.append(.log(day, [schoolClass.id]))
        } label: {
            if store.isLogged(schoolClass.id, on: day) {
                Label(schoolClass.flowTitle, systemImage: "checkmark")
            } else {
                Text(schoolClass.flowTitle)
            }
        }
    }

    private func startTracking() {
        let day = Date().startOfDay
        path.append(.log(day, store.classes.map { $0.id }))
    }

    private func logRemaining() {
        let day = Date().startOfDay
        path.append(.log(day, store.unloggedClasses(on: day).map { $0.id }))
    }
}

// MARK: - A day with nothing tracked

struct BlankDayCard: View {
    @EnvironmentObject private var store: DataStore
    let date: Date
    @Binding var path: [Route]

    var body: some View {
        let info = DayList(date: date)

        Button {
            path.append(.log(date, store.classes.map { $0.id }))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(.title3.bold())
                    Text(info.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Nothing tracked")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .opacity(0.7)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - One day in the feed

struct DayCard: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var timerStore: TimerStore
    let list: DayList
    @Binding var path: [Route]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if list.isNoSchool {
                Text("No school")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
            } else if list.entries.isEmpty {
                Text("Nothing logged yet")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(list.entries) { entry in
                        entryRows(entry)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Header: title + count on the left, stopwatch and arrow on the right

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                path.append(.dayList(list.id))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.title)
                        .font(.title3.bold())
                    Text(list.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    if !list.isNoSchool && list.totalCount > 0 {
                        Text("\(list.doneCount)/\(list.totalCount) done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            stopwatchControl

            Button {
                path.append(.dayList(list.id))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 38)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.white)
    }

    /// Stopwatch button: pick a class to time. Shows on today's card only.
    @ViewBuilder
    private var stopwatchControl: some View {
        if list.date.isToday && !list.isNoSchool {
            if let session = timerStore.session {
                Button {
                    path.append(.timer(session.classID))
                } label: {
                    stopwatchIcon(active: true)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Section("Time yourself on…") {
                        ForEach(store.classes) { schoolClass in
                            Button(schoolClass.flowTitle) {
                                path.append(.timer(schoolClass.id))
                            }
                        }
                    }
                } label: {
                    stopwatchIcon(active: false)
                }
            }
        }
    }

    private func stopwatchIcon(active: Bool) -> some View {
        Image(systemName: active ? "stopwatch.fill" : "stopwatch")
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(width: 38, height: 38)
            .background(active ? Theme.accent : Theme.cardHigh, in: Circle())
    }

    // MARK: Rows

    @ViewBuilder
    private func entryRows(_ entry: ClassEntry) -> some View {
        let name = store.displayName(for: entry)
        let showPeriod = name != String(entry.period)
        let studied = store.studySeconds(for: entry.classID, on: list.date)

        if entry.assignments.isEmpty {
            HStack(spacing: 6) {
                Color.clear.frame(width: 86, height: 1)
                nameBlock(name, studied: studied, strike: false)
                if showPeriod {
                    PeriodTag(period: entry.period)
                }
                Spacer()
                Text("No homework")
                    .font(.subheadline)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, 8)
        } else {
            ForEach(Array(entry.assignments.enumerated()), id: \.element.id) { index, item in
                let suffix = entry.assignments.count > 1 ? " (\(index + 1))" : ""
                assignmentRow(
                    item,
                    title: name + suffix,
                    detail: item.trimmedTitle,
                    period: showPeriod ? entry.period : nil,
                    studied: entry.assignments.count == 1
                        ? studied
                        : store.studySeconds(forAssignment: item.id)
                )
            }
        }
    }

    private func nameBlock(_ title: String, detail: String? = nil, studied: Double, strike: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.body.weight(.semibold))
                .strikethrough(strike)
                .lineLimit(1)
            // The assignment's name (cut off if it's long; the full name shows when you open the day)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            if studied >= 30 {
                StudyTimeTag(seconds: studied)
            }
        }
    }

    private func assignmentRow(_ item: Assignment, title: String, detail: String?, period: Int?, studied: Double) -> some View {
        let dimmed = item.isFinished || item.isSkippedToday

        return HStack(spacing: 6) {
            priorityMenu(item)

            // Check = finished
            Button {
                store.toggleFinished(assignmentID: item.id, in: list.id)
            } label: {
                Image(systemName: item.isFinished ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isFinished ? Theme.success : Theme.textSecondary)
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)

            // Red minus = not doing this one today
            Button {
                store.toggleSkipped(assignmentID: item.id, in: list.id)
            } label: {
                Image(systemName: item.isSkippedToday ? "minus.circle.fill" : "minus.circle")
                    .font(.title3)
                    .foregroundStyle(item.isSkippedToday ? Theme.danger : Theme.textSecondary)
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                nameBlock(title, detail: detail, studied: studied, strike: item.isFinished)

                if let period {
                    PeriodTag(period: period)
                }

                Spacer(minLength: 4)

                Text(item.kind == .study ? "Study" : "HW")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Text(dueText(item.dueDate))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 50, alignment: .trailing)
            }
            .opacity(dimmed ? 0.55 : 1)
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 8)
    }

    // Tap the number on the left to set the priority (1 = most important)
    private func priorityMenu(_ item: Assignment) -> some View {
        Menu {
            Button("None") {
                store.setPriority(nil, assignmentID: item.id, in: list.id)
            }
            ForEach(1...max(1, min(list.totalCount, 12)), id: \.self) { number in
                Button {
                    store.setPriority(number, assignmentID: item.id, in: list.id)
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
                .frame(width: 22, height: 30)
                .contentShape(Rectangle())
        }
    }

    private func dueText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.isToday ? "Today" : date.weekdayShort
    }
}

// MARK: - Small "P1" period label shown next to a class name

struct PeriodTag: View {
    let period: Int

    var body: some View {
        Text("P\(period)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accent.opacity(0.35), in: Capsule())
    }
}
