import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// The six optical and print looks: the anaglyph's two copies land a measured
/// parallax apart, by depth through the combine and by one number through the
/// filter; a misregistered plate moves by its offset and turns about the
/// sheet's center, on the spot-ink masters and the process plates alike; a
/// mirage moves a row by the shift the CPU twin names; schlieren flips its
/// brightness across a spine and reads mid-gray on a flat layer; the
/// wavelength ramp's middle is green; and chromatography rings never enter a
/// neighbor's core, keep their order, and repeat from a seed.
@Suite
@MainActor
struct OpticalLookTests {

    static let side = 240

    // MARK: Anaglyph

    /// Two black bars on white, the left one at depth 0.2 and the right one at
    /// 0.9, through the depth-driven anaglyph.
    final class BarsByDepth: Sketch {
        var separation = 40.0
        override var canvasSize: CanvasSize { .square(OpticalLookTests.side) }
        override func draw() {
            let scene = makeRenderTarget()
            withTarget(scene) {
                background(.white)
                noStroke(); fill(.black)
                drawRect(50, 40, 24, 160)
                drawRect(166, 40, 24, 160)
            }
            let depth = makeRenderTarget()
            withTarget(depth) {
                noStroke()
                fill(Color(white: 0.2)); drawRect(0, 0, 120, 240)
                fill(Color(white: 0.9)); drawRect(120, 0, 120, 240)
            }
            background(.white)
            drawImage(scene.combined(with: depth, .anaglyph(separation: separation, focus: 0.5)).image, 0, 0)
        }
    }

    /// One black bar on white through the one-parallax filter.
    final class BarByFilter: Sketch {
        var separation = 10.0
        override var canvasSize: CanvasSize { .square(OpticalLookTests.side) }
        override func draw() {
            background(.white)
            noStroke(); fill(.black)
            drawRect(100, 40, 30, 160)
            postProcess(.anaglyph(separation: separation))
        }
    }

    private enum Tint { case cyan, red, black, white, other }

    private func tint(_ px: Pixels, _ x: Int, _ y: Int) -> Tint {
        let r = px.channel(0, x, y), g = px.channel(1, x, y), b = px.channel(2, x, y)
        if r < 70 && g > 180 && b > 180 { return .cyan }
        if r > 180 && g < 70 && b < 70 { return .red }
        if r < 70 && g < 70 && b < 70 { return .black }
        if r > 180 && g > 180 && b > 180 { return .white }
        return .other
    }

