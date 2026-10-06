@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import ImageIO

/// Correctness probes for the time budget on a traced frame (`--pt-seconds`,
/// `PathTracing.secondsPerFrame`): the clock ends a frame's trace at the sample
/// where the time runs out, and the frame it leaves is a fixed render of the count
/// it reached.
///
/// The budget reads the wall clock, so no claim here is about how many samples a
/// budget buys; every claim is about what the frame is once the clock has spoken.
/// The one claim that touches time at all asks only that the clock, and not the
/// cap, was what stopped the frame, with a margin a loaded machine cannot cross.
@Suite(.serialized)
@MainActor
struct TracedBudgetTests {

    /// The probe scene: the reuse suite's still room (a matte sphere on a floor
    /// under one small bright panel), 160 pixels square.
    private func room() -> Sketch { TracedReuseTests.Probe.make(.still) }

    /// A cap no budget of a fraction of a second reaches on the probe, so the
    /// clock is the only thing that can end the frame.
    private static let farCap = 100_000

    /// What a traced still left behind: its pixels, the `pathTraced` object of its
    /// recipe (read through the file, the route a frame takes), and the trace's
    /// own report of itself.
    private struct Still {
        var image: CGImage
        var traced: [String: Any]
        var report: PathTraceReport
    }

    private func still(_ settings: PathTracing) throws -> Still {
        OllinApp.pathTracedExport = settings
        defer { OllinApp.pathTracedExport = nil }
        let path = ollinTempPath("ollin-pt-budget-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try OllinApp.export(room(), to: path, frame: 1)
        let report = try #require(OllinApp.lastPathTraceReport)
        // Read through the bytes, not the URL: an image source decodes from its file
        // when the image is first drawn, and the file is gone by then.
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let png = try #require(props[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        let text = try #require(png[kCGImagePropertyPNGDescription] as? String)
        let recipe = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let traced = try #require(recipe["pathTraced"] as? [String: Any])
        return Still(image: image, traced: traced, report: report)
    }

    // MARK: - The claims

    /// The budget is asked for, never assumed, and what the settings derive from
    /// it is pinned: a frame's time is the budget, or the history's worth of it on
    /// the first frame of a reusing run, and the floor the clock may not cut under
    /// is the named minimum, else one sample.
    @Test func theBudgetIsOffUnlessAskedForAndItsTermsArePinned() {
        #expect(PathTracing(samplesPerPixel: 8).secondsPerFrame == 0)
        #expect(PathTracing(samplesPerPixel: 8).isBudgeted == false)
        #expect(PathTracing(samplesPerPixel: 8, secondsPerFrame: -3).secondsPerFrame == 0)
        #expect(PathTracing(samplesPerPixel: 8, secondsPerFrame: .nan).secondsPerFrame == 0)
        #expect(PathTracing(samplesPerPixel: 8, secondsPerFrame: 10).isBudgeted)
        #expect(PathTracing(samplesPerPixel: 8).timeBudget(tracingTheHistory: true) == .infinity)
        #expect(PathTracing(samplesPerPixel: 8, secondsPerFrame: 10).timeBudget(tracingTheHistory: false) == 10)
        #expect(PathTracing(samplesPerPixel: 8, secondsPerFrame: 10).timeBudget(tracingTheHistory: true) == 10)
        let reusing = PathTracing(samplesPerPixel: 32, reusedFrames: 8, secondsPerFrame: 10)
        #expect(reusing.timeBudget(tracingTheHistory: false) == 10)
        #expect(reusing.timeBudget(tracingTheHistory: true) == 80)
        #expect(PathTracing(samplesPerPixel: 64, secondsPerFrame: 1).timeFloor == 1)
        #expect(PathTracing(samplesPerPixel: 64, minSamplesPerPixel: 24, secondsPerFrame: 1).timeFloor == 24)
        #expect(PathTracing(samplesPerPixel: 16, minSamplesPerPixel: 24, secondsPerFrame: 1).timeFloor == 16)
    }

    /// The headline claim: a frame the clock ends at N samples is a fixed render of
    /// N samples, byte for byte, and the recipe records the budget and N, so the
    /// frame reproduces with the count in place of the budget. The cap is far past
    /// what the budget reaches, so the clock is what stopped it, which the trace's
    /// own time says too, with a margin no loaded machine crosses against a cap of
    /// a hundred thousand.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aBudgetedFrameIsAFixedRenderOfTheCountItReached() throws {
        let budget = 0.4
        let budgeted = try still(PathTracing(samplesPerPixel: Self.farCap, secondsPerFrame: budget))
        let reached = try #require(budgeted.report.reachedSamplesPerPixel)
        #expect(reached > 1 && reached < Self.farCap, "the clock let the frame reach \(reached)")
        let seconds = try #require(budgeted.report.secondsTraced)
        #expect(seconds > 0 && seconds < budget + 3, "the trace took \(seconds) s against a budget of \(budget)")
        #expect(budgeted.traced["seconds"] as? Double == budget)
        #expect(budgeted.traced["reachedSamples"] as? Int == reached)
        #expect(budgeted.traced["samples"] as? Int == Self.farCap)

        let fixed = try still(PathTracing(samplesPerPixel: reached))
        #expect(pixels(of: fixed.image) == pixels(of: budgeted.image))
        #expect(fixed.report.reachedSamplesPerPixel == nil)
        #expect(fixed.report.secondsTraced == nil)
        #expect(fixed.traced["seconds"] == nil)
        #expect(fixed.traced["reachedSamples"] == nil)
    }

