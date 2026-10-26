import SwiftUI
import WidgetKit

// Widget extension only. The Home Screen widget: today's homework and your timer.

private let widgetAccent = Color(red: 0.56, green: 0.50, blue: 1.0)
private let widgetTop = Color(red: 0.11, green: 0.09, blue: 0.27)
private let widgetBottom = Color(red: 0.055, green: 0.043, blue: 0.14)
private let widgetMuted = Color(red: 0.70, green: 0.68, blue: 0.89)
private let widgetGreen = Color(red: 0.43, green: 0.91, blue: 0.72)
private let widgetRed = Color(red: 1.0, green: 0.42, blue: 0.42)

// MARK: - Data

nonisolated struct HomeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

nonisolated extension WidgetSnapshot {
    /// Fake data shown while the widget is being picked from the widget gallery.
    static var sample: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            dayStart: now,
            updatedAt: now,
            dateLabel: "Today",
            hasList: true,
            isNoSchool: false,
            done: 1,
            total: 3,
            rows: [
                WidgetRow(id: "1", title: "Math", kind: "HW", due: "Fri", priority: 1, isFinished: false, isSkipped: false),
                WidgetRow(id: "2", title: "Science", kind: "Study", due: "Mon", priority: 2, isFinished: false, isSkipped: false),
                WidgetRow(id: "3", title: "English", kind: "HW", due: "Wed", priority: nil, isFinished: true, isSkipped: false)
            ],
            timer: nil
        )
    }
}

nonisolated struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.sample : SharedSnapshotStore.load()
        completion(HomeEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let entry = HomeEntry(date: Date(), snapshot: SharedSnapshotStore.load())
        // The app also refreshes the widget whenever something changes.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Look

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeEntry

    /// Only use the saved list if it's for today (otherwise it's yesterday's).
    private var today: WidgetSnapshot? {
        guard let snapshot = entry.snapshot,
              Calendar.current.isDate(snapshot.dayStart, inSameDayAs: entry.date) else { return nil }
        return snapshot
    }

    private var timer: WidgetTimerInfo? { entry.snapshot?.timer }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemLarge:
                listView(maxRows: 9)
            default:
                listView(maxRows: 4)
            }
        }
        .foregroundStyle(Color.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [widgetTop, widgetBottom], startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Small

    @ViewBuilder
    private var smallView: some View {
        if let timer {
            timerBlock(timer, big: true)
        } else if let today, today.hasList, !today.isNoSchool {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(widgetMuted)
                Text("\(today.done)/\(today.total)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("done")
                    .font(.caption)
                    .foregroundStyle(widgetMuted)
                Spacer(minLength: 0)
                if let next = today.rows.first(where: { !$0.isFinished && !$0.isSkipped }) {
                    Text("Next: \(next.title)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                } else {
                    Text(today.total == 0 ? "No homework" : "All done!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(widgetGreen)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            messageView
        }
    }

    // MARK: Medium and large

    @ViewBuilder
    private func listView(maxRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let timer {
                timerBlock(timer, big: false)
            }

            if let today, today.hasList, !today.isNoSchool {
                let limit = timer == nil ? maxRows : max(maxRows - 1, 1)

                HStack {
                    Text(today.dateLabel)
                        .font(.headline)
                    Spacer()
                    Text("\(today.done)/\(today.total) done")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(widgetMuted)
                }

                if today.rows.isEmpty {
                    Text("No homework today")
                        .font(.subheadline)
                        .foregroundStyle(widgetMuted)
                } else {
                    ForEach(Array(today.rows.prefix(limit))) { row in
                        rowView(row)
                    }
                    if today.rows.count > limit {
                        Text("+\(today.rows.count - limit) more")
                            .font(.caption2)
                            .foregroundStyle(widgetMuted)
                    }
                }
                Spacer(minLength: 0)
            } else if timer == nil {
                messageView
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(today?.isNoSchool == true ? "No school today" : "Nothing tracked yet")
                .font(.headline)
            Text(today?.isNoSchool == true ? "Enjoy the day off!" : "Open ClassList to log today.")
                .font(.caption)
                .foregroundStyle(widgetMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func rowView(_ row: WidgetRow) -> some View {
        HStack(spacing: 6) {
            Text(row.priority.map { "\($0)" } ?? "–")
                .font(.caption.weight(.bold))
                .foregroundStyle(row.priority == nil ? widgetMuted : widgetAccent)
                .frame(width: 14)

            Image(systemName: icon(for: row))
                .font(.caption)
                .foregroundStyle(color(for: row))

            Text(row.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .strikethrough(row.isFinished)

            Spacer(minLength: 2)

            Text(row.kind)
                .font(.caption2)
                .foregroundStyle(widgetMuted)

            Text(row.due)
                .font(.caption2.weight(.semibold))
                .frame(width: 38, alignment: .trailing)
        }
        .opacity((row.isFinished || row.isSkipped) ? 0.55 : 1)
    }

    private func icon(for row: WidgetRow) -> String {
        if row.isSkipped { return "minus.circle.fill" }
        return row.isFinished ? "checkmark.circle.fill" : "circle"
    }

    private func color(for row: WidgetRow) -> Color {
        if row.isSkipped { return widgetRed }
        return row.isFinished ? widgetGreen : widgetMuted
    }

    private func timerBlock(_ timer: WidgetTimerInfo, big: Bool) -> some View {
        let timesUp = timer.isCountdown && !timer.isPaused && timer.rangeEnd <= entry.date
        let status = timesUp ? "Time's up!" : (timer.isPaused ? "On a break" : (timer.isCountdown ? "Time left" : "Studying"))

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: timer.isPaused ? "pause.circle.fill" : "stopwatch.fill")
                    .foregroundStyle(widgetAccent)
                Text(timer.className)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Text(
                timerInterval: timer.rangeStart...max(timer.rangeEnd, timer.rangeStart),
                pauseTime: timer.pausedAt,
                countsDown: timer.isCountdown,
                showsHours: false
            )
            .font(Font.system(size: big ? 40 : 28, weight: .bold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .multilineTextAlignment(.leading)

            Text(status)
                .font(.caption2)
                .foregroundStyle(timesUp ? widgetGreen : widgetMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The widget

struct ClassListHomeWidget: Widget {
    let kind = "ClassListHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("ClassList")
        .description("Today's homework and your study timer.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
