import Foundation

/// A complex number, `real + imaginary·i`, where `i` squared is `-1`.
///
/// A complex number is a point of the plane that knows how to multiply. Adding
/// two of them adds their coordinates, exactly as `Vector2` does; multiplying
/// them multiplies their lengths and *adds their angles*, which is the one thing
/// a plain vector cannot do and the reason so much of generative work is
/// written in them: an escape-time fractal is `z * z + c` repeated, a domain
/// coloring paints a function of `z` over the plane it acts on, a Möbius map
/// turns the plane inside out around a point, and a conformal warp keeps every
/// small square square. The GPU side of the same arithmetic is the shader
/// library's `complex` module (`cmul`, `cexp`, `domainColor`, and the rest), so
/// a curve worked out here in `draw()` lands on the pixels a shader paints.
///
/// `Complex` is a `Numeric` value, so it takes literals, sums under `reduce`,
/// and mixes with `Double` on either side of `+`, `-`, `*`, and `/`. The
/// transcendental functions are static members, `Complex.exp(z)`,
/// `Complex.pow(z, 3)`, `Complex.sin(z)`, which keeps a plain `Double`
/// expression such as `pow(2, 20 * t - 10) * sin(x)` from having to consider
/// this type at all.
///
/// ```swift
/// var z = Complex(0.3, 0.5)
/// let c: Complex = -0.8 + 0.156 * .i
/// for _ in 0 ..< 40 { z = z * z + c }      // one Julia orbit
/// let turned = z * .unit(.pi / 6)          // turned by thirty degrees
/// let spiral = Complex.exp(z)              // e to the z
/// drawCircle(center: Vector2(turned), radius: 4)
/// ```
///
/// The plane is read the way mathematics writes it, the imaginary axis pointing
/// *up*; a `Vector2` is in canvas points with y down, so `Vector2(z)` and
/// `Complex(v)` copy the coordinates and leave the flip to the framing, the way
/// the shader library's `complexPlane` does.
public struct Complex: Hashable, Codable, Sendable {
    /// The real part.
    public var real: Double
    /// The imaginary part, the coefficient of `i`.
    public var imaginary: Double

    /// `real + imaginary·i`. The second argument defaults to zero, so
    /// `Complex(3)` is the real number three.
    public init(_ real: Double, _ imaginary: Double = 0) {
        self.real = real
        self.imaginary = imaginary
    }

    /// `real + imaginary·i`, with the parts named.
    public init(real: Double, imaginary: Double) {
        self.real = real
        self.imaginary = imaginary
    }

    /// The point `vector.x + vector.y·i`. The coordinates are copied as they
    /// are, so a canvas point comes in with y down; see `complexPlane` in the
    /// shader library for a framing that turns the axis up.
    public init(_ vector: Vector2) {
        self.real = vector.x
        self.imaginary = vector.y
    }

    /// The number at distance `magnitude` from the origin, turned `argument`
    /// radians from the positive real axis: the polar form.
    public init(magnitude: Double, argument: Double) {
        self.real = magnitude * Foundation.cos(argument)
        self.imaginary = magnitude * Foundation.sin(argument)
    }

    /// `0`.
    public static let zero = Complex(0, 0)
    /// `1`.
    public static let one = Complex(1, 0)
    /// The imaginary unit, `i`.
    public static let i = Complex(0, 1)

    /// The point on the unit circle at `angle` radians, `e^(i·angle)`:
    /// multiplying by it turns a number by that angle.
    public static func unit(_ angle: Double) -> Complex {
        Complex(Foundation.cos(angle), Foundation.sin(angle))
    }

    /// The distance from the origin, `|z|` (the modulus).
    public var magnitude: Double { (real * real + imaginary * imaginary).squareRoot() }

    /// `|z|²`, without the square root: cheaper when you only compare sizes,
    /// which is what an escape test does.
    public var magnitudeSquared: Double { real * real + imaginary * imaginary }

    /// The angle from the positive real axis, in radians, in `(-pi, pi]`.
    public var argument: Double { atan2(imaginary, real) }

    /// The mirror image across the real axis, `real - imaginary·i`.
    public var conjugate: Complex { Complex(real, -imaginary) }

