import SwiftUI

/// 1080×1080 share card snapshot — what gets exported via the Stats tab's
/// Share button and dropped into Messages / Instagram / etc. Designed to read
/// at a glance: hero stat, supporting stats, three biggest movers, branding.
struct StatsShareCard: View {
    let exercises: [Exercise]
    let renderedDate: Date

    private var weekSessions: Int { WorkoutAnalytics.sessionsThisWeek(exercises) }
    private var streak: Int { WorkoutAnalytics.weekStreak(exercises) }
    private var totalGained: Double { WorkoutAnalytics.totalGained(exercises) }

    private var topMovers: [Exercise] {
        exercises
            .filter { $0.stats.hasTrend && $0.stats.totalChange > 0 }
            .sorted { $0.stats.totalChange > $1.stats.totalChange }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer().frame(height: 38)
                heroStat
                Spacer().frame(height: 28)
                statRow
                Spacer().frame(height: 36)
                moversSection
                Spacer()
                footer
            }
            .padding(60)
        }
        .frame(width: 1080, height: 1080)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "#0B0B10"), Color(hex: "#16161B")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Circle()
                .fill(Theme.accent.opacity(0.18))
                .frame(width: 600, height: 600)
                .blur(radius: 120)
                .offset(x: 220, y: -240)
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accentGradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("GYMTRACK")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .tracking(2)
                Text(formattedDate)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
    }

    private var heroStat: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTAL WEIGHT GAINED")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(1.5)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("+\(totalGained.clean)")
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accentGradient)
                Text("lbs")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
    }

    private var statRow: some View {
        HStack(spacing: 16) {
            statTile(value: "\(weekSessions)", label: weekSessions == 1 ? "Workout this week" : "Workouts this week", color: Theme.accent)
            statTile(value: "\(streak)", label: streak == 1 ? "Week streak" : "Week streak", color: Theme.move)
            statTile(value: "\(exercises.count)", label: "Exercises tracked", color: Theme.cardio)
        }
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var moversSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("BIGGEST GAINS")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(1.5)
            if topMovers.isEmpty {
                Text("Log a few sessions to surface your top movers here.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(spacing: 12) {
                    ForEach(topMovers) { exercise in
                        moverRow(exercise)
                    }
                }
            }
        }
    }

    private func moverRow(_ exercise: Exercise) -> some View {
        let stats = exercise.stats
        let color = Color(hex: exercise.colorHex)
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 50, height: 50)
                Image(systemName: exercise.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Best \(stats.personalBest.clean) \(exercise.unit)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Text("+\(stats.totalChange.clean)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("tracked with GymTrack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: renderedDate)
    }
}

#Preview {
    StatsShareCard(exercises: [], renderedDate: Date())
        .preferredColorScheme(.dark)
}
