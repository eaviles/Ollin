import Foundation
import ARKit
import simd

/// Runs ARKit body tracking and turns each tracked skeleton into a `PhonePoseSample`
/// — the named joints as 3D positions in meters, model space (the skeleton root at
/// the origin). ARKit delivers its delegate callbacks on the main thread, so the
/// `onPose` closure fires on main.
///
/// ARKit's full body skeleton has ~91 joints addressed by string name; we map a
/// practical subset onto `PhoneJoint`. A name that isn't present in the skeleton
/// returns a nil transform and is simply skipped, so the figure still streams the
/// joints that resolved — and the available names are logged once for tuning.
final class ARStreamer: NSObject, ARSessionDelegate {

    /// Fired (on the main thread) for each updated body, with its joints in meters.
    var onPose: ((PhonePoseSample) -> Void)?

    /// Whether this device supports ARKit body tracking (A12+, rear camera).
    var isSupported: Bool { ARBodyTrackingConfiguration.isSupported }

    private let session = ARSession()
    private var loggedJointNames = false

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARBodyTrackingConfiguration()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        for anchor in frame.anchors {
            guard let body = anchor as? ARBodyAnchor else { continue }
            let skeleton = body.skeleton

            if !loggedJointNames {
                loggedJointNames = true
                let names = skeleton.definition.jointNames.joined(separator: ", ")
                NSLog("Ollin capture — ARKit body joints: %@", names)
            }

            var joints: [PhoneJoint: SIMD3<Float>] = [:]
            for (phoneJoint, arName) in ARStreamer.jointMap {
                if let transform = skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: arName)) {
                    let p = transform.columns.3
                    joints[phoneJoint] = SIMD3<Float>(p.x, p.y, p.z)
                }
            }
            onPose?(PhonePoseSample(tracked: body.isTracked, timestamp: frame.timestamp, joints: joints))
        }
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
