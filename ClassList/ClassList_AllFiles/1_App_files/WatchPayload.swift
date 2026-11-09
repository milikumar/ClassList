import Foundation

// This file must belong to BOTH the ClassList app and the Watch app.
// It's the small bit of data the iPhone and the watch send each other.

/// One of your classes, sent from the iPhone to the watch.
nonisolated struct WatchClass: Codable, Hashable, Identifiable {
    var id: UUID
    var period: Int
    var name: String        // empty if you only use numbers

    var title: String { name.isEmpty ? "Period \(period)" : name }
}

/// One homework or test, sent from the watch to the iPhone.
nonisolated struct WatchLoggedItem: Codable, Hashable {
    var isStudy: Bool
    /// Days after today (0 = today, 1 = tomorrow...). nil = no due date.
    var dueOffset: Int?
}

/// What you answered for one class. No items = "No homework".
nonisolated struct WatchLoggedClass: Codable, Hashable {
    var classID: UUID
    var items: [WatchLoggedItem]
}

/// Everything you logged on the watch for one day.
nonisolated struct WatchLogPayload: Codable {
    var dayStart: Date
    var classes: [WatchLoggedClass]
}
