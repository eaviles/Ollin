import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the `.fallingSand` sim, run headless on a 64-texel field and
/// read back as one material per texel (four well-separated display levels, so the
/// decode is unambiguous under the present pass's dither).
///
/// The centerpiece is a cell-for-cell match against a plain CPU walk of the same
/// block rule: the GPU runs every 2x2 block in parallel from the same four reads,
/// and with the friction coin off (friction 0 always rolls) the rule is a pure
/// function of the field, so the two must agree after the same number of passes.
/// That match pins the tiling and its alternation, the straight falls, the sink
/// through water, the diagonal roll and its order after the falls, the water
/// spread, and the closed edge. Sabotage-verified: swapping the roll and spread
/// order in the shader, or letting a grain roll in a block where another fell,
/// turns the match red.
@Suite
@MainActor
struct FallingSandTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func aGrainFallsToTheFloorOneCellPerTwoPasses() throws {
        // One grain of sand at row 4. Eight passes a frame move it four cells a
        // frame (a cell is in a block's top row every other pass), so after three
        // drawn frames it is at row 16 (4 + 12) and after seventeen it rests on
        // the floor, still one grain.
        let falling = try materials(probe(.grain), frame: 2)
        #expect(cells(of: .sand, in: falling) == [Cell(32, 16)])
        let landed = try materials(probe(.grain), frame: 16)
        #expect(cells(of: .sand, in: landed) == [Cell(32, 63)])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func sandSinksThroughWaterAndMatchesTheReference() throws {
        // A 3x3 block of sand dropped into a basin of water eight rows deep. It
        // sinks, the water it displaces rises to the surface, and the heap slumps
        // on the floor. Every frame must match the CPU walk exactly, mid-fall and
        // settled alike.
        for frame in [2, 6, 12, 30] {
            let gpu = try materials(probe(.basin), frame: frame)
            #expect(gpu == stepped(seed(.basin), passes: passes(at: frame)), "frame \(frame)")
        }
        let settled = try materials(probe(.basin), frame: 30)
        let sand = cells(of: .sand, in: settled), water = cells(of: .water, in: settled)
        #expect(sand.count == 9)
        #expect(water.count == 64 * 8)
        // Nothing lighter sits under a grain: the pile is at rest.
        #expect(sand.allSatisfy { at($0.x, $0.y + 1, in: settled) >= 2 })
        // The nine cells of water the sand displaced now sit above the old surface.
        #expect(water.filter { $0.y < 56 }.count == 9)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func wallsHoldAndNeverMove() throws {
        // A wall shelf under a falling block: grains land on it and slump off its
        // ends to the floor, and the shelf itself is exactly where it was drawn.
        for frame in [4, 30] {
            let gpu = try materials(probe(.shelf), frame: frame)
            #expect(gpu == stepped(seed(.shelf), passes: passes(at: frame)), "frame \(frame)")
        }
        let settled = try materials(probe(.shelf), frame: 30)
        #expect(cells(of: .wall, in: settled) == cells(of: .wall, in: seed(.shelf)))
        let sand = cells(of: .sand, in: settled)
        #expect(sand.count == 9)
        #expect(sand.allSatisfy { at($0.x, $0.y + 1, in: settled) >= 2 })
        #expect(sand.contains { $0.y == 63 }, "some grains rolled off the shelf")
        #expect(sand.contains { $0.y == 39 }, "some grains rest on the shelf")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func fullFrictionStacksATower() throws {
        // With friction 1 no grain ever rolls, so the block lands as the same 3x3
        // block on the floor; with friction 0 its corners slump away. The contrast
        // is what proves the coin gates the roll.
        let tower = try materials(probe(.basinNoWater, friction: 1), frame: 20)
        let block = (61 ... 63).flatMap { y in (31 ... 33).map { x in Cell(x, y) } }
        #expect(cells(of: .sand, in: tower) == block)
        let heap = try materials(probe(.basinNoWater, friction: 0), frame: 20)
        #expect(cells(of: .sand, in: heap).count == 9)
        #expect(cells(of: .sand, in: heap) != block)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func sameRunReplaysExactly() throws {
        // The friction coin is a hash of the block, the pass, and the field's own
        // frame age: no wall clock, so a rerun is cell-identical.
        let a = try materials(probe(.shelf, friction: 0.5), frame: 20)
        let b = try materials(probe(.shelf, friction: 0.5), frame: 20)
        #expect(a == b)
        #expect(cells(of: .sand, in: a).count == 9)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func restFieldStaysEmpty() throws {
        let empty = try materials(probe(.nothing), frame: 10)
        #expect(empty.allSatisfy { $0.allSatisfy { $0 == 0 } })
    }

    // MARK: Probes and readback

    /// How many passes the field has run in the picture of `frame`: the headless
    /// drive draws frames 0 through `frame`, eight passes each, and the seed goes
    /// down on the first of them.
    private func passes(at frame: Int) -> Int { 8 * (frame + 1) }

    struct Cell: Equatable { let x: Int, y: Int; init(_ x: Int, _ y: Int) { self.x = x; self.y = y } }

    private func probe(_ scene: FallingSandProbeScene, friction: Double = 0) -> FallingSandProbeSketch {
        let sketch = FallingSandProbeSketch()
        sketch.scene = scene
        sketch.friction = friction
        return sketch
    }

    /// The rendered field decoded to a material per texel. The four levels sit at
    /// linear 0, 1/3, 2/3, 1, which the present pass encodes to sRGB bytes of about
    /// 0, 155, 213, 255.
    private func materials(_ sketch: Sketch, frame: Int) throws -> [[Int]] {
        let image = try #require(OllinApp.image(of: sketch, frame: frame))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0 ..< h).map { y in
            (0 ..< w).map { x in
                switch data[(y * w + x) * 4] {
                case ..<78: 0
                case ..<184: 1
                case ..<234: 2
                default: 3
                }
            }
        }
    }

    private func cells(of material: SandMaterial, in g: [[Int]]) -> [Cell] {
        g.indices.flatMap { y in g[y].indices.filter { g[y][$0] == material.rawValue }.map { Cell($0, y) } }
    }

    /// A cell read with the closed box: outside the field is wall.
    private func at(_ x: Int, _ y: Int, in g: [[Int]]) -> Int {
        (0 ..< 64).contains(x) && (0 ..< 64).contains(y) ? g[y][x] : 3
    }

    /// The field as drawn on the first frame, before any pass.
    private func seed(_ scene: FallingSandProbeScene) -> [[Int]] {
        var g = [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64)
        for mark in scene.marks {
            for y in mark.y0 ... mark.y1 { for x in mark.x0 ... mark.x1 { g[y][x] = mark.material.rawValue } }
        }
        return g
    }

    /// The CPU walk of the block rule, `passes` times, the tiling's origin
    /// walking the four corners of a block with the pass index (x flips every
    /// pass, y every second pass), friction 0.
    private func stepped(_ grid: [[Int]], passes: Int) -> [[Int]] {
        var g = grid
        func sinks(_ top: Int, _ below: Int) -> Bool { top < 3 && below < 3 && top > below }
        for pass in 0 ..< passes {
            let ox = pass % 2, oy = (pass / 2) % 2
            let columns = stride(from: ox == 0 ? 0 : -1, to: 64, by: 2)
            let rows = stride(from: oy == 0 ? 0 : -1, to: 64, by: 2)
            var next = g
            for by in rows {
                for bx in columns {
                    var a = at(bx, by, in: g), b = at(bx + 1, by, in: g)
                    var c = at(bx, by + 1, in: g), d = at(bx + 1, by + 1, in: g)
                    let fellLeft = sinks(a, c), fellRight = sinks(b, d)
                    if fellLeft { swap(&a, &c) }
                    if fellRight { swap(&b, &d) }
                    if !fellLeft && !fellRight {
                        if sinks(a, d) { swap(&a, &d) } else if sinks(b, c) { swap(&b, &c) }
                    }
                    if (a == 1 && b == 0) || (a == 0 && b == 1) { swap(&a, &b) }
                    if (c == 1 && d == 0) || (c == 0 && d == 1) { swap(&c, &d) }
                    for (x, y, m) in [(bx, by, a), (bx + 1, by, b), (bx, by + 1, c), (bx + 1, by + 1, d)]
                        where (0 ..< 64).contains(x) && (0 ..< 64).contains(y) {
                        next[y][x] = m
                    }
                }
            }
            g = next
        }
        return g
    }
}

