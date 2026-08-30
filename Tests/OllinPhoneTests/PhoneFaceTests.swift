import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises `PhoneFace`'s accessors over staged values (GPU-free, CI-safe): the
/// face-local/world split for the eyes and the look-at point, the gaze directions,
/// and the texture coordinates riding the mesh. The numbers are chosen so each
/// expectation has one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) struct PhoneFaceTests {

    /// 90° about +y as a quaternion `(x, y, z, w)`: face-local +z lands on world +x.
    private var quarterTurnY: SIMD4<Float> {
        simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)).vector
    }

    /// A face standing at (1, 2, -3), turned a quarter turn about y, its left eye
    /// 3 cm out along face-local +x and its gaze converging half a meter ahead.
    private var turnedFace: PhoneFace {
        PhoneFace(headOrientation: quarterTurnY,
                  headPosition: Vector3(1, 2, -3),
                  leftEyePosition: Vector3(0.03, 0.05, 0.02),
                  lookAtPoint: Vector3(0, 0, 0.5))
    }

    @Test func faceLocalReadsIgnoreTheHead() {
        let face = turnedFace
        let eye = face.eyePosition(.left)
        #expect(abs(eye.x - 0.03) < 1e-5 && abs(eye.y - 0.05) < 1e-5 && abs(eye.z - 0.02) < 1e-5)
        #expect(abs(face.lookAtPoint.z - 0.5) < 1e-5)
    }

    @Test func worldReadsApplyTheHead() {
        // The quarter turn sends local (x, y, z) to (z, y, -x), then the head
        // position moves it: the eye to (1.02, 2.05, -3.03), the look-at point to
        // (1.5, 2, -3). A missing turn would leave the point behind the head.
        let face = turnedFace
        let eye = face.worldEyePosition(.left)
        #expect(abs(eye.x - 1.02) < 1e-5 && abs(eye.y - 2.05) < 1e-5 && abs(eye.z + 3.03) < 1e-5)
        let target = face.worldLookAtPoint
        #expect(abs(target.x - 1.5) < 1e-5 && abs(target.y - 2) < 1e-5 && abs(target.z + 3) < 1e-5)
    }

    @Test func aNeutralEyeGazesOutOfTheFace() {
        // Identity eye orientation: face-local gaze is +z, and the head's quarter
        // turn stands it along world +x.
        let face = turnedFace
        let local = face.gazeDirection(.left)
        #expect(abs(local.x) < 1e-5 && abs(local.y) < 1e-5 && abs(local.z - 1) < 1e-5)
        let world = face.worldGazeDirection(.left)
        #expect(abs(world.x - 1) < 1e-5 && abs(world.y) < 1e-5 && abs(world.z) < 1e-5)
    }

    @Test func aTurnedEyeTurnsItsGaze() {
        // An eye turned 30° about +y gazes at (sin 30°, 0, cos 30°) in face space.
        let q = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 1, 0)).vector
        let face = PhoneFace(leftEyeOrientation: q)
        let gaze = face.gazeDirection(.left)
        #expect(abs(gaze.x - 0.5) < 1e-5 && abs(gaze.y) < 1e-5 && abs(gaze.z - 0.8660254) < 1e-5)
    }

    @Test func theHeadTransformMatchesTheWorldReads() {
        // Standing the face-local eye through `headTransform` must agree with
        // `worldEyePosition`, so a mesh drawn under it holds the eyes inside it.
        let face = turnedFace
        let local = face.eyePosition(.left)
        let p = face.headTransform * SIMD4<Float>(Float(local.x), Float(local.y), Float(local.z), 1)
        let world = face.worldEyePosition(.left)
        #expect(abs(Double(p.x) - world.x) < 1e-5)
        #expect(abs(Double(p.y) - world.y) < 1e-5)
        #expect(abs(Double(p.z) - world.z) < 1e-5)
    }

    @Test func theMeshWearsItsTextureCoordinates() {
        // Aligned UVs ride onto the mesh; a misaligned set is dropped rather than
        // shifted onto the wrong vertices.
        let points = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
        let uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]
        let dressed = PhoneFace(meshPoints: points, triangleIndices: [0, 1, 2],
                                textureCoordinates: uvs)
        #expect(dressed.mesh().uvs.count == 3)
        #expect(dressed.meshUVs.count == 3)
        let misaligned = PhoneFace(meshPoints: points, triangleIndices: [0, 1, 2],
                                   textureCoordinates: [Vector2(0, 0)])
        #expect(misaligned.mesh().uvs.isEmpty)
    }

    @Test func aWireSampleCarriesTheEyesOntoTheFace() {
        // The decode-side init must map every new wire field onto the face.
        let sample = PhoneFaceSample(
            isTracked: true, timestamp: 4,
            headOrientation: SIMD4<Float>(0, 0, 0, 1),
            headPosition: SIMD3<Float>(0, 1.6, -0.4),
            blendShapes: [Float](repeating: 0, count: PhoneBlendShape.allCases.count),
            meshVertices: [SIMD3<Float>(0, 0, 0)],
            textureCoordinates: [SIMD2<Float>(0.25, 0.75)],
            leftEyePosition: SIMD3<Float>(0.032, 0.03, 0.025),
            rightEyePosition: SIMD3<Float>(-0.032, 0.03, 0.025),
            lookAtPoint: SIMD3<Float>(0, -0.01, 0.6))
        let face = PhoneFace(sample)
        #expect(abs(face.eyePosition(.left).x - 0.032) < 1e-6)
        #expect(abs(face.eyePosition(.right).x + 0.032) < 1e-6)
        #expect(abs(face.lookAtPoint.z - 0.6) < 1e-6)
        #expect(face.meshUVs.count == 1)
        #expect(abs(face.meshUVs[0].y - 0.75) < 1e-6)
    }
}
