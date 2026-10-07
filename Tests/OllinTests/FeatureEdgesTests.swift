@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import simd
import COllinShaders

/// A mesh's feature edges (`featureEdges(creaseAngle:)`), the hidden-line solid.
///
/// What a sketch is being promised: a mesh's creases, its boundary, and its
/// silhouette draw over its faces in the stroke, and nothing else does (no
/// diagonal of a box, no tessellation of a sphere); the faces' depth hides the
/// edges of anything behind them and never their own; copies drawn as one
/// instanced draw ink exactly as the same meshes drawn one by one; an edge
/// is the 3D line's stroke, cross-section for cross-section; and the edge set
/// of a mesh is found once while the mesh keeps being drawn.
@Suite
@MainActor
struct FeatureEdgesTests {

    // MARK: The edges a mesh has

    private func kinds(_ set: FeatureEdgeSet) -> (boundary: Int, crease: Int, smooth: Int) {
        var counts = (boundary: 0, crease: 0, smooth: 0)
        for edge in set.edges {
            switch Int(edge.a.w) {
            case 0: counts.boundary += 1
            case 1: counts.crease += 1
            default: counts.smooth += 1
            }
        }
        return counts
    }

    @Test func aBoxHasTwelveCreasesAndItsDiagonalsAreSmooth() {
        let set = FeatureEdgeSet.find(in: .box(size: 1), creaseAngle: .pi / 6)
        let k = kinds(set)
        #expect(k.crease == 12 && k.smooth == 6 && k.boundary == 0, "\(k)")
        #expect(set.isClosed)
        // Every crease runs along an axis, a box's edge; every smooth edge across a face.
        for edge in set.edges {
            let d = edge.b - edge.a
            let axes = [abs(d.x), abs(d.y), abs(d.z)].filter { $0 > 1e-6 }.count
            #expect(axes == (Int(edge.a.w) == 1 ? 1 : 2))
        }
    }

    @Test func aSphereIsClosedAndSmoothEverywhere() {
        let set = FeatureEdgeSet.find(in: .sphere(), creaseAngle: .pi / 6)
        let k = kinds(set)
        #expect(set.isClosed)
        #expect(k.boundary == 0 && k.crease == 0 && k.smooth > 500, "\(k)")
    }

    @Test func aPlaneEndsInItsBoundary() {
        let set = FeatureEdgeSet.find(in: .plane(width: 2, depth: 2, segments: 2), creaseAngle: .pi / 6)
        let k = kinds(set)
        #expect(!set.isClosed)
        #expect(k.boundary == 8 && k.crease == 0, "\(k)")
    }

    @Test func aZeroAngleMakesEveryEdgeACrease() {
        let set = FeatureEdgeSet.find(in: .box(size: 1), creaseAngle: 0)
        #expect(kinds(set).crease == 18)
    }

    @Test func aMeshDrawnAgainIsSearchedOnce() {
        var cache = FeatureEdgeCache()
        let box = Mesh.box(size: 1)
        let first = cache.edges(of: box, creaseAngle: 0.5)
        #expect(cache.edges(of: box, creaseAngle: 0.5) === first, "the same arrays")
        #expect(cache.edges(of: Mesh.box(size: 1), creaseAngle: 0.5) === first, "an equal mesh built again")
        #expect(cache.count == 1)
        #expect(cache.edges(of: box, creaseAngle: 0.6) !== first, "another angle is another set")
        var moved = box
        moved.positions[0] = moved.positions[0] + Vector3(0, 0.1, 0)
        #expect(cache.edges(of: moved, creaseAngle: 0.5) !== first, "a changed mesh is searched again")
        #expect(cache.count == 3)
    }

    // MARK: Recording

