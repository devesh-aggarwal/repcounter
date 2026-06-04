import Foundation
import SwiftUI

/// The hero headline shown at the top of the Summary tab. Picks the most
/// narratively-strong fact about the user's training right now — a fresh PR
/// beats a streak, which beats a weekly count, which beats cumulative gains,
/// which beats a generic welcome. Rotates organically with real behavior, so
/// the same number isn't shoved at the user every time they open the page.
enum StatHeadline {
    case newPR(exerciseName: String, value: Double, unit: String)
    case weekStreak(weeks: Int)
    case strongWeek(workouts: Int)
    case totalGained(amount: Double, unit: String, exerciseCount: Int)
    case sessions(count: Int)
    case welcome

    var headline: String {
        switch self {
        case .newPR(_, let value, let unit):
            return "+\(value.clean)"
        case .weekStreak(let weeks):
            return "\(weeks)"
        case .strongWeek(let workouts):
            return "\(workouts)"
        case .totalGained(let amount, _, _):
            return "+\(amount.clean)"
        case .sessions(let count):
            return "\(count)"
        case .welcome:
            return "—"
        }
    }

    var headlineSuffix: String {
        switch self {
        case .newPR(_, _, let unit): return unit
        case .weekStreak: return "weeks"
        case .strongWeek: return "sessions"
        case .totalGained(_, let unit, _): return unit
        case .sessions: return "sessions"
        case .welcome: return ""
        }
    }

    var label: String {
        switch self {
        case .newPR(let name, _, _):
            return "NEW PR — \(name.uppercased())"
        case .weekStreak:
            return "ON A ROLL"
        case .strongWeek:
            return "STRONG WEEK"
        case .totalGained:
            return "GAINED ALL-TIME"
        case .sessions:
            return "SESSIONS LOGGED"
        case .welcome:
            return "WELCOME"
        }
    }

    var subtitle: String? {
        switch self {
        case .newPR(let name, _, _):
            return "You pushed \(name) past its previous best this week."
        case .weekStreak(let weeks):
            return "Trained at least once every week for \(weeks) weeks straight."
        case .strongWeek(let workouts):
            return "\(workouts) sessions this week — keep stacking them."
        case .totalGained(_, _, let count):
            return "across \(count) exercises since you started tracking."
        case .sessions(let count):
            return "Every \(count > 1 ? "one" : "session") moves the needle."
        case .welcome:
            return "Log your first lift and the story starts here."
        }
    }
}

@MainActor
enum StatHeadlineEngine {
    /// Picks the most interesting fact about the user's current training.
    /// Order matters: a fresh PR is more emotional than a streak; a streak
    /// is more meaningful than a count of sessions.
    static func headline(for exercises: [Exercise], today: Date = Date()) -> StatHeadline {
        // 1. New PR this week — most emotional moment in any session.
        if let pr = freshPR(in: exercises, within: 7, of: today) {
            return .newPR(exerciseName: pr.name, value: pr.value, unit: pr.unit)
        }

        // 2. Three+ week streak — shows real consistency.
        let streak = WorkoutAnalytics.weekStreak(exercises)
        if streak >= 3 {
            return .weekStreak(weeks: streak)
        }

        // 3. Heavy week — three or more workouts in the current week.
        let weekCount = WorkoutAnalytics.sessionsThisWeek(exercises)
        if weekCount >= 3 {
            return .strongWeek(workouts: weekCount)
        }

        // 4. Cumulative gains — works for established users.
        let gained = WorkoutAnalytics.totalGained(exercises)
        if gained > 0 {
            let exerciseCount = exercises.filter { $0.stats.totalChange > 0 }.count
            return .totalGained(
                amount: gained,
                unit: Preferences.shared.defaultUnit,
                exerciseCount: exerciseCount
            )
        }

        // 5. Sessions count — early users with no gains yet.
        let totalSessions = WorkoutAnalytics.workoutDates(exercises).count
        if totalSessions > 0 {
            return .sessions(count: totalSessions)
        }

        // 6. Brand new — nothing logged yet.
        return .welcome
    }

    private static func freshPR(in exercises: [Exercise], within days: Int, of date: Date) -> (name: String, value: Double, unit: String)? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: date) else { return nil }
        var best: (name: String, value: Double, unit: String, date: Date)?
        for exercise in exercises {
            let entries = exercise.sortedEntries
            guard let last = entries.last,
                  last.date >= cutoff,
                  entries.count >= 2 else { continue }
            let prior = entries.dropLast()
            if let priorMax = prior.map(\.value).max(),
               last.value > priorMax {
                if best == nil || last.date > best!.date {
                    best = (exercise.name, last.value, exercise.unit, last.date)
                }
            }
        }
        return best.map { ($0.name, $0.value, $0.unit) }
    }
}
