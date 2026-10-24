import CoreGraphics
import Foundation
import Testing
import COllinShaders
@testable import Ollin

/// A field rebuilt as blocks: the cell's center decides the block, so a unit
/// sphere cut at half a unit has exactly the silhouette its centers say, and a
/// larger one steps its outline on the block lattice; every face is square to
/// the grid, so under an oblique light the blocks take three tones where the
/// sphere they came from takes a gradient; the tone of a block is fixed by the
/// seed; and the program walks a nested scope as its outer one alone.
@Suite
@MainActor
struct VoxelBlocksTests {

    static let side = 240

    /// A field drawn flat (no lights) under an orthographic camera looking down
    /// -z, framing `frame` units top to bottom, or lit under an oblique camera.
    final class Blocks: Sketch {
        var field = SDF3D.sphere(radius: 1)
        var frame = 4.0
        var lit = false
        override var canvasSize: CanvasSize { .square(VoxelBlocksTests.side) }
        override func draw() {
            background(.black)
            if lit {
                camera(.perspective(eye: Vector3(3.2, 2.6, 4.4), fieldOfView: .pi / 4))
                directionalLight(.white, direction: Vector3(-0.35, -0.8, -0.5), intensity: 1)
                ambientLight(Color(white: 0.2))
                // Diffuse only, so a flat face is one tone and a curved one is not.
                material(.matte)
            } else {
                camera(.orthographic(eye: Vector3(0, 0, 10), height: frame))
            }
            fill(Color(red: 0.9, green: 0.6, blue: 0.3))
            drawSDF3D(field)
        }
    }

    private func render(_ field: SDF3D, frame: Double = 4, lit: Bool = false) throws -> Pixels {
        let s = Blocks(); s.field = field; s.frame = frame; s.lit = lit
        let image = try OllinApp.image(of: s, frame: 1)
        WipesAndCopiesTests.dump(image, "blocks")
        return Pixels(image)
    }

    private func isInk(_ p: Pixels, _ x: Int, _ y: Int) -> Bool { p.channel(0, x, y) > 110 }

