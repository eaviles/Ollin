import Foundation
import ARKit
import simd

/// Runs ARKit face tracking (front TrueDepth camera) and turns the tracked faces
/// (up to 3 at once) into `PhoneFaceSample`s: the 52 expression blendshapes, the
/// deforming mesh (with its topology and texture coordinates) in face-local space,
/// each head's world pose, the two eye poses, and the look-at point the eyes
/// converge on. ARKit delivers its delegate callbacks on the main thread, so
/// `onFaces` fires on main.
///
/// Face tracking uses the front camera and so is mutually exclusive with the
/// rear-camera body tracking (`ARStreamer`); the app runs one or the other.
final class FaceStreamer: NSObject, ARSessionDelegate, LightReporting {

    /// Fired (on the main thread) each frame with the complete current face set —
    /// possibly empty when no face is in view, so the Mac side clears it.
    var onFaces: (([PhoneFaceSample]) -> Void)?

    /// A face session is the only one that reads a direction for the light, because
    /// ARKit knows the shape it is looking at well enough to read the shading on it.
    let lightSampler = LightSampler()

    /// Whether this device supports ARKit face tracking (a TrueDepth front camera).
    var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    private let session = ARSession()

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARFaceTrackingConfiguration()
        // Track as many faces as the hardware allows (3 on TrueDepth), capped so the
        // wire's one-byte face count and the per-frame mesh payload stay bounded.
        config.maximumNumberOfTrackedFaces = min(3, ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces)
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lightSampler.report(frame)
        let faces = frame.anchors.compactMap { anchor -> PhoneFaceSample? in
            guard let face = anchor as? ARFaceAnchor else { return nil }

            // 52 coefficients in PhoneBlendShape order; a shape ARKit didn't report
            // reads as 0 (neutral).
            let blendShapes = FaceStreamer.blendShapeOrder.map { location in
                Float(truncating: face.blendShapes[location] ?? 0)
            }

            // The mesh, in face-local space (meters, centered on the face), plus its
            // triangle topology (constant per device; ARKit's indices are vertex
            // indices, always non-negative) and the per-vertex texture coordinates
            // (constant too; only the vertex positions deform frame to frame).
            let vertices = face.geometry.vertices.map { SIMD3<Float>($0.x, $0.y, $0.z) }
            let indices = face.geometry.triangleIndices.map { UInt16($0) }
            let uvs = face.geometry.textureCoordinates.map { SIMD2<Float>($0.x, $0.y) }

            // Head pose in world space: rotation as a quaternion + translation.
            let q = simd_quatf(face.transform)
            let t = face.transform.columns.3

            // The eyes and the gaze, all face-local (relative to the head): each eye
            // a rigid transform, the look-at point the two eyes converge on.
            let leftQ = simd_quatf(face.leftEyeTransform)
            let leftT = face.leftEyeTransform.columns.3
            let rightQ = simd_quatf(face.rightEyeTransform)
            let rightT = face.rightEyeTransform.columns.3

            return PhoneFaceSample(
                tracked: face.isTracked,
                timestamp: frame.timestamp,
                headOrientation: SIMD4<Float>(q.vector.x, q.vector.y, q.vector.z, q.vector.w),
                headPosition: SIMD3<Float>(t.x, t.y, t.z),
                blendShapes: blendShapes,
                meshVertices: vertices,
                triangleIndices: indices,
                textureCoordinates: uvs,
                leftEyeOrientation: SIMD4<Float>(leftQ.vector.x, leftQ.vector.y,
                                                 leftQ.vector.z, leftQ.vector.w),
                leftEyePosition: SIMD3<Float>(leftT.x, leftT.y, leftT.z),
                rightEyeOrientation: SIMD4<Float>(rightQ.vector.x, rightQ.vector.y,
                                                  rightQ.vector.z, rightQ.vector.w),
                rightEyePosition: SIMD3<Float>(rightT.x, rightT.y, rightT.z),
                lookAtPoint: face.lookAtPoint)
        }
        onFaces?(faces)
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
