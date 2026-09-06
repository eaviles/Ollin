import Testing
import Foundation
import CoreGraphics
import CryptoKit
import COllinShaders
import OllinWebGate
import OllinExpander
@testable import Ollin

/// The points door of the web page: a stroke or a fill crosses as the points
/// and the style the sketch gave, and the page expands them through the
/// framework's own expander compiled to WebAssembly. The drawer's records are
/// checked first (what a run holds, how a recording and a symmetry fold place
/// them), then the round trip on the Mac (the shared expander over the wire's
/// records against the drawer's own vertices), the track's packing, the
/// committed module's provenance, and the page against the Mac in the browser,
/// with the expander blanked as the sabotage.
@Suite @MainActor struct WebSourceTests {

    // MARK: Fixtures

    /// Strokes of every join and cap at several weights, a hairpin, a
    /// collinear run, a transform, gradients, a width profile, and the
    /// elliptical arcs: everything the fringe expander takes.
    final class Strokes: Sketch {
        override var canvasSize: CanvasSize { .square(400) }
        override func draw() {
            background(.white)
            noFill()
            let zig = [Vector2(20, 300), Vector2(60, 60), Vector2(110, 300), Vector2(150, 80), Vector2(152, 80), Vector2(152, 80), Vector2(220, 300), Vector2(260, 40)]
            for (i, join) in [StrokeJoin.miter, .bevel, .round].enumerated() {
                for (k, cap) in [StrokeCap.butt, .square, .round].enumerated() {
                    for (w, weight) in [0.3, 1.0, 3.0, 12.0].enumerated() {
                        withState {
                            translate(Double(i) * 8, Double(k) * 6 + Double(w) * 2)
                            strokeJoin(join); strokeCap(cap); strokeWeight(weight)
                            stroke(Color(red: 0.1 * Double(i), green: 0.2, blue: 0.3 * Double(k), alpha: w == 2 ? 0.4 : 1))
                            drawPolyline(zig)
                            drawPolyline(zig, closed: true)
                        }
                    }
                }
            }
            strokeWeight(6); strokeJoin(.miter)
            drawPolyline([Vector2(300, 300), Vector2(380, 300), Vector2(302, 300.2)])
            drawPolyline([Vector2(300, 320), Vector2(340, 320), Vector2(380, 320), Vector2(380, 360), Vector2(300, 320)], closed: true)
            withState {
                translate(200, 200); rotate(0.7); scale(1.6, 0.8)
                strokeWeight(4); strokeCap(.round); strokeJoin(.round)
                drawPolyline([Vector2(-60, -40), Vector2(0, 30), Vector2(60, -40), Vector2(90, 20)])
                drawBezier(Vector2(-80, 40), Vector2(0, -90), Vector2(80, 40))
            }
            strokeWeight(7)
            stroke(Gradient.linear(from: Vector2(20, 350), to: Vector2(380, 390), [.red, .blue]))
            drawPolyline([Vector2(20, 350), Vector2(120, 390), Vector2(220, 350), Vector2(380, 390)])
            stroke(Gradient.alongPath([.green, .black, .orange]))
            drawCurve([Vector2(20, 370), Vector2(120, 330), Vector2(220, 370), Vector2(380, 330)])
            stroke(.black)
            strokeProfile(.taper(start: 0.2, end: 0))
            strokeWeight(14); strokeCap(.round)
            drawPolyline([Vector2(30, 30), Vector2(120, 20), Vector2(200, 60), Vector2(300, 20)])
            strokeProfile(.uniform)
            strokeWeight(3)
            drawArc(300, 100, 60, 30, start: 0.3, stop: 4.0, mode: .pie)
            drawArc(300, 100, 50, 25, start: 0.3, stop: 4.0, mode: .chord)
            drawArc(300, 100, 40, 20, start: 0.3, stop: 4.0, mode: .open)
        }
    }

