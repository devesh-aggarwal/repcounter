import Foundation
import SwiftData

/// Seeds the owner's real Push / Pull / Legs / Misc program + the historical
/// progression for each lift on first install only. Runs at most once per
/// install (tracked via `Preferences.hasSeeded`). The Settings → Erase all
/// data button is the user-facing escape hatch for anyone who wants a clean
/// slate — it intentionally does not re-seed.
///
/// Note for future App Store submissions: this is the owner's personal data
/// shipped as default content. Reviewers will see it. That's fine (the data
/// looks like a real, plausible program), but if you ever want a generic
/// "start blank" seed for public release, swap `program` for an empty
/// `[Template]` list per day and drop the `seedHistory` call.
enum SeedData {
    private struct Template {
        let name: String
        /// Weight progression over time, oldest → newest. Last value becomes
        /// the slider's starting position.
        let progression: [Double]
        let step: Double
        let unit: String
        let icon: String
        /// True for plate-loaded bars (Smith machine, barbell). Planet Fitness
        /// machines are just set-the-pin so they default to false.
        let usesPlates: Bool

        init(_ name: String, _ progression: [Double], step: Double = 2.5,
             unit: String = "lbs", icon: String = "dumbbell.fill",
             usesPlates: Bool = false) {
            self.name = name
            self.progression = progression
            self.step = step
            self.unit = unit
            self.icon = icon
            self.usesPlates = usesPlates
        }
    }

    private static let program: [(SplitDay, [Template])] = [
        (.push, [
            Template("Smith Machine Press", [20, 25, 30], icon: "figure.strengthtraining.traditional", usesPlates: true),
            Template("Shoulder Press", [20, 25, 27.5, 32.5, 35, 37.5], icon: "dumbbell.fill"),
            Template("Tricep Pushdown", [30, 35, 40], icon: "figure.strengthtraining.functional"),
            Template("Single-Arm Lateral Raise", [5, 7.5], icon: "figure.arms.open"),
            Template("Cable Crossover", [10, 12.5], icon: "figure.strengthtraining.functional"),
            Template("Dead Hang", [30], step: 5, unit: "sec", icon: "timer")
        ]),
        (.pull, [
            Template("Dependent Curl", [25, 30], icon: "dumbbell.fill"),
            Template("Bicep Curls", [15, 20], icon: "dumbbell.fill"),
            Template("Wrist Curls", [15, 20], icon: "dumbbell.fill"),
            Template("Assisted Pull-up", [50, 35, 30, 20], step: 5, icon: "figure.strengthtraining.functional"),
            Template("Abdominal Crunch", [70, 80], step: 5, icon: "figure.core.training"),
            Template("Seated Row", [62.5, 65, 70, 80, 82.5, 87.5], icon: "figure.rower")
        ]),
        (.legs, [
            Template("Leg Press", [155, 120, 135], step: 5, icon: "figure.strengthtraining.functional"),
            Template("Box Step", [24, 30], step: 2, icon: "figure.step.training"),
            Template("Seated Leg Curl", [57.5, 60, 70], icon: "figure.strengthtraining.functional"),
            Template("Calf Extension", [80, 140, 145, 147.5], icon: "figure.fall"),
            Template("Hip Adductor", [60, 80, 85, 87.5], icon: "figure.strengthtraining.functional")
        ]),
        (.misc, [
            Template("Back Extension", [90], step: 5, icon: "figure.core.training")
        ])
    ]

    /// History begins here; per-exercise progression is spread evenly between
    /// this date and today.
    private static var programStart: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 6
        return Calendar.current.date(from: components) ?? Date()
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard !Preferences.shared.hasSeeded else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard existing == 0 else {
            Preferences.shared.hasSeeded = true
            return
        }

        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        // Land the last seeded entry on yesterday, not today. Otherwise every
        // freshly-installed exercise looks "logged today" — the progress UI
        // would render 6/6 done before the user has touched anything.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let start = programStart
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: yesterday).day ?? 1)

        var globalIndex = 0
        for (day, templates) in program {
            for (orderInDay, template) in templates.enumerated() {
                let top = template.progression.max() ?? 0
                let exercise = Exercise(
                    name: template.name,
                    unit: template.unit,
                    minValue: 0,
                    maxValue: roundedCeiling(top),
                    step: template.step,
                    currentValue: template.progression.last ?? 0,
                    colorHex: day.colorHex,
                    iconName: template.icon,
                    sortIndex: globalIndex,
                    barWeight: template.usesPlates ? 45 : 0,
                    restSeconds: Preferences.shared.defaultRestSeconds
                )
                exercise.dayRaw = day.rawValue
                exercise.orderInDay = orderInDay
                exercise.usesPlates = template.usesPlates
                context.insert(exercise)

                seedHistory(for: exercise, progression: template.progression,
                            start: start, totalDays: totalDays, calendar: calendar)
                globalIndex += 1
            }
        }
        Preferences.shared.hasSeeded = true
    }

    /// Places each progression value at an evenly spaced date across the program.
    private static func seedHistory(
        for exercise: Exercise,
        progression: [Double],
        start: Date,
        totalDays: Int,
        calendar: Calendar
    ) {
        let count = progression.count
        guard count > 0 else { return }

        for (index, value) in progression.enumerated() {
            let fraction = count == 1 ? 1.0 : Double(index) / Double(count - 1)
            let offset = Int((Double(totalDays) * fraction).rounded())
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let entry = ProgressEntry(value: value, date: date, exercise: exercise)
            entry.exercise = exercise
            exercise.entries.append(entry)
        }
    }

    /// Rounds a max up to a comfortable slider ceiling.
    private static func roundedCeiling(_ value: Double) -> Double {
        let padded = value * 1.6
        let bucket: Double = padded > 200 ? 50 : 25
        return max(bucket, (padded / bucket).rounded(.up) * bucket)
    }
}
