import Foundation

/// A graph that lays itself out: every node pushes every other node apart,
/// every edge pulls its two ends together, and out of that tug-of-war the
/// graph untangles into an even, readable web with no coordinates ever
/// given. Hold one, `step()` it each frame to watch it settle live (or
/// `settle()` it once in `setup()`), and draw the `positions` and `edges`
/// however you like, or call `drawGraph` for the plain rendering.
///
/// ```swift
/// let ring = (0 ..< 24).map { ($0, ($0 + 1) % 24) }
/// let layout = ForceLayout(count: 24, edges: ring, in: bounds, seed: 7)
///
/// override func draw() {
///     layout.step()
///     background(.white)
///     stroke(.black); fill(.black)
///     drawGraph(layout)
/// }
/// ```
///
/// Nodes start at seeded random positions and move a little less each step:
/// the `temperature` caps how far a node may travel per step and cools
/// linearly to zero over `coolingSteps`, so the layout swings boldly at
/// first, refines gently, and then freezes (`isSettled`). Mutating the graph
/// (`addNode`, `connect`) or dragging a node calls for a `reheat(_:)` so the
/// layout can absorb the change. Everything is deterministic: seeded
/// placement and fixed iteration orders, so a run replays exactly.
///
/// Implemented from the published technique (Fruchterman and Reingold,
/// *Graph Drawing by Force-Directed Placement*, Software: Practice and
/// Experience 21, 1991), not ported: repulsion `k²/d` between all node
/// pairs, attraction `d²/k` along edges, displacement capped by a cooling
/// temperature, positions clamped to the frame.
public final class ForceLayout {

    /// One edge: the indices of the two nodes it joins, and a `weight`
    /// multiplying its pull (1 is a normal edge; heavier edges draw their
    /// ends closer).
    public struct Edge: Sendable {
        /// The index of one end.
        public var a: Int
        /// The index of the other end.
        public var b: Int
        /// How strongly this edge pulls, as a multiplier on the attraction.
        public var weight: Double

        public init(_ a: Int, _ b: Int, weight: Double = 1) {
            self.a = a
            self.b = b
            self.weight = weight
        }
    }

    /// The node positions, in node order. Read them to draw; write one to
    /// drag a node (pair with `pinned` and a `reheat` so the rest of the
    /// graph reflows around it).
    public var positions: [Vector2]

    /// The edges. Mutate freely between steps; `connect` is the sugar that
    /// appends one.
    public var edges: [Edge]

    /// Per-node anchors: a pinned node exerts its forces but never moves.
    /// Pin the node you're dragging, or a root you want held in place.
    public var pinned: [Bool]

    /// The rectangle the layout stays inside (nodes clamp to it every step).
    public let bounds: Rectangle

    /// The spacing constant `k`, in canvas units: the scale every force is
    /// measured against, defaulting to `√(area / count)`. Settled edges come
    /// out *near* `k` only for small or dense graphs; in a large sparse one
    /// the crowd's combined repulsion compresses spacing well below it, so
    /// treat `k` as the size dial (raise it to open the web, lower it to
    /// tighten) rather than a promised edge length.
    public var idealDistance: Double

    /// An optional pull toward the center of `bounds`, as a phantom edge
    /// from every node (0 is off, 1 pulls like a normal edge). Useful when
    /// the graph has disconnected pieces, which otherwise repel each other
    /// onto the walls.
    public var gravity: Double = 0

    /// The current cap on how far a node may move in one step, in canvas
    /// units. Cools linearly to zero over `coolingSteps`; set it directly
    /// (or call `reheat`) to stir a settled layout back into motion.
    public var temperature: Double

    /// How many steps the temperature takes to cool from fresh to frozen.
    /// At 60 fps the default settles in about four seconds of watching.
    public var coolingSteps: Int

    /// The temperature a fresh layout (and a full `reheat()`) starts at:
    /// a tenth of the frame's larger side.
    public var initialTemperature: Double

    /// Whether the layout has cooled to a stop. A settled layout's `step()`
    /// is free, so you can leave it in `draw()`.
    public var isSettled: Bool { temperature <= 0 }

    /// A layout of `count` nodes joined by `edges` (pairs of node indices),
    /// placed at seeded random positions inside `bounds`.
    public init(count: Int, edges: [(Int, Int)] = [], in bounds: Rectangle,
                idealDistance: Double? = nil, seed: UInt64 = 1) {
        let n = Swift.max(count, 0)
        self.bounds = bounds
        self.edges = edges.map { Edge($0.0, $0.1) }
        self.pinned = [Bool](repeating: false, count: n)
        self.idealDistance = idealDistance
            ?? (n > 0 ? (bounds.width * bounds.height / Double(n)).squareRoot() : 1)
        let start = Swift.max(bounds.width, bounds.height) / 10
        self.initialTemperature = start
        self.temperature = start
        self.coolingSteps = 250
        var rng = SplitMix64(seed: seed)
        self.positions = (0 ..< n).map { _ in
            Vector2(bounds.x + Double.random(in: 0 ..< 1, using: &rng) * bounds.width,
                    bounds.y + Double.random(in: 0 ..< 1, using: &rng) * bounds.height)
        }
    }

