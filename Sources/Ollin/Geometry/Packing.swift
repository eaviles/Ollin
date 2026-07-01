import Foundation

/// Circle packing: fill a region with non-overlapping circles, the classic
/// generative-art motif. Two ways to produce a packing are built in, both pure
/// functions of their inputs (seed a `packCircles(in:count:)` run and it always
/// lays the circles down the same way):
///
/// - **Grow-to-touch** (`packCircles`): each circle grows until it touches a
///   neighbor or the bounds, so it ends up the largest it can be without
///   overlapping. `packCircles(in:count:…)` also scatters its own seed points and
///   fills the gaps between big circles with progressively smaller ones (the
///   dense, varied look); `packCircles(around:…)` grows a circle at each point
///   you hand it (blue-noise points make an even foam).
/// - **Front relaxation** (`relaxCircles`): start from circles that overlap and
///   push every overlapping pair apart until none do, holding their radii fixed.
///   The sibling of `Voronoi.relaxed()`, and the way to settle a set you sized
///   yourself.
///
/// The output is `[Circle]`, so it feeds straight into `drawCircles`, the shape
/// booleans, hatching, and SVG export.
///
/// ```swift
/// // Dense, self-seeding pack:
/// var rng = SplitMix64(seed: 7)
/// let packed = packCircles(in: bounds, count: 400, minRadius: 3, maxRadius: 90, using: &rng)
///
/// // Grow-to-touch over a blue-noise set (an even foam):
/// let sites = poissonDisk(in: bounds, radius: 40, using: &rng)
/// let foam = packCircles(around: sites, in: bounds, padding: 2)
/// ```

// MARK: - Grow-to-touch (self-seeding)

/// A dense circle packing of `bounds`: scatter up to `count` seed points and grow
/// a circle at each to the largest radius that clears every circle already placed
/// (and stays inside `bounds`), so big circles land first and smaller ones fill
/// the gaps between them. Draws its seed points from `rng`, so the same seed
/// always produces the same packing.
///
/// The `count` is a target, not a guarantee: packing gets harder as the region
/// fills, so a run stops once `count` circles are placed *or* it has thrown
/// `count * attemptsPerCircle` darts without room for more, whichever comes
/// first. A circle smaller than `minRadius` is never placed (the point is
/// discarded and another tried).
///
/// - Parameters:
///   - bounds: The rectangle to pack.
///   - count: The target number of circles.
///   - minRadius: The smallest circle to place; smaller candidates are dropped.
///   - maxRadius: A cap on how large a circle may grow (no cap by default).
///   - padding: A gap to leave between neighboring circles.
///   - attemptsPerCircle: Darts thrown per target circle before giving up (sets
///     the total dart budget, `count * attemptsPerCircle`).
///   - rng: The random source to draw seed points from; seed it for a
///     reproducible packing.
/// - Returns: The placed circles, largest-first in placement order.
public func packCircles<R: RandomNumberGenerator>(
    in bounds: Rectangle,
    count: Int,
    minRadius: Double,
    maxRadius: Double = .infinity,
    padding: Double = 0,
    attemptsPerCircle: Int = 30,
    using rng: inout R
) -> [Circle] {
    guard count > 0, bounds.width > 0, bounds.height > 0, minRadius > 0 else { return [] }

    var circles: [Circle] = []
    circles.reserveCapacity(count)
    let maxAttempts = count * Swift.max(attemptsPerCircle, 1)
    var attempts = 0

    while circles.count < count, attempts < maxAttempts {
        attempts += 1
        let p = Vector2(bounds.x + Double.random(in: 0 ..< 1, using: &rng) * bounds.width,
                        bounds.y + Double.random(in: 0 ..< 1, using: &rng) * bounds.height)

        // The largest circle at `p` reaches to the nearest wall and to the edge
        // of the nearest existing circle (minus the gap), whichever is closer.
        var r = Swift.min(wallGap(p, bounds), maxRadius)
        for c in circles {
            r = Swift.min(r, p.distance(to: c.center) - c.radius - padding)
            if r < minRadius { break }
        }
        if r >= minRadius {
            circles.append(Circle(center: p, radius: r))
        }
    }
    return circles
}

