import Testing
import Foundation
import CoreGraphics
import OllinWebGate
@testable import Ollin

/// The triangle door of the web page: a stroke's fringe bands and a fill's
/// triangles cross as the vertices the renderer would have drawn, under the
/// Mac's blend modes, and the page rasterizes them through a multisampled
/// buffer as the Mac does. The recorder is checked on its own (what a run
/// holds, how a recording replays under its transform, how the track packs the
/// vertices), then the page against the Mac in the shared browser gate.
@Suite @MainActor struct WebTriangleTests {

    // MARK: Fixtures

    /// Strokes with joins and caps, a bezier, a gradient stroke, a concave
    /// polygon, and a holed shape: the stroke path and the triangle path
    /// together, one vertex moving with the clock.
    final class Drawn: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.white)
            noFill()
            stroke(.black)
            strokeWeight(6)
            strokeJoin(.miter)
            strokeCap(.round)
            drawPolyline([Vector2(20, 200), Vector2(60, 40 + sin(time) * 10), Vector2(110, 200), Vector2(150, 60)])
            strokeWeight(2)
            stroke(Color(red: 0.2, green: 0.3, blue: 0.9, alpha: 0.7))
            drawBezier(Vector2(20, 220), Vector2(120, 100), Vector2(220, 220))
            strokeWeight(5)
            stroke(Gradient.linear(from: Vector2(160, 150), to: Vector2(230, 230), [.red, .blue]))
            drawLine(160, 150, 230, 230)
            noStroke()
            fill(Color(hex: 0xD04020))
            drawPolygon([Vector2(160, 30), Vector2(225, 60), Vector2(200, 130), Vector2(170, 90), Vector2(150, 120)])
            fill(Color(hex: 0x206040))
            stroke(.black)
            strokeWeight(1.5)
            drawShape { path in
                path.move(to: Vector2(30, 30))
                path.line(to: Vector2(120, 30))
                path.line(to: Vector2(120, 110))
                path.line(to: Vector2(30, 110))
                path.close()
                path.move(to: Vector2(55, 55))
                path.line(to: Vector2(95, 55))
                path.line(to: Vector2(95, 85))
                path.line(to: Vector2(55, 85))
                path.close()
            }
        }
    }

    /// Outline text, which fills through the triangle path.
    final class Captioned: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(.white)
            fill(.black)
            textSize(48)
            drawText("Ag", 20, 100)
        }
    }

    /// Translucent strokes and a shape under the additive and lightest modes.
    final class Blended: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(.black)
            blendMode(.add)
            strokeWeight(14)
            stroke(Color(red: 0.6, green: 0.1, blue: 0.1, alpha: 0.8))
            drawLine(10, 40, 150, 120)
            stroke(Color(red: 0.1, green: 0.1, blue: 0.7, alpha: 0.8))
            drawLine(10, 120, 150, 40)
            noStroke()
            fill(Color(red: 0.2, green: 0.5, blue: 0.2, alpha: 0.9))
            drawCircle(80, 80, 30)
            blendMode(.lightest)
            fill(Color(red: 0.4, green: 0.4, blue: 0.0, alpha: 1))
            drawPolygon([Vector2(30, 140), Vector2(130, 140), Vector2(80, 60)])
        }
    }

    /// A recording of strokes, a fill, and a shape, replayed turning.
    final class Batched: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        var batch: Batch?
        override func setup() {
            batch = makeBatch {
                stroke(.black)
                strokeWeight(4)
                drawLine(-40, 0, 40, 0)
                drawLine(0, -40, 0, 40)
                noStroke()
                fill(Color(hex: 0x3060C0))
                drawPolygon([Vector2(10, 10), Vector2(40, 10), Vector2(40, 40)])
                fill(Color(hex: 0xC03060))
                drawCircle(-25, -25, 10)
            }
        }
        override func draw() {
            background(.white)
            guard let batch else { return }
            withState {
                translate(80, 80)
                rotate(Double(frameCount) * 0.1)
                drawBatch(batch)
            }
        }
    }

    /// Lines piling onto a canvas that never clears: the multisampled surface
    /// keeps its samples from frame to frame.
    final class Piling: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        override func setup() {
            background(.white)
            noClear()
        }
        override func draw() {
            stroke(Color(red: 0, green: 0, blue: 0, alpha: 0.5))
            strokeWeight(3)
            let k = Double(frameCount)
            drawLine(10, 10 + k * 12, 150, 20 + k * 10)
        }
    }

    /// A stroke count that grows from frame to frame (a changing cast).
    final class Growing: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            stroke(.black)
            strokeWeight(2)
            for i in 0 ..< frameCount { drawLine(10, 10 + Double(i) * 12, 110, 20 + Double(i) * 12) }
        }
    }

    // MARK: The recorder

    @Test func strokesAndFillsCrossAsTheirVertices() throws {
        let sketch = Drawn()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 3, fps: 30)
        let frame = recording.frames[2]
        // The last recorded frame's vertices are the ones the drawer still holds.
        #expect(frame.graph.vertexCount == sketch.drawer.vertices.count)
        #expect(frame.graph.vertexCount > 100)
        #expect(frame.graph.instanceCount == 0 && frame.graph.quadCount == 0)
        #expect(frame.vector.count == frame.graph.vectorCount)
        #expect(frame.graph.hasTriangles)
        // In call order: the stroke path's bands (fringe), then the polygon's
        // fill (no fringe), then the holed shape's fill and its outline.
        var kinds: [Bool] = []
        for item in frame.graph.canvas {
            guard case let .triangles(_, count, fringe, blend) = item else { Issue.record("\(item)"); continue }
            #expect(count > 0 && blend == 0)
            kinds.append(fringe)
        }
        #expect(kinds == [true, false, true])
        // A vertex on the wire is the drawer's, field for field.
        let v = sketch.drawer.vertices[0]
        let onWire = Array(frame.vector[frame.graph.vertexOffset ..< frame.graph.vertexOffset + WebVertex.floats])
        #expect(onWire == [v.position.x, v.position.y, v.aa.x, v.color.x, v.color.y, v.color.z, v.color.w])
        // The moving vertex is the polyline's second point, so the frames differ.
        #expect(recording.frames[0].vector != recording.frames[2].vector)
        #expect(recording.frames[0].graph == recording.frames[2].graph)
    }

    @Test func outlineTextCrossesAsItsFills() throws {
        let recording = try OllinApp.recordWebFrames(of: Captioned(), frames: 1, fps: 30)
        let g = recording.frames[0].graph
        #expect(g.vertexCount > 0)
        #expect(g.canvas.count == 1)
        if case let .triangles(_, _, fringe, _) = g.canvas[0] { #expect(!fringe) } else { Issue.record("\(g.canvas)") }
    }

    @Test func aBlendModeCrossesOnShapesAndStrokes() throws {
        let recording = try OllinApp.recordWebFrames(of: Blended(), frames: 1, fps: 30)
        let g = recording.frames[0].graph
        var blends: [Int] = []
        for item in g.canvas {
            switch item {
            case let .triangles(_, _, _, blend), let .shapes(_, _, blend): blends.append(blend)
            default: Issue.record("\(item)")
            }
        }
        // The two lines (one fringe run), the circle, then the triangle under lightest.
        #expect(blends == [WebBlend.index(of: .add), WebBlend.index(of: .add), WebBlend.index(of: .lightest)])
        #expect(g.meta["canvas"] != nil)
    }

    @Test func aRecordingOfStrokesReplaysUnderItsTransform() throws {
        let sketch = Batched()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 2, fps: 30)
        let frame = recording.frames[1]
        let batch = try #require(sketch.batch)
        #expect(frame.graph.vertexCount == batch.vertices.count)
        #expect(frame.graph.instanceCount == 1)
        // The runs replay in the recording's order: the lines, the fill, the circle.
        var order: [String] = []
        for item in frame.graph.canvas {
            switch item {
            case let .triangles(_, _, fringe, _): order.append(fringe ? "stroke" : "fill")
            case .shapes: order.append("shape")
            default: order.append("?")
            }
        }
        #expect(order == ["stroke", "fill", "shape"])
        // A recorded vertex lands where the draw-time transform puts it: the
        // batch was made about the origin, so the first vertex turned by the
        // frame's angle sits 80 points in from the corner.
        let angle = Float(2 * 0.1)   // frameCount is 2 on the second recorded frame
        let v = batch.vertices[0].position
        let expected = SIMD2<Float>(80 + v.x * cos(angle) - v.y * sin(angle), 80 + v.x * sin(angle) + v.y * cos(angle))
        let vo = frame.graph.vertexOffset
        #expect(abs(frame.vector[vo] - expected.x) < 1e-3 && abs(frame.vector[vo + 1] - expected.y) < 1e-3,
                "\(frame.vector[vo]), \(frame.vector[vo + 1]) against \(expected)")
    }

    @Test func theTrackPacksTheVerticesOfAStableCastAsSamples() throws {
        let recording = try OllinApp.recordWebFrames(of: Drawn(), frames: 6, fps: 30)
        let track = WebTrack(recording)
        #expect(track.stable)
        let g = recording.frames[0].graph
        #expect(track.vertexCount == g.vertexCount)
        // The base holds the shapes, quads, and rows as floats (none here), the
        // vertices' positions exact, and their coverage and color as 16-bit
        // samples with a range per field.
        #expect(track.base.isEmpty)
        let sampled = WebVertex.floats - WebVertex.positionFloats
        #expect(track.vertexPositions.count == (g.vertexCount * WebVertex.positionFloats * 4 + 2) / 3 * 4)
        #expect(track.vertexBase.count == (g.vertexCount * sampled * 2 + 2) / 3 * 4)
        let meta = try #require(try JSONSerialization.jsonObject(with: Data(track.meta.utf8)) as? [String: Any])
        let vranges = try #require(meta["vranges"] as? [Double])
        #expect(vranges.count == 2 * sampled)
        #expect(vranges[0] >= 0 && vranges[1] <= 1)   // the coverage
        #expect(meta["msaa"] as? Bool == true)
        // Only the vertices the moving point reaches travel as columns.
        #expect(track.sampledColumns > 0 && track.sampledColumns < g.vertexCount * WebVertex.floats / 2,
                "\(track.sampledColumns) of \(g.vertexCount * WebVertex.floats)")
        #expect(track.fittedColumns == 0 && track.drivenColumns == 0)
        // A page with no triangles asks for no multisampling.
        let plain = WebTrack(try OllinApp.recordWebFrames(of: WebExportTests.Hello(), frames: 2, fps: 30))
        #expect(plain.meta.contains("\"msaa\":false"))
    }

    @Test func aChangingCastStoresItsVerticesByField() throws {
        let recording = try OllinApp.recordWebFrames(of: Growing(), frames: 3, fps: 30)
        let track = WebTrack(recording)
        #expect(!track.stable)
        #expect(track.base.isEmpty && track.vertexBase.isEmpty)
        let counts = recording.frames.map(\.graph.vertexCount)
        #expect(counts[0] < counts[1] && counts[1] < counts[2])
        // Every vertex of every frame: the position exact, two bytes a field for the rest.
        let total = counts.reduce(0, +)
        #expect(track.stream.count == (total * (WebVertex.floats - WebVertex.positionFloats) * 2 + 2) / 3 * 4)
        #expect(track.vertexPositions.count == (total * WebVertex.positionFloats * 4 + 2) / 3 * 4)
        #expect(track.meta.contains("\"positionOffsets\":[0,"))
        let meta = try #require(try JSONSerialization.jsonObject(with: Data(track.meta.utf8)) as? [String: Any])
        let ranges = WebTrack.floats(track.ranges)
        #expect(ranges.count == 2 * (WebInstance.floats + WebQuad.floats + WebGroup.floats + WebNode.floats
                                     + WebField.floats + WebNode3D.floats + WebVertex.floats))
        let graphs = try #require(meta["graphs"] as? [[String: Any]])
        #expect(graphs.count == 3)
        #expect(graphs[0]["vertices"] as? Int == counts[0])
    }

    @Test func thePagesTrianglePipelinesAreTheFrameworksOwn() throws {
        let shaders = try WebShaders.make()
        #expect(shaders.triangleFragment.contains("vec3 srgbToLinear(vec3 c)"))
        #expect(shaders.fringeFragment.contains("float perceptualCoverage(float c)"))
        #expect(shaders.fringeFragment.contains("vColor.a * perceptualCoverage(clamp(vCoverage, 0.0, 1.0))"))
        #expect(shaders.triangleVertex.contains("layout(location = 1) in float aCoverage;"))
        #expect(!shaders.fringeFragment.contains("float3"))
    }

    // MARK: The browser

    /// The fraction of pixels whose color is more than `levels` off between two
    /// same-sized images. A fill's aliased edge or a stroke drawn a shade too
    /// light moves few pixels but moves them far, which a mean over the whole
    /// picture barely sees.
    static func farFraction(_ a: CGImage, _ b: CGImage, past levels: Int = 32) -> Double {
        let x = WebExportTests.rgba(of: a), y = WebExportTests.rgba(of: b)
        var far = 0
        for i in stride(from: 0, to: min(x.count, y.count), by: 4) {
            var worst = 0
            for c in 0 ..< 3 { worst = max(worst, abs(Int(x[i + c]) - Int(y[i + c]))) }
            if worst > levels { far += 1 }
        }
        return Double(far) / Double(x.count / 4)
    }

    /// The most of a picture's pixels a page may put more than 32 levels off
    /// the Mac's: the figure gate's own line for a visible move.
    static let farTolerance = 0.002

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePageDrawsTheStrokesAndFillsTheMacDrew() async throws {
        let cases: [(name: String, make: () -> Sketch, frames: Int, probe: Int)] = [
            ("Drawn (joins, a bezier, a gradient stroke, a polygon, a holed shape)", { Drawn() }, 12, 0),
            ("Drawn, moving", { Drawn() }, 12, 7),
            ("Captioned (outline text)", { Captioned() }, 1, 0),
            ("Blended (add, lightest)", { Blended() }, 1, 0),
            ("Batched (a recording turning)", { Batched() }, 6, 3),
            ("Piling (an accumulating canvas)", { Piling() }, 8, 5),
            ("Growing (a changing cast)", { Growing() }, 4, 3),
        ]
        for c in cases {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: 30)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await WebExportTests.pagePixels(page, frame: c.probe)
            let reference = try #require(OllinApp.image(of: c.make(), frame: c.probe, fps: 30))
            let difference = try WebExportTests.meanDifference(played, reference)
            let far = Self.farFraction(played, reference)
            print("web page against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
            #expect(difference < Snapshot.tolerance, "\(c.name) frame \(c.probe): mean difference \(difference)")
            #expect(far < Self.farTolerance, "\(c.name) frame \(c.probe): \(far * 100)% of the pixels past 32 levels")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theGateSeesAMissingStroke() async throws {
        // The page at a frame with few lines against the Mac at the frame with
        // the most must read as different, or the parity above proves nothing.
        let recording = try OllinApp.recordWebFrames(of: Growing(), frames: 6, fps: 30)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 0)
        let elsewhere = try #require(OllinApp.image(of: Growing(), frame: 5, fps: 30))
        let difference = try WebExportTests.meanDifference(played, elsewhere)
        #expect(difference > Snapshot.tolerance, "mean difference \(difference)")
    }
}
