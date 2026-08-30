import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises `PhoneHand`'s accessors over staged wire samples (GPU-free, CI-safe):
/// the 2D canvas mapping, the lifted 3D positions, the bones that skip an unlifted
/// end, and the gesture helpers. The numbers are chosen so each expectation has
/// one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) struct PhoneHandTests {

    /// A right hand with a lifted wrist and index tip, plus a thumb tip the phone
    /// could not lift (2D only, over a depth hole).
    private var liftedHand: PhoneHand {
        PhoneHand(PhoneHandSample(
            isTracked: true, timestamp: 2, chirality: .right, confidence: 0.9,
            joints: [
                .wrist: PhoneHandJointSample(point: SIMD2<Float>(0.5, 0.5), confidence: 0.95,
                                             hasWorldPosition: true,
                                             worldPosition: SIMD3<Float>(0, 1, -1)),
                .indexTip: PhoneHandJointSample(point: SIMD2<Float>(0.6, 0.7), confidence: 0.9,
                                                hasWorldPosition: true,
                                                worldPosition: SIMD3<Float>(0, 1.2, -1)),
                .thumbTip: PhoneHandJointSample(point: SIMD2<Float>(0.4, 0.6), confidence: 0.8),
            ]))
    }

    @Test func pointsMapUprightIntoTheCanvas() throws {
        // Normalized (0.25, 0.75), lower-left origin, into a 100x200 rectangle at
        // the origin: x = 25, and y flips to (1 - 0.75) * 200 = 50.
        let hand = PhoneHand(PhoneHandSample(
            isTracked: true, timestamp: 0, joints: [
                .wrist: PhoneHandJointSample(point: SIMD2<Float>(0.25, 0.75)),
            ]))
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 200)
        let p = try #require(hand.point(.wrist, in: rect))
        #expect(abs(p.x - 25) < 1e-6)
        #expect(abs(p.y - 50) < 1e-6)
        // And the rectangle's corner offsets shift the mapped point with it.
        let shifted = try #require(hand.point(.wrist, in: Rectangle(x: 10, y: 20, width: 100, height: 200)))
        #expect(abs(shifted.x - 35) < 1e-6)
        #expect(abs(shifted.y - 70) < 1e-6)
    }

    @Test func liftedJointsReportWorldPositions() throws {
        let hand = liftedHand
        #expect(hand.hasWorldPositions)
        let wrist = try #require(hand.position(.wrist))
        #expect(wrist == Vector3(0, 1, -1))
        // The thumb tip was reported in 2D but not lifted: present, no position.
        #expect(hand.has(.thumbTip))
        #expect(hand.position(.thumbTip) == nil)
        // A joint the model never placed is absent entirely.
        #expect(!hand.has(.littleTip))
        #expect(hand.confidence(of: .littleTip) == nil)
    }

    @Test func bonesSkipAnUnliftedEnd() {
        // 3D bones need both ends lifted. The wrist and index tip are lifted but
        // are not adjacent in the skeleton, and every bone touching the 2D-only
        // thumb tip must drop out, so no 3D bone survives.
        #expect(liftedHand.bones().isEmpty)
        // The 2D overlay only needs both ends reported: wrist-to-thumbCMC is
        // missing its middle joints, so only bones with both ends present map.
        let rect = Rectangle(x: 0, y: 0, width: 1, height: 1)
        #expect(liftedHand.bones(in: rect).isEmpty)
    }

    @Test func adjacentLiftedJointsMakeABone() throws {
        // Lift two joints that share a skeleton bone and it comes through in 3D.
        let hand = PhoneHand(PhoneHandSample(
            isTracked: true, timestamp: 0, joints: [
                .indexDIP: PhoneHandJointSample(point: SIMD2<Float>(0.5, 0.5),
                                                hasWorldPosition: true,
                                                worldPosition: SIMD3<Float>(0, 1, -1)),
                .indexTip: PhoneHandJointSample(point: SIMD2<Float>(0.5, 0.6),
                                                hasWorldPosition: true,
                                                worldPosition: SIMD3<Float>(0, 1.5, -1)),
            ]))
        let bones = hand.bones()
        #expect(bones.count == 1)
        let bone = try #require(bones.first)
        #expect(bone.0 == Vector3(0, 1, -1))
        #expect(bone.1 == Vector3(0, 1.5, -1))
    }

    @Test func centerAveragesOnlyTheLiftedJoints() {
        // (0,1,-1) and (0,1.2,-1) average to (0,1.1,-1); the 2D-only thumb tip
        // must not drag the centroid to the origin.
        let c = liftedHand.center
        #expect(abs(c.x) < 1e-6)
        #expect(abs(c.y - 1.1) < 1e-6)
        #expect(abs(c.z + 1) < 1e-6)
    }

    @Test func pinchNeedsBothTipsLifted() throws {
        // The staged hand's thumb tip is 2D-only, so there is no pinch to measure.
        #expect(liftedHand.pinchDistance == nil)
        let pinching = PhoneHand(PhoneHandSample(
            isTracked: true, timestamp: 0, joints: [
                .thumbTip: PhoneHandJointSample(point: SIMD2<Float>(0.5, 0.5),
                                                hasWorldPosition: true,
                                                worldPosition: SIMD3<Float>(0, 1, -1)),
                .indexTip: PhoneHandJointSample(point: SIMD2<Float>(0.5, 0.5),
                                                hasWorldPosition: true,
                                                worldPosition: SIMD3<Float>(0.03, 1.04, -1)),
            ]))
        let d = try #require(pinching.pinchDistance)
        #expect(abs(d - 0.05) < 1e-6)          // a 3-4-5 triangle, scaled down
    }

    @Test func cloudIsEmptyWithoutWorldPositions() {
        let flat = PhoneHand(PhoneHandSample(
            isTracked: true, timestamp: 0, joints: [
                .wrist: PhoneHandJointSample(point: SIMD2<Float>(0.5, 0.5)),
            ]))
        #expect(flat.cloud().isEmpty)
        #expect(!flat.hasWorldPositions)
    }

    @Test func skeletonReachesEveryJointOnce() {
        // 20 bones: every joint but the wrist appears exactly once as a bone's far
        // end, so each finger is one unbroken chain out of the wrist.
        #expect(PhoneHand.skeleton.count == 20)
        let ends = PhoneHand.skeleton.map(\.1)
        #expect(Set(ends).count == 20)
        #expect(!ends.contains(.wrist))
    }
}
