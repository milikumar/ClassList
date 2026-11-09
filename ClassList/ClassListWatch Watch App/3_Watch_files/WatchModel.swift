import SwiftUI
import Combine
import WatchConnectivity

// Watch app only. Keeps your classes (sent from the iPhone) and sends back what you log.

nonisolated final class WatchSessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSessionDelegate()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(logData: Data) {
        WCSession.default.transferUserInfo(["log": logData])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Pick up the classes the iPhone already sent earlier.
        if let data = session.receivedApplicationContext["classes"] as? Data {
            Task { @MainActor in
                WatchModel.shared.receive(classesData: data)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["classes"] as? Data else { return }
        Task { @MainActor in
            WatchModel.shared.receive(classesData: data)
        }
    }
}

@MainActor
final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    @Published var classes: [WatchClass] = []
    @Published var lastSent: Date?

    private let classesKey = "watch.classes"
    private let sentKey = "watch.lastSent"

    init() {
        if let data = UserDefaults.standard.data(forKey: classesKey),
           let saved = try? JSONDecoder().decode([WatchClass].self, from: data) {
            classes = saved
        }
        lastSent = UserDefaults.standard.object(forKey: sentKey) as? Date
    }

    func start() {
        WatchSessionDelegate.shared.activate()
    }

    func receive(classesData: Data) {
        guard let decoded = try? JSONDecoder().decode([WatchClass].self, from: classesData) else { return }
        classes = decoded
        UserDefaults.standard.set(classesData, forKey: classesKey)
    }

    func send(_ payload: WatchLogPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        WatchSessionDelegate.shared.send(logData: data)
        lastSent = Date()
        UserDefaults.standard.set(lastSent, forKey: sentKey)
    }

    var sentToday: Bool {
        guard let lastSent else { return false }
        return Calendar.current.isDateInToday(lastSent)
    }
}
