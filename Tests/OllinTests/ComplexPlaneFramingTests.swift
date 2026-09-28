@testable import Ollin
import Testing
import CoreGraphics

/// The framing every complex-plane generator shares, as `ComplexPlane` writes
/// it: `center` in the middle, `3 / zoom` units across the shorter side, the
/// imaginary axis up. The render tests put a feature at a known number in each
/// generator and read the pixel the plane says it is at; the mirrored mapping
/// (imaginary axis down, which is what three of the five generators drew until
/// 2026-09-27) is the sabotage each one is checked against.
@Suite
@MainActor
struct ComplexPlaneFramingTests {

    static let wheel = [Color(hex: 0xFF0000), Color(hex: 0x00FF00), Color(hex: 0x0000FF)]
    static let size = 256
    static let bounds = Rectangle(x: 0, y: 0, width: 256, height: 256)

    // MARK: The value

    @Test func aCanvasPointAndAPlanePointRoundTrip() {
        let plane = ComplexPlane(center: Vector2(-0.6, 0.2), zoom: 2.5)
        for rect in [Self.bounds, Rectangle(x: 40, y: 20, width: 268, height: 268),
                     Rectangle(x: 0, y: 0, width: 400, height: 200)] {
            for z in [Vector2(0, 0), Vector2(0.3, -0.7), Vector2(-1.1, 0.45)] {
                let back = plane.planePoint(at: plane.canvasPoint(of: z, in: rect), in: rect)
                #expect(abs(back.x - z.x) < 1e-12 && abs(back.y - z.y) < 1e-12)
            }
        }
    }

    @Test func theCenterSitsInTheMiddleAndTheImaginaryAxisRises() {
        let plane = ComplexPlane(center: Vector2(-0.6, 0.2), span: 3)
        let rect = Rectangle(x: 40, y: 20, width: 200, height: 200)
        let mid = plane.canvasPoint(of: Vector2(-0.6, 0.2), in: rect)
        #expect(mid == rect.center)
        let above = plane.canvasPoint(of: Vector2(-0.6, 1.2), in: rect)
        #expect(above.x == rect.center.x && above.y < rect.center.y, "a larger imaginary part is higher up")
        #expect(abs((rect.center.y - above.y) - 200 / 3) < 1e-9, "one unit is a third of the side")
    }

    @Test func theSpanRunsAcrossTheShorterSide() {
        let plane = ComplexPlane()
        let wide = Rectangle(x: 0, y: 0, width: 400, height: 200)
        let edge = plane.canvasPoint(of: Vector2(0, 1.5), in: wide)
        #expect(abs(edge.y) < 1e-9, "1.5i is the top edge of a 3-unit span")
        let right = plane.canvasPoint(of: Vector2(1.5, 0), in: wide)
        #expect(abs(right.x - 300) < 1e-9, "the long side shows more: 1.5 is a quarter in from its edge")
        let tall = Rectangle(x: 0, y: 0, width: 200, height: 400)
        #expect(abs(plane.canvasPoint(of: Vector2(1.5, 0), in: tall).x - 200) < 1e-9)
    }

    @Test func zoomAndSpanAreOneRule() {
        #expect(ComplexPlane(zoom: 1).span == 3)
        #expect(ComplexPlane(zoom: 2).span == 1.5)
        #expect(ComplexPlane(span: 0.5).zoom == 6)
        #expect(ComplexPlane().center == .zero && ComplexPlane().span == 3)
    }

