@testable import Ollin
import Testing

/// CPU checks on the stencil-clipping recorder (`withClip`): the batch structure
/// the renderer replays, the per-surface scoping, and the SVG clipPath export.
/// None of it touches Metal, so these run everywhere (including CI); the rendered
/// result is pinned by the `clip` snapshot.
@Suite
@MainActor
struct ClipTests {

    /// A closed square `Shape` with its corner at `origin`.
    private func square(_ origin: Vector2 = .zero, side: Double = 40) -> Shape {
        Shape([origin,
               origin + Vector2(side, 0),
               origin + Vector2(side, side),
               origin + Vector2(0, side)])
    }

    @Test func batchesCarryClipLevels() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.drawCircle(10, 10, 5)
        drawer.withClip(square()) {
            drawer.drawCircle(20, 20, 5)
            drawer.withClip(square(Vector2(10, 10), side: 20)) {
                drawer.drawCircle(22, 22, 3)
            }
        }
        drawer.drawCircle(30, 30, 5)
        let kinds = drawer.batches.map(\.kind)
        #expect(kinds == [.sdf, .clipPush, .sdf, .clipPush, .sdf, .clipPop, .clipPop, .sdf])
        // Content tests `equal` at its nesting level; each push establishes the
        // next level and each pop dismantles its own.
        #expect(drawer.batches.map(\.clipLevel) == [0, 1, 1, 2, 2, 2, 1, 0])
        #expect(drawer.usesClipStencil)
    }

    @Test func pushRecordsRegionTriangles() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.withClip(square()) {}
        // The push batch's run in the shared vertex array is the square's fill
        // triangulation (two triangles); the pop carries no geometry.
        #expect(drawer.batches.map(\.kind) == [.clipPush, .clipPop])
        #expect(drawer.vertices.count == 6)
    }

    @Test func backgroundInsideClipReemitsPush() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.withClip(square()) {
            drawer.drawCircle(20, 20, 5)
            drawer.background(.red)          // wipes the batches recorded so far…
            drawer.drawCircle(22, 22, 3)     // …but this still draws clipped
        }
        #expect(drawer.batches.map(\.kind) == [.clipPush, .sdf, .clipPop])
        #expect(drawer.batches.map(\.clipLevel) == [1, 1, 1])
    }

    @Test func unbalancedPopIsIgnored() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.popClip()
        #expect(drawer.batches.isEmpty)
        #expect(!drawer.usesClipStencil)
    }

    @Test func frameResetClosesOpenClips() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.pushClip(square())
        drawer.beginFrame()                  // an early exit left the block open
        #expect(drawer.activeClipLevel == 0)
        #expect(!drawer.usesClipStencil)
        #expect(drawer.batches.isEmpty)
    }

    @Test func clippingIsPerSurface() {
        let drawer = Drawer()
        drawer.beginFrame()
        let target = RenderTarget(width: 64, height: 64, scale: 1, drawer: drawer)
        drawer.withClip(square()) {
            #expect(drawer.activeClipLevel == 1)
            drawer.withTarget(target) {
                // A layer starts unclipped: the canvas's region doesn't reach in.
                #expect(drawer.activeClipLevel == 0)
                drawer.withClip(square()) {
                    drawer.drawCircle(10, 10, 4)
                    #expect(drawer.activeClipLevel == 1)
                }
            }
            #expect(drawer.activeClipLevel == 1)   // back on the canvas's level
        }
        #expect(target.needsStencil)
        #expect(drawer.usesClipStencil)
        // The layer's clip batches are tagged for it, not the canvas.
        let targetBatches = drawer.batches.filter { $0.target === target }
        #expect(targetBatches.map(\.kind) == [.clipPush, .sdf, .clipPop])
    }

    @Test func stateChangesInsideClipDoNotLeak() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.fill(.white)
        drawer.withClip(square()) {
            drawer.fill(.red)
            drawer.blendMode(.add)
        }
        #expect(drawer.fillPaint == .color(.white))
        #expect(drawer.currentBlend == .normal)
    }

    /// A fixture for the vector export: a rect-clipped circle, then an
    /// unclipped rect after the pop.
    final class ClipSVGFixture: Sketch {
        override var canvasSize: CanvasSize { .square(100) }

        override func draw() {
            background(.white)
            noStroke()
            withClip(Rectangle(x: 10, y: 10, width: 50, height: 50)) {
                fill(.black)
                drawCircle(30, 30, 20)
            }
            fill(.black)
            drawRect(70, 70, 10, 10)
        }
    }

    @Test func svgExportEmitsClipPaths() throws {
        let svg = OllinApp.svg(of: ClipSVGFixture())
        #expect(svg.contains("<clipPath id=\"clip0\">"))
        let open = try #require(svg.range(of: "<g clip-path=\"url(#clip0)\">"))
        let close = try #require(svg.range(of: "</g>"))
        let circle = try #require(svg.range(of: "<circle"))
        let rect = try #require(svg.range(of: "<rect x=\"70\""))
        // The clipped circle sits inside the group; the later rect sits after it.
        #expect(open.lowerBound < circle.lowerBound)
        #expect(circle.lowerBound < close.lowerBound)
        #expect(close.lowerBound < rect.lowerBound)
    }
}
