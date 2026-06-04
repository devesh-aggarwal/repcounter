import Foundation
import SwiftData

/// Watch-side seed. Mirrors the iPhone's program exactly so the wrist shows
/// the same Push / Pull / Legs / Misc workout without iCloud sync — handy
/// while we're still pre-iCloud. Runs once per install (guarded by
/// UserDefaults). When iCloud is eventually enabled, the Watch will pick up
/// the synced records; the seeded records here will be deduped by content
/// or supplanted by the iPhone's authoritative copy.
@MainActor
enum WatchSeedData {
    private static let seededKey = "watch.hasSeeded"

    private struct Template {
        let name: String
        /// Weight progression over time, oldest → newest. Last value becomes
        /// the slider's starting position.
        let progression: [Double]
        let step: Double
        let unit: String
        let icon: String
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

    /// Exact mirror of the iPhone seed so the wrist shows the user's actual
    /// program.
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

    /// Same start anchor as the iPhone seed so progression timestamps line up.
    private static var programStart: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 6
        return Calendar.current.date(from: components) ?? Date()
    }

    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard existing == 0 else {
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let start = programStart
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: yesterday).day ?? 1)

        var globalIndex = 0
        for (day, templates) in program {
            for (orderInDay, template) in templates.enumerated() {
                let top = template.progression.max() ?? 0
                let exercise = Exercise()
                exercise.name = template.name
                exercise.unit = template.unit
                exercise.minValue = 0
                exercise.maxValue = roundedCeiling(top)
                exercise.step = template.step
                exercise.currentValue = template.progression.last ?? 0
                exercise.colorHex = day.colorHex
                exercise.iconName = template.icon
                exercise.sortIndex = globalIndex
                exercise.barWeight = template.usesPlates ? 45 : 0
                exercise.restSeconds = 60
                exercise.usesPlates = template.usesPlates
                exercise.dayRaw = day.rawValue
                exercise.orderInDay = orderInDay
                context.insert(exercise)

                seedHistory(for: exercise, progression: template.progression,
                            start: start, totalDays: totalDays, calendar: calendar)
                globalIndex += 1
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

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

    private static func roundedCeiling(_ value: Double) -> Double {
        let padded = value * 1.6
        let bucket: Double = padded > 200 ? 50 : 25
        return max(bucket, (padded / bucket).rounded(.up) * bucket)
    }
}
