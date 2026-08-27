import CoreGraphics
import Foundation
import Testing
import Ollin
@testable import OllinVision

/// The failure paths and the bounds mapping are always-on; the real-model
/// tests need the three fetched model parts (`Scripts/fetch-models.sh`),
/// soft-skipping elsewhere (CI never fetches the weights).
@Suite struct PointSegmenterTests {

    static let imageEncoderURL = ModelTrackerTests.model("SAM2_1SmallImageEncoderFLOAT16.mlpackage")
    static let promptEncoderURL = ModelTrackerTests.model("SAM2_1SmallPromptEncoderFLOAT16.mlpackage")
    static let maskDecoderURL = ModelTrackerTests.model("SAM2_1SmallMaskDecoderFLOAT16.mlpackage")

    static var modelsAreFetched: Bool {
        ModelTrackerTests.isFetched(imageEncoderURL)
            && ModelTrackerTests.isFetched(promptEncoderURL)
            && ModelTrackerTests.isFetched(maskDecoderURL)
    }

    static func segmenter() -> PointSegmenter {
        PointSegmenter(imageEncoderAt: imageEncoderURL,
                       promptEncoderAt: promptEncoderURL,
                       maskDecoderAt: maskDecoderURL)
    }

    /// A staged 512×512 scene with two separate things on a dark ground: a
    /// white disc centered at (160, 200) with radius 80, and a white square
    /// from (370, 370) to (430, 430). Deliberately asymmetric, so a flipped
    /// or shifted coordinate mapping puts a click on neither.
    static let discCenter = Vector2(160, 200)
    static let discRadius = 80.0
    static let squareCenter = Vector2(400, 400)

    static func scene() -> Image {
        let image = Image(width: 512, height: 512, color: Color(white: 0.1))
        let white = Color(white: 1)
        for y in 0..<512 {
            for x in 0..<512 {
                let dx = Double(x) - discCenter.x, dy = Double(y) - discCenter.y
                if dx * dx + dy * dy < discRadius * discRadius { image[x, y] = white }
                if (370..<430).contains(x), (370..<430).contains(y) { image[x, y] = white }
            }
        }
        return image
    }

    /// The matte's alpha at a frame-fraction position (the matte is
    /// mask-resolution, so probes go through fractions, not frame pixels).
    static func matteAlpha(_ matte: Image, atFraction u: Double, _ v: Double) -> Double {
        matte[Int(u * Double(matte.width - 1)), Int(v * Double(matte.height - 1))].alpha
    }

    // MARK: Always-on