    private func drawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(.perspective(eye: Vector3(0, 0, 5)))
        return d
    }

    @Test func theEdgesRideTheSolidDrawsCopies() {
        let d = drawer()
        d.featureEdges(creaseAngle: .pi / 6)
        let copies = (0..<5).map { MeshInstance(position: Vector3(Double($0), 0, 0)) }
        d.drawMeshInstanced(.box(size: 1), instances: copies)
        #expect(d.batches.map(\.kind) == [.meshInstanced, .lines3D])
        let solid = d.batches[0], edges = d.batches[1]
        #expect(edges.edgeSet?.edges.count == 18)
        #expect(edges.meshInstanceStart == solid.meshInstanceStart)
        #expect(edges.meshInstanceCount == 5)
        #expect(edges.edgeStyle.closed == 1)
        #expect(edges.worldBounds != nil)
    }

    @Test func aSingleMeshRidesItsOwnPlacement() {
        let d = drawer()
        d.featureEdges(creaseAngle: .pi / 6)
        d.translate(Vector3(1, 2, 3))
        d.drawMesh(.box(size: 1))
        #expect(d.batches.map(\.kind) == [.mesh3D, .lines3D])
        let edges = d.batches[1]
        #expect(edges.meshInstanceCount == 1)
        let placed = d.meshInstances[edges.meshInstanceStart].model
        #expect(placed.columns.3 == SIMD4<Float>(1, 2, 3, 1))
    }

    @Test func offByDefaultOffWithoutAStrokeAndUnderAWireframe() {
        let plain = drawer()
        plain.drawMesh(.box(size: 1))
        #expect(!plain.batches.contains { $0.edgeSet != nil })

        let unstroked = drawer()
        unstroked.featureEdges(creaseAngle: 0.5)
        unstroked.strokePaint = nil
        unstroked.drawMesh(.box(size: 1))
        #expect(!unstroked.batches.contains { $0.edgeSet != nil })

        let wire = drawer()
        wire.featureEdges(creaseAngle: 0.5)
        wire.wireframe(true)
        wire.drawMesh(.box(size: 1))
        #expect(!wire.batches.contains { $0.edgeSet != nil })
    }

    @Test func theStateIsSavedAndRestored() {
        let d = drawer()
        d.pushState()
        d.featureEdges(creaseAngle: 0.4)
        #expect(d.featureEdgeAngle == 0.4)
        d.popState()
        #expect(d.featureEdgeAngle == nil)
        d.featureEdges(creaseAngle: 0.4)
        d.noFeatureEdges()
        #expect(d.featureEdgeAngle == nil)
    }

    @Test func theStrokesWeightAndUnitsAreCarried() {
        let d = drawer()
        d.featureEdges(creaseAngle: 0.5)
        d.strokeWidth = 3
        d.strokeUnitsMode = .world
        d.drawMesh(.box(size: 1))
        let style = d.batches[1].edgeStyle
        #expect(style.halfWidth == 1.5 && style.worldUnits == 1)
    }

    // MARK: In pixels

    private func frame(_ sketch: Sketch) throws -> Pixels {
        Pixels(try OllinApp.image(of: sketch, frame: 1))
    }

    private func isInk(_ f: Pixels, _ x: Int, _ y: Int) -> Bool { f.gray(x, y) < 100 }

    /// A unit box seen face on through a perspective camera: the four edges of
    /// its near face, and nothing inside them, no diagonal.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBoxSeenFaceOnShowsOneSquare() throws {
        let f = try frame(EdgeBoxProbe())
        let row = (0..<f.width).filter { isInk(f, $0, 128) }
        // The near face's left and right edges cross the middle row, and nothing between.
        #expect(row.count >= 2)
        let left = row.min()!, right = row.max()!
        #expect(left < 100 && right > 156, "the near face spans \(left) to \(right)")
        let inside = row.filter { $0 > left + 4 && $0 < right - 4 }
        #expect(inside.isEmpty, "ink inside the near face at \(inside)")
        // The diagonal would cross the middle of the face.
        #expect(!isInk(f, 128, 128) && !isInk(f, 110, 110) && !isInk(f, 146, 146))
    }

    /// A thin slab turned about its vertical axis: its back face lies a few
    /// percent of the distance behind the front one, inside the depth pull, so
    /// the back face's far edge would show just inside the front face's right
    /// edge if it were drawn. Both of its faces turn away on a closed mesh, so
    /// it is not: one line on the right where the left shows the slab's
    /// thickness as two.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aCreaseThatTurnsAwayOnAClosedMeshIsLeftOut() throws {
        let f = try frame(SlabProbe())
        // A one-point line straddling two pixels lays half its ink in each, so
        // any pixel visibly darker than the paper counts.
        let row = (0..<f.width).map { f.gray($0, 128) < 200 }
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0...f.width {
            let ink = x < f.width && row[x]
            if ink, start == nil { start = x }
            if !ink, let s = start { runs.append(s ... x - 1); start = nil }
        }
        #expect(runs.count == 3, "ink runs on the middle row: \(runs)")
    }

    /// A sphere: its outline and nothing inside it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSphereShowsItsOutline() throws {
        let probe = EdgeBoxProbe()
        probe.sphere = true
        let f = try frame(probe)
        let row = (0..<f.width).filter { isInk(f, $0, 128) }
        #expect(row.count >= 2)
        let left = row.min()!, right = row.max()!
        #expect(right - left > 60)
        let inside = row.filter { $0 > left + 4 && $0 < right - 4 }
        #expect(inside.isEmpty, "the sphere's tessellation shows at \(inside)")
    }

    /// A curved surface's silhouette is one unbroken line: the darkest pixel
    /// on every ray out from the sphere's center across its outline is ink.
    /// (A silhouette edge runs beside a face seen nearly edge on, which hides
    /// whatever part of the line overlaps it, so a line centered on the edge
    /// comes out beaded; it is set just outside the contour instead.)
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSpheresOutlineIsUnbroken() throws {
        let f = try frame(SphereOutlineProbe())
        // The outline's radius on the canvas, read along the row through the center.
        let row = (0 ..< f.width).filter { f.gray($0, 256) < 128 }
        let radius = Double(row.max()! - row.min()!) / 2
        let center = Double(row.max()! + row.min()!) / 2
        var darkest: [Int] = []
        for k in 0 ..< 720 {
            let a = Double(k) / 720 * 2 * .pi
            var lowest = 255
            for step in stride(from: radius - 6, through: radius + 6, by: 0.25) {
                let x = Int(center + cos(a) * step), y = Int(256 + sin(a) * step)
                lowest = min(lowest, f.gray(x, y))
            }
            darkest.append(lowest)
        }
        let light = darkest.enumerated().filter { $0.element > 90 }
        #expect(light.isEmpty, "\(light.count) of 720 rays cross the outline without ink")
    }

    /// A near box over a far one, both filled white on gray: the far box's edge
    /// is hidden exactly where the near box's face covers it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aNearBoxHidesAFarBoxsEdges() throws {
        let f = try frame(TwoBoxesProbe())
        // The far box (64 points a unit, its left edge at x = 0.1, its bottom
        // at y = 0.1) runs up its left edge from behind the near box (which
        // ends at y = 0.5) into the open.
        let x = 128 + Int((0.1 * 64).rounded())
        let behind = (128 - 28 ... 128 - 10).filter { y in (x - 1 ... x + 1).contains { isInk(f, $0, y) } }
        let open = (128 - 60 ... 128 - 40).filter { y in (x - 1 ... x + 1).contains { isInk(f, $0, y) } }
        #expect(behind.isEmpty, "the far edge shows through the near box at rows \(behind)")
        #expect(open.count >= 15, "the far edge is missing where nothing covers it: \(open.count)")
        // The near box keeps its own outline whole along its top edge.
        let top = 128 - 32
        let gaps = (128 - 26 ... 128 + 26).filter { x in !(top - 1 ... top + 1).contains { isInk(f, x, $0) } }
        #expect(gaps.isEmpty, "the near box's own face eats its edge at columns \(gaps)")
    }

    /// Copies drawn as one instanced draw ink exactly as the same meshes drawn
    /// one at a time: the same matrices reach the same vertex shader. The
    /// copies stand apart on the canvas, since where two solids nearly touch
    /// the order they are drawn in decides an edge pulled toward the eye (see
    /// the next test for the order that holds whatever it is).
    @Test(.enabled(if: Snapshot.hasMetal))
    func copiesInkAsTheMeshesDrawnOneByOne() throws {
        let a = ScatteredBoxesProbe()
        a.instanced = true
        let b = ScatteredBoxesProbe()
        b.instanced = false
        let fa = try frame(a), fb = try frame(b)
        let inked = (0..<fa.width * fa.height).filter { fa.bytes[$0 * 4] < 128 }.count
        #expect(inked > 500, "only \(inked) inked pixels")
        #expect(fa.bytes == fb.bytes)
    }

    /// Two boxes drawn one call each, well apart in depth: the far box's edge is
    /// hidden behind the near box whichever is drawn first.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aNearBoxHidesAFarBoxsEdgesWhicheverIsDrawnFirst() throws {
        for nearFirst in [true, false] {
            let probe = TwoBoxesProbe()
            probe.oneByOne = true
            probe.nearFirst = nearFirst
            let f = try frame(probe)
            let x = 128 + Int((0.1 * 64).rounded())
            let behind = (128 - 28 ... 128 - 10).filter { y in (x - 1 ... x + 1).contains { isInk(f, $0, y) } }
            let open = (128 - 60 ... 128 - 40).filter { y in (x - 1 ... x + 1).contains { isInk(f, $0, y) } }
            #expect(behind.isEmpty && open.count >= 15,
                    "near box first: \(nearFirst), behind \(behind), open \(open.count)")
        }
    }

    /// An edge's cross-section is the 3D line's: the top edge of a box seen
    /// face on (ortho, no lights) against a `drawLine` along the same segment,
    /// at weights with no core, a core of whole pixels, and a wider one. The
    /// edge lies on a pixel boundary, where a core that misses part of a pixel
    /// shows as a gray line in place of a black one.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [1.0, 2.0, 3.0])
    func anEdgeIsTheLinesStroke(weight: Double) throws {
        let edge = EdgeAgainstLineProbe()
        edge.weight = weight
        let line = EdgeAgainstLineProbe()
        line.asLine = true
        line.weight = weight
        let fe = try frame(edge), fl = try frame(line)
        var worst = 0
        for y in 80 ..< 112 {
            for x in [120, 128, 136] {
                worst = max(worst, abs(fe.gray(x, y) - fl.gray(x, y)))
            }
        }
        #expect(worst <= 1, "the cross-sections differ by \(worst) levels at weight \(weight)")
        // And it is a stroke at all: the column crosses ink.
        #expect((80 ..< 112).contains { fe.gray(128, $0) < 140 })
    }

    /// Under temporal anti-aliasing and motion blur the edges are drawn, and
    /// hidden, in every jittered pass.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theEdgesHoldUnderTheJitteredAndBlurredPasses() throws {
        let probe = TwoBoxesProbe()
        probe.framePasses = true
        let f = try frame(probe)
        let x = 128 + Int((0.1 * 64).rounded())
        let behind = (128 - 28 ... 128 - 10).filter { y in isInk(f, x, y) }
        let open = (128 - 60 ... 128 - 40).filter { y in (x - 1 ... x + 1).contains { isInk(f, $0, y) } }
        #expect(behind.isEmpty && open.count >= 15, "behind \(behind), open \(open.count)")
    }
}

