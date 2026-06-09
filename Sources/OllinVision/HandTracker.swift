import Ollin
import Vision
import Foundation
import os

/// A hand joint, the 21 points Vision reports per hand: the wrist, plus four
/// joints along each finger from base to tip.
public enum HandJoint: String, Sendable, CaseIterable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    /// The fingertip joints, handy for pinch/point gestures.
    public static let tips: [HandJoint] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
}

/// A finger — the chain of joints from the wrist out to a fingertip.
public enum Finger: String, Sendable, CaseIterable {
    case thumb, index, middle, ring, little

    /// The joints along this finger, wrist first, tip last.
    public var chain: [HandJoint] {
        switch self {
        case .thumb:  return [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]
        case .index:  return [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]
        case .middle: return [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]
        case .ring:   return [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]
        case .little: return [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
        }
    }
}

/// One detected hand: which hand it is, and the joints Vision was confident
/// about, in normalized coordinates. Map them onto the canvas with the `in:`
/// helpers (pass the rectangle you drew the frame into).
///
/// ```swift
/// for hand in hands.hands {
///     for (a, b) in hand.bones(in: bounds) { drawLine(a, b) }
///     if let tip = hand.point(.indexTip, in: bounds) { drawCircle(tip.x, tip.y, 8) }
/// }
/// ```
public struct Hand: Sendable {

    /// Left or right hand (from the camera's point of view), or `unknown`.
    public enum Chirality: Sendable { case left, right, unknown }

    public let chirality: Chirality
    /// Overall detection confidence, `0…1`.
    public let confidence: Double

    /// Confident joints in normalized coordinates (lower-left origin). A joint
    /// Vision couldn't place is absent.
    let joints: [HandJoint: Vector2]

    /// Whether a joint was detected with enough confidence to report.
    public func has(_ joint: HandJoint) -> Bool { joints[joint] != nil }

    /// One joint mapped into `rect`, or `nil` if it wasn't detected.
    public func point(_ joint: HandJoint, in rect: Rectangle, mirrored: Bool = false) -> Vector2? {
        joints[joint].map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// Every detected joint mapped into `rect`.
    public func points(in rect: Rectangle, mirrored: Bool = false) -> [HandJoint: Vector2] {
        joints.mapValues { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// The detected joints along one finger, mapped into `rect`, in order — a
    /// polyline from the wrist to the tip (missing joints are skipped).
    public func finger(_ finger: Finger, in rect: Rectangle, mirrored: Bool = false) -> [Vector2] {
        finger.chain.compactMap { point($0, in: rect, mirrored: mirrored) }
    }

    /// The hand skeleton as line segments mapped into `rect` — consecutive joints
    /// along each finger. A gap (a missing joint) breaks the chain rather than
    /// drawing a segment across it.
    public func bones(in rect: Rectangle, mirrored: Bool = false) -> [(Vector2, Vector2)] {
        var segments: [(Vector2, Vector2)] = []
        for finger in Finger.allCases {
            var previous: Vector2?
            for joint in finger.chain {
                if let current = point(joint, in: rect, mirrored: mirrored) {
                    if let previous { segments.append((previous, current)) }
                    previous = current
                } else {
                    previous = nil
                }
            }
        }
        return segments
    }
}

/// Finds hands and their 21-joint skeletons in a camera's frames (or a still
/// image) — the most expressive tracker for gesture-driven sketches. Pinch,
/// point, and open-hand all fall out of a few joint positions.
///
/// ```swift
/// let camera = Camera()
/// let hands = HandTracker(camera)
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     for hand in hands.hands {
///         for (a, b) in hand.bones(in: bounds) { drawLine(a, b) }
///     }
/// }
/// ```
public final class HandTracker: VisionTracking, @unchecked Sendable {

    /// How many hands to look for (Vision's `maximumHandCount`).
    public let maximumHandCount: Int

    /// Joints below this confidence are dropped (occluded or guessed).
    private static let minimumJointConfidence: Float = 0.3

    private let lock = OSAllocatedUnfairLock<[Hand]>(initialState: [])
    private let status = VisionStatus("hand tracking")

    /// The hands seen in the most recent analyzed frame.
    public var hands: [Hand] { lock.withLock { $0 } }
    /// How many hands are present right now.
    public var count: Int { lock.withLock { $0.count } }

    /// Whether hand tracking can run on this Mac (`false` only if the Vision model
    /// has no compute device here); `unavailableReason` explains a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why hand tracking can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Track hands in `camera`'s live feed.
    @MainActor
    public init(_ camera: Camera, maximumHandCount: Int = 2) {
        self.maximumHandCount = max(1, maximumHandCount)
        camera.register(self)
    }

    /// Detect hands in a still image, once.
    public static func detect(in image: Image, maximumHandCount: Int = 2) async throws -> [Hand] {
        var request = DetectHumanHandPoseRequest()
        request.maximumHandCount = max(1, maximumHandCount)
        let observations = try await request.perform(on: image.currentCGImage())
        return decode(observations)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        var request = DetectHumanHandPoseRequest()
        request.maximumHandCount = maximumHandCount
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { $0 = HandTracker.decode(observations) }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Decoding

    private static func decode(_ observations: [HumanHandPoseObservation]) -> [Hand] {
        observations.map { observation in
            var joints: [HandJoint: Vector2] = [:]
            for (name, joint) in observation.allJoints() {
                guard joint.confidence >= minimumJointConfidence,
                      let mapped = handJoint(name) else { continue }
                joints[mapped] = Vector2(Double(joint.location.x), Double(joint.location.y))
            }
            let chirality: Hand.Chirality
            switch observation.chirality {
            case .left:  chirality = .left
            case .right: chirality = .right
            default:     chirality = .unknown
            }
            return Hand(chirality: chirality, confidence: Double(observation.confidence), joints: joints)
        }
    }

    /// Map Vision's joint name onto our `HandJoint` (ignoring the enum's group
    /// and revision cases). An explicit switch, not a rawValue match — Vision's
    /// rawValues are its own internal strings, not our case names.
    private static func handJoint(_ name: HumanHandPoseObservation.JointName) -> HandJoint? {
        switch name {
        case .wrist:      return .wrist
        case .thumbCMC:   return .thumbCMC
        case .thumbMP:    return .thumbMP
        case .thumbIP:    return .thumbIP
        case .thumbTip:   return .thumbTip
        case .indexMCP:   return .indexMCP
        case .indexPIP:   return .indexPIP
        case .indexDIP:   return .indexDIP
        case .indexTip:   return .indexTip
        case .middleMCP:  return .middleMCP
        case .middlePIP:  return .middlePIP
        case .middleDIP:  return .middleDIP
        case .middleTip:  return .middleTip
        case .ringMCP:    return .ringMCP
        case .ringPIP:    return .ringPIP
        case .ringDIP:    return .ringDIP
        case .ringTip:    return .ringTip
        case .littleMCP:  return .littleMCP
        case .littlePIP:  return .littlePIP
        case .littleDIP:  return .littleDIP
        case .littleTip:  return .littleTip
        default:          return nil
        }
    }
}
