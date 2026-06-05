import SwiftUI
import Charts

/// Compact line chart for one exercise's progression. Used in the
/// "all exercises at a glance" grid on the Summary tab.
struct ExerciseSparkline: View {
    let exercise: Exercise
    var onTap: (() -> Void)? = nil

    private var tint: Color { Color(hex: exercise.colorHex) }
    private var entries: [ProgressEntry] { exercise.sortedEntries }
    private var stats: ExerciseStats { exercise.stats }

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 10) {
                header
                if entries.count >= 2 {
                    chart
                } else {
                    Text("No trend yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                footer
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.name): \(stats.latestValue.clean) \(exercise.unit), \(trendDescription)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: exercise.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(exercise.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(entries, id: \.id) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Value", entry.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                AreaMark(
                    x: .value("Date", entry.date),
                    y: .value("Value", entry.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.4), tint.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 44)
    }

    private var yDomain: ClosedRange<Double> {
        guard let high = entries.map(\.value).max() else { return 0...1 }
        let lower = min(0, entries.map(\.value).min() ?? 0)
        return lower...(high + max(1, high * 0.1))
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(stats.latestValue.clean)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(exercise.unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            if stats.hasTrend {
                trendBadge
            }
        }
    }

    @ViewBuilder
    private var trendBadge: some View {
        let delta = stats.totalChange
        let up = delta >= 0
        HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
            Text(delta == 0 ? "0" : "\(up ? "+" : "−")\(abs(delta).clean)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(up ? Theme.accent : Color(hex: "#FF6E40"))
    }

    private var trendDescription: String {
        guard stats.hasTrend else { return "no trend" }
        let delta = stats.totalChange
        let direction = delta >= 0 ? "up" : "down"
        return "\(direction) \(abs(delta).clean) \(exercise.unit) all-time"
    }
}

#Preview {
    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
        ExerciseSparkline(exercise: Exercise(name: "Bench", currentValue: 135))
        ExerciseSparkline(exercise: Exercise(name: "Squat", currentValue: 225))
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
