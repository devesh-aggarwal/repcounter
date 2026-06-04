import SwiftUI
import SwiftData

/// Watch's first surface. Today's split's exercises as a vertical list,
/// each row is a tap target that opens `WatchExerciseView`. Splits are
/// switched inline via a row of colored dots at the top — `Menu` doesn't
/// exist on watchOS and the navigation-link Picker style rendered as a
/// busy stacked label/value chip in the toolbar.
struct WatchTodayView: View {
    @Query(sort: \Exercise.sortIndex) private var exercises: [Exercise]
    @State private var selectedDay: SplitDay?

    private var effectiveDay: SplitDay {
        selectedDay ?? recommendedDay
    }

    private var recommendedDay: SplitDay {
        WorkoutSchedule.recommendedDay(from: exercises)
    }

    private var dayExercises: [Exercise] {
        exercises
            .filter { $0.day == effectiveDay }
            .sorted { $0.orderInDay < $1.orderInDay }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background.ignoresSafeArea()
                if dayExercises.isEmpty && exercises.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Today")
        }
    }

    private var list: some View {
        List {
            // Split switcher — four colored dots, tap to change split.
            // Compact, glanceable, native-feeling on the small screen.
            splitDots
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 6, trailing: 4))

            // Split title + "Today" marker.
            HStack(spacing: 4) {
                Text(effectiveDay.title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchTheme.color(forHex: effectiveDay.colorHex))
                    .tracking(2)
                if effectiveDay == recommendedDay {
                    Text("· Today")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 4, trailing: 8))

            if dayExercises.isEmpty {
                Text("No exercises in this split")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(dayExercises) { exercise in
                    NavigationLink {
                        WatchExerciseView(exercise: exercise)
                    } label: {
                        WatchExerciseRow(exercise: exercise)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
            }
        }
        .listStyle(.carousel)
    }

    private var splitDots: some View {
        HStack(spacing: 10) {
            ForEach(SplitDay.allCases) { day in
                Button {
                    selectedDay = day
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    ZStack {
                        Circle()
                            .fill(WatchTheme.color(forHex: day.colorHex))
                            .opacity(day == effectiveDay ? 1.0 : 0.35)
                            .frame(
                                width: day == effectiveDay ? 14 : 9,
                                height: day == effectiveDay ? 14 : 9
                            )
                        if day == effectiveDay {
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: effectiveDay)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No exercises yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

import WatchKit

private struct WatchExerciseRow: View {
    let exercise: Exercise

    private var tint: Color { WatchTheme.color(forHex: exercise.colorHex) }
    private var loggedToday: Bool {
        let calendar = Calendar.current
        return exercise.entries.contains { calendar.isDateInToday($0.date) }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.2)).frame(width: 28, height: 28)
                Image(systemName: exercise.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if loggedToday {
                        Circle().fill(WatchTheme.accent).frame(width: 4, height: 4)
                    }
                    Text(exercise.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                Text("\(exercise.currentValue.clean) \(exercise.unit)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
