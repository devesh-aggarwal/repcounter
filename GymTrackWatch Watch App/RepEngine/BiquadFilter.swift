import Foundation

/// Direct-Form II Transposed biquad IIR filter.
/// Coefficients derived using RBJ Audio EQ Cookbook formulas (Q = 1/sqrt(2)).
final class BiquadFilter {
    private let b0, b1, b2, a1, a2: Double
    private var z1: Double = 0
    private var z2: Double = 0

    private init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    func reset() { z1 = 0; z2 = 0 }

    static func lowPass(sampleRate: Double, cutoff: Double) -> BiquadFilter {
        let q = 1.0 / sqrt(2.0)
        let w0 = 2.0 * .pi * cutoff / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        let b0 = (1.0 - cosw0) / 2.0 / a0
        let b1 = (1.0 - cosw0) / a0
        let b2 = (1.0 - cosw0) / 2.0 / a0
        let a1 = -2.0 * cosw0 / a0
        let a2 = (1.0 - alpha) / a0
        return BiquadFilter(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    static func highPass(sampleRate: Double, cutoff: Double) -> BiquadFilter {
        let q = 1.0 / sqrt(2.0)
        let w0 = 2.0 * .pi * cutoff / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        let b0 = (1.0 + cosw0) / 2.0 / a0
        let b1 = -(1.0 + cosw0) / a0
        let b2 = (1.0 + cosw0) / 2.0 / a0
        let a1 = -2.0 * cosw0 / a0
        let a2 = (1.0 - alpha) / a0
        return BiquadFilter(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
}
