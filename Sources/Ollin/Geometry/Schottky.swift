import Foundation

/// Schottky groups: circles paired off by Möbius maps, and the endless lace of
/// circles that pairing generates.
///
/// Take an even number of circles and pair them up. Each pairing is the Möbius
/// map carrying the *outside* of one circle onto the *inside* of its partner,
/// so applying it to anything drops that thing into the partner disc, smaller.
/// Apply the pairings and their inverses in every order and the circles nest
/// forever; what they close down onto is the group's limit set.
///
/// ```swift
/// let lace = schottkyCircles(.necklace, in: canvasRectangle.inset(by: 60))
/// noFill()
/// drawCircles(lace)
/// ```
///
/// Circles come back in canvas coordinates, so the lace lands among the
/// circles that made it, needing no fitting. Since a Möbius map carries a
/// circle to a circle, the output is real circles rather than a flattened
/// polyline: `drawCircles` renders them analytically, and the vector-export
/// path writes true circle geometry for a plotter.
///
/// Separated circles give a Cantor dust strung along the lace; tightening them
/// toward tangency fuses the dust into a curve. That whole spectrum is the
/// family's parameter space, and unlike `kleinianLimitSet`, which traces one
/// *connected* curve, the circle orbit renders every point of it.
///
/// The walk is rng-free and adaptive (a branch stops once its circle falls
/// under `minRadius`, since everything below nests inside it), so the result
/// is deterministic given the pairings, `minRadius`, and `maxDepth`.

// MARK: - Pairings

/// One circle pairing: the Möbius map carrying the outside of `from` onto the
/// inside of `to`, turned by `twist` radians about the target center.
///
/// A `twist` of zero is the plain pairing, which reads as a mirror-like fold;
/// turning it rotates each nested generation against the last, which is what
/// puts the spiral in a spiral lace. The angle runs in canvas orientation
/// (clockwise, with y down).
public struct SchottkyPairing: Equatable, Sendable {
    public var from: Circle
    public var to: Circle
    public var twist: Double

    public init(from: Circle, to: Circle, twist: Double = 0) {
        self.from = from
        self.to = to
        self.twist = twist
    }
}

// MARK: - The circle orbit

/// A hard ceiling on emitted circles, so a badly-conditioned arrangement
/// (overlapping circles make the group non-discrete, and the nesting stops
/// shrinking) ends instead of exhausting memory.
private let schottkyCircleLimit = 2_000_000

/// Walks the tree of reduced words, handing each image circle to `emit` along
/// with whether the branch stopped there.
///
/// Letters run `0 ..< 2n`: letter `i < n` is pairing `i`, letter `i + n` its
/// inverse, so `inverse(i) = (i + n) % 2n` and a word stays reduced by never
/// following the cancelling letter. Circle `i` is pairing `i`'s target and
/// circle `i + n` its source, which is exactly the labelling that makes
/// generator `i` carry circle `inverse(i)` onto circle `i`.
private func schottkyWalk(_ pairings: [SchottkyPairing],
                          minRadius: Double,
                          maxDepth: Int,
                          emit: (Circle, Bool) -> Void) {
    let n = pairings.count
    let letters = n * 2

    var circles: [Circle] = []
    var generators: [MobiusMap] = []
    circles.reserveCapacity(letters)
    generators.reserveCapacity(letters)
    for pairing in pairings { circles.append(pairing.to) }
    for pairing in pairings { circles.append(pairing.from) }
    for pairing in pairings {
        generators.append(MobiusMap.pairing(from: pairing.from,
                                            to: pairing.to,
                                            twist: pairing.twist))
    }
    for i in 0 ..< n { generators.append(generators[i].inverse) }

    var emitted = 0

    // The starting circles, the only ones no word produces.
    for circle in circles {
        emit(circle, false)
        emitted += 1
    }

    func walk(_ matrix: MobiusMap, _ last: Int, _ depth: Int) {
        let cancelling = (last + n) % letters
        for k in 0 ..< letters where k != cancelling {
            guard emitted < schottkyCircleLimit else { return }
            guard let image = matrix.image(of: circles[k]) else { continue }
            // Everything below this child nests inside `image`, so its radius
            // is the branch's own error bound: under `minRadius` there is
            // nothing left to draw.
            let isLeaf = image.radius < minRadius || depth >= maxDepth
            emit(image, isLeaf)
            emitted += 1
            if !isLeaf {
                walk((matrix * generators[k]).normalized, k, depth + 1)
            }
        }
    }

    for i in 0 ..< letters {
        walk(generators[i], i, 1)
    }
}

