import Foundation
import WatchKit
import Observation

/// Drives automatic rep counting for the watch's exercise screen.
///
/// Wraps the `MotionSampler` + `RepDetector` pipeline (the engine merged in from
/// RepCounter) and a `WKExtendedRuntimeSession` so counting survives the screen
/// sleeping / the wrist dropping mid-set. Unlike a one-shot counter it keeps
/// running across sets: each time the detector sees a set end (a rest after a
/// run of reps) it fires `onSetEnded` so the view can log that set into the
/// shared SwiftData store, then re-arms for the next set automatically.
///
/// Modelled on RepCounter's `WorkoutSession`; the threading / runtime-session
/// lifecycle is kept identical because that code is proven against the same
/// build settings (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
@Observable
final class AutoRepSession: NSObject {

    enum Phase {
        case idle
        case counting
        case paused
        /// The extended-runtime session could not be started or was invalidated
        /// for a non-recoverable reason. Counting won't survive the screen
        /// sleeping in this state.
        case failed
    }

    // MARK: Observable state
    var phase: Phase = .idle
    /// Reps counted in the set currently in progress.
    var reps: Int = 0
    /// Total sets auto-logged in this counting session (for light UI feedback).
    var setsLogged: Int = 0

    // MARK: Callbacks (fired on the main actor)
    /// Fired once per confirmed rep — use for a per-rep haptic / pulse.
    var onRep: (() -> Void)?
    /// Fired when a set ends (rest detected after a run of reps). The argument is
    /// the number of reps in the set that just finished.
    var onSetEnded: ((Int) -> Void)?

    // MARK: Internals
    private let sampler = MotionSampler()
    private let detector = RepDetector(sampleRate: 50)
    private var runtimeSession: WKExtendedRuntimeSession?

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
    }

    // MARK: Public actions

    func start() {
        guard phase == .idle || phase == .failed else { return }
        detector.reset()
        reps = 0
        setsLogged = 0
        // Flip to the active UI before any startup work: both the motion sampler
        // and the runtime session can stall on device (especially the first time
        // the motion subsystem spins up after launch), and we never want that
        // between the tap and the first render. Both calls below are non-blocking.
        phase = .counting
        sampler.start()
        startRuntimeSession()
    }

    func pause() {
        guard phase == .counting else { return }
        sampler.stop()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        detector.reset()
        reps = 0
        if runtimeSession?.state != .running {
            startRuntimeSession()
        }
        sampler.start()
        phase = .counting
    }

    func stop() {
        sampler.stop()
        runtimeSession?.invalidate()
        runtimeSession = nil
        phase = .idle
        reps = 0
        detector.reset()
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
            reps += 1
            onRep?()
        case .setEnded(let count):
            // Log the set that just finished, then re-arm for the next one — the
            // detector has already reset its own per-set state.
            setsLogged += 1
            reps = 0
            onSetEnded?(count)
        }
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

extension AutoRepSession: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // No-op: motion sampling is already running.
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // The system is about to reclaim this session. Start a fresh one so the
        // process — and therefore motion sampling — keeps going without a gap.
        guard phase == .counting else { return }
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
            if phase == .counting {
                startRuntimeSession()
            }
        default:
            // .error, .resignedFrontmost, .suppressedBySystem, etc. — the app
            // may now be suspended when the screen sleeps. Surface it.
            if phase == .counting || phase == .paused {
                phase = .failed
            }
        }
    }
}
