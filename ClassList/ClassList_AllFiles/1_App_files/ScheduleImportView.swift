import SwiftUI
import PhotosUI
import Vision
import UIKit
import ImageIO

// App only. Reads a picture of your bell schedule on your phone (nothing is uploaded),
// finds times like "8:00 - 8:50", and lets you check them before adding.

// MARK: - Reading text from the picture

nonisolated struct ImageBox: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

nonisolated enum ScheduleOCR {
    /// Returns the text in the picture, one string per row of the page (left to right).
    static func readRows(from image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let box = ImageBox(cgImage: cgImage, orientation: orientation(for: image.imageOrientation))

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: recognizeRows(box))
            }
        }
    }

    private static func recognizeRows(_ box: ImageBox) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: box.cgImage, orientation: box.orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        struct Piece {
            let text: String
            let minX: CGFloat
            let midY: CGFloat
            let height: CGFloat
        }

        var pieces: [Piece] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let frame = observation.boundingBox
            pieces.append(Piece(text: candidate.string, minX: frame.minX, midY: frame.midY, height: frame.height))
        }

        // Group pieces that sit on the same line, from top to bottom.
        let topToBottom = pieces.sorted { $0.midY > $1.midY }
        var rows: [[Piece]] = []
        for piece in topToBottom {
            if let current = rows.last, let anchor = current.first,
               abs(anchor.midY - piece.midY) < max(anchor.height, piece.height) * 0.6 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }

        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map { $0.text }.joined(separator: "   ")
        }
    }

    private static func orientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Finding class times in that text

nonisolated struct ScheduleCandidate {
    var label: String
    var startMinutes: Int
    var endMinutes: Int
}

