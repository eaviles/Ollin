import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// The material textures on the GPU: a generator renders the same bytes twice
/// from one seed, and the same bytes over a scatter handed in as over the one
/// it builds for itself; a bloom's center reads its deepest tone and a point
/// off every bloom reads the background; a chip's center reads its tone and
/// the binder reads the background; bubble wrap at a lens radius of zero or an
/// amount of zero changes no byte, and a bubble's dome carries the highlight.
@Suite
@MainActor
struct MaterialTextureRenderTests {

    static let side = 240
    static let layer = Rectangle(x: 0, y: 0, width: Double(side), height: Double(side))

    /// A generator drawn over black.
    final class GeneratorProbe: Sketch {
        var generator: Generator = .checkers()
        static func make(_ generator: Generator) -> GeneratorProbe {
            let s = GeneratorProbe(); s.generator = generator; return s
        }
        override var canvasSize: CanvasSize { .square(MaterialTextureRenderTests.side) }
        override func draw() {
            background(.black)
            drawImage(generate(generator).image, 0, 0)
        }
    }

    /// A drawing of two discs over a pale ground, with a filter over all of it.
    final class FilterProbe: Sketch {
        var filter: Filter?
        static func make(_ filter: Filter?) -> FilterProbe {
            let s = FilterProbe(); s.filter = filter; return s
        }
        override var canvasSize: CanvasSize { .square(MaterialTextureRenderTests.side) }
        override func draw() {
            background(Color(hex: 0xEFEAE0))
            noStroke()
            fill(Color(hex: 0x2B6C8C)); drawCircle(80, 100, 50)
            fill(Color(hex: 0xE4572E)); drawCircle(160, 140, 44)
            if let filter { postProcess(filter) }
        }
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        guard pa.count == pb.count else { return 255 }
        return zip(pa, pb).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    private func rgb(_ px: Pixels, _ p: Vector2) -> SIMD3<Int> {
        let x = min(max(Int(p.x), 0), Self.side - 1), y = min(max(Int(p.y), 0), Self.side - 1)
        return SIMD3(px.channel(0, x, y), px.channel(1, x, y), px.channel(2, x, y))
    }

    private func bytes(_ c: Color) -> SIMD3<Int> {
        SIMD3(Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()))
    }

