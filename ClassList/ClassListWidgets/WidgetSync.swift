// xcode: set sdk=iOS

import SwiftUI
import WidgetKit

// App only. Saves today's homework and the running timer for the Home Screen widget.

@MainActor
enum WidgetSync {
    static func refresh(store: DataStore, timerStore: TimerStore) {
        let now = Date()
        let today = now.startOfDay

        var snapshot = WidgetSnapshot(
            dayStart: today,
            updatedAt: now,
            dateLabel: now.formatted(.dateTime.weekday(.wide)),
            hasList: false,
            isNoSchool: false,
            done: 0,
            total: 0,
            rows: [],
            timer: nil
        )

        if let list = store.list(for: today) {
            snapshot.hasList = true
            snapshot.isNoSchool = list.isNoSchool
            snapshot.done = list.doneCount
            snapshot.total = list.totalCount
            snapshot.rows = rows(for: list, store: store)
        }

        if let session = timerStore.session {
            snapshot.timer = timerInfo(session, now: now)
        }

        SharedSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func rows(for list: DayList, store: DataStore) -> [WidgetRow] {
        var result: [WidgetRow] = []

        for entry in list.entries {
            let name = store.displayName(for: entry)

            for (index, item) in entry.assignments.enumerated() {
                let suffix = entry.assignments.count > 1 ? " (\(index + 1))" : ""

                var due = "—"
                if let date = item.dueDate {
                    due = date.isToday ? "Today" : date.weekdayShort
                }

                result.append(
                    WidgetRow(
                        id: item.id.uuidString,
                        title: name + suffix,
                        kind: item.kind == .study ? "Study" : "HW",
                        due: due,
                        priority: item.priority,
                        isFinished: item.isFinished,
                        isSkipped: item.isSkippedToday
                    )
                )
            }
        }

        // Things to do first (by priority), then finished, then "not today".
        return result.sorted { first, second in
            if first.sortGroup != second.sortGroup {
                return first.sortGroup < second.sortGroup
            }
            return (first.priority ?? 99) < (second.priority ?? 99)
        }
    }

    private static func timerInfo(_ session: TimerSession, now: Date) -> WidgetTimerInfo {
        if session.isCountdown {
            let remaining = session.remainingSeconds(at: now)
            return WidgetTimerInfo(
                className: session.className,
                isCountdown: true,
                isPaused: session.isPaused,
                rangeStart: now,
                rangeEnd: now.addingTimeInterval(remaining),
                pausedAt: session.isPaused ? now : nil
            )
        } else {
            let study = session.studySeconds(at: now)
            let virtualStart = now.addingTimeInterval(-study)
            return WidgetTimerInfo(
                className: session.className,
                isCountdown: false,
                isPaused: session.isPaused,
                rangeStart: virtualStart,
                rangeEnd: virtualStart.addingTimeInterval(12 * 3600),
                pausedAt: session.isPaused ? now : nil
            )
        }
    }
}
