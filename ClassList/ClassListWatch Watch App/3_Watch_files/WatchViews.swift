import SwiftUI
import Combine

// Watch app only. The screens for logging your day. Everything is taps, no typing.

nonisolated enum WatchRoute: Hashable {
    case question(Int)
    case due(classIndex: Int, itemIndex: Int, isStudy: Bool)
    case another(classIndex: Int, itemIndex: Int, isStudy: Bool, dueOffset: Int?)
    case addType(classIndex: Int, itemIndex: Int)
    case review
}

/// Your answers while you're logging (not sent until you tap Send).
@MainActor
final class LogDraft: ObservableObject {
    /// class number -> its items. An empty list means "No homework".
    @Published var items: [Int: [WatchLoggedItem]] = [:]

    func reset(_ classIndex: Int) {
        items[classIndex] = nil
    }

    func markNone(_ classIndex: Int) {
        items[classIndex] = []
    }

    func set(_ classIndex: Int, itemIndex: Int, item: WatchLoggedItem) {
        var list = Array((items[classIndex] ?? []).prefix(itemIndex))
        list.append(item)
        items[classIndex] = list
    }

    func clearAll() {
        items = [:]
    }
}

// MARK: - Root

struct WatchRootView: View {
    @EnvironmentObject private var model: WatchModel
    @StateObject private var draft = LogDraft()
    @State private var path: [WatchRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationDestination(for: WatchRoute.self) { route in
                    destination(route)
                }
        }
    }

    private var home: some View {
        List {
            if model.classes.isEmpty {
                Text("Open ClassList on your iPhone once so your classes show up here.")
                    .font(.footnote)
            } else {
                Button {
                    path.append(.question(0))
                } label: {
                    Label("Log Today", systemImage: "square.and.pencil")
                }

                if model.sentToday, let sent = model.lastSent {
                    Label("Sent \(sent.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("ClassList")
    }

    @ViewBuilder
    private func destination(_ route: WatchRoute) -> some View {
        switch route {
        case .question(let index):
            WatchQuestionView(draft: draft, path: $path, classIndex: index)
        case .due(let classIndex, let itemIndex, let isStudy):
            WatchDueView(path: $path, classIndex: classIndex, itemIndex: itemIndex, isStudy: isStudy)
        case .another(let classIndex, let itemIndex, let isStudy, let dueOffset):
            WatchAnotherView(
                draft: draft,
                path: $path,
                classIndex: classIndex,
                itemIndex: itemIndex,
                isStudy: isStudy,
                dueOffset: dueOffset
            )
        case .addType(let classIndex, let itemIndex):
            WatchAddTypeView(path: $path, classIndex: classIndex, itemIndex: itemIndex)
        case .review:
            WatchReviewView(draft: draft, path: $path)
        }
    }
}

// MARK: - One class: homework, no homework, or study

struct WatchQuestionView: View {
    @EnvironmentObject private var model: WatchModel
    @ObservedObject var draft: LogDraft
    @Binding var path: [WatchRoute]
    let classIndex: Int

    private var title: String {
        model.classes.indices.contains(classIndex) ? model.classes[classIndex].title : "Class"
    }

    var body: some View {
        List {
            Section("Class \(classIndex + 1) of \(model.classes.count)") {
                Button {
                    path.append(.due(classIndex: classIndex, itemIndex: 0, isStudy: false))
                } label: {
                    Label("Homework", systemImage: "doc.text")
                }

                Button {
                    draft.markNone(classIndex)
                    goToNextClass()
                } label: {
                    Label("No homework", systemImage: "checkmark.circle")
                }

                Button {
                    path.append(.due(classIndex: classIndex, itemIndex: 0, isStudy: true))
                } label: {
                    Label("Study / test", systemImage: "graduationcap")
                }
            }
        }
        .navigationTitle(title)
        .onAppear {
            // Coming back to this screen means you're answering it again.
            draft.reset(classIndex)
        }
    }

    private func goToNextClass() {
        if classIndex + 1 < model.classes.count {
            path.append(.question(classIndex + 1))
        } else {
            path.append(.review)
        }
    }
}

// MARK: - Due day

struct WatchDueView: View {
    @Binding var path: [WatchRoute]
    let classIndex: Int
    let itemIndex: Int
    let isStudy: Bool

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())

        List {
            Section(isStudy ? "Test day" : "Due") {
                Button("No due date") {
                    choose(nil)
                }

                ForEach(0..<7, id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today

                    Button {
                        choose(offset)
                    } label: {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide)))
                            Spacer()
                            if offset == 0 {
                                Text("Today").font(.caption2)
                            } else if offset == 1 {
                                Text("Tomorrow").font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(isStudy ? "Study" : "Homework")
    }

    private func choose(_ offset: Int?) {
        path.append(.another(classIndex: classIndex, itemIndex: itemIndex, isStudy: isStudy, dueOffset: offset))
    }
}

// MARK: - Add another item for the same class?

struct WatchAnotherView: View {
    @EnvironmentObject private var model: WatchModel
    @ObservedObject var draft: LogDraft
    @Binding var path: [WatchRoute]
    let classIndex: Int
    let itemIndex: Int
    let isStudy: Bool
    let dueOffset: Int?

    private var isLastClass: Bool {
        classIndex + 1 >= model.classes.count
    }

    var body: some View {
        List {
            Button {
                commit()
                path.append(.addType(classIndex: classIndex, itemIndex: itemIndex + 1))
            } label: {
                Label("Add another", systemImage: "plus.circle")
            }

            Button {
                commit()
                if isLastClass {
                    path.append(.review)
                } else {
                    path.append(.question(classIndex + 1))
                }
            } label: {
                Label(isLastClass ? "Finish" : "Next class", systemImage: "arrow.right.circle")
            }
        }
        .navigationTitle("Saved")
    }

    private func commit() {
        draft.set(classIndex, itemIndex: itemIndex, item: WatchLoggedItem(isStudy: isStudy, dueOffset: dueOffset))
    }
}

// MARK: - Homework or study for the extra item

struct WatchAddTypeView: View {
    @Binding var path: [WatchRoute]
    let classIndex: Int
    let itemIndex: Int

    var body: some View {
        List {
            Button {
                path.append(.due(classIndex: classIndex, itemIndex: itemIndex, isStudy: false))
            } label: {
                Label("Homework", systemImage: "doc.text")
            }

            Button {
                path.append(.due(classIndex: classIndex, itemIndex: itemIndex, isStudy: true))
            } label: {
                Label("Study / test", systemImage: "graduationcap")
            }
        }
        .navigationTitle("Another")
    }
}

// MARK: - Review and send

struct WatchReviewView: View {
    @EnvironmentObject private var model: WatchModel
    @ObservedObject var draft: LogDraft
    @Binding var path: [WatchRoute]

    var body: some View {
        List {
            Section("Your day") {
                ForEach(Array(model.classes.enumerated()), id: \.element.id) { index, schoolClass in
                    if let items = draft.items[index] {
                        HStack {
                            Text(schoolClass.title)
                                .lineLimit(1)
                            Spacer()
                            Text(items.isEmpty ? "None" : "\(items.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button {
                send()
            } label: {
                Label("Send to iPhone", systemImage: "iphone")
            }
            .tint(.purple)
        }
        .navigationTitle("Review")
    }

    private func send() {
        var logged: [WatchLoggedClass] = []
        for (index, schoolClass) in model.classes.enumerated() {
            if let items = draft.items[index] {
                logged.append(WatchLoggedClass(classID: schoolClass.id, items: items))
            }
        }

        model.send(
            WatchLogPayload(dayStart: Calendar.current.startOfDay(for: Date()), classes: logged)
        )
        draft.clearAll()
        path = []
    }
}