    @Test func missingFilesSurfaceInsteadOfFailingSilently() async {
        let segmenter = PointSegmenter(
            imageEncoderAt: URL(fileURLWithPath: "/nowhere/encoder.mlpackage"),
            promptEncoderAt: URL(fileURLWithPath: "/nowhere/prompt.mlpackage"),
            maskDecoderAt: URL(fileURLWithPath: "/nowhere/decoder.mlpackage"))
        let image = Image(width: 32, height: 32, color: .white)
        await #expect(throws: PointSegmenter.Error.self) {
            _ = try await segmenter.detect(in: image, at: [Vector2(16, 16)])
        }
        #expect(!segmenter.isAvailable)
        #expect(segmenter.unavailableReason?.contains("/nowhere") == true)
    }

    @Test func aClickOutsideTheRectangleIsIgnored() {
        let segmenter = Self.segmenter()
        let rect = Rectangle(x: 100, y: 100, width: 200, height: 200)
        segmenter.pick(at: Vector2(50, 50), in: rect)
        #expect(!segmenter.isWorking)
        #expect(segmenter.pick == nil)
        // An exclude with no pick active does nothing either.
        segmenter.exclude(Vector2(150, 150), in: rect)
        #expect(!segmenter.isWorking)
    }

    @Test func boundsMapFrameFractionsIntoTheDrawnRectangle() {
        let dummy = Image(width: 1, height: 1, color: .white)
        let pick = PointSegmenter.Pick(matte: dummy, cutout: dummy, score: 1,
                                       region: Rectangle(x: 0.25, y: 0.25,
                                                         width: 0.5, height: 0.5))
        let mapped = pick.bounds(in: Rectangle(x: 100, y: 200, width: 400, height: 300))
        #expect(abs(mapped.x - 200) < 1e-9)
        #expect(abs(mapped.y - 275) < 1e-9)
        #expect(abs(mapped.width - 200) < 1e-9)
        #expect(abs(mapped.height - 150) < 1e-9)
    }

    // MARK: Real model (soft-gated on the downloaded weights)

    /// The end-to-end pin, and the coordinate-mapping counterfactual in one:
    /// the same staged scene answers two different clicks with two different
    /// things, each mask sitting where its target is. A flipped axis, a
    /// wrong scale, or a swapped point order all fail this.
    @Test func aClickPicksTheThingUnderIt() async throws {
        guard Self.modelsAreFetched else { return }
        let scene = Self.scene()
        let segmenter = Self.segmenter()
        let pixels = Rectangle(x: 0, y: 0, width: 512, height: 512)

        let disc = try #require(try await segmenter.detect(in: scene, at: [Self.discCenter]))
        #expect(disc.score > 0.5)
        let discBounds = disc.bounds(in: pixels)
        #expect(abs(discBounds.x - (Self.discCenter.x - Self.discRadius)) < 20)
        #expect(abs(discBounds.y - (Self.discCenter.y - Self.discRadius)) < 20)
        #expect(abs(discBounds.width - Self.discRadius * 2) < 40)
        #expect(abs(discBounds.height - Self.discRadius * 2) < 40)
        // The matte is solid over the disc and empty over the square.
        #expect(Self.matteAlpha(disc.matte, atFraction: Self.discCenter.x / 512,
                                Self.discCenter.y / 512) > 0.9)
        #expect(Self.matteAlpha(disc.matte, atFraction: Self.squareCenter.x / 512,
                                Self.squareCenter.y / 512) < 0.1)

        let square = try #require(try await segmenter.detect(in: scene, at: [Self.squareCenter]))
        let squareBounds = square.bounds(in: pixels)
        #expect(abs(squareBounds.x - 370) < 20)
        #expect(abs(squareBounds.y - 370) < 20)
        #expect(Self.matteAlpha(square.matte, atFraction: Self.discCenter.x / 512,
                                Self.discCenter.y / 512) < 0.1)
    }

    /// The cutout carries the frame's own pixels under the mask and
    /// transparency elsewhere, at frame resolution.
    @Test func theCutoutIsTheFramesPixelsWhereTheMaskIs() async throws {
        guard Self.modelsAreFetched else { return }
        let scene = Self.scene()
        let segmenter = Self.segmenter()
        let disc = try #require(try await segmenter.detect(in: scene, at: [Self.discCenter]))
        #expect(disc.cutout.width == 512 && disc.cutout.height == 512)
        let center = disc.cutout[Int(Self.discCenter.x), Int(Self.discCenter.y)]
        #expect(center.alpha > 0.9)
        #expect(center.red > 0.8)   // the disc is white
        let elsewhere = disc.cutout[Int(Self.squareCenter.x), Int(Self.squareCenter.y)]
        #expect(elsewhere.alpha < 0.1)
    }

    /// The label plumbing: a background point rides along without turning
    /// into a second foreground point. If the labels were swapped or lost,
    /// the mask would grow toward the avoided corner and this bound breaks.
    @Test func anAvoidedPointStaysOutOfThePick() async throws {
        guard Self.modelsAreFetched else { return }
        let scene = Self.scene()
        let segmenter = Self.segmenter()
        let disc = try #require(try await segmenter.detect(
            in: scene, at: [Self.discCenter], avoiding: [Self.squareCenter]))
        #expect(Self.matteAlpha(disc.matte, atFraction: Self.squareCenter.x / 512,
                                Self.squareCenter.y / 512) < 0.1)
        let bounds = disc.bounds(in: Rectangle(x: 0, y: 0, width: 512, height: 512))
        #expect(bounds.x + bounds.width < 370)   // nowhere near the square
    }

    /// The live path over a hand-fired frame source: frames flow, a pick
    /// answers asynchronously, a refine lands against the frozen frame's
    /// cached encoding, and `clear()` empties the surface.
    @Test @MainActor func liveWiringAnswersPicksAndClears() async throws {
        guard Self.modelsAreFetched else { return }
        let source = FrameSourceTests.ManualFrameSource()
        let segmenter = PointSegmenter(source,
                                       imageEncoderAt: Self.imageEncoderURL,
                                       promptEncoderAt: Self.promptEncoderURL,
                                       maskDecoderAt: Self.maskDecoderURL)
        let frame = Self.scene().currentCGImage()
        let rect = Rectangle(x: 0, y: 0, width: 512, height: 512)

        // No pick before any frame arrived: there is nothing to freeze.
        segmenter.pick(at: Self.discCenter, in: rect)
        #expect(segmenter.pick == nil)

        // The tap takes a frame the way a capture queue would. Its analysis
        // runs on a background task, so nothing here waits on it: a deadline
        // over that task reads a saturated full-suite machine as a failure.
        source.frameTap?(frame)

        // The deterministic drive: the same analyze path awaited inline, then
        // the pick's own worker awaited. A loaded machine makes both slower,
        // never absent.
        await SourceAnalyzers.analyzer(for: source).analyzeNow(FrameBox(frame))
        segmenter.pick(at: Self.discCenter, in: rect)
        await segmenter.settle()
        let disc = try #require(segmenter.pick)
        let bounds = disc.bounds(in: rect)
        #expect(abs(bounds.x - (Self.discCenter.x - Self.discRadius)) < 20)

        // A refine against the frozen frame: exclude the disc's right half
        // and the mask retreats leftward.
        segmenter.exclude(Vector2(Self.discCenter.x + Self.discRadius * 0.6,
                                  Self.discCenter.y), in: rect)
        await segmenter.settle()
        if let after = segmenter.pick {
            let refinedBounds = after.bounds(in: rect)
            #expect(refinedBounds.x + refinedBounds.width
                    <= bounds.x + bounds.width + 1)
        }

        segmenter.clear()
        #expect(segmenter.pick == nil)
        #expect(segmenter.isAvailable)
    }
}
