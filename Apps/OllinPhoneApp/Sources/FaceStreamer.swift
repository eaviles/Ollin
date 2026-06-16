import Foundation
import ARKit
import simd

/// Runs ARKit face tracking (front TrueDepth camera) and turns each tracked face
/// into a `PhoneFaceSample` — the 52 expression blendshapes, the deforming mesh in
/// face-local space, and the head's world pose. ARKit delivers its delegate
/// callbacks on the main thread, so `onFace` fires on main.
///
/// Face tracking uses the front camera and so is mutually exclusive with the
/// rear-camera body tracking (`ARStreamer`); the app runs one or the other.
final class FaceStreamer: NSObject, ARSessionDelegate {

    /// Fired (on the main thread) for each updated face.
    var onFace: ((PhoneFaceSample) -> Void)?

    /// Whether this device supports ARKit face tracking (a TrueDepth front camera).
    var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    private let session = ARSession()

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        for anchor in frame.anchors {
            guard let face = anchor as? ARFaceAnchor else { continue }

            // 52 coefficients in PhoneBlendShape order; a shape ARKit didn't report
            // reads as 0 (neutral).
            let blendShapes = FaceStreamer.blendShapeOrder.map { location in
                Float(truncating: face.blendShapes[location] ?? 0)
            }

            // The mesh, in face-local space (meters, centered on the face).
            let vertices = face.geometry.vertices.map { SIMD3<Float>($0.x, $0.y, $0.z) }

            // Head pose in world space: rotation as a quaternion + translation.
            let q = simd_quatf(face.transform)
            let t = face.transform.columns.3

            onFace?(PhoneFaceSample(
                tracked: face.isTracked,
                timestamp: frame.timestamp,
                headOrientation: SIMD4<Float>(q.vector.x, q.vector.y, q.vector.z, q.vector.w),
                headPosition: SIMD3<Float>(t.x, t.y, t.z),
                blendShapes: blendShapes,
                meshVertices: vertices))
        }
    }

    /// ARKit's `BlendShapeLocation`s in `PhoneBlendShape` order — the index into this
    /// list *is* the `PhoneBlendShape.rawValue`, so the wire carries the coefficients
    /// positionally with no keys. Kept in lock-step with the enum (52 entries).
    static let blendShapeOrder: [ARFaceAnchor.BlendShapeLocation] = [
        // Eyes — left
        .eyeBlinkLeft, .eyeLookDownLeft, .eyeLookInLeft, .eyeLookOutLeft,
        .eyeLookUpLeft, .eyeSquintLeft, .eyeWideLeft,
        // Eyes — right
        .eyeBlinkRight, .eyeLookDownRight, .eyeLookInRight, .eyeLookOutRight,
        .eyeLookUpRight, .eyeSquintRight, .eyeWideRight,
        // Jaw
        .jawForward, .jawLeft, .jawRight, .jawOpen,
        // Mouth
        .mouthClose, .mouthFunnel, .mouthPucker, .mouthLeft, .mouthRight,
        .mouthSmileLeft, .mouthSmileRight, .mouthFrownLeft, .mouthFrownRight,
        .mouthDimpleLeft, .mouthDimpleRight, .mouthStretchLeft, .mouthStretchRight,
        .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
        .mouthPressLeft, .mouthPressRight, .mouthLowerDownLeft, .mouthLowerDownRight,
        .mouthUpperUpLeft, .mouthUpperUpRight,
        // Brows
        .browDownLeft, .browDownRight, .browInnerUp, .browOuterUpLeft, .browOuterUpRight,
        // Cheeks
        .cheekPuff, .cheekSquintLeft, .cheekSquintRight,
        // Nose
        .noseSneerLeft, .noseSneerRight,
        // Tongue
        .tongueOut,
    ]
}