// MARK: - Grow-to-touch (from given points)

/// Grow a circle at each of `sites` until it touches its nearest neighbor (or the
/// bounds), so the circles just meet without overlapping. Because two circles
/// growing at the same rate meet exactly halfway, each radius is simply half the
/// distance to the nearest other point (less half the `padding`), capped by the
/// bounds and `maxRadius`. A pure function of the points, so it needs no random
/// source; feed it a blue-noise (`poissonDisk`) set for an even, gap-free foam.
///
/// - Parameters:
///   - sites: The circle centers.
///   - bounds: A rectangle each circle stays inside; pass `nil` to leave circles
///     unbounded (grown only against each other).
///   - minRadius: Circles that would come out smaller than this are dropped.
///   - maxRadius: A cap on how large a circle may grow (no cap by default).
///   - padding: A gap to leave between neighboring circles.
/// - Returns: One circle per surviving site, in the order of `sites`.
public func packCircles(
    around sites: [Vector2],
    in bounds: Rectangle? = nil,
    minRadius: Double = 0,
    maxRadius: Double = .infinity,
    padding: Double = 0
) -> [Circle] {
    guard sites.count > 0 else { return [] }

    var circles: [Circle] = []
    circles.reserveCapacity(sites.count)
    for (i, s) in sites.enumerated() {
        var nearest = Double.infinity
        for (j, t) in sites.enumerated() where j != i {
            nearest = Swift.min(nearest, s.distanceSquared(to: t))
        }
        // Half the distance to the nearest neighbor is where equal-rate growth
        // meets; subtract half the gap so the two circles stop `padding` apart.
        var r = nearest.isFinite ? (nearest.squareRoot() - padding) / 2 : maxRadius
        r = Swift.min(r, maxRadius)
        if let bounds { r = Swift.min(r, wallGap(s, bounds)) }
        if r >= minRadius, r > 0 {
            circles.append(Circle(center: s, radius: r))
        }
    }
    return circles
}

// MARK: - Front relaxation

/// Push overlapping circles apart until none overlap, holding each radius fixed.
/// Each iteration nudges every overlapping pair away from each other by half
/// their overlap, then (if `bounds` is given) slides any circle poking out of the
/// region back inside. A few iterations settle most sets; a heavily overlapping
/// one wants more. Deterministic, so it needs no random source, and the sibling
/// of `Voronoi.relaxed()` for circles you sized yourself.
///
/// - Parameters:
///   - circles: The (possibly overlapping) circles to separate.
///   - bounds: A rectangle to keep circles inside; pass `nil` to skip the wall
///     constraint.
///   - iterations: How many separation passes to run.
///   - padding: A gap to open up between neighboring circles.
/// - Returns: The circles with their centers moved apart; radii are unchanged.
public func relaxCircles(
    _ circles: [Circle],
    in bounds: Rectangle? = nil,
    iterations: Int = 20,
    padding: Double = 0
) -> [Circle] {
    guard circles.count > 1, iterations > 0 else { return circles }

    var centers = circles.map(\.center)
    let radii = circles.map(\.radius)
    let n = circles.count

    for _ in 0 ..< iterations {
        for i in 0 ..< n {
            for j in (i + 1) ..< n {
                let delta = centers[j] - centers[i]
                let minDist = radii[i] + radii[j] + padding
                let d = delta.length
                if d >= minDist { continue }
                // A coincident pair has no direction to split along; part them on
                // a fixed axis so the result stays reproducible.
                let dir = d > 1e-9 ? delta * (1 / d) : Vector2(1, 0)
                let push = (minDist - Swift.max(d, 0)) / 2
                centers[i] = centers[i] - dir * push
                centers[j] = centers[j] + dir * push
            }
        }
        if let bounds {
            for i in 0 ..< n {
                centers[i] = clampInside(centers[i], radius: radii[i], bounds: bounds)
            }
        }
    }
    return zip(centers, radii).map { Circle(center: $0, radius: $1) }
}

