import Testing
import Foundation
import Ollin
@testable import OllinVision

/// The saliency model is neural, so every model-touching test carries a trait
/// that refuses it where the compute device is missing (the segmenter-test
/// pattern); the clamp math is exercised against a real observation once the
/// model demonstrably runs.
@Suite struct SaliencyTrackerTests {

    /// A bright disk on a dark ground — the same fixture the subject-lift test
    /// uses; salient enough for both saliency models to light up (verified on
    /// this hardware).
    private func diskImage() -> Image {
        let image = Image(width: 320, height: 240, color: Color(white: 0.05))
        let cx = 160, cy = 120, radius = 70
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius)
            where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                image[x, y] = Color(red: 1.0, green: 0.6, blue: 0.1)
            }
        }
        return image
    }

    private var diskRect: Rectangle { Rectangle(x: 0, y: 0, width: 320, height: 240) }

    /// The attention model's reading of `diskImage()`, made once for the
    /// suite: three tests ask the same still request (two read it, and the
    /// live-wiring test only needs to know the model runs here), so the model
    /// runs once. `nil` where the model cannot run, which `modelRuns` reports as
    /// the skip it is.
    private static let attention = Task<Saliency?, Never> {
        try? await SaliencyTracker.detect(in: SaliencyTrackerTests().diskImage())
    }

    private static let modelRuns: ConditionTrait = .enabled("the saliency model has no compute device here") {
        await SaliencyTrackerTests.attention.value != nil
    }

    @Test(modelRuns) func attentionCentersOnTheDisk() async throws {
        let saliency = try #require(await Self.attention.value)
        #expect(saliency.heatMap.width > 0 && saliency.heatMap.height > 0)
        // The eye goes to the disk: more heat under its center than in a corner.
        let center = saliency.salience(at: Vector2(160, 120), in: diskRect)
        let corner = saliency.salience(at: Vector2(8, 8), in: diskRect)
        #expect(center > corner)
        // The published image is the same surface: the heat map's own center
        // pixel reads back brighter (alpha) than its corner.
        let heat = saliency.heatMap
        #expect(heat[heat.width / 2, heat.height / 2].alpha
                > heat[0, 0].alpha)
    }

    @Test(modelRuns) func queriesReadTheRightPartOfThePicture() async throws {
        // The disk sits off-center, in the picture's top quarter, and
        // objectness boxes it: the query surface must put the heat *inside*
        // that box, not in its vertical mirror. A fixture centered top to
        // bottom cannot tell the two apart, being the same under the flip.
        let image = Image(width: 320, height: 240, color: Color(white: 0.05))
        let cx = 160, cy = 56, radius = 44
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius)
            where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                image[x, y] = Color(red: 1.0, green: 0.6, blue: 0.1)
            }
        }
        let saliency = try await SaliencyTracker.detect(in: image,
                                                               mode: .objectness)
        // Lenient on detection (the model decides), strict on orientation.
        let region = try #require(saliency.regions.first)
        let box = region.bounds(in: diskRect)
        let mirrored = Rectangle(x: box.x, y: 240 - box.y - box.height,
                                 width: box.width, height: box.height)
        func meanSalience(in r: Rectangle) -> Double {
            var sum = 0.0, n = 0.0
            for gy in 0..<6 {
                for gx in 0..<6 {
                    let p = Vector2(r.x + (Double(gx) + 0.5) / 6 * r.width,
                                    r.y + (Double(gy) + 0.5) / 6 * r.height)
                    sum += saliency.salience(at: p, in: diskRect)
                    n += 1
                }
            }
            return sum / n
        }
        #expect(meanSalience(in: box) > meanSalience(in: mirrored) * 3)
    }

    /// The largest gap between a query at a heat-map cell's center and that
    /// cell of the published picture, and the brightest cell, so a caller can
    /// tell a map that agrees from a map that is merely dark.
    private func disagreement(of heat: Image,
                              with query: (Vector2) -> Double) -> (worst: Double, peak: Double) {
        var worst = 0.0, peak = 0.0
        for y in 0..<heat.height {
            for x in 0..<heat.width {
                let alpha = heat[x, y].alpha
                peak = max(peak, alpha)
                let point = Vector2((Double(x) + 0.5) / Double(heat.width) * diskRect.width,
                                    (Double(y) + 0.5) / Double(heat.height) * diskRect.height)
                worst = max(worst, abs(query(point) - alpha))
            }
        }
        return (worst, peak)
    }

    /// A disk off-center both ways, so a query that reads another row or
    /// another column of the map cannot agree with the picture by symmetry.
    private func cornerDiskImage() -> Image {
        let image = Image(width: 320, height: 240, color: Color(white: 0.05))
        let cx = 236, cy = 66, radius = 44
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius)
            where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                image[x, y] = Color(red: 1.0, green: 0.6, blue: 0.1)
            }
        }
        return image
    }

    @Test(modelRuns) func theQueriesAndThePictureAreOneSurface() async throws {
        // Every cell of the published heat map, asked through the query at
        // its own center, is the picture's value to its 8 bits. A query that
        // read the map's rows without their padding would agree on the first
        // row and nowhere else, and a marker placed by it would sit beside
        // the glow it follows.
        let saliency = try await SaliencyTracker.detect(in: cornerDiskImage())
        let (worst, peak) = disagreement(of: saliency.heatMap) {
            saliency.salience(at: $0, in: diskRect)
        }
        #expect(peak > 0.2, "the model lit the map at all (peak \(peak))")
        #expect(worst <= 1.5 / 255, "a query and its cell differ by \(worst)")
    }

    @Test(modelRuns) func edgeQueriesClampInsteadOfTrapping() async throws {
        let saliency = try #require(await Self.attention.value)
        // A point on or past the map's last row or column reads the edge
        // cell: the byte plane clamps its indices, so none of these traps.
        _ = saliency.salienceNormalized(at: Vector2(1, 1))
        _ = saliency.salienceNormalized(at: Vector2(0.999999, 0.5))
        _ = saliency.salienceNormalized(at: Vector2(-2, 3))
        // And through canvas space: the frame's exact bottom-right corner.
        _ = saliency.salience(at: Vector2(320, 240), in: diskRect)
    }

    @Test(modelRuns) func objectnessBoxesTheDisk() async throws {
        let saliency = try await SaliencyTracker.detect(in: diskImage(),
                                                               mode: .objectness)
        // Lenient on count (the model decides what stands out), strict on
        // placement: when regions come back, one must cover the disk's center.
        try #require(!saliency.regions.isEmpty)
        let covers = saliency.regions.contains { region in
            let b = region.bounds(in: diskRect)
            return b.x <= 160 && 160 <= b.x + b.width
                && b.y <= 120 && 120 <= b.y + b.height
        }
        #expect(covers)
    }

    @MainActor
    @Test(modelRuns) func liveWiringPublishesHeatMapRegionsAndQueries() async throws {
        // Gated on the still path: the live assertion runs only where the
        // model demonstrably maps this exact frame.
        let image = diskImage()

        // The camera-free live path: a hand-driven source standing in for the
        // capture queue, exactly like the frame-source tests.
        let source = FrameSourceTests.ManualFrameSource()
        let saliency = SaliencyTracker(source)
        let tap = try #require(source.frameTap)
        let frame = image.currentCGImage()

        // The tap takes a frame the way a capture queue would. Its analysis
        // runs on a background task, so nothing here waits on it: a deadline
        // over that task reads a saturated full-suite machine as a failure.
        tap(frame)

        // The heat-map read arms its conversion (the first read turns it on),
        // so the analyzed frame below publishes it.
        #expect(saliency.heatMap == nil)

        // The deterministic drive: the same analyze path, awaited inline. A
        // loaded machine makes this slower, never absent.
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(frame))
        #expect(saliency.heatMap != nil)
        // Once published, the query surface answers from the same observation —
        // the disk's center out-heats a corner here too.
        #expect(saliency.salience(at: Vector2(160, 120), in: diskRect)
                > saliency.salience(at: Vector2(8, 8), in: diskRect))
    }

    @MainActor
    @Test(modelRuns) func theLiveQueriesAndTheLivePictureAreOneSurface() async throws {
        let source = FrameSourceTests.ManualFrameSource()
        let saliency = SaliencyTracker(source)
        _ = saliency.heatMap   // the first read arms the picture
        let frame = cornerDiskImage().currentCGImage()
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(frame))
        let heat = try #require(saliency.heatMap)
        let (worst, peak) = disagreement(of: heat) {
            saliency.salience(at: $0, in: diskRect)
        }
        #expect(peak > 0.2, "the model lit the map at all (peak \(peak))")
        #expect(worst <= 1.5 / 255, "a query and its cell differ by \(worst)")
    }
}
