import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// `imageSampling(.nearest)`: a picture drawn larger than its pixels keeps every
/// pixel a hard square, with no enlarged copy made on the CPU. The default
/// `.linear` blends neighbors, a picture drawn smaller than its pixels is
/// blended under either, and the choice is drawing state `withState { }`
/// puts back.
@Suite(.serialized)
@MainActor
struct ImageSamplingTests {

    /// A 4 by 4 picture of the eight corner colors, no two neighbors alike, so
    /// every seam between cells is a seam a blend would show.
    static let corners: [[UInt8]] = [
        [0, 0, 0], [255, 0, 0], [0, 255, 0], [0, 0, 255],
        [255, 255, 0], [255, 0, 255], [0, 255, 255], [255, 255, 255],
    ]
    static func cellColor(_ x: Int, _ y: Int) -> [UInt8] { corners[(x + y * 3) % 8] }
    static let picture = Image(width: 4, height: 4, premultipliedRGBA: (0 ..< 16).flatMap { i in
        cellColor(i % 4, i / 4) + [255]
    })!

    /// Draws the picture at `scale` times its size, under one sampling, and
    /// gives the second draw its own state block to show the block puts the
    /// choice back.
    final class Enlarged: Sketch {
        var sampling: ImageSampling = .linear
        var factor = 2.0
        var insideState = false
        override var canvasSize: CanvasSize { .square(8) }
        override func draw() {
            background(.black)
            let side = 4 * factor
            if insideState {
                withState {
                    imageSampling(sampling)
                    drawImage(ImageSamplingTests.picture, 0, 0, side, side)
                }
            } else {
                imageSampling(sampling)
                drawImage(ImageSamplingTests.picture, 0, 0, side, side)
            }
        }
    }

    private func render(_ sampling: ImageSampling, factor: Double = 2, insideState: Bool = false) throws -> (bytes: [UInt8], width: Int) {
        let sketch = Enlarged()
        sketch.sampling = sampling
        sketch.factor = factor
        sketch.insideState = insideState
        let image = try #require(try OllinApp.image(of: sketch, frame: 0))
        return (pixels(of: image), image.width)
    }

    private func pixel(_ r: (bytes: [UInt8], width: Int), _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * r.width + x) * 4
        return [r.bytes[i], r.bytes[i + 1], r.bytes[i + 2]]
    }

    /// The proof: drawn at twice its size under `.nearest`, the 4 by 4 picture
    /// reads as 16 flat 2 by 2 cells, each the byte of its source pixel. The
    /// colors are the eight corners of the cube, which the present pass's
    /// dither leaves exact, so "flat" is byte for byte.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anEnlargedPictureReadsAsFlatCellsUnderNearest() throws {
        let r = try render(.nearest)
        for y in 0 ..< 8 {
            for x in 0 ..< 8 {
                #expect(pixel(r, x, y) == Self.cellColor(x / 2, y / 2), "pixel \(x), \(y): \(pixel(r, x, y))")
            }
        }
    }

    /// And the default blends: the same draw under `.linear` mixes neighbors
    /// at the seams, so at least one pixel in a cell is not its source byte.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDefaultBlendsTheSeams() throws {
        let r = try render(.linear)
        var blended = 0
        for y in 0 ..< 8 {
            for x in 0 ..< 8 where pixel(r, x, y) != Self.cellColor(x / 2, y / 2) { blended += 1 }
        }
        #expect(blended >= 16, "only \(blended) pixels differ from their cell under linear sampling")
    }

    /// Drawn smaller than its pixels, a picture is blended under either: the
    /// reduction stays linear, so `.nearest` is byte-identical to the default
    /// there.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aReducedPictureIsBlendedUnderEither() throws {
        let linear = try render(.linear, factor: 0.5)
        let nearest = try render(.nearest, factor: 0.5)
        #expect(linear.bytes == nearest.bytes)
    }

    /// `withState { }` puts the choice back: a picture drawn after the block is
    /// drawn the way it was before it.
    @Test func theChoiceIsDrawingStateTheBlockRestores() {
        let sketch = Enlarged()
        sketch.setCanvasSize(width: 8, height: 8)
        sketch.sampling = .nearest
        sketch.insideState = true
        sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        sketch.performDraw()
        #expect(sketch.drawer.imageSamplingMode == .linear)
        #expect(sketch.drawer.batches.contains { $0.kind == .image && $0.imageSamplesNearest })
    }
}
