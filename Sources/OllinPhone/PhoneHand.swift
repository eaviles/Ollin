import Ollin
import simd

/// One hand streamed from the phone: which hand it is, the model's confidence,
/// and the 21-joint skeleton the phone found on its own Neural Engine (Hands
/// mode, rear camera).
///
/// Every joint carries an upright 2D image point, already turned for how the
/// phone was held: map it onto the canvas with `point(_:in:)`, passing the
/// rectangle you want the picture's frame to fill. On a LiDAR phone a joint also
/// carries a metric 3D `position(_:)` in ARKit world space (meters, y up, the
/// origin where the phone's session started), the same world the depth sweep,
/// the room, and the body stream stand in, so a hand can reach into that scene.
///
/// ```swift
/// for hand in device.latestHands {
///     for (a, b) in hand.bones() { drawCapsule(from: a, to: b, radius: 0.008) }
///     if let d = hand.pinchDistance, d < 0.02 { background(.white) }
/// }
/// ```
public struct PhoneHand: Sendable {

    /// Left or right hand (from the camera's point of view), or `unknown`.
    public enum Chirality: Sendable { case left, right, unknown }

    /// Whether the phone's ARKit session had steady tracking when this hand was
    /// found; the world positions of a frame without tracking are best skipped.
    public let isTracked: Bool

    /// The capture timestamp of the frame, in the phone's clock (seconds).
    public let timestamp: Double

    /// Which hand this is, as the model saw it.
    public let chirality: Chirality

    /// The model's overall confidence in this hand, `0…1`.
    public let confidence: Double

    let joints: [PhoneHandJoint: PhoneHandJointSample]

    /// Wrap a decoded wire sample. Public so a hand can be staged with no phone
    /// (a test or a figure builds a `PhoneHandSample` and reads it back through
    /// the same accessors the live stream uses).
    public init(_ sample: PhoneHandSample) {
        isTracked = sample.isTracked
        timestamp = sample.timestamp
        switch sample.chirality {
        case .left: chirality = .left
        case .right: chirality = .right
        case .unknown: chirality = .unknown
        }
        confidence = Double(sample.confidence)
        joints = sample.joints
    }

    /// Whether a joint was reported in this frame (the model dropped the ones it
    /// could not place).
    public func has(_ joint: PhoneHandJoint) -> Bool { joints[joint] != nil }

    /// The model's confidence in one joint, `0…1`, or `nil` if it wasn't reported.
    public func confidence(of joint: PhoneHandJoint) -> Double? {
        joints[joint].map { Double($0.confidence) }
    }

    /// One joint's metric 3D position in ARKit world space (meters), or `nil`
    /// when it wasn't reported or the phone had no depth to lift it through (a
    /// non-LiDAR phone, or a joint over a hole in the depth map).
    public func position(_ joint: PhoneHandJoint) -> Vector3? {
        guard let j = joints[joint], j.hasWorldPosition else { return nil }
        return Vector3(Double(j.worldPosition.x), Double(j.worldPosition.y),
                       Double(j.worldPosition.z))
    }

    /// One joint's upright image point mapped into `rect` (canvas space), or
    /// `nil` if it wasn't reported. Map into the same rectangle you draw the
    /// scene into and the overlay lines up whichever way the phone is held.
    public func point(_ joint: PhoneHandJoint, in rect: Rectangle) -> Vector2? {
        joints[joint].map { PhoneHand.mapped($0.point, in: rect) }
    }

    /// Every reported joint's image point mapped into `rect`.
    public func points(in rect: Rectangle) -> [PhoneHandJoint: Vector2] {
        joints.mapValues { PhoneHand.mapped($0.point, in: rect) }
    }

    /// Whether any joint carries a lifted 3D position: `false` on a phone with no
    /// LiDAR, where the hand is a 2D skeleton only.
    public var hasWorldPositions: Bool {
        joints.values.contains { $0.hasWorldPosition }
    }

    /// The hand skeleton as 3D segments in ARKit world space, for the bones whose
    /// both ends were lifted. Draw them with `drawCapsule(from:to:radius:)` for a
    /// solid hand, or read `cloud()` for the lightest one.
    public func bones() -> [(Vector3, Vector3)] {
        PhoneHand.skeleton.compactMap { bone in
            guard let a = position(bone.0), let b = position(bone.1) else { return nil }
            return (a, b)
        }
    }

    /// The hand skeleton as 2D segments mapped into `rect`, for the bones whose
    /// both ends were reported: the flat overlay for drawing over a feed.
    public func bones(in rect: Rectangle) -> [(Vector2, Vector2)] {
        PhoneHand.skeleton.compactMap { bone in
            guard let a = point(bone.0, in: rect), let b = point(bone.1, in: rect) else { return nil }
            return (a, b)
        }
    }

    /// The centroid of the lifted joints, a steady point to aim an orbiting
    /// `Camera3D` at. The origin when no joint carries a world position.
    public var center: Vector3 {
        var sum = Vector3.zero
        var count = 0
        for joint in PhoneHandJoint.allCases {
            guard let p = position(joint) else { continue }
            sum += p
            count += 1
        }
        return count > 0 ? sum / Double(count) : .zero
    }

    /// How far apart the thumb and index fingertips are, in meters, or `nil`
    /// when either wasn't lifted: the one number most gestures hang off (closed
    /// pinch is under about a centimeter and a half).
    public var pinchDistance: Double? {
        guard let thumb = position(.thumbTip), let index = position(.indexTip) else { return nil }
        return thumb.distance(to: index)
    }

    /// The lifted hand as a `PointCloud` in ARKit world space: each joint a
    /// `jointSize` splat, each bone a line of `boneSize` splats, the lightest way
    /// to draw it (for solid bones see `drawCapsule(from:to:radius:)`). Empty when
    /// no joint carries a world position.
    public func cloud(jointSize: Double = 0.012, boneSize: Double = 0.005,
                      color: Color = .white) -> PointCloud {
        var cloud = PointCloud()
        for joint in PhoneHandJoint.allCases {
            guard let p = position(joint) else { continue }
            cloud.add(p, color: color, size: jointSize)
        }
        for (a, b) in bones() {
            let steps = max(1, Int((a.distance(to: b) / max(boneSize, 1e-4)).rounded()))
            for s in 1..<steps {                 // interior dots; endpoints are joints
                cloud.add(a.lerp(to: b, Double(s) / Double(steps)), color: color, size: boneSize)
            }
        }
        return cloud
    }

    /// The bones of the streamed hand, as joint pairs: the wrist into each finger's
    /// base, then along each finger to its tip.
    public static let skeleton: [(PhoneHandJoint, PhoneHandJoint)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
    ]

    /// The five fingertip joints, handy for pinch and point gestures.
    public static let tips: [PhoneHandJoint] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]

    /// Each finger as its chain of joints, wrist first, tip last: the polylines to
    /// run a tube or a ribbon along.
    public static let fingerChains: [[PhoneHandJoint]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    /// An upright normalized point (lower-left origin, y up) into canvas space
    /// (top-left origin, y down), scaled into `rect`.
    private static func mapped(_ p: SIMD2<Float>, in rect: Rectangle) -> Vector2 {
        Vector2(rect.x + Double(p.x) * rect.width,
                rect.y + (1 - Double(p.y)) * rect.height)
    }
}
