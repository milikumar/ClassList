import SwiftUI
import Combine
import ActivityKit
import UserNotifications

// MARK: - Time formatting

/// 25:00 or 1:05:00. Countdowns round up so a fresh 25 minute timer shows 25:00.
nonisolated func clockString(_ seconds: Double, roundUp: Bool = false) -> String {
    let rounded = roundUp ? seconds.rounded(.up) : seconds.rounded(.down)
    let total = max(0, Int(rounded))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
}

/// 45m or 1h 05m
nonisolated func shortDuration(_ seconds: Double) -> String {
    let totalMinutes = Int((seconds / 60).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return String(format: "%dh %02dm", hours, minutes)
    }
    return "\(max(totalMinutes, 1))m"
}

// MARK: - A running timer

/// Uses real clock times instead of counting ticks, so it stays correct
/// while the app is in the background, the phone is locked, or the app is closed.
nonisolated struct TimerSession: Codable, Equatable {
    var classID: UUID
    var className: String
    var isCountdown: Bool
    var targetSeconds: Double
    var startedAt: Date
    var studyAccumulated: Double
    var breakAccumulated: Double
    var segmentStart: Date
    var isPaused: Bool
    /// What you're timing (nil = just the class).
    var assignmentID: UUID?
    var assignmentTitle: String?

    func studySeconds(at now: Date) -> Double {
        var total = studyAccumulated
        if !isPaused {
            total += now.timeIntervalSince(segmentStart)
        }
        if isCountdown {
            total = min(total, targetSeconds)
        }
        return max(0, total)
    }

    func breakSeconds(at now: Date) -> Double {
        var total = breakAccumulated
        if isPaused {
            total += now.timeIntervalSince(segmentStart)
        }
        return max(0, total)
    }

    func remainingSeconds(at now: Date) -> Double {
        max(0, targetSeconds - studySeconds(at: now))
    }

    func isFinished(at now: Date) -> Bool {
        isCountdown && remainingSeconds(at: now) <= 0
    }

    func displayTime(at now: Date) -> String {
        if isCountdown {
            return clockString(remainingSeconds(at: now), roundUp: true)
        }
        return clockString(studySeconds(at: now))
    }
}

// MARK: - "Time's up" notification

@MainActor
enum TimerAlerts {
    static let identifier = "timer-end"

