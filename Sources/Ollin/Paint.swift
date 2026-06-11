import Foundation
import simd

/// What `fill(_:)` and `stroke(_:)` paint with: a flat `Color` or a `Gradient`.
/// The color and gradient overloads cover most call sites; `Paint` itself is for
/// passing either around as one value (a palette of paints, a paint parameter).
public enum Paint: Equatable, Hashable, Sendable {
    case color(Color)
    case gradient(Gradient)

    /// The flat color, or `nil` for a gradient.
    public var solidColor: Color? {
        if case .color(let c) = self { return c }
        return nil
    }
}

/// A gradient paint: a `Ramp` of colors laid over a geometry — a line between
/// two points, a radius around a center, or the run of the path it strokes.
/// Coordinates are in drawing space (the same space the shape's own coordinates
/// use), so the gradient rides the transform stack with the shapes it paints.
///
/// ```swift
/// fill(.linear(from: Vector2(0, 0), to: Vector2(0, height), sky))
/// fill(.radial(center: Vector2(x, y), radius: 200, [.white, .clear]))
/// stroke(.alongPath(heat))   // the ramp runs start → end along the stroke
/// ```
public struct Gradient: Equatable, Hashable, Sendable {
    /// How the ramp is laid over the canvas.
    public enum Geometry: Equatable, Hashable, Sendable {
        /// The ramp runs from `start` (t = 0) to `end` (t = 1), constant across
        /// the perpendicular; it clamps beyond the ends.
        case linear(start: Vector2, end: Vector2)
        /// The ramp runs outward from `center` (t = 0) to `radius` (t = 1) and
        /// clamps beyond it.
        case radial(center: Vector2, radius: Double)
        /// The ramp follows the painted path: along a `drawLine` / `drawBezier`
        /// stroke and a stroked polyline or contour it runs start → end by arc
        /// length; on a region shape (and its fill) it sweeps once around the
        /// shape's center, starting at 12 o'clock and turning clockwise.
        case alongPath
    }

    /// The colors, with their interpolation space (see `Ramp`).
    public var ramp: Ramp
    /// Where t = 0…1 lands on the canvas.
    public var geometry: Geometry

    public init(ramp: Ramp, geometry: Geometry) {
        self.ramp = ramp
        self.geometry = geometry
    }

    // MARK: Factories (the forms call sites read best with)

    /// A gradient from `start` to `end`.
    public static func linear(from start: Vector2, to end: Vector2, _ ramp: Ramp) -> Gradient {
        Gradient(ramp: ramp, geometry: .linear(start: start, end: end))
    }

    /// A gradient from `start` to `end`, spreading `colors` evenly (mixed in
    /// `space`, OKLab by default).
    public static func linear(from start: Vector2, to end: Vector2, _ colors: [Color],
                              in space: ColorSpace = .oklab) -> Gradient {
        linear(from: start, to: end, Ramp(colors, in: space))
    }

    /// A gradient radiating from `center` out to `radius`.
    public static func radial(center: Vector2, radius: Double, _ ramp: Ramp) -> Gradient {
        Gradient(ramp: ramp, geometry: .radial(center: center, radius: radius))
    }

    /// A gradient radiating from `center` out to `radius`, spreading `colors`
    /// evenly (mixed in `space`, OKLab by default).
    public static func radial(center: Vector2, radius: Double, _ colors: [Color],
                              in space: ColorSpace = .oklab) -> Gradient {
        radial(center: center, radius: radius, Ramp(colors, in: space))
    }

    /// A gradient that follows the painted path (see `Geometry.alongPath`).
    public static func alongPath(_ ramp: Ramp) -> Gradient {
        Gradient(ramp: ramp, geometry: .alongPath)
    }

    /// A gradient that follows the painted path, spreading `colors` evenly
    /// (mixed in `space`, OKLab by default).
    public static func alongPath(_ colors: [Color], in space: ColorSpace = .oklab) -> Gradient {
        alongPath(Ramp(colors, in: space))
    }
}

/// A `Ramp` sampled into a fixed-width lookup row, the form the GPU and the
/// per-vertex tessellated path both consume. Baked once per distinct ramp and
/// cached (see `Drawer.gradientRow(for:)`): the renderer uploads `bytes` as one
/// row of the gradient strip texture, and the tessellated path reads `samples`
/// per vertex — so both pipelines paint the same colors. Sampling happens in the
/// ramp's own `ColorSpace` here, at bake time; downstream interpolation between
/// neighboring texels is then close enough at this resolution that the shader
/// needs no color-space math.
struct BakedGradient {
    /// Texels per row. 256 keeps a row at 1 KB while making the in-between
    /// linear interpolation visually indistinguishable from the exact mix.
    static let width = 256

    /// sRGB-encoded straight-alpha RGBA8, `width` texels.
    let bytes: [UInt8]
    /// The same texels as sRGB-encoded floats, for CPU-side vertex colors.
    let samples: [SIMD4<Float>]

    init(_ ramp: Ramp) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(BakedGradient.width * 4)
        var samples = [SIMD4<Float>]()
        samples.reserveCapacity(BakedGradient.width)
        for i in 0..<BakedGradient.width {
            let t = Double(i) / Double(BakedGradient.width - 1)
            let c = ramp.color(at: t)
            let v = SIMD4<Float>(Float(min(max(c.red, 0), 1)),
                                 Float(min(max(c.green, 0), 1)),
                                 Float(min(max(c.blue, 0), 1)),
                                 Float(min(max(c.alpha, 0), 1)))
            samples.append(v)
            bytes.append(UInt8((v.x * 255).rounded()))
            bytes.append(UInt8((v.y * 255).rounded()))
            bytes.append(UInt8((v.z * 255).rounded()))
            bytes.append(UInt8((v.w * 255).rounded()))
        }
        self.bytes = bytes
        self.samples = samples
    }

    /// The row's color at `t` (clamped), linearly interpolating between texels —
    /// the CPU mirror of the GPU's clamped LUT sample.
    func sample(_ t: Double) -> SIMD4<Float> {
        let clamped = min(max(t, 0), 1)
        let x = clamped * Double(BakedGradient.width - 1)
        let i = Int(x)
        guard i < BakedGradient.width - 1 else { return samples[BakedGradient.width - 1] }
        let f = Float(x - Double(i))
        return samples[i] * (1 - f) + samples[i + 1] * f
    }
}
