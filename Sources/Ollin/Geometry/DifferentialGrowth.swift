import Foundation

/// Differential growth: a line of connected nodes that grows and folds into
/// organic, brain-coral structure. Each step every node is nudged by three
/// forces, and long edges split into new nodes, so the line lengthens and buckles
/// the way a leaf margin, a coral, or a convoluted cortex does.
///
/// - **Attraction** pulls each node toward its two path-neighbors, so the line
///   stays connected and segments do not stretch without bound.
/// - **Alignment** pulls each node toward the midpoint of its neighbors, smoothing
///   the curve.
/// - **Repulsion** pushes each node away from every *nearby* node (neighbor or
///   not, broad-phased through a spatial hash), so the line refuses to cross
///   itself and folds back instead.
///
/// When an edge grows longer than `maxSegmentLength` a node is inserted at its
/// midpoint, which is what lets the boundary lengthen as it expands. A little
/// `jitter` (and the optional `growthRate`) breaks the symmetry so a plain ring
/// buckles rather than just inflating.
///
/// Unlike the one-shot generators (packing, L-systems), this is a *stateful*
/// stepper you hold and advance each frame, and the product is geometry: `nodes`
/// (or `contour`) is the evolving line, which feeds stroking, filling, the shape
/// booleans, hatching, and SVG export. Seeded, so the same seed grows the same
/// form.
///
/// ```swift
/// // Held across frames, seeded once:
/// let growth = DifferentialGrowth.ring(center: Vector2(540, 540), radius: 80,
///                                      count: 40, seed: 7, maxNodes: 4000)
///
/// // In draw():
/// growth.step(3)                          // a few sub-steps per frame
/// noFill(); stroke(.white); strokeWeight(2)
/// drawPolyline(growth.nodes, closed: true)
/// ```
public final class DifferentialGrowth {
    /// The current node positions, in path order.
    public private(set) var nodes: [Vector2]
    /// Whether the path is a closed loop (its last node joins the first).
    public let closed: Bool

    /// An edge longer than this splits, inserting a node at its midpoint.
    public var maxSegmentLength: Double
    /// A node repels every other node within this radius.
    public var repulsionRadius: Double
    /// How strongly a node is pulled toward each path-neighbor.
    public var attraction: Double
    /// How strongly a node is pushed from nearby nodes.
    public var repulsion: Double
    /// How strongly a node is pulled toward its neighbors' midpoint (smoothing).
    public var alignment: Double
    /// A small random nudge per step; breaks symmetry so the line buckles.
    public var jitter: Double
    /// Extra nodes injected at random edges per step, to drive asymmetric growth
    /// (0 leaves growth to edge-splitting alone).
    public var growthRate: Double
    /// A ceiling on the node count; growth halts and the line settles once hit.
    public var maxNodes: Int
    /// An optional rectangle the nodes are kept inside.
    public var bounds: Rectangle?
    /// For an open path, whether the two endpoints are pinned in place.
    public var fixedEnds: Bool

    private var rng: SplitMix64