/// Every circle in the orbit of a Schottky group's pairing circles, down to
/// `minRadius`.
///
/// - Parameters:
///   - pairings: The circle pairings, one per generator (two of them is the
///     classic two-generator family). Discs should be disjoint: overlapping
///     ones make the group non-discrete and the lace turns to mud.
///   - minRadius: The size at which a branch stops, in canvas points. Half a
///     pixel is the natural floor; larger values return a sparser lace and
///     return it faster.
///   - maxDepth: A backstop on word length for arrangements that shrink slowly
///     (near-tangent circles do).
/// - Returns: The pairing circles followed by their images, parents before
///   children.
public func schottkyCircles(pairing pairings: [SchottkyPairing],
                            minRadius: Double = 0.5,
                            maxDepth: Int = 40) -> [Circle] {
    guard !pairings.isEmpty, minRadius > 0 else { return [] }
    guard pairings.allSatisfy({ $0.from.radius > 0 && $0.to.radius > 0 }) else { return [] }

    var result: [Circle] = []
    schottkyWalk(pairings, minRadius: minRadius, maxDepth: maxDepth) { circle, _ in
        result.append(circle)
    }
    return result
}

/// The limit set of a Schottky group, as a point cloud.
///
/// The walk keeps the circles it stopped at: each one is smaller than
/// `minRadius` and contains limit points, so its center sits within
/// `minRadius` of the limit set. Tightly separated circles give a Cantor dust,
/// near-tangent ones a dense curve.
///
/// Unlike the chaos game behind `inversionLimitSet`, this uses no randomness
/// at all, so the same arrangement always returns the same cloud.
public func schottkyLimitSet(pairing pairings: [SchottkyPairing],
                             minRadius: Double = 0.5,
                             maxDepth: Int = 40) -> [Vector2] {
    guard !pairings.isEmpty, minRadius > 0 else { return [] }
    guard pairings.allSatisfy({ $0.from.radius > 0 && $0.to.radius > 0 }) else { return [] }

    var result: [Vector2] = []
    schottkyWalk(pairings, minRadius: minRadius, maxDepth: maxDepth) { circle, isLeaf in
        if isLeaf { result.append(circle.center) }
    }
    return result
}

// MARK: - The necklace family

/// `pairs * 2` circles spaced evenly around a ring, opposite ones paired: the
/// symmetric family the classic figures are drawn from.
///
/// `tightness` runs 0 to 1 as a fraction of the kissing radius, so 1 is the
/// arrangement where neighbours just touch and anything above overlaps.
/// Loosen it and the limit set is a dust; tighten it and the dust fuses.
///
/// - Parameters:
///   - pairs: How many pairings, so how many generators. Two is the classic
///     two-generator family.
///   - bounds: The ring is centered here and sized to fit.
///   - tightness: Circle radius as a fraction of the kissing radius.
///   - twist: Applied to every pairing.
public func schottkyNecklace(pairs: Int,
                             in bounds: Rectangle,
                             tightness: Double = 0.9,
                             twist: Double = 0) -> [SchottkyPairing] {
    guard pairs >= 1 else { return [] }
    let count = pairs * 2

    // Place the ring so the widest circle still fits the bounds.
    let kissingRatio = sin(Double.pi / Double(count))
    let ringRadius = min(bounds.width, bounds.height) / 2 / (1 + kissingRatio)
    let radius = max(ringRadius * kissingRatio * tightness, 1e-9)
    let center = bounds.center

    var circles: [Circle] = []
    circles.reserveCapacity(count)
    for i in 0 ..< count {
        let angle = Double(i) / Double(count) * .tau
        circles.append(Circle(center: Vector2(center.x + cos(angle) * ringRadius,
                                              center.y + sin(angle) * ringRadius),
                              radius: radius))
    }

    return (0 ..< pairs).map {
        SchottkyPairing(from: circles[$0 + pairs], to: circles[$0], twist: twist)
    }
}