    /// The covered span of row `y`, as the light summed along it over the
    /// light inside (so an antialiased edge counts by its coverage), in pixels.
    private func width(_ p: Pixels, row y: Int) -> Double {
        // The face's light is the median of the lit pixels, since the present
        // pass's dither spreads a flat face over two levels and the brightest
        // would read every other pixel as partly covered.
        let row = (0 ..< p.width).map { linear(UInt8(p.channel(0, $0, y))) }
        let lit = row.filter { $0 > (row.max() ?? 0) / 2 }.sorted()
        guard !lit.isEmpty, lit[lit.count / 2] > 0.05 else { return 0 }
        let inside = lit[lit.count / 2]
        return (0 ..< p.width).reduce(0.0) { $0 + linear(UInt8(p.channel(0, $1, y))) } / inside
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCellCenterDecidesTheBlock() throws {
        // Centers at +-0.25 and +-0.75 on each axis: (0.75, 0.25, 0.25) is inside a
        // unit sphere and (0.75, 0.75, 0.25) is not, so the rows within half a unit
        // of the middle are four blocks (two units) wide, the rows from there to a
        // unit two blocks wide, and nothing reaches past a unit.
        let p = try render(SDF3D.sphere(radius: 1).voxelized(size: 0.5, jitter: 0, seams: 0, occlusion: 0))
        let perUnit = Double(Self.side) / 4
        for y in 0 ..< Self.side {
            let v = abs((Double(y) + 0.5 - 120) / perUnit)
            let w = width(p, row: y)
            if v < 0.5 - 0.03 { #expect(abs(w - 2 * perUnit) < 1.5, "row \(y) is two units wide: \(w)") }
            else if v > 0.5 + 0.03 && v < 1 - 0.03 { #expect(abs(w - perUnit) < 1.5, "row \(y) is one unit wide: \(w)") }
            else if v > 1 + 0.03 { #expect(w < 0.5, "row \(y) is empty: \(w)") }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSphereStepsItsOutlineOnTheLattice() throws {
        // A block a quarter unit wide is 15 pixels, and the lattice is aligned to
        // the origin, which is the middle of the frame: every row's edges sit on
        // a multiple of 15 pixels from it, and the rows take several widths.
        let p = try render(SDF3D.sphere(radius: 1.45).voxelized(size: 0.25, jitter: 0, seams: 0, occlusion: 0))
        var widths = Set<Int>()
        for y in stride(from: 2, to: Self.side, by: 3) {
            let w = width(p, row: y)
            guard w > 1 else { continue }
            let blocks = w / 15
            #expect(abs(blocks - blocks.rounded()) < 0.1, "row \(y) is a whole number of blocks: \(blocks)")
            widths.insert(Int(blocks.rounded()))
        }
        #expect(widths.count >= 4, "a stepped circle, not a square: \(widths.sorted())")
    }

    /// The share of the object's pixels within three levels of its `n` most
    /// common colors.
    private func shareInTopColors(_ p: Pixels, _ n: Int) -> Double {
        var counts: [Int: Int] = [:]
        var object: [Int] = []
        for y in 0 ..< p.height {
            for x in 0 ..< p.width where p.channel(0, x, y) > 12 {
                let key = p.channel(0, x, y) << 16 | p.channel(1, x, y) << 8 | p.channel(2, x, y)
                counts[key, default: 0] += 1
                object.append(key)
            }
        }
        func near(_ a: Int, _ b: Int) -> Bool {
            abs((a >> 16) - (b >> 16)) <= 3 && abs((a >> 8 & 255) - (b >> 8 & 255)) <= 3 && abs((a & 255) - (b & 255)) <= 3
        }
        // The most common colors that are not a dither step from one already
        // taken: the dither spreads one tone over neighboring levels.
        var top: [Int] = []
        for (key, _) in counts.sorted(by: { $0.value > $1.value }) where top.count < n {
            if !top.contains(where: { near($0, key) }) { top.append(key) }
        }
        let within = object.filter { k in top.contains { near(k, $0) } }.count
        return Double(within) / Double(max(object.count, 1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyFaceIsSquareToTheGrid() throws {
        let sphere = SDF3D.sphere(radius: 1.2)
        let blocks = try render(sphere.voxelized(size: 0.3, jitter: 0, seams: 0, occlusion: 0), lit: true)
        let smooth = try render(sphere, lit: true)
        let stepped = shareInTopColors(blocks, 3), graded = shareInTopColors(smooth, 3)
        #expect(stepped > 0.9, "three faces, three tones: \(stepped)")
        #expect(graded < 0.5, "the sphere itself is a gradient: \(graded)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSeedFixesEachBlocksTone() throws {
        let field = SDF3D.sphere(radius: 1.2)
        let a = try render(field.voxelized(size: 0.3, jitter: 0.3, seed: 4), lit: true)
        let b = try render(field.voxelized(size: 0.3, jitter: 0.3, seed: 4), lit: true)
        let c = try render(field.voxelized(size: 0.3, jitter: 0.3, seed: 5), lit: true)
        let flat = try render(field.voxelized(size: 0.3, jitter: 0), lit: true)
        #expect(a.bytes == b.bytes, "one seed, one picture")
        #expect(a.bytes != c.bytes, "another seed, other tones")
        #expect(a.bytes != flat.bytes, "jitter moves the tones")
    }

    @Test func aNestedScopeTakesTheOuterBlocksOnly() {
        let inner = SDF3D.sphere(radius: 1).voxelized(size: 0.1)
        let outer = inner.union(SDF3D.box(size: 0.5).at(1, 0, 0)).voxelized(size: 0.3)
        var nodes: [SDFNode3D] = []
        _ = outer.flatten(defaultFill: .white, into: &nodes)
        #expect(nodes.filter { $0.kind == 5 }.count == 1 && nodes.filter { $0.kind == 6 }.count == 1)
        // END remembers how far back BEGIN is.
        let begin = nodes.firstIndex { $0.kind == 5 }!, end = nodes.firstIndex { $0.kind == 6 }!
        #expect(Int(nodes[end].extra) == end - begin)
        #expect(nodes[end].k == 0.3)
    }
}