    /// A layout over explicit starting positions (a circle, a grid, the
    /// output of another pass), joined by `edges` (pairs of node indices).
    public init(positions: [Vector2], edges: [(Int, Int)] = [], in bounds: Rectangle,
                idealDistance: Double? = nil) {
        self.bounds = bounds
        self.positions = positions
        self.edges = edges.map { Edge($0.0, $0.1) }
        self.pinned = [Bool](repeating: false, count: positions.count)
        self.idealDistance = idealDistance
            ?? (positions.isEmpty ? 1
                : (bounds.width * bounds.height / Double(positions.count)).squareRoot())
        let start = Swift.max(bounds.width, bounds.height) / 10
        self.initialTemperature = start
        self.temperature = start
        self.coolingSteps = 250
    }

    /// The number of nodes.
    public var count: Int { positions.count }

    // MARK: - Growing the graph

    /// Append a node at `position` and return its index. Follow with a
    /// `reheat` so the layout makes room for it.
    @discardableResult
    public func addNode(at position: Vector2, pinned: Bool = false) -> Int {
        positions.append(position)
        self.pinned.append(pinned)
        return positions.count - 1
    }

    /// Append an edge between nodes `a` and `b`.
    public func connect(_ a: Int, _ b: Int, weight: Double = 1) {
        edges.append(Edge(a, b, weight: weight))
    }

    /// The index of the node nearest to `point` (for picking one up with
    /// the mouse), or `nil` for an empty layout.
    public func nearestNode(to point: Vector2) -> Int? {
        var best: Int?
        var bestD2 = Double.infinity
        for i in positions.indices {
            let d2 = (positions[i] - point).lengthSquared
            if d2 < bestD2 { bestD2 = d2; best = i }
        }
        return best
    }

    /// Warm the layout back up so it can absorb a change: `1` restarts the
    /// full cooling run, smaller fractions give a gentler reflow (0.3 reads
    /// well after adding a node or releasing a drag).
    public func reheat(_ fraction: Double = 1) {
        temperature = Swift.max(temperature,
                                initialTemperature * Swift.min(Swift.max(fraction, 0), 1))
    }

    // MARK: - Stepping

    /// Advance the layout one step: every pair repels, every edge attracts,
    /// each node moves at most `temperature` along its summed force, and the
    /// temperature cools. A settled layout returns immediately.
    public func step() {
        let n = positions.count
        guard n > 1, temperature > 0 else { return }

        let k = Swift.max(idealDistance, 1e-6)
        var displacement = [Vector2](repeating: .zero, count: n)

        // Repulsion between all pairs, accumulated once per pair with the
        // equal-and-opposite push applied to both ends.
        for i in 0 ..< n - 1 {
            let p = positions[i]
            for j in (i + 1) ..< n {
                var delta = p - positions[j]
                var d2 = delta.lengthSquared
                if d2 < 1e-12 {
                    // Coincident nodes: part them along a fixed, index-derived
                    // direction so the tie breaks the same way every run.
                    delta = Vector2(angle: Double(i * 31 &+ j) * 0.61803, length: 1e-6)
                    d2 = delta.lengthSquared
                }
                let d = d2.squareRoot()
                let push = delta * (k * k / (d2 * d))    // (delta/d) * k²/d
                displacement[i] += push
                displacement[j] -= push
            }
        }

        // Attraction along edges (skipping self-loops and stale indices).
        for edge in edges {
            guard edge.a != edge.b,
                  positions.indices.contains(edge.a),
                  positions.indices.contains(edge.b) else { continue }
            let delta = positions[edge.a] - positions[edge.b]
            let d = delta.length
            guard d > 1e-9 else { continue }
            let pull = delta * (d / k * edge.weight)     // (delta/d) * d²/k
            displacement[edge.a] -= pull
            displacement[edge.b] += pull
        }

        // Gravity: a phantom edge from every node to the center.
        if gravity > 0 {
            let center = bounds.center
            for i in 0 ..< n {
                let delta = center - positions[i]
                let d = delta.length
                guard d > 1e-9 else { continue }
                displacement[i] += delta * (d / k * gravity)
            }
        }

        // Move, capped by the temperature, clamped into the frame.
        for i in 0 ..< n where !pinned[i] {
            let d = displacement[i].length
            guard d > 1e-9 else { continue }
            let travel = Swift.min(d, temperature)
            let p = positions[i] + displacement[i] * (travel / d)
            positions[i] = Vector2(
                Swift.min(bounds.x + bounds.width, Swift.max(bounds.x, p.x)),
                Swift.min(bounds.y + bounds.height, Swift.max(bounds.y, p.y)))
        }

        temperature = Swift.max(0, temperature - initialTemperature / Double(Swift.max(coolingSteps, 1)))
    }

    /// Advance the layout by `steps` steps.
    public func step(_ steps: Int) {
        for _ in 0 ..< Swift.max(steps, 0) { step() }
    }

    /// Run the layout to a standstill: step until the cooling reaches zero.
    /// The setup-shaped form, for when you want the settled web, not the
    /// settling.
    public func settle() {
        while !isSettled { step() }
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Draw `layout` plainly: each edge as a line in the current stroke,
    /// each node as a disk of `nodeRadius` in the current fill (0 skips the
    /// nodes). For any other styling, read `positions` and `edges` directly.
    func drawGraph(_ layout: ForceLayout, nodeRadius: Double = 5) {
        for edge in layout.edges
        where layout.positions.indices.contains(edge.a)
            && layout.positions.indices.contains(edge.b) {
            drawLine(layout.positions[edge.a], layout.positions[edge.b])
        }
        if nodeRadius > 0 {
            drawCircles(layout.positions, radius: nodeRadius)
        }
    }
}
