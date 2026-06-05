import SwiftUI

/// The hero surface — Workout Mode. One exercise fills the screen; swipe
/// horizontally through the day's exercises. After the last exercise comes a
/// "Good job" completion page.
struct WorkoutModeView: View {
    let exercises: [Exercise]
    @Binding var startingExerciseID: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var restTimer: RestTimer

    @State private var currentIndex: Int = 0

    /// `count` is one past the last exercise — the trailing tag is the
    /// "Good job" page.
    private var pageCount: Int { exercises.count + 1 }
    private var isOnCompletionPage: Bool { currentIndex == exercises.count }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if exercises.isEmpty {
                emptyState
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                        ExerciseFocusCard(exercise: exercise)
                            .tag(index)
                    }
                    SessionCompleteCard(
                        exercises: exercises,
                        onClose: dismiss.callAsFunction
                    )
                    .tag(exercises.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(.container, edges: .bottom)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if restTimer.isActive {
                    RestTimerBar(timer: restTimer)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                pageIndicator
                    .padding(.bottom, 32)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: restTimer.isActive)
        }
        .toolbar(.hidden, for: .tabBar, .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if let id = startingExerciseID,
               let index = exercises.firstIndex(where: { $0.id == id }) {
                currentIndex = index
            }
            startingExerciseID = nil
        }
    }

    // MARK: - Layout

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tick()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            Spacer()
            if !exercises.isEmpty, !isOnCompletionPage {
                Text("\(currentIndex + 1) of \(exercises.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex
                          ? Theme.textPrimary
                          : Theme.textPrimary.opacity(0.18))
                    .frame(
                        width: i == currentIndex ? 22 : 6,
                        height: 6
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text("No exercises in this split.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Button("Close") { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 4)
        }
    }

}

// MARK: - Session complete

/// Reward page shown when the user swipes past the last exercise. Big
/// "Good job", the day's color, and a one-tap close.
private struct SessionCompleteCard: View {
    let exercises: [Exercise]
    let onClose: () -> Void

    private var loggedCount: Int {
        exercises.filter(\.isLoggedToday).count
    }

    private var totalSets: Int {
        exercises.reduce(0) { $0 + $1.completedSetsToday }
    }

    private var splitColor: Color {
        Color(hex: exercises.first?.colorHex ?? Theme.accent.description)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [splitColor.opacity(0.18), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(splitColor.opacity(0.16))
                        .frame(width: 130, height: 130)
                    Image(systemName: "checkmark")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(splitColor)
                }
                VStack(spacing: 8) {
                    Text("Good job")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(loggedCount) of \(exercises.count) logged")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    if totalSets > 0 {
                        Text("\(totalSets) set\(totalSets == 1 ? "" : "s") this session")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(splitColor)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(splitColor))
                        .shadow(color: splitColor.opacity(0.4), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
            .padding(.top, 80)
        }
        .onAppear {
            Haptics.success()
            CelebrationCenter.shared.celebrate()
        }
    }
}
