import Foundation
import ARKit
import simd

/// Runs ARKit body tracking and turns the tracked skeletons into `PhonePoseSample`s:
/// the named joints as positions and orientations in meters, model space (the
/// skeleton root at the origin), plus the anchor transform that stands the skeleton
/// in world space and the person's estimated scale. ARKit delivers its delegate
/// callbacks on the main thread, so the `onBodies` closure fires on main.
///
/// ARKit's full body skeleton has ~91 joints addressed by string name; we map a
/// practical subset onto `PhoneJoint`. A name that isn't present in the skeleton
/// returns a nil transform and is simply skipped, so the figure still streams the
/// joints that resolved, and the available names are logged once for tuning.
final class ARStreamer: NSObject, ARSessionDelegate, LightReporting {

    /// Fired (on the main thread) each frame with every tracked body, empty when
    /// none is in view, so the receiver can clear itself.
    var onBodies: (([PhonePoseSample]) -> Void)?

    let lightSampler = LightSampler()

    /// Whether this device supports ARKit body tracking (A12+, rear camera).
    var isSupported: Bool { ARBodyTrackingConfiguration.isSupported }

    private let session = ARSession()
    private var loggedJointNames = false
    /// `PhoneJoint` → index into this skeleton definition's joint list, resolved
    /// once from the first body (the definition is fixed per device).
    private var jointIndices: [PhoneJoint: Int]?

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARBodyTrackingConfiguration()
        // Size the skeleton to the person, so `estimatedScaleFactor` means something.
        config.automaticSkeletonScaleEstimationEnabled = true
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lightSampler.report(frame)
        var bodies: [PhonePoseSample] = []
        for anchor in frame.anchors {
            guard let body = anchor as? ARBodyAnchor else { continue }
            let skeleton = body.skeleton

            if !loggedJointNames {
                loggedJointNames = true
                let names = skeleton.definition.jointNames.joined(separator: ", ")
                NSLog("Ollin capture, ARKit body joints: %@", names)
            }

            let indices = resolvedJointIndices(for: skeleton)
            var joints: [PhoneJoint: PhoneJointSample] = [:]
            for (phoneJoint, arName) in ARStreamer.jointMap {
                guard let transform = skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: arName))
                else { continue }
                let p = transform.columns.3
                let tracked = indices[phoneJoint].map { skeleton.isJointTracked($0) } ?? false
                joints[phoneJoint] = PhoneJointSample(position: SIMD3<Float>(p.x, p.y, p.z),
                                                      orientation: simd_quatf(transform).vector,
                                                      tracked: tracked)
            }
            bodies.append(PhonePoseSample(tracked: body.isTracked, timestamp: frame.timestamp,
                                          anchor: body.transform,
                                          scaleFactor: Float(body.estimatedScaleFactor),
                                          joints: joints))
        }
        onBodies?(bodies)
    }

    /// The joint-name → index map for this skeleton definition, built once (the
    /// per-joint tracked flag is addressed by index).
    private func resolvedJointIndices(for skeleton: ARSkeleton3D) -> [PhoneJoint: Int] {
        if let jointIndices { return jointIndices }
        var map: [PhoneJoint: Int] = [:]
        let names = skeleton.definition.jointNames
        for (phoneJoint, arName) in ARStreamer.jointMap {
            if let i = names.firstIndex(of: arName) { map[phoneJoint] = i }
        }
        jointIndices = map
        return map
    }

    /// Our `PhoneJoint` → ARKit joint-name mapping. Names that don't resolve on a
    /// given device are skipped at runtime (and the real list is logged on the first
    /// body, so these can be corrected against the device).
    static let jointMap: [PhoneJoint: String] = [
        .root: "root",
        .hips: "hips_joint",
        .spine: "spine_4_joint",
        .chest: "spine_7_joint",
        .neck: "neck_1_joint",
        .head: "head_joint",
        .leftShoulder: "left_shoulder_1_joint",
        .leftElbow: "left_forearm_joint",
        .leftWrist: "left_hand_joint",
        .leftHand: "left_handMid_1_joint",
        .rightShoulder: "right_shoulder_1_joint",
        .rightElbow: "right_forearm_joint",
        .rightWrist: "right_hand_joint",
        .rightHand: "right_handMid_1_joint",
        .leftHip: "left_upLeg_joint",
        .leftKnee: "left_leg_joint",
        .leftAnkle: "left_foot_joint",
        .leftFoot: "left_toes_joint",
        .rightHip: "right_upLeg_joint",
        .rightKnee: "right_leg_joint",
        .rightAnkle: "right_foot_joint",
        .rightFoot: "right_toes_joint",
    ]
}
