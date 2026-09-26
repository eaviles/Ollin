import Testing
import Ollin
@testable import OllinVision

/// Exercises the still-image detection path end to end — building an `Image`,
/// running the Vision request, and decoding the result — without a camera or any
/// bundled photo. A blank image deterministically has no faces, so this verifies
/// the plumbing (request runs, result decodes) and stays CI-safe.
@Suite struct FaceTrackerTests {

    @Test func detectOnBlankImageReturnsNoFaces() async throws {
        let image = Image(width: 128, height: 128, color: .white)
        let faces = try await FaceTracker.detect(in: image)
        #expect(faces.isEmpty)
    }

    @Test func detectReturnsCleanlyOnTinyImage() async throws {
        // The case: a degenerate 8×8 input does not throw (or trap); any result is fine.
        let image = Image(width: 8, height: 8, color: .black)
        _ = try await FaceTracker.detect(in: image)
    }
}
