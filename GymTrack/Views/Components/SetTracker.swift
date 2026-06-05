import SwiftUI

/// Compact "completed of target" set counter for Workout Mode. A row of pips
/// fills as you check off sets; the big button logs the next one and pulses
/// the device once per set so you can feel your count. Tap the count label to
/// undo the last set.
///
/// The two numbers — sets done and sets planned — are the "dual count": you
/// always see both where you are and where you're headed.
struct SetTracker: View {
    @Bindable var exercise: Exercise
    var tint: Color
    /// Fired after a set is logged — used to chain into the rest timer.
    var onLogSet: () -> Void = {}

    /// Cap the number of rendered pips so an ambitious target doesn't overflow
    /// the row; beyond this the "x of y" label still tells the exact story.
    private let maxPips = 8

    private var done: Int { exercise.completedSetsToday }
    private var target: Int { max(exercise.targetSets, 1) }

    var body: some View {
        VStack(spacing: 12) {
            header
            HStack(spacing: 12) {
                if done > 0 {
                    undoButton
                }
                logButton
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            pips
            Spacer(minLength: 8)
            Button(action: undo) {
                Text("\(done) of \(target) sets")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(exercise.allSetsDone ? tint : Theme.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: done)
            }
            .buttonStyle(.plain)
            .disabled(done == 0)
            .accessibilityLabel("\(done) of \(target) sets completed. Tap to undo a set.")
        }
    }

    private var pips: some View {
        HStack(spacing: 6) {
            ForEach(0..<min(target, maxPips), id: \.self) { i in
                Capsule()
                    .fill(i < done ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.14)))
                    .frame(width: i < done ? 16 : 10, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: done)
            }
            if target > maxPips {
                Text("+\(target - maxPips)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var logButton: some View {
        Button(action: log) {
            HStack(spacing: 7) {
                Image(systemName: exercise.allSetsDone ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(exercise.allSetsDone ? "All sets done" : "Log set")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(tint))
            .shadow(color: tint.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(exercise.allSetsDone ? "Log another set" : "Log a set")
    }

    private var undoButton: some View {
        Button(action: undo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo last set")
    }

    private func log() {
        let count = exercise.logSet()
        Haptics.setLogged(count: count, target: exercise.targetSets)
        if exercise.allSetsDone {
            CelebrationCenter.shared.celebrate()
        }
        onLogSet()
    }

    private func undo() {
        guard done > 0 else { return }
        exercise.undoSet()
        Haptics.tick()
    }
}
