import SwiftUI
import WatchConnectivity

// iPhone app only. Talks to the watch: sends it your classes, and receives what you log there.

nonisolated final class PhoneConnectivity: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneConnectivity()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends your list of classes to the watch.
    func sendClasses(_ classes: [WatchClass]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(classes) else { return }
        try? session.updateApplicationContext(["classes": data])
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            PhoneBridge.shared.pushClasses()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            PhoneBridge.shared.pushClasses()
        }
    }

    /// The watch sent something you logged.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["log"] as? Data else { return }
        Task { @MainActor in
            PhoneBridge.shared.receive(logData: data)
        }
    }
}

/// Connects the watch messages to your saved data.
@MainActor
final class PhoneBridge {
    static let shared = PhoneBridge()

    private weak var store: DataStore?
    private let pendingKey = "classlist.pendingWatchLogs"

    func attach(_ store: DataStore) {
        self.store = store
        applyPending()
        pushClasses()
    }

    func pushClasses() {
        guard let store else { return }
        let list = store.classes.map {
            WatchClass(id: $0.id, period: $0.period, name: $0.trimmedName)
        }
        PhoneConnectivity.shared.sendClasses(list)
    }

    func receive(logData: Data) {
        if let store, let payload = try? JSONDecoder().decode(WatchLogPayload.self, from: logData) {
            apply(payload, to: store)
        } else {
            // The app isn't open yet. Keep it and add it the next time it opens.
            var pending = UserDefaults.standard.array(forKey: pendingKey) as? [Data] ?? []
            pending.append(logData)
            UserDefaults.standard.set(pending, forKey: pendingKey)
        }
    }

    private func applyPending() {
        guard let store,
              let pending = UserDefaults.standard.array(forKey: pendingKey) as? [Data],
              !pending.isEmpty else { return }

        UserDefaults.standard.removeObject(forKey: pendingKey)
        for data in pending {
            if let payload = try? JSONDecoder().decode(WatchLogPayload.self, from: data) {
                apply(payload, to: store)
            }
        }
    }

    private func apply(_ payload: WatchLogPayload, to store: DataStore) {
        let day = payload.dayStart.startOfDay
        var entries: [ClassEntry] = []

        for logged in payload.classes {
            guard let schoolClass = store.classes.first(where: { $0.id == logged.classID }) else { continue }

            var assignments: [Assignment] = []
            for item in logged.items {
                let due = item.dueOffset.map { day.adding(days: $0) }
                assignments.append(Assignment(kind: item.isStudy ? .study : .homework, dueDate: due))
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

        guard !entries.isEmpty else { return }
        store.saveEntries(entries, on: day)
    }
}
