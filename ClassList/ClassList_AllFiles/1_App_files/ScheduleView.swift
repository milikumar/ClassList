import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: DataStore
    @State private var weekday: Int

    private enum NameMode {
        case newBlank
        case duplicate
        case rename
    }

    @State private var nameMode: NameMode = .newBlank
    @State private var showNameAlert = false
    @State private var nameText = ""
    @State private var confirmDelete = false
    @State private var showImport = false

    // Calendar weekday numbers: 2 = Monday ... 6 = Friday
    private let weekdays: [(number: Int, name: String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri")
    ]

    init() {
        let today = Calendar.current.component(.weekday, from: Date())
        _weekday = State(initialValue: (2...6).contains(today) ? today : 2)
    }

    private var daySlots: [ScheduleSlot] {
        store.schedule
            .filter { $0.weekday == weekday }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bell Schedule")
                    .font(.largeTitle.bold())
                Text("Add your class times for each day. When a class ends, you'll get a reminder to log it.")
                    .foregroundStyle(Theme.textSecondary)

                scheduleBar

                Button {
                    showImport = true
                } label: {
                    Label("Import from a picture", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(SecondaryButtonStyle())

                Picker("Day", selection: $weekday) {
                    ForEach(weekdays, id: \.number) { day in
                        Text(day.name).tag(day.number)
                    }
                }
                .pickerStyle(.segmented)

                if daySlots.isEmpty {
                    Text("No classes added for this day yet. With nothing added, every class shows up when you track.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(daySlots) { slot in
                    slotCard(slot)
                }

                Button {
                    store.addSlot(weekday: weekday)
                } label: {
                    Label("Add a class", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())

                if store.schedule.contains(where: { $0.weekday != weekday }) {
                    Menu {
                        ForEach(weekdays.filter { $0.number != weekday }, id: \.number) { other in
                            Button("Copy from \(other.name)") {
                                store.copySchedule(from: other.number, to: weekday)
                            }
                        }
                    } label: {
                        Text("Copy another day's schedule here")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }

                Text("Not getting reminders? Check Settings → Notifications → ClassList on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            NotificationScheduler.requestPermission()
        }
        .alert(alertTitle, isPresented: $showNameAlert) {
            TextField("Name", text: $nameText)
            Button("Save") {
                commitName()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("For example: Normal week, Short week, Testing days")
        }
        .confirmationDialog(
            "Delete \"\(store.activeScheduleName)\"?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = store.activeScheduleID {
                    store.deleteSchedule(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the saved schedule. Your lists stay.")
        }
        .sheet(isPresented: $showImport) {
            ScheduleImportView()
        }
    }

    // MARK: Named schedules

    private var alertTitle: String {
        switch nameMode {
        case .newBlank: return "New schedule"
        case .duplicate: return "Duplicate schedule"
        case .rename: return "Rename schedule"
        }
    }

    private var scheduleBar: some View {
        Menu {
            Section("Switch schedule") {
                ForEach(store.savedSchedules) { saved in
                    Button {
                        store.switchSchedule(to: saved.id)
                    } label: {
                        if saved.id == store.activeScheduleID {
                            Label(saved.name, systemImage: "checkmark")
                        } else {
                            Text(saved.name)
                        }
                    }
                }
            }

            Section {
                Button("New blank schedule…") { startNaming(.newBlank) }
                Button("Duplicate this schedule…") { startNaming(.duplicate) }
                Button("Rename this schedule…") { startNaming(.rename) }
                if store.savedSchedules.count > 1 {
                    Button("Delete this schedule", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule in use")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(store.activeScheduleName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func startNaming(_ mode: NameMode) {
        nameMode = mode
        switch mode {
        case .newBlank: nameText = ""
        case .duplicate: nameText = store.activeScheduleName + " copy"
        case .rename: nameText = store.activeScheduleName
        }
        showNameAlert = true
    }

    private func commitName() {
        switch nameMode {
        case .newBlank:
            store.createSchedule(named: nameText, copyCurrent: false)
        case .duplicate:
            store.createSchedule(named: nameText, copyCurrent: true)
        case .rename:
            if let id = store.activeScheduleID {
                store.renameSchedule(id, to: nameText)
            }
        }
    }

    private func slotCard(_ slot: ScheduleSlot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    ForEach(store.classes) { schoolClass in
                        Button(schoolClass.flowTitle) {
                            store.updateSlot(slot.id) { $0.classID = schoolClass.id }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(className(for: slot))
                            .font(.headline)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    store.removeSlot(slot.id)
                } label: {
                    Image(systemName: "trash")
                }
            }

            DatePicker(
                "Starts",
                selection: timeBinding(slot.id, isStart: true),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "Ends",
                selection: timeBinding(slot.id, isStart: false),
                displayedComponents: .hourAndMinute
            )
        }
        .card()
    }

    private func className(for slot: ScheduleSlot) -> String {
        store.classes.first(where: { $0.id == slot.classID })?.flowTitle ?? "Class"
    }

    private func timeBinding(_ id: UUID, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                guard let slot = store.schedule.first(where: { $0.id == id }) else { return Date() }
                let minutes = isStart ? slot.startMinutes : slot.endMinutes
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

                store.updateSlot(id) { slot in
                    if isStart {
                        slot.startMinutes = minutes
                        if slot.endMinutes <= minutes {
                            slot.endMinutes = min(minutes + 50, 23 * 60 + 59)
                        }
                    } else {
                        slot.endMinutes = min(max(minutes, slot.startMinutes + 5), 23 * 60 + 59)
                    }
                }
            }
        )
    }
}
