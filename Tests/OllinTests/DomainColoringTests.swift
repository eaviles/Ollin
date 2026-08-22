@testable import Ollin
import Testing
import CoreGraphics

/// Render checks on the `domainColoring` generator. The load-bearing one is the
/// argument principle: walk a small circle counter-clockwise around a zero and
/// the palette must advance through one full turn; walk one around a pole and it
/// must run backward through one. That is what makes the picture a reading of
/// the function rather than a pretty field, so it is worth a test that a look
/// at the image could not replace.
///
/// The probes paint a three-stop palette of pure red, green, and blue, so a
/// sample's nearest stop is unambiguous, and they use `.phase` shading (no
/// brightness ruling) wherever a color is being read back.
@Suite
@MainActor
struct DomainColoringTests {

    /// Red, green, blue: far apart in every channel, so nearest-stop matching
    /// recovers the wheel position from a rendered pixel.
    static let wheel = [Color(hex: 0xFF0000), Color(hex: 0x00FF00), Color(hex: 0x0000FF)]

    // MARK: Reading pixels back

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func rgb(_ data: [UInt8], _ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// Which of the three stops a sample sits nearest, by squared distance.
    private func nearestStop(_ c: (Int, Int, Int)) -> Int {
        let stops = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]
        var best = 0, bestDistance = Int.max
        for (i, s) in stops.enumerated() {
            let d = (c.0 - s.0) * (c.0 - s.0) + (c.1 - s.1) * (c.1 - s.1) + (c.2 - s.2) * (c.2 - s.2)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    /// The net number of stops the wheel advances over one counter-clockwise lap
    /// of the plane around `plane`, sampled as a ring of pixels. Three stops to
    /// the wheel, so one full turn of the palette reads as +3, one turn the
    /// other way as -3.
    private func lap(_ image: CGImage, around plane: Vector2, radius: Double,
                     span: Double = 3, center: Vector2 = .zero) -> Int {
        let data = pixels(of: image)
        let size = Double(image.width)
        // Plane to pixel: the shader frames `span` units across the tile and
        // writes the imaginary axis upward, so the canvas y runs the other way.
        let toPixel: (Vector2) -> (Int, Int) = { p in
            (Int((0.5 + (p.x - center.x) / span) * size),
             Int((0.5 - (p.y - center.y) / span) * size))
        }
        let steps = 72
        var indices: [Int] = []
        for i in 0 ..< steps {
            let theta = Double(i) / Double(steps) * .tau      // counter-clockwise in the plane
            let sample = plane + Vector2(cos(theta), sin(theta)) * radius
            let (x, y) = toPixel(sample)
            indices.append(nearestStop(rgb(data, image, x, y)))
        }
        var net = 0
        for i in 0 ..< steps {
            let step = (indices[(i + 1) % steps] - indices[i] + 3) % 3
            net += step == 1 ? 1 : (step == 2 ? -1 : 0)
        }
        return net
    }

    // MARK: The argument principle

    @Test(.enabled(if: Snapshot.hasMetal))
    func theWheelTurnsOneWayAroundAZeroAndTheOtherAroundAPole() throws {
        let probe = DomainProbe.make(.domainColoring(
            .rational(zeros: [Vector2(-0.6, 0)], poles: [Vector2(0.6, 0)]),
            colors: Self.wheel, shading: .phase))
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        #expect(lap(image, around: Vector2(-0.6, 0), radius: 0.2) == 3,
                "a simple zero must show one full turn of the wheel, counter-clockwise")
        #expect(lap(image, around: Vector2(0.6, 0), radius: 0.2) == -3,
                "a simple pole must show the same turn the other way")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRepeatedZeroTurnsTheWheelTwice() throws {
        // Multiplicity is the count of turns, which is the rest of the theorem.
        let probe = DomainProbe.make(.domainColoring(
            .rational(zeros: [Vector2(-0.5, 0), Vector2(-0.5, 0)], poles: []),
            colors: Self.wheel, shading: .phase))
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        #expect(lap(image, around: Vector2(-0.5, 0), radius: 0.25) == 6,
                "a double zero must show two turns")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func thePowerFunctionWindsItsExponentTimes() throws {
        let probe = DomainProbe.make(.domainColoring(.power(3), colors: Self.wheel,
                                                     shading: .phase))
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        #expect(lap(image, around: .zero, radius: 0.7) == 9, "z cubed winds three times")
    }

    // MARK: The plane, and what the color says

    @Test(.enabled(if: Snapshot.hasMetal))
    func theImaginaryAxisRunsUpTheCanvas() throws {
        // f(z) = z, so the color directly reports the direction of the pixel's own
        // number. Right of the middle is +1 (the wheel's start, red). Above the
        // middle is +i, a quarter turn on, which lands three quarters of the way
        // from red to green. Miss the flip and it lands near red again.
        let probe = DomainProbe.make(.domainColoring(.power(1), colors: Self.wheel,
                                                     shading: .phase))
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        let data = pixels(of: image)
        let half = image.width / 2, quarter = image.width / 4
        let right = rgb(data, image, half + quarter, half)
        let above = rgb(data, image, half, half - quarter)
        #expect(right.0 > 200 && right.1 < 60, "expected the wheel to start at red: \(right)")
        #expect(above.1 > above.0, "expected +i a quarter turn on, past red: \(above)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPhasePortraitReadsDirectionOnly() throws {
        // Every point of one ray out of the origin has the same direction, so
        // f(z) = z must paint the whole ray one color, however far out it goes.
        let probe = DomainProbe.make(.domainColoring(.power(1), colors: Self.wheel,
                                                     shading: .phase))
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        let data = pixels(of: image)
        let half = image.width / 2
        let near = rgb(data, image, half + 20, half - 20)
        let far = rgb(data, image, half + 100, half - 100)
        let drift = abs(near.0 - far.0) + abs(near.1 - far.1) + abs(near.2 - far.2)
        #expect(drift < 12, "expected one color along the ray, drifted by \(drift)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func modulusShadingRulesTheSizeAndPhaseShadingDoesNot() throws {
        // The same ray, once plain and once with the modulus ruling on: the
        // ruling must make brightness rise and fall along it (the rings), while
        // the plain portrait holds one value. The swing is measured against the
        // ray's own color, not against white: the direction is fixed along a
        // ray, so the ruling can only darken the one color the wheel gives it,
        // by up to the 0.55 the shader's ramp bottoms out at.
        func brightnessSwing(_ shading: Generator.DomainShading) throws -> Double {
            let probe = DomainProbe.make(.domainColoring(.power(1), colors: Self.wheel,
                                                         shading: shading, strength: 1))
            let image = try #require(OllinApp.image(of: probe, frame: 1))
            let data = pixels(of: image)
            let half = image.width / 2
            var lowest = 255, highest = 0
            // From 12 pixels out, not from 1: a pixel center near the middle
            // sits at a visibly different angle from one far along the same
            // diagonal (the half-pixel offset is most of a near sample's
            // coordinate), and that turn is a real color change, not a defect.
            for step in 12 ... 100 {
                let c = rgb(data, image, half + step, half - step)
                let value = max(c.0, max(c.1, c.2))
                lowest = min(lowest, value); highest = max(highest, value)
            }
            return Double(highest - lowest) / Double(max(highest, 1))
        }
        let plain = try brightnessSwing(.phase)
        let ruled = try brightnessSwing(.modulus)
        #expect(plain < 0.05, "expected a flat ray without the ruling, swing \(plain)")
        #expect(ruled > 0.3, "expected rings along the ray, swing \(ruled)")
    }

    // MARK: What the typed surface carries

    @Test func onlyFourZerosAndPolesAreCarried() {
        let many = (0 ..< 6).map { Vector2(Double($0) * 0.2, 0) }
        let function = Generator.ComplexFunction.rational(zeros: many, poles: many)
        #expect(function.zeroPoints.count == 4)
        #expect(function.polePoints.count == 4)
        #expect(function.zeroPoints.first == many.first, "the first four are the ones kept")
    }

    @Test func onlyThePowerFunctionCarriesAnExponent() {
        #expect(Generator.ComplexFunction.power(2.5).exponent == 2.5)
        #expect(Generator.ComplexFunction.power(40).exponent == 8, "clamped to the shader's range")
        #expect(Generator.ComplexFunction.tangent.exponent == 1)
        #expect(Generator.ComplexFunction.tangent.zeroPoints.isEmpty)
    }
}

/// One generator filling the canvas at its native size, so a pixel maps onto the
/// plane by the shader's own framing and nothing resamples on the way out.
private final class DomainProbe: Sketch {
    var generator: Generator = .domainColoring()

    static func make(_ generator: Generator) -> DomainProbe {
        let probe = DomainProbe()
        probe.generator = generator
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        drawImage(generate(generator, width: 256, height: 256).image, 0, 0)
    }
}
