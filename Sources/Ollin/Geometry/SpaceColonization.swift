import Foundation

/// Space colonization: grow branching structure toward a scattered set of
/// attraction points (the venation-and-branching growth model). Every step,
/// each remaining attractor pulls on the single closest branch node within
/// `influenceRadius`; each pulled node grows a new node one `stepLength`
/// toward the average of its pulls; attractors that a node reaches (within
/// `killRadius`) are consumed. Veins, roots, lightning, and trees fall out of
/// where you scatter the attractors and where you plant the roots.
///
/// It's a stateful stepper you hold and `step()` each frame (or run to the
/// end with `grow()`). The algorithm is deterministic for a given input: the
/// same attractors and roots always grow the same structure.
///
/// ```swift
/// seed(7)
/// let growth = SpaceColonization(attractors: poissonDisk(radius: 24),
///                                roots: [Vector2(width / 2, height)])
///
/// override func draw() {
///     growth.step()
///     background(.black); stroke(.white)
///     for (a, b) in growth.segments { drawLine(a, b) }
/// }
/// ```
public final class SpaceColonization {
    /// One node of the grown structure.
    public struct Node {
        /// Where the node sits.
        public let position: Vector2
        /// The index of the node this one grew from (`nil` for a root).
        public let parent: Int?
    }

    /// The grown structure so far (roots first, then in growth order).
    public private(set) var nodes: [Node]
    /// The attraction points not yet consumed.
    public private(set) var attractors: [Vector2]
    /// How far an attractor can reach to pull on a node.
    public var influenceRadius: Double
    /// How close a node must come to consume an attractor. Keep it larger
    /// than `stepLength` (a node can otherwise step right past its goal).
    public var killRadius: Double
    /// How far a new node grows from its parent each step.
    public var stepLength: Double
    /// A cap on the structure's size.
    public var maxNodes: Int

    private var finishedFlag = false
    private var stalledSteps = 0

    /// A growth toward `attractors`, starting from one root node per entry
    /// of `roots`.
    public init(attractors: [Vector2], roots: [Vector2],
                influenceRadius: Double = 120, killRadius: Double = 24,
                stepLength: Double = 12, maxNodes: Int = 6000) {
        self.attractors = attractors
        self.nodes = roots.map { Node(position: $0, parent: nil) }
        self.influenceRadius = influenceRadius
        self.killRadius = killRadius
        self.stepLength = stepLength
        self.maxNodes = maxNodes
    }

    /// The number of nodes grown so far.
    public var count: Int { nodes.count }

    /// True when growth is over: every reachable attractor is consumed and
    /// no node can grow further.
    public var isFinished: Bool { finishedFlag }

    /// The structure as line segments (each node to its parent), ready for
    /// `drawLine`, thickness mapping, or SVG export.
    public var segments: [(Vector2, Vector2)] {
        nodes.compactMap { node in
            node.parent.map { (nodes[$0].position, node.position) }
        }
    }