    /// `1 / z`.
    public var reciprocal: Complex {
        let d = magnitudeSquared
        return Complex(real / d, -imaginary / d)
    }

    /// The same point as a `Vector2`, coordinates copied as they are.
    public var vector: Vector2 { Vector2(real, imaginary) }

    /// Whether both parts are finite numbers.
    public var isFinite: Bool { real.isFinite && imaginary.isFinite }

    /// The number turned by `angle` radians about the origin.
    public func rotated(by angle: Double) -> Complex {
        self * Complex.unit(angle)
    }

    /// The principal square root: half the argument, the root of the modulus.
    /// The other root is its negative.
    public func squareRoot() -> Complex {
        Complex(magnitude: magnitude.squareRoot(), argument: argument / 2)
    }
}

// MARK: - Arithmetic

extension Complex: AdditiveArithmetic, SignedNumeric, ExpressibleByFloatLiteral {
    public typealias Magnitude = Double

    public init?<T: BinaryInteger>(exactly source: T) {
        guard let value = Double(exactly: source) else { return nil }
        self.init(value)
    }

    public init(integerLiteral value: Int) { self.init(Double(value)) }
    public init(floatLiteral value: Double) { self.init(value) }

    public static func + (a: Complex, b: Complex) -> Complex {
        Complex(a.real + b.real, a.imaginary + b.imaginary)
    }

    public static func - (a: Complex, b: Complex) -> Complex {
        Complex(a.real - b.real, a.imaginary - b.imaginary)
    }

    public static prefix func - (a: Complex) -> Complex { Complex(-a.real, -a.imaginary) }

    public static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.real * b.real - a.imaginary * b.imaginary,
                a.real * b.imaginary + a.imaginary * b.real)
    }

    public static func / (a: Complex, b: Complex) -> Complex {
        let d = b.magnitudeSquared
        return Complex((a.real * b.real + a.imaginary * b.imaginary) / d,
                       (a.imaginary * b.real - a.real * b.imaginary) / d)
    }

    public static func += (a: inout Complex, b: Complex) { a = a + b }
    public static func -= (a: inout Complex, b: Complex) { a = a - b }
    public static func *= (a: inout Complex, b: Complex) { a = a * b }
    public static func /= (a: inout Complex, b: Complex) { a = a / b }

    // A real number on either side, so a scale or an offset needs no wrapping.
    // Disfavored so that a plain `Double` expression keeps reading as one:
    // without the mark, `lengths.reduce(0, +)` over doubles is ambiguous, since
    // `0` could be this type's literal and `+ (Complex, Double)` would fit.

    @_disfavoredOverload
    public static func + (a: Complex, b: Double) -> Complex { Complex(a.real + b, a.imaginary) }
    @_disfavoredOverload
    public static func + (a: Double, b: Complex) -> Complex { Complex(a + b.real, b.imaginary) }
    @_disfavoredOverload
    public static func - (a: Complex, b: Double) -> Complex { Complex(a.real - b, a.imaginary) }
    @_disfavoredOverload
    public static func - (a: Double, b: Complex) -> Complex { Complex(a - b.real, -b.imaginary) }
    @_disfavoredOverload
    public static func * (a: Complex, b: Double) -> Complex { Complex(a.real * b, a.imaginary * b) }
    @_disfavoredOverload
    public static func * (a: Double, b: Complex) -> Complex { Complex(a * b.real, a * b.imaginary) }
    @_disfavoredOverload
    public static func / (a: Complex, b: Double) -> Complex { Complex(a.real / b, a.imaginary / b) }
    @_disfavoredOverload
    public static func / (a: Double, b: Complex) -> Complex { Complex(a) / b }
}

extension Complex: CustomStringConvertible {
    /// Reads as it is written: `1 + 2i`, `1 - 2i`, `2i`, `-i`, `3`.
    public var description: String {
        func plain(_ x: Double) -> String {
            x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(x)
        }
        if imaginary == 0 { return plain(real) }
        let unit = abs(imaginary) == 1 ? "" : plain(abs(imaginary))
        let sign = imaginary < 0 ? "-" : "+"
        if real == 0 { return (imaginary < 0 ? "-" : "") + unit + "i" }
        return "\(plain(real)) \(sign) \(unit)i"
    }
}

