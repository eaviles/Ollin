import Ollin
import Testing
import Foundation

/// Checks on the DXF exporter. Like the G-code tests, these record draw calls
/// on the CPU and never touch Metal, so they run everywhere. Each file is read
/// back through a small reader below, and the tests assert drawing facts (the
/// skeleton every reader looks for, millimeters and the flip, a layer per
/// color, a circle kept as a circle, touching paths merged, clipping honored)
/// rather than exact text.
@Suite
@MainActor
struct DXFExportTests {

    // MARK: - A small DXF reader

    /// The file as its sections: the header's variables, the layer table, and
    /// every entity with its layer and points.
    struct Document {
        struct Entity {
            var type: String
            var layer: String
            var points: [(x: Double, y: Double)]
            var radius: Double?
            var closed = false
        }
        var version = ""
        var units = -1
        var extents = (minX: 0.0, minY: 0.0, maxX: 0.0, maxY: 0.0)
        var layers: [(name: String, color: Int)] = []
        var entities: [Entity] = []
        var sawEOF = false

        init(_ text: String) {
            // Group code / value pairs, one per two lines.
            let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
            var pairs: [(Int, String)] = []
            var i = 0
            while i + 1 < lines.count {
                if let code = Int(lines[i].trimmingCharacters(in: .whitespaces)) {
                    pairs.append((code, lines[i + 1]))
                }
                i += 2
            }
            var section = ""
            var variable = ""
            var current: Entity? = nil
            var polyline: Entity? = nil
            var layerName: String? = nil
            func finish() {
                if let done = current { entities.append(done) }
                current = nil
            }
            for (code, value) in pairs {
                if code == 0 {
                    if value == "EOF" { sawEOF = true; finish(); continue }
                    if value == "SECTION" || value == "ENDSEC" || value == "TABLE" || value == "ENDTAB" {
                        finish()
                        if value == "ENDSEC" { section = "" }
                        continue
                    }
                    if section == "ENTITIES" {
                        switch value {
                        case "POLYLINE":
                            finish()
                            polyline = Entity(type: "POLYLINE", layer: "", points: [])
                        case "VERTEX":
                            current = Entity(type: "VERTEX", layer: "", points: [])
                        case "SEQEND":
                            if let done = current, done.type == "VERTEX" { polyline?.points += done.points }
                            current = nil
                            if let done = polyline { entities.append(done) }
                            polyline = nil
                        default:
                            finish()
                            current = Entity(type: value, layer: "", points: [])
                        }
                        continue
                    }
                    if section == "TABLES", value == "LAYER" {
                        layerName = ""
                    }
                    continue
                }
                if code == 2, section.isEmpty { section = value; continue }
                if code == 9 { variable = value; continue }
                if section == "HEADER" {
                    switch (variable, code) {
                    case ("$ACADVER", 1): version = value
                    case ("$INSUNITS", 70): units = Int(value.trimmingCharacters(in: .whitespaces)) ?? -1
                    case ("$EXTMIN", 10): extents.minX = Double(value) ?? 0
                    case ("$EXTMIN", 20): extents.minY = Double(value) ?? 0
                    case ("$EXTMAX", 10): extents.maxX = Double(value) ?? 0
                    case ("$EXTMAX", 20): extents.maxY = Double(value) ?? 0
                    default: break
                    }
                    continue
                }
                if section == "TABLES", layerName != nil {
                    if code == 2 { layerName = value }
                    if code == 62, let name = layerName {
                        layers.append((name, Int(value.trimmingCharacters(in: .whitespaces)) ?? -1))
                        layerName = nil
                    }
                    continue
                }
                if section == "ENTITIES" {
                    if current?.type == "VERTEX" {
                        if code == 10 { current?.points.append((Double(value) ?? 0, 0)) }
                        if code == 20 { current!.points[current!.points.count - 1].y = Double(value) ?? 0 }
                        if code == 8, polyline != nil, polyline!.layer.isEmpty { polyline!.layer = value }
                        // A vertex's own points are folded into the polyline at SEQEND.
                        if code == 8 { current?.layer = value }
                        continue
                    }
                    if polyline != nil, current == nil {
                        if code == 8 { polyline!.layer = value }
                        if code == 70 { polyline!.closed = (Int(value.trimmingCharacters(in: .whitespaces)) ?? 0) & 1 == 1 }
                        continue
                    }
                    guard current != nil else { continue }
                    switch code {
                    case 8: current!.layer = value
                    case 10, 11: current!.points.append((Double(value) ?? 0, 0))
                    case 20, 21: current!.points[current!.points.count - 1].y = Double(value) ?? 0
                    case 40: current!.radius = Double(value)
                    default: break
                    }
                }
            }
        }

