import Foundation

/// Crackle as line work a plotter can draw: the veins of cracked wax, each a
/// wandering walk across a cell that stops at the cell's edge or where it
/// meets another vein, forking once near its middle, and denser along the
/// creases where the wax was folded.
///
/// A vein starts inside the cell and walks both ways from its root, or
/// starts on the cell's rim and walks in. Its heading wanders by a slow
/// noise (`wobble`) with a little jitter at every step, so it reads as a
/// crack rather than a curve. It ends on the rim, bisected to the edge so a
/// plotter reaches it, or on the first vein it meets, which it touches and
/// never crosses. When
/// it is done it may fork (`forkChance`): a child vein sets out from a point
/// between a third and two thirds along it, fifty to eighty degrees off, and
/// may fork once more itself (`maxOrder`). Every crease in `creases` seeds
/// extra veins along itself, so the crackle crowds where the sketch says the
/// wax creased. Every vein is a point list; the same seed grows the same
/// crackle.
///
/// ```swift
/// let wax = Shape(Circle(center: center, radius: 400).contour.points)
/// let veins = Crackle.grow(in: wax, spacing: 36, creases: [[a, b], [c, d]], seed: 5)
/// stroke(Color(hex: 0x1F2B5B)); strokeWeight(1.4); noFill()
/// for line in veins.lines { drawPolyline(line) }
/// ```
public struct Crackle: Equatable, Sendable {

    /// One vein of the crackle.
    public struct Vein: Equatable, Sendable {
        /// The points along the vein, root first (a vein that walked both
        /// ways has its root in the middle).
        public let points: [Vector2]
        /// 0 for a vein seeded in the cell or on its rim, 1 for a fork off
        /// one, 2 for a fork off that.
        public let order: Int
        /// The index of the vein this one forked from, or nil.
        public let parent: Int?

        public init(points: [Vector2], order: Int = 0, parent: Int? = nil) {
            self.points = points
            self.order = max(order, 0)
            self.parent = parent
        }

        /// The vein's length along its points.
        public var length: Double {
            guard points.count > 1 else { return 0 }
            var sum = 0.0
            for i in 1 ..< points.count { sum += (points[i] - points[i - 1]).length }
            return sum
        }
    }

    /// The veins, in the order they grew: a fork always follows its parent.
    public let veins: [Vein]
    /// The cell the veins cross.
    public let cell: Shape

    public init(veins: [Vein], cell: Shape) {
        self.veins = veins
        self.cell = cell
    }

    /// Every vein's points, for a loop that only strokes.
    public var lines: [[Vector2]] { veins.map(\.points) }

    /// The deepest fork: a vein of this order never forks again.
    public static let maxOrder = 2

    // MARK: - Growing

    /// Crackle over a rectangle, see `grow(in:spacing:creases:forkChance:wobble:seed:)`.
    public static func grow(in region: Rectangle, spacing: Double = 40, creases: [[Vector2]] = [],
                            forkChance: Double = 0.5, wobble: Double = 0.3, seed: Int = 0) -> Crackle {
        grow(in: Shape(contours: [region.contour]), spacing: spacing, creases: creases, forkChance: forkChance,
             wobble: wobble, seed: seed)
    }

