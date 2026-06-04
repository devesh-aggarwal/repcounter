import SwiftUI

struct Insight {
    let text: String
    let icon: String
    let color: Color
}

/// Turns an exercise's recent history into one actionable coaching sentence.
enum InsightEngine {
    static func make(entries: [ProgressEntry], unit: String, currentValue: Double) -> Insight {
        let stats = ExerciseStats(entries: entries, fallbackValue: currentValue)

        guard stats.sessionCount >= 2 else {
            return Insight(
                text: "Log a few sessions to unlock trend insights.",
                icon: "sparkles",
                color: Theme.textSecondary
            )
        }

        if let best = entries.max(by: { $0.value < $1.value }),
           (Calendar.current.dateComponents([.day], from: best.date, to: Date()).day ?? 99) <= 7,
           stats.totalChange > 0 {
            return Insight(
                text: "New personal best this week — momentum is on your side.",
                icon: "trophy.fill",
                color: Color(hex: "#FFD740")
            )
        }

        let rate = stats.weeklyRate
        if rate >= 0.5 {
            let projected = stats.latestValue + rate * 4
            return Insight(
                text: "Trending up · +\(rate.clean) \(unit)/wk. On pace for ~\(projected.clean) \(unit) in a month.",
                icon: "arrow.up.right",
                color: Theme.accent
            )
        }
        if rate <= -0.5 {
            return Insight(
                text: "Down \(abs(rate).clean) \(unit)/wk lately — consider extra recovery or a lighter deload week.",
                icon: "arrow.down.right",
                color: Color(hex: "#FF6E40")
            )
        }

        if let days = daysSinceChange(entries), days >= 14 {
            return Insight(
                text: "Plateau · same weight for \(days) days. Try +1 increment or add a rep to break through.",
                icon: "exclamationmark.triangle.fill",
                color: Color(hex: "#FFD740")
            )
        }

        return Insight(
            text: "Holding steady. Small consistent jumps add up — aim for a tiny bump next session.",
            icon: "checkmark.seal.fill",
            color: Theme.accentSoft
        )
    }

    /// Up to three cross-exercise observations for the analytics tab.
    static func summary(for exercises: [Exercise]) -> [Insight] {
        var out: [Insight] = []
        let trended = exercises.filter { $0.stats.hasTrend }

        if let top = trended.max(by: { $0.stats.totalChange < $1.stats.totalChange }),
           top.stats.totalChange > 0 {
            out.append(Insight(
                text: "Biggest gain: \(top.name) is up \(top.stats.totalChange.clean) \(top.unit).",
                icon: "flame.fill",
                color: Theme.move
            ))
        }

        let streak = WorkoutAnalytics.weekStreak(exercises)
        if streak >= 2 {
            out.append(Insight(
                text: "On a roll — \(streak) weeks training in a row. Keep it going.",
                icon: "checkmark.seal.fill",
                color: Theme.accent
            ))
        }

        if let dominant = mostFrequentSplit(exercises), dominant.share >= 0.4 {
            out.append(Insight(
                text: "\(dominant.day.title) is \(Int(dominant.share * 100))% of your sessions — balance with extra \(complement(of: dominant.day)) if you can.",
                icon: "scalemass.fill",
                color: dominant.day.color
            ))
        }

        if let stalled = trended.first(where: { (daysSinceChange($0.sortedEntries) ?? 0) >= 21 }),
           let days = daysSinceChange(stalled.sortedEntries) {
            out.append(Insight(
                text: "Plateau watch: \(stalled.name) hasn't moved in \(days) days. Try a small bump or a rep change.",
                icon: "exclamationmark.triangle.fill",
                color: Color(hex: "#FFD60A")
            ))
        }

        if out.isEmpty {
            out.append(Insight(
                text: "Log your lifts across a few sessions to unlock insights.",
                icon: "sparkles",
                color: Theme.textSecondary
            ))
        }
        return Array(out.prefix(3))
    }

    /// Split day with the largest share of total sessions, returned with its
    /// share of all sessions (0…1). Returns nil when there's no history.
    private static func mostFrequentSplit(_ exercises: [Exercise]) -> (day: SplitDay, share: Double)? {
        let counts = WorkoutAnalytics.sessionsBySplit(exercises)
        let total = counts.values.reduce(0, +)
        guard total > 0, let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (top.key, Double(top.value) / Double(total))
    }

    /// Suggests a complementary split to balance an overweighted day.
    private static func complement(of day: SplitDay) -> String {
        switch day {
        case .push: return "pull"
        case .pull: return "push"
        case .legs: return "upper-body"
        case .misc: return "compound"
        }
    }

    /// Days since the value last differed from the most recent value.
    private static func daysSinceChange(_ entries: [ProgressEntry]) -> Int? {
        guard let latest = entries.last else { return nil }
        for entry in entries.reversed() where entry.value != latest.value {
            return Calendar.current.dateComponents([.day], from: entry.date, to: Date()).day
        }
        return nil
    }
}
