@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import simd
import COllinShaders

/// Lines drawn through the 3D camera (`drawLine`/`drawPolyline` over `Vector3`).
///
/// What a sketch is being promised: the line is the 2D stroke, joins and caps
/// and fringe, laid on the projection of its points; every vertex keeps the
/// depth of the point it was laid out around, so a solid hides the line exactly
/// where it covers it and the line hides what lies behind it; the soft edge
/// never stops something drawn later from showing beside the line; the weight
/// holds on screen along a receding line unless it is asked to be in world
/// units; and a line lying on a floor seen at a low angle keeps its ink.
@Suite
@MainActor
struct Lines3DTests {

    // MARK: Recording

    private func drawer(camera: Camera3D = .perspective(eye: Vector3(0, 0, 5))) -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(camera)
        return d
    }

    private let canvas = SIMD2<Float>(400, 300)

    @Test func aRunOfLineCallsIsOneBatch() {
        let d = drawer()
        d.drawPolyline3D([Vector3(-1, 0, 0), Vector3(1, 0, 0)], closed: false, canvas: canvas)
        d.drawPolyline3D([Vector3(0, -1, 0), Vector3(0, 1, 0)], closed: false, canvas: canvas)
        #expect(d.batches.count == 1)
        let b = d.batches[0]
        #expect(b.kind == .lines3D)
        #expect(b.lineCoreStart == 0 && b.lineFringeStart == 0)
        #expect(b.lineCoreCount == d.lineCoreVertices.count && b.lineCoreCount > 0)
        #expect(b.lineFringeCount == d.lineFringeVertices.count && b.lineFringeCount > 0)
        // A 2D draw between two lines opens a fresh batch, which starts where the
        // first one's runs end.
        d.drawRect(Rectangle(x: 0, y: 0, width: 10, height: 10))
        d.drawPolyline3D([Vector3(-1, 1, 0), Vector3(1, 1, 0)], closed: false, canvas: canvas)
        #expect(d.batches.count == 3)
        #expect(d.batches[2].lineCoreStart == b.lineCoreCount)
        #expect(d.batches[2].lineFringeStart == b.lineFringeCount)
        #expect(d.batches[2].lineCoreStart + d.batches[2].lineCoreCount == d.lineCoreVertices.count)
    }

    @Test func theCoreIsWhollyCoveredAndTheFringeIsNot() {
        let d = drawer()
        d.strokeWidth = 4
        d.strokeJoinStyle = .round
        d.strokeCapStyle = .round
        d.drawPolyline3D([Vector3(-1, 0, 0), Vector3(0, 1, -1), Vector3(1, 0, 0.5)], closed: false, canvas: canvas)
        #expect(d.lineCoreVertices.allSatisfy { $0.coverage >= 1 })
        for t in stride(from: 0, to: d.lineFringeVertices.count, by: 3) {
            let tri = d.lineFringeVertices[t ..< t + 3]
            #expect(tri.contains { $0.coverage < 1 })
        }
    }

    @Test func withoutACameraNothingIsRecordedAndANoteSaysWhy() {
        let d = Drawer()
        d.beginFrame()
        d.drawPolyline3D([Vector3(0, 0, 0), Vector3(1, 0, 0)], closed: false, canvas: canvas)
        #expect(d.batches.isEmpty && d.lineVertexCount == 0)
        #expect(d.drawerNotes.contains { $0.contains("draw through the 3D camera") })
    }

    @Test func aRecordedBatchHoldsNoLines() {
        let d = drawer()
        let batch = d.makeBatch {
            d.drawPolyline3D([Vector3(0, 0, 0), Vector3(1, 0, 0)], closed: false, canvas: canvas)
        }
        #expect(batch.innerBatches.isEmpty)
        #expect(d.lineVertexCount == 0)
    }

    @Test func everyVertexHoldsAPointOfTheLineMovedByTheModelMatrix() {
        let d = drawer()
        d.translate(0.5, -0.25, 0.1)
        let points = [Vector3(-1, 0, 0), Vector3(0, 1, -1), Vector3(1, 0, 0.5)]
        d.drawPolyline3D(points, closed: false, canvas: canvas)
        let placed = points.map { SIMD3<Float>(Float($0.x + 0.5), Float($0.y - 0.25), Float($0.z + 0.1)) }
        for v in d.lineCoreVertices + d.lineFringeVertices {
            let p = SIMD3<Float>(v.position.x, v.position.y, v.position.z)
            #expect(placed.contains { simd_distance($0, p) < 1e-5 })
        }
    }

    @Test func aColorForEachPointColorsTheVerticesBuiltAroundIt() {
        let d = drawer()
        let points = [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)]
        let colors: [Color] = [.red, .green, .blue]
        d.drawPolyline3D(points, colors: colors, closed: false, canvas: canvas)
        for v in d.lineCoreVertices + d.lineFringeVertices {
            let k = points.firstIndex { abs(Float($0.x) - v.position.x) < 1e-5 && abs(Float($0.y) - v.position.y) < 1e-5 }!
            #expect(v.color == colors[k].simd4)
        }
        // A list of the wrong length is set aside for the stroke color, with a note.
        let e = drawer()
        e.strokePaint = .color(.orange)
        e.drawPolyline3D(points, colors: [.red], closed: false, canvas: canvas)
        #expect((e.lineCoreVertices + e.lineFringeVertices).allSatisfy { $0.color == Color.orange.simd4 })
        #expect(e.drawerNotes.contains { $0.contains("one color per point") })
    }

    /// The canvas position of a recorded vertex: its world point through the
    /// camera, plus its offset.
    private func canvasPosition(_ v: OllinLineVertex, camera: Camera3D, canvas: SIMD2<Float>) -> SIMD2<Double> {
        let vp = camera.viewProjectionMatrix(aspect: Double(canvas.x / canvas.y))
        let c = vp * SIMD4<Float>(v.position.x, v.position.y, v.position.z, 1)
        let x = (Double(c.x / c.w) + 1) / 2 * Double(canvas.x)
        let y = (1 - Double(c.y / c.w)) / 2 * Double(canvas.y)
        return SIMD2(x + Double(v.offset.x), y + Double(v.offset.y))
    }

    @Test(arguments: [StrokeJoin.miter, .bevel, .round])
    func joinsAndCapsAreTheTwoDimensionalStrokesOnTheProjection(join: StrokeJoin) {
        let camera = Camera3D.perspective(eye: Vector3(1.5, 2, 6), target: .zero)
        let points = [Vector3(-2, 0, 0), Vector3(-0.5, 1.2, -1), Vector3(0.6, -0.4, 0.8),
                      Vector3(1.8, 0.9, -0.3), Vector3(2.2, -1, 1.5)]
        for cap in [StrokeCap.butt, .square, .round] {
            let d = drawer(camera: camera)
            d.strokeWidth = 7
            d.strokeJoinStyle = join
            d.strokeCapStyle = cap
            d.drawPolyline3D(points, closed: false, canvas: canvas)
            // The same stroke drawn in 2D through the points the camera puts them at.
            let flat = drawer(camera: camera)
            flat.strokeWidth = 7
            flat.strokeJoinStyle = join
            flat.strokeCapStyle = cap
            flat.drawPolyline(points.map { flat.project($0, viewport: canvas)! }, closed: false)
            // Split the 2D triangles the way the 3D path does, then compare each
            // class in order, vertex for vertex.
            var core: [OllinVertex] = [], fringe: [OllinVertex] = []
            for t in stride(from: 0, to: flat.vertices.count, by: 3) {
                let tri = Array(flat.vertices[t ..< t + 3])
                if tri.allSatisfy({ $0.aa.x >= 1 }) { core += tri } else { fringe += tri }
            }
            #expect(core.count == d.lineCoreVertices.count, "\(join) \(cap) core")
            #expect(fringe.count == d.lineFringeVertices.count, "\(join) \(cap) fringe")
            var worst = 0.0
            let pairs = Array(zip(core, d.lineCoreVertices)) + Array(zip(fringe, d.lineFringeVertices))
            for (a, b) in pairs {
                let p = canvasPosition(b, camera: camera, canvas: canvas)
                worst = max(worst, abs(p.x - Double(a.position.x)), abs(p.y - Double(a.position.y)))
                #expect(abs(a.aa.x - b.coverage) < 1e-4)
            }
            #expect(worst < 0.01, "\(join) \(cap): a vertex lands \(worst) points from the 2D stroke's")
        }
    }

    @Test func whatLiesBehindTheCameraIsCutAwayAtTheNearPlane() {
        let camera = Camera3D.perspective(eye: Vector3(0, 0, 0), target: Vector3(0, 0, -1), near: 0.1)
        let d = drawer(camera: camera)
        d.drawPolyline3D([Vector3(0.2, -0.1, -10), Vector3(0.1, 0.2, 5)], closed: false, canvas: canvas)
        let all = d.lineCoreVertices + d.lineFringeVertices
        #expect(!all.isEmpty)
        // Every vertex sits in front of the camera, and the cut end on the near plane.
        #expect(all.allSatisfy { $0.position.z <= -0.1 + 1e-5 })
        #expect(all.contains { abs($0.position.z + 0.1) < 1e-4 })
        // A closed loop the camera stands inside opens behind the camera and keeps
        // what lies in front of it, in one piece.
        let e = drawer(camera: camera)
        e.drawPolyline3D([Vector3(-1, 0.5, -3), Vector3(1, 0.5, -3), Vector3(1, 0.5, 3), Vector3(-1, 0.5, 3)],
                         closed: true, canvas: canvas)
        let loop = e.lineCoreVertices + e.lineFringeVertices
        #expect(!loop.isEmpty && loop.allSatisfy { $0.position.z <= -0.1 + 1e-5 })
        #expect(loop.contains { $0.position.x == -1 && $0.position.z == -3 })
        #expect(loop.contains { $0.position.x == 1 && $0.position.z == -3 })
    }

    /// The widest offset among the vertices built around the point nearest `z`.
    private func halfWidth(at z: Float, in d: Drawer) -> Float {
        (d.lineCoreVertices + d.lineFringeVertices)
            .filter { abs($0.position.z - z) < 1e-4 }
            .map { simd_length($0.offset) }.max() ?? 0
    }

    @Test func aScreenWeightHoldsAlongARecedingLineAndAWorldWeightShrinks() {
        let camera = Camera3D.perspective(eye: Vector3(0, 1, 2), target: Vector3(0, 0, -10))
        // Measured at the two inner points, whose vertices are cross-sections
        // only (the ends carry caps, which reach past the cross-section).
        let points = [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 0, -10), Vector3(1, 0, -40), Vector3(1, 0, -41)]
        let d = drawer(camera: camera)
        d.strokeWidth = 4
        d.drawPolyline3D(points, closed: false, canvas: canvas)
        // The outer edge sits half the weight plus half the fringe out, near and far.
        #expect(abs(halfWidth(at: 0, in: d) - 2.5) < 1e-3)
        #expect(abs(halfWidth(at: -40, in: d) - 2.5) < 1e-3)

        let w = drawer(camera: camera)
        w.strokeWidth = 0.1
        w.strokeUnitsMode = .world
        w.drawPolyline3D(points, closed: false, canvas: canvas)
        let near = halfWidth(at: 0, in: w) - 0.5, far = halfWidth(at: -40, in: w) - 0.5
        // Half a world-tenth seen from the distances the two points stand at.
        let projection = camera.projectionMatrix(aspect: Double(canvas.x / canvas.y))
        let perUnit = Double(projection.columns.1.y) * Double(canvas.y) / 2
        func distance(_ p: Vector3) -> Double {
            Double((camera.viewMatrix * SIMD4<Float>(p.simd3, 1)).z) * -1
        }
        #expect(abs(Double(near) - 0.05 * perUnit / distance(points[1])) < 1e-3)
        #expect(abs(Double(far) - 0.05 * perUnit / distance(points[3])) < 1e-3)
        #expect(near > 10 * far)
    }

    @Test func theUnitsAreSavedByWithState() {
        let d = drawer()
        d.pushState()
        d.strokeUnitsMode = .world
        d.popState()
        #expect(d.strokeUnitsMode == .screen)
    }

    @Test func aVectorExportCarriesTheProjectedLine() {
        // Four units tall on 256 points: (-1, 0.5) lands at (64, 96) and (1, -0.5)
        // at (192, 160), whatever the 2D transform says.
        // The file keeps a 2D transform as an attribute beside the points, so the
        // line's element must carry none.
        let svg = OllinApp.svg(of: VectorLineProbe())
        let line = svg.split(separator: "\n").first { $0.contains("64,96") }
        #expect(line?.contains("192,160") == true, "\(svg)")
        #expect(line?.contains("transform") == false, "\(line ?? "")")
    }

    @Test func aWebPageNamesTheCallItCannotCarry() {
        #expect(OllinApp.webRefusalName(for: .lines3D).contains("3D points"))
    }

    // MARK: In pixels

    private struct Frame {
        let width: Int, height: Int, data: [UInt8]
        func rgb(_ x: Int, _ y: Int) -> SIMD3<Int> {
            let i = (y * width + x) * 4
            return SIMD3(Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
    }

    private func frame(_ sketch: Sketch) throws -> Frame {
        let image = try OllinApp.image(of: sketch, frame: 1)
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Frame(width: w, height: h, data: data)
    }

    /// A red line on black, an orthographic camera four units tall on a 256-point
    /// canvas (64 points a unit), and a gray unit box at the origin, its front at
    /// z = 0.5: the box covers columns 96 to 160.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBoxHidesALineBehindItExactlyWhereItCovers() throws {
        let probe = BoxAndLineProbe()
        probe.lineZ = -1
        let f = try frame(probe)
        let red = (0 ..< f.width).filter { x in
            let c = f.rgb(x, 128); return c.x > 150 && c.y < 60 && c.z < 60
        }
        let gray = (0 ..< f.width).filter { x in
            let c = f.rgb(x, 128); return abs(c.x - c.y) < 8 && c.x > 90
        }
        #expect(red.contains(20) && red.contains(235))
        #expect(gray.first == 96 && gray.last == 159, "the box spans \(gray.first ?? -1) to \(gray.last ?? -1)")
        #expect(!red.contains { (96 ..< 160).contains($0) }, "the line shows through the box")
        // The line runs right up to the box on either side.
        #expect(red.contains(94) && red.contains(161))
    }

    /// The same box and line under temporal anti-aliasing and motion blur: the
    /// export draws the geometry once per jitter offset, and the line has to be
    /// drawn, and hidden, in every one of those passes.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theLineHoldsUnderTheJitteredAndBlurredPasses() throws {
        let probe = BoxAndLineProbe()
        probe.lineZ = -1
        probe.framePasses = true
        let f = try frame(probe)
        func isRed(_ x: Int) -> Bool { let c = f.rgb(x, 128); return c.x > 150 && c.y < 60 && c.z < 60 }
        #expect(isRed(20) && isRed(235) && isRed(90) && isRed(166))
        #expect(!(100 ..< 156).contains { isRed($0) }, "the line shows through the box")
        // The passes ran: the jitter softens the edges the plain frame draws.
        let plain = BoxAndLineProbe()
        plain.lineZ = -1
        let p = try frame(plain)
        let moved = (0 ..< f.data.count).filter { f.data[$0] != p.data[$0] }.count
        #expect(moved > 100, "only \(moved) bytes differ from the frame without the passes")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLineHidesWhatLiesBehindItWhicheverIsDrawnFirst() throws {
        let probe = BoxAndLineProbe()
        probe.lineZ = 1
        probe.lineFirst = true
        let f = try frame(probe)
        for x in 100 ... 156 {
            let c = f.rgb(x, 128)
            #expect(c.x > 150 && c.y < 60 && c.z < 60, "column \(x) shows the box over the line")
        }
        // And the soft edge never punches the box drawn after it: no pixel along
        // the line's edges over the box is darker than the box, which is what a
        // fringe that wrote depth would leave (the black ground showing through).
        let box = f.rgb(128, 100).x
        for y in 120 ... 136 {
            for x in 100 ... 156 {
                let c = f.rgb(x, y)
                #expect(max(c.x, c.y, c.z) >= box - 3, "(\(x), \(y)) reads \(c) over a box of \(box)")
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theWeightHoldsOnScreenAlongARecedingLine() throws {
        let f = try frame(RecedingLineProbe())
        // The line runs straight up the middle of the canvas, away from the camera.
        func span(_ y: Int) -> Int {
            (0 ..< f.width).filter { f.rgb($0, y).x > 127 }.count
        }
        let rows = [230, 180, 140, 120]   // the far end lands near row 115
        for y in rows {
            let r = (120 ..< 136).map { f.rgb($0, y).x }
            #expect(span(y) == 4, "row \(y) is \(span(y)) points wide: \(r)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLineOnAFloorSeenAtALowAngleKeepsItsInk() throws {
        let onFloor = try frame(FloorLinesProbe())
        let bare = FloorLinesProbe()
        bare.hasFloor = false
        let without = try frame(bare)
        // Ink is how far below the floor's gray a pixel reads. Below row 205 the
        // floor is seen at 7 degrees or more.
        var kept = 0, all = 0
        for y in 205 ..< onFloor.height {
            for x in 0 ..< onFloor.width {
                kept += max(0, 191 - onFloor.rgb(x, y).x)
                all += max(0, 191 - without.rgb(x, y).x)
            }
        }
        #expect(all > 0)
        #expect(Double(kept) / Double(all) > 0.99, "the floor hides \(100 - 100 * kept / max(all, 1))% of the ink")
    }
}

/// A line in 3D under a 2D translate, for the vector export.
private final class VectorLineProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        ortho(eye: Vector3(0, 0, 10), height: 4)
        translate(30, 0)
        stroke(.black)
        drawLine(Vector3(-1, 0.5, 0), Vector3(1, -0.5, 0))
    }
}

/// A gray unit box and a red line across it, at a depth the test sets.
private final class BoxAndLineProbe: Sketch {
    var lineZ = -1.0
    var lineFirst = false
    var framePasses = false
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 0, 10), height: 4)
        if framePasses { temporalAntialiasing(); motionBlur() }
        noLights()
        fill(Color(white: 0.5))
        stroke(.red)
        strokeWeight(6)
        if lineFirst { drawLine(Vector3(-2, 0, lineZ), Vector3(2, 0, lineZ)) }
        drawBox(size: 1)
        if !lineFirst { drawLine(Vector3(-2, 0, lineZ), Vector3(2, 0, lineZ)) }
    }
}