// MARK: - Helpers (file-private)

/// The radius of the largest circle centered at `p` that fits inside `bounds`,
/// i.e. the distance from `p` to the nearest wall (negative if `p` is outside).
private func wallGap(_ p: Vector2, _ bounds: Rectangle) -> Double {
    Swift.min(Swift.min(p.x - bounds.x, bounds.x + bounds.width - p.x),
              Swift.min(p.y - bounds.y, bounds.y + bounds.height - p.y))
}

/// A center clamped so a circle of `radius` stays wholly inside `bounds` (or
/// centered on the axis when the region is too small to hold it).
private func clampInside(_ c: Vector2, radius: Double, bounds: Rectangle) -> Vector2 {
    func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        lo <= hi ? Swift.min(Swift.max(v, lo), hi) : (lo + hi) / 2
    }
    return Vector2(clamp(c.x, bounds.x + radius, bounds.x + bounds.width - radius),
                   clamp(c.y, bounds.y + radius, bounds.y + bounds.height - radius))
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A dense circle packing of `bounds` (the whole canvas by default): big
    /// circles land first and smaller ones fill the gaps, each grown to touch its
    /// neighbors. Driven by the seeded `random`, so `seed(_:)` makes the packing
    /// reproducible.
    ///
    /// ```swift
    /// seed(7)
    /// let packed = packCircles(count: 400, minRadius: 3 * scale, maxRadius: 90 * scale)
    /// noStroke(); fill(.white)
    /// drawCircles(packed)
    /// ```
    func packCircles(in bounds: Rectangle? = nil,
                     count: Int,
                     minRadius: Double,
                     maxRadius: Double = .infinity,
                     padding: Double = 0,
                     attemptsPerCircle: Int = 30) -> [Circle] {
        Ollin.packCircles(in: bounds ?? canvasRectangle,
                          count: count,
                          minRadius: minRadius,
                          maxRadius: maxRadius,
                          padding: padding,
                          attemptsPerCircle: attemptsPerCircle,
                          using: &rng)
    }

    /// Grow a circle at each of `sites` until it just touches its nearest
    /// neighbor (or the bounds), holding no gaps. A blue-noise set makes an even
    /// foam; deterministic, so it reads straight off the points.
    ///
    /// ```swift
    /// seed(7)
    /// let sites = poissonDisk(radius: 40)
    /// drawCircles(packCircles(around: sites, padding: 2))
    /// ```
    func packCircles(around sites: [Vector2],
                     in bounds: Rectangle? = nil,
                     minRadius: Double = 0,
                     maxRadius: Double = .infinity,
                     padding: Double = 0) -> [Circle] {
        Ollin.packCircles(around: sites,
                          in: bounds ?? canvasRectangle,
                          minRadius: minRadius,
                          maxRadius: maxRadius,
                          padding: padding)
    }

    /// Push overlapping circles apart until none overlap, keeping them inside
    /// `bounds` (the canvas by default). Deterministic, the sibling of
    /// `lloyd(_:)` for circles you sized yourself.
    func relaxCircles(_ circles: [Circle],
                      in bounds: Rectangle? = nil,
                      iterations: Int = 20,
                      padding: Double = 0) -> [Circle] {
        Ollin.relaxCircles(circles,
                           in: bounds ?? canvasRectangle,
                           iterations: iterations,
                           padding: padding)
    }
}

// MARK: - Shape packing