/// Four circles at `(±spread·r, ±r)` of radius `r`, each vertical pair paired
/// with the other: the two-generator family the classic figures come from.
///
/// Because a pair *touches*, its generator holds the tangency point fixed and
/// is parabolic, which is what fills the picture. A parabolic map barely
/// contracts near its fixed point, so the orbit keeps producing large circles
/// for many generations and they crowd into a fan at the two tangency points.
/// Pair circles across the ring instead (`schottkyNecklace`) and every
/// generator contracts hard, leaving a thin dust.
///
/// `spread` is the ratio of the pairs' separation to the circle radius, and it
/// is the family's main dial:
///
/// - At `1` all four circles are mutually tangent and the limit set closes up
///   into a round circle with four cusps.
/// - Above `1` the pairs draw apart, the top and bottom tangencies open into
///   gaps, and the limit set becomes a fractal curve.
/// - Below `1` the circles would overlap and the group stops being discrete, so
///   the value is clamped.
///
/// `lean` swings each pair *about its own tangency point*, the two pairs in
/// opposite senses so the arrangement keeps its mirror symmetry. Since a pair
/// stays tangent however far it swings, both generators stay parabolic, which
/// makes this the dial to animate: the picture stays dense all the way along
/// it, where `twist` thins out as soon as it leaves zero. Leaning opens the
/// round limit set into swept arcs gathering on the two cusps. It is clamped
/// short of a quarter turn, where the two pairs would collide.
///
/// `twist` turns each pairing off its tangency-preserving setting, winding each
/// generation against the last: the round limit set at `spread == 1` deforms
/// into a spiralling quasi-circle. Because it breaks the parabolic fixed point,
/// every generator starts contracting and the lace thins as it grows. It runs
/// in canvas orientation and repeats every `2π`.
///
/// The four circles are scaled to fill `bounds`.
public func schottkyCuspedPairs(in bounds: Rectangle,
                                spread: Double = 1,
                                lean: Double = 0,
                                twist: Double = 0) -> [SchottkyPairing] {
    let spread = max(spread, 1)
    let lean = min(max(lean, -1.4), 1.4)
    // The circles span 2r(spread + 1) across and 4r down; fit the wider one.
    let extent = min(bounds.width, bounds.height)
    let radius = extent / (2 * max(spread + 1, 2))
    let offset = spread * radius
    let center = bounds.center

    /// One tangent pair: both circles sit at `tangency ± radius · direction`,
    /// which keeps them touching at that point for any lean.
    func pair(_ dx: Double, _ angle: Double) -> SchottkyPairing {
        let tangency = Vector2(center.x + dx, center.y)
        let step = Vector2(cos(angle), sin(angle)) * radius
        return SchottkyPairing(from: Circle(center: tangency + step, radius: radius),
                               to: Circle(center: tangency - step, radius: radius),
                               twist: twist)
    }
    let up = Double.pi / 2
    return [pair(-offset, up + lean), pair(offset, up - lean)]
}

// MARK: - Presets

/// Arrangements worth knowing by name, each a landmark of the two-generator
/// family's parameter space.
public enum SchottkyPreset: CaseIterable, Sendable {
    /// All four circles mutually tangent: the limit set closes into a round
    /// circle pinched by four cusps, the family's most symmetric member.
    case kissing
    /// The pairs leaned over, gathering the lace into two cusps with big swept
    /// arcs crossing between them and gaps opening top and bottom.
    case leaning
    /// The pairs drawn apart, so the top and bottom tangencies open and the
    /// limit set breaks into fractal arcs between two cusps.
    case cusped
    /// A slight twist on a nearly-kissing arrangement, which winds the round
    /// limit set into a spiralling quasi-circle.
    case spiral
    /// Circles paired across the ring rather than in touching pairs: every
    /// generator contracts hard, and the limit set is a Cantor dust threaded
    /// through an open lace.
    case dust

    /// The pairings, laid out to fill `bounds`.
    public func pairings(in bounds: Rectangle) -> [SchottkyPairing] {
        switch self {
        case .kissing: schottkyCuspedPairs(in: bounds, spread: 1)
        case .leaning: schottkyCuspedPairs(in: bounds, spread: 1, lean: 0.6)
        case .cusped: schottkyCuspedPairs(in: bounds, spread: 1.12)
        case .spiral: schottkyCuspedPairs(in: bounds, spread: 1.02, twist: 0.15)
        case .dust: schottkyNecklace(pairs: 2, in: bounds, tightness: 0.85)
        }
    }
}

/// The circle orbit of a named `SchottkyPreset`, laid out to fill `bounds`.
public func schottkyCircles(_ preset: SchottkyPreset,
                            in bounds: Rectangle,
                            minRadius: Double = 0.5,
                            maxDepth: Int = 40) -> [Circle] {
    schottkyCircles(pairing: preset.pairings(in: bounds),
                    minRadius: minRadius, maxDepth: maxDepth)
}

/// The limit set of a named `SchottkyPreset`, laid out to fill `bounds`.
public func schottkyLimitSet(_ preset: SchottkyPreset,
                             in bounds: Rectangle,
                             minRadius: Double = 0.5,
                             maxDepth: Int = 40) -> [Vector2] {
    schottkyLimitSet(pairing: preset.pairings(in: bounds),
                     minRadius: minRadius, maxDepth: maxDepth)
}
