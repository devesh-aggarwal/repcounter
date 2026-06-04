import Foundation

/// Renders the user's current training state into a structured system prompt
/// for the AI coach. The output is deliberately verbose and numeric so the
/// model can ground its answers in actual data rather than guess from a name.
@MainActor
enum AIContextBuilder {
    static func systemPrompt(exercises: [Exercise], today: Date = Date()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long

        var output = ""
        output += instructionsBlock()
        output += "\n\n## USER CONTEXT\n"
        output += "Today: \(dateFormatter.string(from: today))\n"
        output += "Weekday: \(weekdayName(for: today))\n"
        output += "Default unit: \(Preferences.shared.defaultUnit)\n"
        output += "Default rest: \(Preferences.shared.defaultRestSeconds)s\n"
        output += "\n## WEEKLY SCHEDULE\n"
        output += scheduleBlock()
        output += "\n## AGGREGATE STATS\n"
        output += statsBlock(exercises)
        output += "\n## EXERCISES\n"
        output += exercisesBlock(exercises)
        return output
    }

    // MARK: - Sections

    private static func instructionsBlock() -> String {
        """
        # SYSTEM
        You are GymTrack's in-app coach. You help the user analyze their training, plan workouts, debug plateaus, and stay motivated.

        ## Voice
        - Direct, specific, numeric. Cite the user's actual numbers.
        - Concise. No preamble. No "I'd be happy to help" filler.
        - Encouraging but honest. Call out plateaus and bad habits when you see them.
        - Don't invent exercises or weights that aren't in the user's program.

        ## Output format — use markdown
        The client renders your output with a markdown renderer. Use it:
        - `**bold**` for the headline number or key takeaway.
        - `## Heading` for sections in longer answers (skip for short ones).
        - `- bullets` for any list of 3+ items.
        - `1. numbered` for ordered steps (e.g. a workout plan).
        - Inline `code` for exact exercise names when referenced in a list.

        ## Visualizations — inline charts
        When you discuss an exercise's progression, history, or trend, emit a
        single line on its own containing:

            [chart:Exercise Name]

        The client replaces that line with a live sparkline of that exercise
        from the user's actual data. Use the EXACT name as it appears in the
        EXERCISES block. Examples:

            [chart:Smith Machine Press]
            [chart:Shoulder Press]

        Place the chart on a line of its own, with blank lines around it.
        Don't fabricate a chart for an exercise that isn't in the data — if it
        isn't there, say so and skip the chart.

        ## What you know
        - The user's full active program (push/pull/legs/misc), per-exercise history, current weights, PR status, and unit (lbs/kg).
        - Their weekly schedule and hard rules (e.g. never legs on Mon/Fri).
        - Their preferred default rest duration.

        ## What you don't know
        - Their bodyweight, age, diet, sleep, or injuries unless they tell you.
        - Anything outside the data block below.

        ## Style guidance
        - When suggesting a weight bump, prefer +1 step (the exercise's `step`) unless asked for more.
        - When asked "what should I do today", answer with the recommended split + the specific exercises and current weights, formatted as a numbered list.
        - When asked about progress on one exercise: quote the trend, the PR, the time span, then drop an inline chart for that exercise.
        - When asked to compare exercises, use a bulleted list with `**name**: current → delta` shape, then chart the most interesting one.
        """
    }

    private static func scheduleBlock() -> String {
        let schedule = Preferences.shared.schedule
        var lines: [String] = []
        for weekday in [2, 3, 4, 5, 6, 7, 1] {
            let dayName = weekday.weekdayFullName
            if let split = schedule[weekday] {
                lines.append("- \(dayName): \(split.title) (pinned)")
            } else {
                lines.append("- \(dayName): auto (continue rotation)")
            }
        }
        lines.append("\nHard rules:")
        lines.append("- Mondays and Fridays never recommend Legs — substitute Misc.")
        return lines.joined(separator: "\n")
    }

    private static func statsBlock(_ exercises: [Exercise]) -> String {
        let week = WorkoutAnalytics.sessionsThisWeek(exercises)
        let streak = WorkoutAnalytics.weekStreak(exercises)
        let gained = WorkoutAnalytics.totalGained(exercises)
        let bySplit = WorkoutAnalytics.sessionsBySplit(exercises)
        let totalSessions = bySplit.values.reduce(0, +)

        var lines: [String] = []
        lines.append("- Workouts this week: \(week)")
        lines.append("- Week streak: \(streak)")
        lines.append("- Total weight gained (across all exercises, all-time): \(gained.clean) lbs")
        lines.append("- Total recorded workout sessions: \(totalSessions)")
        if totalSessions > 0 {
            lines.append("- Sessions by split: " + SplitDay.allCases.map { day in
                "\(day.title) \(bySplit[day] ?? 0)"
            }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private static func exercisesBlock(_ exercises: [Exercise]) -> String {
        var sections: [String] = []
        for day in SplitDay.allCases {
            let dayExercises = exercises
                .filter { $0.day == day }
                .sorted { $0.orderInDay < $1.orderInDay }
            guard !dayExercises.isEmpty else { continue }
            var section = "### \(day.title) day (\(day.focus))\n"
            for exercise in dayExercises {
                section += renderExercise(exercise) + "\n"
            }
            sections.append(section)
        }
        return sections.joined(separator: "\n")
    }

    private static func renderExercise(_ exercise: Exercise) -> String {
        let stats = exercise.stats
        let entries = exercise.sortedEntries
        let plates = exercise.usesPlates ? " · uses \(exercise.barWeight.clean)\(exercise.unit) bar" : ""
        let restLine = " · rest \(exercise.restSeconds)s"
        let stepLine = " · step \(exercise.step.clean)\(exercise.unit)"
        var line = "- \(exercise.name): currently \(exercise.currentValue.clean) \(exercise.unit)\(plates)\(restLine)\(stepLine)"
        if stats.hasTrend {
            let delta = stats.totalChange
            let direction = delta >= 0 ? "+" : ""
            line += " · all-time \(direction)\(delta.clean) (best \(stats.personalBest.clean), low \(stats.lowest.clean))"
            line += " · weekly rate \((delta >= 0 ? "+" : ""))\(stats.weeklyRate.clean) over \(stats.sessionCount) sessions"
            if entries.count >= 2 {
                let history = entries.suffix(6).map { "\($0.value.clean)@\($0.date.shortRelative)" }.joined(separator: ", ")
                line += " · recent: \(history)"
            }
        } else {
            line += " · no logged sessions yet"
        }
        return line
    }

    private static func weekdayName(for date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday.weekdayFullName
    }
}