    /// A differential-growth stepper seeded with an initial line of `nodes`.
    ///
    /// - Parameters:
    ///   - nodes: The starting path (at least two points).
    ///   - closed: Whether it is a closed loop (the default) or an open line.
    ///   - seed: The random seed; the same seed grows the same form.
    ///   - maxSegmentLength: The edge length above which a node is inserted.
    ///   - repulsionRadius: The radius within which nodes push apart.
    ///   - attraction: Pull toward path-neighbors.
    ///   - repulsion: Push from nearby nodes.
    ///   - alignment: Pull toward the neighbors' midpoint (smoothing).
    ///   - jitter: A small random nudge per step.
    ///   - growthRate: Extra random node injections per step.
    ///   - maxNodes: The node-count ceiling.
    ///   - bounds: An optional rectangle to keep nodes inside.
    ///   - fixedEnds: For an open path, whether to pin the endpoints.
    public init(nodes: [Vector2],
                closed: Bool = true,
                seed: UInt64 = 0,
                maxSegmentLength: Double = 9,
                repulsionRadius: Double = 18,
                attraction: Double = 0.2,
                repulsion: Double = 0.5,
                alignment: Double = 0.25,
                jitter: Double = 0.35,
                growthRate: Double = 0,
                maxNodes: Int = 6000,
                bounds: Rectangle? = nil,
                fixedEnds: Bool = false) {
        self.nodes = nodes
        self.closed = closed
        self.rng = SplitMix64(seed: seed)
        self.maxSegmentLength = maxSegmentLength
        self.repulsionRadius = repulsionRadius
        self.attraction = attraction
        self.repulsion = repulsion
        self.alignment = alignment
        self.jitter = jitter
        self.growthRate = growthRate
        self.maxNodes = maxNodes
        self.bounds = bounds
        self.fixedEnds = fixedEnds
    }

    /// The number of nodes currently in the line.
    public var count: Int { nodes.count }

    /// The current line as a `Contour` (closed or open to match `closed`).
    public var contour: Contour { Contour(nodes, closed: closed) }

    /// Advance the growth by one step: apply the three forces to every node, keep
    /// nodes inside `bounds`, then split long edges (and inject growth).
    public func step() {
        let n = nodes.count
        guard n >= 2 else { return }

        let cell = Swift.max(repulsionRadius, 1e-6)
        let index = SpatialIndex(nodes, cellSize: cell)

        var delta = [Vector2](repeating: .zero, count: n)
        for i in 0 ..< n {
            let p = nodes[i]
            let hasPrev = closed || i > 0
            let hasNext = closed || i < n - 1
            var force = Vector2.zero

            if hasPrev {
                let prev = nodes[(i - 1 + n) % n]
                force = force + (prev - p) * attraction
                if hasNext {
                    let next = nodes[(i + 1) % n]
                    force = force + (next - p) * attraction
                    let mid = (prev + next) * 0.5
                    force = force + (mid - p) * alignment
                }
            } else if hasNext {
                force = force + (nodes[(i + 1) % n] - p) * attraction
            }

            // Repulsion from the nearby nodes the index hands back.
            index.forNeighbors(of: i, within: cell) { j, dist2 in
                guard dist2 < repulsionRadius * repulsionRadius, dist2 > 1e-12 else { return }
                let diff = p - nodes[j]
                let dist = dist2.squareRoot()
                let falloff = (repulsionRadius - dist) / repulsionRadius
                force = force + diff * (1 / dist) * (falloff * repulsion)
            }

            if jitter > 0 {
                let angle = Double.random(in: 0 ..< (2 * .pi), using: &rng)
                let mag = jitter * Double.random(in: 0 ..< 1, using: &rng)
                force = force + Vector2(cos(angle), sin(angle)) * mag
            }
            delta[i] = force
        }

        for i in 0 ..< n {
            if fixedEnds, !closed, i == 0 || i == n - 1 { continue }
            nodes[i] = nodes[i] + delta[i]
        }
        if let bounds { for i in nodes.indices { nodes[i] = clampInside(nodes[i], bounds) } }

        splitLongEdges()
        if growthRate > 0 { injectRandom() }
    }

    /// Advance the growth by `steps` steps.
    public func step(_ steps: Int) {
        for _ in 0 ..< Swift.max(steps, 0) { step() }
    }

    // MARK: - Node management

    /// Insert a node at the midpoint of every edge longer than `maxSegmentLength`.
    private func splitLongEdges() {
        guard nodes.count < maxNodes else { return }
        let n = nodes.count
        let edgeCount = closed ? n : n - 1
        var result: [Vector2] = []
        result.reserveCapacity(n)
        for i in 0 ..< n {
            result.append(nodes[i])
            if i < edgeCount, result.count < maxNodes {
                let a = nodes[i], b = nodes[(i + 1) % n]
                if a.distance(to: b) > maxSegmentLength {
                    result.append((a + b) * 0.5)
                }
            }
        }
        nodes = result
    }

