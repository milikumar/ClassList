import SwiftUI

// Watch app only. The entry point of the watch app.

@main
struct ClassListWatchApp: App {
    @StateObject private var model = WatchModel.shared

    init() {
        WatchModel.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
        }
    }
}
