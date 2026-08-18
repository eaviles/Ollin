import Foundation

/// One sinusoidal cam of a guilloche: `bumps` waves of `amplitude` around the
/// circle, starting at `phase`. A single rosette scallops a ring; stacking
/// several (a coarse one plus a fine one) nests their waves into the layered
/// engine-turned look.
public struct Rosette: Equatable, Sendable {
    /// How many waves fit around the circle. Whole numbers close the curve.
    public var bumps: Int
    /// The wave's height, in the same units as the ring radii.
    public var amplitude: Double
    /// Where around the circle the first wave starts.
    public var phase: Double

    public init(bumps: Int, amplitude: Double, phase: Double = 0) {
        self.bumps = bumps
        self.amplitude = amplitude
        self.phase = phase
    }
}

/// A guilloche rosette: the engine-turned ornament of watch faces, banknotes,
/// and certificates. The machine behind the look is a lathe whose cams rock
/// the cutter as the piece turns; each pass cuts one wavy ring, and the piece
/// is turned a hair between passes. This traces the same recipe: `rings`
/// concentric closed curves from `innerRadius` out to `outerRadius`, each
/// `r(θ) = base + Σ amplitude·sin(bumps·θ + phase)` over the stacked
/// `rosettes`, ring `k` rotated by `k · twist`. The creeping rotation is what
/// weaves neighboring rings into the braided moiré.
///
/// Returns one closed `Contour` per ring, innermost first, centered on the
/// origin, so the line-work strokes, hatches, and exports to SVG for a pen
/// plotter. Pure closed form: no randomness anywhere.
///
/// ```swift
/// stroke(.white); strokeWeight(1); noFill()
/// withState {
///     translate(width / 2, height / 2)
///     for ring in guilloche(rings: 36, innerRadius: 90, outerRadius: 320,
///                           rosettes: [Rosette(bumps: 12, amplitude: 26)]) {
///         drawPolyline(ring.points, closed: true)
///     }
/// }
/// ```
public func guilloche(rings: Int, innerRadius: Double, outerRadius: Double,
                      rosettes: [Rosette], twist: Double = .pi / 90,
                      samples: Int? = nil) -> [Contour] {
    guard rings > 0 else { return [] }
    let maxBumps = rosettes.map { abs($0.bumps) }.max() ?? 1
    let count = samples.map { max(16, $0) } ?? min(max(360, 48 * maxBumps), 4096)
    return (0..<rings).map { ring in
        let fraction = rings > 1 ? Double(ring) / Double(rings - 1) : 0
        let base = innerRadius + (outerRadius - innerRadius) * fraction
        let turn = Double(ring) * twist
        return Contour((0..<count).map { i in
            let theta = Double(i) / Double(count) * .tau
            var r = base
            for rosette in rosettes {
                r += rosette.amplitude * sin(Double(rosette.bumps) * (theta + turn)
                                             + rosette.phase)
            }
            return Vector2(angle: theta, length: r)
        }, closed: true)
    }
}

/// The one-cam convenience: a guilloche from a single rosette of `bumps`
/// waves at `amplitude`. See `guilloche(rings:innerRadius:outerRadius:rosettes:twist:samples:)`
/// for the stacked form and the recipe.
public func guilloche(rings: Int, innerRadius: Double, outerRadius: Double,
                      bumps: Int, amplitude: Double, twist: Double = .pi / 90,
                      samples: Int? = nil) -> [Contour] {
    guilloche(rings: rings, innerRadius: innerRadius, outerRadius: outerRadius,
              rosettes: [Rosette(bumps: bumps, amplitude: amplitude)],
              twist: twist, samples: samples)
}
