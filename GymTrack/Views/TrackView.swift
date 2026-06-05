import SwiftUI
import SwiftData

/// Tab 1 — the day's plan. Display-only list of exercise rows. A prominent
/// "Workout Mode" CTA enters the hero flow; tapping any individual row enters
/// Workout Mode at that exercise. There's no inline editing — all of that
/// lives in Workout Mode where it has room to breathe.
struct TrackView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var restTimer: RestTimer
    @Query(sort: \Exercise.sortIndex) private var exercises: [Exercise]

    @State private var selectedDay: SplitDay?
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var editing: Exercise?
    @State private var workoutModeStartingID: UUID?
    @State private var showingWorkoutMode = false

    private var recommendedDay: SplitDay {
        WorkoutSchedule.recommendedDay(from: exercises)
    }

    private var effectiveDay: SplitDay {
        selectedDay ?? recommendedDay
    }

    private var dayExercises: [Exercise] {
        exercises
            .filter { $0.day == effectiveDay }
            .sorted { $0.orderInDay < $1.orderInDay }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        dayHeader
                        if !dayExercises.isEmpty {
                            startWorkoutButton
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                        }
                        ForEach(dayExercises) { exercise in
                            ExerciseRow(exercise: exercise) {
                                workoutModeStartingID = exercise.id
                                showingWorkoutMode = true
                                Haptics.impact(.light)
                            }
                            .contextMenu {
                                Button { editing = exercise } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) { delete(exercise) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        if dayExercises.isEmpty {
                            emptyDay
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .accessibilityLabel("Add exercise")
                }
            }
            .sheet(isPresented: $showingAdd) {
                ExerciseEditor(exercise: nil, defaultDay: effectiveDay)
            }
            .sheet(item: $editing) { exercise in
                ExerciseEditor(exercise: exercise, defaultDay: exercise.day)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showingWorkoutMode) {
                // Explicitly forward the RestTimer environment object —
                // fullScreenCover doesn't reliably inherit it on all iOS
                // versions, and WorkoutModeView (and its ExerciseFocusCard
                // children) crash without it.
                WorkoutModeView(
                    exercises: dayExercises,
                    startingExerciseID: $workoutModeStartingID
                )
                .environmentObject(restTimer)
            }
        }
    }

    // MARK: - Header

    private var dayHeader: some View {
        let day = effectiveDay
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Workout", selection: Binding(
                get: { effectiveDay },
                set: { newDay in withAnimation(.snappy) { selectedDay = newDay } }
            )) {
                ForEach(SplitDay.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .tint(day.color)

            HStack(spacing: 8) {
                Text(day.focus)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if day == recommendedDay {
                    Text("Today")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(day.color))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Start CTA

    private var startWorkoutButton: some View {
        Button {
            workoutModeStartingID = dayExercises.first?.id
            showingWorkoutMode = true
            Haptics.impact(.medium)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Workout Mode")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [effectiveDay.color, effectiveDay.color.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: effectiveDay.color.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyDay: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textTertiary)
            Text("No exercises for this day yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Button("Add Exercise") { showingAdd = true }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(effectiveDay.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func delete(_ exercise: Exercise) {
        context.delete(exercise)
        Haptics.impact()
    }
}

#Preview {
    TrackView()
        .modelContainer(PreviewData.container)
        .environmentObject(RestTimer())
        .preferredColorScheme(.dark)
}
