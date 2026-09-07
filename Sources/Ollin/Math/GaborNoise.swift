import Foundation

/// Gabor noise: a noise whose spectrum you design instead of inherit. Every
/// kernel is a small Gaussian blob carrying a cosine wave, scattered at random
/// and summed (sparse Gabor convolution), so the field has one principal
/// `wavelength` and, when `spread` is small, one direction. The parameters
/// mean what they mean on `Generator.gaborNoise`, and the two compute the same
/// field: `GaborNoise(wavelength: 24).value(x, y)` is the value the generator
/// paints at pixel `(x, y)`, so a sketch can read on the CPU what the GPU drew.
/// Coordinates are pixels. The kernels are filtered for a one-pixel footprint,
/// so a wavelength driven toward two pixels fades to gray instead of aliasing.
///
/// Build one and keep it: the constructor precomputes the kernel, and every
/// `value` then costs the nine cells around the point.
public struct GaborNoise: Sendable, Equatable {
    /// The wave period in pixels.
    public let wavelength: Double
    /// The spectral width of the band as a fraction of the frequency: 0.2 is
    /// nearly a pure wave, 1 blobby. The kernel radius is `wavelength / bandwidth`.
    public let bandwidth: Double
    /// The wave direction in radians (0 oscillates along x: vertical stripes).
    public let angle: Double
    /// How far each kernel's own direction may wander from `angle`: 0 is one
    /// direction, π every direction (the isotropic field).
    public let spread: Double
    /// How many kernels overlap at any point (the quality dial).
    public let impulses: Int
    /// Slides every wave along its own direction; periodic over 2π.
    public let phase: Double
    /// Picks the field.
    public let seed: Int

    // The kernel, worked out once: the cell size (also the kernel radius), the
    // mean impulses per cell, the filtered envelope width / frequency / gain,
    // and 1 / (3 sigma) of the unfiltered noise.
    private let radius: Double
    private let density: Double
    private let a: Double
    private let f: Double
    private let k: Double
    private let norm: Double
    private let seedBits: UInt32
    private let limit: Float

    public init(wavelength: Double = 32, bandwidth: Double = 0.5, angle: Double = 0,
                spread: Double = .pi, impulses: Int = 32, phase: Double = 0, seed: Int = 0) {
        self.wavelength = max(1, wavelength)
        self.bandwidth = min(max(bandwidth, 0.05), 4)
        self.angle = angle
        self.spread = min(max(spread, 0), .pi)
        self.impulses = min(max(impulses, 1), 128)
        self.phase = phase
        self.seed = seed
        let f0 = 1 / self.wavelength
        let a0 = self.bandwidth * f0
        let n = Double(self.impulses)
        radius = 1 / a0
        density = n / .pi
        // The pixel footprint, a Gaussian of sigma 0.5 px, applied in the
        // frequency domain: the product of two Gaussians is a Gaussian, so the
        // filtered kernel is again a Gabor kernel with a narrower band, a lower
        // frequency, and less gain.
        let s2 = 0.25
        let aa = a0 * a0
        let a1sq = 1 / (1 / aa + 2 * .pi * s2)
        a = a1sq.squareRoot()
        f = f0 / (1 + 2 * .pi * s2 * aa)
        k = (a1sq / aa) * exp(-0.5 * f0 * f0 / (1 / (4 * .pi * .pi * s2) + aa / (2 * .pi)))
        // Variance of the unfiltered noise: impulse density times E[w^2] (1/3
        // for weights uniform on [-1, 1]) times the kernel's squared integral,
        // (1 + exp(-2 pi f0^2 / a0^2)) / (4 a0^2); with the density n / (pi r^2)
        // and r = 1 / a0 the widths cancel.
        let variance = n * (1 + exp(-2 * .pi * f0 * f0 / aa)) / (12 * .pi)
        norm = 1 / (3 * variance.squareRoot())
        seedBits = Self.seedBits(seed)
        limit = Float(exp(-density))
    }