    @Test func aGeneratorHandsOverItsOwnFraming() throws {
        let julia = Generator.julia(c: Vector2(-0.79, 0.15), center: Vector2(0.2, -0.1), zoom: 4)
        let plane = try #require(julia.plane)
        #expect(plane.center == Vector2(0.2, -0.1) && plane.zoom == 4)
        #expect(try #require(Generator.mandelbrot().plane).center == Vector2(-0.6, 0), "the default framing")
        #expect(try #require(Generator.orbitTrap(c: Vector2(0.3, 0.5)).plane).center == .zero,
                "a Julia trap frames the origin")
        #expect(try #require(Generator.domainColoring(zoom: 0.5).plane).span == 6)
        #expect(try #require(Generator.newton(zoom: 20_000).plane).zoom == 10_000, "after the factory's clamp")
        #expect(Generator.checkers().plane == nil)
        #expect(Generator.noise().plane == nil)
    }

    // MARK: Reading pixels

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func rgb(_ data: [UInt8], _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * Self.size + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// The nearest of red, green, blue, white.
    private func nearestStop(_ c: (Int, Int, Int)) -> Int {
        let stops = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)]
        var best = 0, bestDistance = Int.max
        for (i, s) in stops.enumerated() {
            let d = (c.0 - s.0) * (c.0 - s.0) + (c.1 - s.1) * (c.1 - s.1) + (c.2 - s.2) * (c.2 - s.2)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    private func render(_ generator: Generator) throws -> CGImage {
        try OllinApp.image(of: FramingProbe.make(generator), frame: 1)
    }

    /// The pixel a number lands on, through the generator's own plane, and the
    /// pixel it would land on with the imaginary axis mirrored.
    private func pixel(of z: Vector2, on generator: Generator, mirrored: Bool = false) throws -> (Int, Int) {
        let plane = try #require(generator.plane)
        let at = plane.canvasPoint(of: z, in: Self.bounds)
        let y = mirrored ? Double(Self.size) - at.y : at.y
        return (Int(at.x.rounded(.down)), Int(y.rounded(.down)))
    }

    // MARK: The generators

    @Test func aJuliaSetIsDrawnWhereThePlaneSays() throws {
        // c = 0 gives the unit disk, whose edge is analytic: a pixel and a
        // third inside the circle is the interior color, the same outside is
        // not, on both axes and both signs, which pins the scale and the
        // center to within a pixel.
        let unit = Generator.julia(c: .zero, colors: Self.wheel, interior: .white,
                                   center: .zero, zoom: 1, iterations: 150)
        let disk = pixels(of: try render(unit))
        for direction in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)] {
            let (ix, iy) = try pixel(of: direction * 0.985, on: unit)
            #expect(nearestStop(rgb(disk, ix, iy)) == 3, "inside the circle toward \(direction)")
            let (ox, oy) = try pixel(of: direction * 1.015, on: unit)
            #expect(nearestStop(rgb(disk, ox, oy)) != 3, "outside the circle toward \(direction)")
        }

        // A c off both axes gives a set with no mirror symmetry: the CPU
        // iteration under the plane's mapping agrees with the picture, and
        // the same iteration under the mirrored mapping agrees less.
        let c = Vector2(-0.4, 0.6)
        let julia = Generator.julia(c: c, colors: Self.wheel, interior: .white,
                                    center: .zero, zoom: 1, iterations: 150)
        let data = pixels(of: try render(julia))
        let plane = try #require(julia.plane)
        func inside(_ p: Vector2) -> Bool {
            var z = p
            for _ in 0 ..< 150 {
                z = Vector2(z.x * z.x - z.y * z.y, 2 * z.x * z.y) + c
                if z.x * z.x + z.y * z.y > 256 { return false }
            }
            return true
        }
        var agree = 0, mirrored = 0, total = 0
        for y in stride(from: 2, to: Self.size, by: 4) {
            for x in stride(from: 2, to: Self.size, by: 4) {
                let drawn = nearestStop(rgb(data, x, y)) == 3
                let center = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                let p = plane.planePoint(at: center, in: Self.bounds)
                if inside(p) == drawn { agree += 1 }
                if inside(Vector2(p.x, -p.y)) == drawn { mirrored += 1 }
                total += 1
            }
        }
        let share = Double(agree) / Double(total), mirroredShare = Double(mirrored) / Double(total)
        #expect(share > 0.97, "the CPU orbit agrees with the picture at \(share)")
        #expect(mirroredShare < share - 0.02, "the mirrored mapping agrees less, \(mirroredShare)")
    }

    @Test func aMandelbrotWindowOffTheRealAxisIsTheOneAsked() throws {
        // A window above the real axis, which the mirrored framing would fill
        // with the window below it.
        let center = Vector2(-0.75, 0.1)
        let mandelbrot = Generator.mandelbrot(colors: Self.wheel, interior: .white,
                                              center: center, zoom: 8, iterations: 150)
        let data = pixels(of: try render(mandelbrot))
        let plane = try #require(mandelbrot.plane)
        func inside(_ c: Vector2) -> Bool {
            var z = Vector2.zero
            for _ in 0 ..< 150 {
                z = Vector2(z.x * z.x - z.y * z.y, 2 * z.x * z.y) + c
                if z.x * z.x + z.y * z.y > 256 { return false }
            }
            return true
        }
        var agree = 0, mirrored = 0, total = 0
        for y in stride(from: 2, to: Self.size, by: 4) {
            for x in stride(from: 2, to: Self.size, by: 4) {
                let drawn = nearestStop(rgb(data, x, y)) == 3
                let at = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                let p = plane.planePoint(at: at, in: Self.bounds)
                if inside(p) == drawn { agree += 1 }
                let below = Vector2(p.x, 2 * center.y - p.y)
                if inside(below) == drawn { mirrored += 1 }
                total += 1
            }
        }
        let share = Double(agree) / Double(total), mirroredShare = Double(mirrored) / Double(total)
        #expect(share > 0.95, "the CPU orbit agrees with the picture at \(share)")
        #expect(mirroredShare < share - 0.05, "the window below agrees less, \(mirroredShare)")
    }

    @Test func anOrbitTrapKnotSitsWhereThePlaneSays() throws {
        // Mandelbrot mode: the first iterate is the pixel's own number, so the
        // pixel at the trap has distance zero and is the bluest in its
        // neighborhood, and the blueness falls off around it.
        let trap = Vector2(0.5, 0.7)
        let generator = Generator.orbitTrap(.point(trap), c: nil, colors: Self.wheel,
                                            center: .zero, zoom: 1, iterations: 150, glow: 0.06)
        let data = pixels(of: try render(generator))
        let (px, py) = try pixel(of: trap, on: generator)
        var bluest = (px, py), best = Int.min
        for oy in -7 ... 7 {
            for ox in -7 ... 7 {
                let c = rgb(data, px + ox, py + oy)
                let blueness = c.2 - c.0 - c.1
                if blueness > best { best = blueness; bluest = (px + ox, py + oy) }
            }
        }
        #expect(abs(bluest.0 - px) <= 1 && abs(bluest.1 - py) <= 1,
                "the knot is at \(bluest), the plane put the trap at \((px, py))")
        let (mx, my) = try pixel(of: trap, on: generator, mirrored: true)
        let mirror = rgb(data, mx, my)
        #expect(mirror.2 - mirror.0 - mirror.1 < best - 100, "nothing at the mirrored place")
    }

    @Test func aZeroWindsWhereThePlaneSays() throws {
        // The wheel goes round once counter-clockwise around a zero. Read the
        // eight pixels around the one the plane names: they wind once only if
        // the zero is inside that ring, within a pixel.
        let zero = Vector2(0.5, 0.7)
        let generator = Generator.domainColoring(.rational(zeros: [zero], poles: []),
                                                 colors: Self.wheel, shading: .phase,
                                                 center: .zero, zoom: 1)
        let data = pixels(of: try render(generator))
        func winding(around x: Int, _ y: Int) -> Int {
            // Counter-clockwise in the plane is counter-clockwise on the
            // canvas with y up: right, up-right, up, up-left, left, ...
            let ring = [(1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1)]
            let stops = ring.map { nearestStop(rgb(data, x + $0.0, y + $0.1)) }
            var net = 0
            for i in 0 ..< 8 {
                let step = (stops[(i + 1) % 8] - stops[i] + 3) % 3
                net += step == 1 ? 1 : (step == 2 ? -1 : 0)
            }
            return net
        }
        let (px, py) = try pixel(of: zero, on: generator)
        #expect(winding(around: px, py) == 3, "one turn of the wheel around the plane's pixel")
        let (mx, my) = try pixel(of: zero, on: generator, mirrored: true)
        #expect(winding(around: mx, my) == 0, "no zero at the mirrored place")
    }

    @Test func aRootIsPaintedWhereThePlaneSays() throws {
        // Root 0 wears the first stop, and with full shading the pixel that
        // holds the root is the brightest of its basin: it landed in no steps.
        let roots = [Vector2(1, 1), Vector2(-1, 0), Vector2(0, -1)]
        let generator = Generator.newton(roots: roots, colors: Self.wheel, shading: 1,
                                         center: .zero, zoom: 1)
        let data = pixels(of: try render(generator))
        let (px, py) = try pixel(of: roots[0], on: generator)
        #expect(nearestStop(rgb(data, px, py)) == 0, "the first root's basin is red")
        var brightest = (px, py), best = -1
        for oy in -5 ... 5 {
            for ox in -5 ... 5 {
                let c = rgb(data, px + ox, py + oy)
                if c.0 > best { best = c.0; brightest = (px + ox, py + oy) }
            }
        }
        #expect(abs(brightest.0 - px) <= 1 && abs(brightest.1 - py) <= 1,
                "the basin is brightest at \(brightest), the plane put the root at \((px, py))")
        let (mx, my) = try pixel(of: roots[0], on: generator, mirrored: true)
        #expect(nearestStop(rgb(data, mx, my)) != 0, "the mirrored place is another root's basin")
    }
}

/// One generator filling the canvas at its native size, so a pixel maps onto the
/// plane by the shader's own framing and nothing resamples on the way out.
private final class FramingProbe: Sketch {
    var generator: Generator = .mandelbrot()

    static func make(_ generator: Generator) -> FramingProbe {
        let probe = FramingProbe()
        probe.generator = generator
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        drawImage(generate(generator, width: 256, height: 256).image, 0, 0)
    }
}
