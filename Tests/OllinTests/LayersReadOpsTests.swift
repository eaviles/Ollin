import Testing
import CoreGraphics
@testable import Ollin

/// A layer that draws the image of a filter or a combine made the same frame
/// sees that op's result: the layer is drawn after the op runs, however the
/// two were made, and through a chain of such layers and ops. A frame that
/// draws its ops only onto the canvas keeps the order it always had.
@Suite
@MainActor
struct LayersReadOpsTests {

    /// Red, inverted by a filter, drawn into a second layer, and that layer
    /// onto the canvas; with `chained`, the second layer is filtered again and
    /// drawn into a third.
    final class Nested: Sketch {
        var chained = false
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            background(.black)
            let a = makeRenderTarget()
            withTarget(a) { background(.red) }
            let inverted = a.filtered(.invert())
            let b = makeRenderTarget()
            withTarget(b) { drawImage(inverted.image, 0, 0) }
            guard chained else { drawImage(b.image, 0, 0); return }
            let back = b.filtered(.invert())
            let c = makeRenderTarget()
            withTarget(c) {
                drawImage(back.image, 0, 0)
                noStroke(); fill(.blue); drawRect(0, 0, 16, 16)
            }
            drawImage(c.image, 0, 0)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerDrawsAFilterMadeTheSameFrame() throws {
        let px = Pixels(try OllinApp.image(of: Nested(), frame: 1))
        #expect(px.channel(0, 32, 32) < 8 && px.channel(1, 32, 32) > 247 && px.channel(2, 32, 32) > 247,
                "inverted red is cyan: \(px.channel(0, 32, 32)), \(px.channel(1, 32, 32)), \(px.channel(2, 32, 32))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aChainOfLayersAndFiltersResolvesInOrder() throws {
        let s = Nested(); s.chained = true
        let px = Pixels(try OllinApp.image(of: s, frame: 1))
        // Inverted twice is red again, with the third layer's own mark on top.
        #expect(px.channel(0, 40, 40) > 247 && px.channel(1, 40, 40) < 8, "red again: \(px.channel(0, 40, 40))")
        #expect(px.channel(2, 8, 8) > 247 && px.channel(0, 8, 8) < 8, "the third layer's own mark")
    }
}
