import Foundation
import simd
@testable import RepCounter_Watch_App

enum SignalGenerators {

    static let sampleRate: Double = 50.0
    static var dt: Double { 1.0 / sampleRate }

    /// Sine wave on the X axis of acceleration, zero gyro.
    static func sine(frequency: Double, amplitude: Double, duration: Double,
                     startTime: TimeInterval = 0) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = startTime + Double(i) * dt
            let v = amplitude * sin(2 * .pi * frequency * t)
            return MotionSample(timestamp: t,
                                accel: SIMD3(v, 0, 0),
                                gyro: SIMD3(0, 0, 0))
        }
    }

    /// Sine with amplitude ramping linearly from a0 to a1 across the duration.
    static func sineRamp(frequency: Double, a0: Double, a1: Double, duration: Double) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = Double(i) * dt
            let frac = Double(i) / Double(max(n - 1, 1))
            let amp = a0 + (a1 - a0) * frac
            let v = amp * sin(2 * .pi * frequency * t)
            return MotionSample(timestamp: t, accel: SIMD3(v, 0, 0), gyro: SIMD3(0, 0, 0))
        }
    }

    /// Gaussian noise (Box-Muller). Deterministic via seed.
    static func noise(sigma: Double, duration: Double, seed: UInt64 = 42) -> [MotionSample] {
        var rng = SeededRNG(seed: seed)
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = Double(i) * dt
            let u1 = max(rng.nextDouble(), 1e-12)
            let u2 = rng.nextDouble()
            let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
            return MotionSample(timestamp: t, accel: SIMD3(sigma * z, 0, 0), gyro: SIMD3(0, 0, 0))
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
