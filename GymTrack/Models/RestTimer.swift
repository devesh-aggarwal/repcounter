import Foundation
import UserNotifications

/// A wall-clock-accurate rest countdown shared across the app.
/// Remaining time is derived from an end date so it stays correct even if
/// ticks are throttled while backgrounded.
@MainActor
final class RestTimer: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var isPaused = false
    @Published private(set) var finished = false
    @Published private(set) var label = "Rest"

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var ticker: Timer?
    private static let notificationID = "gymtrack.rest.timer"

    var isActive: Bool { endDate != nil || isPaused || finished }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining / total))
    }

    func start(seconds: Int, label: String) {
        requestAuthorizationIfNeeded()
        self.label = label
        total = TimeInterval(max(1, seconds))
        remaining = total
        isPaused = false
        finished = false
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(total)
        startTicker()
        scheduleNotification(after: total)
        Haptics.impact(.medium)
    }

    func adjust(by delta: TimeInterval) {
        guard isActive, !finished else { return }
        if isPaused {
            let updated = max(0, (pausedRemaining ?? remaining) + delta)
            pausedRemaining = updated
            remaining = updated
        } else {
            let updatedRemaining = max(0, remaining + delta)
            endDate = Date().addingTimeInterval(updatedRemaining)
            remaining = updatedRemaining
            rescheduleNotification(after: updatedRemaining)
        }
        total = max(total, remaining)
        Haptics.tick()
    }

    func togglePause() {
        guard !finished else { return }
        if isPaused {
            let resumeFrom = pausedRemaining ?? remaining
            endDate = Date().addingTimeInterval(resumeFrom)
            isPaused = false
            pausedRemaining = nil
            startTicker()
            rescheduleNotification(after: resumeFrom)
        } else {
            pausedRemaining = remaining
            isPaused = true
            stopTicker()
            cancelNotification()
        }
        Haptics.tick()
    }

    func stop() {
        stopTicker()
        cancelNotification()
        endDate = nil
        pausedRemaining = nil
        remaining = 0
        isPaused = false
        finished = false
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let end = endDate, !isPaused else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        stopTicker()
        endDate = nil
        remaining = 0
        finished = true
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.finished else { return }
            self.stop()
        }
    }

    // MARK: - Notifications

    private func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(after seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "\(label) — back to it."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func rescheduleNotification(after seconds: TimeInterval) {
        cancelNotification()
        scheduleNotification(after: seconds)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// Formats the remaining time as m:ss.
    var display: String {
        let value = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
