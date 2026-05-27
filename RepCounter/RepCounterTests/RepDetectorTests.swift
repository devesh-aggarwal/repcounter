import XCTest
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
}
