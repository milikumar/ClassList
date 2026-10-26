import SwiftUI

// MARK: - Due day picker (also used when editing a class)

struct DayChips: View {
    @Binding var selection: Date?
    let days: [Date]

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            chip(title: "No due date", caption: nil, isSelected: selection == nil) {
                selection = nil
            }

            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                chip(title: day.weekdayName, caption: caption(for: day), isSelected: isSelected(day)) {
                    selection = day
                }
            }
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        guard let selection else { return false }
        return selection.isSameDay(as: day)
    }

    private func caption(for day: Date) -> String? {
        if day.isToday { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return nil
    }

    private func chip(
        title: String,
        caption: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(caption ?? " ")
                    .font(.system(size: 10))
                    .opacity(0.8)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? Theme.accent : Theme.cardHigh,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Logging flow (every class, or whichever classes you pick)

enum HomeworkAnswer {
    case homework
    case noWork
    case study
}

/// One thing to do for a class: homework OR a study/test, with its own due day.
struct DraftItem {
    var kind: AssignmentKind
    var due: Date? = nil
    var name: String = ""
}

struct ClassDraft {
    var answer: HomeworkAnswer?
    var items: [DraftItem] = []

    var hasDetails: Bool { answer == .homework || answer == .study }
}

enum TrackStage: Equatable {
    case question(Int)
    case details(Int)
}

struct TrackFlowView: View {
    @EnvironmentObject private var store: DataStore
    @Binding var path: [Route]

    let date: Date
    let classIDs: [UUID]

    @State private var stage: TrackStage = .question(0)
    @State private var drafts: [ClassDraft]

    init(path: Binding<[Route]>, date: Date, classIDs: [UUID]) {
        _path = path
        self.date = date.startOfDay
        self.classIDs = classIDs
        _drafts = State(initialValue: Array(repeating: ClassDraft(), count: classIDs.count))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if drafts.isEmpty {
                caughtUpView
            } else {
                progressHeader

                switch stage {
                case .question(let index):
                    questionView(index)
                case .details(let index):
                    detailsView(index)
                }
            }
        }
        .background { AppBackground() }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private var flowClasses: [SchoolClass] {
        store.classes.filter { classIDs.contains($0.id) }
    }

    private var classIndex: Int {
        switch stage {
        case .question(let index), .details(let index):
            return index
        }
    }

    private var isLastClass: Bool {
        classIndex + 1 >= drafts.count
    }

    private var upcomingDays: [Date] {
        (0..<7).map { date.adding(days: $0) }
    }

    private var dateLabel: String {
        date.isToday
            ? "Today"
            : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func schoolClass(_ index: Int) -> SchoolClass? {
        let classes = flowClasses
        return classes.indices.contains(index) ? classes[index] : nil
    }

    private var caughtUpView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.success)
            Text("All caught up")
                .font(.title.bold())
            Text("Every class is already logged.")
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Done") {
                path = []
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(dateLabel)  ·  Class \(classIndex + 1) of \(drafts.count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            ProgressView(value: Double(classIndex + 1), total: Double(max(drafts.count, 1)))
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Question screen

    @ViewBuilder
    private func questionView(_ index: Int) -> some View {
        let current = schoolClass(index)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    if let subtitle = current?.flowSubtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(current?.flowTitle ?? "Class")
                        .font(.largeTitle.bold())
                }

                Text("Do you have anything to do for this class?")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)

                VStack(spacing: 12) {
                    answerButton(index, .homework, "Yes, I have homework", "doc.text")
                    answerButton(index, .noWork, "No homework", "checkmark.circle")
                    answerButton(index, .study, "I have to study for a quiz/test", "graduationcap")
                }
            }
            .padding(20)
        }
    }

    private func answerButton(
        _ index: Int,
        _ answer: HomeworkAnswer,
        _ title: String,
        _ icon: String
    ) -> some View {
        let selected = drafts.indices.contains(index) && drafts[index].answer == answer

        return Button {
            choose(answer, for: index)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .foregroundStyle(Color.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Theme.accent : Theme.card,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Details screen (how many things, and the type + due day for each)

    @ViewBuilder
    private func detailsView(_ index: Int) -> some View {
        if drafts.indices.contains(index), drafts[index].hasDetails {
            let days = upcomingDays

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(schoolClass(index)?.flowTitle ?? "Class")
                        .font(.largeTitle.bold())

                    countCard(index)

                    ForEach(drafts[index].items.indices, id: \.self) { number in
                        itemCard(index, number, days: days)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(isLastClass ? "Finish" : "Next") {
                    advance(from: index)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private func itemCard(_ index: Int, _ number: Int, days: [Date]) -> some View {
        let isStudy = drafts[index].items.indices.contains(number)
            && drafts[index].items[number].kind == .study

        return VStack(alignment: .leading, spacing: 12) {
            TextField("Item \(number + 1): add a name (optional)", text: nameBinding(index, number))
                .font(.headline)

            // Switch between homework and studying for a test
            Picker("Type", selection: kindBinding(index, number)) {
                Text("Homework").tag(AssignmentKind.homework)
                Text("Study / Test").tag(AssignmentKind.study)
            }
            .pickerStyle(.segmented)

            Text(isStudy ? "What day is the test?" : "When is it due?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            DayChips(selection: dueBinding(index, number), days: days)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func countCard(_ index: Int) -> some View {
        let count = drafts[index].items.count

        return HStack {
            Text("How many assignments or tests?")
                .font(.headline)
            Spacer()
            HStack(spacing: 14) {
                Button {
                    changeCount(index, by: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .disabled(count <= 1)

                Text("\(count)")
                    .font(.title3.bold())
                    .frame(minWidth: 24)

                Button {
                    changeCount(index, by: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(count >= 6)
            }
            .font(.title2)
        }
        .card()
    }

    private func nameBinding(_ index: Int, _ number: Int) -> Binding<String> {
        Binding(
            get: {
                if drafts.indices.contains(index), drafts[index].items.indices.contains(number) {
                    return drafts[index].items[number].name
                }
                return ""
            },
            set: { newValue in
                if drafts.indices.contains(index), drafts[index].items.indices.contains(number) {
                    drafts[index].items[number].name = newValue
                }
            }
        )
    }

    private func kindBinding(_ index: Int, _ number: Int) -> Binding<AssignmentKind> {
        Binding(
            get: {
                if drafts.indices.contains(index), drafts[index].items.indices.contains(number) {
                    return drafts[index].items[number].kind
                }
                return AssignmentKind.homework
            },
            set: { newValue in
                if drafts.indices.contains(index), drafts[index].items.indices.contains(number) {
                    drafts[index].items[number].kind = newValue
                }
            }
        )
    }

    private func dueBinding(_ index: Int, _ number: Int) -> Binding<Date?> {
        Binding(
            get: {
                if drafts.indices.contains(index), drafts[index].items.indices.contains(number) {
                    return drafts[index].items[number].due
                }
                return nil
            },
            set: { newValue in
                if drafts.indices.contains(index), drafts[index].items.indices.contains(number) {
                    drafts[index].items[number].due = newValue
                }
            }
        )
    }

    // MARK: Actions

    private func choose(_ answer: HomeworkAnswer, for index: Int) {
        guard drafts.indices.contains(index) else { return }

        // Only start over if the answer type actually changed.
        if drafts[index].answer != answer {
            drafts[index].answer = answer
            switch answer {
            case .homework:
                drafts[index].items = [DraftItem(kind: .homework)]
            case .study:
                drafts[index].items = [DraftItem(kind: .study)]
            case .noWork:
                drafts[index].items = []
            }
        }

        if drafts[index].hasDetails {
            go(to: .details(index))
        } else {
            advance(from: index)
        }
    }

    /// The + / - buttons. A new item starts as the same type as the one before it;
    /// switch it with the Homework / Study picker above its date.
    private func changeCount(_ index: Int, by delta: Int) {
        guard drafts.indices.contains(index) else { return }

        var items = drafts[index].items
        let newCount = min(6, max(1, items.count + delta))

        if newCount > items.count {
            let kind = items.last?.kind ?? .homework
            while items.count < newCount {
                items.append(DraftItem(kind: kind))
            }
        } else {
            items = Array(items.prefix(newCount))
        }
        drafts[index].items = items
    }

    private func advance(from index: Int) {
        if index + 1 < drafts.count {
            go(to: .question(index + 1))
        } else {
            finish()
        }
    }

    private func goBack() {
        switch stage {
        case .details(let index):
            go(to: .question(index))

        case .question(let index):
            if index == 0 {
                if !path.isEmpty { path.removeLast() }
            } else {
                let previous = index - 1
                if drafts.indices.contains(previous), drafts[previous].hasDetails {
                    go(to: .details(previous))
                } else {
                    go(to: .question(previous))
                }
            }
        }
    }

    private func go(to newStage: TrackStage) {
        withAnimation(.easeInOut(duration: 0.2)) {
            stage = newStage
        }
    }

    private func finish() {
        var entries: [ClassEntry] = []

        for (index, schoolClass) in flowClasses.enumerated() {
            guard drafts.indices.contains(index), let answer = drafts[index].answer else { continue }

            var assignments: [Assignment] = []

            switch answer {
            case .homework, .study:
                for item in drafts[index].items {
                    let cleaned = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    assignments.append(
                        Assignment(
                            kind: item.kind,
                            dueDate: item.due,
                            title: cleaned.isEmpty ? nil : cleaned
                        )
                    )
                }
            case .noWork:
                break
            }

            entries.append(
                ClassEntry(
                    classID: schoolClass.id,
                    nameSnapshot: schoolClass.displayName,
                    period: schoolClass.period,
                    assignments: assignments
                )
            )
        }

        store.saveEntries(entries, on: date)
        path = []
    }
}
