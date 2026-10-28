@testable import Ollin
import COllinShaders
import Testing
import CoreGraphics
import Foundation

/// A flat field stood up as a slab (`SDF.extruded(depth:)`), held to the 3D
/// solids it has to equal: an extruded circle is the cylinder and an extruded
/// rectangle the box, pixel for pixel; a flat transform lifted into the walk
/// draws what the 3D one draws; the flat program's melt stays in the plane; and
/// the slab voxelizes on the lattice.
@Suite(.serialized) @MainActor struct ExtrudedFieldTests {

    static let side = 240

    /// A field under a camera: lit and oblique, or flat under an orthographic
    /// camera looking down an axis, framing `frame` units top to bottom.
    final class Stage: Sketch {
        var field = SDF3D.sphere(radius: 1)
        var frame = 4.0
        var view: View = .lit
        enum View { case lit, front, side }
        override var canvasSize: CanvasSize { .square(ExtrudedFieldTests.side) }
        override func draw() {
            background(.black)
            switch view {
            case .lit:
                camera(.perspective(eye: Vector3(3.2, 2.6, 4.4), fieldOfView: .pi / 4))
                directionalLight(.white, direction: Vector3(-0.35, -0.8, -0.5), intensity: 1)
                ambientLight(Color(white: 0.2))
                material(.matte)
            case .front:
                camera(.orthographic(eye: Vector3(0, 0, 10), height: frame))
                noLights()   // flat ink, so a wall's shading never reads as its edge
            case .side:
                camera(.orthographic(eye: Vector3(10, 0, 0), target: .zero, up: Vector3(0, 1, 0), height: frame))
                noLights()
            }
            fill(Color(red: 0.9, green: 0.6, blue: 0.3))
            drawSDF3D(field)
        }
    }

    private func render(_ field: SDF3D, view: Stage.View = .lit, frame: Double = 4) throws -> Pixels {
        let s = Stage(); s.field = field; s.view = view; s.frame = frame
        let image = try OllinApp.image(of: s, frame: 1)
        WipesAndCopiesTests.dump(image, "extruded")
        return Pixels(image)
    }

    /// The widest absolute difference over every channel of two renders.
    private func maxDifference(_ a: Pixels, _ b: Pixels) -> Int {
        zip(a.bytes, b.bytes).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }

    private func isInk(_ p: Pixels, _ x: Int, _ y: Int) -> Bool { p.channel(0, x, y) > 110 }

    /// The rows of column `x` that carry ink, as a range, or nil for none.
    private func inkRows(_ p: Pixels, column x: Int) -> ClosedRange<Int>? {
        let rows = (0 ..< p.height).filter { isInk(p, x, $0) }
        guard let lo = rows.first, let hi = rows.last else { return nil }
        return lo ... hi
    }

    /// The columns of row `y` that carry ink, as a range, or nil for none. From the
    /// side the slab's depth runs across the picture, so this is what reads it.
    private func inkColumns(_ p: Pixels, row y: Int) -> ClosedRange<Int>? {
        let columns = (0 ..< p.width).filter { isInk(p, $0, y) }
        guard let lo = columns.first, let hi = columns.last else { return nil }
        return lo ... hi
    }

    // MARK: The solids it equals

