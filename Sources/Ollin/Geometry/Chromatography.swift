import Foundation

/// Chromatography rings as geometry a sketch holds: the rings a drop of ink
/// leaves as it spreads through paper, each pigment stopping at its own
/// distance, so the stain is a set of noisy bands around a core, with fibers
/// of the outermost front wicking a little past the edge. Several drops that
/// spread into each other stop where they meet: every ring yields to its
/// neighbor along the line their fronts share, with a ruffle where it was
/// stopped, and no ring ever enters a neighbor's core.
///
/// A drop is `spread(at:radius:)`, a set is `scatter(in:count:radius:)`, and
/// `spread(_:)` takes drops you placed yourself. Each ring is a closed
/// outline with a `tone` (0 the core, 1 the outermost front), each band
/// between two rings is a `Shape`, and the fibers are short open lines, so a
/// sketch fills the bands, strokes the rings, or plots both. Every value
/// repeats from its seed.
///
/// ```swift
/// let stain = Chromatography.scatter(in: canvasRectangle, count: 6, radius: 70 ... 150, seed: 2)
/// noStroke()
/// for drop in stain.drops {
///     for (band, ring) in zip(drop.bands, drop.rings) {
///         fill(inks.color(at: ring.tone))
///         drawShape(band)
///     }
/// }
/// ```
public struct Chromatography: Equatable, Sendable {

    /// One ring of a drop: the closed outline where one pigment front stopped.
    public struct Ring: Equatable, Sendable {
        /// The outline, closed (the last point joins the first).
        public let points: [Vector2]
        /// The ring's nominal radius as a fraction of the drop's, before noise
        /// and before yielding to a neighbor.
        public let fraction: Double
        /// 0 for the core, 1 for the outermost front, evenly between.
        public let tone: Double

        public init(points: [Vector2], fraction: Double, tone: Double) {
            self.points = points
            self.fraction = min(max(fraction, 0), 1)
            self.tone = min(max(tone, 0), 1)
        }
    }

    /// One drop of ink and the rings it left.
    public struct Drop: Equatable, Sendable {
        public let center: Vector2
        /// The radius the outermost front would reach with nothing in its way.
        public let radius: Double
        /// The rings, core first.
        public let rings: [Ring]
        /// Short radial lines at the outermost front, open, root first.
        public let fibers: [[Vector2]]

        public init(center: Vector2, radius: Double, rings: [Ring], fibers: [[Vector2]] = []) {
            self.center = center
            self.radius = max(radius, 0)
            self.rings = rings
            self.fibers = fibers
        }

        /// The core's radius: the innermost ring's nominal radius, which no
        /// neighbor's ring enters.
        public var core: Double { (rings.first?.fraction ?? Chromatography.coreFraction) * radius }

        /// The bands between the rings as shapes, core first: the core disc,
        /// then each annulus between a ring and the one inside it.
        public var bands: [Shape] {
            rings.enumerated().map { i, ring in
                i == 0 ? Shape(ring.points) : Shape(outer: ring.points, holes: [rings[i - 1].points])
            }
        }
    }

    /// The drops, in the order they were placed.
    public let drops: [Drop]

    public init(drops: [Drop]) {
        self.drops = drops
    }

    /// Every ring's outline closed back on its first point, then every fiber,
    /// for a loop that only strokes.
    public var lines: [[Vector2]] {
        var out: [[Vector2]] = []
        for drop in drops {
            for ring in drop.rings where !ring.points.isEmpty { out.append(ring.points + [ring.points[0]]) }
            out.append(contentsOf: drop.fibers)
        }
        return out
    }

    /// The core's share of a drop's radius: the innermost ring's nominal
    /// fraction, and the distance from a neighbor's center no ring enters.
    public static let coreFraction = 0.22

    // MARK: - Spreading

    /// One drop spread at `center` to `radius`, with `rings` fronts from the
    /// core to the edge. `ruffle` is how much a front crinkles where a
    /// neighbor stops it (0 to 1; a lone drop has none), and `fibers` how
    /// densely the outer front wicks past the edge (0 none, 1 a fiber every
    /// few points of circumference).
    public static func spread(at center: Vector2, radius: Double, rings: Int = 5, ruffle: Double = 0.4,
                              fibers: Double = 0.5, seed: Int = 0) -> Chromatography {
        spread([(center, radius)], rings: rings, ruffle: ruffle, fibers: fibers, seed: seed)
    }

