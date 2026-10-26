import ActivityKit
import SwiftUI
import WidgetKit

// Widget extension only. The Dynamic Island and lock screen timer.

private let islandAccent = Color(red: 0.56, green: 0.50, blue: 1.0)
private let panelBackground = Color(red: 0.11, green: 0.09, blue: 0.27)

// MARK: - Shared pieces

private func statusText(_ state: StudyTimerAttributes.ContentState, isStale: Bool) -> String {
    if state.isCountdown && isStale { return "Time's up!" }
    if state.isPaused { return "On a break" }
    return state.isCountdown ? "Time left" : "Studying"
}

/// A clock that keeps counting by itself, even when the app is closed.
private struct StudyTimerText: View {
    let state: StudyTimerAttributes.ContentState

    var body: some View {
        Text(
            timerInterval: state.rangeStart...max(state.rangeEnd, state.rangeStart),
            pauseTime: state.pausedAt,
            countsDown: state.isCountdown,
            showsHours: false
        )
        .monospacedDigit()
    }
}

// MARK: - Lock screen banner

private struct StudyTimerLockScreenView: View {
    let className: String
    let state: StudyTimerAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.isPaused ? "pause.circle.fill" : "stopwatch.fill")
                .font(.title)
                .foregroundStyle(islandAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text(className)
                    .font(.headline)
                    .lineLimit(1)
                Text(statusText(state, isStale: isStale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StudyTimerText(state: state)
                .font(Font.largeTitle.monospacedDigit().bold())
                .frame(width: 130, alignment: .trailing)
        }
        .padding(16)
        .foregroundStyle(.white)
        .activityBackgroundTint(panelBackground)
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - The Live Activity

struct StudyTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyTimerAttributes.self) { context in
            StudyTimerLockScreenView(
                className: context.attributes.className,
                state: context.state,
                isStale: context.isStale
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "stopwatch.fill")
                        .font(.title2)
                        .foregroundStyle(islandAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StudyTimerText(state: context.state)
                        .font(Font.title2.monospacedDigit().bold())
                        .frame(width: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.className)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(statusText(context.state, isStale: context.isStale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "stopwatch.fill")
                    .foregroundStyle(islandAccent)
            } compactTrailing: {
                StudyTimerText(state: context.state)
                    .font(Font.caption.monospacedDigit().bold())
                    .frame(width: 46, alignment: .trailing)
            } minimal: {
                Image(systemName: "stopwatch.fill")
                    .foregroundStyle(islandAccent)
            }
            .keylineTint(islandAccent)
        }
    }
}
