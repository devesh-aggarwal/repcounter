import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var unit: String = "lbs"
    var minValue: Double = 0
    var maxValue: Double = 500
    var step: Double = 2.5
    var currentValue: Double = 0
    var colorHex: String = "#30D158"
    var iconName: String = "dumbbell.fill"
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    /// Which split day this exercise belongs to (SplitDay raw value).
    var dayRaw: String = SplitDay.push.rawValue
    /// Position within its split day.
    var orderInDay: Int = 0
    /// Weight of the empty bar, used by the plate calculator.
    var barWeight: Double = 45
    /// Default rest-timer duration in seconds.
    var restSeconds: Int = 90
    /// True only for exercises that load free-weight plates onto a bar
    /// (Smith machine, barbell). Most gym machines just set a weight pin and
    /// don't need plate math, so this is opt-in per exercise.
    var usesPlates: Bool = false
    /// How many sets you plan to do for this exercise in a session.
    var targetSets: Int = 3
    /// Sets checked off so far. Scoped to `setsLogDate` — see
    /// `completedSetsToday`, which auto-resets the count across days.
    var completedSetsRaw: Int = 0
    /// The day `completedSetsRaw` belongs to. When it isn't today, the count
    /// is treated as zero so each session starts fresh without a nightly job.
    var setsLogDate: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \ProgressEntry.exercise)
    var entries: [ProgressEntry] = []

    init(
        name: String,
        unit: String = "lbs",
        minValue: Double = 0,
        maxValue: Double = 500,
        step: Double = 5,
        currentValue: Double = 0,
        colorHex: String = "#00E676",
        iconName: String = "dumbbell.fill",
        sortIndex: Int = 0,
        barWeight: Double = 45,
        restSeconds: Int = 90
    ) {
        self.id = UUID()
        self.name = name
        self.unit = unit
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.currentValue = currentValue
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortIndex = sortIndex
        self.barWeight = barWeight
        self.restSeconds = restSeconds
        self.createdAt = Date()
        self.entries = []
    }

    /// The split day this exercise belongs to.
    var day: SplitDay {
        get { SplitDay(rawValue: dayRaw) ?? .push }
        set { dayRaw = newValue.rawValue }
    }

    var sortedEntries: [ProgressEntry] {
        entries.sorted { $0.date < $1.date }
    }

    var stats: ExerciseStats {
        ExerciseStats(entries: sortedEntries, fallbackValue: currentValue)
    }

    /// True for weight-bearing units where bar weight + plate math could
    /// theoretically apply. Whether the user actually wants plate calc is
    /// gated by `usesPlates`.
    var isWeightUnit: Bool { unit == "lbs" || unit == "kg" }

    /// The most recent session before today, used as the "last time" reference.
    /// Falls back to the latest entry when today's is the only one.
    var priorEntry: ProgressEntry? {
        let sorted = sortedEntries
        guard let last = sorted.last else { return nil }
        if Calendar.current.isDateInToday(last.date) {
            return sorted.dropLast().last ?? last
        }
        return last
    }

    /// True when the current value matches or exceeds every logged value.
    var isAtPersonalBest: Bool {
        let values = entries.map(\.value)
        guard values.count >= 2, let best = values.max() else { return false }
        return currentValue >= best && currentValue > (sortedEntries.first?.value ?? currentValue)
    }

    /// Whether there's a logged entry dated today — i.e. the user has
    /// actively recorded this exercise in the current session.
    var isLoggedToday: Bool {
        let calendar = Calendar.current
        return entries.contains { calendar.isDateInToday($0.date) }
    }

    /// The value logged today, if any. Used for "weight moved today" totals.
    var todayLoggedValue: Double? {
        let calendar = Calendar.current
        return entries.first(where: { calendar.isDateInToday($0.date) })?.value
    }

    // MARK: - Set counting

    /// Hard ceiling on logged sets so a stuck button or fat-finger can't run
    /// the count away. Plenty of headroom for any real workout.
    static let maxSets = 30

    /// Number of sets checked off for *today*. Returns zero automatically when
    /// the stored count belongs to a previous day, so every session starts at
    /// zero without needing a scheduled reset.
    var completedSetsToday: Int {
        Calendar.current.isDateInToday(setsLogDate) ? completedSetsRaw : 0
    }

    /// True once you've checked off every planned set for today.
    var allSetsDone: Bool {
        targetSets > 0 && completedSetsToday >= targetSets
    }

    /// Check off one set for today. Handles the day rollover and clamping, and
    /// returns the new completed count so callers can drive haptics/animation.
    @discardableResult
    func logSet() -> Int {
        completedSetsRaw = min(completedSetsToday + 1, Self.maxSets)
        setsLogDate = Date()
        return completedSetsRaw
    }

    /// Undo the most recent set for today (floored at zero).
    @discardableResult
    func undoSet() -> Int {
        completedSetsRaw = max(completedSetsToday - 1, 0)
        setsLogDate = Date()
        return completedSetsRaw
    }
}