        func entities(on layer: String) -> [Entity] { entities.filter { $0.layer == layer } }
        func ofType(_ type: String) -> [Entity] { entities.filter { $0.type == type } }
    }

    /// The reader folds a polyline's vertices as they arrive; this re-reads a
    /// file's polylines' vertices in order, since the fold above appends only
    /// the last vertex per SEQEND.
    private func polylines(in text: String) -> [(layer: String, closed: Bool, points: [(x: Double, y: Double)])] {
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        var pairs: [(Int, String)] = []
        var i = 0
        while i + 1 < lines.count {
            if let code = Int(lines[i].trimmingCharacters(in: .whitespaces)) { pairs.append((code, lines[i + 1])) }
            i += 2
        }
        var out: [(layer: String, closed: Bool, points: [(x: Double, y: Double)])] = []
        var inPolyline = false, inVertex = false
        for (code, value) in pairs {
            if code == 0 {
                switch value {
                case "POLYLINE": inPolyline = true; inVertex = false; out.append(("", false, []))
                case "VERTEX": inVertex = true
                case "SEQEND": inPolyline = false; inVertex = false
                default: inPolyline = false; inVertex = false
                }
                continue
            }
            guard inPolyline, !out.isEmpty else { continue }
            if inVertex {
                if code == 10 { out[out.count - 1].points.append((Double(value) ?? 0, 0)) }
                if code == 20 { out[out.count - 1].points[out[out.count - 1].points.count - 1].y = Double(value) ?? 0 }
            } else {
                if code == 8 { out[out.count - 1].layer = value }
                if code == 70 { out[out.count - 1].closed = (Int(value.trimmingCharacters(in: .whitespaces)) ?? 0) & 1 == 1 }
            }
        }
        return out
    }

    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }

    // MARK: - The skeleton

    @Test func theFileHasTheSkeletonEveryReaderLooksFor() {
        let text = OllinApp.dxf(of: Lines(), settings: DXF(width: 200, margin: 5))
        let doc = Document(text)
        #expect(doc.version == "AC1009", "the R12 dialect")
        #expect(doc.units == 4, "millimeters")
        #expect(doc.sawEOF)
        #expect(text.hasPrefix("  0\r\nSECTION\r\n  2\r\nHEADER"), "group codes padded to three columns, lines ended the way a drawing program writes them")
        #expect(near(doc.extents.minX, 0) && near(doc.extents.minY, 0))
        #expect(near(doc.extents.maxX, 210) && near(doc.extents.maxY, 110), "the extents are the size with the margin: \(doc.extents)")
        #expect(!doc.layers.isEmpty && doc.layers.allSatisfy { (1...9).contains($0.color) })
    }

    // MARK: - Millimeters and the flip

    @Test func theTopEdgeIsTheDrawingsTopInMillimeters() {
        // A line two units under the top of a 200 × 100 canvas, mapped to 100 mm
        // wide with a 5 mm margin: it lands at y = 54, from x = 10 to 100.
        let text = OllinApp.dxf(of: Lines(), settings: DXF(width: 100, margin: 5))
        let doc = Document(text)
        let lines = doc.ofType("LINE")
        let top = lines.first { $0.points.allSatisfy { near($0.y, 54) } }
        #expect(top != nil, "the line near the top is at 54 mm: \(lines.map(\.points))")
        if let top {
            let xs = top.points.map(\.x).sorted()
            #expect(near(xs[0], 10) && near(xs[1], 100))
        }
        // The one near the bottom lands at y = 6: the canvas's down is the drawing's down turned over.
        #expect(lines.contains { $0.points.allSatisfy { near($0.y, 6) } })
        // Nothing leaves the drawing.
        for entity in doc.entities {
            for p in entity.points {
                #expect(p.x >= -0.01 && p.x <= 110.01 && p.y >= -0.01 && p.y <= 60.01, "\(p) is inside")
            }
        }
    }

    // MARK: - Layers

    @Test func eachColorIsALayerNamedByItsBytes() {
        let doc = Document(OllinApp.dxf(of: Colors(), settings: DXF(width: 100)))
        let names = doc.layers.map(\.name)
        #expect(names == ["color-000000", "color-FF0000", "color-0000FF"], "layers in the order first drawn: \(names)")
        #expect(doc.layers.map(\.color) == [7, 1, 5], "black is the foreground, red is 1, blue is 5")
        #expect(doc.entities(on: "color-FF0000").count == 2, "the red stroke and the red fill share a layer")
        #expect(doc.entities(on: "color-0000FF").count == 1)
        // The planner exposes the same layers before anything is written.
        let plan = OllinApp.drafting(of: Colors(), settings: DXF(width: 100))
        #expect(plan.layers.map(\.name) == names)
        #expect(plan.entities(on: "color-FF0000").count == 2)
        #expect(near(plan.size.width, 100) && near(plan.size.height, 50))
    }

    // MARK: - Circles

    @Test func aCircleStaysACircleUnlessSomethingSkewsIt() {
        let doc = Document(OllinApp.dxf(of: Circles(), settings: DXF(width: 100)))
        let circles = doc.ofType("CIRCLE")
        #expect(circles.count == 2, "the plain circle and the turned, uniformly scaled one: \(circles.count)")
        // The plain one: center (50, 50) of a 200 × 100 canvas, radius 20, at half scale.
        let plain = circles.first { near($0.points[0].x, 25) }
        #expect(plain != nil)
        #expect(plain.map { near($0.points[0].y, 25) } == true, "its center is 25 mm up from the bottom")
        #expect(plain?.radius.map { near($0, 10) } == true, "its radius is scaled with the drawing")
        // The turned one was drawn at radius 10 under a scale of 2, so it is 20
        // canvas units across the half, 10 mm here, and still a circle.
        let scaled = circles.first { near($0.points[0].x, 75) }
        #expect(scaled?.radius.map { near($0, 10) } == true, "\(String(describing: scaled?.radius))")
        // The one under a non-uniform scale is flattened, so the file has one
        // closed polyline for it and no third circle.
        let flattened = polylines(in: OllinApp.dxf(of: Circles(), settings: DXF(width: 100)))
        #expect(flattened.count == 1 && flattened[0].closed && flattened[0].points.count > 12)
    }

    // MARK: - Merging, lines, and clipping

    @Test func touchingPathsMergeAndATwoPointPathIsALine() {
        let joined = polylines(in: OllinApp.dxf(of: Chain(), settings: DXF(width: 100)))
        #expect(joined.count == 1, "the four touching segments become one polyline: \(joined.count)")
        #expect(joined.first?.points.count == 5)
        let apart = Document(OllinApp.dxf(of: Chain(), settings: DXF(width: 100, joinTolerance: 0)))
        #expect(apart.ofType("LINE").count == 4, "with no tolerance each segment is its own line")
        #expect(apart.ofType("POLYLINE").isEmpty)
    }

    @Test func aClipCutsTheWork() {
        let doc = Document(OllinApp.dxf(of: Clipped(), settings: DXF(width: 100)))
        // The line ran the full width; only the middle half survives the clip.
        let line = doc.ofType("LINE").first
        #expect(line != nil)
        if let line {
            let xs = line.points.map(\.x).sorted()
            #expect(near(xs[0], 25) && near(xs[1], 75), "clipped to 25...75 mm: \(xs)")
        }
    }

    @Test func aFillIsAClosedPolylineUnlessHatched() {
        let solid = polylines(in: OllinApp.dxf(of: Filled(), settings: DXF(width: 100)))
        #expect(solid.count == 1 && solid[0].closed && solid[0].points.count == 4, "a rect fill is one closed polyline")
        let hatched = OllinApp.dxf(of: Filled(), settings: DXF(width: 100), hatching: Hatching(spacing: 4))
        let doc = Document(hatched)
        #expect(doc.ofType("LINE").count > 10, "hatched, the fill is line work: \(doc.ofType("LINE").count) lines")
    }

    @Test func thePublicPlannerTakesPlainContours() {
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let square = Contour([Vector2(10, 10), Vector2(90, 10), Vector2(90, 90), Vector2(10, 90)], closed: true)
        let plan = DXF(width: 50).drafting([square, Contour([Vector2(0, 50), Vector2(100, 50)], closed: false)], in: canvas)
        #expect(plan.layers.map(\.name) == ["0"])
        #expect(plan.entities.count == 2)
        let doc = Document(plan.text)
        #expect(doc.ofType("LINE").count == 1 && doc.ofType("POLYLINE").count == 1)
        #expect(near(plan.size.width, 50) && near(plan.size.height, 50))
    }

    @Test func theExportWritesTheFile() throws {
        let path = NSTemporaryDirectory() + "ollin-dxf-test-\(UUID().uuidString).dxf"
        OllinApp.exportDXF(Lines(), to: path, settings: DXF(width: 100))
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(Document(text).sawEOF)
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Probe sketches

/// Two lines across the canvas, one two units under the top edge and one two
/// units above the bottom, apart so they stay two lines.
private final class Lines: Sketch {
    override var canvasSize: CanvasSize { .size(200, 100) }
    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(2)
        drawLine(10, 2, 190, 2)
        drawLine(10, 98, 190, 98)
    }
}

