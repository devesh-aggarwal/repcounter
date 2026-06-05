import Foundation

struct WeeklyCount: Identifiable {
    let id = UUID()
    let weekStart: Date
    let count: Int
}

/// Cross-exercise aggregates for the analytics tab.
enum WorkoutAnalytics {
    /// Distinct calendar days on which anything was logged.
    static func workoutDates(_ exercises: [Exercise]) -> [Date] {
        let calendar = Calendar.current
        var days = Set<Date>()
        for exercise in exercises {
            for entry in exercise.entries {
                days.insert(calendar.startOfDay(for: entry.date))
            }
        }
        return days.sorted()
    }

    static func sessions(_ exercises: [Exercise], since: Date) -> Int {
        workoutDates(exercises).filter { $0 >= since }.count
    }

    static func sessionsThisWeek(_ exercises: [Exercise]) -> Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return sessions(exercises, since: weekStart)
    }

    /// Sum of positive all-time gains across every exercise.
    static func totalGained(_ exercises: [Exercise]) -> Double {
        exercises.reduce(0) { $0 + max(0, $1.stats.totalChange) }
    }

    /// Consecutive weeks (ending this or last week) that contain at least one workout.
    static func weekStreak(_ exercises: [Exercise]) -> Int {
        let calendar = Calendar.current
        let weeks = Set(workoutDates(exercises).compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0)?.start
        })
        guard !weeks.isEmpty,
              var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }

        if !weeks.contains(cursor) {
            guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor),
                  weeks.contains(lastWeek) else { return 0 }
            cursor = lastWeek
        }

        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Workout counts for the most recent `weeks` weeks, oldest first.
    static func sessionsPerWeek(_ exercises: [Exercise], weeks: Int) -> [WeeklyCount] {
        let calendar = Calendar.current
        let dates = workoutDates(exercises)
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }

        var result: [WeeklyCount] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            let count = dates.filter { $0 >= start && $0 < end }.count
            result.append(WeeklyCount(weekStart: start, count: count))
        }
        return result
    }

    /// Workout intensity (entry count) for every day in the last `weeks` weeks,
    /// keyed by start-of-day. Days with no workouts are absent from the map.
    static func dailyActivity(_ exercises: [Exercise], weeks: Int) -> [Date: Int] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date()) else { return [:] }
        var counts: [Date: Int] = [:]
        for exercise in exercises {
            for entry in exercise.entries where entry.date >= cutoff {
                let day = calendar.startOfDay(for: entry.date)
                counts[day, default: 0] += 1
            }
        }
        return counts
    }

    /// Distinct workout days per split day. One Push day with 6 logged
    /// exercises counts as 1 Push session.
    static func sessionsBySplit(_ exercises: [Exercise]) -> [SplitDay: Int] {
        let calendar = Calendar.current
        var seen: Set<String> = []
        var counts: [SplitDay: Int] = [:]
        for exercise in exercises {
            let day = exercise.day
            for entry in exercise.entries {
                let dayKey = "\(day.rawValue)-\(calendar.startOfDay(for: entry.date).timeIntervalSince1970)"
                if seen.insert(dayKey).inserted {
                    counts[day, default: 0] += 1
                }
            }
        }
        return counts
    }

    /// Total positive gains aggregated per split day, expressed in the
    /// exercise's own unit. Different units are summed naively (lbs alongside
    /// kg alongside sec) — UI should treat this as a relative ordering, not
    /// an absolute total. Adequate for "which split is moving most?"
    static func gainsBySplit(_ exercises: [Exercise]) -> [SplitDay: Double] {
        var totals: [SplitDay: Double] = [:]
        for exercise in exercises {
            let gain = max(0, exercise.stats.totalChange)
            totals[exercise.day, default: 0] += gain
        }
        return totals
    }
}
