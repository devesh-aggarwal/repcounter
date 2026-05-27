import XCTest
import simd
@testable import RepCounter_Watch_App

final class RepDetectorTests: XCTestCase {

    private func runDetector(on samples: [MotionSample]) -> [DetectorEvent] {
        let detector = RepDetector(sampleRate: 50)
        var events: [DetectorEvent] = []
        detector.onEvent = { events.append($0) }
        for s in samples { detector.process(s) }
        return events
    }

    private func repCount(_ events: [DetectorEvent]) -> Int {
        events.filter { if case .rep = $0 { return true } else { return false } }.count
    }

    // 10 cycles of clean 1 Hz sine at amp 0.5 g → expect ~10 reps.
    func testCleanSine1Hz() {
        let samples = SignalGenerators.sine(frequency: 1.0, amplitude: 0.5, duration: 10.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testCleanSine05Hz() {
        let samples = SignalGenerators.sine(frequency: 0.5, amplitude: 0.5, duration: 20.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testCleanSine2Hz() {
        let samples = SignalGenerators.sine(frequency: 2.0, amplitude: 0.5, duration: 5.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testStillWristProducesNoReps() {
        // σ=0.01 g represents accelerometer noise on a wrist held still.
        // (High-amplitude ambient motion rejection is covered by the on-device
        // walking-around check in the manual test plan, not here.)
        let samples = SignalGenerators.noise(sigma: 0.01, duration: 10.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertEqual(reps, 0, "A still wrist should not produce any reps")
    }

    func testSubtleVibrationOnNoise() {
        // Spec "leg-day vibration" case: 0.7 Hz sine, amp 0.05 g, on top of σ=0.02 g noise.
        let sine = SignalGenerators.sine(frequency: 0.7, amplitude: 0.05, duration: 14.0) // ~10 cycles
        let noise = SignalGenerators.noise(sigma: 0.02, duration: 14.0)
        let mixed = SignalGenerators.add(sine, noise)
        let reps = repCount(runDetector(on: mixed))
        XCTAssertGreaterThanOrEqual(reps, 8, "Subtle vibration should still be detected")
        XCTAssertLessThanOrEqual(reps, 12)
    }

    func testRisingAmplitudeStillCounted() {
        // 1 Hz sine, amplitude ramps 0.1 g → 1.0 g over 10 cycles.
        let samples = SignalGenerators.sineRamp(frequency: 1.0, a0: 0.1, a1: 1.0, duration: 10.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testSetEndsAfterMotionStops() {
        // 1 Hz sine for 10 s, then 6 s of silence. Expect a setEnded event within ~4 s of motion stopping.
        let active = SignalGenerators.sine(frequency: 1.0, amplitude: 0.5, duration: 10.0)
        let lastT = active.last!.timestamp
        let quiet = SignalGenerators.silence(duration: 6.0, startTime: lastT + SignalGenerators.dt)
        let samples = active + quiet

        let detector = RepDetector(sampleRate: 50)
        var setEndDetectedAt: TimeInterval? = nil
        var setEndCount: Int? = nil
        for s in samples {
            detector.onEvent = { event in
                if case .setEnded(let c) = event, setEndCount == nil {
                    setEndCount = c
                }
            }
            detector.process(s)
            if setEndCount != nil && setEndDetectedAt == nil {
                setEndDetectedAt = s.timestamp
            }
        }

        XCTAssertNotNil(setEndDetectedAt, "Expected a setEnded event after motion stopped")
        XCTAssertGreaterThanOrEqual(setEndCount ?? 0, 9)
        XCTAssertLessThanOrEqual(setEndCount ?? 0, 11)
        let delay = (setEndDetectedAt ?? 0) - lastT
        XCTAssertGreaterThan(delay, 3.5, "Set-end should not fire too eagerly (got \(delay)s)")
        XCTAssertLessThan(delay, 5.5, "Set-end should fire within ~4 s of motion stopping (got \(delay)s)")
    }

    func testSingleImpactSpikeIgnored() {
        // Flat zero for 5 s with one 3 g spike at t=2 s on the vertical axis.
        var samples = SignalGenerators.silence(duration: 5.0)
        let spikeIdx = Int(2.0 * SignalGenerators.sampleRate)
        samples[spikeIdx] = MotionSample(
            timestamp: samples[spikeIdx].timestamp,
            accel: SIMD3(0, 0, 3.0),
            gyro: SIMD3(0, 0, 0)
        )
        let reps = repCount(runDetector(on: samples))
        XCTAssertEqual(reps, 0, "A single impact spike must not be counted")
    }

    func testRefractoryPreventsDoubleCount() {
        // 1 Hz primary sine on accel.z with a small secondary bump 100 ms after each peak.
        // Combine 1 Hz at 0.5 g amplitude with 1 Hz at 0.2 g phase-shifted by -100 ms (= -0.628 rad).
        let n = Int(10.0 * SignalGenerators.sampleRate)
        let samples: [MotionSample] = (0..<n).map { i in
            let t = Double(i) * SignalGenerators.dt
            let v = 0.5 * sin(2 * .pi * 1.0 * t)
                  + 0.2 * sin(2 * .pi * 1.0 * t - 0.628)
            return MotionSample(timestamp: t, accel: SIMD3(0, 0, v), gyro: SIMD3(0, 0, 0))
        }
        let reps = repCount(runDetector(on: samples))
        // ~10 cycles in 10s, expect 9–11 — not 18–20.
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }
}
