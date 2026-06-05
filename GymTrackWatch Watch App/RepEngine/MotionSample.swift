import Foundation
import simd

/// A single 50 Hz motion measurement.
/// - timestamp: seconds since some monotonic reference (e.g. `Date().timeIntervalSince1970`).
/// - accel: linear acceleration (g), gravity removed.
/// - gyro: rotation rate (rad/s).
struct MotionSample {
    let timestamp: TimeInterval
    let accel: SIMD3<Double>
    let gyro: SIMD3<Double>
}
