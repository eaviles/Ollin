import Foundation
import Metal
import MetalKit
@testable import Ollin
import Testing

/// What a long run leaves behind. Installation mode, the wallpaper, the screen
/// saver, and the menu-bar piece run for days, and a cache that gains one entry
/// a frame is invisible in any test shorter than that. So one sketch that
/// churns everything the renderer keeps across frames (pictures made again,
/// layers made and dropped, a batch rebuilt, glyph-atlas text that keeps
/// changing, a gradient and a sea state that move every frame) runs twenty
/// thousand frames through the live path, and what the renderer and the drawer
/// hold is counted as it goes (`MetalRenderer.census`, `Drawer.census`).
///
/// The invariant: no count in the last half of the run goes above the most it
/// reached between frames 2,000 and 4,000, give or take a margin. The first
/// minutes fill every pool and cache to the size the piece needs; after that a
/// run that only repeats itself has nothing new to keep. The margin (a quarter,
/// and at least 8) is for the caches that fill and clear on a cycle of their
/// own and so peak at slightly different heights, the glyph atlas's page most
/// of all; a count that grows with the frames passes it within a few hundred
/// frames. Counts rather than bytes, because the counts belong to this renderer
/// alone and the process's memory is shared with every other suite in it.
@Suite(.serialized)
@MainActor
struct SoakTests {

    /// Everything a frame can leave behind, made on a schedule that repeats.
    final class Churn: Sketch {
        private(set) var draws = 0
        private var picture: Image?
        private var trail: Feedback?
        private var light: Accumulator?
        private var batch: Batch?
        /// Glyphs cycled through the atlas: six hundred ideographs, whole-em
        /// cells, more than one page holds, so the page fills and is rebuilt
        /// over and over.
        static let glyphs: [String] = (0x4E00 ..< 0x4E00 + 600)
            .compactMap(Unicode.Scalar.init).map { String(Character($0)) }

        override var canvasSize: CanvasSize { .square(64) }

        override func draw() {
            draws += 1
            let f = frameCount
            background(.black)

            // A picture made again every tenth frame, as a sketch that reloads
            // one does.
            if picture == nil || f % 10 == 0 {
                picture = Image(width: 8, height: 8, color: Color(hue: Double(f % 360) / 360, saturation: 1, brightness: 1))
            }
            if let picture { drawImage(picture, 0, 0, 16, 16) }

            // A layer made in the frame and dropped with it.
            let layer = makeRenderTarget(width: 32, height: 32)
            withTarget(layer) {
                background(.red)
                fill(.white)
                drawCircle(16, 16, Double(f % 16))
            }
            drawImage(layer.image, 16, 0, 16, 16)

            // A feedback layer and an accumulator, each kept fifty frames and
            // then replaced, so the old one's storage has to go with it.
            if trail == nil || f % 50 == 0 {
                trail = makeFeedback(width: 32, height: 32)
                light = makeAccumulator(width: 32, height: 32)
            }
            if let trail {
                withFeedback(trail) { previous in
                    drawImage(previous, 0, 0)
                    fill(.blue)
                    drawCircle(Double(f % 32), 16, 3)
                }
                drawImage(trail.image, 32, 0, 16, 16)
            }
            if let light {
                withAccumulator(light) {
                    fill(.green)
                    drawCircle(Double((f * 7) % 32), 16, 4)
                }
                drawImage(light.image, 48, 0, 16, 16)
            }

            // A batch rebuilt every tenth frame.
            if batch == nil || f % 10 == 0 {
                batch = makeBatch {
                    fill(.yellow)
                    for i in 0..<8 { drawCircle(Double(i * 8), 40, Double(1 + (f + i) % 4)) }
                }
            }
            if let batch { drawBatch(batch) }

            // Atlas text that moves on to new glyphs every twentieth frame, so
            // over the run the page fills and is rebuilt again and again.
            textFont(OutlineFont.system)
            textMode(.atlas)
            textSize(10)
            fill(.white)
            let glyphs = Self.glyphs
            let start = ((f / 20) * 3) % glyphs.count
            drawText(glyphs[start] + glyphs[(start + 1) % glyphs.count] + glyphs[(start + 2) % glyphs.count], 2, 60)

            // A gradient whose colors move every frame.
            fill(Gradient.linear(from: Vector2(0, 44), to: Vector2(64, 44),
                                 [Color(hue: Double(f % 1000) / 1000, saturation: 1, brightness: 1), .black]))
            drawRect(0, 44, 64, 6)

            // A sea state that moves every frame, as a wind driven by the clock is.
            let sea = makeOceanField(Ocean(windSpeed: 6 + Double(f) * 1e-4), at: Double(f) / 60, resolution: 16)
            drawImage(sea.image, 48, 48, 16, 16)
        }
    }