    /// Crackle grown over a cell. About one vein is seeded for every two
    /// `spacing` squares of the cell's area, a third of them on the rim
    /// walking in and the rest inside walking both ways, plus one every two
    /// fifths of a spacing along each crease, headed along it; the seeds are shuffled by
    /// the seed. A vein stops at the rim, where it meets another vein, or
    /// after it has crossed the cell. `forkChance` is the chance a finished
    /// vein forks, lower by two fifths for each order; `wobble` is how far
    /// the heading wanders, in radians, around its course.
    ///
    /// - Parameters:
    ///   - cell: the region the veins cross; every point of every vein lies
    ///     inside it.
    ///   - spacing: the typical distance between veins.
    ///   - creases: polylines along which the veins crowd.
    ///   - forkChance: the chance in `0...1` that a vein forks.
    ///   - wobble: how far the heading wanders, in radians.
    ///   - seed: the whole crackle repeats from it.
    public static func grow(in cell: Shape, spacing: Double = 40, creases: [[Vector2]] = [],
                            forkChance: Double = 0.5, wobble: Double = 0.3, seed: Int = 0) -> Crackle {
        guard let bounds = cell.bounds, bounds.width > 0, bounds.height > 0 else { return Crackle(veins: [], cell: cell) }
        let area = cell.area
        guard area > 0 else { return Crackle(veins: [], cell: cell) }
        let spacing = max(spacing, 2)
        let forkChance = min(max(forkChance, 0), 1)
        let wobble = max(wobble, 0)
        let step = max(1.5, spacing * 0.12)
        let maxSteps = Int((bounds.width + bounds.height) / step) + 8
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let fields = NoiseFields(seed: seed)
        var index = SpatialIndex(bounds: bounds, cellSize: max(step * 2, 1))
        var committed: [Vector2] = []
        var before: [Int] = []       // the committed index of each point's predecessor on its vein, or -1
        var after: [Int] = []        // and of its successor
        var owner: [Int] = []        // the vein each committed point belongs to

        /// Where the segment `a` to `b` first crosses a committed segment,
        /// as the crossing point, or nil.
        func firstCrossing(_ a: Vector2, _ b: Vector2, ignoring vein: Int?) -> Vector2? {
            var best: (t: Double, point: Vector2)?
            let r = b - a
            index.forEachNeighbor(of: b, within: step * 2.2) { k, _ in
                if let vein, owner[k] == vein { return }
                for other in [before[k], after[k]] where other >= 0 {
                    let c = committed[k], d = committed[other]
                    let s = d - c
                    let denominator = r.cross(s)
                    guard abs(denominator) > 1e-12 else { continue }
                    let t = (c - a).cross(s) / denominator
                    let u = (c - a).cross(r) / denominator
                    guard t > 1e-9, t < 1, u >= 0, u <= 1 else { continue }
                    if best == nil || t < best!.t { best = (t, a + r * t) }
                }
            }
            return best?.point
        }

        struct Seed {
            var root: Vector2
            var heading: Double
            var bothWays: Bool
            var order: Int
            var parent: Int?
        }
        var queue: [Seed] = []

        // The seeds: a third on the rim walking in, the rest inside walking
        // both ways, then one every half spacing along each crease.
        let count = max(1, Int((area / (2 * spacing * spacing)).rounded()))
        let rimCount = count / 3
        let rims = cell.contours.map { $0.resampled(spacing: step) }.filter { $0.points.count >= 3 }
        for _ in 0 ..< rimCount where !rims.isEmpty {
            let rim = rims[Int.random(in: 0 ..< rims.count, using: &rng)]
            let n = rim.points.count
            let k = Int.random(in: 0 ..< n, using: &rng)
            let tangent = rim.points[(k + 1) % n] - rim.points[(k + n - 1) % n]
            guard tangent.lengthSquared > 1e-12 else { continue }
            var inward = tangent.normalized.perpendicular
            if !cell.contains(rim.points[k] + inward * step * 2) { inward = -inward }
            let root = rim.points[k] + inward * 0.5
            guard cell.contains(root) else { continue }
            queue.append(Seed(root: root, heading: inward.angle + Double.random(in: -0.5 ... 0.5, using: &rng),
                              bothWays: false, order: 0, parent: nil))
        }
        for _ in rimCount ..< count {
            for _ in 0 ..< 50 {
                let p = Vector2(Double.random(in: bounds.x ... bounds.x + bounds.width, using: &rng),
                                Double.random(in: bounds.y ... bounds.y + bounds.height, using: &rng))
                if cell.contains(p) {
                    queue.append(Seed(root: p, heading: Double.random(in: 0 ..< .tau, using: &rng),
                                      bothWays: true, order: 0, parent: nil))
                    break
                }
            }
        }
        for crease in creases where crease.count >= 2 {
            for i in 1 ..< crease.count {
                let a = crease[i - 1], b = crease[i]
                let segment = b - a
                let length = segment.length
                guard length > 1e-9 else { continue }
                let along = segment / length
                var d = spacing * 0.2
                while d < length {
                    let root = a + along * d + along.perpendicular * (Double.random(in: -0.3 ... 0.3, using: &rng) * spacing)
                    d += spacing * 0.4
                    guard cell.contains(root) else { continue }
                    var heading = along.angle + Double.random(in: -0.3 ... 0.3, using: &rng)
                    if Bool.random(using: &rng) { heading += .pi }
                    queue.append(Seed(root: root, heading: heading, bothWays: true, order: 0, parent: nil))
                }
            }
        }
        if queue.count > 1 {
            for i in stride(from: queue.count - 1, to: 0, by: -1) {
                let j = Int.random(in: 0 ... i, using: &rng)
                queue.swapAt(i, j)
            }
        }

        /// One run from `root` along `heading`, ending inside the cell: on
        /// the rim (bisected to it), on the first committed vein it meets
        /// (which it touches), or after crossing the cell.
        func run(from root: Vector2, heading: Double, parent: Int?, rng: inout SplitMix64) -> [Vector2] {
            var points = [root]
            var p = root
            let phase = Double.random(in: 0 ..< 1000, using: &rng)
            for i in 0 ..< maxSteps {
                let s = Double(i) * step
                let turn = wobble * 1.3 * fields.signedNoise(s / (spacing * 0.9) + phase)
                    + 0.12 * Double.random(in: -1 ... 1, using: &rng)
                let next = p + Vector2(angle: heading + turn, length: step)
                if !cell.contains(next) {
                    var inside = p, outside = next
                    for _ in 0 ..< 8 {
                        let mid = (inside + outside) / 2
                        if cell.contains(mid) { inside = mid } else { outside = mid }
                    }
                    if (inside - p).length > step * 0.2 { points.append(inside) }
                    break
                }
                // The first steps of a fork leave its parent, and nothing
                // else is near; after them a vein ends where its next
                // segment would cross another, on the crossing itself, or
                // where it comes within a step of one, touching it.
                let leaving = i < 4 ? parent : nil
                if let crossing = firstCrossing(p, next, ignoring: leaving) {
                    points.append(crossing)
                    break
                }
                if let met = index.anyNeighbor(of: next, within: step * 0.8), leaving == nil || owner[met] != leaving {
                    let touch = committed[met]
                    points.append(firstCrossing(p, touch, ignoring: leaving) ?? touch)
                    break
                }
                points.append(next)
                p = next
            }
            return points
        }

        var veins: [Vein] = []
        var head = 0
        while head < queue.count {
            let seed = queue[head]
            head += 1
            if seed.parent == nil, index.hasNeighbor(of: seed.root, within: step * 2) { continue }
            var points: [Vector2]
            if seed.bothWays {
                let forward = run(from: seed.root, heading: seed.heading, parent: seed.parent, rng: &rng)
                let backward = run(from: seed.root, heading: seed.heading + .pi, parent: seed.parent, rng: &rng)
                points = Array(backward.dropFirst().reversed()) + forward
            } else {
                points = run(from: seed.root, heading: seed.heading, parent: seed.parent, rng: &rng)
            }
            guard points.count >= 3 else { continue }
            let me = veins.count
            let first = committed.count
            for (j, p) in points.enumerated() {
                index.insert(p)
                committed.append(p)
                before.append(j == 0 ? -1 : first + j - 1)
                after.append(j == points.count - 1 ? -1 : first + j + 1)
                owner.append(me)
            }
            veins.append(Vein(points: points, order: seed.order, parent: seed.parent))

            let chance = forkChance * pow(0.6, Double(seed.order))
            if seed.order < maxOrder, points.count >= 6, Double.random(in: 0 ..< 1, using: &rng) < chance {
                let station = Int(Double(points.count - 1) * Double.random(in: 0.35 ... 0.65, using: &rng))
                let local = (points[min(station + 1, points.count - 1)] - points[max(station - 1, 0)]).angle
                let side: Double = Bool.random(using: &rng) ? 1 : -1
                let heading = local + side * Double.random(in: 0.9 ... 1.4, using: &rng)
                queue.append(Seed(root: points[station], heading: heading, bothWays: false,
                                  order: seed.order + 1, parent: me))
            }
        }
        return Crackle(veins: veins, cell: cell)
    }
}