/// Pack arbitrary shapes into `bounds`, growing each until it touches its
/// neighbors' *outlines* (not just their bounding circles), so smaller shapes
/// nestle into the concave gaps a star's notches or a triangle's edges leave.
/// Big shapes land first and progressively smaller ones fill the space between
/// them, each a random pick from `shapes`, rotated, and scaled to fit. Output is
/// `[Shape]`, feeding the fill, stroke, shape-boolean, hatching, and SVG paths.
///
/// This is [`ContinuousPacking`](x-source-tag://ContinuousPacking) run to
/// completion; hold one and `step()` it for the animated, fills-in-over-time
/// form.
///
/// - Parameters:
///   - shapes: The shapes to draw from (each placed shape is a random pick).
///   - bounds: The rectangle to pack.
///   - count: The target number of shapes (a run also stops once no room is left).
///   - minRadius: The smallest shape (by bounding-circle radius) to place.
///   - maxRadius: A cap on the bounding-circle radius (the bounds by default).
///   - padding: A gap left between neighboring shapes.
///   - rotation: The range a placed shape is randomly rotated within (radians;
///     pass `0 ... 0` to leave shapes upright).
///   - scale: How much of its bounding circle each shape fills (1 = touching).
///   - rng: The random source; seed it for a reproducible packing.
/// - Returns: The placed, transformed shapes, largest-first.
public func packShapes<R: RandomNumberGenerator>(
    _ shapes: [Shape],
    in bounds: Rectangle,
    count: Int,
    minRadius: Double,
    maxRadius: Double = .infinity,
    padding: Double = 0,
    rotation: ClosedRange<Double> = 0 ... Double.tau,
    scale: Double = 1,
    using rng: inout R
) -> [Shape] {
    guard !shapes.isEmpty, count > 0 else { return [] }
    let packer = ContinuousPacking(shapes: shapes, in: bounds, seed: rng.next(),
                                   minRadius: minRadius, maxRadius: maxRadius, padding: padding,
                                   rotation: rotation, scale: scale, attemptsPerStep: 20)
    var stalledSteps = 0
    while packer.count < count, stalledSteps < 80 {
        let before = packer.count
        packer.step()
        stalledSteps = packer.count == before ? stalledSteps + 1 : 0
    }
    return packer.shapes
}

/// Grow-to-touch shape packing from given points: place a shape at each of
/// `sites`, its bounding circle grown to half the distance to the nearest other
/// point. A blue-noise set makes an even scatter of non-overlapping shapes. The
/// circle placement is fixed by the points; `rng` drives only the shape choice
/// and rotation.
public func packShapes<R: RandomNumberGenerator>(
    _ shapes: [Shape],
    around sites: [Vector2],
    in bounds: Rectangle? = nil,
    minRadius: Double = 0,
    maxRadius: Double = .infinity,
    padding: Double = 0,
    rotation: ClosedRange<Double> = 0 ... Double.tau,
    scale: Double = 1,
    using rng: inout R
) -> [Shape] {
    guard !shapes.isEmpty else { return [] }
    let circles = packCircles(around: sites, in: bounds, minRadius: minRadius,
                              maxRadius: maxRadius, padding: padding)
    return circles.map { placeRandomShape(shapes, in: $0, rotation: rotation, scale: scale, using: &rng) }
}

// MARK: - Shape-packing helpers (file-private)

/// Pick a random shape and place it inside `circle`.
private func placeRandomShape<R: RandomNumberGenerator>(
    _ shapes: [Shape], in circle: Circle,
    rotation: ClosedRange<Double>, scale: Double, using rng: inout R
) -> Shape {
    let proto = shapes[Int.random(in: 0 ..< shapes.count, using: &rng)]
    let angle = rotation.lowerBound < rotation.upperBound
        ? Double.random(in: rotation, using: &rng)
        : rotation.lowerBound
    return placeShape(proto, in: circle, angle: angle, scale: scale)
}

// MARK: - Continuous packing (stateful)

