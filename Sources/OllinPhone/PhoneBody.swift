import Ollin
import simd

/// One person's pose streamed from the phone's ARKit body tracker: every joint a
/// 3D position in **meters**, model space — the pelvis root at the origin, x to the
/// picture's right, y up, z toward the camera (ARKit's convention).
///
/// Where `Body3D` (OllinVision) *estimates* a skeleton from a single Mac webcam,
/// this is the phone's on-device ARKit skeleton arriving over the wire, with the
/// same model-space accessor shape. Draw it as a `PointCloud` (`cloud()`, like
/// `LiftedPose.cloud`), or as solid bones with `drawCapsule(from:to:radius:)`
/// over `bones()`, or pose parts at the joints through `modelTransform(_:)`.
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

    /// Model space → ARKit world space (meters, y up, the origin where the phone's
    /// session started): where the person stands. Multiply a model-space point (or
    /// a whole `cloud()`, via `PointCloud.transformed(by:)`) through this to place
    /// the skeleton in the same world the depth sweep and the room mesh use.
    public let worldTransform: simd_float4x4

    /// The person's estimated size relative to the default rig (1 = the default
    /// rig height; a smaller person gives a smaller factor).
    public let scaleFactor: Double

    let joints: [PhoneJoint: PhoneJointSample]

    /// Wrap a decoded wire sample. Public so a pose can be staged with no phone
    /// (a test or a figure builds a `PhonePoseSample` and reads it back through
    /// the same accessors the live stream uses).
    public init(_ sample: PhonePoseSample) {
        isTracked = sample.tracked
        timestamp = sample.timestamp
        worldTransform = sample.anchor
        scaleFactor = Double(sample.scaleFactor)
        joints = sample.joints
    }

    /// Whether a joint was reported in this frame.
    public func has(_ joint: PhoneJoint) -> Bool { joints[joint] != nil }

    /// One joint's position in model space (meters, root at the origin), or `nil`
    /// if it wasn't reported.
    public func position(_ joint: PhoneJoint) -> Vector3? {
        joints[joint].map { PhoneBody.vector($0.position) }
    }

    /// One joint's position in ARKit world space (the anchor applied), or `nil`
    /// if it wasn't reported.
    public func worldPosition(_ joint: PhoneJoint) -> Vector3? {
        guard let j = joints[joint] else { return nil }
        let p = worldTransform * SIMD4<Float>(j.position, 1)
        return Vector3(Double(p.x), Double(p.y), Double(p.z))
    }

    /// One joint's orientation as a quaternion `(x, y, z, w)` in model space, or
    /// `nil` if it wasn't reported.
    public func orientation(_ joint: PhoneJoint) -> SIMD4<Float>? { joints[joint]?.orientation }

    /// Whether the camera actually observed a joint this frame. ARKit's rig fills
    /// unseen joints in from their neighbors; those report `false`.
    public func isJointTracked(_ joint: PhoneJoint) -> Bool { joints[joint]?.tracked ?? false }

    /// One joint's full model-space pose (orientation and position composed into a
    /// 4x4), or `nil` if it wasn't reported. Hand it to `transform(_:)` inside
    /// `withState { }` to pose a solid part at the joint.
    public func modelTransform(_ joint: PhoneJoint) -> simd_float4x4? {
        guard let j = joints[joint] else { return nil }
        var m = simd_float4x4(simd_quatf(vector: j.orientation))
        m.columns.3 = SIMD4<Float>(j.position, 1)
        return m
    }

    /// One joint's full pose stood in ARKit world space (the anchor applied), or
    /// `nil` if it wasn't reported.
    public func worldTransform(of joint: PhoneJoint) -> simd_float4x4? {
        modelTransform(joint).map { worldTransform * $0 }
    }

    /// Every reported joint's position in model space.
    public var positions: [PhoneJoint: Vector3] {
        joints.mapValues { PhoneBody.vector($0.position) }
    }

    /// The skeleton as 3D segments in model space, for the bones whose both ends
    /// were reported: project them however you like to draw the figure from any
    /// angle.
    public func bones() -> [(Vector3, Vector3)] {
        PhoneBody.skeleton.compactMap { bone in
            guard let a = joints[bone.0], let b = joints[bone.1] else { return nil }
            return (PhoneBody.vector(a.position), PhoneBody.vector(b.position))
        }
    }

    /// The centroid of the reported joints, a steady point to aim an orbiting
    /// `Camera3D` at. The origin when no joints were reported.
    public var center: Vector3 {
        guard !joints.isEmpty else { return .zero }
        var sum = Vector3.zero
        for j in joints.values { sum += PhoneBody.vector(j.position) }
        return sum / Double(joints.count)
    }

    /// The centroid in ARKit world space (the anchor applied to `center`).
    public var worldCenter: Vector3 {
        let c = center
        let p = worldTransform * SIMD4<Float>(Float(c.x), Float(c.y), Float(c.z), 1)
        return Vector3(Double(p.x), Double(p.y), Double(p.z))
    }

    private static func vector(_ v: SIMD3<Float>) -> Vector3 {
        Vector3(Double(v.x), Double(v.y), Double(v.z))
    }

    /// The skeleton as a `PointCloud` for drawing in the cloud's own space: each
    /// joint a `jointSize` splat, each bone a line of `boneSize` splats spaced
    /// about `boneSize` apart, the lightest way to draw the figure (as
    /// `LiftedPose.cloud` does; for solid bones see `drawCapsule(from:to:radius:)`).
    public func cloud(jointSize: Double = 0.05, boneSize: Double = 0.02,
                      color: Color = .white) -> PointCloud {
        var cloud = PointCloud()
        for j in joints.values { cloud.add(PhoneBody.vector(j.position), color: color, size: jointSize) }
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
