import Foundation

/// Detects rhythmic reps in a motion sample stream.
///
/// Pipeline: signed vertical (Z) acceleration → band-pass (0.25 Hz HPF + 4 Hz LPF)
/// → adaptive envelope (rolling RMS) → hysteresis peak detection with refractory
/// → rhythm confirmation → rep emission.
///
/// The peak detector finds one peak per oscillation of the band-passed signal.
/// On top of it sits a **rhythm confirmation** stage with two jobs:
///
///  * **Don't count one-off motion.** Peaks are buffered, not emitted, until
///    `confirmReps` consecutive peaks arrive with a consistent tempo. A single
///    bump, or sporadic unrelated motion, never reaches that threshold and is
///    ignored. On lock-on the backlog is flushed at once, so the displayed count
///    jumps straight to N (e.g. 3) and then advances live.
///
///  * **Don't double-count a rep.** A real rep produces a burst when the motion
///    starts and another when it reverses. Requiring a consistent rhythm before
///    counting means the refractory is set from the *true* rep period the moment
///    counting begins, so the secondary within-rep peak is rejected from the very
///    first counted rep rather than only after several reps have elapsed.
final class RepDetector {

    // MARK: Tunables (see spec § Detection algorithm)
    private let sampleRate: Double
    private let envWindowSeconds: Double = 2.0
    private let thresholdK: Double = 0.5
    private let noiseFloor: Double = 0.02
    private let hysteresisFactor: Double = 0.5
    private let initialRefractory: Double = 0.333
    private let refractoryFactor: Double = 0.6
    private let setEndQuietSeconds: Double = 4.0
    private let setEndEnvDropFraction: Double = 0.3
    private let warmupSeconds: Double = 0.5
    private let impactRatio: Double = 5.0
    private let impactWindowSeconds: Double = 0.2
    private let impactSuppressSeconds: Double = 0.3
    private let impactAbsoluteThreshold: Double = 2.0  // g — physical impacts (drops, clinks)

    // Rhythm confirmation: how many consecutive consistent oscillations are
    // required before the counter starts (and how far it jumps on lock-on).
    private let confirmReps: Int = 3
    // Plausible rep period bounds (s). Peaks spaced outside this band are not
    // treated as part of a rep rhythm.
    private let minRepPeriod: Double = 0.3
    private let maxRepPeriod: Double = 4.0
    // Allowed tempo drift between consecutive oscillations when locking on.
    private let periodRatioLo: Double = 0.5
    private let periodRatioHi: Double = 2.0

    // MARK: Filters
    private let hpf: BiquadFilter
    private let lpf: BiquadFilter

    // MARK: State
    private var startTime: TimeInterval?
    private var lastSampleTime: TimeInterval = 0
    private var envSumSq: Double = 0           // running sum of squares for RMS
    private var envBuffer: [Double] = []
    private var envBufferCapacity: Int
    private var peakEnvThisSet: Double = 0
    private var lastRepTime: TimeInterval? = nil
    private var refractory: Double
    private var currentSetReps: Int = 0
    private var lastImpactSuppressUntil: TimeInterval = 0
    private var envHistoryShort: [Double] = [] // for impact detection
    private var envShortCapacity: Int

    // Peak-detection state machine.
    private var inPeak: Bool = false
    private var peakMax: Double = 0
    private var lastCandidateTime: TimeInterval? = nil

    // Rhythm confirmation state.
    private var confirmed: Bool = false
    private var pendingReps: Int = 0           // candidates seen but not yet emitted
    private var consistentStreak: Int = 0
    private var candidateIntervals: [Double] = []

