import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises `PhoneBody`'s accessors over staged wire samples (GPU-free, CI-safe):
/// the model/world split, the per-joint orientation transforms, and the tracked
/// flags. The numbers are chosen so each expectation has one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) struct PhoneBodyTests {

    /// 90° about +y (right-handed): +x lands on -z.
    private var quarterTurnY: simd_float4x4 {
        simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)))
    }

    /// A body standing at (1, 2, 3), turned a quarter turn about y, with a head
    /// joint 1 m up and a hip at the root.
    private var turnedBody: PhoneBody {
        var anchor = quarterTurnY
        anchor.columns.3 = SIMD4<Float>(1, 2, 3, 1)
        return PhoneBody(PhonePoseSample(
            tracked: true, timestamp: 1, anchor: anchor, scaleFactor: 0.9,
            joints: [
                .head: PhoneJointSample(position: SIMD3<Float>(0, 1, 0)),
                .hips: PhoneJointSample(position: SIMD3<Float>(1, 0, 0), tracked: false),
            ]))
    }

    @Test func modelPositionsIgnoreTheAnchor() throws {
        let head = try #require(turnedBody.position(.head))
        #expect(abs(head.x) < 1e-5 && abs(head.y - 1) < 1e-5 && abs(head.z) < 1e-5)
    }

    @Test func worldPositionsApplyTheAnchor() throws {
        // The head sits on the rotation axis: it only translates, to (1, 3, 3).
        let head = try #require(turnedBody.worldPosition(.head))
        #expect(abs(head.x - 1) < 1e-5 && abs(head.y - 3) < 1e-5 && abs(head.z - 3) < 1e-5)
        // The hip sits 1 m along model +x: the quarter turn sends it to -z, so it
        // stands at (1, 2, 2). A missing turn would read (2, 2, 3).
        let hip = try #require(turnedBody.worldPosition(.hips))
        #expect(abs(hip.x - 1) < 1e-5 && abs(hip.y - 2) < 1e-5 && abs(hip.z - 2) < 1e-5)
    }

    @Test func scaleAndTrackedFlagsSurvive() {
        let body = turnedBody
        #expect(abs(body.scaleFactor - 0.9) < 1e-6)
        #expect(body.isJointTracked(.head))
        #expect(!body.isJointTracked(.hips))       // the rig filled it in
        #expect(!body.isJointTracked(.leftFoot))   // not reported at all
    }

    @Test func jointTransformComposesOrientationAndPosition() throws {
        // A wrist at (0, 1, 0) turned 90° about +z: its local +x must come out
        // pointing along +y, from the joint's own position.
        let q = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let body = PhoneBody(PhonePoseSample(
            tracked: true, timestamp: 0,
            joints: [.leftWrist: PhoneJointSample(position: SIMD3<Float>(0, 1, 0),
                                                  orientation: q.vector)]))
        let m = try #require(body.modelTransform(.leftWrist))
        let tip = m * SIMD4<Float>(1, 0, 0, 1)
        #expect(abs(tip.x) < 1e-5 && abs(tip.y - 2) < 1e-5 && abs(tip.z) < 1e-5)
    }

    @Test func worldJointTransformStandsInTheWorld() throws {
        // The identity-oriented head, through the body's quarter turn and offset:
        // its transform's position column must match `worldPosition`.
        let body = turnedBody
        let m = try #require(body.worldTransform(of: .head))
        let p = try #require(body.worldPosition(.head))
        #expect(abs(Double(m.columns.3.x) - p.x) < 1e-5)
        #expect(abs(Double(m.columns.3.y) - p.y) < 1e-5)
        #expect(abs(Double(m.columns.3.z) - p.z) < 1e-5)
    }

    @Test func worldCenterIsTheTransformedCentroid() {
        // Centroid of (0,1,0) and (1,0,0) is (0.5, 0.5, 0); the quarter turn sends
        // it to (0, 0.5, -0.5), and the offset stands it at (1, 2.5, 2.5).
        let c = turnedBody.worldCenter
        #expect(abs(c.x - 1) < 1e-5 && abs(c.y - 2.5) < 1e-5 && abs(c.z - 2.5) < 1e-5)
    }
}
