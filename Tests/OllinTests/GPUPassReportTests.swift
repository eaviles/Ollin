@testable import Ollin
import Foundation
import Metal
import Testing

/// A failed frame says which pass failed. A command buffer made to keep each
/// pass's outcome hands them back with its error, and the failure's sentence
/// names the pass the failure began in, by the name the pass was given and by
/// its place in the frame. The sentences are built from records made here, so
/// nothing in these tests has to fail on the GPU.
@Suite
@MainActor
struct GPUPassReportTests {
    /// One pass's record, the shape Metal hands back.
    private final class PassRecord: NSObject, MTLCommandBufferEncoderInfo {
        let label: String
        let debugSignposts: [String] = []
        let errorState: MTLCommandEncoderErrorState
        init(_ label: String, _ errorState: MTLCommandEncoderErrorState) {
            self.label = label
            self.errorState = errorState
        }
    }

    /// A command buffer error carrying `passes`, with the system's own code for
    /// a frame it blamed for a hang.
    private func failure(_ passes: [PassRecord]?) -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: "Caused GPU Hang Error"]
        if let passes { info[MTLCommandBufferEncoderInfoErrorKey] = passes }
        return NSError(domain: MTLCommandBufferErrorDomain, code: 3, userInfo: info)
    }

    @Test func aFaultedPassIsNamedAloneWithItsPlace() {
        let report = GPUFailures.passReport(failure([
            PassRecord("traced scene: triangles", .completed),
            PassRecord("encodeShadowPass", .completed),
            PassRecord("canvas (headless)", .faulted),
            PassRecord("present", .affected),
        ]))
        #expect(report == "; the pass that failed: \"canvas (headless)\" (3 of 4)")
    }

    @Test func aPassWithNoNameIsFoundByItsPlace() {
        let report = GPUFailures.passReport(failure([
            PassRecord("first", .completed), PassRecord("", .faulted),
        ]))
        #expect(report == "; the pass that failed: an unnamed pass (2 of 2)")
    }

    @Test func withNoneFaultedTheRunningPassesAreListedAndTheRestCounted() {
        let running = (1...6).map { PassRecord("pass \($0)", .affected) }
        let report = GPUFailures.passReport(failure([PassRecord("done", .completed)] + running))
        #expect(report == "; the GPU names no pass as the cause, and these were running: "
                + "\"pass 1\" (2 of 7), \"pass 2\" (3 of 7), \"pass 3\" (4 of 7), \"pass 4\" (5 of 7), "
                + "and 2 more")
    }

    @Test func aFrameThatNeverStartedSaysHowFarItGot() {
        let report = GPUFailures.passReport(failure([
            PassRecord("a", .completed), PassRecord("b", .completed), PassRecord("c", .pending),
        ]))
        #expect(report == "; the GPU names no pass as the cause (2 of 3 had finished)")
    }

    @Test func aCommandBufferThatKeptNoRecordAddsNothing() {
        #expect(GPUFailures.passReport(failure(nil)).isEmpty)
        #expect(GPUFailures.passReport(failure([])).isEmpty)
    }

    @Test func theReportIsTheTailOfTheFailuresSentence() {
        let (sentence, overflow) = GPUFailures.describe(failure([PassRecord("lit pass", .faulted)]))
        #expect(sentence == "a frame failed on the GPU and came back empty: Caused GPU Hang Error"
                + "; the pass that failed: \"lit pass\" (1 of 1)")
        #expect(!overflow)
        // A failure with no record carries no tail.
        #expect(GPUFailures.describe(failure(nil)).sentence
                == "a frame failed on the GPU and came back empty: Caused GPU Hang Error")
    }

    @Test func aPassTakesItsMakersNameWithoutTheSignature() {
        #expect(GPUFailures.passName("encodeShadowPass(_:into:meshBuffer:)") == "encodeShadowPass")
        #expect(GPUFailures.passName("canvas (headless)") == "canvas (headless)")
        #expect(GPUFailures.passName("present") == "present")
        #expect(GPUFailures.passName("").isEmpty)
    }

    /// A drive that waits for its frame asks for the record, and a pass made on
    /// such a command buffer carries its name. A command buffer that keeps no
    /// record names nothing, which is the live window's frame until one fails.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aReportingCommandBufferNamesItsPasses() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.renderTarget]
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store

        let reporting = try #require(renderer.makeCommandBuffer())
        #expect(reporting.reportsPasses)
        let named = try #require(renderer.countedEncoder(reporting, pass, caller: "canvas (test)"))
        #expect(named.label == "canvas (test)")
        named.endEncoding()
        let blit = try #require(reporting.namedBlitEncoder())
        #expect(blit.label == "aReportingCommandBufferNamesItsPasses")
        blit.endEncoding()
        reporting.commit()
        reporting.waitUntilCompleted()
        #expect(reporting.status == .completed)

        let plain = try #require(renderer.makeCommandBuffer(reportingPasses: false))
        #expect(!plain.reportsPasses)
        let unnamed = try #require(renderer.countedEncoder(plain, pass, caller: "canvas (test)"))
        #expect(unnamed.label == nil)
        unnamed.endEncoding()
        plain.commit()
        plain.waitUntilCompleted()
        #expect(plain.status == .completed)
    }

    /// The live window's frames keep no record until one of them has failed.
    @Test func theLiveWindowAsksOnlyAfterAFailure() {
        let failures = GPUFailures()
        #expect(!failures.hasFailed)
        failures.markSpent("a frame was read as a GPU hang, planted by this test")
        #expect(failures.hasFailed)
        failures.clearSpent()
        #expect(failures.hasFailed, "a new queue does not forget that a frame failed")
    }
}
