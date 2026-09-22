import CoreGraphics
import Foundation
import Metal
import Ollin
import Testing

/// Pure CPU invariants on `Complex`: the literal and standard-library conformances,
/// the arithmetic identities, and the transcendental functions against the
/// closed forms. No Metal, so these run everywhere including CI.
@Suite
struct ComplexTests {

    private func close(_ a: Complex, _ b: Complex, _ eps: Double = 1e-9) -> Bool {
        abs(a.real - b.real) <= eps && abs(a.imaginary - b.imaginary) <= eps
    }

    @Test func aLiteralIsARealNumber() {
        let three: Complex = 3
        #expect(three == Complex(3, 0))
        let half: Complex = 0.5
        #expect(half.real == 0.5 && half.imaginary == 0)
        #expect(Complex.i * Complex.i == -1)
        #expect(Complex(2) == Complex(2, 0))
        #expect(Complex(exactly: 7) == Complex(7))
    }

    @Test func aPlainDoubleExpressionStaysCheap() {
        // The regression the design guards: with the transcendentals as free
        // functions, this easing curve took seconds to type-check and one in
        // the framework failed outright. It has to compile as plain doubles.
        func elastic(_ t: Double) -> Double {
            let c5 = (2 * Double.pi) / 4.5
            return t < 0.5
                ? -(pow(2, 20 * t - 10) * sin((20 * t - 11.125) * c5)) / 2
                : (pow(2, -20 * t + 10) * sin((20 * t - 11.125) * c5)) / 2 + 1
        }
        let brightness = pow(max(0, 0.5), 1 / 2.2) * 255 + 0.5
        #expect(abs(elastic(1) - 1) < 0.01 && elastic(0.25).isFinite && brightness > 180)
    }

    @Test func theStandardLibraryTakesIt() {
        let orbit = [Complex(1, 1), Complex(0, 2), Complex(-1, 0.5)]
        #expect(orbit.reduce(0, +) == Complex(0, 3.5))
        #expect(close(orbit.reduce(1, *), Complex(1, 1) * Complex(0, 2) * Complex(-1, 0.5)))
        var running = Complex.zero
        for z in orbit { running += z }
        #expect(running == Complex(0, 3.5))
        // A sum over doubles still reads as doubles: the mixed operators are
        // disfavored, so `0` stays the integer literal it was.
        let lengths = [1.0, 2.0, 3.5]
        let period = lengths.reduce(0, +)
        #expect(period == 6.5)
        let critical = 2 / log(1 + 2.0.squareRoot())
        #expect(critical > 2.26 && critical < 2.27)
    }

    @Test func aRealMixesOnEitherSide() {
        let z = Complex(1, 2)
        let s = 2.5
        #expect(z * s == Complex(2.5, 5))
        #expect(s * z == Complex(2.5, 5))
        #expect(z * 2 == Complex(2, 4))
        #expect(z + 1 == Complex(2, 2))
        #expect(1 - z == Complex(0, -2))
        #expect(z - 1 == Complex(0, 2))
        #expect(z / 2 == Complex(0.5, 1))
        #expect(close(1 / z, z.reciprocal))
    }

    @Test func multiplyingAddsTheAngles() {
        let a = 0.7, b = 1.9
        #expect(close(Complex.unit(a) * Complex.unit(b), .unit(a + b)))
        #expect(close(Complex.pow(.unit(a), 5), .unit(5 * a)))
        #expect(close(Complex.pow(.unit(a), 5.0), .unit(5 * a)))
        let z = Complex(magnitude: 2, argument: 0.4)
        #expect(close(z.rotated(by: 1), Complex(magnitude: 2, argument: 1.4)))
        #expect(abs(z.magnitude - 2) < 1e-12)
        #expect(abs(z.argument - 0.4) < 1e-12)
        #expect(abs(z.magnitudeSquared - 4) < 1e-12)
    }

    @Test func divisionUndoesMultiplication() {
        let a = Complex(3, -1), b = Complex(-0.5, 2)
        #expect(close(a * b / b, a))
        #expect(close(b * b.reciprocal, .one))
        #expect(close(a.conjugate * a, Complex(a.magnitudeSquared)))
        var c = a
        c *= b
        c /= b
        #expect(close(c, a))
        #expect(-a == Complex(-3, 1))
    }

    @Test func expAndLogUndoEachOther() {
        for z in [Complex(0.3, 0.5), Complex(-1.2, 2.0), Complex(2, -3), Complex(0, 1)] {
            #expect(close(Complex.log(Complex.exp(z)), z))
            #expect(close(Complex.exp(Complex.log(z)), z))
        }
        #expect(close(Complex.exp(Complex(0, .pi)), -1, 1e-12))
        #expect(close(Complex.log(Complex(-1)), Complex(0, .pi)))
        #expect(close(Complex.exp(Complex(1)), Complex(exp(1.0))))
    }