    private func within(_ a: SIMD3<Int>, _ b: SIMD3<Int>, _ tolerance: Int) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.z - b.z) <= tolerance
    }

    // MARK: Same seed, same bytes

    @Test(.enabled(if: Snapshot.hasMetal))
    func aGeneratorRendersTheSameBytesTwice() throws {
        for generator in [Generator.rust(seed: 5), .verdigris(seed: 5), .terrazzo(chipRadius: 24, seed: 5)] {
            let a = try OllinApp.image(of: GeneratorProbe.make(generator), frame: 1)
            let b = try OllinApp.image(of: GeneratorProbe.make(generator), frame: 1)
            #expect(maxDifference(a, b) == 0)
        }
        // And another seed is another picture.
        let a = try OllinApp.image(of: GeneratorProbe.make(.rust(seed: 5)), frame: 1)
        let c = try OllinApp.image(of: GeneratorProbe.make(.rust(seed: 6)), frame: 1)
        #expect(maxDifference(a, c) > 60)
    }

    /// The scatter a generator builds for itself is the one a sketch builds
    /// with the same arguments, byte for byte, so geometry stroked from it
    /// lands on the paint. The seed also seeds the grain, so it travels with
    /// the scatter.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aHandedInScatterPaintsTheSameAsTheBuiltOne() throws {
        let blooms = Patina.scatter(in: Self.layer, count: 14, radius: 40 ... 150, seed: 3)
        let built = try OllinApp.image(of: GeneratorProbe.make(.rust(seed: 3)), frame: 1)
        let handed = try OllinApp.image(of: GeneratorProbe.make(.rust(blobs: blooms, seed: 3)), frame: 1)
        #expect(maxDifference(built, handed) == 0)
        // Another seed with the same blooms differs by its grain alone: a few levels.
        let regrained = try OllinApp.image(of: GeneratorProbe.make(.rust(blobs: blooms, seed: 4)), frame: 1)
        let grainOnly = maxDifference(built, regrained)
        #expect(grainOnly > 0 && grainOnly < 40, "grain alone moved \(grainOnly) levels")

        let floor = Terrazzo.scatter(in: Self.layer, chipRadius: 24, density: 0.55, gap: 3, tones: 5, seed: 3)
        let builtFloor = try OllinApp.image(of: GeneratorProbe.make(.terrazzo(chipRadius: 24, seed: 3)), frame: 1)
        let handedFloor = try OllinApp.image(of: GeneratorProbe.make(.terrazzo(chips: floor, seed: 3)), frame: 1)
        #expect(maxDifference(builtFloor, handedFloor) == 0)
    }

    // MARK: Where the paint lands

    /// A bloom's center, inside its innermost mass, reads the third tone, and a
    /// point every bloom's reach misses reads the background.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBloomPaintsItsTonesWhereItsGeometrySays() throws {
        let blob = Patina.Blob(center: Vector2(120, 120), radius: 70,
                               amplitudes: SIMD4(0.1, 0.08, 0.04, 0.03), phases: SIMD4(0.3, 1.1, 2.0, 0.7),
                               massOffset: Vector2(0.1, 0.05), blisters: [], tone: 0.5)
        let tones = [Color(hex: 0xC2602E), Color(hex: 0x8F3F1C), Color(hex: 0x5E2612), Color(hex: 0x2A140A)]
        let generator = Generator.rust(blobs: Patina(blobs: [blob]), tones: tones,
                                       background: Color(hex: 0x4B5057), lip: 0, blisters: 0, grain: 0)
        let px = Pixels(try OllinApp.image(of: GeneratorProbe.make(generator), frame: 1))
        // The second mass is centered 1.7 offsets out: read there.
        let core = rgb(px, blob.massCenter(1))
        #expect(within(core, bytes(tones[2]), 6), "core \(core) against \(bytes(tones[2]))")
        // The outer bloom just inside its edge: the first tone, darkened a
        // little toward the core, so it sits between the first two tones.
        let edgeward = blob.center + Vector2(cos(0.3), sin(0.3)) * (blob.boundaryRadius(at: 0.3) - 12)
        let outer = rgb(px, edgeward)
        let t0 = bytes(tones[0]), t1 = bytes(tones[1])
        #expect(outer.x <= t0.x + 4 && outer.x >= t1.x - 4, "outer \(outer) off the first tone \(t0)")
        // A corner far from the bloom: the background.
        #expect(within(rgb(px, Vector2(6, 230)), bytes(Color(hex: 0x4B5057)), 3))
    }

    /// A chip's center reads its tone and the binder between chips reads the
    /// background; a hatched chip is darker along its lines than between them.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aChipPaintsItsToneWhereItsGeometrySays() throws {
        let tones = [Color(hex: 0xDCC9B2), Color(hex: 0x8F3A2E), Color(hex: 0x2E3A46)]
        let chips = [Terrazzo.Chip(center: Vector2(70, 70), radius: 40, rotation: 0.4, tier: 0, tone: 1,
                                   corners: [1, 0.9, 0.8, 0.95, 0.85, 1]),
                     Terrazzo.Chip(center: Vector2(170, 160), radius: 12, rotation: 1.2, tier: 2, tone: 2,
                                   corners: [1, 0.8, 0.9, 0.75, 1])]
        let floor = Terrazzo(chips: chips, gap: 3)
        let background = Color(hex: 0xB8AFA2)
        let flat = Pixels(try OllinApp.image(of: GeneratorProbe.make(
            .terrazzo(chips: floor, tones: tones, background: background, hatching: 0, grain: 0)), frame: 1))
        // The large chip's center is its tone, jittered by the chip's own hash
        // within a few levels; the small chip's center its own.
        let big = rgb(flat, chips[0].center), small = rgb(flat, chips[1].center)
        let expectedBig = bytes(tones[1]), expectedSmall = bytes(tones[2])
        #expect(abs(big.x - expectedBig.x) <= 14 && abs(big.z - expectedBig.z) <= 8, "big chip \(big) against \(expectedBig)")
        #expect(abs(small.z - expectedSmall.z) <= 10 && abs(small.x - expectedSmall.x) <= 8, "small chip \(small) against \(expectedSmall)")
        #expect(within(rgb(flat, Vector2(200, 40)), bytes(background), 2))
        // Hatched, the large chip has rows darker than their neighbors and the
        // small one, too small for lines, is the same as flat.
        let hatched = Pixels(try OllinApp.image(of: GeneratorProbe.make(
            .terrazzo(chips: floor, tones: tones, background: background, hatching: 1, grain: 0)), frame: 1))
        var darkest = 255, lightest = 0
        for i in -10 ... 10 {
            let p = chips[0].center + Vector2(cos(0.4 + .pi / 2), sin(0.4 + .pi / 2)) * Double(i)
            let v = rgb(hatched, p).x
            darkest = min(darkest, v); lightest = max(lightest, v)
        }
        #expect(lightest - darkest > 20, "no hatch across the large chip (\(darkest) to \(lightest))")
        #expect(rgb(hatched, chips[1].center) == small)
    }

    // MARK: Bubble wrap

    @Test(.enabled(if: Snapshot.hasMetal))
    func bubbleWrapAtNoRadiusOrNoAmountChangesNoByte() throws {
        let plain = try OllinApp.image(of: FilterProbe.make(nil), frame: 1)
        let flat = try OllinApp.image(of: FilterProbe.make(.bubbleWrap(radius: 0)), frame: 1)
        #expect(maxDifference(plain, flat) == 0)
        let held = try OllinApp.image(of: FilterProbe.make(.bubbleWrap(amount: 0)), frame: 1)
        #expect(maxDifference(plain, held) == 0)
        // The gate can fail: a sheet at full amount is another picture.
        let wrapped = try OllinApp.image(of: FilterProbe.make(.bubbleWrap()), frame: 1)
        #expect(maxDifference(plain, wrapped) > 60)
    }

    /// A bubble's dome carries the highlight on the side toward the light and
    /// the dark arc on the side away: read across the bubble centered on the
    /// lattice's origin, the lit side is brighter than the shaded side.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBubbleIsLitOnTheSideTowardTheLight() throws {
        let radius = 30.0, gap = 4.0
        let pitch = 2 * radius + gap
        // The lattice's point at (2 pitch, 0 rows) sits at x = 2 pitch, y = 0;
        // the next row down is offset half a pitch: a center well inside the
        // canvas at (2.5 pitch, sqrt(3)/2 pitch).
        let center = Vector2(2.5 * pitch, 0.86602540378 * pitch)
        let angle = 0.0   // the light from +x
        let filter = Filter.bubbleWrap(radius: radius, gap: gap, magnification: 1, lightAngle: angle, highlight: 1)
        let px = Pixels(try OllinApp.image(of: FilterProbe.make(filter), frame: 1))
        let lit = rgb(px, center + Vector2(0.38 * radius, 0))
        let shaded = rgb(px, center - Vector2(0.86 * radius, 0))
        let plain = Pixels(try OllinApp.image(of: FilterProbe.make(nil), frame: 1))
        let ground = rgb(plain, center)
        #expect(lit.x > ground.x + 8 || lit.x >= 250, "the highlight \(lit) over the ground \(ground)")
        #expect(shaded.x < ground.x - 30, "the dark arc \(shaded) under the ground \(ground)")
    }
}
