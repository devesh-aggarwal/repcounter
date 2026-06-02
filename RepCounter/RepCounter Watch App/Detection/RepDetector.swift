import Foundation

/// Detects rhythmic reps in a motion sample stream.
///
/// Pipeline: signed vertical (Z) acceleration → band-pass (0.25 Hz HPF + 4 Hz LPF)
/// → two RMS envelopes (slow for set-end, fast for movement) → episode detection
/// → rhythm confirmation → rep emission.
///
/// **One rep = one movement episode.** A real rep is a burst of motion bounded by
/// rest: the wrist goes rest → movement → rest. That burst contains *two*
/// acceleration spikes — one when the limb starts moving and one when it stops or
/// reverses — so counting individual acceleration peaks double-counts every rep
/// (the bug this design fixes). Instead we track a fast "movement energy"
/// envelope and count a rep on the **onset** of each movement episode
/// (rest → movement). The stop spike, and any jitter inside the rep, fall inside
/// the same episode and are ignored; the detector re-arms only once the envelope
/// falls back to rest, so the next onset is the next rep.
///
/// The active/rest thresholds are a fraction of a slowly-decaying estimate of
/// recent movement energy, so the detector self-scales between a big arm curl and
/// the faint body vibration of a squat without per-exercise tuning.
///
/// On top of the episode detector sits a **rhythm confirmation** stage: episodes
/// are buffered, not emitted, until `confirmReps` of them arrive with a consistent
/// tempo. A single burst or sporadic unrelated motion never reaches that threshold
/// and is ignored. On lock-on the backlog is flushed at once, so the displayed
/// count jumps straight to N (e.g. 3) and then advances live, one per episode.
final class RepDetector {

    // MARK: Tunables (see spec § Detection algorithm)
    private let sampleRate: Double
    private let envWindowSeconds: Double = 2.0      // slow RMS, for set-end detection
    private let fastWindowSeconds: Double = 0.4     // fast RMS, for movement/rest
    private let noiseFloor: Double = 0.02           // absolute floor for the active threshold
    // Movement episode hysteresis, as fractions of the recent-movement-energy
    // reference: cross above `active` → rep onset; fall below `rest` → re-arm.
    // `rest` sits comfortably above the band-pass filter's ring-down floor after a
    // movement (~0.2·ref) so a normal between-rep pause clears it, yet well below
    // the in-movement level (~ref) so a mid-rep lull never reads as rest.
    private let movementActiveFrac: Double = 0.50
    private let movementRestFrac: Double = 0.30
    private let refHalfLifeSeconds: Double = 4.0    // decay of the movement-energy reference
    // Minimum spacing between episode onsets — a coarse guard against a single
    // noise blip re-triggering immediately after rest. The hysteresis does the
    // real work; this is just a floor.
    private let minEpisodeSpacing: Double = 0.25
    private let setEndQuietSeconds: Double = 4.0
    private let setEndEnvDropFraction: Double = 0.3
    private let warmupSeconds: Double = 0.5
    private let impactRatio: Double = 5.0
    private let impactWindowSeconds: Double = 0.2
    private let impactSuppressSeconds: Double = 0.3
    private let impactAbsoluteThreshold: Double = 2.0  // g — physical impacts (drops, clinks)

    // Rhythm confirmation: how many consecutive consistent episodes are required
    // before the counter starts (and how far it jumps on lock-on).
    private let confirmReps: Int = 3
    // Plausible rep period bounds (s). Episodes spaced outside this band are not
    // treated as part of a rep rhythm.
    private let minRepPeriod: Double = 0.3
    private let maxRepPeriod: Double = 4.0
    // Allowed tempo drift between consecutive episodes when locking on.
    private let periodRatioLo: Double = 0.5
    private let periodRatioHi: Double = 2.0

    // MARK: Filters
    private let hpf: BiquadFilter
    private let lpf: BiquadFilter

