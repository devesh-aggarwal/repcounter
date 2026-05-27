import XCTest
import simd
@testable import RepCounter_Watch_App

/// Replays recorded traces through RepDetector and checks set rep counts against ground truth.
/// Each trace JSON file has the form:
///   { "expected_reps": [N1, N2, ...], "samples": [[t, ax, ay, az, gx, gy, gz], ...] }
/// Test skips when no traces are present so CI passes on a fresh checkout.
final class TraceReplayTests: XCTestCase {

    struct TraceFile: Decodable {
        let expected_reps: [Int]
        let samples: [[Double]]
    }

    private func traceURLs() -> [URL] {
        let bundle = Bundle(for: TraceReplayTests.self)
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "traces") else {
            return []
        }
        return urls
    }

    func testAllRecordedTraces() throws {
        let urls = traceURLs()
        try XCTSkipIf(urls.isEmpty,
                      "No recorded traces present — add JSON files to RepCounterTests/traces/")
        for url in urls {
            let data = try Data(contentsOf: url)
            let trace = try JSONDecoder().decode(TraceFile.self, from: data)
            let detector = RepDetector(sampleRate: 50)
            var setCounts: [Int] = []
            detector.onEvent = { event in
                if case .setEnded(let c) = event { setCounts.append(c) }
            }
            for row in trace.samples {
                let sample = MotionSample(
                    timestamp: row[0],
                    accel: SIMD3(row[1], row[2], row[3]),
                    gyro: SIMD3(row[4], row[5], row[6])
                )
                detector.process(sample)
            }
            XCTAssertEqual(setCounts.count, trace.expected_reps.count,
                "Trace \(url.lastPathComponent): wrong number of sets detected")
            for (i, (got, want)) in zip(setCounts, trace.expected_reps).enumerated() {
                XCTAssertLessThanOrEqual(abs(got - want), 1,
                    "Trace \(url.lastPathComponent) set \(i+1): expected \(want), got \(got)")
            }
        }
    }
}
