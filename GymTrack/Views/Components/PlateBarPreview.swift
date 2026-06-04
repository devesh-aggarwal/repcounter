import SwiftUI

/// Animated plate-stack visualization that loads onto a virtual barbell as
/// the user scrolls the picker. Unique visual signature for plate-loaded
/// exercises (Smith Machine, barbell) — the bar tells you the math.
struct PlateBarPreview: View {
    let exercise: Exercise

    private var availablePlates: [Double] { PlateMath.plates(for: exercise.unit) }
    private var result: PlateResult {
        PlateMath.compute(
            target: exercise.currentValue,
            bar: exercise.barWeight,
            plates: availablePlates
        )
    }

    private var rightSidePlates: [PlateStack] {
        result.perSide.sorted { $0.plate > $1.plate }
    }

    private var leftSidePlates: [PlateStack] {
        result.perSide.sorted { $0.plate < $1.plate }
    }

    var body: some View {
        HStack(spacing: 2) {
            Spacer()
            ForEach(leftSidePlates) { stack in
                ForEach(0..<stack.count, id: \.self) { _ in
                    plate(for: stack.plate)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            collar
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 60, height: 4)
            collar
            ForEach(rightSidePlates) { stack in
                ForEach(0..<stack.count, id: \.self) { _ in
                    plate(for: stack.plate)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer()
        }
        .frame(height: 60)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: exercise.currentValue)
    }

    private func plate(for value: Double) -> some View {
        let maxPlate = availablePlates.max() ?? value
        let height: CGFloat = 26 + CGFloat(value / maxPlate) * 28
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(PlateMath.color(for: value))
            .frame(width: 10, height: height)
    }

    private var collar: some View {
        Rectangle()
            .fill(Color.white.opacity(0.32))
            .frame(width: 6, height: 16)
    }
}