    /// The counts, renderer and drawer together, plus the glyphs the atlas holds.
    private func census(_ runner: SketchRunner, _ sketch: Churn) -> [String: Int] {
        var counts = runner.renderer.census
        for (key, value) in sketch.drawer.census { counts["drawer." + key] = value }
        counts["atlasGlyphs"] = OutlineFont.system.atlas.glyphCount
        return counts
    }

    /// The frames each check reads, and the run's length. The early window is
    /// where every cache has filled once: the glyph atlas's page takes the
    /// longest, about three thousand frames of this sketch's text.
    static let early = 2_000...4_000
    static let late = 10_000...20_000
    /// The frames whose counts the run prints, for the record.
    static let reported = [2_000, 20_000]

    @Test(.enabled(if: Snapshot.hasMetal))
    func twentyThousandFramesKeepNoMoreThanTheirFirstFourThousand() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Churn()
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        view.drawableSize = CGSize(width: 64, height: 64)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        sketch.setCanvasSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        let firstGeneration = OutlineFont.system.atlas.generation

        var earlyMost: [String: Int] = [:]
        var lateMost: [String: Int] = [:]
        var at: [Int: [String: Int]] = [:]
        for frame in 1...Self.late.upperBound {
            // The live path drops a refresh the frame ring has no room for, so
            // wait for room: every turn of this loop is a drawn frame.
            while !runner.canStartFrame {
                RunLoop.current.run(until: Date().addingTimeInterval(0.0005))
            }
            autoreleasepool { runner.draw(in: view) }
            // Read every frame, since a cache that fills and clears on a cycle
            // shows its peak only on the frame before it clears.
            guard Self.early.contains(frame) || Self.late.contains(frame) else { continue }
            var counts = census(runner, sketch)
            let inFlight = counts.removeValue(forKey: "framesInFlight") ?? 0
            #expect(inFlight <= MetalRenderer.maxFramesInFlight)
            if Self.early.contains(frame) { earlyMost.merge(counts, uniquingKeysWith: max) }
            if Self.late.contains(frame) { lateMost.merge(counts, uniquingKeysWith: max) }
            if Self.reported.contains(frame) { at[frame] = counts }
        }

        #expect(sketch.draws == Self.late.upperBound, "every turn of the loop should have drawn")
        for key in lateMost.keys.sorted() {
            let before = earlyMost[key] ?? 0, after = lateMost[key] ?? 0
            #expect(after <= before + max(8, before / 4),
                    "\(key) grew: at most \(before) in frames 2,000 to 4,000, \(after) later")
        }
        #expect(OutlineFont.system.atlas.generation - firstGeneration >= 2,
                "the text should have filled the glyph atlas's page and had it rebuilt more than once")
        // Printed so a run records the numbers the invariant was read from.
        let rows = (at[2_000] ?? [:]).keys.sorted().compactMap { key -> String? in
            let a = at[2_000]?[key] ?? 0, b = at[20_000]?[key] ?? 0
            return a == 0 && b == 0 ? nil : "\(key) \(a) -> \(b)"
        }
        print("soak census at frame 2,000 -> 20,000: " + rows.joined(separator: ", "))
    }
}