    /// The seed as the shader carries it: the low 24 bits, every seed a sketch
    /// hands out, as an exact float.
    static func seedBits(_ seed: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: seed) & 0xFF_FFFF
    }

    /// The noise at pixel `(x, y)`, in `0...1` (three standard deviations
    /// mapped onto the range, so a rare peak clips).
    public func value(_ x: Double, _ y: Double) -> Double {
        min(max(0.5 + 0.5 * sum(x, y) * norm, 0), 1)
    }

    /// The noise at `point` (see `value(_:_:)`).
    public func value(at point: Vector2) -> Double { value(point.x, point.y) }

    /// The noise at pixel `(x, y)`, in `-1...1`.
    public func signedValue(_ x: Double, _ y: Double) -> Double {
        min(max(sum(x, y) * norm, -1), 1)
    }

    /// The nine cells around the point, summed.
    private func sum(_ x: Double, _ y: Double) -> Double {
        let qx = x / radius, qy = y / radius
        let cx = floor(qx), cy = floor(qy)
        let fx = qx - cx, fy = qy - cy
        let i = Int(cx), j = Int(cy)
        var total = 0.0
        for dj in -1...1 {
            for di in -1...1 {
                total += cell(i + di, j + dj, fx - Double(di), fy - Double(dj))
            }
        }
        return total
    }

    /// One cell's impulses, the point given in that cell's own unit square.
    private func cell(_ i: Int, _ j: Int, _ lx: Double, _ ly: Double) -> Double {
        var state = cellSeed(i, j)
        // Knuth's small-mean Poisson draw for the impulse count, bounded the
        // way the shader bounds it.
        var t = Self.uniform(&state)
        var count = 0
        while t > limit && count < 48 { count += 1; t *= Self.uniform(&state) }
        var total = 0.0
        for _ in 0 ..< count {
            let ux = Double(Self.uniform(&state)), uy = Double(Self.uniform(&state))
            let w = Double(Self.uniform(&state)) * 2 - 1
            let omega = angle + spread * (Double(Self.uniform(&state)) * 2 - 1)
            let dx = lx - ux, dy = ly - uy
            guard dx * dx + dy * dy < 1 else { continue }
            let px = dx * radius, py = dy * radius
            let envelope = k * exp(-.pi * a * a * (px * px + py * py))
            let wave = cos(2 * .pi * f * (px * cos(omega) + py * sin(omega)) + phase)
            total += w * envelope * wave
        }
        return total
    }

    /// One well-mixed seed per cell, made odd for the generator below.
    private func cellSeed(_ i: Int, _ j: Int) -> UInt32 {
        var h = (UInt32(truncatingIfNeeded: i &+ 1_073_741_824) &* 0x9E37_79B1)
              ^ (UInt32(truncatingIfNeeded: j &+ 1_073_741_824) &* 0x85EB_CA77)
              ^ (seedBits &* 0xC2B2_AE3D)
        h ^= h >> 16; h &*= 0x7FEB_352D; h ^= h >> 15; h &*= 0x846C_A68B; h ^= h >> 16
        return h | 1
    }

    /// The Borosh-Niederreiter multiplicative congruential step, in the
    /// shader's own single precision so both sides draw the same numbers.
    @inline(__always)
    private static func uniform(_ x: inout UInt32) -> Float {
        x &*= 3_039_177_861
        return Float(x) * 2.3283064365386963e-10
    }
}

public extension Sketch {
    /// Gabor noise at pixel `(x, y)`, in `0...1`: the field
    /// `generate(.gaborNoise(...))` paints, read on the CPU with the same
    /// parameters (see `GaborNoise`). Coordinates are pixels, `wavelength` the
    /// wave period in pixels, `bandwidth` the band's width as a fraction of the
    /// frequency, `angle` the wave direction and `spread` how far each kernel's
    /// direction may wander from it (π is every direction), `impulses` the
    /// quality, `phase` the slide of the waves (periodic over 2π), and `seed`
    /// the field. Unlike `noise()`, it is not pinned by `noiseSeed`: the seed
    /// is a parameter so the two forms stay one field. Sampling many points a
    /// frame? Build one `GaborNoise` and ask it, so the kernel is set up once.
    func gaborNoise(_ x: Double, _ y: Double, wavelength: Double = 32, bandwidth: Double = 0.5,
                    angle: Double = 0, spread: Double = .pi, impulses: Int = 32,
                    phase: Double = 0, seed: Int = 0) -> Double {
        GaborNoise(wavelength: wavelength, bandwidth: bandwidth, angle: angle, spread: spread,
                   impulses: impulses, phase: phase, seed: seed).value(x, y)
    }
}