    static func scheduleEnd(in seconds: Double, className: String) {
        guard seconds >= 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time's up!"
        content.body = "Your \(className) timer finished."
        content.sound = .default
        content.userInfo = ["type": "timer"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelEnd() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

// MARK: - Dynamic Island / lock screen timer

@MainActor
enum LiveActivityManager {
    /// Keeps the Dynamic Island and lock screen timer in step with the real timer.
    /// canStart = false means "only update or end an existing one, never start a new one".
    static func sync(with session: TimerSession?, canStart: Bool = true) {
        Task { @MainActor in
            await apply(session, canStart: canStart)
        }
    }

    private static func apply(_ session: TimerSession?, canStart: Bool) async {
        let existing = Activity<StudyTimerAttributes>.activities

        guard let session else {
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let now = Date()
        let content = ActivityContent(
            state: makeState(session, now: now),
            staleDate: staleDate(session, now: now)
        )

        if let current = existing.first {
            await current.update(content)
        } else if canStart, ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = StudyTimerAttributes(className: session.className)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }

    private static func makeState(_ session: TimerSession, now: Date) -> StudyTimerAttributes.ContentState {
        if session.isCountdown {
            let remaining = session.remainingSeconds(at: now)
            return StudyTimerAttributes.ContentState(
                isCountdown: true,
                isPaused: session.isPaused,
                rangeStart: now,
                rangeEnd: now.addingTimeInterval(remaining),
                pausedAt: session.isPaused ? now : nil
            )
        } else {
            // Count up: pretend the stopwatch started "study time" ago.
            let study = session.studySeconds(at: now)
            let virtualStart = now.addingTimeInterval(-study)
            return StudyTimerAttributes.ContentState(
                isCountdown: false,
                isPaused: session.isPaused,
                rangeStart: virtualStart,
                rangeEnd: virtualStart.addingTimeInterval(12 * 3600),
                pausedAt: session.isPaused ? now : nil
            )
        }
    }

    /// When a running countdown ends, the lock screen switches to "Time's up!".
    private static func staleDate(_ session: TimerSession, now: Date) -> Date? {
        guard session.isCountdown, !session.isPaused else { return nil }
        return now.addingTimeInterval(session.remainingSeconds(at: now))
    }
}

// MARK: - Timer store (one timer at a time, saved so it survives closing the app)

@MainActor
final class TimerStore: ObservableObject {
    @Published var session: TimerSession? = nil {
        didSet {
            persist()
            LiveActivityManager.sync(with: session)
        }
    }

    private let key = "classlist.timerSession"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(TimerSession.self, from: data) {
            session = saved
        }
    }

    private func persist() {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func start(
        classID: UUID,
        className: String,
        assignmentID: UUID?,
        assignmentTitle: String?,
        isCountdown: Bool,
        minutes: Int
    ) {
        guard session == nil else { return }
        let now = Date()
        let target = Double(minutes * 60)

        session = TimerSession(
            classID: classID,
            className: className,
            isCountdown: isCountdown,
            targetSeconds: isCountdown ? target : 0,
            startedAt: now,
            studyAccumulated: 0,
            breakAccumulated: 0,
            segmentStart: now,
            isPaused: false,
            assignmentID: assignmentID,
            assignmentTitle: assignmentTitle
        )

        if isCountdown {
            TimerAlerts.scheduleEnd(in: target, className: className)
        }
    }

    func pause() {
        guard var current = session, !current.isPaused else { return }
        let now = Date()
        current.studyAccumulated = current.studySeconds(at: now)
        current.segmentStart = now
        current.isPaused = true
        session = current
        TimerAlerts.cancelEnd()
    }

    func resume() {
        guard var current = session, current.isPaused else { return }
        let now = Date()
        current.breakAccumulated += now.timeIntervalSince(current.segmentStart)
        current.segmentStart = now
        current.isPaused = false
        session = current

        if current.isCountdown {
            TimerAlerts.scheduleEnd(in: current.remainingSeconds(at: now), className: current.className)
        }
    }

    /// Saves the study and break time to the class, then clears the timer.
    func finish(into store: DataStore) {
        guard let current = session else { return }
        let now = Date()
        let study = current.studySeconds(at: now)
        let rest = current.breakSeconds(at: now)

        if study >= 1 || rest >= 1 {
            store.addStudyLog(
                classID: current.classID,
                assignmentID: current.assignmentID,
                date: current.startedAt,
                study: study,
                breaks: rest
            )
        }
        TimerAlerts.cancelEnd()
        session = nil
    }

    func discard() {
        TimerAlerts.cancelEnd()
        session = nil
    }
}

// MARK: - Small shared views

/// "⏱ 25m" shown under a class name.
struct StudyTimeTag: View {
    let seconds: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "stopwatch")
            Text(shortDuration(seconds))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
    }
}

/// Shows at the top of the home screen while a timer is running.
struct ActiveTimerBanner: View {
    @EnvironmentObject private var timerStore: TimerStore
    @Binding var path: [Route]

    var body: some View {
        if let session = timerStore.session {
            Button {
                path.append(.timer(session.classID))
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let now = context.date
                    HStack(spacing: 12) {
                        Image(systemName: session.isPaused ? "pause.circle.fill" : "stopwatch.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.className)
                                .font(.headline)
                            Text(statusText(session, now: now))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                        Spacer()
                        Text(session.displayTime(at: now))
                            .font(Font.title3.bold().monospacedDigit())
                    }
                    .foregroundStyle(Color.white)
                    .padding(16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func statusText(_ session: TimerSession, now: Date) -> String {
        if session.isFinished(at: now) { return "Time's up!" }
        if session.isPaused { return "On a break" }
        return session.isCountdown ? "Time left" : "Studying"
    }
}

// MARK: - Timer screen

struct TimerView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var timerStore: TimerStore
    @Environment(\.dismiss) private var dismiss

    let classID: UUID
    @State private var isClosing = false

    var body: some View {
        Group {
            if let session = timerStore.session {
                RunningTimerContent(
                    session: session,
                    requestedClassID: classID,
                    onFinish: { close(save: true) },
                    onDiscard: { close(save: false) }
                )
            } else if isClosing {
                Color.clear
            } else {
                TimerSetupContent(classID: classID)
            }
        }
        .background { AppBackground() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func close(save: Bool) {
        isClosing = true
        if save {
            timerStore.finish(into: store)
        } else {
            timerStore.discard()
        }
        dismiss()
    }
}

// Pick what you're working on, countdown or stopwatch, then start
struct TimerSetupContent: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var timerStore: TimerStore

    let classID: UUID

    @State private var isCountdown = true
    @State private var minutes = 25
    @State private var selectedAssignmentID: UUID?
    @State private var didPickDefault = false

    private let presets = [15, 25, 30, 45, 60]

    private var schoolClass: SchoolClass? {
        store.classes.first { $0.id == classID }
    }

    /// Today's homework and tests for this class.
    private var assignments: [Assignment] {
        guard let list = store.list(for: Date()),
              let entry = list.entries.first(where: { $0.classID == classID }) else { return [] }
        return entry.assignments
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Study timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(schoolClass?.flowTitle ?? "Class")
                        .font(.largeTitle.bold())
                }

                if !assignments.isEmpty {
                    assignmentCard
                }

                Picker("Mode", selection: $isCountdown) {
                    Text("Countdown").tag(true)
                    Text("Stopwatch").tag(false)
                }
                .pickerStyle(.segmented)

                if isCountdown {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How long do you want to study?")
                            .font(.headline)

                        Stepper(value: $minutes, in: 1...240, step: 5) {
                            Text("\(minutes) minutes")
                                .font(.title3.weight(.semibold))
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                            ForEach(presets, id: \.self) { preset in
                                Button {
                                    minutes = preset
                                } label: {
                                    Text("\(preset)m")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            minutes == preset ? Theme.accent : Theme.cardHigh,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .card()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stopwatch")
                            .font(.headline)
                        Text("Counts up while you work. Pause any time to take a break. Break time is tracked separately.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Start") {
                start()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onAppear {
            // Start on the first thing that isn't finished yet.
            guard !didPickDefault else { return }
            didPickDefault = true
            selectedAssignmentID = assignments
                .first(where: { !$0.isFinished && !$0.isSkippedToday })?
                .id
        }
    }

    // MARK: What are you working on?

    private var assignmentCard: some View {
        let items = assignments

        return VStack(alignment: .leading, spacing: 8) {
            Text("What are you working on?")
                .font(.headline)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                choiceRow(
                    title: item.label(index: index, of: items.count),
                    subtitle: subtitle(for: item),
                    isSelected: selectedAssignmentID == item.id
                ) {
                    selectedAssignmentID = item.id
                }
            }

            choiceRow(
                title: "Just the class",
                subtitle: "Not for one specific assignment",
                isSelected: selectedAssignmentID == nil
            ) {
                selectedAssignmentID = nil
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func subtitle(for item: Assignment) -> String {
        var parts: [String] = [item.kind == .study ? "Study / test" : "Homework"]
        if let due = item.dueDate {
            parts.append(due.isToday ? "due today" : "due \(due.weekdayShort)")
        }
        if item.isFinished {
            parts.append("finished")
        } else if item.isSkippedToday {
            parts.append("not today")
        }
        return parts.joined(separator: " · ")
    }

    private func choiceRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.cardHigh : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func start() {
        if isCountdown {
            NotificationScheduler.requestPermission()
        }

        let items = assignments
        var title: String?
        if let id = selectedAssignmentID, let index = items.firstIndex(where: { $0.id == id }) {
            title = items[index].label(index: index, of: items.count)
        }

        timerStore.start(
            classID: classID,
            className: schoolClass?.flowTitle ?? "Class",
            assignmentID: title == nil ? nil : selectedAssignmentID,
            assignmentTitle: title,
            isCountdown: isCountdown,
            minutes: minutes
        )
    }
}

// The big running timer with pause / resume / finish
struct RunningTimerContent: View {
    @EnvironmentObject private var timerStore: TimerStore

    let session: TimerSession
    let requestedClassID: UUID
    let onFinish: () -> Void
    let onDiscard: () -> Void

    @State private var confirmDiscard = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            content(at: context.date)
        }
        .confirmationDialog(
            "Discard this timer?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                onDiscard()
            }
            Button("Keep Timing", role: .cancel) {}
        } message: {
            Text("The time won't be saved.")
        }
    }

    private func content(at now: Date) -> some View {
        let finished = session.isFinished(at: now)
        let targetForBar = max(session.targetSeconds, 1)

        return ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(session.className)
                        .font(.title.bold())
                    if let title = session.assignmentTitle {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                    }
                    Text(statusText(finished: finished))
                        .font(.headline)
                        .foregroundStyle(finished ? Theme.success : Theme.textSecondary)
                }

                if requestedClassID != session.classID {
                    Text("A timer is already running. Finish it before starting another.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(session.displayTime(at: now))
                    .font(Font.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if session.isCountdown {
                    ProgressView(
                        value: min(session.studySeconds(at: now), targetForBar),
                        total: targetForBar
                    )
                    .tint(Theme.accent)
                }

                HStack(spacing: 12) {
                    statCard(title: "Studied", value: clockString(session.studySeconds(at: now)))
                    statCard(title: "Break", value: clockString(session.breakSeconds(at: now)))
                }

                VStack(spacing: 12) {
                    if finished {
                        Button("Finish & Save") {
                            onFinish()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button(session.isPaused ? "Resume" : "Pause") {
                            if session.isPaused {
                                timerStore.resume()
                            } else {
                                timerStore.pause()
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Finish & Save") {
                            onFinish()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Button("Discard timer") {
                        confirmDiscard = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
    }

    private func statusText(finished: Bool) -> String {
        if finished { return "Time's up!" }
        if session.isPaused { return "On a break" }
        return session.isCountdown ? "Time left" : "Studying"
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Font.title2.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}
