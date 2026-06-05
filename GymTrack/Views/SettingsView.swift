import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]

    @Bindable private var prefs = Preferences.shared

    @State private var showResetConfirm = false
    @State private var showShareSheet = false

    private let units = ["lbs", "kg"]
    /// 2 = Mon … 1 = Sun. Reordered so Monday leads the list.
    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            Form {
                unitsSection
                restSection
                scheduleSection
                aiSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .confirmationDialog(
                "Delete all exercises and history?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Erase Everything", role: .destructive, action: resetAllData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every exercise and every logged session from this device. Export first if you want a backup.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = CSVExport.makeFile(from: exercises) {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: Sections

    private var unitsSection: some View {
        Section {
            Picker("Default unit", selection: $prefs.defaultUnit) {
                ForEach(units, id: \.self) { unit in
                    Text(unit).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Weight unit")
        } footer: {
            Text("Used as the starting unit when you add a new exercise. Existing exercises keep their current unit — change it in the exercise editor.")
        }
    }

    private var restSection: some View {
        Section {
            Picker("Default rest", selection: $prefs.defaultRestSeconds) {
                ForEach([30, 45, 60, 75, 90, 120, 150, 180], id: \.self) { seconds in
                    Text(formatRest(seconds)).tag(seconds)
                }
            }
        } header: {
            Text("Rest timer")
        } footer: {
            Text("Applied to new exercises. Existing exercises keep their own rest duration — change it in the exercise editor.")
        }
    }

    private var aiSection: some View {
        Section {
            SecureField("OpenAI API key (sk-…)", text: $prefs.openAIAPIKey)
                .font(.system(size: 14, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !prefs.openAIAPIKey.isEmpty {
                Button("Clear key", role: .destructive) {
                    prefs.openAIAPIKey = ""
                    Haptics.impact()
                }
            }
        } header: {
            Text("AI coach")
        } footer: {
            Text("The Coach tab streams responses from OpenAI using your API key. Keys never leave this device. Get one at platform.openai.com/api-keys.")
        }
    }

    private func formatRest(_ seconds: Int) -> String {
        if seconds % 60 == 0 {
            let mins = seconds / 60
            return mins == 1 ? "1 min" : "\(mins) min"
        }
        return "\(seconds)s"
    }

    private var scheduleSection: some View {
        Section {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                HStack {
                    Text(weekday.weekdayFullName)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("", selection: scheduleBinding(for: weekday)) {
                        Text("Auto").tag(SplitDay?.none)
                        ForEach(SplitDay.allCases) { day in
                            Text(day.title).tag(SplitDay?.some(day))
                        }
                    }
                    .labelsHidden()
                    .tint(prefs.schedule[weekday]?.color ?? Theme.textTertiary)
                }
            }
            Button("Reset to Auto") {
                prefs.schedule = Preferences.defaultSchedule
                Haptics.tick()
            }
            .foregroundStyle(Theme.accent)
        } header: {
            Text("Weekly schedule")
        } footer: {
            Text("Auto picks up where you left off in the rotation (Push → Pull → Legs → Misc). Mondays and Fridays never recommend Legs — they substitute Misc instead. Pin a specific workout to a day only if you always do that workout on that day.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                showShareSheet = true
                Haptics.tick()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(exercises.isEmpty)
            .foregroundStyle(Theme.textPrimary)

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Erase all data", systemImage: "trash")
            }
            .disabled(exercises.isEmpty)
        } header: {
            Text("Data")
        } footer: {
            Text("Your data lives on this device only. It is not backed up to iCloud or sent anywhere. Reinstalling the app erases it.")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(versionString)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: Helpers

    private func scheduleBinding(for weekday: Int) -> Binding<SplitDay?> {
        Binding(
            get: { prefs.schedule[weekday] },
            set: { newValue in
                if let newValue {
                    prefs.schedule[weekday] = newValue
                } else {
                    prefs.schedule.removeValue(forKey: weekday)
                }
                Haptics.tick()
            }
        )
    }

    private func resetAllData() {
        for exercise in exercises {
            context.delete(exercise)
        }
        try? context.save()
        Haptics.impact(.heavy)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// UIKit bridge for `UIActivityViewController`. SwiftUI's `ShareLink` only
/// accepts compile-time-known item types — this lets us share a URL produced
/// from a button press without re-fetching exercises on every render.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