    @Test func rootsAndPowers() {
        #expect(close(Complex.sqrt(Complex(-4)), Complex(0, 2)))
        let z = Complex(1.5, -2.2)
        #expect(close(Complex.sqrt(z) * Complex.sqrt(z), z))
        #expect(close(z.squareRoot(), Complex.sqrt(z)))
        #expect(close(Complex.pow(z, 3), z * z * z))
        #expect(close(Complex.pow(z, -2), (z * z).reciprocal))
        #expect(close(Complex.pow(z, 0.5), Complex.sqrt(z)))
        #expect(close(Complex.pow(z, 3.0), z * z * z, 1e-9))
        #expect(close(Complex.pow(z, Complex(2)), z * z, 1e-9))
        #expect(Complex.pow(.zero, 3) == .zero)
        #expect(Complex.pow(.zero, 0) == .one)
        #expect(Complex.pow(.zero, 2.0) == .zero)
        #expect(Complex.pow(.zero, Complex.zero) == .one)
        #expect(close(Complex.pow(.i, .i), Complex(exp(-Double.pi / 2))))
    }

    @Test func trigonometryHoldsItsIdentities() {
        let z = Complex(0.8, -0.6)
        #expect(close(Complex.sin(z) * Complex.sin(z) + Complex.cos(z) * Complex.cos(z), .one))
        #expect(close(Complex.tan(z), Complex.sin(z) / Complex.cos(z)))
        #expect(close(Complex.cosh(z) * Complex.cosh(z) - Complex.sinh(z) * Complex.sinh(z), .one))
        #expect(close(Complex.tanh(z), Complex.sinh(z) / Complex.cosh(z)))
        #expect(close(Complex.sin(.i * z), .i * Complex.sinh(z)))
        #expect(close(Complex.sin(Complex(0.8)), Complex(sin(0.8))))
        #expect(close(Complex.cos(Complex(0.8)), Complex(cos(0.8))))
    }

    @Test func itReadsAsWritten() {
        #expect(Complex(1, 2).description == "1 + 2i")
        #expect(Complex(1, -2).description == "1 - 2i")
        #expect(Complex(0, 2).description == "2i")
        #expect(Complex(0, -1).description == "-i")
        #expect(Complex(3).description == "3")
        #expect(Complex(0.5, 1).description == "0.5 + i")
        #expect(Complex.zero.description == "0")
    }

    @Test func itBridgesToVector2() {
        let v = Vector2(3, 4)
        let z = Complex(v)
        #expect(z == Complex(3, 4))
        #expect(Vector2(z) == v)
        #expect(z.vector == v)
        #expect(abs(z.magnitude - v.length) < 1e-12)
        #expect(close(z.rotated(by: 0.3), Complex(v.rotated(by: 0.3)), 1e-12))
    }

    @Test func finiteAndCodable() throws {
        #expect(Complex(1, 2).isFinite)
        #expect(!Complex(.infinity, 0).isFinite)
        let data = try JSONEncoder().encode(Complex(1.5, -2))
        #expect(try JSONDecoder().decode(Complex.self, from: data) == Complex(1.5, -2))
    }
}

/// Whether this machine has a GPU to draw with. It sits outside the suite
/// because a test trait is read before the suite's actor is entered.
private let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// The shader library's `complex` module against the CPU value: a probe paints
/// each helper's answer over a grid of the plane, encoded into the red and
/// green bytes, and the same grid is worked out here with `Complex`. The
/// encoding holds sixteen units in a byte, so a level is a sixteenth; a wrong
/// sign, a swapped part, or a missing clamp is an error of order one.
@MainActor
struct ComplexShaderTests {

    /// One helper painted over the plane, `span` units across, encoded as
    /// `unipolar(f / 8)` in red and green.
    final class Probe: Sketch {
        var expression = "z"
        override var canvasSize: CanvasSize { .square(32) }
        override func draw() {
            let shader = Shader("""
            float4 shade(float2 uv, ShaderInfo info) {
                float2 z = complexPlane(uv, info.resolution, float2(0.0), 4.0);
                float2 f = \(expression);
                return float4(unipolar(f.x / 8.0), unipolar(f.y / 8.0), 0.0, 1.0);
            }
            """, using: [.complex])
            drawImage(generate(shader).image, 0, 0)
        }
    }

    /// The plane the probe frames, worked out on the CPU: aspect 1, so
    /// `span` units across both ways, the imaginary axis up.
    private func point(col: Int, row: Int, size: Int) -> Complex {
        let u = (Double(col) + 0.5) / Double(size) - 0.5
        let v = (Double(row) + 0.5) / Double(size) - 0.5
        return Complex(u * 4, -v * 4)
    }

