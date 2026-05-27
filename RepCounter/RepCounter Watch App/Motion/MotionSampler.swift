import Foundation
import CoreMotion
import simd

/// Streams CoreMotion device-motion samples at 50 Hz to a callback.
/// Uses the `.xArbitraryZVertical` reference frame so the z-axis is roughly
/// vertical; this lets RepDetector use `sample.accel.z` as its signed signal.
final class MotionSampler {

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    /// Called on `queue` for each sample.
    var onSample: ((MotionSample) -> Void)?

    init() {
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        queue.name = "RepCounter.MotionSampler"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let sample = MotionSample(
                timestamp: motion.timestamp,
                accel: SIMD3(motion.userAcceleration.x,
                             motion.userAcceleration.y,
                             motion.userAcceleration.z),
                gyro: SIMD3(motion.rotationRate.x,
                            motion.rotationRate.y,
                            motion.rotationRate.z)
            )
            self.onSample?(sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
