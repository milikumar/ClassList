# ClassList

ClassList is a native SwiftUI planner for keeping track of classes, daily homework, study tasks, and time spent studying. It includes an iPhone app, a Home Screen widget and Live Activity, and an Apple Watch companion for logging work.

New to iOS architecture? See the beginner-friendly [architecture guide](ARCHITECTURE.md).

## Architecture

The iPhone app uses a small, view-driven SwiftUI structure. `ClassListApp` creates the shared `DataStore` and routes between setup, home, schedule, timer, and settings screens. The store keeps class, schedule, daily list, and study-session data on device using `UserDefaults`.

```text
ClassListApp
  └─ RootView (setup and navigation)
       ├─ SetupView → HomeView
       ├─ TrackFlowView → DayListView
       ├─ ScheduleView / ScheduleImportView
       ├─ TimerView
       └─ PastListsView / SettingsView

DataStore
  ├─ Classes, daily lists, schedules, and study logs
  ├─ WidgetSync → shared widget snapshot → Home Screen widget
  ├─ TimerStore → Live Activity and timer notifications
  └─ PhoneBridge ↔ WatchConnectivity ↔ WatchModel
```

### Project layout

- `ClassList/ClassList.xcodeproj` — Xcode project and shared build schemes.
- `ClassList/ClassList_AllFiles/1_App_files/ClassListApp.swift` — App entry point, shared stores, and navigation routes.
- `ClassList/ClassList_AllFiles/1_App_files/Models.swift` — Class, assignment, day list, schedule, and study log models, plus the on-device `DataStore`.
- `ClassList/ClassList_AllFiles/1_App_files/SetupAndHomeViews.swift` — First-run setup and the home feed of today and past lists.
- `ClassList/ClassList_AllFiles/1_App_files/TrackFlowView.swift` — Guided homework and study logging flow.
- `ClassList/ClassList_AllFiles/1_App_files/DayListView.swift`, `PastListsAndSettingsViews.swift` — Daily list details, editing, past lists, and settings.
- `ClassList/ClassList_AllFiles/1_App_files/ScheduleView.swift`, `ScheduleImportView.swift` — Weekly schedules and schedule import from an image.
- `ClassList/ClassList_AllFiles/1_App_files/TimerFeature.swift`, `StudyTimerAttributes.swift` — Study timer state, notifications, and Live Activity attributes.
- `ClassList/ClassList_AllFiles/1_App_files/PhoneConnectivity.swift`, `WatchPayload.swift` — iPhone/watch message handling and shared payload models.
- `ClassList/ClassList_AllFiles/1_App_files/WidgetSync.swift`, `SharedSnapshot.swift` — Snapshot data sent to the widget extension.
- `ClassList/ClassList_AllFiles/1_App_files/Theme.swift`, `Notifications.swift` — Shared appearance and notification routing/scheduling.
- `ClassList/ClassListWidgets/` — Home Screen widget and Live Activity extension.
- `ClassList/ClassListWatch Watch App/3_Watch_files/` — Watch app screens, local model, and entry point.
- `ClassList/Assets.xcassets/` — iPhone app icons and accent color.

## Features

### Classes and daily lists

- Set up 1–10 classes with names or period numbers.
- Log homework, study/test tasks, due dates, and optional assignment names for each class.
- Mark a class as having no homework or no class that day, and mark, skip, edit, or reprioritize assignments.
- Browse today's list and past lists, with blank weekday cards for days without a saved list.

### Schedules

- Create and switch between named weekly schedules.
- Set class meeting days and times.
- Import a schedule from a photo using on-device image text recognition, then choose weekdays before adding the detected slots.

### Study timer

- Run a count-up or countdown study timer for a class, optionally linked to an assignment.
- Pause for breaks and keep accumulated study and break time in the study log.
- Keep timer state across app launches, receive timer-end notifications, and show an active timer on the Lock Screen and Dynamic Island where supported.

### Widgets and Apple Watch

- The Home Screen widget summarizes today's assignments and can display the active study timer.
- The watch receives the class list from the iPhone and provides a tap-based flow for recording homework, study/tests, and due days.
- Watch entries are transferred to the iPhone and merged into the matching day's list by class.

### Appearance and notifications

- The app uses a shared SwiftUI theme and includes settings for app appearance.
- Notifications can remind you about scheduled class days and an expiring countdown timer.

## Build and run

Open `ClassList/ClassList.xcodeproj` in Xcode and run the `ClassList` scheme on an iOS simulator or device. The project currently sets an iOS deployment target of 26.5 and a watchOS deployment target of 26.6. The watch app and widgets can be run on their corresponding simulators when those runtimes are installed.

## Data and integrations

- Classes, schedules, daily lists, timer state, and study logs are stored locally using `UserDefaults`.
- The iPhone and watch exchange classes and watch-entered daily logs with WatchConnectivity.
- The widget and iPhone share widget snapshots through the app's shared snapshot store.
- Schedule photo import uses Apple's Vision text-recognition framework.

## Maintaining this document

Update this README when a meaningful feature, app target, data flow, or platform requirement changes. Keep the project layout and feature descriptions aligned with the source in `ClassList/`.