nonisolated enum ScheduleParser {
    // 8:00 - 8:50, 8:00-8:50, 8:00 AM to 8:50 AM, 8.00 – 8.50
    private static let rangePattern =
        #"(\d{1,2})[:.](\d{2})\s*([AaPp]\.?[Mm]\.?)?\s*(?:[-–—−~]|to|until)\s*(\d{1,2})[:.](\d{2})\s*([AaPp]\.?[Mm]\.?)?"#

    static func candidates(from rows: [String]) -> [ScheduleCandidate] {
        guard let regex = try? NSRegularExpression(pattern: rangePattern, options: [.caseInsensitive]) else {
            return []
        }

        var result: [ScheduleCandidate] = []

        for row in rows {
            let fullRange = NSRange(row.startIndex..., in: row)
            let matches = regex.matches(in: row, options: [], range: fullRange)
            var previousEnd = row.startIndex

            for (matchIndex, match) in matches.enumerated() {
                guard let matchRange = Range(match.range, in: row) else { continue }

                func group(_ index: Int) -> String? {
                    guard let range = Range(match.range(at: index), in: row) else { return nil }
                    return String(row[range])
                }

                // The words just before the time, like "Period 3"
                var label = clean(String(row[previousEnd..<matchRange.lowerBound]))
                if label.isEmpty && matchIndex == matches.count - 1 {
                    label = clean(String(row[matchRange.upperBound...]))
                }
                previousEnd = matchRange.upperBound

                guard let startHour = Int(group(1) ?? ""),
                      let startMinute = Int(group(2) ?? ""),
                      let endHour = Int(group(4) ?? ""),
                      let endMinute = Int(group(5) ?? "") else { continue }

                guard let times = resolve(
                    startHour: startHour, startMinute: startMinute, startMeridiem: group(3),
                    endHour: endHour, endMinute: endMinute, endMeridiem: group(6)
                ) else { continue }

                let isDuplicate = result.contains {
                    $0.startMinutes == times.start && $0.endMinutes == times.end && $0.label == label
                }
                if !isDuplicate {
                    result.append(ScheduleCandidate(label: label, startMinutes: times.start, endMinutes: times.end))
                }
            }
        }

        return result
    }

    /// The first number in some text ("Period 3" -> 3).
    static func firstNumber(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\d{1,2}"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Int(text[range])
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func meridiemLetter(_ text: String?) -> Character? {
        text?.lowercased().first
    }

    private static func to24(_ hour: Int, _ meridiem: Character?) -> Int {
        guard let meridiem else { return hour }
        if meridiem == "p" { return hour < 12 ? hour + 12 : hour }
        return hour == 12 ? 0 : hour
    }

    private static func resolve(
        startHour: Int, startMinute: Int, startMeridiem: String?,
        endHour: Int, endMinute: Int, endMeridiem: String?
    ) -> (start: Int, end: Int)? {
        guard (0...23).contains(startHour), (0...59).contains(startMinute),
              (0...23).contains(endHour), (0...59).contains(endMinute) else { return nil }

        let startLetter = meridiemLetter(startMeridiem)
        let endLetter = meridiemLetter(endMeridiem)

        var sh = startHour
        var eh = endHour

        if startLetter == nil && endLetter == nil {
            // No AM/PM written: school times from 1 to 6 are the afternoon.
            if (1...6).contains(sh) { sh += 12 }
            if (1...6).contains(eh) { eh += 12 }
        } else {
            sh = to24(sh, startLetter ?? endLetter)
            eh = to24(eh, endLetter ?? startLetter)
        }

        var start = sh * 60 + startMinute
        let end = eh * 60 + endMinute

        // "11:15 - 12:05 PM": the start was really in the morning.
        if start > end && startLetter == nil && start - 720 >= 0 {
            start -= 720
        }

        guard end > start, end - start >= 5, end - start <= 300 else { return nil }
        return (start, end)
    }
}

// MARK: - The import screen

struct ScheduleImportView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    struct ImportRow: Identifiable {
        let id = UUID()
        var label: String
        var startMinutes: Int
        var endMinutes: Int
        var classID: UUID?
        var include: Bool
    }

    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isReading = false
    @State private var message: String?
    @State private var rows: [ImportRow] = []
    @State private var selectedDays: Set<Int> = [2, 3, 4, 5, 6]

    private let weekdays: [(number: Int, name: String)] = [
        (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri")
    ]

    private var includedCount: Int {
        rows.filter { $0.include && $0.classID != nil }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Import from a picture")
                        .font(.largeTitle.bold())
                    Text("Choose a clear photo or screenshot of your bell schedule. I'll read the times on your phone, then you check them and pick the classes.")
                        .foregroundStyle(Theme.textSecondary)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(
                            previewImage == nil ? "Choose a picture" : "Choose a different picture",
                            systemImage: "photo"
                        )
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(maxWidth: .infinity)
                    }

                    if isReading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading the picture…")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }

                    if !rows.isEmpty {
                        reviewSection
                    }
                }
                .padding(20)
            }
            .background { AppBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !rows.isEmpty {
                    Button("Add \(includedCount) to \(store.activeScheduleName)") {
                        addToSchedule()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(includedCount == 0 || selectedDays.isEmpty)
                    .opacity(includedCount == 0 || selectedDays.isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await load(newItem) }
            }
        }
    }

    // MARK: Review

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check what I found")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 10) {
                Text("These times are for:")
                    .font(.headline)
                HStack(spacing: 8) {
                    ForEach(weekdays, id: \.number) { day in
                        dayChip(day.number, day.name)
                    }
                }
                Text("This replaces the classes already on those days in \"\(store.activeScheduleName)\".")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            Text("Turn off anything that isn't a class (like lunch), and fix any class or time that's wrong.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            ForEach($rows) { $row in
                rowCard($row)
            }
        }
    }

    private func dayChip(_ number: Int, _ name: String) -> some View {
        let isOn = selectedDays.contains(number)

        return Button {
            if isOn {
                selectedDays.remove(number)
            } else {
                selectedDays.insert(number)
            }
        } label: {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isOn ? Theme.accent : Theme.cardHigh,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func rowCard(_ row: Binding<ImportRow>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("Include", isOn: row.include)
                    .labelsHidden()

                Menu {
                    ForEach(store.classes) { schoolClass in
                        Button(schoolClass.flowTitle) {
                            row.wrappedValue.classID = schoolClass.id
                            row.wrappedValue.include = true
                        }
                    }
                    Button("Not a class", role: .destructive) {
                        row.wrappedValue.classID = nil
                        row.wrappedValue.include = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(className(for: row.wrappedValue.classID))
                            .font(.headline)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                }
                Spacer()
            }

            if !row.wrappedValue.label.isEmpty {
                Text("Read as: \(row.wrappedValue.label)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            DatePicker(
                "Starts",
                selection: timeBinding(row.startMinutes),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "Ends",
                selection: timeBinding(row.endMinutes),
                displayedComponents: .hourAndMinute
            )
        }
        .card()
        .opacity(row.wrappedValue.include ? 1 : 0.55)
    }

    private func className(for id: UUID?) -> String {
        guard let id, let found = store.classes.first(where: { $0.id == id }) else {
            return "Pick a class"
        }
        return found.flowTitle
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    // MARK: Reading the picture

    private func load(_ item: PhotosPickerItem) async {
        isReading = true
        message = nil
        rows = []

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            isReading = false
            message = "I couldn't open that picture. Try a different one."
            return
        }
        previewImage = image

        let lines = await ScheduleOCR.readRows(from: image)
        let found = ScheduleParser.candidates(from: lines)

        rows = found.map { candidate in
            let guess = guessClass(for: candidate.label)
            return ImportRow(
                label: candidate.label,
                startMinutes: candidate.startMinutes,
                endMinutes: candidate.endMinutes,
                classID: guess,
                include: guess != nil
            )
        }
        isReading = false

        if found.isEmpty {
            message = "I couldn't find any times like 8:00 - 8:50 in that picture. Try a closer, clearer photo, or add the times by hand."
        }
    }

    /// Match "Period 3" to your class 3, or a class name written in the row.
    private func guessClass(for label: String) -> UUID? {
        if let number = ScheduleParser.firstNumber(in: label),
           let match = store.classes.first(where: { $0.period == number }) {
            return match.id
        }

        let lowered = label.lowercased()
        if !lowered.isEmpty,
           let named = store.classes.first(where: {
               !$0.trimmedName.isEmpty && lowered.contains($0.trimmedName.lowercased())
           }) {
            return named.id
        }
        return nil
    }

    private func addToSchedule() {
        var items: [(classID: UUID, start: Int, end: Int)] = []
        for row in rows where row.include {
            if let id = row.classID {
                items.append((classID: id, start: row.startMinutes, end: row.endMinutes))
            }
        }
        store.importSlots(items, onWeekdays: selectedDays)
        dismiss()
    }
}