/// A unit box (or a sphere) under `featureEdges`, seen face on from 3 units.
private final class EdgeBoxProbe: Sketch {
    var sphere = false
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        perspective(eye: Vector3(0, 0, 3))
        noLights()
        fill(.white)
        stroke(.black)
        strokeWeight(2)
        featureEdges()
        if sphere { drawMesh(.sphere(radius: 0.6)) } else { drawMesh(.box(size: 1)) }
    }
}

/// A near unit box at the origin over a far one up and to the right, both
/// white on gray, ortho, 64 points a unit.
private final class TwoBoxesProbe: Sketch {
    var framePasses = false
    var oneByOne = false
    var nearFirst = false
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(Color(white: 0.5))
        ortho(eye: Vector3(0, 0, 10), height: 4)
        if framePasses { temporalAntialiasing(); motionBlur() }
        noLights()
        fill(.white)
        stroke(.black)
        strokeWeight(2)
        featureEdges()
        let far = Vector3(0.6, 0.6, -3), near = Vector3.zero
        if oneByOne {
            for position in nearFirst ? [near, far] : [far, near] {
                withState {
                    translate(position)
                    drawMesh(.box(size: 1))
                }
            }
        } else {
            drawMesh(.box(size: 1), instances: [MeshInstance(position: far), MeshInstance(position: near)])
        }
    }
}

