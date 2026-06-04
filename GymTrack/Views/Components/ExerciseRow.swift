import SwiftUI

/// Display-only row on the Today tab. Icon (tap to start rest), name, value,
/// optional "logged today" dot. Tap the row body → Workout Mode at this
/// exercise. There's no inline adjuster anymore — the picker only lives in
/// Workout Mode, which keeps the Today tab calm.
struct ExerciseRow: View {
    let exercise: Exercise
    let onTap: () -> Void
    @EnvironmentObject private var restTimer: RestTimer

    private var tint: Color { Color(hex: exercise.colorHex) }

    var body: some View {
        HStack(spacing: 14) {
            restIconButton
            Button(action: onTap) {
                HStack(spacing: 10) {
                    nameBlock
                    Spacer(minLength: 8)
                    valueBlock
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    private var restIconButton: some View {
        Button {
            restTimer.start(seconds: exercise.restSeconds, label: exercise.name)
            Haptics.impact(.medium)
        } label: {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 42, height: 42)
                Image(systemName: exercise.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                Image(systemName: "timer")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2.5)
                    .background(Circle().fill(tint))
                    .offset(x: 14, y: 12)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start \(exercise.restSeconds)-second rest for \(exercise.name)")
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if exercise.isLoggedToday {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                }
                Text(exercise.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .opacity(exercise.isLoggedToday ? 0.7 : 1.0)
                    .lineLimit(1)
            }
            if exercise.completedSetsToday > 0 {
                setsBadge
            }
        }
    }

    private var setsBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: exercise.allSetsDone ? "checkmark.circle.fill" : "circle.grid.2x2.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(exercise.completedSetsToday) of \(exercise.targetSets) sets")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(exercise.allSetsDone ? tint : Theme.textTertiary)
    }

    private var valueBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(exercise.currentValue.clean)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(exercise.unit)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
