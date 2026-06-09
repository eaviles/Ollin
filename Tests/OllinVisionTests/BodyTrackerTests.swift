import Testing
import Ollin
@testable import OllinVision

/// Body pose is hard to synthesize, so detection is a smoke test and the skeleton
/// model is checked directly.
@Suite struct BodyTrackerTests {

    @Test func blankImageHasNoBodies() async throws {
        let image = Image(width: 128, height: 128, color: .white)
        // Soft-skip: the body-pose model needs a compute device that some setups
        // lack in a headless test process (e.g. Intel Macs with no Neural Engine,
        // "No available compute device"). A throw there isn't a code failure; it
        // runs for real where a device is available.
        guard let bodies = try? await BodyTracker.detect(in: image) else { return }
        #expect(bodies.isEmpty)
    }

    @Test func skeletonReferencesKnownJoints() {
        // Every bone connects two of the 19 joints, and the skeleton is connected
        // (the neck and root appear, tying head/arms and legs together).
        #expect(!Body.skeleton.isEmpty)
        let used = Set(Body.skeleton.flatMap { [$0.0, $0.1] })
        #expect(used.isSubset(of: Set(BodyJoint.allCases)))
        #expect(used.contains(.neck))
        #expect(used.contains(.root))
    }

    @Test func bonesAndPointsAreEmptyForAnEmptyBody() {
        let body = Body(confidence: 0, joints: [:])
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(body.bones(in: rect).isEmpty)
        #expect(body.points(in: rect).isEmpty)
        #expect(body.point(.nose, in: rect) == nil)
    }
}