    @Test(.enabled(if: Snapshot.hasMetal))
    func anExtrudedRectangleIsTheBox() throws {
        // The exact 2D box distance extruded is the 3D box's distance term for
        // term, so the march takes the same steps and the picture is the same.
        let slab = SDF.rect(width: 2.2, height: 1.3).extruded(depth: 0.9)
        let box = SDF3D.box(width: 2.2, height: 1.3, depth: 0.9)
        let a = try render(slab), b = try render(box)
        #expect(a.bytes == b.bytes)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anExtrudedCircleIsTheCylinder() throws {
        // The cylinder stands on y; the slab's depth runs along z, so turn one onto
        // the other. One transform scope each side, so the points differ by a
        // rotation's rounding and nothing else: within two levels at every pixel.
        let slab = SDF.circle(radius: 1).extruded(depth: 1.4).rotatedX(.pi / 2)
        let cylinder = SDF3D.cylinder(radius: 1, height: 1.4).rotatedX(.pi)
        let a = try render(slab), b = try render(cylinder)
        #expect(maxDifference(a, b) <= 2)
        let inkA = (0 ..< a.width).reduce(0) { $0 + (inkRows(a, column: $1)?.count ?? 0) }
        #expect(inkA > 2000)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSlabIsAsThickAsItsDepth() throws {
        // From the side, orthographic, four units top to bottom: a slab 1.2 deep
        // covers 1.2 / 4 of the height, within a pixel each edge.
        let slab = SDF.circle(radius: 1.2).extruded(depth: 1.2)
        let p = try render(slab, view: .side)
        let span = inkColumns(p, row: p.height / 2)
        let expected = Double(p.width) * 1.2 / 4
        #expect(span != nil)
        if let span {
            #expect(abs(Double(span.count) - expected) <= 2, "\(span.count) columns against \(expected)")
        }
        // And the disc's own height stands up: 2.4 of the 4 units.
        let tall = inkRows(p, column: p.width / 2)
        #expect(tall != nil)
        if let tall { #expect(abs(Double(tall.count) - Double(p.height) * 2.4 / 4) <= 2, "\(tall.count) rows") }
    }

    // MARK: The flat transforms, lifted

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatTranslationIsTheSpaceOne() throws {
        // The canvas's y runs down, so a flat shape moved down the canvas stands
        // lower: the slab stands as the canvas shows it.
        let flat = SDF.circle(radius: 0.6).at(0.8, 0.3).extruded(depth: 0.5)
        let space = SDF.circle(radius: 0.6).extruded(depth: 0.5).at(0.8, -0.3, 0)
        #expect(try render(flat).bytes == render(space).bytes)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatRotationTurnsAboutTheDepth() throws {
        // A turn on the canvas, where y runs down, is the opposite turn in a y-up world.
        let flat = SDF.rect(width: 1.6, height: 0.5).rotated(0.7).extruded(depth: 0.4)
        let space = SDF.rect(width: 1.6, height: 0.5).extruded(depth: 0.4).rotatedZ(-0.7)
        #expect(try render(flat).bytes == render(space).bytes)
        // And it is a turn, not a no-op: the unturned slab draws something else.
        let plain = SDF.rect(width: 1.6, height: 0.5).extruded(depth: 0.4)
        #expect(try render(flat).bytes != render(plain).bytes)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatPolarRepeatFoldsAboutTheDepth() throws {
        // The fold is the 3D one about z, instruction for instruction; the two
        // bound their march differently (the flat bound is a disc, the 3D one a
        // ball), so the hits agree within a level or two rather than to the byte.
        let leaf = SDF.rect(width: 0.5, height: 0.25).at(1, 0)
        let flat = leaf.repeatedRadially(count: 6).extruded(depth: 0.3)
        let space = leaf.extruded(depth: 0.3).repeatedRadially(count: 6, around: Vector3(0, 0, 1))
        let a = try render(flat, view: .front), b = try render(space, view: .front)
        // The march has no edge anti-aliasing, so a hit that moves by a hair flips
        // an edge pixel whole: count the pixels that differ, not how far.
        let far = zip(a.bytes, b.bytes).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > 32 ? 1 : 0) }
        #expect(Double(far) / Double(a.bytes.count) < 0.002, "\(far) bytes past 32 levels")
        // Six copies: the ink along a ring a unit out crosses six blobs.
        var blobs = 0
        let c = Double(a.width) / 2, r = Double(a.width) / 4
        var inside = isInk(a, Int(c + r), Int(c))   // the ring starts inside the first copy
        for k in 0 ..< 720 {
            let t = Double(k) / 720 * 2 * .pi
            let ink = isInk(a, Int(c + r * cos(t)), Int(c + r * sin(t)))
            if ink && !inside { blobs += 1 }
            inside = ink
        }
        #expect(blobs == 6, "\(blobs) blobs on the ring")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatMirrorAndTilingLeaveTheDepthAlone() throws {
        // A flat fold keeps the canvas's right and lower halves, which stand as the
        // slab's right and lower halves, so its 3D twin is not the walk's own fold
        // (that keeps the upper half) but the four copies placed by hand; the
        // tiling is the 3D one with no spacing along z. Different programs march
        // from different bounds, so count the pixels that differ, not how far.
        let flat = SDF.circle(radius: 0.3).at(0.5, 0.4).mirrored(x: true, y: true)
            .repeated(spacing: Vector2(1.6, 1.2), count: 1).extruded(depth: 0.3)
        let disc = SDF.circle(radius: 0.3).extruded(depth: 0.3)
        let four = disc.at(0.5, 0.4, 0).union(disc.at(-0.5, 0.4, 0)).union(disc.at(0.5, -0.4, 0)).union(disc.at(-0.5, -0.4, 0))
        let space = four.repeated(spacing: Vector3(1.6, 1.2, 0), count: 1)
        // Sixteen discs' worth of aliased edges: under a hundredth of the bytes
        // move, where a wrong fold or tiling moves whole discs.
        let a = try render(flat), b = try render(space)
        let far = zip(a.bytes, b.bytes).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > 32 ? 1 : 0) }
        #expect(Double(far) / Double(a.bytes.count) < 0.01, "\(far) bytes past 32 levels")
        let inked = (0 ..< a.width).reduce(0) { $0 + (inkRows(a, column: $1)?.count ?? 0) }
        #expect(inked > 500)
        // From the side the copies never stack along z: one band of ink, 0.3 deep.
        let p = try render(flat, view: .side)
        let span = inkColumns(p, row: p.height / 2 - Int(Double(p.height) * 0.4 / 4))
        #expect(span != nil)
        if let span { #expect(abs(Double(span.count) - Double(p.width) * 0.3 / 4) <= 2, "\(span.count) columns") }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatScaleKeepsTheDepth() throws {
        // A per-axis scale lifted with its third factor at one: the slab stays
        // 0.4 deep from the side, where a zero would stretch it past the frame.
        let slab = SDF.circle(radius: 0.5).scaled(x: 2, y: 1.5).extruded(depth: 0.4)
        let p = try render(slab, view: .side)
        let span = inkColumns(p, row: p.height / 2)
        #expect(span != nil)
        if let span { #expect(abs(Double(span.count) - Double(p.width) * 0.4 / 4) <= 2, "\(span.count) columns") }
        // And the scale took: 1.5 tall, so 0.75 of the 4 units each way.
        let tall = inkRows(p, column: p.width / 2)
        if let tall { #expect(abs(Double(tall.count) - Double(p.height) * 1.5 / 4) <= 2, "\(tall.count) rows") }
    }

    // MARK: The melt stays in the plane

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFlatMeltKeepsTheFacesFlat() throws {
        // Two circles melted flat, then stood up: the top face is one plane, so
        // from the side every column is the same depth. The same two circles
        // stood up first and melted in space bulge where they overlap.
        let a = SDF.circle(radius: 0.7).at(-0.45, 0), b = SDF.circle(radius: 0.7).at(0.45, 0)
        let flat = a.smoothUnion(b, k: 0.6).extruded(depth: 0.5)
        let space = a.extruded(depth: 0.5).smoothUnion(b.extruded(depth: 0.5), k: 0.6)
        let pf = try render(flat, view: .side), ps = try render(space, view: .side)
        func depths(_ p: Pixels) -> [Int] {
            (0 ..< p.width).compactMap { inkRows(p, column: $0)?.count }
        }
        let df = depths(pf), ds = depths(ps)
        #expect(!df.isEmpty && !ds.isEmpty)
        #expect((df.max() ?? 0) - (df.min() ?? 0) <= 2, "flat melt spans \(df.min() ?? 0)...\(df.max() ?? 0) rows")
        #expect((ds.max() ?? 0) - (ds.min() ?? 0) >= 4, "space melt spans \(ds.min() ?? 0)...\(ds.max() ?? 0) rows")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aColorRidesTheLeaf() throws {
        // A leaf's color crosses: the flat field's color is the slab's, and a
        // color set on the slab paints the leaves left unpainted.
        let red = SDF.circle(radius: 1).colored(.red).extruded(depth: 0.5)
        let blue = SDF.circle(radius: 1).extruded(depth: 0.5).colored(.blue)
        let pr = try render(red, view: .front), pb = try render(blue, view: .front)
        let c = pr.width / 2
        #expect(pr.channel(0, c, c) > 150 && pr.channel(2, c, c) < 60)
        #expect(pb.channel(2, c, c) > 150 && pb.channel(0, c, c) < 60)
    }

    // MARK: Blocks

    @Test(.enabled(if: Snapshot.hasMetal))
    func aVoxelizedSlabIsPixelArt() throws {
        // A disc one block thick, from the front: every row's ink is whole cells
        // wide (the cell is 0.25 of 4 units over the height), within a pixel and
        // a half each side. The slab sits half a block off the origin so it holds
        // a row of cell centers, the blocks' own rule.
        let slab = SDF.circle(radius: 1.4).extruded(depth: 0.25).at(0, 0, 0.125).voxelized(size: 0.25)
        let p = try render(slab, view: .front)
        let cell = Double(p.height) * 0.25 / 4
        var rows = 0
        for y in stride(from: 4, to: p.height - 4, by: 3) {
            let ink = (0 ..< p.width).filter { isInk(p, $0, y) }
            guard let lo = ink.first, let hi = ink.last, hi > lo else { continue }
            let width = Double(hi - lo + 1)
            let cells = (width / cell).rounded()
            #expect(abs(width - cells * cell) <= 3, "row \(y): \(width) px is not whole cells of \(cell)")
            rows += 1
        }
        #expect(rows > 20)
        // One block deep from the side.
        let side = try render(slab, view: .side)
        let span = inkColumns(side, row: side.height / 2)
        #expect(span != nil)
        if let span { #expect(abs(Double(span.count) - cell) <= 3, "\(span.count) columns deep") }
    }

    // MARK: The program

    @Test func theFlatProgramLiftsNodeForNode() {
        // The lifted program is the flat one's, instruction for instruction, plus
        // the extrusion: a leaf as EVAL2D with its geometry as the flat node packs
        // it, the combine shared, a rotation about z by the flat node's angle, and
        // the per-axis scale with z at one.
        let field = SDF.circle(radius: 1).colored(.red)
            .smoothUnion(SDF.rect(width: 2, height: 1).rotated(0.4).scaled(x: 2, y: 3), k: 0.2)
        var flat: [SDFNode] = []
        _ = field.flatten(defaultFill: .white, into: &flat)
        var nodes: [SDFNode3D] = []
        let bounds = field.extruded(depth: 0.8).flatten(defaultFill: .white, into: &nodes)
        // The half-turn scope round it all, the flat nodes, the extrusion, the restore.
        #expect(nodes.count == flat.count + 3)
        #expect(nodes.first?.kind == 3 && nodes.first?.sel == 1)
        let aboutX: SIMD4<Float> = SIMD4(1, 0, 0, 0)
        #expect(nodes.first?.geo0 == aboutX && abs((nodes.first?.geo1.x ?? 0) - .pi) < 1e-6)
        #expect(nodes[nodes.count - 2].kind == 8 && nodes[nodes.count - 2].k == 0.4)
        #expect(nodes.last?.kind == 4 && nodes.last?.k == 1)
        for (n, m) in zip(flat, nodes.dropFirst()) {
            switch n.kind {
            case 0:
                #expect(m.kind == 7)
                #expect(m.sel == n.sel && m.extra == n.extra)
                let sameGeometry: Bool = m.geo0 == n.geo0 && m.geo1 == n.geo1
                let sameColor: Bool = m.color == n.color
                #expect(sameGeometry && sameColor)
            case 3 where n.sel == 1:
                #expect(m.kind == 3 && m.sel == 1)
                let about: SIMD4<Float> = SIMD4(0, 0, 1, 0)
                #expect(m.geo0 == about)
                #expect(abs(m.geo1.x - 0.4) < 1e-6)
            case 3 where n.sel == 6:
                #expect(m.kind == 3 && m.sel == 6)
                let factors: SIMD4<Float> = SIMD4(2, 3, 1, 0)
                #expect(m.geo0 == factors)
            default:
                #expect(m.kind == n.kind && m.sel == n.sel)
                #expect(m.k == n.k)
            }
        }
        #expect(abs(bounds.lo.z + 0.4) < 1e-6 && abs(bounds.hi.z - 0.4) < 1e-6)
        #expect(bounds.valueDepth == 2 && bounds.pointDepth == 3)
        #expect(!bounds.unbounded)
    }

    @Test func theLiftedProgramStandsUpByAHalfTurn() {
        // The flat translate is carried as written; the half turn round the program
        // is what stands it up, and the bounds stand with it: a circle two down the
        // canvas is two below.
        var nodes: [SDFNode3D] = []
        let bounds = SDF.circle(radius: 0.5).at(1, 2).extruded(depth: 1).flatten(defaultFill: .white, into: &nodes)
        let shift: SIMD4<Float> = SIMD4(1, 2, 0, 0)
        #expect(nodes[1].kind == 3 && nodes[1].sel == 0)
        #expect(nodes[1].geo0 == shift)
        #expect(abs(bounds.lo.y + 2.5) < 1e-6 && abs(bounds.hi.y + 1.5) < 1e-6)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSlabStandsAsTheCanvasShowsIt() throws {
        // A triangle points up on the canvas; it points up in the scene too, and a
        // shape placed down the canvas stands below the origin. Read the front view:
        // the ink's rows run from the apex down.
        let tri = SDF.triangle(radius: 1.2).extruded(depth: 0.3)
        let p = try render(tri, view: .front)
        let c = p.width / 2
        let top = (0 ..< p.height).first { isInk(p, c, $0) }
        #expect(top != nil)
        // The row where the ink first appears is narrower than the last ink row: an
        // apex above, a base below, as drawSDF shows the triangle on the canvas.
        func inkWidth(_ y: Int) -> Int { (0 ..< p.width).filter { isInk(p, $0, y) }.count }
        if let top {
            let bottom = (0 ..< p.height).last { isInk(p, c, $0) } ?? top
            #expect(inkWidth(top + 4) < inkWidth(bottom - 4), "\(inkWidth(top + 4)) at the top, \(inkWidth(bottom - 4)) at the bottom")
        }
    }

    @Test func theDepthHasAFloorAndIsCentered() {
        var nodes: [SDFNode3D] = []
        let thin = SDF.square(1).extruded(depth: 0).flatten(defaultFill: .white, into: &nodes)
        #expect(abs(thin.hi.z - 0.0005) < 1e-6 && abs(thin.lo.z + 0.0005) < 1e-6)
        var more: [SDFNode3D] = []
        let painted = SDF.square(1).extruded(depth: 2).colored(.green).voxelized(size: 0.1)
            .flatten(defaultFill: .white, into: &more)
        #expect(abs(painted.lo.z + 1.1) < 1e-6 && abs(painted.hi.z - 1.1) < 1e-6)
        #expect(more.first?.kind == 5 && more.last?.kind == 6)
        #expect(more[2].kind == 7)
        let green: SIMD4<Float> = Color.green.simd4
        #expect(more[2].color == green)
    }
}
