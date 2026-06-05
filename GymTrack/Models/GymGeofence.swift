import Foundation
import CoreLocation
import UserNotifications

/// Watches a user-set "gym" coordinate using CoreLocation region monitoring.
/// When the user crosses the geofence boundary, fires a local notification
/// inviting them to open GymTrack and log a workout.
///
/// What it can't currently do: start a Live Activity on entry — that requires
/// the Widget Extension target to be set up in Xcode. Once that's wired, the
/// `regionDidEnter` handler can additionally call `Activity.request(...)`
/// against a workout-tracking ActivityAttributes type.
///
/// Required Xcode setup (one-time):
/// 1. Signing & Capabilities → add **Background Modes** → check
///    "Location updates".
/// 2. Info → add `NSLocationAlwaysAndWhenInUseUsageDescription` and
///    `NSLocationWhenInUseUsageDescription` keys with user-facing strings
///    explaining why you want background location.
/// 3. User must grant "Always" permission in the system prompt for region
///    monitoring to fire while the app is closed.
@MainActor
final class GymGeofence: NSObject {
    static let shared = GymGeofence()

    private let manager = CLLocationManager()
    private static let regionIdentifier = "gymtrack.gym.region"

    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Asks for "When in Use" first (one-tap permission), then upgrades to
    /// "Always" so region monitoring works in the background.
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// One-shot lookup of the current device location — used by Settings'
    /// "Use my current location as my gym" button.
    func requestCurrentLocation() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                manager.requestLocation()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                continuation.resume(throwing: GeofenceError.locationDenied)
                self.locationContinuation = nil
            @unknown default:
                continuation.resume(throwing: GeofenceError.locationDenied)
                self.locationContinuation = nil
            }
        }
    }

    /// Starts monitoring a circular region around the saved gym coordinate.
    /// Returns immediately; entry/exit events arrive asynchronously through
    /// `CLLocationManagerDelegate`.
    func startMonitoring(latitude: Double, longitude: Double, radius: Double = 120) {
        // Region monitoring requires Always authorization.
        if manager.authorizationStatus != .authorizedAlways {
            manager.requestAlwaysAuthorization()
        }
        stopMonitoring()
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        // CLLocationManager caps each region at 100m–500m; clamp accordingly.
        let clampedRadius = min(max(radius, 100), 500)
        let region = CLCircularRegion(center: center, radius: clampedRadius, identifier: Self.regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    func stopMonitoring() {
        for region in manager.monitoredRegions where region.identifier == Self.regionIdentifier {
            manager.stopMonitoring(for: region)
        }
    }

    /// Configures monitoring from saved Preferences at app launch. Safe to
    /// call when geofencing is disabled — it just becomes a no-op + stop.
    func reconfigureFromPreferences() {
        let prefs = Preferences.shared
        guard prefs.gymGeofenceEnabled,
              let lat = prefs.gymLatitude,
              let lng = prefs.gymLongitude else {
            stopMonitoring()
            return
        }
        startMonitoring(latitude: lat, longitude: lng, radius: prefs.gymRadiusMeters)
    }

    private func deliverArrivalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "You're at the gym 💪"
        content.body = "Open GymTrack to start logging your workout."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "gymtrack.arrival",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension GymGeofence: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionIdentifier else { return }
        Task { @MainActor in
            self.deliverArrivalNotification()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if let continuation = self.locationContinuation {
                continuation.resume(returning: location.coordinate)
                self.locationContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let continuation = self.locationContinuation {
                continuation.resume(throwing: error)
                self.locationContinuation = nil
            }
        }
    }
}

enum GeofenceError: LocalizedError {
    case locationDenied

    var errorDescription: String? {
        switch self {
        case .locationDenied:
            return "Location access denied. Enable it in Settings to use gym arrival detection."
        }
    }
}
