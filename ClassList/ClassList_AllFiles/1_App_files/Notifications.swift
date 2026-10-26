import SwiftUI
import Combine
import UIKit
import UserNotifications

// MARK: - What a tapped notification asks the app to do

nonisolated enum PendingAction: Equatable {
    case logClass(classID: UUID, date: Date)
    case recordMissing(date: Date)
    case openTimer
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pendingAction: PendingAction?
}

// MARK: - Set up as early as possible so notification taps are never missed

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        return true
    }
}

// MARK: - Receives notification taps (and shows banners while the app is open)

nonisolated final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String ?? ""
        let classID = (info["classID"] as? String).flatMap { UUID(uuidString: $0) }
        let date = (info["date"] as? Double).map { Date(timeIntervalSince1970: $0) }

        Task { @MainActor in
            switch type {
            case "log":
                if let classID, let date {
                    AppRouter.shared.pendingAction = .logClass(classID: classID, date: date)
                }
            case "missing":
                if let date {
                    AppRouter.shared.pendingAction = .recordMissing(date: date)
                }
            case "timer":
                AppRouter.shared.pendingAction = .openTimer
            default:
                break
            }
        }

        completionHandler()
    }
}

// MARK: - Schedules the class reminders

@MainActor
enum NotificationScheduler {
    private struct Reminder {
        let id: String
        let title: String
        let body: String
        let date: Date
        let info: [String: Any]
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Schedules the next 7 days of reminders. Classes you've already logged
    /// and "No school" days are skipped. (Timer alerts are never touched here.)
    static func refresh(using store: DataStore) {
        let now = Date()
        let today = now.startOfDay
        var reminders: [Reminder] = []

        for offset in 0..<7 {
            let day = today.adding(days: offset)
            if store.list(for: day)?.isNoSchool == true { continue }

            var lastEnd: Date?

            for slot in store.slots(on: day) {
                guard let schoolClass = store.classes.first(where: { $0.id == slot.classID }),
                      let fireDate = date(atMinutes: slot.endMinutes, on: day) else { continue }

                if let current = lastEnd {
                    lastEnd = max(current, fireDate)
                } else {
                    lastEnd = fireDate
                }

                if fireDate <= now || store.isLogged(slot.classID, on: day) { continue }

                reminders.append(
                    Reminder(
                        id: "log-\(Int(day.timeIntervalSince1970))-\(slot.id.uuidString)",
                        title: "Log \(schoolClass.flowTitle)",
                        body: "Any homework or studying? Tap to log it now.",
                        date: fireDate,
                        info: [
                            "type": "log",
                            "classID": slot.classID.uuidString,
                            "date": day.timeIntervalSince1970
                        ]
                    )
                )
            }

            if let lastEnd {
                let reminderDate = lastEnd.addingTimeInterval(15 * 60)
                if reminderDate > now && !store.unloggedClasses(on: day).isEmpty {
                    reminders.append(
                        Reminder(
                            id: "missing-\(Int(day.timeIntervalSince1970))",
                            title: "Record missing classes",
                            body: "Missed logging a class today? Tap to catch up.",
                            date: reminderDate,
                            info: [
                                "type": "missing",
                                "date": day.timeIntervalSince1970
                            ]
                        )
                    )
                }
            }
        }

        // Remove class reminders that no longer apply (only ones we made).
        let wantedIDs = Set(reminders.map { $0.id })
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let stale = requests.map { $0.identifier }.filter { id in
                (id.hasPrefix("log-") || id.hasPrefix("missing-")) && !wantedIDs.contains(id)
            }
            if !stale.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
            }
        }

        // Adding with the same id simply replaces the old one.
        for reminder in reminders {
            add(reminder)
        }
    }

    private static func date(atMinutes minutes: Int, on day: Date) -> Date? {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    private static func add(_ reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = reminder.info

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
