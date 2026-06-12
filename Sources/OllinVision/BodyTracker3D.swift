import Ollin
import Vision
import Foundation
import os

/// A joint of the 3D body skeleton — the 17 points the model places in space:
/// head (top and center), shoulders (center, left, right), arms (elbows,
/// wrists), the spine and the pelvis root, and legs (hips, knees, ankles).
///
/// A different set from `BodyJoint` (the 2D pose): no eyes or ears, but a spine
/// and a measured head top — the 3D skeleton is built for the body in space,
/// not the face.
public enum BodyJoint3D: Sendable, CaseIterable {
    case topHead, centerHead
    case centerShoulder, leftShoulder, rightShoulder
    case leftElbow, rightElbow, leftWrist, rightWrist
    case spine, root
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// One person's pose in space: every joint as a 3D position in **meters**,
/// plus its projection back onto the picture for overlays.
///
/// Three coordinate spaces, all read straight off the body:
/// - **Canvas** (`point(_:in:)`, `bones(in:)`) — the joints projected onto the
///   frame and mapped into the rectangle you drew it in, for skeleton overlays.
/// - **Model space** (`position(_:)`, `bones()`) — meters, with the pelvis
///   `root` at the origin, x to the picture's right, y up, and z pointing away
///   from the camera. Project `(z, y)` and you've drawn the person from the
///   side; `(x, z)` is the view from above — angles no camera was at.
/// - **Camera space** (`cameraRelativePosition(_:)`) — meters from the camera
///   itself, so a visible person's z is their distance (the `distance` sugar).
///
/// Unlike the 2D pose, the model always places the **full skeleton**, guessing
/// joints it can't see — there is no per-joint confidence, and an off-frame
/// ankle simply projects outside the rectangle you map into.
///
/// ```swift
/// if let body = tracker.body {
///     for (a, b) in body.bones(in: rect) { drawLine(a, b) }      // over the feed
///     for (a, b) in body.bones() { drawSideView(a, b) }           // in meters
/// }
/// ```
public struct Body3D: Sendable {

    /// How the body's height was established. Without real depth data the model
    /// assumes a reference height and scales the skeleton to it; captures that
    /// carry depth (a LiDAR photo) get a true measurement.
    public enum HeightEstimation: Sendable {
        /// Assumed: the skeleton is scaled to a standard reference height.
        case reference
        /// Measured from depth data in the image.
        case measured
    }

    /// Everything known about one joint, decoded out of the observation.
    struct JointRecord: Sendable {
        /// Model space: meters, root at the origin.
        let position: Vector3
        /// Camera space: meters from the camera.
        let cameraPosition: Vector3
        /// The joint projected onto the frame, normalized (lower-left origin).
        let imagePoint: Vector2
    }

    /// Overall detection confidence, `0…1`.
    public let confidence: Double

    /// The person's estimated height in meters — see `heightEstimation` for
    /// whether it was measured or assumed.
    public let height: Double

    /// Whether `height` (and with it the skeleton's scale) was measured from
    /// depth data or assumed from a reference.
    public let heightEstimation: HeightEstimation

    let joints: [BodyJoint3D: JointRecord]

    init(confidence: Double, height: Double, heightEstimation: HeightEstimation,
         joints: [BodyJoint3D: JointRecord]) {
        self.confidence = confidence
        self.height = height
        self.heightEstimation = heightEstimation
        self.joints = joints
    }

    /// How far the person is from the camera, in meters (the distance to their
    /// pelvis root), or `nil` if the root wasn't reported.
    public var distance: Double? { joints[.root].map { $0.cameraPosition.length } }

    /// Whether a joint was reported. The model normally places all 17.
    public func has(_ joint: BodyJoint3D) -> Bool { joints[joint] != nil }

    // MARK: Canvas (the overlay surface)

    /// One joint projected onto the frame and mapped into `rect`, or `nil` if it
    /// wasn't reported. A joint outside the frame maps outside `rect`.
    public func point(_ joint: BodyJoint3D, in rect: Rectangle, mirrored: Bool = false) -> Vector2? {
        joints[joint].map { VisionSpace.point($0.imagePoint, in: rect, mirrored: mirrored) }
    }

    /// Every reported joint projected onto the frame and mapped into `rect`.
    public func points(in rect: Rectangle, mirrored: Bool = false) -> [BodyJoint3D: Vector2] {
        joints.mapValues { VisionSpace.point($0.imagePoint, in: rect, mirrored: mirrored) }
    }

    /// The skeleton as line segments mapped into `rect`, for the bones whose
    /// both ends were reported.
    public func bones(in rect: Rectangle, mirrored: Bool = false) -> [(Vector2, Vector2)] {
        Body3D.skeleton.compactMap { bone in
            guard let a = point(bone.0, in: rect, mirrored: mirrored),
                  let b = point(bone.1, in: rect, mirrored: mirrored) else { return nil }
            return (a, b)
        }
    }

    // MARK: Model space (meters, root at the origin)

    /// One joint's position in model space — meters, root at the origin, x to
    /// the picture's right, y up, z away from the camera — or `nil` if it wasn't
    /// reported.
    public func position(_ joint: BodyJoint3D) -> Vector3? {
        joints[joint]?.position
    }

    /// Every reported joint's position in model space.
    public var positions: [BodyJoint3D: Vector3] {
        joints.mapValues { $0.position }
    }

    /// The skeleton as 3D segments in model space — project the endpoints
    /// however you like to draw the figure from any angle.
    public func bones() -> [(Vector3, Vector3)] {
        Body3D.skeleton.compactMap { bone in
            guard let a = position(bone.0), let b = position(bone.1) else { return nil }
            return (a, b)
        }
    }

