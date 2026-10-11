import Testing
import Foundation
@testable import OllinVision

/// How every tracker turns a failed run into what a sketch reads, the path a
/// Mac without a Neural Engine (a CI runner) takes every run and a desk whose
/// Vision stack works never does. One shape
/// per kind of failure: a missing capability is said as a sentence and holds,
/// a bad frame is passed over, and a run that works again clears the sentence.
@Suite
struct VisionStatusTests {

    private let noComputeDevice = NSError(
        domain: "com.apple.Vision", code: 12,
        userInfo: [NSLocalizedDescriptionKey: "No available compute device for VNComputeStageMain"])
    private let badFrame = NSError(
        domain: "com.apple.Vision", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "The image buffer is not valid"])

    @Test func aTrackerStartsAvailable() {
        let status = VisionStatus("hand tracking")
        #expect(status.isAvailable)
        #expect(status.reason == nil)
    }

    @Test func aMissingComputeDeviceIsSaidAndHolds() {
        let status = VisionStatus("hand tracking")
        status.recordFailure(noComputeDevice)
        #expect(!status.isAvailable)
        let reason = status.reason ?? ""
        #expect(reason.hasPrefix("hand tracking can't run on this Mac"), Comment(rawValue: reason))
        #expect(reason.contains("Neural Engine"), Comment(rawValue: reason))
        // A bad frame after it does not change what is said.
        status.recordFailure(badFrame)
        #expect(status.reason == reason)
    }

    @Test func aBadFrameIsPassedOver() {
        let status = VisionStatus("hand tracking")
        status.recordFailure(badFrame)
        status.recordFailure(CancellationError())
        #expect(status.isAvailable)
        #expect(status.reason == nil)
    }

    @Test func aRunThatWorksAgainClearsTheSentence() {
        let status = VisionStatus("hand tracking")
        status.recordFailure(noComputeDevice)
        #expect(!status.isAvailable)
        status.recordSuccess()
        #expect(status.isAvailable)
        #expect(status.reason == nil)
    }

    @Test func aMissingModelIsSaidInItsOwnWords() {
        let status = VisionStatus("object detection")
        status.markUnavailable("object detection has no model: Detector.mlmodelc is not in the bundle")
        #expect(!status.isAvailable)
        #expect(status.reason == "object detection has no model: Detector.mlmodelc is not in the bundle")
    }
}
