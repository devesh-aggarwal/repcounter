import SwiftUI

struct PlateCalculatorView: View {
    @Bindable var exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    private var tint: Color { Color(hex: exercise.colorHex) }
    private var availablePlates: [Double] { PlateMath.plates(for: exercise.unit) }
    private var result: PlateResult {
        PlateMath.compute(target: exercise.currentValue, bar: exercise.barWeight, plates: availablePlates)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        targetCard
                        barbellVisual
                        breakdown
                        barWeightControl
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }

    private var targetCard: some View {
        VStack(spacing: 6) {
            Text(exercise.name.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(exercise.currentValue.clean)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(exercise.unit)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            if !result.isExact {
                Text("Closest with your plates: \(result.achievable.clean) \(exercise.unit)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#FFD740"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var barbellVisual: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Text("LEFT SIDE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("RIGHT SIDE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(spacing: 3) {
                Spacer(minLength: 0)
                // LEFT side: lightest closest to the bar (mirror of right).
                ForEach(leftPlates) { stack in
                    ForEach(0..<stack.count, id: \.self) { _ in
                        plateBar(stack.plate)
                    }
                }
                // Left collar
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 10, height: 26)
                // Bar shaft
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 8)
                    .frame(maxWidth: 80)
                // Right collar
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 10, height: 26)
                // RIGHT side: heaviest closest to the bar.
                ForEach(rightPlates) { stack in
                    ForEach(0..<stack.count, id: \.self) { _ in
                        plateBar(stack.plate)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 130)
            .padding(.horizontal, 8)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            )

            if result.isJustBar {
                Text("Just the bar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Right side: heaviest plates closest to the bar (drawn leftmost in the
    /// right-side stack), like a real loadout.
    private var rightPlates: [PlateStack] {
        result.perSide.sorted { $0.plate > $1.plate }
    }

    /// Left side: mirrored — lightest closest to the viewer, heaviest closest
    /// to the bar. Same plates as right; barbells are symmetric.
    private var leftPlates: [PlateStack] {
        result.perSide.sorted { $0.plate < $1.plate }
    }

    private func plateBar(_ plate: Double) -> some View {
        let maxPlate = availablePlates.max() ?? plate
        let height = CGFloat(50 + (plate / maxPlate) * 78)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(PlateMath.color(for: plate))
            .frame(width: 16, height: height)
            .overlay(
                Text(plate.clean)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
                    .rotationEffect(.degrees(-90))
            )
    }

    private var breakdown: some View {
        VStack(spacing: 0) {
            if result.perSide.isEmpty {
                row(label: "Bar only", detail: "\(exercise.barWeight.clean) \(exercise.unit)")
            } else {
                ForEach(Array(result.perSide.enumerated()), id: \.element.id) { index, stack in
                    if index > 0 { divider }
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PlateMath.color(for: stack.plate))
                            .frame(width: 14, height: 22)
                        Text("\(stack.plate.clean) \(exercise.unit)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("× \(stack.count) per side")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        )
    }

    private var barWeightControl: some View {
        HStack {
            Text("Bar weight")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(exercise.barWeight.clean) \(exercise.unit)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(minWidth: 60)
            Stepper("", value: $exercise.barWeight, in: 0...100, step: 5)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        )
    }

    private func row(label: String, detail: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(detail)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 16)
    }
}
