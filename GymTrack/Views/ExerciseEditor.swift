import SwiftUI
import SwiftData

struct ExerciseEditor: View {
    /// When non-nil the editor updates an existing exercise; otherwise it creates one.
    let exercise: Exercise?
    /// The split day a newly created exercise is added to.
    var defaultDay: SplitDay = .push

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit = "lbs"
    @State private var minValue = 0.0
    @State private var maxValue = 500.0
    @State private var step = 2.5
    @State private var startValue = 45.0
    @State private var colorHex = Theme.palette[0]
    @State private var iconName = Theme.icons[0]
    @State private var restSeconds = 60
    @State private var barWeight = 45.0
    @State private var usesPlates = false
    @State private var targetSets = 3
    @State private var day: SplitDay = .push

    private let units = ["lbs", "kg", "reps", "sec", "min", "mi", "km"]

    private var tint: Color { Color(hex: colorHex) }
    private var isEditing: Bool { exercise != nil }
    private var isWeightUnit: Bool { unit == "lbs" || unit == "kg" }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && maxValue > minValue }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        previewCard
                        nameField
                        dayPicker
                        iconPicker
                        colorPicker
                        unitPicker
                        rangeFields
                        setsSection
                        timerSection
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var previewCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 46, height: 46)
                Image(systemName: iconName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(name.isEmpty ? "Exercise name" : name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(name.isEmpty ? Theme.textTertiary : Theme.textPrimary)
            Spacer()
            Text("\(startValue.clean) \(unit)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        )
    }

    private var nameField: some View {
        section("NAME") {
            TextField("", text: $name, prompt: Text("e.g. Incline Press").foregroundColor(Theme.textTertiary))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(16)
                .background(fieldBackground)
        }
    }

    private var dayPicker: some View {
        section("WORKOUT DAY") {
            HStack(spacing: 10) {
                ForEach(SplitDay.allCases) { option in
                    let selected = option == day
                    Text(option.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selected ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule().fill(selected ? AnyShapeStyle(option.color) : AnyShapeStyle(Theme.surface))
                        )
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: selected ? 0 : 1))
                        .onTapGesture {
                            withAnimation(.snappy) { day = option }
                            Haptics.tick()
                        }
                }
            }
        }
    }

    private var iconPicker: some View {
        section("ICON") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Theme.icons, id: \.self) { icon in
                        let selected = icon == iconName
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selected ? .black : Theme.textSecondary)
                            .frame(width: 46, height: 46)
                            .background(
                                Circle().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surface))
                            )
                            .overlay(Circle().stroke(Theme.stroke, lineWidth: selected ? 0 : 1))
                            .onTapGesture {
                                iconName = icon
                                Haptics.tick()
                            }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var colorPicker: some View {
        section("ACCENT") {
            HStack(spacing: 12) {
                ForEach(Theme.palette, id: \.self) { hex in
                    let selected = hex == colorHex
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Circle().stroke(.white, lineWidth: selected ? 3 : 0)
                        )
                        .scaleEffect(selected ? 1.1 : 1)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) { colorHex = hex }
                            Haptics.tick()
                        }
                }
            }
        }
    }

    private var unitPicker: some View {
        section("UNIT") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(units, id: \.self) { option in
                        let selected = option == unit
                        Text(option)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? .black : Theme.textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surface))
                            )
                            .overlay(Capsule().stroke(Theme.stroke, lineWidth: selected ? 0 : 1))
                            .onTapGesture {
                                unit = option
                                if option == "lbs" || option == "kg" {
                                    barWeight = PlateMath.defaultBar(for: option)
                                }
                                Haptics.tick()
                            }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var timerSection: some View {
        section("REST & BAR") {
            VStack(spacing: 0) {
                HStack {
                    Text("Rest timer")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(restDisplay)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(minWidth: 60)
                    Stepper("", value: restBinding, in: 15...600, step: 15)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if isWeightUnit {
                    divider
                    Toggle(isOn: $usesPlates) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uses plates")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Smith machine, barbell — anything you load plates on.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .tint(tint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if usesPlates {
                        divider
                        numberRow("Bar weight", value: $barWeight, range: 0...100, stepBy: 5)
                    }
                }
            }
            .background(fieldBackground)
        }
    }

    private var setsSection: some View {
        section("SETS") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target sets")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("How many sets you'll aim for in Workout Mode.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text("\(targetSets)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(minWidth: 28)
                Stepper("", value: $targetSets, in: 1...Exercise.maxSets)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(fieldBackground)
        }
    }

    private var restBinding: Binding<Double> {
        Binding(get: { Double(restSeconds) }, set: { restSeconds = Int($0) })
    }

    private var restDisplay: String {
        restSeconds % 60 == 0 ? "\(restSeconds / 60) min" : "\(restSeconds)s"
    }

    private var rangeFields: some View {
        section("RANGE & STEP") {
            VStack(spacing: 0) {
                numberRow("Minimum", value: $minValue, range: 0...maxValue, stepBy: step)
                divider
                numberRow("Maximum", value: $maxValue, range: minValue...10000, stepBy: step)
                divider
                numberRow("Increment", value: $step, range: 1...50, stepBy: 1)
                divider
                numberRow("Starting value", value: $startValue, range: minValue...maxValue, stepBy: step)
            }
            .background(fieldBackground)
        }
    }

    private func numberRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, stepBy: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value.wrappedValue.clean)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(minWidth: 46)
            Stepper("", value: value, in: range, step: stepBy)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.horizontal, 16)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        guard let exercise else {
            // New exercise: inherit the day we were opened for and the user's
            // preferred default unit + rest duration.
            day = defaultDay
            colorHex = defaultDay.colorHex
            unit = Preferences.shared.defaultUnit
            restSeconds = Preferences.shared.defaultRestSeconds
            return
        }
        name = exercise.name
        unit = exercise.unit
        minValue = exercise.minValue
        maxValue = exercise.maxValue
        step = exercise.step
        startValue = exercise.currentValue
        colorHex = exercise.colorHex
        iconName = exercise.iconName
        restSeconds = exercise.restSeconds
        barWeight = exercise.barWeight
        usesPlates = exercise.usesPlates
        targetSets = exercise.targetSets
        day = exercise.day
    }

    private func save() {
        let clampedStart = min(max(minValue, startValue), maxValue)
        if let exercise {
            exercise.name = name.trimmingCharacters(in: .whitespaces)
            exercise.unit = unit
            exercise.minValue = minValue
            exercise.maxValue = maxValue
            exercise.step = step
            exercise.currentValue = clampedStart
            exercise.colorHex = colorHex
            exercise.iconName = iconName
            exercise.restSeconds = restSeconds
            exercise.barWeight = barWeight
            exercise.usesPlates = usesPlates
            exercise.targetSets = targetSets
            exercise.day = day
        } else {
            let newExercise = Exercise(
                name: name.trimmingCharacters(in: .whitespaces),
                unit: unit, minValue: minValue, maxValue: maxValue,
                step: step, currentValue: clampedStart,
                colorHex: colorHex, iconName: iconName, sortIndex: totalCount,
                barWeight: barWeight, restSeconds: restSeconds
            )
            newExercise.dayRaw = day.rawValue
            newExercise.orderInDay = countInDay
            newExercise.usesPlates = usesPlates
            newExercise.targetSets = targetSets
            context.insert(newExercise)
        }
        Haptics.success()
        dismiss()
    }

    /// Total number of exercises, used as the next global sort index.
    private var totalCount: Int {
        (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
    }

    /// Number of exercises already in the chosen day, used as the next order.
    private var countInDay: Int {
        let raw = day.rawValue
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate<Exercise> { $0.dayRaw == raw })
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}

#Preview {
    ExerciseEditor(exercise: nil, defaultDay: .push)
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