    /// Advance one growth step: attractors pull, pulled nodes grow, reached
    /// attractors are consumed.
    public func step() {
        guard !finishedFlag, !attractors.isEmpty, nodes.count < maxNodes else {
            finishedFlag = true
            return
        }

        // Hash the nodes so each attractor scans only nearby cells for its
        // closest node.
        let cell = Swift.max(influenceRadius, 1e-6)
        var grid: [GrowthCell: [Int]] = [:]
        grid.reserveCapacity(nodes.count)
        for (i, node) in nodes.enumerated() {
            grid[GrowthCell(node.position, cell), default: []].append(i)
        }

        // Each attractor pulls on its single closest node within reach.
        let influence2 = influenceRadius * influenceRadius
        var pulls: [Int: Vector2] = [:]      // node index → summed unit pulls
        for attractor in attractors {
            var bestDistance2 = influence2
            var best: Int?
            let col = Int(floor(attractor.x / cell)), row = Int(floor(attractor.y / cell))
            for cc in (col - 1) ... (col + 1) {
                for rr in (row - 1) ... (row + 1) {
                    guard let bucket = grid[GrowthCell(column: cc, row: rr)] else { continue }
                    for i in bucket {
                        let d2 = attractor.distanceSquared(to: nodes[i].position)
                        if d2 < bestDistance2 { bestDistance2 = d2; best = i }
                    }
                }
            }
            if let best {
                let direction = (attractor - nodes[best].position).normalized
                pulls[best, default: .zero] += direction
            }
        }

        // Pulled nodes grow toward the average of their pulls. A pull sum
        // near zero (attractors in perfect balance) grows nothing, and a new
        // node that would land on an existing one is skipped, so growth
        // can't oscillate in place.
        var grew = false
        let tooClose2 = (stepLength * 0.5) * (stepLength * 0.5)
        for (index, pull) in pulls.sorted(by: { $0.key < $1.key }) {
            guard pull.lengthSquared > 1e-9, nodes.count < maxNodes else { continue }
            let position = nodes[index].position + pull.normalized * stepLength
            let col = Int(floor(position.x / cell)), row = Int(floor(position.y / cell))
            var collides = false
            outer: for cc in (col - 1) ... (col + 1) {
                for rr in (row - 1) ... (row + 1) {
                    guard let bucket = grid[GrowthCell(column: cc, row: rr)] else { continue }
                    for i in bucket where position.distanceSquared(to: nodes[i].position) < tooClose2 {
                        collides = true
                        break outer
                    }
                }
            }
            guard !collides else { continue }
            nodes.append(Node(position: position, parent: index))
            grid[GrowthCell(position, cell), default: []].append(nodes.count - 1)
            grew = true
        }

        // Consume the attractors any node has reached.
        let kill2 = killRadius * killRadius
        let before = attractors.count
        attractors.removeAll { attractor in
            let col = Int(floor(attractor.x / cell)), row = Int(floor(attractor.y / cell))
            for cc in (col - 1) ... (col + 1) {
                for rr in (row - 1) ... (row + 1) {
                    guard let bucket = grid[GrowthCell(column: cc, row: rr)] else { continue }
                    for i in bucket where attractor.distanceSquared(to: nodes[i].position) < kill2 {
                        return true
                    }
                }
            }
            return false
        }

        // No growth means the remaining attractors are unreachable; many
        // consecutive steps without consuming one means the same.
        stalledSteps = attractors.count < before ? 0 : stalledSteps + 1
        if !grew || stalledSteps > 60 { finishedFlag = true }
    }

    /// Advance `steps` steps.
    public func step(_ steps: Int) {
        for _ in 0 ..< Swift.max(steps, 0) where !finishedFlag { step() }
    }

    /// Run the growth to the end.
    public func grow() {
        while !finishedFlag { step() }
    }

    /// A thickness per node from the pipe model: every leaf tip has
    /// `leafWidth`, and a parent's width is the sum of its children's raised
    /// to `exponent`, re-rooted (so trunks are thick and twigs thin, the way
    /// real branches carry their load). Index-aligned with `nodes`.
    public func thicknesses(leafWidth: Double = 1.5, exponent: Double = 2.2) -> [Double] {
        var flow = [Double](repeating: 0, count: nodes.count)
        for i in stride(from: nodes.count - 1, through: 0, by: -1) {
            if flow[i] == 0 { flow[i] = pow(leafWidth, exponent) }   // a leaf tip
            if let parent = nodes[i].parent { flow[parent] += flow[i] }
        }
        return flow.map { pow($0, 1 / exponent) }
    }
}

/// A uniform-grid cell key for the growth's neighbor searches.
private struct GrowthCell: Hashable {
    let column: Int, row: Int
    init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
    init(column: Int, row: Int) { self.column = column; self.row = row }
    init(_ p: Vector2, _ cell: Double) {
        self.column = Int(floor(p.x / cell))
        self.row = Int(floor(p.y / cell))
    }
}