/// A continuous (incremental) packer: instead of filling a region in one call,
/// it adds a few marks per `step()`, each grown to the largest that fits the gaps
/// left by the marks already placed. Held across frames and stepped in `draw()`,
/// it *animates* a packing filling in, and because big gaps fill first, each new
/// mark is smaller than the last, so the region densifies from a few large shapes
/// down to a scatter of tiny ones.
///
/// Pass a bag of `shapes` to pack shapes (each placed pick is rotated and scaled
/// to its circle, exactly like `packShapes`), or none to pack plain `circles`.
/// Placed marks never move, so pairing it with accumulation (`noClear()`) and
/// drawing only the newly added marks each frame keeps the per-frame cost flat no
/// matter how full the region gets.
///
/// ```swift
/// let packer = ContinuousPacking(shapes: bag, in: bounds, seed: 4,
///                                minRadius: 3, maxRadius: 130, padding: 4)
///
/// override func setup() { noClear() }            // accumulate
/// override func draw() {
///     let start = packer.count
///     packer.step()                              // add a few this frame
///     for i in start ..< packer.count {          // draw only the new ones
///         fill(.white); drawShape(packer.shapes[i])
///     }
/// }
/// ```
///
/// - Tag: ContinuousPacking
public final class ContinuousPacking {
    /// The bounding circles placed so far, largest-first.
    public private(set) var circles: [Circle] = []
    /// The placed shapes (parallel to `circles`); empty when no shape bag was given.
    public private(set) var shapes: [Shape] = []

    private let bag: [Shape]
    private let bounds: Rectangle
    /// The smallest mark to place; the packer stops finding room once every gap is
    /// smaller than this.
    public var minRadius: Double
    /// A cap on how large a mark may grow.
    public var maxRadius: Double
    /// A gap left between neighboring marks.
    public var padding: Double
    /// The range a placed shape is randomly rotated within (radians).
    public var rotation: ClosedRange<Double>
    /// How much of its bounding circle each shape fills.
    public var scale: Double
    /// How many placements are attempted per `step()`.
    public var attemptsPerStep: Int

    private var rng: SplitMix64
    private var grid: [PackingCell: [Int]] = [:]
    private let cell: Double

    /// A continuous packer over `bounds`, drawing shapes from `shapes` (or packing
    /// plain circles when it's empty).
    ///
    /// - Parameters:
    ///   - shapes: The shape bag to draw placements from (empty packs circles).
    ///   - bounds: The rectangle to fill.
    ///   - seed: The random seed; the same seed grows the same packing.
    ///   - minRadius: The smallest mark to place.
    ///   - maxRadius: A cap on the mark radius.
    ///   - padding: A gap left between marks.
    ///   - rotation: The random rotation range for shapes (radians).
    ///   - scale: How much of its circle each shape fills.
    ///   - attemptsPerStep: Placement attempts per `step()`.
    public init(shapes: [Shape] = [], in bounds: Rectangle, seed: UInt64 = 0,
                minRadius: Double, maxRadius: Double, padding: Double = 0,
                rotation: ClosedRange<Double> = 0 ... Double.tau, scale: Double = 1,
                attemptsPerStep: Int = 10) {
        self.bag = shapes
        self.bounds = bounds
        self.rng = SplitMix64(seed: seed)
        self.minRadius = minRadius
        self.maxRadius = maxRadius
        self.padding = padding
        self.rotation = rotation
        self.scale = scale
        self.attemptsPerStep = attemptsPerStep
        // The grid cell is the largest a mark can be, which an unbounded
        // `maxRadius` clamps to the region size (nothing grows past the bounds).
        self.cell = Swift.max(Swift.min(maxRadius, Swift.min(bounds.width, bounds.height)), 1e-6)
    }

    /// The number of marks placed so far.
    public var count: Int { circles.count }

