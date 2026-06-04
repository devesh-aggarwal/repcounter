import SwiftUI

/// GitHub-style calendar heatmap of workout activity. 7 rows (weekdays) ×
/// `weeks` columns. Each cell's opacity scales with the day's entry count.
struct ActivityHeatmap: View {
    let exercises: [Exercise]
    var weeks: Int = 12
    var tint: Color = Theme.accent

    private var activity: [Date: Int] {
        WorkoutAnalytics.dailyActivity(exercises, weeks: weeks)
    }

    private var maxCount: Int {
        max(1, activity.values.max() ?? 1)
    }

    /// The first day rendered: start of week, `weeks - 1` weeks before this one.
    private var startDate: Date {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                weekdayLabels
                cellGrid
            }
            footer
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: 3) {
            // Compact M/W/F labels so we don't overcrowd.
            ForEach(0..<7, id: \.self) { row in
                let label: String = {
                    switch row {
                    case 1: return "M"
                    case 3: return "W"
                    case 5: return "F"
                    default: return ""
                    }
                }()
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 10, height: cellSize)
            }
        }
        .padding(.trailing, 2)
    }

    private var cellGrid: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<weeks, id: \.self) { column in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { row in
                        cell(week: column, weekday: row)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            ForEach(0..<5, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(intensityColor(for: step))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
    }

    private func cell(week: Int, weekday: Int) -> some View {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: startDate) ?? Date()
        let day = calendar.startOfDay(for: date)
        let count = activity[day] ?? 0
        let isFuture = day > calendar.startOfDay(for: Date())

        let intensity: Int
        if isFuture {
            intensity = -1
        } else if count == 0 {
            intensity = 0
        } else {
            let normalized = Double(count) / Double(maxCount)
            intensity = min(4, Int((normalized * 4).rounded(.up)))
        }

        return RoundedRectangle(cornerRadius: 2.5)
            .fill(intensity == -1 ? Color.clear : intensityColor(for: intensity))
            .frame(width: cellSize, height: cellSize)
    }

    private func intensityColor(for level: Int) -> Color {
        switch level {
        case 0: return Theme.fill
        case 1: return tint.opacity(0.25)
        case 2: return tint.opacity(0.5)
        case 3: return tint.opacity(0.75)
        default: return tint
        }
    }

    private let cellSize: CGFloat = 14
}

#Preview {
    ActivityHeatmap(exercises: [])
        .padding()
        .background(Theme.surface)
        .preferredColorScheme(.dark)
}
