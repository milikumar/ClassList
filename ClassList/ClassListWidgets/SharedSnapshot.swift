import Foundation

// This file must belong to BOTH the ClassList app and the widget extension.
// The app saves a small "snapshot" of today here, and the Home Screen widget reads it.

nonisolated struct WidgetRow: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var kind: String          // "HW" or "Study"
    var due: String           // "Today", "Fri", or "—"
    var priority: Int?
    var isFinished: Bool
    var isSkipped: Bool

    /// 0 = still to do, 1 = finished, 2 = not doing today
    var sortGroup: Int { isSkipped ? 2 : (isFinished ? 1 : 0) }
}

nonisolated struct WidgetTimerInfo: Codable, Hashable {
    var className: String
    var isCountdown: Bool
    var isPaused: Bool
    var rangeStart: Date
    var rangeEnd: Date
    var pausedAt: Date?
}

nonisolated struct WidgetSnapshot: Codable {
    var dayStart: Date
    var updatedAt: Date
    var dateLabel: String
    var hasList: Bool
    var isNoSchool: Bool
    var done: Int
    var total: Int
    var rows: [WidgetRow]
    var timer: WidgetTimerInfo?
}

/// Saves/loads the snapshot in the App Group, which the app and widget share.
nonisolated enum SharedSnapshotStore {
    private static let key = "classlist.widgetSnapshot"

    /// "group." + the app's bundle identifier, for example group.com.mili.classlist2026.
    /// (Works from both the app and the extension, so there's nothing to edit.)
    static var groupID: String {
        var id = Bundle.main.bundleIdentifier ?? ""
        if Bundle.main.bundleURL.pathExtension == "appex" {
            id = id.split(separator: ".").dropLast().joined(separator: ".")
        }
        return "group." + id
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: groupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: groupID),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
