import Foundation

/// Detects rhythmic reps in a motion sample stream.
/// Algorithm: signed vertical (Z) acceleration → band-pass (0.25 Hz HPF + 4 Hz LPF)
/// → adaptive envelope (rolling RMS) → hysteresis peak detection with refractory.
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
    private var inPeak: Bool = false
    private var peakMax: Double = 0
    private var currentSetReps: Int = 0
    private var lastImpactSuppressUntil: TimeInterval = 0
    private var envHistoryShort: [Double] = [] // for impact detection
    private var envShortCapacity: Int

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
        inPeak = false
        peakMax = 0
        currentSetReps = 0
        lastImpactSuppressUntil = 0
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

        // 6. Refractory + impact-suppression gates.
        let refractoryOK: Bool = {
            guard let last = lastRepTime else { return true }
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
                // Emit rep at descent through hysteresis.
                inPeak = false
                emitRep(at: t, env: env)
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
            }
        }
    }

    private func emitRep(at t: TimeInterval, env: Double) {
        // Track period for adaptive refractory.
        if let last = lastRepTime {
            let period = t - last
            currentSetReps += 1
            // After 3 reps, lock refractory to 0.6 × observed period.
            if currentSetReps >= 3 {
                refractory = max(0.1, refractoryFactor * period)
            }
        } else {
            currentSetReps += 1
        }
        lastRepTime = t
        onEvent?(.rep)
    }
}
