import ActivityKit
import Foundation

// This file must belong to BOTH the ClassList app and the widget extension.

/// What the Dynamic Island / lock screen timer needs to know.
nonisolated struct StudyTimerAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var isCountdown: Bool
        var isPaused: Bool
        /// The on-screen clock counts between these two times.
        var rangeStart: Date
        var rangeEnd: Date
        /// When paused, the clock freezes at this moment.
        var pausedAt: Date?
    }

    var className: String
}