/// A 64-texel falling-sand field seeded on its first frame with one of a few scenes.
/// Each mark is a rectangle of texels laid down with the material's own gray; the
/// rect is inset a quarter texel inside the covered texels, so their centers read
/// full coverage while the excluded neighbors sit three quarters of a texel into
/// the anti-aliased halo, under the inject's alpha gate.
struct FallingSandProbeMark { let material: SandMaterial; let x0: Int, y0: Int, x1: Int, y1: Int }

enum FallingSandProbeScene {
    case nothing, grain, basin, basinNoWater, shelf

    var marks: [FallingSandProbeMark] {
        let block = FallingSandProbeMark(material: .sand, x0: 31, y0: 10, x1: 33, y1: 12)
        switch self {
        case .nothing: return []
        case .grain: return [FallingSandProbeMark(material: .sand, x0: 32, y0: 4, x1: 32, y1: 4)]
        case .basin: return [FallingSandProbeMark(material: .water, x0: 0, y0: 56, x1: 63, y1: 63), block]
        case .basinNoWater: return [block]
        case .shelf: return [FallingSandProbeMark(material: .wall, x0: 30, y0: 40, x1: 34, y1: 40), block]
        }
    }
}

@MainActor
private final class FallingSandProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }

    var scene = FallingSandProbeScene.nothing
    var friction = 0.0

    private var field: SimField!

    override func setup() {
        field = makeSimField(.fallingSand(passes: 8, friction: friction), scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {
            if frameCount == 1 {
                noStroke()
                for mark in scene.marks {
                    fill(mark.material.color)
                    drawRect(Double(mark.x0) + 0.25, Double(mark.y0) + 0.25,
                             Double(mark.x1 - mark.x0) + 0.5, Double(mark.y1 - mark.y0) + 0.5)
                }
            }
        }
        drawImage(field.image, 0, 0)
    }
}
