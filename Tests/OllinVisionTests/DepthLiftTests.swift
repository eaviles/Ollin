import Testing
import Ollin
@testable import OllinVision

/// Pure-CPU checks on `Body.lifted(through:)` and `LiftedPose`: a 2D pose with
/// known normalized joints back-projected through a synthetic constant-depth
/// frame yields the expected metric joints, drops holes, and builds bones/cloud.
/// No Metal, no model — the `Body` is constructed directly — so these run on CI.
@Suite struct DepthLiftTests {

    /// A frame with constant `depth`, centered square intrinsics, at `n × n`.
    private func constantFrame(depth d: Float, n: Int = 10, f: Double = 10) -> RGBDFrame {
        RGBDFrame(color: Image(width: n, height: n, color: .white),
                  depth: Array(repeating: d, count: n * n), confidence: nil,
                  depthWidth: n, depthHeight: n,
                  intrinsics: CameraIntrinsics(fx: f, fy: f,
                                               cx: Double(n) / 2, cy: Double(n) / 2,
                                               width: n, height: n))
    }

    /// Nose high (y 0.8) and centered, neck a little lower (y 0.6) and centered.
    private var standingBody: Body {
        Body(confidence: 0.9, joints: [.nose: Vector2(0.5, 0.8), .neck: Vector2(0.5, 0.6)])
    }

    @Test func jointsLiftToMetricCameraSpace() {
        let pose = standingBody.lifted(through: constantFrame(depth: 2))
        #expect(pose.has(.nose))
        #expect(pose.has(.neck))
        #expect(abs(pose.confidence - 0.9) < 1e-9)

        // Centered in x; both at depth 2 (z = −2); the nose above the neck in y.
        let nose = pose.position(.nose)!
        let neck = pose.position(.neck)!
        #expect(abs(nose.x) < 1e-9)
        #expect(abs(nose.z - -2) < 1e-9)
        #expect(abs(neck.z - -2) < 1e-9)
        #expect(nose.y > neck.y)
    }

    @Test func aJointOverAHoleIsDropped() {
        // Depth holed across the top of the frame (rows 0–3), valid below. With no
        // sampling window the high nose (y 0.8 → a top row) finds no depth and is
        // dropped, while the lower neck (y 0.6 → row 4) survives.
        let n = 10
        var depth = [Float](repeating: 2, count: n * n)
        for row in 0..<4 { for col in 0..<n { depth[row * n + col] = 0 } }
        let frame = RGBDFrame(color: Image(width: n, height: n, color: .white),
                              depth: depth, confidence: nil, depthWidth: n, depthHeight: n,
                              intrinsics: CameraIntrinsics(fx: 10, fy: 10, cx: 5, cy: 5,
                                                           width: n, height: n))
        let pose = standingBody.lifted(through: frame, radius: 0)
        #expect(!pose.has(.nose))
        #expect(pose.has(.neck))
    }

    @Test func bonesConnectLiftedJoints() {
        // The neck–nose bone is the first in the skeleton; with both lifted it's drawn.
        let pose = standingBody.lifted(through: constantFrame(depth: 2))
        #expect(pose.bones().count == 1)
    }

    @Test func centerIsTheJointCentroid() {
        let pose = standingBody.lifted(through: constantFrame(depth: 2))
        let center = pose.center!
        let nose = pose.position(.nose)!, neck = pose.position(.neck)!
        #expect(abs(center.x - (nose.x + neck.x) / 2) < 1e-9)
        #expect(abs(center.y - (nose.y + neck.y) / 2) < 1e-9)
        #expect(abs(center.z - (nose.z + neck.z) / 2) < 1e-9)
    }

    @Test func cloudHasAtLeastOneSplatPerJoint() {
        let pose = standingBody.lifted(through: constantFrame(depth: 2))
        #expect(pose.cloud().count >= pose.positions.count)
        #expect(pose.positions.count == 2)
    }

    @Test func anEmptyPoseLiftsToNothing() {
        let pose = Body(confidence: 0, joints: [:]).lifted(through: constantFrame(depth: 2))
        #expect(pose.positions.isEmpty)
        #expect(pose.center == nil)
        #expect(pose.bones().isEmpty)
        #expect(pose.cloud().isEmpty)
    }
}
