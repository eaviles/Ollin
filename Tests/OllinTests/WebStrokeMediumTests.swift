import CoreGraphics
import Foundation
import Testing
@testable import Ollin
import OllinExpander
import OllinWebGate

/// Strokes under a medium on a recorded page: each crosses as its ribbon
/// runs, the shared expander gives back the renderer's vertex pairs (the
/// ribbon's own coordinates included) from them, the page lays them through
/// the medium's own shading under a one-coat stencil, and a wet or oil stroke
/// on the canvas drags the canvas the page draws first without it. On a
/// canvas that keeps its paint it is refused by name.
@Suite @MainActor struct WebStrokeMediumTests {

    /// A pencil scribble that crosses itself, a multicolor pastel loop, a
    /// profiled bristle stroke in two pigments, a dashed dry brush, and a
    /// charcoal line under a turn, on paper.
    final class Media: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            background(Color(hex: 0xF4EFE3))
            noFill()
            strokeMedium(.pencil)
            stroke(Color(hex: 0x2A2A30)); strokeWeight(3)
            drawPolyline([Vector2(20, 30), Vector2(90, 70), Vector2(30, 90), Vector2(100, 20), Vector2(60, 110)])
            strokeMedium(.pastel(palette: [Color(hex: 0xC2452D), Color(hex: 0xE9B84A), Color(hex: 0x2B6C8C)], seed: 3))
            strokeWeight(10)
            drawCircle(145, 55, 32)
            strokeMedium(.bristles(Color(hex: 0x1E5631), streaks: 9, amount: 0.5, seed: 2))
            stroke(Color(hex: 0x8DB255)); strokeWeight(16)
            strokeProfile(.taper())
            drawCurve([Vector2(20, 150), Vector2(70, 110), Vector2(120, 190), Vector2(180, 140)], closed: false)
            noStrokeProfile()
            strokeMedium(.dryBrush(amount: 0.7, seed: 5))
            stroke(Color(hex: 0x5A3A22)); strokeWeight(12)
            strokeDash(.dashes(26, gap: 10))
            drawLine(20, 185, 185, 178)
            noStrokeDash()
            strokeMedium(.charcoal)
            stroke(Color(hex: 0x1A1B1E)); strokeWeight(6)
            withState {
                translate(150, 120); rotate(0.4 + time * 0.2)
                drawLine(-30, 0, 30, 0)
            }
        }
    }

    /// Every ribbon vertex the shared expander gives back from one source's
    /// records, thirteen floats each.
    static func expanded(_ source: WebSource) -> [ArraySlice<Float>] {
        var floats: [Float] = []
        source.encode(into: &floats)
        var out: [Float] = []
        let runs = floats.withUnsafeBufferPointer { WebSourceExpander.expandRibbons($0, into: &out) }
        #expect(runs != nil, "a ribbon record did not read back")
        let n = WebSourceExpander.ribbonVertexFloats
        return stride(from: 0, to: out.count, by: n).map { out[$0 ..< $0 + n] }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMediumStrokeCrossesAsItsRibbonRunsAndExpandsBackToTheRenderersPairs() throws {
        let sketch = Media()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 1, fps: 30, controls: false)
        let g = recording.frames[0].graph
        #expect(g.hasRibbons)
        let items = g.canvas.filter { if case .ribbons = $0 { return true }; return false }
        #expect(items.count == 5, "one item a stroke")
        let drawer = sketch.drawer
        let ribbons = drawer.webSources.filter { if case .ribbons = $0.kind { return true }; return false }
        #expect(ribbons.count == 5)
        let dashed = ribbons.contains { source in
            if case let .ribbons(runs, _, _, _, _, whole, _) = source.kind { return runs.count > 1 && whole != nil }
            return false
        }
        #expect(dashed, "the dashed stroke is several runs on one path")
        var worst = (position: Float(0), arc: Float(0), across: Float(0), along: Float(0))
        for source in ribbons {
            let page = Self.expanded(source)
            let pairs = Array(drawer.vertices[source.vertexRange])
            try #require(page.count * 2 == pairs.count, "\(page.count) expanded against \(pairs.count / 2) pairs")
            for (k, slice) in page.enumerated() {
                let v = Array(slice)
                let a = pairs[2 * k], r = pairs[2 * k + 1]
                worst.position = max(worst.position, abs(v[0] - a.position.x), abs(v[1] - a.position.y))
                #expect(v[2] == a.aa.x && SIMD4(v[3], v[4], v[5], v[6]) == a.color)
                worst.arc = max(worst.arc, abs(v[7] - r.aa.x))
                worst.across = max(worst.across, abs(v[8] - r.aa.y))
                worst.along = max(worst.along, abs(v[10] - r.color.z))
                #expect(abs(v[9] - r.color.x) < 1e-3 && v[11] == r.color.y && abs(v[12] - r.color.w) < 1e-2)
            }
        }
        // The points cross in single precision, so the page's ribbon sits a few
        // float steps from the Mac's and no further.
        #expect(worst.position < 2e-3, "\(worst)")
        #expect(worst.arc < 1e-2 && worst.across < 1e-3 && worst.along < 1e-4, "\(worst)")
    }

    /// A wet stroke over two marks, and an oil stroke across the wet one,
    /// over a mark drawn after it, which the wet stroke drags all the same.
    final class Wet: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        var drags = true
        override func draw() {
            background(Color(hex: 0xF4EFE3))
            noStroke()
            fill(Color(hex: 0xE07A2E)); drawCircle(60, 70, 34)
            fill(Color(hex: 0x2B6C8C)); drawRect(92, 40, 46, 60)
            noFill()
            if drags { strokeMedium(.wet()) }
            stroke(Color(hex: 0x8E2C48)); strokeWeight(18)
            drawCurve([Vector2(14, 72), Vector2(70, 60), Vector2(120, 84), Vector2(150, 66)], closed: false)
            if drags { strokeMedium(.oil(relief: 1.4)) }
            stroke(Color(hex: 0x3E7A3A)); strokeWeight(16)
            drawLine(30, 130, 140, 112)
            noStrokeMedium()
            noStroke(); fill(Color(hex: 0xF2C14E)); drawCircle(110, 124, 14)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aWetStrokeOnTheCanvasCrossesMarkedToDragItsGround() throws {
        let recording = try OllinApp.recordWebFrames(of: Wet(), frames: 1, fps: 30, controls: false)
        let marked = recording.frames[0].graph.canvas.filter {
            if case let .ribbons(_, _, _, _, readsGround) = $0 { return readsGround }
            return false
        }
        #expect(marked.count == 2, "the wet stroke and the oil stroke each drag the ground")
    }

    /// A wet stroke on a canvas that keeps its paint.
    final class WetPile: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func setup() { noClear() }
        override func draw() {
            if frameCount == 1 { background(.white) }
            noStroke(); fill(.orange); drawCircle(60, 60, 30)
            noFill(); stroke(.blue); strokeWeight(14)
            strokeMedium(.wet())
            drawLine(10, 60, 110, 60)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aWetStrokeOnACanvasThatKeepsItsPaintIsRefusedByName() throws {
        do {
            _ = try OllinApp.recordWebFrames(of: WetPile(), frames: 1, fps: 30, controls: false)
            Issue.record("a wet stroke over a pile crossed")
        } catch let refusal as WebExportRefusal {
            #expect(refusal.call.contains("noClear"))
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePageDragsTheGroundTheMacDragged() async throws {
        let recording = try OllinApp.recordWebFrames(of: Wet(), frames: 2, fps: 30, controls: false)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 1)
        let reference = try OllinApp.image(of: Wet(), frame: 1, fps: 30)
        let difference = try WebExportTests.meanDifference(played, reference)
        let far = WebTriangleTests.farFraction(played, reference)
        print("web page against the Mac: wet and oil frame 1, mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
        #expect(difference < Snapshot.tolerance, "mean difference \(difference)")
        #expect(far < 0.01, "\(far * 100)% of the pixels past 32 levels")
        // Without the drag and the relief the page would draw flat ribbons in
        // the pigment: the parity above is the ground and the light crossing.
        let flat = Wet()
        flat.drags = false
        let plain = try OllinApp.image(of: flat, frame: 1, fps: 30)
        #expect(try WebExportTests.meanDifference(played, plain) > difference + 1)
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePageLaysTheDryMediaTheMacDrew() async throws {
        let recording = try OllinApp.recordWebFrames(of: Media(), frames: 4, fps: 30, controls: false)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 2)
        let reference = try OllinApp.image(of: Media(), frame: 2, fps: 30)
        let difference = try WebExportTests.meanDifference(played, reference)
        let far = WebTriangleTests.farFraction(played, reference)
        print("web page against the Mac: dry media frame 2, mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
        #expect(difference < Snapshot.tolerance, "mean difference \(difference)")
        // A dry medium thresholds its tooth sharply, so a coordinate a float
        // step off on the page turns a whole speckle on or off, and the page
        // samples four times where the Mac samples eight: the far pixels are
        // those flips, scattered (0.3% measured), never a region.
        #expect(far < 0.01, "\(far * 100)% of the pixels past 32 levels")
        // Without its medium the page would draw plain ribbons: the parity
        // above is the medium's shading crossing, not flat strokes.
        let plain = try OllinApp.image(of: Plain(), frame: 2, fps: 30)
        #expect(try WebExportTests.meanDifference(played, plain) > difference + 1)
    }

    /// The same strokes with no medium, the picture the page would draw if the
    /// shading did not cross.
    final class Plain: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            background(Color(hex: 0xF4EFE3))
            noFill()
            stroke(Color(hex: 0x2A2A30)); strokeWeight(3)
            drawPolyline([Vector2(20, 30), Vector2(90, 70), Vector2(30, 90), Vector2(100, 20), Vector2(60, 110)])
            stroke(Color(hex: 0xC2452D)); strokeWeight(10)
            drawCircle(145, 55, 32)
            stroke(Color(hex: 0x8DB255)); strokeWeight(16)
            strokeProfile(.taper())
            drawCurve([Vector2(20, 150), Vector2(70, 110), Vector2(120, 190), Vector2(180, 140)], closed: false)
            noStrokeProfile()
            stroke(Color(hex: 0x5A3A22)); strokeWeight(12)
            strokeDash(.dashes(26, gap: 10))
            drawLine(20, 185, 185, 178)
            noStrokeDash()
            stroke(Color(hex: 0x1A1B1E)); strokeWeight(6)
            withState {
                translate(150, 120); rotate(0.4 + time * 0.2)
                drawLine(-30, 0, 30, 0)
            }
        }
    }
}
