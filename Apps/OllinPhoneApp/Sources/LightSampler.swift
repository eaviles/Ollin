import Foundation
import ARKit
import simd

/// Reads the room's light off an ARKit frame and turns it into a `PhoneLightSample`.
///
/// Every mode gets one of these, because every ARKit session estimates the light and
/// a sketch wants it whatever the phone is pointed at. A camera frame arrives sixty
/// times a second and the light in a room does not change nearly that fast, so this
/// sends a few times a second instead.
///
/// A world-facing session reports brightness and warmth. A face session reports an
/// `ARDirectionalLightEstimate` as well, which adds where the light comes from and
/// the spherical-harmonic description of it, because a face is a shape ARKit knows
/// well enough to read the shading on.
final class LightSampler {

    /// Fired (on the main thread) each time a reading is due.
    var onLight: ((PhoneLightSample) -> Void)?

    /// How often a reading goes out, in seconds.
    private let interval: TimeInterval = 0.2

    private var lastSent: TimeInterval = -.greatestFiniteMagnitude

    /// Report this frame's light, if one is due.
    func report(_ frame: ARFrame) {
        guard let estimate = frame.lightEstimate else { return }
        guard frame.timestamp - lastSent >= interval else { return }
        lastSent = frame.timestamp

        var sample = PhoneLightSample(timestamp: frame.timestamp,
                                      ambientIntensity: Float(estimate.ambientIntensity),
                                      colorTemperature: Float(estimate.ambientColorTemperature))

        if let directional = estimate as? ARDirectionalLightEstimate {
            let d = directional.primaryLightDirection
            sample.hasDirection = true
            sample.direction = SIMD3<Float>(d.x, d.y, d.z)
            sample.directionalIntensity = Float(directional.primaryLightIntensity)
            sample.sphericalHarmonics = Self.floats(directional.sphericalHarmonicsCoefficients)
        }

        onLight?(sample)
    }

    /// ARKit hands the coefficients over as raw bytes (27 floats, nine per color
    /// channel), so they are read back out as floats.
    private static func floats(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        out.withUnsafeMutableBytes { raw in
            _ = data.copyBytes(to: raw, count: count * MemoryLayout<Float>.size)
        }
        return out
    }
}

/// A streamer that reads the room's light beside whatever else it is capturing. The
/// app wires them all to the same handler, so the light keeps arriving through a
/// mode switch.
protocol LightReporting: AnyObject {
    var lightSampler: LightSampler { get }
}
