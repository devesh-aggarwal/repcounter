import SwiftUI
import WatchKit

/// Full-screen countdown for rest periods on the watch. Uses the system's
/// built-in `Text(timerInterval:countsDown:)` so the clock ticks per-second
/// without the app needing background time. Vibrates when the timer ends.
struct WatchRestTimerView: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    @State private var endDate: Date
    @State private var finished: Bool = false

    private var tint: Color { WatchTheme.color(forHex: exercise.colorHex) }

    init(exercise: Exercise) {
        self.exercise = exercise
        self._endDate = State(
            initialValue: Date().addingTimeInterval(TimeInterval(exercise.restSeconds))
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.18), .clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
            VStack(spacing: 12) {
                Text("REST")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .tracking(2)
                if finished {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(tint)
                        Text("Done")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                } else {
                    Text(timerInterval: Date()...endDate, countsDown: true)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(finished ? "Close" : "Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.bordered)
                .tint(finished ? tint : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle("")
        .onAppear {
            WKInterfaceDevice.current().play(.start)
            // Schedule a one-shot timer that flips `finished` when the rest
            // period ends — we trust wall-clock math here, not tick counting.
            let interval = endDate.timeIntervalSinceNow
            if interval > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    finished = true
                    WKInterfaceDevice.current().play(.success)
                }
            }
        }
    }
}
