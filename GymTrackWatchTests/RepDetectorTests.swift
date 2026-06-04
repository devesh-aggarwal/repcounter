import XCTest
import simd
@testable import GymTrackWatch_Watch_App

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

    // MARK: One rep = one episode (no double counting)

    // The core regression: a real rep is rest → move → rest, and the movement
    // burst contains both a start spike and a stop/reversal spike. Counting
    // acceleration peaks would score ~2× (≈20); the episode detector must score
    // one per rep.
    func testStartAndStopCountAsOneRep() {
        let samples = SignalGenerators.pausedReps(reps: 10)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11, "Start and stop of one rep must not both count")
    }

    func testFasterRepsCountedOnce() {
        let samples = SignalGenerators.pausedReps(reps: 10, restDuration: 0.5)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testSlowerRepsCountedOnce() {
        let samples = SignalGenerators.pausedReps(reps: 8, restDuration: 1.6)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 7)
        XCTAssertLessThanOrEqual(reps, 9)
    }

    func testRisingAmplitudeStillCountedOnce() {
        // Each rep's burst grows from 0.1 g to 1.0 g; the adaptive threshold should
        // track it and still count one rep per burst.
        let samples = SignalGenerators.pausedReps(reps: 10, amplitude: 0.1, amplitudeEnd: 1.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testSubtleVibrationReps() {
        // Spec "leg-day vibration" case: faint movement bursts (0.06 g) over light
        // sensor noise (σ=0.01 g), with rest between reps.
        let samples = SignalGenerators.pausedReps(reps: 10, amplitude: 0.06,
                                                   noiseSigma: 0.01)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 8, "Subtle vibration reps should still be detected")
        XCTAssertLessThanOrEqual(reps, 12)
    }

    // MARK: Negative cases

    func testStillWristProducesNoReps() {
        // σ=0.01 g represents accelerometer noise on a wrist held still.
        let samples = SignalGenerators.noise(sigma: 0.01, duration: 10.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertEqual(reps, 0, "A still wrist should not produce any reps")
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

    func testSingleBurstIgnored() {
        // A single isolated movement burst (then stillness) must not count: the
        // counter waits for a sustained rhythm.
        let samples = SignalGenerators.pausedReps(reps: 1)
            + SignalGenerators.silence(duration: 3.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertEqual(reps, 0, "A single isolated rep must not be counted")
    }

    // MARK: Confirmation + set end

    func testCountJumpsToConfirmThreshold() {
        // Reps are buffered until a consistent rhythm is confirmed, then the
        // backlog is flushed at once: the count stays at 0, then jumps to 3.
        let samples = SignalGenerators.pausedReps(reps: 8)
        let detector = RepDetector(sampleRate: 50)
        var repTimes: [TimeInterval] = []
        for s in samples {
            detector.onEvent = { event in
                if case .rep = event { repTimes.append(s.timestamp) }
            }
            detector.process(s)
        }
        XCTAssertGreaterThanOrEqual(repTimes.count, 4, "Expected several reps")
        // The first three reps are flushed together at the lock-on instant.
        XCTAssertEqual(repTimes[0], repTimes[1], "First 3 reps should flush at once")
        XCTAssertEqual(repTimes[1], repTimes[2], "First 3 reps should flush at once")
        // Subsequent reps are counted live, strictly later.
        XCTAssertGreaterThan(repTimes[3], repTimes[2], "4th rep should be counted live, later")
    }

    func testSetEndsAfterMotionStops() {
        // 10 reps, then a long quiet tail. Expect a setEnded event within ~4 s of
        // motion stopping, reporting ~10 reps.
        let active = SignalGenerators.pausedReps(reps: 10)
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
        // The last rep's rest (0.6 s) counts toward the quiet window, so allow a
        // little slack on the lower bound.
        let delay = (setEndDetectedAt ?? 0) - lastT
        XCTAssertLessThan(delay, 5.5, "Set-end should fire within ~4 s of motion stopping (got \(delay)s)")
    }
}
