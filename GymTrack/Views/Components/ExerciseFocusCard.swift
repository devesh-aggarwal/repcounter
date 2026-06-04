import SwiftUI
import SwiftData

/// Full-screen, single-exercise card used inside Workout Mode. Everything
/// orbits the value: a 160pt rounded number is the visual anchor; the
/// tape-measure picker sits below as the verb that changes it. Plates assemble
/// onto a virtual barbell at the top for plate-loaded exercises.
///
/// Saves commit on release — no 30s grace window. You're at the gym, your
/// intent to log is unambiguous.
struct ExerciseFocusCard: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var restTimer: RestTimer
    @Query private var allExercises: [Exercise]

    @State private var pulse: Bool = false
    @State private var showingPlates: Bool = false
    @State private var showingHoldTimer: Bool = false

    private var tint: Color { Color(hex: exercise.colorHex) }
    private var isTimedExercise: Bool {
        exercise.unit == "sec" || exercise.unit == "min"
    }

    var body: some View {
        ZStack {
            backgroundWash
            VStack(spacing: 0) {
                topMeta
                if exercise.usesPlates {
                    PlateBarPreview(exercise: exercise)
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                } else {
                    Spacer().frame(height: 24)
                }
                Spacer(minLength: 0)
                heroValue
                Spacer(minLength: 0)
                adjusterBlock
                Spacer().frame(height: 22)
                SetTracker(exercise: exercise, tint: tint) {
                    // Finishing a set flows straight into rest.
                    restTimer.start(seconds: exercise.restSeconds, label: exercise.name)
                }
                Spacer().frame(height: 18)
                footer
            }
            .padding(.horizontal, 28)
            // Reserve room for the WorkoutModeView's top bar (~70pt) and the
            // page indicator + safe-area inset at the bottom (~110pt). Without
            // this the meta line and footer chips slide under the chrome.
            .padding(.top, 80)
            .padding(.bottom, 110)
        }
        .overlay {
            if pulse {
                Rectangle()
                    .fill(tint.opacity(0.18))
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingPlates) {
            PlateCalculatorView(exercise: exercise)
        }
        .sheet(isPresented: $showingHoldTimer) {
            ExerciseTimerView(exercise: exercise)
        }
    }

    // MARK: Layout

    private var backgroundWash: some View {
        LinearGradient(
            colors: [tint.opacity(0.10), .clear, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topMeta: some View {
        VStack(spacing: 6) {
            Text(exercise.day.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint.opacity(0.9))
                .tracking(2.5)
            Text(exercise.name)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let prior = exercise.priorEntry {
                Text("Previously \(prior.value.clean) \(exercise.unit) · \(prior.date.shortRelative)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 6)
    }

    private var heroValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(exercise.currentValue.clean)
                .font(.system(size: 160, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(exercise.unit)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: exercise.currentValue)
    }

    private var adjusterBlock: some View {
        HStack(spacing: 18) {
            StepButton(symbol: "minus", accessibilityLabel: "Decrease") {
                adjust(by: -exercise.step)
            }
            HorizontalNumberPicker(
                value: $exercise.currentValue,
                range: exercise.minValue...exercise.maxValue,
                step: exercise.step,
                tint: tint,
                onCommit: commit
            )
            StepButton(symbol: "plus", accessibilityLabel: "Increase") {
                adjust(by: exercise.step)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            actionChip(icon: "timer", title: "Rest \(restLabel)") {
                restTimer.start(seconds: exercise.restSeconds, label: exercise.name)
            }
            if exercise.usesPlates {
                actionChip(icon: "circle.grid.2x1.fill", title: "Plates") {
                    showingPlates = true
                }
            }
            if isTimedExercise {
                actionChip(icon: "stopwatch.fill", title: "Hold") {
                    showingHoldTimer = true
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func actionChip(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var restLabel: String {
        let s = exercise.restSeconds
        return s % 60 == 0 ? "\(s / 60)m" : "\(s)s"
    }

    // MARK: Behavior

    private func adjust(by delta: Double) {
        let updated = min(max(exercise.minValue, exercise.currentValue + delta),
                          exercise.maxValue)
        guard updated != exercise.currentValue else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            exercise.currentValue = updated
        }
        Haptics.impact()
        commit()
    }

    /// Immediate commit — no 30s grace. In Workout Mode, every release is an
    /// intentional log.
    private func commit() {
        let calendar = Calendar.current
        let priorBest = exercise.entries
            .filter { !calendar.isDateInToday($0.date) }
            .map(\.value)
            .max()
        let isPR = priorBest != nil && exercise.currentValue > priorBest!

        if let today = exercise.entries.first(where: { calendar.isDateInToday($0.date) }) {
            // Only overwrite if value actually changed — avoids busy date
            // updates while the picker is settling.
            if today.value != exercise.currentValue {
                today.value = exercise.currentValue
                today.date = Date()
            }
        } else {
            let entry = ProgressEntry(
                value: exercise.currentValue,
                date: Date(),
                exercise: exercise
            )
            context.insert(entry)
            exercise.entries.append(entry)
        }

        if isPR {
            Haptics.success()
            CelebrationCenter.shared.celebrate()
            triggerPulse()
        }

        if Preferences.shared.syncToHealthKit {
            let snapshot = allExercises
            Task { try? await HealthSync.shared.syncTodayWorkout(exercises: snapshot) }
        }
    }

    private func triggerPulse() {
        withAnimation(.easeOut(duration: 0.2)) { pulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.45)) { pulse = false }
        }
    }
}