    /// Callback fired for each detector event. Called synchronously inside `process`.
    var onEvent: ((DetectorEvent) -> Void)?

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.hpf = BiquadFilter.highPass(sampleRate: sampleRate, cutoff: 0.25)
        self.lpf = BiquadFilter.lowPass(sampleRate: sampleRate, cutoff: 4.0)
        self.envBufferCapacity = Int(envWindowSeconds * sampleRate)
        self.envShortCapacity = Int(impactWindowSeconds * sampleRate)
        self.refractory = initialRefractory
    }

    func reset() {
        hpf.reset(); lpf.reset()
        startTime = nil
        lastSampleTime = 0
        envSumSq = 0
        envBuffer.removeAll(keepingCapacity: true)
        envHistoryShort.removeAll(keepingCapacity: true)
        peakEnvThisSet = 0
        lastRepTime = nil
        refractory = initialRefractory
        currentSetReps = 0
        lastImpactSuppressUntil = 0
        inPeak = false
        peakMax = 0
        lastCandidateTime = nil
        resetRhythm()
    }

    func process(_ sample: MotionSample) {
        let t = sample.timestamp
        if startTime == nil { startTime = t }
        lastSampleTime = t
        let elapsed = t - (startTime ?? t)

        // 1. Signed vertical-axis acceleration. The watch is assumed to be in a
        //    gravity-aligned frame (see MotionSampler + spec). Using signed Z
        //    preserves cycle direction so the band-pass output peaks once per rep.
        let s = sample.accel.z

        // 2. Band-pass filter (HPF then LPF).
        let hp = hpf.process(s)
        let f = lpf.process(hp)

        // 3. Update rolling RMS envelope.
        envBuffer.append(f * f)
        envSumSq += f * f
        if envBuffer.count > envBufferCapacity {
            envSumSq -= envBuffer.removeFirst()
        }
        let env = sqrt(envSumSq / Double(envBuffer.count))

        // 4. Impact suppression: arm a lockout on either an absolute-spike
        //    (catches drops from silence, where the env-ratio check below
        //    would not fire) or a 5× env jump (catches transitions during
        //    rhythmic motion).
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

        // 5. Warmup gate: feed filters but emit no reps in first 0.5 s.
        guard elapsed >= warmupSeconds else { return }

        // 6. Refractory + impact-suppression gates. Refractory spacing is keyed
        //    off the last *candidate* (not the last emitted rep) so that peaks are
        //    spaced correctly even before the rhythm has been confirmed.
        let refractoryOK: Bool = {
            guard let last = lastCandidateTime else { return true }
            return (t - last) >= refractory
        }()
        let impactOK = t >= lastImpactSuppressUntil

        // 7. Peak detection state machine with hysteresis.
        let threshold = max(noiseFloor, thresholdK * env)
        if !inPeak {
            if f > threshold && refractoryOK && impactOK {
                inPeak = true
                peakMax = f
            }
        } else {
            peakMax = max(peakMax, f)
            if f < threshold * hysteresisFactor {
                // Oscillation complete — hand it to the rhythm tracker.
                inPeak = false
                handleCandidate(at: t)
            }
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
                refractory = initialRefractory
                lastRepTime = nil
                lastCandidateTime = nil
                inPeak = false
                resetRhythm()
            }
        }
    }

    /// Feed one completed oscillation into the rhythm tracker. Emits reps only
    /// once a consistent rhythm of `confirmReps` oscillations has been seen.
    private func handleCandidate(at t: TimeInterval) {
        let interval = lastCandidateTime.map { t - $0 }
        lastCandidateTime = t

        // Once locked on, every oscillation that cleared the refractory gate is a
        // rep. The refractory (set from the observed rhythm at lock-on) already
        // rejects the secondary within-rep peak, so no further test is needed.
        if confirmed {
            emit(at: t)
            return
        }

        // Not yet locked on: decide whether this oscillation continues a rhythm.
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
                // Tempo broke — restart the streak from this oscillation.
                restartRhythm()
            }
        } else {
            // First oscillation, or an implausibly spaced one: start fresh.
            restartRhythm()
        }

        if consistentStreak >= confirmReps {
            // Lock on: derive the refractory from the observed rhythm so the
            // secondary within-rep peak is rejected from here on, then flush the
            // backlog so the displayed count jumps straight to N.
            confirmed = true
            if let med = medianInterval(candidateIntervals) {
                refractory = max(0.1, refractoryFactor * med)
            }
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

    private func medianInterval(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
