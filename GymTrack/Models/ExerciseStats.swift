import Foundation

/// Derived analytics for an exercise's logged history.
/// `entries` are expected in ascending date order.
struct ExerciseStats {
    let entries: [ProgressEntry]
    let fallbackValue: Double

    var sessionCount: Int { entries.count }

    var startValue: Double { entries.first?.value ?? fallbackValue }
    var latestValue: Double { entries.last?.value ?? fallbackValue }

    var totalChange: Double { latestValue - startValue }

    var percentChange: Double {
        guard startValue != 0 else { return 0 }
        return totalChange / startValue * 100
    }

    var personalBest: Double {
        entries.map(\.value).max() ?? fallbackValue
    }

    var lowest: Double {
        entries.map(\.value).min() ?? fallbackValue
    }

    /// Calendar days spanned from first to last entry (inclusive).
    var daysTracked: Int {
        guard let first = entries.first?.date, let last = entries.last?.date else { return 0 }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: first),
            to: calendar.startOfDay(for: last)
        ).day ?? 0
        return days + 1
    }

    /// Average change per week across the tracked span.
    var weeklyRate: Double {
        guard let first = entries.first?.date,
              let last = entries.last?.date,
              last > first else { return 0 }
        let weeks = last.timeIntervalSince(first) / (7 * 24 * 3600)
        return weeks > 0 ? totalChange / weeks : 0
    }

    /// Change relative to the previous session.
    var lastSessionChange: Double {
        guard entries.count >= 2 else { return 0 }
        return entries[entries.count - 1].value - entries[entries.count - 2].value
    }

    var hasTrend: Bool { entries.count >= 2 }
}
