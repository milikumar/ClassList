import SwiftUI
import WidgetKit

// Widget extension only. This is the entry point for the extension.

@main
struct StudyTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        StudyTimerLiveActivity()
        ClassListHomeWidget()
    }
}