/// Black, then red (a stroke and a fill), then blue.
private final class Colors: Sketch {
    override var canvasSize: CanvasSize { .size(200, 100) }
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        drawLine(10, 10, 190, 10)
        stroke(.red)
        drawLine(10, 30, 190, 30)
        noStroke()
        fill(.red)
        drawRect(20, 40, 40, 20)
        stroke(.blue)
        noFill()
        drawLine(10, 90, 190, 90)
    }
}

/// A plain circle, one under a turn and a uniform scale, and one squashed.
private final class Circles: Sketch {
    override var canvasSize: CanvasSize { .size(200, 100) }
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        drawCircle(50, 50, 20)
        withState {
            translate(150, 50)
            rotate(0.7)
            scale(2)
            drawCircle(0, 0, 10)
        }
        withState {
            translate(100, 50)
            scale(2, 0.5)
            drawCircle(0, 0, 10)
        }
    }
}

/// Four segments drawn end to end.
private final class Chain: Sketch {
    override var canvasSize: CanvasSize { .size(200, 100) }
    override func draw() {
        background(.white)
        stroke(.black)
        drawLine(10, 50, 60, 50)
        drawLine(60, 50, 110, 50)
        drawLine(110, 50, 160, 50)
        drawLine(160, 50, 190, 50)
    }
}

/// One line across the canvas, inside a clip covering the middle half.
private final class Clipped: Sketch {
    override var canvasSize: CanvasSize { .size(200, 100) }
    override func draw() {
        background(.white)
        stroke(.black)
        withClip(Rectangle(x: 50, y: 0, width: 100, height: 100)) {
            drawLine(0, 50, 200, 50)
        }
    }
}

/// One filled rectangle.
private final class Filled: Sketch {
    override var canvasSize: CanvasSize { .size(200, 100) }
    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        drawRect(50, 25, 100, 50)
    }
}
