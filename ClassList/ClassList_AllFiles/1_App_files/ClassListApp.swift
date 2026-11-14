import SwiftUI

// MARK: - App entry point

@main
struct ClassListApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DataStore()
    @StateObject private var timerStore = TimerStore()
    @StateObject private var canvasStore = CanvasStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(timerStore)
                .environmentObject(canvasStore)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .fontDesign(.rounded)
        }
    }
}

// MARK: - Navigation

nonisolated enum Route: Hashable {
    /// Log classes for a day: the date and which classes to ask about.
    case log(Date, [UUID])
    case dayList(UUID)
    case pastLists
    case settings
    case schedule
    case timer(UUID)
    case canvas
}

struct RootView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var timerStore: TimerStore
    @EnvironmentObject private var canvasStore: CanvasStore
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        Group {
            if store.classes.isEmpty {
                SetupView()
            } else {
                NavigationStack(path: $path) {
                    HomeView(path: $path)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .log(let date, let classIDs):
                                TrackFlowView(path: $path, date: date, classIDs: classIDs)
                            case .dayList(let id):
                                DayListView(listID: id)
                            case .pastLists:
                                PastListsView(path: $path)
                            case .settings:
                                SettingsView()
                            case .schedule:
                                ScheduleView()
                            case .timer(let classID):
                                TimerView(classID: classID)
                            case .canvas:
                                CanvasSettingsView()
                            }
                        }
                }
            }
        }
        .onAppear {
            NotificationScheduler.refresh(using: store)
            WidgetSync.refresh(store: store, timerStore: timerStore)
            PhoneBridge.shared.attach(store)
            Task { await canvasStore.refresh() }
            handlePendingAction()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                NotificationScheduler.refresh(using: store)
                LiveActivityManager.sync(with: timerStore.session, canStart: false)
                Task { await canvasStore.refresh() }
                WidgetSync.refresh(store: store, timerStore: timerStore)
                PhoneBridge.shared.attach(store)
                handlePendingAction()
            }
        }
        .onChange(of: store.schedule) { _, _ in
            NotificationScheduler.refresh(using: store)
        }
        .onChange(of: store.loggedSignature) { _, _ in
            NotificationScheduler.refresh(using: store)
        }
        .onChange(of: store.lists) { _, _ in
            WidgetSync.refresh(store: store, timerStore: timerStore)
        }
        .onChange(of: store.classes) { _, _ in
            WidgetSync.refresh(store: store, timerStore: timerStore)
            PhoneBridge.shared.pushClasses()
        }
        .onChange(of: timerStore.session) { _, _ in
            WidgetSync.refresh(store: store, timerStore: timerStore)
        }
        .onChange(of: router.pendingAction) { _, _ in
            handlePendingAction()
        }
    }

    /// Runs when you tap a notification.
    private func handlePendingAction() {
        guard let action = router.pendingAction else { return }
        guard !store.classes.isEmpty else { return }
        router.pendingAction = nil

        switch action {
        case .logClass(let classID, let date):
            path = [.log(date, [classID])]
        case .recordMissing(let date):
            let ids = store.unloggedClasses(on: date).map { $0.id }
            path = [.log(date, ids)]
        case .openTimer:
            if let session = timerStore.session {
                path = [.timer(session.classID)]
            }
        }
    }
}