    // MARK: Camera space (meters from the camera)

    /// One joint's position relative to the camera — meters, x to the picture's
    /// right, y up, z out in front of the lens (a visible person has positive z,
    /// their distance) — or `nil` if it wasn't reported.
    public func cameraRelativePosition(_ joint: BodyJoint3D) -> Vector3? {
        joints[joint]?.cameraPosition
    }

    /// The bones of the 3D body skeleton, as joint pairs: the spine chain from
    /// root to head top, both arms off the shoulder center, both legs off the
    /// root.
    public static let skeleton: [(BodyJoint3D, BodyJoint3D)] = [
        (.root, .spine), (.spine, .centerShoulder),
        (.centerShoulder, .centerHead), (.centerHead, .topHead),
        (.centerShoulder, .leftShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.centerShoulder, .rightShoulder), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.root, .leftHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.root, .rightHip), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]
}

/// Finds one person's pose **in space** from an ordinary 2D camera — every
/// joint a 3D position in meters, where `BodyTracker` gives flat picture
/// coordinates. The same single webcam, but now the sketch knows how far the
/// person is, how tall they are, and what their figure looks like from the
/// side.
///
/// Reads one person — the most prominent — so the surface is a singular
/// `body`, not a list (the 2D tracker is the multi-person one).
///
/// ```swift
/// let camera = Camera()
/// lazy var tracker = BodyTracker3D(camera)
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     if let body = tracker.body {
///         for (a, b) in body.bones(in: bounds) { drawLine(a, b) }
///     }
/// }
/// ```
public final class BodyTracker3D: VisionTracking, @unchecked Sendable {

    private struct State {
        /// The live request — built once on the analysis task and re-performed
        /// every frame. Load-bearing: a *fresh* request costs ~300 ms per
        /// perform (its setup isn't cached process-wide), while re-performing
        /// one held instance runs in ~20 ms — the difference between a slide
        /// show and tracking at the camera's cadence.
        var request: DetectHumanBodyPose3DRequest?
        var result: Body3D?
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let status = VisionStatus("3D body pose")

    /// The person seen in the most recent analyzed frame, or `nil` while no one
    /// is in view.
    public var body: Body3D? { lock.withLock { $0.result } }

    /// Whether 3D body pose can run on this Mac. Some Macs lack the compute
    /// device (Neural Engine) the model needs; when so, this is `false` and
    /// `unavailableReason` says why instead of just reporting no person.
    public var isAvailable: Bool { status.isAvailable }
    /// Why 3D body pose can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Track 3D body pose in `source`'s frames — the live camera, or a playing
    /// video.
    @MainActor
    public init(_ source: any FrameSource) {
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Detect 3D body pose in a still image, once. `nil` when no person is found.
    public static func detect(in image: Image) async throws -> Body3D? {
        let request = DetectHumanBodyPose3DRequest()
        let observations = try await request.perform(on: image.currentCGImage())
        return observations.first.map(Body3D.init)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        // Once the model is known unavailable on this Mac, stop calling perform —
        // it won't recover this session, and re-trying every frame just wastes
        // work and lets Vision log its own error per frame.
        guard status.isAvailable else { return }
        let request = lock.withLock { state in
            if state.request == nil { state.request = DetectHumanBodyPose3DRequest() }
            return state.request!
        }
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { $0.result = observations.first.map(Body3D.init) }
        } catch {
            status.recordFailure(error)
        }
    }
}

// MARK: Decoding

extension Body3D {

    /// Decode from the Vision observation, keeping the Vision types off the
    /// public surface. Positions come out of the matrices' translation columns;
    /// the rotations stay behind until something needs them.
    init(_ observation: HumanBodyPose3DObservation) {
        var joints: [BodyJoint3D: JointRecord] = [:]
        for name in observation.availableJointNames {
            guard let mapped = Body3D.joint3D(name),
                  let joint = observation.joint(for: name) else { continue }
            let model = joint.position.columns.3
            let camera = observation.cameraRelativePosition(for: name).columns.3
            let image = observation.pointInImage(for: name)
            joints[mapped] = JointRecord(
                position: Vector3(Double(model.x), Double(model.y), Double(model.z)),
                cameraPosition: Vector3(Double(camera.x), Double(camera.y), Double(camera.z)),
                imagePoint: Vector2(Double(image.x), Double(image.y)))
        }
        self.init(confidence: Double(observation.confidence),
                  height: observation.bodyHeight.converted(to: .meters).value,
                  heightEstimation: observation.heightEstimationTechnique == .measured
                      ? .measured : .reference,
                  joints: joints)
    }

    /// Map Vision's joint name onto our `BodyJoint3D` (explicit, not a rawValue
    /// match).
    private static func joint3D(_ name: HumanBodyPose3DObservation.JointName) -> BodyJoint3D? {
        switch name {
        case .topHead:        return .topHead
        case .centerHead:     return .centerHead
        case .centerShoulder: return .centerShoulder
        case .leftShoulder:   return .leftShoulder
        case .rightShoulder:  return .rightShoulder
        case .leftElbow:      return .leftElbow
        case .rightElbow:     return .rightElbow
        case .leftWrist:      return .leftWrist
        case .rightWrist:     return .rightWrist
        case .spine:          return .spine
        case .root:           return .root
        case .leftHip:        return .leftHip
        case .rightHip:       return .rightHip
        case .leftKnee:       return .leftKnee
        case .rightKnee:      return .rightKnee
        case .leftAnkle:      return .leftAnkle
        case .rightAnkle:     return .rightAnkle
        @unknown default:     return nil
        }
    }
}
