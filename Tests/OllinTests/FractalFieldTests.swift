@testable import Ollin
import Testing
import CoreGraphics

/// Laws for the fractal leaves (`mandelbulb`, `mengerSponge`, `mandelbox`), pinned on the
/// GPU through flat top-down renders, since the leaves have no CPU evaluator and a mean-diff
/// snapshot cannot tell a right sponge from a wrong one. Each law is a property of the set
/// itself: the sponge's silhouette down an axis is the Sierpinski carpet, so it covers
/// (8/9)^k of its square and sees through its center; the bulb turns its power's symmetry
/// about the y-axis; the box carries the octahedral symmetry of its folds; and `size` is an
/// exact uniform scale of each. A wrong fold phase, a dropped axis, or a bound that clips
/// the picture each breaks one of these while still drawing something plausible.
@Suite
@MainActor
struct FractalFieldTests {
    // A flat look straight down the y-axis: white ambient light only, so a pixel the leaf
    // covers is bright and one it misses is black. `height` frames 3 world units over 256 px.
    private final class FractalProbe: Sketch {
        var field: SDF3D = .sphere(radius: 1)
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(.black)
            ortho(eye: Vector3(0, 10, 0), target: .zero, up: Vector3(0, 0, -1), height: 3,
                  near: 0.1, far: 30)
            ambientLight(.white)
            drawSDF3D(field.colored(.white))
        }
    }

    private static let side = 256
    private static let pixelsPerUnit = Double(side) / 3.0

    private func mask(of field: SDF3D) throws -> [Bool] {
        let probe = FractalProbe()
        probe.field = field
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (0..<(w * h)).map { data[$0 * 4 + 1] > 128 }
    }

    private func coveredFraction(_ m: [Bool], insideSquareOfSide units: Double) -> Double {
        let half = units / 2 * Self.pixelsPerUnit
        let c = Double(Self.side) / 2
        // Two pixels in from the edge, so the outline's own anti-aliasing is not counted.
        let lo = Int((c - half).rounded(.up)) + 2, hi = Int((c + half).rounded(.down)) - 2
        var covered = 0, total = 0
        for y in lo..<hi { for x in lo..<hi { total += 1; if m[y * Self.side + x] { covered += 1 } } }
        return Double(covered) / Double(total)
    }

    /// Radius (px) of the last covered pixel along the ray at `angle` from the center.
    private func silhouetteRadius(_ m: [Bool], angle: Double) -> Double {
        let c = Double(Self.side) / 2 - 0.5
        var last = 0.0
        var r = 0.0
        while r < c {
            let x = Int((c + cos(angle) * r).rounded()), y = Int((c + sin(angle) * r).rounded())
            if x >= 0, y >= 0, x < Self.side, y < Self.side, m[y * Self.side + x] { last = r }
            r += 0.5
        }
        return last
    }

    private func differing(_ a: [Bool], _ b: [Bool]) -> Double {
        var diff = 0, covered = 0
        for i in a.indices { if a[i] != b[i] { diff += 1 }; if a[i] { covered += 1 } }
        return Double(diff) / Double(max(covered, 1))
    }

    // MARK: Menger sponge

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSpongeSilhouetteIsTheSierpinskiCarpet() throws {
        // Down any axis the level-k sponge shows the level-k carpet, which keeps (8/9)^k of
        // its square. Level 0 is the plain cube. The levels are ~0.1 apart, so a tolerance of
        // 0.03 tells them apart while forgiving the anti-aliased hole edges.
        for k in 0...3 {
            let m = try mask(of: .mengerSponge(iterations: k, size: 2))
            let expected = pow(8.0 / 9.0, Double(k))
            let got = coveredFraction(m, insideSquareOfSide: 2)
            #expect(abs(got - expected) < 0.03, "level \(k): covered \(got), carpet says \(expected)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSpongeSeesThroughItsCenterAndKeepsItsCorners() throws {
        let m = try mask(of: .mengerSponge(iterations: 2, size: 2))
        let c = Self.side / 2
        #expect(!m[c * Self.side + c], "the middle bar runs straight through")
        // A corner sub-cube survives every level: a pixel just inside the corner is covered.
        let inset = Int((1.0 - 0.05) * Self.pixelsPerUnit)
        #expect(m[(c - inset) * Self.side + (c - inset)])
        #expect(m[(c + inset) * Self.side + (c + inset)])
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aDeeperSpongeOnlyRemovesMaterial() throws {
        // Level k+1 is level k with more bored out, so its silhouette is a subset.
        let shallow = try mask(of: .mengerSponge(iterations: 2, size: 2))
        let deep = try mask(of: .mengerSponge(iterations: 3, size: 2))
        var gained = 0, covered = 0
        for i in deep.indices { if deep[i] { covered += 1; if !shallow[i] { gained += 1 } } }
        #expect(Double(gained) / Double(covered) < 0.003, "\(gained) pixels appeared at the deeper level")
    }

    // MARK: Mandelbulb

    @Test(.enabled(if: Snapshot.hasMetal))
    func theBulbTurnsItsPowersSymmetry() throws {
        // The power-n map carries an (n-1)-fold symmetry about y (as z^n + c does in the
        // plane), so the power-8 silhouette from above repeats every seventh of a turn. The
        // same test against a power-5 bulb (four-fold) must fail, or it is not reading the
        // power at all.
        let eight = try mask(of: .mandelbulb(power: 8, iterations: 8, radius: 1.2))
        let five = try mask(of: .mandelbulb(power: 5, iterations: 8, radius: 1.2))
        let step = 2 * Double.pi / 7
        var worstEight = 0.0, worstFive = 0.0
        for i in 0..<64 {
            let a = Double(i) / 64 * 2 * .pi
            worstEight = max(worstEight, abs(silhouetteRadius(eight, angle: a) - silhouetteRadius(eight, angle: a + step)))
            worstFive = max(worstFive, abs(silhouetteRadius(five, angle: a) - silhouetteRadius(five, angle: a + step)))
        }
        #expect(worstEight <= 2.0, "a seventh of a turn moved the silhouette by \(worstEight) px")
        #expect(worstFive > 4.0, "a power-5 bulb should not repeat every seventh of a turn")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theBulbStaysInsideItsRadius() throws {
        // `radius` maps the escape ball onto the leaf: the set reaches most of the way out
        // (its lobes sit near the ball's edge) and the drawn skin, fattened a little by the
        // finite iteration count, stays within a few percent of it. Its bounding box is
        // padded past that, so this also pins that the box never clips the rim.
        let m = try mask(of: .mandelbulb(power: 8, iterations: 8, radius: 1.2))
        var farthest = 0.0
        for i in 0..<128 { farthest = max(farthest, silhouetteRadius(m, angle: Double(i) / 128 * 2 * .pi)) }
        let bound = 1.2 * Self.pixelsPerUnit
        #expect(farthest <= bound * 1.1, "the bulb reached \(farthest) px past a \(bound) px radius")
        #expect(farthest >= bound * 0.8, "the bulb reached only \(farthest) px of \(bound)")
    }

    // MARK: Mandelbox

    @Test(.enabled(if: Snapshot.hasMetal))
    func theBoxCarriesTheOctahedralSymmetry() throws {
        // Every fold is even in each axis and blind to their order, so the picture from
        // above matches its x-mirror, its z-mirror, and its transpose.
        let m = try mask(of: .mandelbox(scale: -1.5, iterations: 12, size: 2.4))
        let n = Self.side
        var mirrorX = m, mirrorZ = m, transposed = m
        for y in 0..<n { for x in 0..<n {
            mirrorX[y * n + x] = m[y * n + (n - 1 - x)]
            mirrorZ[y * n + x] = m[(n - 1 - y) * n + x]
            transposed[y * n + x] = m[x * n + y]
        } }
        #expect(differing(m, mirrorX) < 0.015)
        #expect(differing(m, mirrorZ) < 0.015)
        #expect(differing(m, transposed) < 0.015)
        #expect(coveredFraction(m, insideSquareOfSide: 2.4) > 0.5, "the box should be mostly solid from above")
    }

    // MARK: Size

    @Test(.enabled(if: Snapshot.hasMetal))
    func sizeIsAnExactUniformScale() throws {
        // A leaf built at one size and a smaller one scaled up must draw the same picture,
        // which pins both the normalization inside each leaf and its bound.
        let pairs: [(SDF3D, SDF3D)] = [
            (.mengerSponge(iterations: 2, size: 2.5), .mengerSponge(iterations: 2, size: 2).scaled(1.25)),
            (.mandelbulb(power: 8, iterations: 6, radius: 1.25), .mandelbulb(power: 8, iterations: 6, radius: 1).scaled(1.25)),
            (.mandelbox(scale: -1.5, iterations: 10, size: 2.5), .mandelbox(scale: -1.5, iterations: 10, size: 2).scaled(1.25)),
        ]
        for (a, b) in pairs {
            #expect(differing(try mask(of: a), try mask(of: b)) < 0.01)
        }
    }
}
