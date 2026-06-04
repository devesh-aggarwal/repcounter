import SwiftUI
import SwiftData
import WatchKit

/// The defining watchOS interaction, now in two modes:
///
/// 1. **Set the weight** — the Digital Crown IS the tape-measure picker. Spin to
///    change the weight in `step`-sized increments; haptic feedback per detent.
///
/// 2. **Count reps automatically** — tap *Count Reps* and the merged RepCounter
///    engine reads wrist motion, counting each rep with a haptic. When you rest,
///    the set auto-logs into the shared store (one completed set at the chosen
///    weight) and the counter re-arms for the next set — no tapping required.
///    Manual *Log* stays available as a fallback.
struct WatchExerciseView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var workingValue: Double
    @State private var savedFlash: Bool = false
    @State private var showingRest: Bool = false
    @State private var autoSession = AutoRepSession()
    @State private var repPulse: Bool = false
    @FocusState private var crownFocused: Bool

    init(exercise: Exercise) {
        self.exercise = exercise
        self._workingValue = State(initialValue: exercise.currentValue)
    }

    private var tint: Color { WatchTheme.color(forHex: exercise.colorHex) }

    private var isCounting: Bool {
        autoSession.phase == .counting || autoSession.phase == .paused
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.18), .clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()

            if isCounting {
                countingView
            } else {
                setupView
            }

            if savedFlash {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(tint)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationTitle("")
        .focusable(!isCounting)
        .focused($crownFocused)
        .digitalCrownRotation(
            $workingValue,
            from: exercise.minValue,
            through: exercise.maxValue,
            by: exercise.step,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            // Auto-focus so the Digital Crown drives weight changes without a tap.
            crownFocused = true
            wireAutoSession()
        }
        .onChange(of: autoSession.reps) { _, _ in repPulse.toggle() }
        .onDisappear { autoSession.stop() }
        .sheet(isPresented: $showingRest) {
            WatchRestTimerView(exercise: exercise)
        }
        .animation(.easeInOut(duration: 0.2), value: isCounting)
    }

    // MARK: - Setup mode (set weight, choose to auto-count or log manually)

    private var setupView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 2)
            title
            Spacer(minLength: 0)
            heroValue
            Spacer(minLength: 0)
            hint
            Spacer(minLength: 2)
            setPill
            Spacer(minLength: 4)
            countButton
            Spacer(minLength: 4)
            actionRow
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var title: some View {
        VStack(spacing: 2) {
            Text(exercise.day.title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .tracking(1.5)
            Text(exercise.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    private var heroValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(workingValue.clean)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(exercise.unit)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: workingValue)
    }

    private var hint: some View {
        Text("Spin Digital Crown")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)
            .tracking(1)
            .opacity(workingValue == exercise.currentValue ? 1 : 0)
    }

    /// Tap to check off a set manually. Each tap buzzes the wrist once per set so
    /// you can feel how many you've done; the pips fill toward your target.
    private var setPill: some View {
        let done = exercise.completedSetsToday
        let target = max(exercise.targetSets, 1)
        return Button(action: logSetManually) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<min(target, 6), id: \.self) { i in
                        Capsule()
                            .fill(i < done ? tint : Color.white.opacity(0.22))
                            .frame(width: i < done ? 10 : 6, height: 5)
                    }
                }
                Text("\(done)/\(target)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(exercise.allSetsDone ? tint : .secondary)
                    .contentTransition(.numericText())
                Image(systemName: exercise.allSetsDone ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: done)
    }

    /// Primary action: start automatic rep counting from wrist motion.
    private var countButton: some View {
        Button(action: startCounting) {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .bold))
                Text("Count Reps")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button {
                showingRest = true
            } label: {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button(action: commit) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Log")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.bordered)
            .tint(tint)
            .disabled(workingValue == exercise.currentValue)
        }
    }

    // MARK: - Counting mode (live rep count, auto-logs each set on rest)

    private var countingView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 2)
            Text(exercise.name.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
            Text("\(autoSession.reps)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .scaleEffect(repPulse ? 1.08 : 1.0)
                .opacity(autoSession.phase == .paused ? 0.4 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.5), value: repPulse)
            Text("REPS")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(2)

            Spacer(minLength: 2)
            Text("\(workingValue.clean) \(exercise.unit) · Set \(autoSession.setsLogged + 1)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if autoSession.phase == .failed {
                Text("Background tracking stopped")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Button {
                    if autoSession.phase == .paused {
                        autoSession.resume()
                    } else {
                        autoSession.pause()
                    }
                } label: {
                    Image(systemName: autoSession.phase == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button(action: stopCounting) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.bordered)
                .tint(tint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    private func wireAutoSession() {
        autoSession.onRep = {
            WKInterfaceDevice.current().play(.click)
        }
        autoSession.onSetEnded = { _ in
            // A set finished (rest detected): log it at the chosen weight.
            logAutoSet()
        }
    }

    private func startCounting() {
        crownFocused = false
        autoSession.start()
    }

    private func stopCounting() {
        // If the user stops mid-set with reps already counted, log that set so the
        // work isn't lost; the detector only emits a set-end after a rest.
        if autoSession.reps > 0 {
            logAutoSet()
        }
        autoSession.stop()
        crownFocused = true
    }

    /// Auto-log a completed set: record the working weight as today's entry and
    /// increment the completed-set count, then signal with a success haptic +
    /// checkmark flash. Stays on screen so counting continues for the next set.
    private func logAutoSet() {
        persistWeightEntry()
        exercise.logSet()
        WKInterfaceDevice.current().play(.success)
        flashSaved(dismissAfter: false)
    }

    private func logSetManually() {
        let count = exercise.logSet()
        WatchHaptics.setLogged(count: count, target: exercise.targetSets)
    }

    /// Manual "Log" button — commit the weight and pop back to the list.
    private func commit() {
        persistWeightEntry()
        WKInterfaceDevice.current().play(.success)
        flashSaved(dismissAfter: true)
    }

    /// Record `workingValue` as today's data point, collapsing to a single entry
    /// per day (mirrors the manual-commit behaviour the watch already used).
    private func persistWeightEntry() {
        let calendar = Calendar.current
        exercise.currentValue = workingValue

        if let today = exercise.entries.first(where: { calendar.isDateInToday($0.date) }) {
            today.value = workingValue
            today.date = Date()
        } else {
            let entry = ProgressEntry(value: workingValue, date: Date(), exercise: exercise)
            context.insert(entry)
            exercise.entries.append(entry)
        }
    }

    private func flashSaved(dismissAfter: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            savedFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.4)) { savedFlash = false }
            if dismissAfter { dismiss() }
        }
    }
}
