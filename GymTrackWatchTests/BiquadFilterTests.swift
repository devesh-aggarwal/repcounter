import XCTest
@testable import GymTrackWatch_Watch_App

final class BiquadFilterTests: XCTestCase {

    func testLowPassAttenuatesHighFrequency() {
        // 50 Hz sample rate, low-pass cutoff at 4 Hz.
        let lpf = BiquadFilter.lowPass(sampleRate: 50, cutoff: 4)
        // Drive with 20 Hz sine for 2 s (well above cutoff).
        var maxAmp = 0.0
        for i in 0..<100 {
            let t = Double(i) / 50.0
            let x = sin(2 * .pi * 20 * t)
            let y = lpf.process(x)
            if i > 25 { maxAmp = max(maxAmp, abs(y)) } // skip transient
        }
        XCTAssertLessThan(maxAmp, 0.2, "20 Hz should be heavily attenuated by 4 Hz LPF")
    }

    func testLowPassPassesLowFrequency() {
        let lpf = BiquadFilter.lowPass(sampleRate: 50, cutoff: 4)
        // Drive with 1 Hz sine — well below cutoff.
        var maxAmp = 0.0
        for i in 0..<250 {
            let t = Double(i) / 50.0
            let x = sin(2 * .pi * 1 * t)
            let y = lpf.process(x)
            if i > 50 { maxAmp = max(maxAmp, abs(y)) }
        }
        XCTAssertGreaterThan(maxAmp, 0.8, "1 Hz should pass nearly unchanged through 4 Hz LPF")
    }

    func testHighPassAttenuatesDC() {
        let hpf = BiquadFilter.highPass(sampleRate: 50, cutoff: 0.25)
        // Drive with constant 1.0 (DC) for 10 s.
        var maxAmp = 0.0
        for i in 0..<500 {
            let y = hpf.process(1.0)
            if i > 250 { maxAmp = max(maxAmp, abs(y)) }
        }
        XCTAssertLessThan(maxAmp, 0.01, "DC should be removed by HPF")
    }

    func testHighPassPassesMidBand() {
        let hpf = BiquadFilter.highPass(sampleRate: 50, cutoff: 0.25)
        var maxAmp = 0.0
        for i in 0..<500 {
            let t = Double(i) / 50.0
            let x = sin(2 * .pi * 1 * t)
            let y = hpf.process(x)
            if i > 250 { maxAmp = max(maxAmp, abs(y)) }
        }
        XCTAssertGreaterThan(maxAmp, 0.8, "1 Hz should pass nearly unchanged through 0.25 Hz HPF")
    }
}
