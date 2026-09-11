import Foundation

/// Generative watercolor: soft-edged pigment blobs built from nothing but
/// polygon deformation and translucency. One irregular polygon is wobbled
/// into a base shape; each painted layer wobbles it a little further and
/// fills at a few percent opacity; a few dozen stacked layers read as
/// pigment pooling on wet paper, dense in the middle and fading unevenly at
/// the edge.
///
/// ```swift
/// var rng = SplitMix64(seed: 7)
/// let wash = Watercolor(around: center, radius: 220, using: &rng)
/// noStroke()
/// fill(Color(hex: 0x1F6E8C).withAlpha(0.04))
/// for _ in 0 ..< 40 {
///     drawShape(wash.layerShape(using: &rng))
/// }
/// ```
///
/// The deformation is recursive edge subdivision: each edge splits at its
/// midpoint, the midpoint jumps by a Gaussian scaled by that edge's own
/// variance, and the two child edges inherit a decayed, jittered share of
/// it. Because variance rides the edges, some stretches of outline stay
/// nearly crisp while others bloom, which is what keeps the blob from
/// looking like a fuzzy circle. Deterministic from the generator you pass;
/// build in `setup()` (or behind `noLoop()`), since the stacked fills are
/// heavy to re-tessellate every frame.

public struct Watercolor: Equatable, Sendable {
    /// The deformed base polygon every layer grows from.
    public private(set) var polygon: [Vector2]

    /// Per-edge variance, in canvas units: `variances[i]` drives the edge
    /// from `polygon[i]` to the next vertex around.
    public private(set) var variances: [Double]

    /// The detail floor, in canvas units: edges shorter than this stop
    /// subdividing, which is what keeps a layer's point count bounded no
    /// matter how many rounds run (a sub-pixel split changes nothing you
    /// can see, so the default suits any canvas).
    public var detail: Double

    /// How many extra deformation rounds each `layer(...)` runs by default.
    private let layerRounds: Int

    // MARK: - Building the base

    /// Build a base from `polygon`: each edge takes a jittered share of
    /// `variance` (some sides wobbly, some nearly straight), then the whole
    /// outline deforms through `rounds` shared subdivision rounds. All the
    /// layers drawn from this base inherit that one character.
    ///
    /// - Parameters:
    ///   - polygon: The starting outline, at least a triangle.
    ///   - variance: The Gaussian scale of the first-round midpoint jumps,
    ///     in canvas units; defaults to a quarter of the mean edge length.
    ///   - rounds: Shared deformation rounds baked into the base.
    ///   - detail: The detail floor, in canvas units. An edge shorter than
    ///     this stops subdividing, which is what bounds the point count.
    ///   - rng: The random source; seed it to reproduce the blob.
    public init<R: RandomNumberGenerator>(polygon: [Vector2],
                                          variance: Double? = nil,
                                          rounds: Int = 7,
                                          detail: Double = 2,
                                          using rng: inout R) {
        precondition(polygon.count >= 3, "Watercolor needs at least a triangle")
        var points = polygon
        let count = Double(points.count)
        let meanEdge = (0 ..< points.count).reduce(0.0) { sum, i in
            sum + points[i].distance(to: points[(i + 1) % points.count])
        } / count
        let scale = variance ?? meanEdge / 4
        var spreads = (0 ..< points.count).map { _ in
            scale * Double.random(in: 0.2 ... 1.8, using: &rng)
        }
        self.detail = max(detail, 0)
        for _ in 0 ..< max(rounds, 0) {
            Watercolor.deformOnce(&points, &spreads, floor: self.detail, using: &rng)
        }
        self.polygon = points
        variances = spreads
        layerRounds = 4
    }

    /// Build a base blob around a center: an irregular polygon (`sides`
    /// vertices with jittered angles and radii, `irregularity` 0...1 from
    /// regular to lumpy) fed through `init(polygon:...)`. The everyday
    /// starting point; `variance` defaults to a fraction of the radius.
    public init<R: RandomNumberGenerator>(around center: Vector2,
                                          radius: Double,
                                          sides: Int = 10,
                                          irregularity: Double = 0.5,
                                          variance: Double? = nil,
                                          rounds: Int = 7,
                                          detail: Double = 2,
                                          using rng: inout R) {
        let n = max(sides, 3)
        let lumpiness = min(max(irregularity, 0), 1)
        let ring = (0 ..< n).map { i -> Vector2 in
            let jitter = Double.random(in: -0.5 ... 0.5, using: &rng) * lumpiness
            let angle = (Double(i) + jitter) / Double(n) * .tau
            let r = radius * (1 + Double.random(in: -0.4 ... 0.4, using: &rng) * lumpiness)
            return center + Vector2(cos(angle), sin(angle)) * r
        }
        self.init(polygon: ring, variance: variance ?? radius / 5,
                  rounds: rounds, detail: detail, using: &rng)
    }

    // MARK: - Layers