extension Vector2 {
    /// The point `(z.real, z.imaginary)`, coordinates copied as they are.
    public init(_ z: Complex) {
        self.init(z.real, z.imaginary)
    }
}

// MARK: - Functions

extension Complex {
    // Static members rather than free functions on purpose. A free `pow(_:
    // Complex, _: Double)` or `sin(_: Complex)` joins the candidates for every
    // `pow(2, x)` and `sin(x)` in the program, and with a literal-taking type
    // in play a plain easing curve took three seconds to type-check and one in
    // the framework stopped compiling outright. As members they never enter
    // that search.

    /// `e^z`: the modulus is `e` to the real part, the argument is the
    /// imaginary part, so the wheel repeats up the imaginary axis every `2·pi`.
    public static func exp(_ z: Complex) -> Complex {
        Complex(magnitude: Foundation.exp(z.real), argument: z.imaginary)
    }

    /// The natural logarithm, principal branch: `log|z| + i·arg z`, with the
    /// argument in `(-pi, pi]`, so the values jump across the negative real
    /// axis. That cut is real, and a domain coloring shows it.
    public static func log(_ z: Complex) -> Complex {
        Complex(Foundation.log(z.magnitude), z.argument)
    }

    /// `z` to a real power, principal branch: the modulus to the power, the
    /// argument times it. A whole number winds the plane cleanly; a fraction
    /// leaves the seam along the negative real axis.
    public static func pow(_ z: Complex, _ n: Double) -> Complex {
        if z == .zero { return n == 0 ? .one : .zero }
        return Complex(magnitude: Foundation.pow(z.magnitude, n), argument: z.argument * n)
    }

    /// `z` to a complex power, `exp(w·log z)`, principal branch; `0` to any
    /// power but zero is `0`.
    public static func pow(_ z: Complex, _ w: Complex) -> Complex {
        if z == .zero { return w == .zero ? .one : .zero }
        return exp(w * log(z))
    }

    /// `z` to a whole power by repeated squaring: exact where the polar form
    /// would round, which is what an orbit iterated thousands of times wants.
    /// A negative power is the reciprocal.
    public static func pow(_ z: Complex, _ n: Int) -> Complex {
        if n < 0 { return pow(z, -n).reciprocal }
        var result = Complex.one, base = z, e = n
        while e > 0 {
            if e & 1 == 1 { result *= base }
            base *= base
            e >>= 1
        }
        return result
    }

    /// The principal square root (see `squareRoot()`).
    public static func sqrt(_ z: Complex) -> Complex { z.squareRoot() }

    /// `sin z`.
    public static func sin(_ z: Complex) -> Complex {
        Complex(Foundation.sin(z.real) * Foundation.cosh(z.imaginary),
                Foundation.cos(z.real) * Foundation.sinh(z.imaginary))
    }

    /// `cos z`.
    public static func cos(_ z: Complex) -> Complex {
        Complex(Foundation.cos(z.real) * Foundation.cosh(z.imaginary),
                -Foundation.sin(z.real) * Foundation.sinh(z.imaginary))
    }

    /// `tan z`, as `sin z / cos z`: a zero and a pole alternate along the real
    /// axis half a period apart.
    public static func tan(_ z: Complex) -> Complex { sin(z) / cos(z) }

    /// `sinh z`.
    public static func sinh(_ z: Complex) -> Complex {
        Complex(Foundation.sinh(z.real) * Foundation.cos(z.imaginary),
                Foundation.cosh(z.real) * Foundation.sin(z.imaginary))
    }

    /// `cosh z`.
    public static func cosh(_ z: Complex) -> Complex {
        Complex(Foundation.cosh(z.real) * Foundation.cos(z.imaginary),
                Foundation.sinh(z.real) * Foundation.sin(z.imaginary))
    }

    /// `tanh z`, as `sinh z / cosh z`.
    public static func tanh(_ z: Complex) -> Complex { sinh(z) / cosh(z) }
}