    /// `count` drops scattered over `region`, each with a radius drawn from
    /// `radius`, spread into each other so their fronts stop where they meet.
    /// The centers are thrown so no two sit nearer than the larger core would
    /// allow, so every drop keeps its core.
    public static func scatter(in region: Rectangle, count: Int = 6, radius: ClosedRange<Double> = 60 ... 150,
                               rings: Int = 5, ruffle: Double = 0.4, fibers: Double = 0.5,
                               seed: Int = 0) -> Chromatography {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15)
        let lo = max(radius.lowerBound, 1), hi = max(radius.upperBound, lo)
        var placed: [(center: Vector2, radius: Double)] = []
        var tries = 0
        while placed.count < max(count, 0) && tries < max(count, 0) * 60 {
            tries += 1
            let r = Double.random(in: lo ... hi, using: &rng)
            let c = Vector2(Double.random(in: region.x ... region.x + max(region.width, 0), using: &rng),
                            Double.random(in: region.y ... region.y + max(region.height, 0), using: &rng))
            // Two cores may never touch, with a ring's width of air between them.
            let clear = placed.allSatisfy { other in
                (other.center - c).length > (r + other.radius) * coreFraction * 2.2
            }
            if clear { placed.append((c, r)) }
        }
        return spread(placed, rings: rings, ruffle: ruffle, fibers: fibers, seed: seed)
    }

    /// Drops you placed yourself, each a center and the radius it would reach
    /// alone, spread into each other.
    public static func spread(_ placements: [(center: Vector2, radius: Double)], rings: Int = 5,
                              ruffle: Double = 0.4, fibers: Double = 0.5, seed: Int = 0) -> Chromatography {
        let ringCount = max(rings, 1)
        let crinkle = min(max(ruffle, 0), 1)
        let fiberDensity = min(max(fibers, 0), 1)
        let fields = NoiseFields(seed: seed)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let drops = placements.map { (center: $0.center, radius: max($0.radius, 0)) }
        var out: [Drop] = []
        out.reserveCapacity(drops.count)

        for (index, drop) in drops.enumerated() {
            let r = drop.radius
            guard r > 0 else {
                out.append(Drop(center: drop.center, radius: 0, rings: [], fibers: []))
                continue
            }
            let neighbors = drops.enumerated().filter { $0.offset != index && $0.element.radius > 0 }.map(\.element)
            // The fronts' nominal fractions, the core first, crowding toward the
            // edge the way pigments do, each nudged a little by the seed.
            var fractions: [Double] = []
            for i in 0 ..< ringCount {
                let t = ringCount == 1 ? 1 : Double(i) / Double(ringCount - 1)
                var f = coreFraction + (1 - coreFraction) * pow(t, 0.85)
                if i > 0 && i < ringCount - 1 {
                    let gap = (1 - coreFraction) / Double(ringCount - 1)
                    f += gap * 0.2 * Double.random(in: -1 ... 1, using: &rng)
                }
                fractions.append(f)
            }
            fractions[0] = coreFraction
            if ringCount > 1 { fractions[ringCount - 1] = 1 }

            // How far along each ray a front may go before it meets a neighbor's:
            // one cap per ray, shared by every ring of the drop, so the rings
            // keep their order where they are stopped.
            let samples = max(48, Int((r * 2 * .pi / 5).rounded()))
            let noiseOffset = Vector2(Double(index) * 7.31 + 3.7, Double(index) * 4.17 + 1.3)
            var cap = [Double](repeating: .infinity, count: samples)
            var stopped = [Bool](repeating: false, count: samples)   // the outer front, per ray
            for k in 0 ..< samples {
                let theta = Double(k) / Double(samples) * .tau
                let dir = Vector2(angle: theta)
                var limit = Double.infinity
                for other in neighbors {
                    limit = min(limit, Self.reach(from: drop.center, along: dir, toward: other.center,
                                                  ownRadius: r, otherRadius: other.radius))
                }
                if limit < r * 1.2 && crinkle > 0 {
                    // The stopped front crinkles inward, never out.
                    let c = cos(theta), s = sin(theta)
                    let ruff = 0.5 + 0.5 * fields.signedNoise(c * 14 + noiseOffset.x + 41, s * 14 + noiseOffset.y + 43)
                    limit -= crinkle * 0.05 * r * ruff
                }
                cap[k] = max(limit, 0.5)
            }
            var ringPoints: [[Vector2]] = []
            for (ringIndex, fraction) in fractions.enumerated() {
                var points: [Vector2] = []
                points.reserveCapacity(samples)
                let ringPhase = Double(ringIndex) * 0.9
                for k in 0 ..< samples {
                    let theta = Double(k) / Double(samples) * .tau
                    let dir = Vector2(angle: theta)
                    // Three frequencies of noise around the ring, read on a circle so
                    // the outline closes, the two larger ones shared by every ring of
                    // the drop (the fronts follow the paper's grain together, which is
                    // also what keeps the rings from crossing) and the finest one the
                    // ring's own.
                    let c = cos(theta), s = sin(theta)
                    let slow = fields.signedNoise(c * 1.4 + noiseOffset.x, s * 1.4 + noiseOffset.y)
                    let mid = fields.signedNoise(c * 3.6 + noiseOffset.x + 11, s * 3.6 + noiseOffset.y + 17)
                    let fine = fields.signedNoise(c * 9 + noiseOffset.x + 23 + ringPhase * 3, s * 9 + noiseOffset.y + 29)
                    let wobble = 1 + 0.06 * slow + 0.035 * mid + 0.02 * fine
                    let nominal = fraction * r * wobble
                    let rho = min(nominal, cap[k])
                    if ringIndex == ringCount - 1 { stopped[k] = cap[k] < nominal }
                    points.append(drop.center + dir * rho)
                }
                ringPoints.append(points)
            }

            // Fibers wick past the outer front where nothing stopped it.
            var fibers: [[Vector2]] = []
            if fiberDensity > 0, let outer = ringPoints.last {
                let fiberCount = Int((Double(samples) * fiberDensity * 0.45).rounded())
                for _ in 0 ..< fiberCount {
                    let k = Int.random(in: 0 ..< samples, using: &rng)
                    if stopped[k] { continue }
                    let theta = (Double(k) + Double.random(in: 0 ..< 1, using: &rng)) / Double(samples) * .tau
                    let dir = Vector2(angle: theta)
                    let edge = (outer[k] - drop.center).length
                    let reach = edge * (1.04 + 0.1 * Double.random(in: 0 ... 1, using: &rng))
                    let root = edge * (0.9 - 0.06 * Double.random(in: 0 ... 1, using: &rng))
                    let lean = dir.perpendicular * (edge * 0.012 * Double.random(in: -1 ... 1, using: &rng))
                    fibers.append([drop.center + dir * root,
                                   drop.center + dir * ((root + reach) / 2) + lean,
                                   drop.center + dir * reach + lean * 1.6])
                }
            }

            let rings = ringPoints.enumerated().map { i, points in
                Ring(points: points, fraction: fractions[i],
                     tone: ringCount == 1 ? 1 : Double(i) / Double(ringCount - 1))
            }
            out.append(Drop(center: drop.center, radius: r, rings: rings, fibers: fibers))
        }
        return Chromatography(drops: out)
    }

    /// How far a front may travel from `center` along `dir` before it belongs
    /// to the drop at `other`: the nearer of the line where the two fronts
    /// meet (where the distances to the two centers stand in the ratio of the
    /// radii, so the larger drop reaches further) and the rim of the other's
    /// core, with a hair of air kept outside it. Infinite when the ray never
    /// gets there.
    static func reach(from center: Vector2, along dir: Vector2, toward other: Vector2,
                      ownRadius: Double, otherRadius: Double) -> Double {
        let ba = other - center
        let b = dir.x * ba.x + dir.y * ba.y
        let d2 = ba.lengthSquared
        var limit = Double.infinity

        // The meeting line: |P - A| / rA = |P - B| / rB along P = A + t dir.
        let ra2 = ownRadius * ownRadius, rb2 = otherRadius * otherRadius
        let qa = rb2 - ra2, qb = 2 * b * ra2, qc = -d2 * ra2
        if abs(qa) < 1e-9 {
            // Equal radii: the bisector plane, met where t = |BA|^2 / (2 b).
            if b > 0 { limit = min(limit, d2 / (2 * b)) }
        } else {
            let disc = qb * qb - 4 * qa * qc
            if disc >= 0 {
                let root = disc.squareRoot()
                for t in [(-qb - root) / (2 * qa), (-qb + root) / (2 * qa)] where t > 0 {
                    // Only a crossing where the ray heads toward the other drop counts.
                    let p = dir * t
                    let toOther = (p - ba).lengthSquared
                    if toOther < d2 { limit = min(limit, t) }
                }
            }
        }

        // The other's core, kept clear by a hair.
        let core = otherRadius * coreFraction + 1
        let c = d2 - core * core
        let disc = b * b - c
        if disc >= 0 {
            let t0 = b - disc.squareRoot()
            if t0 > 0 { limit = min(limit, t0) }
            else if c < 0 { limit = 0 }   // the ray starts inside the core
        }
        return limit
    }
}