    /// One painted layer: the base polygon pushed through `rounds` more
    /// deformation rounds. Every call draws fresh randomness from `rng`, so
    /// consecutive layers differ; fill each at low opacity and stack them.
    public func layer<R: RandomNumberGenerator>(rounds: Int? = nil,
                                                using rng: inout R) -> [Vector2] {
        var points = polygon
        var spreads = variances
        for _ in 0 ..< max(rounds ?? layerRounds, 0) {
            Watercolor.deformOnce(&points, &spreads, floor: detail, using: &rng)
        }
        return points
    }

    /// `count` layers in one call, each an independent further deformation
    /// of the base.
    public func layers<R: RandomNumberGenerator>(_ count: Int,
                                                 rounds: Int? = nil,
                                                 using rng: inout R) -> [[Vector2]] {
        (0 ..< max(count, 0)).map { _ in layer(rounds: rounds, using: &rng) }
    }

    /// One painted layer as a fillable `Shape`, wound non-zero so the
    /// deformed outline's self-crossings stay solid pigment instead of
    /// cutting even-odd pinholes. The form to hand straight to `drawShape`.
    public func layerShape<R: RandomNumberGenerator>(rounds: Int? = nil,
                                                     using rng: inout R) -> Shape {
        Shape(contours: [Contour(layer(rounds: rounds, using: &rng), closed: true)],
              winding: .nonZero)
    }

    // MARK: - The deformation round

    /// One subdivision round over a closed polygon: every edge splits at its
    /// midpoint, the midpoint jumps by an isotropic Gaussian scaled by the
    /// edge's variance, and both children inherit a decayed, jittered share.
    /// The original vertices stay put; only the new midpoints move. Edges
    /// already shorter than `floor` pass through untouched.
    static func deformOnce<R: RandomNumberGenerator>(_ points: inout [Vector2],
                                                     _ spreads: inout [Double],
                                                     floor: Double,
                                                     using rng: inout R) {
        let n = points.count
        let floor2 = floor * floor
        var newPoints: [Vector2] = []
        var newSpreads: [Double] = []
        newPoints.reserveCapacity(n * 2)
        newSpreads.reserveCapacity(n * 2)
        for i in 0 ..< n {
            let a = points[i]
            let b = points[(i + 1) % n]
            let spread = spreads[i]
            newPoints.append(a)
            guard a.distanceSquared(to: b) > floor2 else {
                newSpreads.append(spread)
                continue
            }
            let mid = a.lerp(to: b, 0.5)
            let jumped = mid + Vector2(gaussian(using: &rng) * spread,
                                       gaussian(using: &rng) * spread)
            newPoints.append(jumped)
            newSpreads.append(spread * Double.random(in: 0.4 ... 0.8, using: &rng))
            newSpreads.append(spread * Double.random(in: 0.4 ... 0.8, using: &rng))
        }
        points = newPoints
        spreads = newSpreads
    }

    /// A standard normal from any generator (Box-Muller, stateless so the
    /// draw count per call is fixed and reproducible).
    private static func gaussian<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        let u1 = Double.random(in: 1e-12 ..< 1, using: &rng)
        let u2 = Double.random(in: 0 ..< 1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(.tau * u2)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Paint a watercolor blob at (`x`, `y`) in the current fill color:
    /// builds an irregular base polygon of the given `radius`, then stacks
    /// `layers` further-deformed copies, each at `opacity`. Driven by the
    /// seeded `random`, so `seed(_:)` reproduces the blob. Heavy work by
    /// design (every layer is a full concave fill): paint in `setup()` into
    /// a `makeBatch { }`, or behind `noLoop()`, rather than every frame.
    func drawWatercolor(_ x: Double, _ y: Double, _ radius: Double,
                        layers: Int = 40, opacity: Double = 0.04,
                        variance: Double? = nil) {
        drawWatercolor(center: Vector2(x, y), radius: radius,
                       layers: layers, opacity: opacity, variance: variance)
    }

    /// Paint a watercolor blob, `drawWatercolor(_:_:_:)`, at `center`.
    func drawWatercolor(center: Vector2, radius: Double,
                        layers: Int = 40, opacity: Double = 0.04,
                        variance: Double? = nil) {
        let base = Watercolor(around: center, radius: radius,
                              variance: variance, using: &rng)
        paintWatercolor(base, layers: layers, opacity: opacity)
    }

    /// Paint a watercolor wash over your own outline: `polygon` is the base
    /// shape (a rough silhouette works better than a perfect one), deformed
    /// and stacked exactly like the blob form.
    func drawWatercolor(_ polygon: [Vector2],
                        layers: Int = 40, opacity: Double = 0.04,
                        variance: Double? = nil) {
        let base = Watercolor(polygon: polygon, variance: variance, using: &rng)
        paintWatercolor(base, layers: layers, opacity: opacity)
    }

    private func paintWatercolor(_ base: Watercolor, layers: Int, opacity: Double) {
        withState {
            noStroke()
            // The pigment is the current fill color (watercolor needs a solid
            // ink to dilute; a gradient or noFill paints in black ink).
            let ink: Color
            if case .some(.color(let current)) = drawer.fillPaint {
                ink = current
            } else {
                ink = .black
            }
            fill(ink.withAlpha(ink.alpha * opacity))
            for _ in 0 ..< max(layers, 0) {
                drawShape(base.layerShape(using: &rng))
            }
        }
    }
}