    /// Inject `growthRate` nodes (fractional part probabilistically) at random
    /// edges, to drive asymmetric growth beyond plain edge-splitting.
    private func injectRandom() {
        let whole = Int(growthRate.rounded(.down))
        let extra = whole + (Double.random(in: 0 ..< 1, using: &rng) < growthRate - Double(whole) ? 1 : 0)
        for _ in 0 ..< extra {
            guard nodes.count < maxNodes, nodes.count >= 2 else { break }
            let edgeCount = closed ? nodes.count : nodes.count - 1
            let i = Int.random(in: 0 ..< Swift.max(edgeCount, 1), using: &rng)
            let a = nodes[i], b = nodes[(i + 1) % nodes.count]
            nodes.insert((a + b) * 0.5, at: i + 1)
        }
    }

    private func clampInside(_ p: Vector2, _ b: Rectangle) -> Vector2 {
        Vector2(Swift.min(Swift.max(p.x, b.x), b.x + b.width),
                Swift.min(Swift.max(p.y, b.y), b.y + b.height))
    }
}

// MARK: - Seed factories

public extension DifferentialGrowth {
    /// A stepper seeded with a small jittered ring, the classic starting shape:
    /// a circle of `count` nodes that buckles into folds as it grows.
    static func ring(center: Vector2,
                     radius: Double,
                     count: Int = 24,
                     seed: UInt64 = 0,
                     maxSegmentLength: Double = 9,
                     repulsionRadius: Double = 18,
                     attraction: Double = 0.2,
                     repulsion: Double = 0.5,
                     alignment: Double = 0.25,
                     jitter: Double = 0.35,
                     growthRate: Double = 0,
                     maxNodes: Int = 6000,
                     bounds: Rectangle? = nil) -> DifferentialGrowth {
        let nodes = (0 ..< Swift.max(count, 3)).map { i -> Vector2 in
            let a = Double(i) / Double(Swift.max(count, 3)) * 2 * .pi
            return Vector2(center.x + cos(a) * radius, center.y + sin(a) * radius)
        }
        return DifferentialGrowth(nodes: nodes, closed: true, seed: seed,
                                  maxSegmentLength: maxSegmentLength, repulsionRadius: repulsionRadius,
                                  attraction: attraction, repulsion: repulsion, alignment: alignment,
                                  jitter: jitter, growthRate: growthRate, maxNodes: maxNodes, bounds: bounds)
    }

    /// A stepper seeded with a straight open line from `start` to `end`, its
    /// endpoints pinned, which grows into a meandering folded ribbon between them.
    static func line(from start: Vector2,
                     to end: Vector2,
                     count: Int = 8,
                     seed: UInt64 = 0,
                     maxSegmentLength: Double = 9,
                     repulsionRadius: Double = 18,
                     attraction: Double = 0.2,
                     repulsion: Double = 0.5,
                     alignment: Double = 0.25,
                     jitter: Double = 0.35,
                     growthRate: Double = 0,
                     maxNodes: Int = 6000,
                     bounds: Rectangle? = nil) -> DifferentialGrowth {
        let nodes = (0 ..< Swift.max(count, 2)).map { i -> Vector2 in
            let t = Double(i) / Double(Swift.max(count, 2) - 1)
            return Vector2(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t)
        }
        let growth = DifferentialGrowth(nodes: nodes, closed: false, seed: seed,
                                        maxSegmentLength: maxSegmentLength, repulsionRadius: repulsionRadius,
                                        attraction: attraction, repulsion: repulsion, alignment: alignment,
                                        jitter: jitter, growthRate: growthRate, maxNodes: maxNodes, bounds: bounds)
        growth.fixedEnds = true
        return growth
    }
}
