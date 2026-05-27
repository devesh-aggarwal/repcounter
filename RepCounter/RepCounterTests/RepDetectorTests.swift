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
}
