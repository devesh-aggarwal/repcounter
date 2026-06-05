import SwiftUI
import Charts

struct ProgressChart: View {
    let entries: [ProgressEntry]
    let unit: String
    let tint: Color

    /// Y-axis from 0 (or just below) up through the high value with headroom.
    /// Anchoring at 0 makes upward progress read as a much taller line than a
    /// window-min anchor, which is the whole point of a progression chart.
    private var yDomain: ClosedRange<Double> {
        let values = entries.map(\.value)
        guard let high = values.max() else { return 0...1 }
        let headroom = max(1, high * 0.15)
        let lower = min(0, values.min() ?? 0)
        return lower...(high + headroom)
    }

    var body: some View {
        Chart {
            ForEach(entries, id: \.id) { entry in
                AreaMark(
                    x: .value("Date", entry.date),
                    y: .value(unit, entry.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.35), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", entry.date),
                    y: .value(unit, entry.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            if let last = entries.last {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value(unit, last.value)
                )
                .foregroundStyle(tint)
                .symbolSize(120)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel().foregroundStyle(Theme.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 220)
    }
}
