import Foundation
import simd
@testable import GymTrackWatch_Watch_App

enum SignalGenerators {

    static let sampleRate: Double = 50.0
    static var dt: Double { 1.0 / sampleRate }

    /// Sine wave on the Z axis of acceleration (vertical, signed).
    static func sine(frequency: Double, amplitude: Double, duration: Double,
                     startTime: TimeInterval = 0) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = startTime + Double(i) * dt
            let v = amplitude * sin(2 * .pi * frequency * t)
            return MotionSample(timestamp: t,
                                accel: SIMD3(0, 0, v),
                                gyro: SIMD3(0, 0, 0))
        }
    }

    /// Sine on the Z axis with amplitude ramping linearly from a0 to a1 across the duration.
    static func sineRamp(frequency: Double, a0: Double, a1: Double, duration: Double) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = Double(i) * dt
            let frac = Double(i) / Double(max(n - 1, 1))
            let amp = a0 + (a1 - a0) * frac
            let v = amp * sin(2 * .pi * frequency * t)
            return MotionSample(timestamp: t, accel: SIMD3(0, 0, v), gyro: SIMD3(0, 0, 0))
        }
    }

    /// Gaussian noise (Box-Muller) on the Z axis of acceleration. Deterministic via seed.
    static func noise(sigma: Double, duration: Double, seed: UInt64 = 42) -> [MotionSample] {
        var rng = SeededRNG(seed: seed)
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = Double(i) * dt
            let u1 = max(rng.nextDouble(), 1e-12)
            let u2 = rng.nextDouble()
            let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
            return MotionSample(timestamp: t, accel: SIMD3(0, 0, sigma * z), gyro: SIMD3(0, 0, 0))
        }
    }

    /// Flat zero signal (used to terminate a set in tests).
    static func silence(duration: Double, startTime: TimeInterval = 0) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            MotionSample(timestamp: startTime + Double(i) * dt,
                         accel: SIMD3(0, 0, 0), gyro: SIMD3(0, 0, 0))
        }
    }

    /// A sequence of `reps` real-style reps: rest → movement → rest. Each rep is a
    /// burst of `cyclesPerRep` cycles of a sine at `moveFrequency` (so the burst
    /// contains the start *and* stop/reversal acceleration spikes of a real rep),
    /// followed by `restDuration` of quiet. A `leadRest` of quiet precedes the
    /// first rep so the detector's warm-up elapses before any movement. Optional
    /// Gaussian noise (`noiseSigma`) is added across the whole stream.
    ///
    /// This is the realistic counterpart to `sine`: counting acceleration peaks
    /// would score ~2× here (one per start spike, one per stop spike), so it is
    /// the signal that exercises episode-based rep detection.
    static func pausedReps(reps: Int,
                           moveFrequency: Double = 2.5,
                           cyclesPerRep: Double = 1.5,
                           amplitude: Double = 0.4,
                           amplitudeEnd: Double? = nil,
                           restDuration: Double = 0.6,
                           leadRest: Double = 0.8,
                           noiseSigma: Double = 0,
                           seed: UInt64 = 42) -> [MotionSample] {
        let moveDuration = cyclesPerRep / moveFrequency
        var rng = SeededRNG(seed: seed)
        var out: [MotionSample] = []

        func noiseSample() -> Double {
            guard noiseSigma > 0 else { return 0 }
            let u1 = max(rng.nextDouble(), 1e-12)
            let u2 = rng.nextDouble()
            let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
            return noiseSigma * z
        }

        func appendSegment(duration: Double, amplitude: Double) {
            let n = Int(duration * sampleRate)
            for i in 0..<n {
                let v = amplitude * sin(2 * .pi * moveFrequency * Double(i) * dt) + noiseSample()
                out.append(MotionSample(timestamp: Double(out.count) * dt,
                                        accel: SIMD3(0, 0, v),
                                        gyro: SIMD3(0, 0, 0)))
            }
        }

        appendSegment(duration: leadRest, amplitude: 0)        // quiet, amplitude 0 = rest
        for r in 0..<reps {
            let frac = reps > 1 ? Double(r) / Double(reps - 1) : 0
            let amp = amplitudeEnd.map { amplitude + ($0 - amplitude) * frac } ?? amplitude
            appendSegment(duration: moveDuration, amplitude: amp)
            appendSegment(duration: restDuration, amplitude: 0)
        }
        return out
    }

    /// Add two sample streams element-wise (assumes equal length).
    static func add(_ a: [MotionSample], _ b: [MotionSample]) -> [MotionSample] {
        precondition(a.count == b.count)
        return zip(a, b).map { (sa, sb) in
            MotionSample(timestamp: sa.timestamp,
                         accel: sa.accel + sb.accel,
                         gyro: sa.gyro + sb.gyro)
        }
    }
}

/// Linear-congruential RNG so tests are deterministic.
struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed | 1 }
    mutating func nextDouble() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
