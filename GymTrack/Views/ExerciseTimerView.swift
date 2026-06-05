import SwiftUI

/// Countdown timer for exercises whose unit is a duration (Dead Hang, planks,
/// sprints). Counts down from `exercise.currentValue` in seconds or minutes,
/// shows a tappable ring, and fires a success haptic + notification on
/// completion. Stays accurate when backgrounded because remaining time is
/// derived from a target end date, not a tick counter.
struct ExerciseTimerView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    @State private var endDate: Date?
    @State private var remaining: TimeInterval
    @State private var ticker: Timer?
    @State private var finished = false

    private var tint: Color { Color(hex: exercise.colorHex) }
    private var totalSeconds: TimeInterval {
        let raw = max(1, exercise.currentValue)
        return exercise.unit == "min" ? raw * 60 : raw
    }
    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - (remaining / totalSeconds)))
    }
    private var isRunning: Bool { endDate != nil && !finished }

    init(exercise: Exercise) {
        self.exercise = exercise
        let raw = max(1, exercise.currentValue)
        let seconds = exercise.unit == "min" ? raw * 60 : raw
        self._remaining = State(initialValue: seconds)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 32) {
                    Spacer()
                    title
                    ring
                    Spacer()
                    controls
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Hold Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { close() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .onDisappear(perform: stopTicker)
        }
    }

    private var title: some View {
        VStack(spacing: 4) {
            Text(exercise.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(finished ? "Done — nice hold" : (isRunning ? "Hang on" : "Ready"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.fill, lineWidth: 18)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [tint.opacity(0.6), tint],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            VStack(spacing: 6) {
                Text(displayString)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(targetString)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 260, height: 260)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if finished {
                bigButton("Close", icon: "checkmark", color: tint) { close() }
            } else if isRunning {
                bigButton("Cancel", icon: "xmark", color: Theme.surfaceElevated) { reset() }
                bigButton("Stop", icon: "stop.fill", color: Color(hex: "#FF6E40")) { finish(early: true) }
            } else {
                bigButton("Start", icon: "play.fill", color: tint) { start() }
            }
        }
    }

    private func bigButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(color == Theme.surfaceElevated ? Theme.textPrimary : .black)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
    }

    private var displayString: String {
        if exercise.unit == "min" {
            let total = Int(remaining.rounded(.up))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return "\(Int(remaining.rounded(.up)))"
    }

    private var targetString: String {
        let raw = Int(exercise.currentValue.rounded())
        if exercise.unit == "min" {
            return "\(raw) min"
        }
        return "\(raw) sec"
    }

    private func start() {
        endDate = Date().addingTimeInterval(remaining)
        finished = false
        Haptics.impact(.medium)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            tick()
        }
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finish(early: false) }
    }

    private func finish(early: Bool) {
        stopTicker()
        endDate = nil
        finished = true
        if !early { Haptics.success() } else { Haptics.impact(.light) }
    }

    private func reset() {
        stopTicker()
        endDate = nil
        finished = false
        remaining = totalSeconds
        Haptics.tick()
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func close() {
        stopTicker()
        dismiss()
    }
}

#Preview {
    ExerciseTimerView(exercise: {
        let e = Exercise(name: "Dead Hang", unit: "sec", maxValue: 120, step: 5, currentValue: 30)
        return e
    }())
    .preferredColorScheme(.dark)
}