    /// The floor holds against the clock: a frame given almost no time and a
    /// minimum of 24 traces exactly 24 samples, and is the fixed render of 24.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFloorHoldsAgainstTheClock() throws {
        let floored = try still(PathTracing(samplesPerPixel: Self.farCap, minSamplesPerPixel: 24,
                                            secondsPerFrame: 0.0001))
        #expect(floored.report.reachedSamplesPerPixel == 24)
        #expect(floored.traced["reachedSamples"] as? Int == 24)
        let fixed = try still(PathTracing(samplesPerPixel: 24))
        #expect(pixels(of: fixed.image) == pixels(of: floored.image))
    }

    /// Under the per-pixel stop the clock cuts the rounds where it falls, and the
    /// frame is the stop's own frame at that cap: the same threshold and minimum
    /// with the reached count as the cap render the same bytes and report the
    /// same mean, since the checks fall at the same sample indices either way.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aBudgetUnderTheStopIsTheStopAtTheCountItReached() throws {
        let budgeted = try still(PathTracing(samplesPerPixel: Self.farCap, noiseThreshold: 0.03,
                                             minSamplesPerPixel: 16, secondsPerFrame: 0.4))
        let reached = try #require(budgeted.report.reachedSamplesPerPixel)
        #expect(reached >= 16 && reached < Self.farCap, "the clock let the frame reach \(reached)")
        #expect(budgeted.traced["minSamples"] as? Int == 16)
        let fixed = try still(PathTracing(samplesPerPixel: reached, noiseThreshold: 0.03,
                                          minSamplesPerPixel: 16))
        #expect(pixels(of: fixed.image) == pixels(of: budgeted.image))
        #expect(fixed.traced["meanSamples"] as? Double == budgeted.traced["meanSamples"] as? Double)
    }

    /// The first frame of a reusing run traces the history's worth of samples
    /// itself, so under a budget it gets the history's worth of time: with four
    /// frames carried, the first frame runs about four times as long as the second
    /// and reaches about four times the count. The claim is read at well under
    /// that ratio, since the clock is the machine's.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFirstFrameOfAReusingRunGetsTheHistorysWorthOfTime() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: Self.farCap, reusedFrames: 4,
                                                secondsPerFrame: 0.15)
        defer { OllinApp.pathTracedExport = nil }
        var reports: [PathTraceReport] = []
        try OllinApp.renderFrames(room(), frames: 2, fps: TracedReuseTests.fps, skipSeconds: 0) { frame, _ in
            reports.append(try #require(frame.pathTrace))
        }
        try #require(reports.count == 2)
        let first = try #require(reports[0].reachedSamplesPerPixel)
        let second = try #require(reports[1].reachedSamplesPerPixel)
        let firstSeconds = try #require(reports[0].secondsTraced)
        let secondSeconds = try #require(reports[1].secondsTraced)
        #expect(first > second * 3 / 2, "the first frame reached \(first), the second \(second)")
        #expect(firstSeconds > secondSeconds * 1.5,
                "the first frame took \(firstSeconds) s, the second \(secondSeconds) s")
        #expect(reports[1].carriedSamplesPerPixel ?? 0 > Double(second),
                "the second frame carried \(reports[1].carriedSamplesPerPixel ?? 0) against its own \(second)")
    }
}