    /// Attempt `attemptsPerStep` placements, keeping each that finds room.
    public func step() {
        guard bounds.width > 0, bounds.height > 0, minRadius > 0 else { return }
        for _ in 0 ..< Swift.max(attemptsPerStep, 1) {
            let p = Vector2(bounds.x + Double.random(in: 0 ..< 1, using: &rng) * bounds.width,
                            bounds.y + Double.random(in: 0 ..< 1, using: &rng) * bounds.height)
            if let r = fittedRadius(at: p) { place(at: p, radius: r) }
        }
    }

    /// The largest mark that fits at `p`, or `nil` if there's no room (or `p`
    /// falls inside a placed shape). With a shape bag the fit is against each
    /// shape's *outline* (so a new mark can grow into a star's notch or beside a
    /// triangle's edge, filling the space the bounding circle would waste); with
    /// no bag it's the plain circle distance.
    private func fittedRadius(at p: Vector2) -> Double? {
        var r = Swift.min(wallGap(p, bounds), maxRadius)
        if r < minRadius { return nil }

        // Only marks whose center is within `currentBest + maxRadius` can
        // constrain `p` (a shape's outline lies within its bounding radius of its
        // center), so scan that neighborhood of the grid.
        let gridMax = Swift.min(maxRadius, Swift.min(bounds.width, bounds.height))
        let reach = Int(((2 * gridMax + padding) / cell).rounded(.up)) + 1
        let col = Int(floor((p.x - bounds.x) / cell)), row = Int(floor((p.y - bounds.y) / cell))
        let geometryAware = !bag.isEmpty
        for cc in (col - reach) ... (col + reach) {
            for rr in (row - reach) ... (row + reach) {
                guard let bucket = grid[PackingCell(cc, rr)] else { continue }
                for j in bucket {
                    let center = circles[j].center, radius = circles[j].radius
                    if geometryAware {
                        let dc = p.distance(to: center)
                        if dc - radius >= r { continue }                    // outline too far to constrain
                        if dc < radius, shapeContains(shapes[j], p) { return nil }   // inside a shape
                        r = Swift.min(r, distanceToOutline(shapes[j], p) - padding)
                    } else {
                        r = Swift.min(r, p.distance(to: center) - radius - padding)
                    }
                    if r < minRadius { return nil }
                }
            }
        }
        return r >= minRadius ? r : nil
    }

    /// Run `steps` steps.
    public func step(_ steps: Int) {
        for _ in 0 ..< Swift.max(steps, 0) { step() }
    }

    private func place(at center: Vector2, radius: Double) {
        let circle = Circle(center: center, radius: radius)
        let index = circles.count
        circles.append(circle)
        let col = Int(floor((center.x - bounds.x) / cell)), row = Int(floor((center.y - bounds.y) / cell))
        grid[PackingCell(col, row), default: []].append(index)
        if !bag.isEmpty {
            shapes.append(placeRandomShape(bag, in: circle, rotation: rotation, scale: scale, using: &rng))
        }
    }
}

/// A uniform-grid cell key for the continuous packer's neighbor search.
private struct PackingCell: Hashable {
    let column: Int, row: Int
    init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
}

