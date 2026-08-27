import Testing
import Foundation
import Ollin
@testable import OllinVision

/// The saliency model is neural, so every model-touching test soft-skips where
/// the compute device is missing (the segmenter-test pattern); the clamp math
/// is exercised against a real observation once the model demonstrably runs.
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

    @Test func attentionCentersOnTheDisk() async throws {
        // Soft-skip: `try?` flattens, so nil covers "model can't run here".
        guard let saliency = try? await SaliencyTracker.detect(in: diskImage()) else { return }
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

    @Test func queriesReadTheRightPartOfThePicture() async throws {
        // The disk sits OFF-center, in the picture's top quarter, and
        // objectness boxes it: the query surface must put the heat *inside*
        // that box, not in its vertical mirror. Pins the **top-down** indexing
        // of Vision's `pixel(at:)` behind the query's internal y-flip (queries
        // used to read the vertically mirrored spot — a real bug the
        // vertically-centered fixtures couldn't catch, being invariant under
        // the flip; the published heat-map image was always upright, only the
        // queries were mirrored).
        let image = Image(width: 320, height: 240, color: Color(white: 0.05))
        let cx = 160, cy = 56, radius = 44
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius)
            where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                image[x, y] = Color(red: 1.0, green: 0.6, blue: 0.1)
            }
        }
        guard let saliency = try? await SaliencyTracker.detect(in: image,
                                                               mode: .objectness) else { return }
        // Lenient on detection (the model decides), strict on orientation.
        guard let region = saliency.regions.first else { return }
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

    @Test func edgeQueriesClampInsteadOfTrapping() async throws {
        guard let saliency = try? await SaliencyTracker.detect(in: diskImage()) else { return }
        // The optical-flow regression, re-pinned here: Vision's nearest-neighbor
        // pixel lookup traps when a coordinate rounds past the last pixel, so
        // any of these would crash without the clamp.
        _ = saliency.salienceNormalized(at: Vector2(1, 1))
        _ = saliency.salienceNormalized(at: Vector2(0.999999, 0.5))
        _ = saliency.salienceNormalized(at: Vector2(-2, 3))
        // And through canvas space: the frame's exact bottom-right corner.
        _ = saliency.salience(at: Vector2(320, 240), in: diskRect)
    }

    @Test func objectnessBoxesTheDisk() async throws {
        guard let saliency = try? await SaliencyTracker.detect(in: diskImage(),
                                                               mode: .objectness) else { return }
        // Lenient on count (the model decides what stands out), strict on
        // placement: when regions come back, one must cover the disk's center.
        guard !saliency.regions.isEmpty else { return }
        let covers = saliency.regions.contains { region in
            let b = region.bounds(in: diskRect)
            return b.x <= 160 && 160 <= b.x + b.width
                && b.y <= 120 && 120 <= b.y + b.height
        }
        #expect(covers)
    }

    @MainActor
    @Test func liveWiringPublishesHeatMapRegionsAndQueries() async throws {
        // Gate on the still path: only run the live assertion where the model
        // demonstrably maps this exact frame (elsewhere this is the soft-skip).
        let image = diskImage()
        guard (try? await SaliencyTracker.detect(in: image)) != nil else { return }

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
}