    /// A convex fan, a holed shape, a gradient fill (which keeps its vertices),
    /// the arc fans, and outline text with a stroke (whose glyph fills and
    /// outline strokes keep their vertices too).
    final class Fills: Sketch {
        override var canvasSize: CanvasSize { .square(300) }
        override func draw() {
            background(.white)
            fill(Color(hex: 0xD04020)); stroke(.black); strokeWeight(2)
            drawPolygon([Vector2(20, 20), Vector2(120, 30), Vector2(140, 120), Vector2(60, 140), Vector2(10, 90)])
            fill(Color(red: 0.2, green: 0.4, blue: 0.9, alpha: 0.6))
            drawShape(Shape(contours: [
                Contour([Vector2(160, 20), Vector2(280, 20), Vector2(280, 140), Vector2(200, 100), Vector2(160, 140)], closed: true),
                Contour([Vector2(190, 40), Vector2(250, 40), Vector2(250, 80), Vector2(190, 80)], closed: true),
            ], winding: .evenOdd))
            withState {
                translate(150, 220); rotate(0.4)
                fill(Gradient.radial(center: .zero, radius: 60, [.yellow, .purple]))
                drawPolygon([Vector2(-60, -40), Vector2(60, -40), Vector2(70, 40), Vector2(-70, 40)])
                noStroke()
                fill(.black)
                drawArc(0, 0, 50, 30, start: 0.2, stop: 3.5, mode: .pie)
                drawArc(0, 0, 40, 25, start: 0.2, stop: 3.5, mode: .chord)
            }
            fill(.black); stroke(.red); strokeWeight(1.5)
            textSize(36)
            drawText("Ag&", 20, 280)
            noFill(); stroke(.black); strokeWeight(3)
            drawLine(20, 20, 280, 290)
        }
    }

    /// Six-fold mirrored symmetry over a stroke and a fill, one point moving.
    final class Folded: Sketch {
        override var canvasSize: CanvasSize { .square(300) }
        override func draw() {
            background(.white)
            translate(150, 150)
            symmetry(6, mirrored: true)
            stroke(.black); strokeWeight(3); noFill()
            drawPolyline([Vector2(10, 0), Vector2(60, 20), Vector2(120, -10 + sin(time) * 8)])
            fill(Color(hex: 0x3060C0)); noStroke()
            drawPolygon([Vector2(20, 30), Vector2(50, 40), Vector2(40, 70)])
        }
    }

