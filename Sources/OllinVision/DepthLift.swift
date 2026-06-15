import Ollin

/// A 2D body pose lifted into space through a depth map — every joint a metric 3D
/// position in **meters**, where `Body` gives flat picture coordinates.
///
/// Where `BodyTracker3D` *estimates* a skeleton's depth from a single image, this
/// reads the depth directly: a 2D `Body` (from `BodyTracker`) back-projected
/// through an `RGBDFrame`'s depth and intrinsics. So with a real depth source —
/// an iPhone's LiDAR or TrueDepth camera — the joints sit at their true distance,
/// not a guessed one.
///
/// Positions are in the camera's right-handed, y-up space: +x right, +y up, the
/// camera looking down −z (a joint in front of the lens has negative z). That's
/// the **same space the depth cloud lives in**, so a lifted skeleton drops inside
/// the person's own `pointCloud(...)` and `cloud(...)` draws both together through
/// one `Camera3D`.
///
/// ```swift
/// if let body = bodies.bodies.first, let frame = device.latestFrame {
///     let pose = body.lifted(through: frame)
///     camera(.orbiting(target: pose.center ?? .zero, radius: 2.5, azimuth: time * 0.3))
///     drawPointCloud(frame.pointCloud())   // the person, as depth points
///     drawPointCloud(pose.cloud())          // the skeleton, in the same space
/// }
/// ```
public struct LiftedPose: Sendable {

    /// The 2D pose's overall detection confidence, `0…1`, carried through.
    public let confidence: Double

    /// Joints that found valid depth, as metric 3D positions (meters) in camera
    /// space. A joint whose depth was a hole (no valid sample nearby) is absent,
    /// just as a low-confidence 2D joint is absent from the source `Body`.
    let joints: [BodyJoint: Vector3]

    init(confidence: Double, joints: [BodyJoint: Vector3]) {
        self.confidence = confidence
        self.joints = joints
    }

    /// Whether a joint was lifted (detected in 2D *and* found valid depth).
    public func has(_ joint: BodyJoint) -> Bool { joints[joint] != nil }

    /// One joint's metric 3D position (meters, camera space), or `nil` if it
    /// wasn't lifted.
    public func position(_ joint: BodyJoint) -> Vector3? { joints[joint] }

    /// Every lifted joint's metric 3D position.
    public var positions: [BodyJoint: Vector3] { joints }

    /// The skeleton as 3D segments in metric space, for the bones whose both ends
    /// were lifted — project them however you like, or draw them in the cloud.
    public func bones() -> [(Vector3, Vector3)] {
        Body.skeleton.compactMap { bone in
            guard let a = joints[bone.0], let b = joints[bone.1] else { return nil }
            return (a, b)
        }
    }

    /// The centroid of the lifted joints, or `nil` if none were lifted — a steady
    /// point to aim an orbiting `Camera3D` at.
    public var center: Vector3? {
        guard !joints.isEmpty else { return nil }
        var sum = Vector3.zero
        for p in joints.values { sum += p }
        return sum / Double(joints.count)
    }

    /// The skeleton as a `PointCloud` for drawing in the cloud's own space: each
    /// joint a `jointSize` splat, each bone a line of `boneSize` splats spaced
    /// about `boneSize` apart. The one shipped way to draw a 3D skeleton today —
    /// 3D mode has no line primitive yet — and it reads naturally over the
    /// person's depth cloud.
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
}

public extension Body {
    /// Lift this 2D pose into metric 3D by back-projecting each joint through
    /// `frame`'s depth and intrinsics — true distances from a real depth source,
    /// landing in the same camera space as `frame.pointCloud(...)`.
    ///
    /// The `Body` must come from the **same color frame** carried by `frame` (run
    /// a `BodyTracker` on the depth source, then lift through its latest frame),
    /// since the joints' normalized points are read against that picture's depth.
    /// `radius` is the depth-sampling window in depth pixels (see
    /// `RGBDFrame.unproject(normalized:radius:)`); a joint with no valid depth
    /// nearby is dropped.
    func lifted(through frame: RGBDFrame, radius: Int = 2) -> LiftedPose {
        var lifted: [BodyJoint: Vector3] = [:]
        for (joint, normalized) in joints {
            if let position = frame.unproject(normalized: normalized, radius: radius) {
                lifted[joint] = position
            }
        }
        return LiftedPose(confidence: confidence, joints: lifted)
    }
}
