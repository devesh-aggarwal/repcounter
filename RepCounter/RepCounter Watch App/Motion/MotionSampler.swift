import Foundation
import CoreMotion
import simd

/// Streams CoreMotion device-motion samples at 50 Hz to a callback.
/// Uses the `.xArbitraryZVertical` reference frame so the z-axis is roughly
/// vertical; this lets RepDetector use `sample.accel.z` as its signed signal.
final class MotionSampler {

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    /// Serializes start/stop so the (potentially blocking) CoreMotion calls
    /// never touch the main thread, while still preserving their ordering.
    private let controlQueue = DispatchQueue(label: "RepCounter.MotionSampler.control")

    /// Called on `queue` for each sample.
    var onSample: ((MotionSample) -> Void)?

    init() {
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        queue.name = "RepCounter.MotionSampler"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        // `startDeviceMotionUpdates` can block its caller for a second or more
        // the first time the device-motion subsystem spins up after launch.
        // Calling it on the main thread freezes the UI right after the user taps
        // Start, so run it on a private serial queue. Samples are still delivered
        // to `queue`, and serializing with stop() keeps start/stop in order.
        controlQueue.async { [weak self] in
            guard let self, self.manager.isDeviceMotionAvailable else { return }
            self.manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: self.queue) { [weak self] motion, _ in
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
    }

    func stop() {
        controlQueue.async { [weak self] in
            self?.manager.stopDeviceMotionUpdates()
        }
    }
}