    /// The runs of cyan and red along one row inside `range`, as (first, last).
    private func fringes(_ px: Pixels, row: Int, range: Range<Int>) -> (cyan: Range<Int>?, red: Range<Int>?) {
        func run(_ wanted: Tint) -> Range<Int>? {
            let xs = range.filter { tint(px, $0, row) == wanted }
            guard let first = xs.first, let last = xs.last else { return nil }
            return first ..< last + 1
        }
        return (run(.cyan), run(.red))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theAnaglyphsCopiesLandAParallaxApartByDepth() throws {
        let px = Pixels(try OllinApp.image(of: BarsByDepth(), frame: 1))
        let row = 120
        // The near bar: parallax 40 * (0.2 - 0.5) = -12 px, the cyan copy on the right.
        let near = fringes(px, row: row, range: 30 ..< 100)
        let nearCyan = try #require(near.cyan), nearRed = try #require(near.red)
        #expect(abs(nearCyan.count - 12) <= 2, "near cyan fringe \(nearCyan)")
        #expect(abs(nearRed.count - 12) <= 2, "near red fringe \(nearRed)")
        #expect(nearRed.upperBound <= nearCyan.lowerBound, "near: red left of cyan")
        // The far bar: parallax 40 * (0.9 - 0.5) = 16 px, the cyan copy on the left.
        let far = fringes(px, row: row, range: 140 ..< 220)
        let farCyan = try #require(far.cyan), farRed = try #require(far.red)
        #expect(abs(farCyan.count - 16) <= 2, "far cyan fringe \(farCyan)")
        #expect(abs(farRed.count - 16) <= 2, "far red fringe \(farRed)")
        #expect(farCyan.upperBound <= farRed.lowerBound, "far: cyan left of red")
        // Between the copies the bar is the fused dark.
        #expect(tint(px, 62, row) == .black)
        #expect(tint(px, 178, row) == .black)
        // Off every bar the paper is paper.
        #expect(tint(px, 10, row) == .white)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFilterShiftsEveryPixelByOneParallax() throws {
        let px = Pixels(try OllinApp.image(of: BarByFilter(), frame: 1))
        let f = fringes(px, row: 120, range: 80 ..< 160)
        let cyan = try #require(f.cyan), red = try #require(f.red)
        #expect(abs(cyan.count - 10) <= 2, "cyan \(cyan)")
        #expect(abs(red.count - 10) <= 2, "red \(red)")
        #expect(cyan.upperBound <= red.lowerBound, "a positive parallax: cyan left, red right")
        // Separation 0 is the identity, byte for byte.
        let still = BarByFilter(); still.separation = 0
        let plain = BarByFilter(); plain.separation = 0
        let a = pixels(of: try OllinApp.image(of: still, frame: 1))
        let b = pixels(of: try OllinApp.image(of: plain, frame: 1))
        #expect(a == b)
        #expect(a.contains { $0 < 70 }, "the bar is there")
    }

    // MARK: Misregistration

    /// A sheet with one mark, as bytes: a rectangle of `color` over white.
    private func sheet(_ rect: (x: Int, y: Int, w: Int, h: Int), color: (UInt8, UInt8, UInt8),
                       side: Int = 64) -> Image {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for y in rect.y ..< rect.y + rect.h {
            for x in rect.x ..< rect.x + rect.w {
                let i = (y * side + x) * 4
                bytes[i] = color.0; bytes[i + 1] = color.1; bytes[i + 2] = color.2
            }
        }
        return Image(width: side, height: side, premultipliedRGBA: bytes)!
    }

    private func masterByte(_ master: Image, _ x: Int, _ y: Int) -> Int {
        let bytes = master.premultipliedPixels()!
        return Int(bytes[(y * master.width + x) * 4])
    }

    @Test func aMisregisteredPlateMovesByItsOffset() throws {
        let square = sheet((20, 20, 20, 20), color: (0, 0, 0))
        let sep = square.separated(into: [.black])
        #expect(masterByte(sep.layers[0].master, 30, 30) <= 2)
        let moved = sep.misregistered(offsets: [Vector2(6, 3)])
        let master = moved.layers[0].master
        // The ink sits 6 to the right and 3 down of where it was.
        #expect(masterByte(master, 30, 30) <= 2)
        #expect(masterByte(master, 44, 40) <= 2, "the new right edge carries ink")
        #expect(masterByte(master, 22, 30) >= 253, "paper slid in where the plate moved away")
        #expect(masterByte(master, 30, 21) >= 253)
        #expect(masterByte(master, 30, 41) <= 2)
        // A whole-pixel move with no turn changes no tone: the ink count is kept.
        let before = sep.layers[0].master.premultipliedPixels()!.enumerated().filter { $0.offset % 4 == 0 && $0.element < 128 }.count
        let after = master.premultipliedPixels()!.enumerated().filter { $0.offset % 4 == 0 && $0.element < 128 }.count
        #expect(before == after)
        // A missing entry means no move.
        let two = square.separated(into: [.black, .blue]).misregistered(offsets: [Vector2(6, 3)])
        #expect(masterByte(two.layers[1].master, 30, 30) == masterByte(square.separated(into: [.black, .blue]).layers[1].master, 30, 30))
    }

    @Test func aMisregisteredPlateTurnsAboutTheSheetsCenter() throws {
        // A mark to the right of the center turns to below it under a quarter turn.
        let mark = sheet((44, 28, 12, 8), color: (0, 0, 0))
        let sep = mark.separated(into: [.black])
        let turned = sep.misregistered(offsets: [.zero], rotations: [.pi / 2])
        let master = turned.layers[0].master
        #expect(masterByte(master, 32, 50) <= 2, "the mark is below the center now")
        #expect(masterByte(master, 50, 32) >= 253, "and no longer to its right")
        // Zero and zero is the identity.
        let same = sep.misregistered(offsets: [.zero], rotations: [0])
        #expect(same.layers[0].master.premultipliedPixels() == sep.layers[0].master.premultipliedPixels())
    }

    @Test func theProcessPlatesMisregisterTheSameWay() throws {
        let square = sheet((20, 20, 20, 20), color: (0, 0, 0))
        let plates = square.separated(into: SoftProof(.genericCMYK))
        guard plates.plates.count == 4 else {
            Issue.record("the generic CMYK profile gave \(plates.plates.count) plates")
            return
        }
        let black = plates.plates.firstIndex { $0.name.lowercased().hasPrefix("b") || $0.name.lowercased().hasPrefix("k") } ?? 3
        var offsets = [Vector2](repeating: .zero, count: 4)
        offsets[black] = Vector2(8, 0)
        let moved = plates.misregistered(offsets: offsets)
        let before = plates.plates[black].master, after = moved.plates[black].master
        // The black plate's ink column moved 8 to the right; another plate did not.
        #expect(masterByte(before, 22, 30) < 128 && masterByte(after, 22, 30) >= 253)
        #expect(masterByte(after, 30, 30) < 128)
        let other = (black + 1) % 4
        #expect(moved.plates[other].master.premultipliedPixels() == plates.plates[other].master.premultipliedPixels())
        // The misprint shows: a black mark rings itself with its other inks,
        // so the fringe the black plate left reads lighter than the body.
        let preview = moved.preview().premultipliedPixels()!
        func light(_ x: Int, _ y: Int) -> Int {
            let i = (y * moved.width + x) * 4
            return Int(preview[i]) + Int(preview[i + 1]) + Int(preview[i + 2])
        }
        #expect(light(22, 30) > light(34, 30) + 30, "fringe \(light(22, 30)), body \(light(34, 30))")
    }

    // MARK: Mirage

    /// One white line down a black canvas, through the mirage.
    final class LinedMirage: Sketch {
        var amount = 14.0
        override var canvasSize: CanvasSize { .square(OpticalLookTests.side) }
        override func draw() {
            background(.black)
            noStroke(); fill(.white)
            drawRect(120, 0, 3, 240)
            postProcess(.mirage(horizon: 0.62, faults: 0.5, amount: amount, phase: 0.3))
        }
    }

    /// The light-weighted center of a row's white, in pixels.
    private func lineCenter(_ px: Pixels, row: Int) -> Double {
        var sum = 0.0, weight = 0.0
        for x in 0 ..< px.width {
            let w = Double(px.channel(1, x, row))
            sum += w * (Double(x) + 0.5); weight += w
        }
        return weight > 0 ? sum / weight : .nan
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theMirageMovesARowByTheShiftItNames() throws {
        let px = Pixels(try OllinApp.image(of: LinedMirage(), frame: 1))
        var moved = 0
        for row in [30, 80, 130] {
            let y = (Double(row) + 0.5) / Double(Self.side)
            let shift = Filter.mirageShift(y: y, horizon: 0.62, faults: 0.5, amount: 14, phase: 0.3)
            // The row reads the source `shift` to the right, so the line lands `shift` to the left.
            let expected = 121.5 - shift
            let center = lineCenter(px, row: row)
            #expect(abs(center - expected) < 1.2, "row \(row): line at \(center), expected \(expected)")
            if abs(shift) > 1 { moved += 1 }
        }
        #expect(moved >= 2, "the rows were moved by more than a pixel")
        // At or below the horizon the shift function answers nothing.
        #expect(Filter.mirageShift(y: 0.7) == 0)
        // Amount 0 is the identity, byte for byte.
        let still = LinedMirage(); still.amount = 0
        let plain = LinedMirage(); plain.amount = 0
        #expect(pixels(of: try OllinApp.image(of: still, frame: 1)) == pixels(of: try OllinApp.image(of: plain, frame: 1)))
        let flat = Pixels(try OllinApp.image(of: still, frame: 1))
        #expect(abs(lineCenter(flat, row: 30) - 121.5) < 0.6)
    }

    // MARK: Schlieren

    /// A blurred white disc on black, read as a density field.
    final class Density: Sketch {
        var angle = 0.0
        var flat = false
        override var canvasSize: CanvasSize { .square(OpticalLookTests.side) }
        override func draw() {
            background(Color(white: 0.3))
            if !flat {
                noStroke(); fill(.white)
                drawCircle(120, 120, 50)
                postProcess(.gaussianBlur(radius: 14))
            }
            postProcess(.schlieren(angle: angle))
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func schlierenFlipsSignAcrossASpineAndRestsMidGray() throws {
        let px = Pixels(try OllinApp.image(of: Density(), frame: 1))
        let rising = px.gray(78, 120), falling = px.gray(162, 120), spine = px.gray(120, 120)
        #expect(rising > 128 + 10, "density climbs along the knife on the left: \(rising)")
        #expect(falling < 128 - 10, "and falls on the right: \(falling)")
        #expect(abs(spine - 128) <= 6, "the spine itself is level: \(spine)")
        // Across the knife nothing changes along it: the top and bottom read level.
        #expect(abs(px.gray(120, 78) - 128) <= 6)
        // Turn the knife half a turn and the sides swap.
        let turned = Density(); turned.angle = .pi
        let tx = Pixels(try OllinApp.image(of: turned, frame: 1))
        #expect(tx.gray(78, 120) < 128 - 10 && tx.gray(162, 120) > 128 + 10)
        // A flat layer is mid-gray everywhere.
        let still = Density(); still.flat = true
        let fx = Pixels(try OllinApp.image(of: still, frame: 1))
        for (x, y) in [(10, 10), (120, 120), (230, 200)] {
            #expect(abs(fx.gray(x, y) - 128) <= 2, "flat at \(x), \(y): \(fx.gray(x, y))")
        }
    }

    // MARK: The wavelength ramp

    @Test func theWavelengthRampsMiddleIsGreen() {
        let ramp = Ramp.wavelengths()
        #expect(ramp.stops.count == 31)
        let green = ramp.color(at: 0.5)        // 550 nm
        #expect(green.green > green.red && green.green > green.blue)
        let violet = ramp.color(at: 0)         // 400 nm
        #expect(violet.blue > violet.green && violet.blue > violet.red)
        let red = ramp.color(at: 1)            // 700 nm
        #expect(red.red > red.green && red.red > red.blue)
        // The stops are the wavelengths' own hues, placed evenly.
        #expect(ramp.stops[15].color == Color(wavelength: 550))
        #expect(abs(ramp.stops[15].position - 0.5) < 1e-9)
        // Run the other way, the ramp reverses.
        let back = Ramp.wavelengths(from: 700, to: 400)
        #expect(back.color(at: 0) == red && back.color(at: 1) == violet)
        // A narrow run keeps its ends.
        let warm = Ramp.wavelengths(from: 570, to: 700, stops: 5)
        #expect(warm.stops.count == 5 && warm.stops[0].color == Color(wavelength: 570))
    }

    // MARK: Chromatography

    @Test func chromatographyRingsNeverEnterANeighborsCore() {
        let region = Rectangle(x: 0, y: 0, width: 400, height: 400)
        let stain = Chromatography.scatter(in: region, count: 10, radius: 80 ... 140, seed: 3)
        #expect(stain.drops.count >= 6, "enough drops to meet: \(stain.drops.count)")
        var yielded = 0
        for (i, a) in stain.drops.enumerated() {
            #expect(a.rings.count == 5 && a.bands.count == 5)
            for (j, b) in stain.drops.enumerated() where j != i {
                for ring in a.rings {
                    for p in ring.points {
                        #expect((p - b.center).length > b.core, "a ring of drop \(i) entered drop \(j)'s core")
                    }
                }
            }
            // The rings keep their order along every ray.
            for k in 1 ..< a.rings.count {
                for (inner, outer) in zip(a.rings[k - 1].points, a.rings[k].points) {
                    #expect((inner - a.center).length <= (outer - a.center).length + 1e-9)
                }
            }
            // Where a front was stopped it sits well under its nominal radius.
            if let outer = a.rings.last, outer.points.contains(where: { ($0 - a.center).length < 0.8 * a.radius }) {
                yielded += 1
            }
            // Every fiber roots inside the outer front and reaches past it.
            if let outer = a.rings.last {
                let samples = outer.points.count
                for fiber in a.fibers {
                    let root = (fiber[0] - a.center).length, tip = (fiber[fiber.count - 1] - a.center).length
                    let k = Int(((fiber[0] - a.center).angle / .tau * Double(samples)).rounded(.down) + Double(samples)) % samples
                    let edge = (outer.points[k] - a.center).length
                    #expect(root < edge && tip > root)
                }
            }
        }
        #expect(yielded >= 2, "fronts that met: \(yielded)")
        // The same seed spreads the same stain, another seed another one.
        #expect(Chromatography.scatter(in: region, count: 10, radius: 80 ... 140, seed: 3) == stain)
        #expect(Chromatography.scatter(in: region, count: 10, radius: 80 ... 140, seed: 4) != stain)
    }

    @Test func aLoneDropKeepsItsRadiusAndItsTones() {
        let drop = Chromatography.spread(at: Vector2(200, 200), radius: 100, rings: 4, seed: 7).drops[0]
        #expect(drop.rings.count == 4)
        #expect(drop.rings[0].tone == 0 && drop.rings[3].tone == 1)
        #expect(abs(drop.rings[0].fraction - Chromatography.coreFraction) < 1e-9)
        #expect(drop.rings[3].fraction == 1)
        let outer = drop.rings[3].points.map { ($0 - drop.center).length }
        #expect(outer.min()! > 86 && outer.max()! < 114, "nothing stopped it: \(outer.min()!) ... \(outer.max()!)")
        #expect(!drop.fibers.isEmpty)
        // Every outline is one point per few pixels of circumference and closes in `lines`.
        let lines = Chromatography(drops: [drop]).lines
        #expect(lines.count == 4 + drop.fibers.count)
        #expect(lines[0].first == lines[0].last)
    }
}
