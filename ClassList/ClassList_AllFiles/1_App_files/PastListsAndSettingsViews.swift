import SwiftUI

// MARK: - Past lists

struct PastListsView: View {
    @EnvironmentObject private var store: DataStore
    @Binding var path: [Route]

    private var sortedLists: [DayList] {
        store.lists.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedLists.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                    Text("No lists yet")
                        .font(.title3.bold())
                    Text("Lists you track will show up here.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedLists) { list in
                        Button {
                            path.append(.dayList(list.id))
                        } label: {
                            row(list)
                        }
                        .listRowBackground(Theme.card)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteList(list.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background { AppBackground() }
        .navigationTitle("Past Lists")
        .navigationBarTitleDisplayMode(.large)
    }

    private func row(_ list: DayList) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(.headline)
                Text(list.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(summary(list))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 4)
    }

    private func summary(_ list: DayList) -> String {
        if list.isNoSchool { return "No school" }
        if list.totalCount == 0 { return "No homework" }
        return "\(list.doneCount)/\(list.totalCount) done"
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Classes")
                    .font(.largeTitle.bold())
                Text("Rename a class any time. Leave a name blank to just use its number.")
                    .foregroundStyle(Theme.textSecondary)

                NavigationLink(value: Route.schedule) {
                    HStack {
                        Label("Bell Schedule", systemImage: "clock")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .foregroundStyle(Color.white)
                    .card()
                }
                .buttonStyle(.plain)

                NavigationLink(value: Route.canvas) {
                    HStack {
                        Label("Canvas", systemImage: "checklist")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .foregroundStyle(Color.white)
                    .card()
                }
                .buttonStyle(.plain)

                Stepper(
                    value: Binding(
                        get: { store.classes.count },
                        set: { store.resizeClasses(to: $0) }
                    ),
                    in: 1...10
                ) {
                    Text("Number of classes: \(store.classes.count)")
                        .font(.headline)
                }
                .card()

                ForEach($store.classes) { $schoolClass in
                    HStack(spacing: 12) {
                        Text("\(schoolClass.period)")
                            .font(.headline)
                            .frame(width: 34, height: 34)
                            .background(Theme.cardHigh, in: Circle())
                        TextField("Class \(schoolClass.period)", text: $schoolClass.name)
                            .textInputAutocapitalization(.words)
                    }
                    .card(padding: 12)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
    }
}
