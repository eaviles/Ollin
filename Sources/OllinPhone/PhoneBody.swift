import Ollin

/// One person's pose streamed from the phone's ARKit body tracker: every joint a
/// 3D position in **meters**, model space — the pelvis root at the origin, x to the
/// picture's right, y up, z toward the camera (ARKit's convention).
///
/// Where `Body3D` (OllinVision) *estimates* a skeleton from a single Mac webcam,
/// this is the phone's on-device ARKit skeleton arriving over the wire — the same
/// model-space accessor shape, drawn the same way (3D mode has no line primitive
/// yet, so the skeleton draws as a `PointCloud`, exactly like `LiftedPose.cloud`).
///
/// ```swift
/// if let body = device.latestBody {
///     camera(.orbiting(target: body.center, radius: 2.5, azimuth: time * 0.3))
///     drawPointCloud(body.cloud())
/// }
/// ```
public struct PhoneBody: Sendable {

    /// Whether ARKit currently has tracking on this person (vs. extrapolating from
    /// the last good frame).
    public let isTracked: Bool

    /// The capture timestamp of the frame, in the phone's clock (seconds).
    public let timestamp: Double

    let joints: [PhoneJoint: Vector3]

    /// Wrap a decoded wire sample, mapping its `SIMD3<Float>` joints into `Vector3`.
    init(_ sample: PhonePoseSample) {
        isTracked = sample.tracked
        timestamp = sample.timestamp
        joints = sample.joints.mapValues { Vector3(Double($0.x), Double($0.y), Double($0.z)) }
    }

    /// Whether a joint was reported in this frame.
    public func has(_ joint: PhoneJoint) -> Bool { joints[joint] != nil }

    /// One joint's position in model space (meters, root at the origin), or `nil`
    /// if it wasn't reported.
    public func position(_ joint: PhoneJoint) -> Vector3? { joints[joint] }

    /// Every reported joint's position in model space.
    public var positions: [PhoneJoint: Vector3] { joints }

    /// The skeleton as 3D segments in model space, for the bones whose both ends
    /// were reported — project them however you like to draw the figure from any
    /// angle.
    public func bones() -> [(Vector3, Vector3)] {
        PhoneBody.skeleton.compactMap { bone in
            guard let a = joints[bone.0], let b = joints[bone.1] else { return nil }
            return (a, b)
        }
    }

    /// The centroid of the reported joints — a steady point to aim an orbiting
    /// `Camera3D` at. The origin when no joints were reported.
    public var center: Vector3 {
        guard !joints.isEmpty else { return .zero }
        var sum = Vector3.zero
        for p in joints.values { sum += p }
        return sum / Double(joints.count)
    }

    /// The skeleton as a `PointCloud` for drawing in the cloud's own space: each
    /// joint a `jointSize` splat, each bone a line of `boneSize` splats spaced
    /// about `boneSize` apart — the one shipped way to draw a 3D skeleton today, as
    /// `LiftedPose.cloud` does.
    public func cloud(jointSize: Double = 0.05, boneSize: Double = 0.02,
                      color: Color = .white) -> PointCloud {
        var cloud = PointCloud()
        for p in joints.values { cloud.add(p, color: color, size: jointSize) }
        for (a, b) in bones() {
            let steps = max(1, Int((a.distance(to: b) / max(boneSize, 1e-4)).rounded()))
            for s in 1..<steps {                 // interior dots; endpoints are joints
                cloud.add(a.lerp(to: b, Double(s) / Double(steps)), color: color, size: boneSize)
            }
        }
        return cloud
    }

    /// The bones of the streamed skeleton, as joint pairs: the spine chain root to
    /// head, both arms off the chest, both legs off the hips.
    public static let skeleton: [(PhoneJoint, PhoneJoint)] = [
        (.root, .hips), (.hips, .spine), (.spine, .chest), (.chest, .neck), (.neck, .head),
        (.chest, .leftShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.leftWrist, .leftHand),
        (.chest, .rightShoulder), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.rightWrist, .rightHand),
        (.hips, .leftHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.leftAnkle, .leftFoot),
        (.hips, .rightHip), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.rightAnkle, .rightFoot),
    ]
}

/// One CoreMotion sample from the phone — the cheap smoke-test payload that proves
/// the USB transport before the skeleton is decoded. Attitude is a quaternion
/// `(x,y,z,w)`; gravity and user acceleration are in g, rotation rate in rad/s.
public struct PhoneMotion: Sendable, Equatable {
    public let attitude: SIMD4<Float>
    public let gravity: Vector3
    public let rotationRate: Vector3
    public let userAcceleration: Vector3
    public let timestamp: Double

    init(_ sample: PhoneMotionSample) {
        attitude = sample.attitude
        gravity = Vector3(Double(sample.gravity.x), Double(sample.gravity.y), Double(sample.gravity.z))
        rotationRate = Vector3(Double(sample.rotationRate.x), Double(sample.rotationRate.y),
                               Double(sample.rotationRate.z))
        userAcceleration = Vector3(Double(sample.userAcceleration.x), Double(sample.userAcceleration.y),
                                   Double(sample.userAcceleration.z))
        timestamp = sample.timestamp
    }
}