    private func bytes(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                                    bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    private func encoded(_ value: Double) -> Int {
        Int((min(max(value / 8 * 0.5 + 0.5, 0), 1) * 255).rounded())
    }

    /// Renders the probe for `expression` and counts the pixels whose bytes
    /// disagree with `function` by more than three levels, skipping the
    /// pixels the encoding cannot hold (past eight units, or not finite).
    private func disagreements(_ expression: String,
                               _ function: (Complex) -> Complex) throws -> [String] {
        let probe = Probe()
        probe.expression = expression
        let image = try #require(OllinApp.image(of: probe))
        let size = image.width
        #expect(size == 32)
        let data = bytes(of: image)
        var bad: [String] = []
        for row in 0 ..< size {
            for col in 0 ..< size {
                let f = function(point(col: col, row: row, size: size))
                guard f.isFinite, abs(f.real) < 7.5, abs(f.imaginary) < 7.5 else { continue }
                let at = (row * size + col) * 4
                let dr = abs(Int(data[at]) - encoded(f.real))
                let dg = abs(Int(data[at + 1]) - encoded(f.imaginary))
                if dr > 3 || dg > 3 {
                    bad.append("(\(col), \(row)): shader \(data[at]),\(data[at + 1]) against \(encoded(f.real)),\(encoded(f.imaginary)) for \(f)")
                }
            }
        }
        return bad
    }

    @Test(.enabled(if: hasMetal))
    func theHelpersAgreeWithTheValue() throws {
        let cases: [(String, (Complex) -> Complex)] = [
            ("z", { $0 }),
            ("cmul(z, z)", { $0 * $0 }),
            ("cdiv(z, z - float2(0.5, 0.25))", { $0 / ($0 - Complex(0.5, 0.25)) }),
            ("cinv(z)", { $0.reciprocal }),
            ("conj(z)", { $0.conjugate }),
            ("cpolar(cabs(z), carg(z))", { $0 }),
            ("cexp(z)", { Complex.exp($0) }),
            ("clog(z)", { Complex.log($0) }),
            ("cpow(z, 2.5)", { Complex.pow($0, 2.5) }),
            ("cpow(z, float2(0.0, 1.0))", { Complex.pow($0, .i) }),
            ("csqrt(z)", { Complex.sqrt($0) }),
            ("csin(z)", { Complex.sin($0) }),
            ("ccos(z)", { Complex.cos($0) }),
            ("ctan(z)", { Complex.tan($0) }),
            ("csinh(z)", { Complex.sinh($0) }),
            ("ccosh(z)", { Complex.cosh($0) }),
            ("ctanh(z)", { Complex.tanh($0) }),
        ]
        for (expression, function) in cases {
            let bad = try disagreements(expression, function)
            #expect(bad.isEmpty, "\(expression): \(bad.count) pixels disagree, first \(bad.first ?? "")")
        }
    }

    @Test(.enabled(if: hasMetal))
    func theProbeWouldSeeAWrongFormula() throws {
        // A formula with the parts swapped disagrees nearly everywhere, so the
        // agreement above is not the encoding hiding everything.
        let bad = try disagreements("cmul(z, z)") { Complex($0.imaginary, $0.real) * $0 }
        #expect(bad.count > 500)
    }

    @Test(.enabled(if: hasMetal))
    func domainColorIsAWheelAtOneLightness() throws {
        // Twelve directions around the wheel: every hue lands at nearly the
        // same lightness (a perceptual wheel), and opposite directions take
        // different hues, so the picture says which way a value points.
        final class Wheel: Sketch {
            override var canvasSize: CanvasSize { .size(12, 1) }
            override func draw() {
                let shader = Shader("""
                float4 shade(float2 uv, ShaderInfo info) {
                    float angle = floor(uv.x * 12.0) / 12.0 * 6.28318530718;
                    return float4(domainColor(cpolar(1.0, angle)), 1.0);
                }
                """, using: [.complex])
                drawImage(generate(shader).image, 0, 0)
            }
        }
        let image = try #require(OllinApp.image(of: Wheel()))
        let data = bytes(of: image)
        var lightness: [Double] = []
        var hues: [Double] = []
        for i in 0 ..< 12 {
            let color = Color(red: Double(data[i * 4]) / 255, green: Double(data[i * 4 + 1]) / 255,
                              blue: Double(data[i * 4 + 2]) / 255)
            let lab = OKLab(color)
            lightness.append(lab.l)
            hues.append(atan2(lab.b, lab.a))
        }
        let spread = lightness.max()! - lightness.min()!
        #expect(spread < 0.06, "lightness spread \(spread)")
        let bins = Set(hues.map { Int(($0 + .pi) / (.pi / 9)) })   // twenty-degree bins
        #expect(bins.count >= 10, "hues \(hues)")
    }
}
