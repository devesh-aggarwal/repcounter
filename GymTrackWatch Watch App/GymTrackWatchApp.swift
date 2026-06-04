import SwiftUI
import SwiftData

/// watchOS entry point. Mirrors the iPhone app's SwiftData setup — the same
/// `Exercise` and `ProgressEntry` schema, the same CloudKit-backed
/// configuration so a single iCloud-synced store flows between phone and
/// wrist. The Watch deliberately runs the same logic on a smaller surface;
/// nothing here is a duplicate of phone code.
///
/// **Note on type duplication:** the SwiftData models below
/// (`Exercise`, `ProgressEntry`, `SplitDay`) are intentionally re-declared
/// here for the Watch target. They mirror the iPhone definitions byte-for-
/// byte — same property names, same defaults, same `@Model` shape — so a
/// CloudKit-backed container reads/writes the same records across both
/// targets. The proper long-term fix is Target Membership (add the iOS
/// files to the watch target via Xcode's File Inspector), but this file
/// lets the watch target compile standalone right now without any further
/// Xcode UI work.
@main
struct GymTrackWatchApp: App {
    let container: ModelContainer

    init() {
        container = Self.makeContainer()
        WatchSeedData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .preferredColorScheme(.dark)
                .tint(WatchTheme.accent)
        }
        .modelContainer(container)
    }

    /// Mirrors the iPhone setup. Falls back to a local-only store if CloudKit
    /// can't be initialized (e.g. capability not yet enabled on the watch).
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Exercise.self, ProgressEntry.self])
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            do {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create watch ModelContainer: \(error)")
            }
        }
    }
}

// MARK: - Shared SwiftData models (mirrored from iOS target)

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
    var dayRaw: String = SplitDay.push.rawValue
    var orderInDay: Int = 0
    var barWeight: Double = 45
    var restSeconds: Int = 90
    var usesPlates: Bool = false
    // Set counting — mirrors the iOS schema byte-for-byte so the
    // CloudKit-backed store reads/writes the same records across both targets.
    var targetSets: Int = 3
    var completedSetsRaw: Int = 0
    var setsLogDate: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \ProgressEntry.exercise)
    var entries: [ProgressEntry] = []

    init() {}

    var day: SplitDay {
        get { SplitDay(rawValue: dayRaw) ?? .push }
        set { dayRaw = newValue.rawValue }
    }

    var sortedEntries: [ProgressEntry] {
        entries.sorted { $0.date < $1.date }
    }

    // MARK: - Set counting (mirrors iOS)

    static let maxSets = 30

    /// Sets checked off for today; auto-resets across days.
    var completedSetsToday: Int {
        Calendar.current.isDateInToday(setsLogDate) ? completedSetsRaw : 0
    }

    var allSetsDone: Bool {
        targetSets > 0 && completedSetsToday >= targetSets
    }

    @discardableResult
    func logSet() -> Int {
        completedSetsRaw = min(completedSetsToday + 1, Self.maxSets)
        setsLogDate = Date()
        return completedSetsRaw
    }

    @discardableResult
    func undoSet() -> Int {
        completedSetsRaw = max(completedSetsToday - 1, 0)
        setsLogDate = Date()
        return completedSetsRaw
    }

    var priorEntry: ProgressEntry? {
        let sorted = sortedEntries
        guard let last = sorted.last else { return nil }
        if Calendar.current.isDateInToday(last.date) {
            return sorted.dropLast().last ?? last
        }
        return last
    }
}

@Model
final class ProgressEntry {
    var id: UUID = UUID()
    var value: Double = 0
    var date: Date = Date()
    var exercise: Exercise?

    init(value: Double, date: Date = Date(), exercise: Exercise? = nil) {
        self.id = UUID()
        self.value = value
        self.date = date
        self.exercise = exercise
    }
}

// MARK: - SplitDay (mirrored from iOS target)

enum SplitDay: String, CaseIterable, Identifiable, Codable {
    case push
    case pull
    case legs
    case misc

    var id: String { rawValue }

    static let rotation: [SplitDay] = [.push, .pull, .legs]

    var title: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .misc: return "Misc"
        }
    }

    var focus: String {
        switch self {
        case .push: return "Chest · Shoulders · Triceps"
        case .pull: return "Back · Biceps · Core"
        case .legs: return "Quads · Hamstrings · Calves"
        case .misc: return "Accessory & extras"
        }
    }

    var colorHex: String {
        switch self {
        case .push: return "#FF375F"
        case .pull: return "#0A84FF"
        case .legs: return "#30D158"
        case .misc: return "#AF52DE"
        }
    }

    var next: SplitDay {
        guard let index = Self.rotation.firstIndex(of: self) else { return .push }
        return Self.rotation[(index + 1) % Self.rotation.count]
    }
}

// MARK: - WorkoutSchedule (simplified — Watch-local)

@MainActor
enum WorkoutSchedule {
    /// Watch-side recommendation: rotation-from-history + the same Mon/Fri
    /// "never legs" house rule the iPhone enforces, with no dependency on a
    /// shared Preferences store.
    static func recommendedDay(from exercises: [Exercise], on date: Date = Date()) -> SplitDay {
        let weekday = Calendar.current.component(.weekday, from: date)
        let blockLegs = weekday == 2 || weekday == 6
        return continueRotation(from: exercises, blockLegs: blockLegs)
    }

    private static func continueRotation(from exercises: [Exercise], blockLegs: Bool) -> SplitDay {
        var latest: (date: Date, day: SplitDay)?
        for exercise in exercises {
            guard let last = exercise.sortedEntries.last else { continue }
            if latest == nil || last.date > latest!.date {
                latest = (last.date, exercise.day)
            }
        }
        guard let latest else { return .push }
        if Calendar.current.isDateInToday(latest.date) {
            return swap(latest.day, blockLegs: blockLegs)
        }
        return swap(latest.day.next, blockLegs: blockLegs)
    }

    private static func swap(_ day: SplitDay, blockLegs: Bool) -> SplitDay {
        (blockLegs && day == .legs) ? .misc : day
    }
}

// MARK: - Convenience

extension Double {
    /// Compact display: drops the decimal when the value is a whole number.
    var clean: String {
        rounded() == self ? String(Int(self)) : String(format: "%.1f", self)
    }
}

extension Date {
    /// Terse relative date string for the watch list.
    var shortRelative: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "today" }
        if calendar.isDateInYesterday(self) { return "yesterday" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: self),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 { return "\(days)d ago" }
        if days < 30 { return "\(days / 7)w ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}

/// Watch-side theme constants. The phone's `Theme` ships with too much
/// surface area for the watch; we lift only the tokens that matter.
enum WatchTheme {
    static let background = Color.black
    static let accent = Color(red: 0.19, green: 0.82, blue: 0.35)        // #30D158 — exercise green
    static let move = Color(red: 1.0, green: 0.22, blue: 0.37)           // #FF375F — push
    static let cardio = Color(red: 0.04, green: 0.52, blue: 1.0)         // #0A84FF — pull
    static let purple = Color(red: 0.69, green: 0.32, blue: 0.87)        // #AF52DE — misc

    /// Resolve an exercise's hex color to a Watch palette color. The watch
    /// can't render arbitrary hex precisely on AOD, so we map to known
    /// system-safe colors.
    static func color(forHex hex: String) -> Color {
        switch hex.lowercased() {
        case "#ff375f": return move
        case "#0a84ff": return cardio
        case "#30d158": return accent
        case "#af52de": return purple
        default: return accent
        }
    }
}
