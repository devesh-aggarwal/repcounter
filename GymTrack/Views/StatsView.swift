import SwiftUI
import SwiftData
import Charts

/// Tab 2 — Summary. Magazine spread: a giant headline number anchors the
/// page, the heatmap acts as a hero illustration, and below it sit one chart,
/// a short records list, and swipeable insights. No grid of small cards.
struct StatsView: View {
    @Query(sort: \Exercise.sortIndex) private var exercises: [Exercise]

    @State private var selectedID: UUID?
    @State private var range: TimeRange = .all
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false

    enum TimeRange: String, CaseIterable, Identifiable {
        case month = "1M"
        case quarter = "3M"
        case all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .month: return 30
            case .quarter: return 90
            case .all: return nil
            }
        }
    }

    private var selected: Exercise? {
        if let selectedID, let match = exercises.first(where: { $0.id == selectedID }) { return match }
        return exercises.max(by: { $0.stats.totalChange < $1.stats.totalChange })
            ?? exercises.first
    }

    private var tint: Color { selected.map { Color(hex: $0.colorHex) } ?? Theme.accent }

    private var filteredEntries: [ProgressEntry] {
        guard let selected else { return [] }
        let all = selected.sortedEntries
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return all }
        return all.filter { $0.date >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if exercises.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 36) {
                            heroHeadline
                            activitySection
                            progressionSection
                            recordsSection
                            insightsSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 60)
                    }
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !exercises.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            shareSnapshot()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .accessibilityLabel("Share progress card")
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let shareImage {
                    StatsShareSheet(image: shareImage)
                }
            }
        }
    }

    // MARK: - Hero (contextual rotating headline)

    private var heroHeadline: some View {
        let headline = StatHeadlineEngine.headline(for: exercises)
        let week = WorkoutAnalytics.sessionsThisWeek(exercises)
        let streak = WorkoutAnalytics.weekStreak(exercises)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(headline.headline)
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accentGradient)
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                if !headline.headlineSuffix.isEmpty {
                    Text(headline.headlineSuffix)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Text(headline.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .tracking(2.5)
                .padding(.top, 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle = headline.subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 24) {
                miniStat(value: "\(week)", label: week == 1 ? "this week" : "this week")
                miniStat(value: "\(streak)", label: streak == 1 ? "week streak" : "week streak")
                Spacer()
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(1)
        }
    }

    // MARK: - Activity heatmap

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ACTIVITY", trailing: "Last 12 weeks")
            ActivityHeatmap(exercises: exercises, weeks: 12, tint: Theme.accent)
        }
    }

    // MARK: - Progression

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Menu {
                    ForEach(exercises) { exercise in
                        Button(exercise.name) { selectedID = exercise.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selected?.name ?? "Exercise")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                rangePicker
            }

            if filteredEntries.count >= 2, let selected {
                ProgressChart(entries: filteredEntries, unit: selected.unit, tint: tint)
                rateCaption
            } else {
                placeholder("Log two or more sessions to see this trend")
            }
        }
    }

    private var rateCaption: some View {
        let stats = ExerciseStats(entries: filteredEntries, fallbackValue: selected?.currentValue ?? 0)
        let up = stats.weeklyRate >= 0
        let unit = selected?.unit ?? ""
        return HStack(spacing: 6) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(up ? Theme.accent : Theme.move)
            Text("\(up ? "+" : "−")\(abs(stats.weeklyRate).clean) \(unit)/week")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("· \(stats.sessionCount) sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(TimeRange.allCases) { option in
                let isSelected = option == range
                Text(option.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Theme.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Color.clear)))
                    .onTapGesture {
                        withAnimation(.snappy) { range = option }
                        Haptics.tick()
                    }
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.fill))
    }

    // MARK: - Records (top 3, magazine-style)

    private var recordsSection: some View {
        let records = exercises
            .filter { $0.stats.hasTrend }
            .sorted { $0.stats.totalChange > $1.stats.totalChange }
            .prefix(3)
        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("TOP MOVERS", trailing: nil)
            if records.isEmpty {
                placeholder("Your records will appear as you log progress")
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { _, exercise in
                        recordRow(exercise)
                    }
                }
            }
        }
    }

    private func recordRow(_ exercise: Exercise) -> some View {
        let stats = exercise.stats
        let color = Color(hex: exercise.colorHex)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: exercise.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Best \(stats.personalBest.clean) \(exercise.unit)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("+\(stats.totalChange.clean)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text(exercise.unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Insights (swipeable)

    private var insightsSection: some View {
        let insights = InsightEngine.summary(for: exercises)
        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("INSIGHTS", trailing: nil)
            TabView {
                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    insightCard(insight)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 30)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 140)
        }
    }

    private func insightCard(_ insight: Insight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(insight.color.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: insight.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(insight.color)
            }
            Text(insight.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .tracking(2.5)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .multilineTextAlignment(.center)
    }

    @MainActor
    private func shareSnapshot() {
        let card = StatsShareCard(exercises: exercises, renderedDate: Date())
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        if let uiImage = renderer.uiImage {
            shareImage = uiImage
            showingShareSheet = true
            Haptics.success()
        } else {
            Haptics.impact(.heavy)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
            Text("No data yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Log your lifts in the Today tab to see\nyour progress here.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

#Preview {
    StatsView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