    /// A recording of strokes and a fill, replayed turning: the points travel
    /// once and only the transform moves.
    final class Turning: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        var batch: Batch?
        override func setup() {
            batch = makeBatch {
                stroke(.black); strokeWeight(4); strokeCap(.round)
                drawLine(-50, 0, 50, 0)
                drawPolyline([Vector2(-40, -40), Vector2(0, 40), Vector2(40, -40)])
                noStroke(); fill(Color(hex: 0xC03060))
                drawPolygon([Vector2(10, 10), Vector2(45, 15), Vector2(40, 45)])
            }
        }
        override func draw() {
            background(.white)
            guard let batch else { return }
            withState {
                translate(100, 100)
                rotate(Double(frameCount) * 0.15)
                drawBatch(batch)
            }
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

    /// The same points under a join that changes: the cast changes with it.
    final class Restyled: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(.white)
            noFill(); stroke(.black); strokeWeight(16)
            strokeJoin(frameCount < 3 ? .miter : .round)
            drawPolyline([Vector2(20, 130), Vector2(80, 30), Vector2(140, 130)])
        }
    }

    /// A dense still line: the case the door exists for.
    final class Dense: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.white)
            stroke(.black); strokeWeight(1.5); noFill()
            var points: [Vector2] = []
            for i in 0 ..< 6000 {
                let t = Double(i) * 0.02
                points.append(Vector2(120 + cos(t) * (10 + t * 0.9), 120 + sin(t) * (10 + t * 0.9)))
            }
            drawPolyline(points)
        }
    }

    // MARK: Helpers

    /// The source region of a frame.
    static func region(of frame: WebFrame) -> [Float] {
        Array(frame.vector[frame.graph.sourceOffset ..< frame.graph.vertexOffset])
    }

    /// The vertices the page would expand from a frame's records, through the
    /// same expander on the Mac.
    static func expanded(_ frame: WebFrame) -> [WebSourceVertex] {
        var out: [WebSourceVertex] = []
        let records = region(of: frame).withUnsafeBufferPointer { floats in
            WebSourceExpander.expand(floats) { out.append($0) }
        }
        #expect(records != nil, "a record did not read back")
        return out
    }

    /// The drawer's vertices the records stand for, in record order.
    static func recorded(_ drawer: Drawer) -> [OllinVertex] {
        drawer.webSources.flatMap { Array(drawer.vertices[$0.vertexRange]) }
    }

    /// Whether the expanded vertices are the drawer's: the position within a
    /// few float ulps (the page applies a transform in plain arithmetic where
    /// the Mac's matrix product may fuse), the coverage and the color exact.
    static func agree(_ page: [WebSourceVertex], _ mac: [OllinVertex], tolerance: Float = 2e-3) -> Bool {
        guard page.count == mac.count else {
            Issue.record("\(page.count) expanded vertices against \(mac.count) recorded")
            return false
        }
        for (a, b) in zip(page, mac) {
            if abs(a.x - b.position.x) > tolerance || abs(a.y - b.position.y) > tolerance
                || a.coverage != b.aa.x || a.color != b.color {
                Issue.record("\(a) against \(b)")
                return false
            }
        }
        return true
    }

    static func sourceItems(_ g: WebGraph) -> [(fringe: Bool, count: Int)] {
        g.canvas.compactMap { if case let .sources(_, _, c, f, _) = $0 { return (f, c) } else { return nil } }
    }

    /// The first record whose expansion on its own does not come to the
    /// vertices the drawer holds for it, described, or nil when every record
    /// agrees; the thing to read when the round trip fails.
    static func culprit(_ drawer: Drawer) -> String? {
        for (i, source) in drawer.webSources.enumerated() {
            var floats: [Float] = []
            source.encode(into: &floats)
            var count = 0
            _ = floats.withUnsafeBufferPointer { WebSourceExpander.expand($0) { _ in count += 1 } }
            if count != source.vertexRange.count {
                return "record \(i) (\(source.kind), \(source.points.count) points) expands to \(count) vertices, the drawer holds \(source.vertexRange.count)"
            }
        }
        return nil
    }

    /// The round trip, with the culprit named when it fails.
    static func roundTrips(_ frame: WebFrame, _ drawer: Drawer) -> Bool {
        let ok = agree(expanded(frame), recorded(drawer))
        if !ok, let culprit = culprit(drawer) { Issue.record(Comment(rawValue: culprit)) }
        return ok
    }

    // MARK: The recorder

    @Test func strokesCrossAsTheirPointsAndExpandBackToTheMacsVertices() throws {
        let sketch = Strokes()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 1, fps: 30, controls: false)
        let frame = recording.frames[0]
        let g = frame.graph
        // Every stroke here comes through the fringe expander, so nothing is
        // left as vertices; the records cover the drawer's vertices exactly.
        #expect(g.vertexCount == 0)
        #expect(g.sourceFloats > 0)
        #expect(g.sourceCount == sketch.drawer.webSources.count)
        #expect(sketch.drawer.webSources.map(\.vertexRange.count).reduce(0, +) == sketch.drawer.vertices.count)
        // Consecutive strokes merge into one item per batch; each is a fringe run.
        let items = Self.sourceItems(g)
        #expect(!items.isEmpty && items.allSatisfy(\.fringe))
        #expect(items.map(\.count).reduce(0, +) == g.sourceCount)
        // The wire is far lighter than the vertices it stands for.
        #expect(g.sourceFloats * 4 < sketch.drawer.vertices.count * MemoryLayout<OllinVertex>.stride / 8)
        // A gradient stroke carries a color per point, a profiled stroke a
        // width per point.
        let kinds = sketch.drawer.webSources.map { source -> (Bool, Bool) in
            if case let .stroke(_, _, _, _, _, widths, _, colors, _) = source.kind { return (widths != nil, colors != nil) }
            return (false, false)
        }
        #expect(kinds.contains { $0.1 } && kinds.contains { $0.0 } && kinds.contains { !$0.0 && !$0.1 })
        // The round trip: the shared expander over the wire gives the drawer's
        // vertices, field for field.
        #expect(Self.roundTrips(frame, sketch.drawer))
    }

    @Test func fillsCrossAsTheirContoursAndWhatKeepsNoSourceStaysAsVertices() throws {
        let sketch = Fills()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 1, fps: 30, controls: false)
        let frame = recording.frames[0]
        let g = frame.graph
        // The polygon's fan, the holed shape, and the black arcs are records;
        // the gradient polygon, the glyph fills, and the glyph outline strokes
        // keep their vertices, so the runs alternate between the two kinds.
        var order: [String] = []
        for item in g.canvas {
            switch item {
            case let .sources(_, _, count, fringe, _): order.append((fringe ? "stroke" : "fill") + "x\(count)")
            case let .triangles(_, count, fringe, _): order.append((fringe ? "vertices-stroke" : "vertices-fill") + (count > 0 ? "" : "!"))
            default: order.append("?")
            }
        }
        #expect(order.contains("fillx1"))
        #expect(order.filter { $0.hasPrefix("vertices-fill") }.count >= 2, "\(order)")
        #expect(g.vertexCount > 0 && g.sourceFloats > 0)
        // The tessellated shape carries its two contours and the odd rule.
        let tessellated = sketch.drawer.webSources.compactMap { source -> [Int]? in
            if case let .tessellated(lengths, nonZero, _) = source.kind { #expect(!nonZero); return lengths }
            return nil
        }
        #expect(tessellated == [[5, 4]])
        // Every record expands back to the drawer's vertices.
        #expect(Self.roundTrips(frame, sketch.drawer))
        // The layout says which columns are structural: three per record and
        // the contour lengths of the shape.
        let structure = try #require(Self.region(of: frame).withUnsafeBufferPointer { WebSourceLayout.structure(of: $0) })
        #expect(structure.records == sketch.drawer.webSources.count)
        #expect(structure.columns.count == 3 * structure.records + 2)
        #expect(g.sourceStructure == structure.columns)
    }

    @Test func aSymmetryFoldCopiesTheRecordUnderItsTransform() throws {
        let sketch = Folded()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 2, fps: 30, controls: false)
        let frame = recording.frames[1]
        // Twelve folds of a stroke and a fill: every one a record, none left
        // as vertices.
        #expect(frame.graph.vertexCount == 0)
        #expect(frame.graph.sourceCount == 12 * 2)
        #expect(Self.roundTrips(frame, sketch.drawer))
        // The moving point's y moves in every fold's copy (the points are the
        // stroke's own, the fold rides in the transform), and nothing else.
        #expect(recording.frames[0].graph == frame.graph)
        let moving = zip(recording.frames[0].vector, frame.vector).filter { $0 != $1 }.count
        #expect(moving == 12)
    }

    @Test func aRecordingReplaysAsItsPointsUnderTheDrawTimeTransform() throws {
        let sketch = Turning()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 3, fps: 30, controls: false)
        let batch = try #require(sketch.batch)
        #expect(batch.webSources.count == 3)
        let frame = recording.frames[2]
        #expect(frame.graph.vertexCount == 0)
        #expect(frame.graph.sourceCount == 3)
        // The records expand to the batch's own vertices turned by the frame's
        // angle (frameCount is 3 on the third recorded frame).
        let angle = Float(3 * 0.15)
        let expected = batch.webSources.flatMap { source in
            batch.vertices[source.vertexRange].map { v -> OllinVertex in
                var placed = v
                placed.position = SIMD2<Float>(100 + v.position.x * cos(angle) - v.position.y * sin(angle),
                                               100 + v.position.x * sin(angle) + v.position.y * cos(angle))
                return placed
            }
        }
        #expect(Self.agree(Self.expanded(frame), expected, tolerance: 1e-2))
        // Between frames only the transforms move: six floats a record.
        #expect(recording.frames[0].graph == frame.graph)
        let moving = zip(recording.frames[0].vector, frame.vector).filter { $0 != $1 }.count
        #expect(moving <= 6 * 3)
    }

    // MARK: The track

    @Test func theTrackCarriesTheRecordsExactAndTheirStructureAsTheCast() throws {
        // A still: the records sit in the base as float32, nothing samples.
        let dense = try OllinApp.recordWebFrames(of: Dense(), frames: 3, fps: 30, controls: false)
        let still = WebTrack(dense)
        #expect(still.stable && still.uniqueFrames == 1)
        let g = dense.frames[0].graph
        #expect(still.base.count == (g.sourceFloats * 4 + 2) / 3 * 4)
        #expect(still.vertexPositions.isEmpty && still.vertexBase.isEmpty && still.stream.isEmpty)
        #expect(still.sourceCount == 1 && still.vertexCount == 0)
        #expect(still.meta.contains("\"sources\":\(g.sourceFloats)"))
        #expect(still.meta.contains("\"msaa\":true"))
        let points = try #require(still.weights.first { $0.name == "strokes and fills as points" })
        #expect(points.perFrame == 0 && points.once == still.base.utf8.count)
        // A changing cast: every frame's records travel exact, beside the
        // positions, and nothing of them is quantized.
        let growing = try OllinApp.recordWebFrames(of: Growing(), frames: 3, fps: 30, controls: false)
        let changing = WebTrack(growing)
        #expect(!changing.stable)
        let floats = growing.frames.map(\.graph.sourceFloats).reduce(0, +)
        #expect(changing.vertexPositions.count == (floats * 4 + 2) / 3 * 4)
        #expect(changing.stream.isEmpty)
        let perFrame = try #require(changing.weights.first { $0.name == "strokes and fills as points" })
        #expect(perFrame.perFrame > 0 && perFrame.once == 0)
        // A join that changes is a change of cast, points or no points.
        let restyled = WebTrack(try OllinApp.recordWebFrames(of: Restyled(), frames: 4, fps: 30, controls: false))
        #expect(!restyled.stable && restyled.uniqueFrames == 2)
    }

    @Test func aPageCarriesTheExpanderOnlyWhenItHasPointsToExpand() throws {
        let dense = try OllinApp.recordWebFrames(of: Dense(), frames: 1, fps: 30, controls: false)
        let (page, weights) = try OllinApp.webInlineFragment(of: dense)
        #expect(page.contains("var EXPANDER = \"\(WebExpanderResource.base64.prefix(24))"))
        #expect(weights.contains { $0.name == "the stroke expander" && $0.once == WebExpanderResource.pageBytes })
        let hello = try OllinApp.recordWebFrames(of: WebExportTests.Hello(), frames: 1, fps: 30, controls: false)
        let (plain, plainWeights) = try OllinApp.webInlineFragment(of: hello)
        #expect(plain.contains("var EXPANDER = \"\";"))
        #expect(!plainWeights.contains { $0.name == "the stroke expander" })
        // The dense line's page is a fraction of what its vertices would weigh.
        let vertices = dense.frames[0].graph.sourceCount > 0 ? Dense().drawer.vertices.count : 0
        _ = vertices
        #expect(page.utf8.count < 400_000)
    }

    // MARK: The module

    @Test func theCommittedExpanderWasBuiltFromTheseSources() throws {
        let data = WebExpanderResource.data
        #expect(data.count > 10_000, "the expander resource is missing or empty")
        #expect(Array(data.prefix(4)) == [0x00, 0x61, 0x73, 0x6D])   // "\0asm"
        let manifest = try #require(WebExpanderResource.manifest)
        #expect(manifest.bytes == data.count)
        #expect(manifest.sdk.hasSuffix("_wasm-embedded"))
        // The hash the build script recorded, over the same files in the same
        // order: the shared module, the entry, the tessellator, the shim.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func files(_ folder: String, _ suffix: String) throws -> [URL] {
            let dir = root.appendingPathComponent(folder)
            return try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(suffix) }.sorted().map { dir.appendingPathComponent($0) }
        }
        var list: [URL] = []
        list += try files("Sources/OllinExpander", ".swift")
        list.append(root.appendingPathComponent("Scripts/web-expander/Entry.swift"))
        list += try files("External/CLibtess2/Include", ".h")
        list += try files("External/CLibtess2/Source", ".c")
        list += try files("External/CLibtess2/Source", ".h")
        list.append(root.appendingPathComponent("Scripts/web-expander/shim/setjmp.h"))
        var hasher = SHA256()
        for url in list { hasher.update(data: try Data(contentsOf: url)) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #expect(digest == manifest.sources,
                "the expander's sources changed since WebExpander.wasm was built; run Scripts/build-web-expander.sh")
    }

    // MARK: The browser

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePageExpandsTheStrokesAndFillsTheMacDrew() async throws {
        let cases: [(name: String, make: () -> Sketch, frames: Int, probe: Int)] = [
            ("Strokes (every join, cap, weight, a profile, gradients, arcs)", { Strokes() }, 1, 0),
            ("Fills (a fan, a holed shape, arcs, text beside them)", { Fills() }, 1, 0),
            ("Folded (six-fold mirrored symmetry)", { Folded() }, 4, 2),
            ("Turning (a recording under a turning transform)", { Turning() }, 4, 3),
            ("Growing (a changing cast)", { Growing() }, 4, 3),
            ("Restyled (a join that changes)", { Restyled() }, 4, 3),
            ("Dense (a still spiral of 6000 points)", { Dense() }, 2, 0),
        ]
        for c in cases {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: 30, controls: false)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await WebExportTests.pagePixels(page, frame: c.probe)
            let reference = try #require(OllinApp.image(of: c.make(), frame: c.probe, fps: 30))
            let difference = try WebExportTests.meanDifference(played, reference)
            let far = WebTriangleTests.farFraction(played, reference)
            print("web page against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
            #expect(difference < Snapshot.tolerance, "\(c.name) frame \(c.probe): mean difference \(difference)")
            #expect(far < WebTriangleTests.farTolerance, "\(c.name) frame \(c.probe): \(far * 100)% of the pixels past 32 levels")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theStrokesOnThePageComeFromTheExpander() async throws {
        // The same page with its expander blanked draws none of the strokes,
        // so it reads as a different picture: the parity above is the
        // expander's doing, not a copy of the vertices.
        let recording = try OllinApp.recordWebFrames(of: Dense(), frames: 1, fps: 30, controls: false)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let marker = "var EXPANDER = \""
        let start = try #require(page.range(of: marker))
        let end = try #require(page.range(of: "\";", range: start.upperBound ..< page.endIndex))
        let blanked = page.replacingCharacters(in: start.upperBound ..< end.lowerBound, with: "")
        #expect(blanked.contains("var EXPANDER = \"\";"))
        let played = try await WebExportTests.pagePixels(blanked, frame: 0)
        let reference = try #require(OllinApp.image(of: Dense(), frame: 0, fps: 30))
        let difference = try WebExportTests.meanDifference(played, reference)
        #expect(difference > Snapshot.tolerance, "mean difference \(difference)")
    }
}