/// A white line four points wide running away from the camera up the middle of
/// the canvas.
private final class RecedingLineProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 1, 3), target: Vector3(0, 0, -10))
        stroke(.white)
        strokeWeight(4)
        drawLine(Vector3(0, 0, 2), Vector3(0, 0, -60))
    }
}

/// Blue lines lying on a light floor seen from just above it, or the same lines
/// on a ground of the floor's gray with no floor under them.
private final class FloorLinesProbe: Sketch {
    var hasFloor = true
    override var canvasSize: CanvasSize { .size(720, 360) }
    override func draw() {
        background(hasFloor ? Color(white: 0.1) : Color(white: 0.75))
        perspective(eye: Vector3(0, 0.35, 6), target: Vector3(0, 0, -4))
        noLights()
        fill(Color(white: 0.75))
        if hasFloor { withState { scale(30, 0.001, 30); drawBox(size: 1) } }
        stroke(Color(red: 0.1, green: 0.2, blue: 0.9))
        strokeWeight(3)
        for i in -6 ... 6 { drawLine(Vector3(Double(i) * 0.5, 0.0005, 5), Vector3(Double(i) * 0.5, 0.0005, -15)) }
        for k in 0 ... 12 {
            let z = 5 - Double(k) * 1.5
            drawLine(Vector3(-4, 0.0005, z), Vector3(4, 0.0005, z))
        }
    }
}
