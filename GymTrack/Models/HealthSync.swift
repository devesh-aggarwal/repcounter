import Foundation
import HealthKit

/// Apple Health bridge — writes one `HKWorkout` per logged training day so
/// GymTrack sessions show up in the Fitness / Health timeline alongside walks
/// and runs. Idempotent per-day: re-syncing the same day replaces the prior
/// workout instead of stacking duplicates.
///
/// Requires the HealthKit capability and the two privacy-usage strings in
/// `Info.plist` (`NSHealthShareUsageDescription`,
/// `NSHealthUpdateUsageDescription`). If neither is configured,
/// `requestAuthorization` returns `.notDetermined` and writes silently no-op.
@MainActor
final class HealthSync {
    static let shared = HealthSync()
    private let store = HKHealthStore()
    private let sourceMetadataKey = "com.gymtrack.workoutSource"
    private let sourceMetadataValue = "GymTrack"

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {}

    /// Prompts the system Health permission sheet. Safe to call repeatedly —
    /// iOS only shows the sheet on the first request.
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let workoutType = HKObjectType.workoutType()
        try await store.requestAuthorization(toShare: [workoutType], read: [workoutType])
    }

    /// Writes today's training as a single strength-training workout. If
    /// there's already a GymTrack-tagged workout for the same calendar day,
    /// the old one is deleted first so we don't double-count.
    func syncTodayWorkout(exercises: [Exercise]) async throws {
        guard isAvailable else { return }
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? Date()

        let todayDates: [Date] = exercises.flatMap { exercise in
            exercise.entries
                .filter { calendar.isDateInToday($0.date) }
                .map(\.date)
        }
        guard let earliest = todayDates.min() else { return }
        let latest = todayDates.max() ?? Date()
        // Workouts <5 min look like data glitches in Health — give it a floor.
        let end = max(latest, earliest.addingTimeInterval(5 * 60))

        try await deleteExisting(in: todayStart, end: todayEnd)
        let workout = HKWorkout(
            activityType: .traditionalStrengthTraining,
            start: earliest,
            end: end,
            duration: end.timeIntervalSince(earliest),
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: [
                sourceMetadataKey: sourceMetadataValue,
                HKMetadataKeyIndoorWorkout: true
            ]
        )
        try await store.save(workout)
    }

    /// One-shot backfill across all logged history. Re-runs `syncTodayWorkout`
    /// for every day with entries — useful for "Sync now" in Settings.
    func syncAllWorkouts(exercises: [Exercise]) async throws {
        guard isAvailable else { return }
        try await requestAuthorization()
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }

        let calendar = Calendar.current
        var dayBuckets: [Date: [Date]] = [:]
        for exercise in exercises {
            for entry in exercise.entries {
                let day = calendar.startOfDay(for: entry.date)
                dayBuckets[day, default: []].append(entry.date)
            }
        }

        for (day, dates) in dayBuckets {
            guard let earliest = dates.min() else { continue }
            let latest = dates.max() ?? earliest
            let end = max(latest, earliest.addingTimeInterval(5 * 60))
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            try await deleteExisting(in: day, end: next)
            let workout = HKWorkout(
                activityType: .traditionalStrengthTraining,
                start: earliest,
                end: end,
                duration: end.timeIntervalSince(earliest),
                totalEnergyBurned: nil,
                totalDistance: nil,
                metadata: [
                    sourceMetadataKey: sourceMetadataValue,
                    HKMetadataKeyIndoorWorkout: true
                ]
            )
            try await store.save(workout)
        }
    }

    private func deleteExisting(in start: Date, end: Date) async throws {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        let mine = workouts.filter {
            ($0.metadata?[sourceMetadataKey] as? String) == sourceMetadataValue
        }
        guard !mine.isEmpty else { return }
        try await store.delete(mine)
    }
}
