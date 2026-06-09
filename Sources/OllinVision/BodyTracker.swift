import Ollin
import Vision
import Foundation
import os

/// A body joint — the 19 points Vision reports for a person: head (nose, eyes,
/// ears, neck), arms (shoulders, elbows, wrists), the torso root, and legs (hips,
/// knees, ankles).
public enum BodyJoint: Sendable, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// One detected person's pose: the joints Vision was confident about, in
/// normalized coordinates. Map them onto the canvas with the `in:` helpers.
///
/// ```swift
/// for body in bodies.bodies {
///     for (a, b) in body.bones(in: bounds) { drawLine(a, b) }
/// }
/// ```
public struct Body: Sendable {

    /// Overall detection confidence, `0…1`.
    public let confidence: Double

    /// Confident joints in normalized coordinates (lower-left origin). A joint
    /// Vision couldn't place (off-frame, occluded) is absent — common for the
    /// legs when only the upper body is in view.
    let joints: [BodyJoint: Vector2]

    /// Whether a joint was detected with enough confidence to report.
    public func has(_ joint: BodyJoint) -> Bool { joints[joint] != nil }

    /// One joint mapped into `rect`, or `nil` if it wasn't detected.
    public func point(_ joint: BodyJoint, in rect: Rectangle, mirrored: Bool = false) -> Vector2? {
        joints[joint].map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// Every detected joint mapped into `rect`.
    public func points(in rect: Rectangle, mirrored: Bool = false) -> [BodyJoint: Vector2] {
        joints.mapValues { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// The skeleton as line segments mapped into `rect`, for the bones whose both
    /// ends were detected (a missing joint simply omits its bones).
    public func bones(in rect: Rectangle, mirrored: Bool = false) -> [(Vector2, Vector2)] {
        Body.skeleton.compactMap { bone in
            guard let a = point(bone.0, in: rect, mirrored: mirrored),
                  let b = point(bone.1, in: rect, mirrored: mirrored) else { return nil }
            return (a, b)
        }
    }

    /// The bones of the body skeleton, as joint pairs: head, spine, both arms,
    /// both legs.
    public static let skeleton: [(BodyJoint, BodyJoint)] = [
        (.neck, .nose),
        (.nose, .leftEye), (.leftEye, .leftEar),
        (.nose, .rightEye), (.rightEye, .rightEar),
        (.neck, .leftShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.neck, .rightShoulder), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.root, .rightHip), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]
}

/// Finds people and their 2D pose skeletons in a camera's frames (or a still
/// image). Where `HandTracker` is the close-up gesture tool, this is the
/// whole-body one — reach, lean, jump, and silhouette all read from the joints.
///
/// ```swift
/// let camera = Camera()
/// let bodies = BodyTracker(camera)
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     for body in bodies.bodies {
///         for (a, b) in body.bones(in: bounds) { drawLine(a, b) }
///     }
/// }
/// ```
public final class BodyTracker: VisionTracking, @unchecked Sendable {

    /// Joints below this confidence are dropped (occluded or off-frame).
    private static let minimumJointConfidence: Float = 0.2

    private let lock = OSAllocatedUnfairLock<[Body]>(initialState: [])
    private let status = VisionStatus("body pose")

    /// The people seen in the most recent analyzed frame.
    public var bodies: [Body] { lock.withLock { $0 } }
    /// How many people are present right now.
    public var count: Int { lock.withLock { $0.count } }

    /// Whether body pose can run on this Mac. Some Macs lack the compute device
    /// (Neural Engine) the model needs; when so, this is `false` and
    /// `unavailableReason` says why instead of just reporting no people.
    public var isAvailable: Bool { status.isAvailable }
    /// Why body pose can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Track body pose in `camera`'s live feed.
    @MainActor
    public init(_ camera: Camera) {
        camera.register(self)
    }

    /// Detect body pose in a still image, once.
    public static func detect(in image: Image) async throws -> [Body] {
        let request = DetectHumanBodyPoseRequest()
        let observations = try await request.perform(on: image.currentCGImage())
        return decode(observations)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        // Once the model is known unavailable on this Mac, stop calling perform —
        // it won't recover this session, and re-trying every frame just wastes work
        // and lets Vision log its own error per frame.
        guard status.isAvailable else { return }
        let request = DetectHumanBodyPoseRequest()
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { $0 = BodyTracker.decode(observations) }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Decoding

    private static func decode(_ observations: [HumanBodyPoseObservation]) -> [Body] {
        observations.map { observation in
            var joints: [BodyJoint: Vector2] = [:]
            for (name, joint) in observation.allJoints() {
                guard joint.confidence >= minimumJointConfidence,
                      let mapped = bodyJoint(name) else { continue }
                joints[mapped] = Vector2(Double(joint.location.x), Double(joint.location.y))
            }
            return Body(confidence: Double(observation.confidence), joints: joints)
        }
    }

    /// Map Vision's joint name onto our `BodyJoint` (explicit, not a rawValue
    /// match), ignoring the enum's group and revision cases.
    private static func bodyJoint(_ name: HumanBodyPoseObservation.JointName) -> BodyJoint? {
        switch name {
        case .nose:          return .nose
        case .leftEye:       return .leftEye
        case .rightEye:      return .rightEye
        case .leftEar:       return .leftEar
        case .rightEar:      return .rightEar
        case .neck:          return .neck
        case .leftShoulder:  return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow:     return .leftElbow
        case .rightElbow:    return .rightElbow
        case .leftWrist:     return .leftWrist
        case .rightWrist:    return .rightWrist
        case .root:          return .root
        case .leftHip:       return .leftHip
        case .rightHip:      return .rightHip
        case .leftKnee:      return .leftKnee
        case .rightKnee:     return .rightKnee
        case .leftAnkle:     return .leftAnkle
        case .rightAnkle:    return .rightAnkle
        default:             return nil
        }
    }
}
