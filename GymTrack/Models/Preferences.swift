import Foundation
import Observation

/// App-wide user preferences persisted in `UserDefaults`. Observable so any view
/// reading `Preferences.shared` re-renders when a setting changes.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    /// Default unit applied to new exercises. Existing exercises keep their
    /// own per-exercise unit; this is just the editor's starting value.
    var defaultUnit: String {
        didSet { UserDefaults.standard.set(defaultUnit, forKey: Keys.defaultUnit) }
    }

    /// Maps `Calendar.component(.weekday, ...)` (1 = Sun … 7 = Sat) to the
    /// workout split day. Missing entries mean "no scheduled workout".
    var schedule: [Int: SplitDay] {
        didSet { saveSchedule() }
    }

    /// Whether to seed a starter program on first launch. Cleared after one
    /// seeding so a manual data reset doesn't repopulate fake history.
    var hasSeeded: Bool {
        didSet { UserDefaults.standard.set(hasSeeded, forKey: Keys.hasSeeded) }
    }

    /// Default rest-timer seconds applied to newly created exercises.
    var defaultRestSeconds: Int {
        didSet { UserDefaults.standard.set(defaultRestSeconds, forKey: Keys.defaultRestSeconds) }
    }

    /// User-supplied OpenAI API key for the in-app AI coach. Empty when not
    /// set; the AI tab gracefully shows a setup screen instead.
    var openAIAPIKey: String {
        didSet { UserDefaults.standard.set(openAIAPIKey, forKey: Keys.openAIAPIKey) }
    }

    /// Whether GymTrack mirrors training sessions to Apple Health.
    var syncToHealthKit: Bool {
        didSet { UserDefaults.standard.set(syncToHealthKit, forKey: Keys.syncToHealthKit) }
    }

    /// Whether the gym-arrival geofence is armed.
    var gymGeofenceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(gymGeofenceEnabled, forKey: Keys.gymGeofenceEnabled)
            Task { @MainActor in GymGeofence.shared.reconfigureFromPreferences() }
        }
    }

    /// Saved gym latitude — nil when unset.
    var gymLatitude: Double? {
        didSet {
            if let gymLatitude {
                UserDefaults.standard.set(gymLatitude, forKey: Keys.gymLatitude)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.gymLatitude)
            }
        }
    }

    /// Saved gym longitude — nil when unset.
    var gymLongitude: Double? {
        didSet {
            if let gymLongitude {
                UserDefaults.standard.set(gymLongitude, forKey: Keys.gymLongitude)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.gymLongitude)
            }
        }
    }

    /// Geofence radius in meters (clamped 100–500 in GymGeofence).
    var gymRadiusMeters: Double {
        didSet { UserDefaults.standard.set(gymRadiusMeters, forKey: Keys.gymRadiusMeters) }
    }

    var isGymLocationSet: Bool { gymLatitude != nil && gymLongitude != nil }

    /// Empty by default — the recommendation falls back to rotation-from-
    /// history, with Mon/Fri never landing on Legs. Users who want a fixed
    /// "I always do X on Y" day can pin it in Settings.
    static let defaultSchedule: [Int: SplitDay] = [:]

    private init() {
        let store = UserDefaults.standard
        self.defaultUnit = store.string(forKey: Keys.defaultUnit) ?? "lbs"
        self.hasSeeded = store.bool(forKey: Keys.hasSeeded)
        // Default to 60s rest unless the user has explicitly overridden it.
        let storedRest = store.integer(forKey: Keys.defaultRestSeconds)
        self.defaultRestSeconds = storedRest > 0 ? storedRest : 60
        self.openAIAPIKey = store.string(forKey: Keys.openAIAPIKey) ?? ""
        self.syncToHealthKit = store.bool(forKey: Keys.syncToHealthKit)
        self.gymGeofenceEnabled = store.bool(forKey: Keys.gymGeofenceEnabled)
        self.gymLatitude = store.object(forKey: Keys.gymLatitude) as? Double
        self.gymLongitude = store.object(forKey: Keys.gymLongitude) as? Double
        let storedRadius = store.double(forKey: Keys.gymRadiusMeters)
        self.gymRadiusMeters = storedRadius > 0 ? storedRadius : 120
        if let data = store.data(forKey: Keys.schedule),
           let decoded = try? JSONDecoder().decode([Int: SplitDay].self, from: data) {
            self.schedule = decoded
        } else {
            self.schedule = Self.defaultSchedule
        }
    }

    private func saveSchedule() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        UserDefaults.standard.set(data, forKey: Keys.schedule)
    }

    private enum Keys {
        static let defaultUnit = "preferences.defaultUnit"
        static let schedule = "preferences.weekdaySchedule"
        static let hasSeeded = "preferences.hasSeeded"
        static let defaultRestSeconds = "preferences.defaultRestSeconds"
        static let openAIAPIKey = "preferences.openAIAPIKey"
        static let syncToHealthKit = "preferences.syncToHealthKit"
        static let gymGeofenceEnabled = "preferences.gymGeofenceEnabled"
        static let gymLatitude = "preferences.gymLatitude"
        static let gymLongitude = "preferences.gymLongitude"
        static let gymRadiusMeters = "preferences.gymRadiusMeters"
    }
}

extension Int {
    /// Localized short weekday name for `Calendar.component(.weekday, ...)`.
    /// 1 = Sunday … 7 = Saturday.
    var weekdayShortName: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = self - 1
        return symbols.indices.contains(index) ? symbols[index] : "?"
    }

    var weekdayFullName: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = self - 1
        return symbols.indices.contains(index) ? symbols[index] : "?"
    }
}
