import Foundation

/// Decides which split day to surface by default.
///
/// Two layers:
/// 1. If the user has explicitly pinned today's weekday to a specific split
///    in `Preferences.shared.schedule`, that wins. Use this for "I always do
///    X on Y" days.
/// 2. Otherwise, fall back to rotation-from-history (pick up where you left
///    off), with house rules: never recommend legs on Monday or Friday.
///    When the rotation *would* be legs on a blocked day, we substitute Misc
///    so the user still gets a useful recommendation rather than a dead end.
@MainActor
enum WorkoutSchedule {
    /// Weekdays where legs is forbidden by the user's gym rules.
    /// 2 = Monday, 6 = Friday per `Calendar.component(.weekday, ...)`.
    private static let legsBlockedWeekdays: Set<Int> = [2, 6]

    static func recommendedDay(from exercises: [Exercise], on date: Date = Date()) -> SplitDay {
        let weekday = Calendar.current.component(.weekday, from: date)
        let legsBlocked = legsBlockedWeekdays.contains(weekday)

        if let mapped = Preferences.shared.schedule[weekday] {
            // Even explicit pin gets the legs guard — the user said they
            // *never* train legs Mon/Fri, so a stale or default mapping
            // shouldn't override that rule.
            if legsBlocked && mapped == .legs {
                return continueRotation(from: exercises, blockLegs: true)
            }
            return mapped
        }
        return continueRotation(from: exercises, blockLegs: legsBlocked)
    }

    /// Picks the next day after the most recently completed session. If the
    /// user already trained today, stays on today's day so they can finish.
    /// If `blockLegs`, substitutes Misc whenever rotation would land on Legs.
    private static func continueRotation(from exercises: [Exercise], blockLegs: Bool) -> SplitDay {
        var latest: (date: Date, day: SplitDay)?
        for exercise in exercises {
            guard let last = exercise.sortedEntries.last else { continue }
            if latest == nil || last.date > latest!.date {
                latest = (last.date, exercise.day)
            }
        }
        guard let latest else {
            // Brand-new install with no history: start with Push (never Legs).
            return .push
        }
        if Calendar.current.isDateInToday(latest.date) {
            // Already trained today — let them finish the session.
            return swap(latest.day, blockLegs: blockLegs)
        }
        return swap(latest.day.next, blockLegs: blockLegs)
    }

    private static func swap(_ day: SplitDay, blockLegs: Bool) -> SplitDay {
        (blockLegs && day == .legs) ? .misc : day
    }
}