/// Whether `p` is inside `shape` (even-odd ray cast over all its contours).
private func shapeContains(_ shape: Shape, _ p: Vector2) -> Bool {
    var inside = false
    for contour in shape.contours {
        let pts = contour.points
        guard pts.count >= 3 else { continue }
        var j = pts.count - 1
        for i in pts.indices {
            let a = pts[i], b = pts[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
    }
    return inside
}

/// The distance from `p` to the nearest edge of `shape` (its outline).
private func distanceToOutline(_ shape: Shape, _ p: Vector2) -> Double {
    var best = Double.infinity
    for contour in shape.contours {
        let pts = contour.points
        guard pts.count >= 2 else { continue }
        for i in pts.indices {
            best = Swift.min(best, pointSegmentDistance(p, pts[i], pts[(i + 1) % pts.count]))
        }
    }
    return best
}

/// The distance from `p` to the segment `a`–`b`.
private func pointSegmentDistance(_ p: Vector2, _ a: Vector2, _ b: Vector2) -> Double {
    let ab = b - a
    let lenSq = ab.lengthSquared
    guard lenSq > 1e-12 else { return p.distance(to: a) }
    let t = Swift.min(Swift.max((p - a).dot(ab) / lenSq, 0), 1)
    return p.distance(to: Vector2(a.x + ab.x * t, a.y + ab.y * t))
}

/// The bounding circle of a shape: its bounding-box center and the distance from
/// that center to its farthest point.
private func shapeBoundingCircle(_ shape: Shape) -> (center: Vector2, radius: Double) {
    let points = shape.contours.flatMap(\.points)
    guard let first = points.first else { return (.zero, 0) }
    var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
    for p in points {
        minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
        minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
    }
    let center = Vector2((minX + maxX) / 2, (minY + maxY) / 2)
    var r2 = 0.0
    for p in points { r2 = Swift.max(r2, p.distanceSquared(to: center)) }
    return (center, r2.squareRoot())
}

/// Place `shape` inside `circle`: normalized to `scale × circle.radius`, rotated
/// by `angle`, and centered on the circle. Rotation is bounding-circle-invariant,
/// so the placed shape always fits the packed circle.
private func placeShape(_ shape: Shape, in circle: Circle, angle: Double, scale: Double) -> Shape {
    let (center, radius) = shapeBoundingCircle(shape)
    guard radius > 0 else { return shape }
    let factor = scale * circle.radius / radius
    let cosT = cos(angle), sinT = sin(angle)
    return shape.mapPoints { p in
        let dx = (p.x - center.x) * factor, dy = (p.y - center.y) * factor
        return Vector2(circle.center.x + dx * cosT - dy * sinT,
                       circle.center.y + dx * sinT + dy * cosT)
    }
}

// MARK: - Shape-packing sugar

public extension Sketch {
    /// Pack shapes into `bounds` (the canvas by default) by packing their
    /// bounding circles: big shapes land first, smaller ones fill the gaps, each
    /// a random pick from `shapes`, rotated and scaled to its packed circle.
    /// Driven by the seeded `random`, so `seed(_:)` makes the packing
    /// reproducible.
    ///
    /// ```swift
    /// seed(4)
    /// let bag = [triangle, square, pentagon, star]
    /// for shape in packShapes(bag, count: 400, minRadius: 8, maxRadius: 120, padding: 4) {
    ///     fill(.white); drawShape(shape)
    /// }
    /// ```
    func packShapes(_ shapes: [Shape],
                    in bounds: Rectangle? = nil,
                    count: Int,
                    minRadius: Double,
                    maxRadius: Double = .infinity,
                    padding: Double = 0,
                    rotation: ClosedRange<Double> = 0 ... Double.tau,
                    scale: Double = 1) -> [Shape] {
        Ollin.packShapes(shapes, in: bounds ?? canvasRectangle, count: count,
                         minRadius: minRadius, maxRadius: maxRadius, padding: padding,
                         rotation: rotation, scale: scale, using: &rng)
    }

    /// Place a shape at each of `sites`, grown to touch its nearest neighbor. A
    /// blue-noise set (`poissonDisk`) makes an even scatter of non-overlapping
    /// shapes.
    func packShapes(_ shapes: [Shape],
                    around sites: [Vector2],
                    in bounds: Rectangle? = nil,
                    minRadius: Double = 0,
                    maxRadius: Double = .infinity,
                    padding: Double = 0,
                    rotation: ClosedRange<Double> = 0 ... Double.tau,
                    scale: Double = 1) -> [Shape] {
        Ollin.packShapes(shapes, around: sites, in: bounds ?? canvasRectangle,
                         minRadius: minRadius, maxRadius: maxRadius, padding: padding,
                         rotation: rotation, scale: scale, using: &rng)
    }
}
