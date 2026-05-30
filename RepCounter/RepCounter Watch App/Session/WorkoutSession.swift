import Foundation
import WatchKit
import Observation

@Observable
final class WorkoutSession: NSObject {

    enum Phase {
        case idle
        case active
        case paused
        /// The extended-runtime session could not be started or was invalidated
        /// for a non-recoverable reason. Rep detection won't survive the screen
        /// sleeping in this state.
        case failed
    }

    // MARK: Observable state
    var phase: Phase = .idle
    var currentSetReps: Int = 0
    var lastSetReps: Int? = nil
    var setNumber: Int = 1

    // MARK: Internals
    private let sampler = MotionSampler()
    private let detector = RepDetector(sampleRate: 50)

    /// Keeps the app process alive (and motion streaming) while the wrist is
    /// down / screen is off, without an HKWorkoutSession. Sessions are time
    /// capped by the system, so we renew on the will-expire warning.
    private var runtimeSession: WKExtendedRuntimeSession?

    private let store = RepStore()

    override init() {
        super.init()
        sampler.onSample = { [weak self] sample in
            self?.detector.process(sample)
        }
        detector.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDetectorEvent(event)
            }
        }
        // Restore any count that was in progress if the app was killed/expired
        // mid-session, so the running total is never lost.
        if let snapshot = store.load() {
            currentSetReps = snapshot.currentSetReps
            lastSetReps = snapshot.lastSetReps
            setNumber = snapshot.setNumber
        }
    }

    // MARK: Public actions

    func start() {
        guard phase == .idle || phase == .failed else { return }
        detector.reset()
        sampler.start()
        // Flip to the active UI before touching the runtime session: its start()
        // can stall on device, and we never want that between the tap and the
        // first render.
        phase = .active
        startRuntimeSession()
    }

    func pause() {
        guard phase == .active else { return }
        sampler.stop()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        detector.reset()
        if runtimeSession?.state != .running {
            startRuntimeSession()
        }
        sampler.start()
        phase = .active
    }

    func end() {
        sampler.stop()
        runtimeSession?.invalidate()
        runtimeSession = nil
        phase = .idle
        currentSetReps = 0
        lastSetReps = nil
        setNumber = 1
        detector.reset()
        store.clear()
    }

    // MARK: Private

    private func startRuntimeSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        runtimeSession = session
        // `WKExtendedRuntimeSession.start()` can block the calling thread for a
        // second or two on real hardware. Calling it on the main thread freezes
        // the UI right after the user taps Start (and on every renewal), so run
        // it off the main thread. Delegate callbacks are still delivered on main.
        let box = UncheckedSendableBox(session)
        DispatchQueue.global(qos: .userInitiated).async {
            box.value.start()
        }
    }

    @MainActor
    private func handleDetectorEvent(_ event: DetectorEvent) {
        switch event {
        case .rep:
            currentSetReps += 1
            WKInterfaceDevice.current().play(.click)
        case .setEnded(let count):
            lastSetReps = count
            setNumber += 1
            currentSetReps = 0
            WKInterfaceDevice.current().play(.success)
        }
        persist()
    }

    private func persist() {
        store.save(.init(currentSetReps: currentSetReps,
                         lastSetReps: lastSetReps,
                         setNumber: setNumber))
    }
}

/// Hands a non-`Sendable` WatchKit object to a background queue for a single,
/// otherwise-safe call. The session is created, stored, and invalidated on the
/// main thread; we only move the blocking `start()` off it.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WorkoutSession: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // No-op: motion sampling is already running.
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // The system is about to reclaim this session. Start a fresh one so the
        // process — and therefore motion sampling — keeps going without a gap.
        guard phase == .active else { return }
        startRuntimeSession()
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        // Only react to the session we currently hold; a renewed session
        // supersedes an expiring one, whose invalidation we can ignore.
        guard extendedRuntimeSession === runtimeSession else { return }
        runtimeSession = nil

        switch reason {
        case .sessionInProgress, .expired:
            // Recoverable: try to keep counting if the user is still working out.
            if phase == .active {
                startRuntimeSession()
            }
        default:
            // .error, .resignedFrontmost, .suppressedBySystem, etc. — the app
            // may now be suspended when the screen sleeps. Surface it; the
            // persisted count is safe either way.
            if phase == .active || phase == .paused {
                phase = .failed
            }
        }
    }
}

// MARK: - Persistence

/// Persists the running rep tally across launches so an expired or killed
/// session never loses the count already accumulated.
private struct RepStore {
    struct Snapshot: Codable {
        var currentSetReps: Int
        var lastSetReps: Int?
        var setNumber: Int
    }

    private let key = "RepCounter.inProgressSnapshot"
    private let defaults = UserDefaults.standard

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> Snapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