    // MARK: State
    private var startTime: TimeInterval?
    private var lastSampleTime: TimeInterval = 0
    private var envSumSq: Double = 0           // running sum of squares for slow RMS
    private var envBuffer: [Double] = []
    private var envBufferCapacity: Int
    private var fastSumSq: Double = 0          // running sum of squares for fast RMS
    private var fastBuffer: [Double] = []
    private var fastBufferCapacity: Int
    private var movementRef: Double = 0        // decaying estimate of recent movement energy
    private let refDecayPerSample: Double
    private var peakEnvThisSet: Double = 0
    private var lastRepTime: TimeInterval? = nil
    private var currentSetReps: Int = 0
    private var lastImpactSuppressUntil: TimeInterval = 0
    private var envHistoryShort: [Double] = [] // for impact detection
    private var envShortCapacity: Int

    // Episode (movement vs rest) state.
    private var inMovement: Bool = false
    private var lastCandidateTime: TimeInterval? = nil   // last episode onset

    // Rhythm confirmation state.
    private var confirmed: Bool = false
    private var pendingReps: Int = 0           // episodes seen but not yet emitted
    private var consistentStreak: Int = 0
    private var candidateIntervals: [Double] = []

    /// Callback fired for each detector event. Called synchronously inside `process`.
    var onEvent: ((DetectorEvent) -> Void)?

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.hpf = BiquadFilter.highPass(sampleRate: sampleRate, cutoff: 0.25)
        self.lpf = BiquadFilter.lowPass(sampleRate: sampleRate, cutoff: 4.0)
        self.envBufferCapacity = Int(envWindowSeconds * sampleRate)
        self.fastBufferCapacity = max(1, Int(fastWindowSeconds * sampleRate))
        self.envShortCapacity = Int(impactWindowSeconds * sampleRate)
        self.refDecayPerSample = pow(0.5, (1.0 / sampleRate) / refHalfLifeSeconds)
    }

    func reset() {
        hpf.reset(); lpf.reset()
        startTime = nil
        lastSampleTime = 0
        envSumSq = 0
        envBuffer.removeAll(keepingCapacity: true)
        fastSumSq = 0
        fastBuffer.removeAll(keepingCapacity: true)
        movementRef = 0
        envHistoryShort.removeAll(keepingCapacity: true)
        peakEnvThisSet = 0
        lastRepTime = nil
        currentSetReps = 0
        lastImpactSuppressUntil = 0
        inMovement = false
        lastCandidateTime = nil
        resetRhythm()
    }

    func process(_ sample: MotionSample) {
        let t = sample.timestamp
        if startTime == nil { startTime = t }
        lastSampleTime = t
        let elapsed = t - (startTime ?? t)

        // 1. Signed vertical-axis acceleration. The watch is assumed to be in a
        //    gravity-aligned frame (see MotionSampler + spec).
        let s = sample.accel.z

        // 2. Band-pass filter (HPF then LPF).
        let hp = hpf.process(s)
        let f = lpf.process(hp)

        // 3. Slow rolling RMS envelope (set-end detection).
        envBuffer.append(f * f)
        envSumSq += f * f
        if envBuffer.count > envBufferCapacity {
            envSumSq -= envBuffer.removeFirst()
        }
        let env = sqrt(envSumSq / Double(envBuffer.count))

        // 4. Fast rolling RMS envelope (movement vs rest). Short enough to see the
        //    quiet gaps between reps, long enough that the acceleration dip in the
        //    middle of a single rep's movement doesn't read as rest.
        fastBuffer.append(f * f)
        fastSumSq += f * f
        if fastBuffer.count > fastBufferCapacity {
            fastSumSq -= fastBuffer.removeFirst()
        }
        let fastEnv = sqrt(fastSumSq / Double(fastBuffer.count))

        // 5. Decaying estimate of recent movement energy. Thresholds are a
        //    fraction of this, so they track the amplitude of whatever lift is in
        //    progress (large for arm work, small for leg-vibration).
        movementRef = max(fastEnv, movementRef * refDecayPerSample)
        let activeThreshold = max(noiseFloor, movementActiveFrac * movementRef)
        let restThreshold = max(noiseFloor * 0.6, movementRestFrac * movementRef)

        // 6. Impact suppression: arm a lockout on either an absolute spike (drops,
        //    clinks) or a 5× slow-env jump (sharp transients during motion).
        if abs(sample.accel.z) >= impactAbsoluteThreshold {
            lastImpactSuppressUntil = t + impactSuppressSeconds
        }
        envHistoryShort.append(env)
        if envHistoryShort.count > envShortCapacity {
            envHistoryShort.removeFirst()
        }
        if let oldEnv = envHistoryShort.first,
           oldEnv > 1e-6,
           env / oldEnv >= impactRatio {
            lastImpactSuppressUntil = t + impactSuppressSeconds
        }
        let impactOK = t >= lastImpactSuppressUntil

        // 7. Episode state machine. The onset of a movement episode is the rep
        //    event; the rep is then "consumed" until the wrist returns to rest, so
        //    the stop spike and any within-rep jitter never start a second rep.
        //    Transitions are tracked even during warm-up (so a movement already in
        //    progress when warm-up ends isn't mistaken for a fresh onset), but a
        //    rep is only emitted once warm-up has elapsed.
        let refractoryOK = lastCandidateTime.map { (t - $0) >= minEpisodeSpacing } ?? true
        if !inMovement {
            if fastEnv > activeThreshold && impactOK {
                inMovement = true
                if elapsed >= warmupSeconds && refractoryOK {
                    handleCandidate(at: t)
                }
            }
        } else if fastEnv < restThreshold {
            inMovement = false
        }

        // 8. Set-end detection.
        peakEnvThisSet = max(peakEnvThisSet, env)
        if currentSetReps > 0 {
            let envDropped = env < peakEnvThisSet * setEndEnvDropFraction
            let quiet = (lastRepTime.map { (t - $0) >= setEndQuietSeconds } ?? false)
            if envDropped && quiet {
                onEvent?(.setEnded(count: currentSetReps))
                currentSetReps = 0
                peakEnvThisSet = 0
                lastRepTime = nil
                lastCandidateTime = nil
                inMovement = false
                resetRhythm()
            }
        }
    }

    /// Feed one movement-episode onset into the rhythm tracker. Emits reps only
    /// once a consistent rhythm of `confirmReps` episodes has been seen.
    private func handleCandidate(at t: TimeInterval) {
        let interval = lastCandidateTime.map { t - $0 }
        lastCandidateTime = t

        // Once locked on, every episode onset is a rep: the episode logic has
        // already collapsed each rep's start/stop spikes into a single onset, so
        // there is nothing left to double-count.
        if confirmed {
            emit(at: t)
            return
        }

        // Not yet locked on: decide whether this episode continues a rhythm.
        let plausible = interval.map { $0 >= minRepPeriod && $0 <= maxRepPeriod } ?? false
        if let iv = interval, plausible {
            let consistent: Bool = {
                guard let last = candidateIntervals.last else { return true }
                let r = iv / last
                return r >= periodRatioLo && r <= periodRatioHi
            }()
            if consistent {
                consistentStreak += 1
                pendingReps += 1
                candidateIntervals.append(iv)
            } else {
                // Tempo broke — restart the streak from this episode.
                restartRhythm()
            }
        } else {
            // First episode, or an implausibly spaced one: start fresh.
            restartRhythm()
        }

        if consistentStreak >= confirmReps {
            // Lock on and flush the backlog so the displayed count jumps to N.
            confirmed = true
            let backlog = pendingReps
            pendingReps = 0
            for _ in 0..<backlog { emit(at: t) }
        }
    }

    private func emit(at t: TimeInterval) {
        currentSetReps += 1
        lastRepTime = t
        onEvent?(.rep)
    }

    private func restartRhythm() {
        consistentStreak = 1
        pendingReps = 1
        candidateIntervals.removeAll(keepingCapacity: true)
    }

    private func resetRhythm() {
        confirmed = false
        consistentStreak = 0
        pendingReps = 0
        candidateIntervals.removeAll(keepingCapacity: true)
    }
}
