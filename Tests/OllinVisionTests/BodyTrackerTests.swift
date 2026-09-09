import Testing
import Ollin
import OllinSamplePhotos
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

    /// The bundled figure photographs are here to be read: each holds one
    /// person whose joints the model should find, including the one standing on
    /// a hand. Read in one test rather than four parallel ones, because Vision's
    /// body-pose model loads on the first request that needs it and answers
    /// requests that arrive while it loads with nothing, which four at once
    /// reliably provoked.
    @Test func everyFigurePhotographYieldsItsBody() async throws {
        // Soft-skip where the model has no compute device, as above.
        guard (try? await BodyTracker.detect(in: SamplePhoto.reaching.load())) != nil else { return }

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