/// Boxes scattered and turned, drawn as copies or one at a time.
private final class ScatteredBoxesProbe: Sketch {
    var instanced = true
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        perspective(eye: Vector3(0, 1, 6), target: .zero)
        noLights()
        fill(.white)
        stroke(.black)
        strokeWeight(1.5)
        featureEdges()
        let copies = (0..<12).map { k -> MeshInstance in
            let a = Double(k) * 0.52
            return MeshInstance(position: Vector3(Double(k % 4) * 1.4 - 2.1, Double(k / 4) * 1.4 - 1.4, 0),
                                rotation: Vector3(a, a * 0.7, a * 0.3), scale: 0.6)
        }
        if instanced {
            drawMesh(.box(size: 1), instances: copies)
        } else {
            for copy in copies {
                withState {
                    // The copy's own matrix as the model, so both routes place
                    // the box by the same floats.
                    drawer.translate(Vector3.zero)
                    drawer.modelMatrix = copy.matrix
                    drawMesh(.box(size: 1))
                }
            }
        }
    }
}

/// The top edge of a unit box seen face on, as a feature edge or as a 3D line.
private final class EdgeAgainstLineProbe: Sketch {
    var asLine = false
    var weight = 3.0
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        ortho(eye: Vector3(0, 0, 10), height: 4)
        noLights()
        fill(.white)
        stroke(.black)
        strokeWeight(weight)
        if asLine {
            drawLine(Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5))
        } else {
            featureEdges()
            drawMesh(.box(size: 1))
        }
    }
}

/// A slab a tenth as thick as it is wide, turned 0.5 radians about y and seen
/// face on from 3 units: the turned-toward side face shows its thickness on the
/// left; on the right the far edge of the back face hides behind the front face.
private final class SlabProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        perspective(eye: Vector3(0, 0, 3))
        noLights()
        fill(.white)
        stroke(.black)
        strokeWeight(1)
        featureEdges()
        rotateY(0.5)
        drawMesh(.box(width: 1, height: 1, depth: 0.1))
    }
}

/// A sphere seen a little from above, large on the canvas.
private final class SphereOutlineProbe: Sketch {
    override var canvasSize: CanvasSize { .square(512) }
    override func draw() {
        background(.white)
        perspective(eye: Vector3(0, 0, 3.2))
        noLights()
        fill(.white)
        stroke(.black)
        strokeWeight(2)
        featureEdges()
        rotateX(0.3)
        drawSphere(radius: 0.9)
    }
}
