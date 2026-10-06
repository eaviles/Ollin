import Testing
import Ollin
import OllinSamplePhotos
@testable import OllinVision

/// Body pose is hard to synthesize, so detection is a smoke test and the skeleton
/// model is checked directly.
@Suite struct BodyTrackerTests {

    /// The model over a blank frame, made once: `nil` where the body-pose model
    /// has no compute device (a headless process on a Mac with no Neural
    /// Engine says "No available compute device"), which `modelRuns` reports
    /// as the skip it is.
    private static let blank = Task<[Body]?, Never> {
        try? await BodyTracker.detect(in: Image(width: 128, height: 128, color: .white))
    }

    private static let modelRuns: ConditionTrait = .enabled("the body-pose model has no compute device here") {
        await BodyTrackerTests.blank.value != nil
    }

    @Test(modelRuns) func blankImageHasNoBodies() async throws {
        let bodies = try #require(await Self.blank.value)
        #expect(bodies.isEmpty)
    }

    /// The bundled figure photographs are here to be read: each holds one
    /// person whose joints the model should find, including the one standing on
    /// a hand. Read in one test rather than four parallel ones, because Vision's
    /// body-pose model loads on the first request that needs it and answers
    /// requests that arrive while it loads with nothing, which four at once
    /// reliably provoked.
    @Test(modelRuns) func everyFigurePhotographYieldsItsBody() async throws {
        // The wrestler's ankles are behind the ring rope, so the bar is most of
        // the skeleton rather than all of it.
        for photo in [SamplePhoto.reaching, .wrestler, .dancer, .handstand] {
            let bodies = try await BodyTracker.detect(in: photo.load())
            #expect(!bodies.isEmpty, "\(photo.name)")
            let joints = bodies.map { body in BodyJoint.allCases.count(where: body.has) }.max() ?? 0
            #expect(joints >= 16, "\(photo.name) found \(joints) joints")
        }
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
