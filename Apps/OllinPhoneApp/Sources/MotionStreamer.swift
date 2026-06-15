import Foundation
import CoreMotion
import simd

/// Streams CoreMotion device motion at ~30 Hz — the cheap transport smoke-test:
/// attitude, gravity, rotation rate, and user acceleration. The moment the wire is
/// alive these numbers move on the Mac, before ARKit has even found a body.
///
/// Updates are delivered on the main queue, so `onSample` fires on main.
final class MotionStreamer {

    /// Fired (on the main thread) for each device-motion sample.
    var onSample: ((PhoneMotionSample) -> Void)?

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let q = m.attitude.quaternion, g = m.gravity, r = m.rotationRate, a = m.userAcceleration
            let sample = PhoneMotionSample(
                attitude: SIMD4<Float>(Float(q.x), Float(q.y), Float(q.z), Float(q.w)),
                gravity: SIMD3<Float>(Float(g.x), Float(g.y), Float(g.z)),
                rotationRate: SIMD3<Float>(Float(r.x), Float(r.y), Float(r.z)),
                userAcceleration: SIMD3<Float>(Float(a.x), Float(a.y), Float(a.z)),
                timestamp: m.timestamp)
            self.onSample?(sample)
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
