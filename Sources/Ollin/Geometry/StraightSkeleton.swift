import Foundation

/// The straight skeleton of a shape: the line network traced by the boundary
/// as it shrinks inward at uniform speed, every edge sliding parallel to
/// itself until the region thins away. Where the medial axis bends into
/// parabolas around reflex corners, the straight skeleton stays piecewise
/// straight, and the wavefront at distance `d` is exactly the shape inset by
/// `d` with sharp mitered corners: one skeleton, a whole ladder of concentric
/// insets. The skeleton also partitions the shape into one face per boundary
/// edge (raise every point to its distance and each face becomes a roof
/// plane), so the same structure drives line work, inset ladders, and
/// paneling.
///
/// ```swift
/// let skeleton = straightSkeleton(of: blob)
/// stroke(.black)
/// for arc in skeleton.arcs { drawLine(arc.start, arc.end) }
/// for d in stride(from: 8.0, to: skeleton.maxInset, by: 8) {
///     drawShape(skeleton.inset(by: d))
/// }
/// ```
///
/// Computed by the standard shrinking-wavefront simulation over a queue of
/// edge and split events, with simultaneous events clustered by level and
/// meeting point and processed together, which is what keeps right angles,
/// collinear runs, and symmetric shapes (where many events land on one
/// point) crack-free. Deterministic given the shape, and setup-shaped:
/// extract once and hold the result.

/// A shape's straight skeleton: the `arcs` of the ridge network, one `Face`
/// per boundary edge, and mitered insets via `inset(by:)`. Returned by
/// `straightSkeleton(of:)`.
public struct StraightSkeleton: Equatable, Sendable {
    /// One skeleton arc: a straight segment between two skeleton nodes, each
    /// end carrying the inset distance at which the wavefront reached it.
    /// `start` is the shallower end (boundary vertices sit at distance 0).
    public struct Arc: Equatable, Sendable {
        public let start: Vector2
        public let end: Vector2
        /// The inset distance at `start` (0 for a boundary vertex).
        public let startDistance: Double
        /// The inset distance at `end`.
        public let endDistance: Double

        public init(start: Vector2, end: Vector2, startDistance: Double, endDistance: Double) {
            self.start = start
            self.end = end
            self.startDistance = startDistance
            self.endDistance = endDistance
        }
    }

    /// The region one boundary edge sweeps as the wavefront shrinks: a
    /// polygon bounded by the edge itself and skeleton arcs. The faces
    /// partition the shape, and `distances` runs 1:1 with `points` (the
    /// edge's own endpoints sit at 0), so a face can be shaded by depth.
    public struct Face: Equatable, Sendable {
        /// The boundary edge this face grew from, in boundary order.
        public let edgeStart: Vector2
        public let edgeEnd: Vector2
        /// The face boundary, starting `edgeStart`, `edgeEnd`, then the
        /// skeleton nodes back around to the start.
        public let points: [Vector2]
        /// The inset distance at each boundary point.
        public let distances: [Double]

        public init(edgeStart: Vector2, edgeEnd: Vector2, points: [Vector2], distances: [Double]) {
            self.edgeStart = edgeStart
            self.edgeEnd = edgeEnd
            self.points = points
            self.distances = distances
        }

        /// The face as a plain closed `Contour`.
        public var contour: Contour { Contour(points, closed: true) }
    }

    /// Every skeleton arc, deduplicated and canonically ordered.
    public let arcs: [Arc]
    /// One face per boundary edge, in boundary order (outer ring first, then
    /// holes, region by region).
    public let faces: [Face]
    /// The largest inset distance before the shape vanishes: `inset(by:)`
    /// returns an empty shape past it.
    public let maxInset: Double

    // The node graph behind exact inset extraction: every face boundary as
    // node indexes into one shared table, so a chord endpoint computed on a
    // shared arc matches its neighbor face exactly, no epsilon stitching.
    let nodePoints: [Vector2]
    let nodeDistances: [Double]
    let faceNodes: [[Int]]
    let inputContours: [Contour]

    public init(arcs: [Arc], faces: [Face], maxInset: Double) {
        self.arcs = arcs
        self.faces = faces
        self.maxInset = maxInset
        nodePoints = []
        nodeDistances = []
        faceNodes = []
        inputContours = []
    }

    init(arcs: [Arc], faces: [Face], maxInset: Double,
         nodePoints: [Vector2], nodeDistances: [Double], faceNodes: [[Int]],
         inputContours: [Contour]) {
        self.arcs = arcs
        self.faces = faces
        self.maxInset = maxInset
        self.nodePoints = nodePoints
        self.nodeDistances = nodeDistances
        self.faceNodes = faceNodes
        self.inputContours = inputContours
    }

    /// The shape inset by `distance` with mitered corners: the wavefront the
    /// skeleton describes, extracted exactly (each face is a roof plane, so
    /// the inset is a straight cut through it). A deep inset can split one
    /// region into several rings, and a hole's ring grows as the region
    /// around it thins; past `maxInset` the result is empty. `distance <= 0`
    /// returns the shape itself.
    public func inset(by distance: Double) -> Shape {
        if distance <= 0 { return Shape(contours: inputContours) }
        guard !faceNodes.isEmpty, distance <= maxInset else { return Shape(contours: []) }

        // One chord per face crossing: enter/exit points where the boundary
        // passes the distance level, keyed by the (nodeA, nodeB) segment they
        // sit on so both faces sharing an arc agree on the point exactly.
        struct Crossing {
            var key: Int64
            var point: Vector2
            var along: Double
        }
        struct Chord {
            var from: Crossing
            var to: Crossing
        }
        var chords: [Chord] = []
        for (f, ring) in faceNodes.enumerated() {
            guard ring.count >= 3 else { continue }
            let edgeDirection = (faces[f].edgeEnd - faces[f].edgeStart).normalized
            var crossings: [Crossing] = []
            for i in ring.indices {
                let a = ring[i]
                let b = ring[(i + 1) % ring.count]
                let da = nodeDistances[a]
                let db = nodeDistances[b]
                // Half-open rule so a vertex exactly at the level counts once.
                guard (da < distance) != (db < distance), db != da else { continue }
                let s = (distance - da) / (db - da)
                let point = nodePoints[a] + (nodePoints[b] - nodePoints[a]) * s
                let lo = Int64(min(a, b)), hi = Int64(max(a, b))
                crossings.append(Crossing(key: lo << 32 | hi,
                                          point: point,
                                          along: point.dot(edgeDirection)))
            }
            guard crossings.count >= 2 else { continue }
            // The level line runs parallel to the face's edge; sorted along
            // it, alternate spans lie inside the face.
            crossings.sort { $0.along != $1.along ? $0.along < $1.along : $0.key < $1.key }
            var i = 0
            while i + 1 < crossings.count {
                let from = crossings[i], to = crossings[i + 1]
                if from.key != to.key {
                    chords.append(Chord(from: from, to: to))
                }
                i += 2
            }
        }
        guard !chords.isEmpty else { return Shape(contours: []) }

        // Stitch chords into rings: each chord ends on the arc where its
        // neighbor face's chord begins, so the walk is exact. Rings start at
        // their lexicographically smallest chord for a canonical output.
        var startingAt: [Int64: Int] = [:]
        for (i, chord) in chords.enumerated() { startingAt[chord.from.key] = i }
        var order = Array(chords.indices)
        order.sort {
            let a = chords[$0].from.point, b = chords[$1].from.point
            return a.x != b.x ? a.x < b.x : a.y < b.y
        }
        var used = [Bool](repeating: false, count: chords.count)
        var rings: [Contour] = []
        for first in order where !used[first] {
            var points: [Vector2] = []
            var i = first
            var closed = false
            while !used[i] {
                used[i] = true
                points.append(chords[i].from.point)
                guard let next = startingAt[chords[i].to.key] else { break }
                if next == first { closed = true; break }
                i = next
            }
            if closed, points.count >= 3 {
                rings.append(Contour(points, closed: true))
            }
        }
        return Shape(contours: rings)
    }
}

/// The straight skeleton of `shape`. Contours must be simple, non-crossing
/// rings; nesting decides which are holes (a ring inside a ring bounds a
/// hole, an island inside a hole starts a fresh region), and each region
/// skeletonizes independently. Dense outlines work but every boundary vertex
/// grows its own arc, so simplify traced or resampled shapes first if you
/// want clean line work. Deterministic given the shape.
public func straightSkeleton(of shape: Shape) -> StraightSkeleton {
    // Cleaned rings, in input order, with a scale-relative tolerance.
    var extent = 0.0
    for contour in shape.contours {
        for p in contour.points {
            extent = max(extent, abs(p.x), abs(p.y))
        }
    }
    let tolerance = max(1e-12, extent * 1e-9)

    var rings: [[Vector2]] = []
    for contour in shape.contours {
        var points = contour.points
        while points.count >= 2, (points[0] - points[points.count - 1]).length <= tolerance {
            points.removeLast()
        }
        var cleaned: [Vector2] = []
        for p in points where cleaned.isEmpty || (p - cleaned[cleaned.count - 1]).length > tolerance {
            cleaned.append(p)
        }
        if cleaned.count >= 3, abs(ringArea(cleaned)) > tolerance * tolerance {
            rings.append(cleaned)
        }
    }
    guard !rings.isEmpty else { return StraightSkeleton(arcs: [], faces: [], maxInset: 0) }

    // Group rings into regions by containment parity: even depth bounds a
    // region, odd depth is a hole of the region directly around it.
    let depths = rings.indices.map { i in
        rings.indices.reduce(0) { depth, j in
            j == i ? depth : depth + (pointInRing(rings[i][0], rings[j]) ? 1 : 0)
        }
    }
    var regions: [(outer: Int, holes: [Int])] = []
    for (i, depth) in depths.enumerated() where depth % 2 == 0 {
        var holes: [Int] = []
        for (j, holeDepth) in depths.enumerated()
        where holeDepth == depth + 1 && pointInRing(rings[j][0], rings[i]) {
            holes.append(j)
        }
        regions.append((i, holes))
    }

    var nodePoints: [Vector2] = []
    var nodeDistances: [Double] = []
    var faces: [StraightSkeleton.Face] = []
    var faceNodes: [[Int]] = []
    var arcPairs: [(Int, Int)] = []
    var seenArcs = Set<Int64>()
    var inputContours: [Contour] = []

    for region in regions {
        // Interior on the left: the outer ring runs positive, holes negative.
        var outer = rings[region.outer]
        if ringArea(outer) < 0 { outer.reverse() }
        var holes: [[Vector2]] = []
        for h in region.holes {
            var ring = rings[h]
            if ringArea(ring) > 0 { ring.reverse() }
            holes.append(ring)
        }
        inputContours.append(Contour(outer, closed: true))
        for hole in holes { inputContours.append(Contour(hole, closed: true)) }

        let engine = SkeletonEngine(rings: [outer] + holes, tolerance: tolerance)
        engine.run()

        let base = nodePoints.count
        nodePoints.append(contentsOf: engine.nodes.map(\.point))
        nodeDistances.append(contentsOf: engine.nodes.map(\.distance))

        // Each face is stitched from its edge plus the arcs of every
        // wavefront vertex that carried one of the edge's endpoints.
        var segments = [[(Int, Int)]](repeating: [], count: engine.edges.count)
        for vertex in engine.vertices {
            guard let death = vertex.deathNode, death != vertex.originNode else { continue }
            segments[vertex.previousEdge.id].append((vertex.originNode, death))
            if vertex.nextEdge.id != vertex.previousEdge.id {
                segments[vertex.nextEdge.id].append((vertex.originNode, death))
            }
        }
        for bridge in engine.bridges {
            segments[bridge.edgeA].append((bridge.nodeA, bridge.nodeB))
            if bridge.edgeB != bridge.edgeA {
                segments[bridge.edgeB].append((bridge.nodeA, bridge.nodeB))
            }
        }
        for edge in engine.edges {
            guard let ring = stitchFace(edge: edge, segments: segments[edge.id]) else { continue }
            faces.append(StraightSkeleton.Face(edgeStart: edge.begin,
                                               edgeEnd: edge.end,
                                               points: ring.map { engine.nodes[$0].point },
                                               distances: ring.map { engine.nodes[$0].distance }))
            faceNodes.append(ring.map { $0 + base })
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                if a == edge.beginNode, b == edge.endNode { continue }
                let key = Int64(min(a, b)) << 32 | Int64(max(a, b))
                if seenArcs.insert(key).inserted {
                    arcPairs.append((a + base, b + base))
                }
            }
        }
        seenArcs.removeAll(keepingCapacity: true)
    }

    var arcs: [StraightSkeleton.Arc] = []
    for (a, b) in arcPairs {
        guard (nodePoints[a] - nodePoints[b]).length > tolerance else { continue }
        let flip = nodeDistances[a] != nodeDistances[b]
            ? nodeDistances[a] > nodeDistances[b]
            : !pointBefore(nodePoints[a], nodePoints[b])
        let (s, e) = flip ? (b, a) : (a, b)
        arcs.append(StraightSkeleton.Arc(start: nodePoints[s], end: nodePoints[e],
                                         startDistance: nodeDistances[s],
                                         endDistance: nodeDistances[e]))
    }
    arcs.sort {
        if $0.startDistance != $1.startDistance { return $0.startDistance < $1.startDistance }
        if $0.start != $1.start { return pointBefore($0.start, $1.start) }
        return pointBefore($0.end, $1.end)
    }
    let maxInset = faceNodes.reduce(0.0) { deepest, ring in
        ring.reduce(deepest) { max($0, nodeDistances[$1]) }
    }
    return StraightSkeleton(arcs: arcs, faces: faces, maxInset: maxInset,
                            nodePoints: nodePoints, nodeDistances: nodeDistances,
                            faceNodes: faceNodes, inputContours: inputContours)
}

/// Walks a face ring from the edge's own base segment through the collected
/// arcs, matching by node identity. Returns nil when the boundary fails to
/// close (degenerate input), and such a face is dropped rather than guessed.
private func stitchFace(edge: SkelEdge, segments: [(Int, Int)]) -> [Int]? {
    var ring = [edge.beginNode, edge.endNode]
    var remaining = segments
    var current = edge.endNode
    for _ in 0 ..< segments.count {
        var pick = -1
        for (i, segment) in remaining.enumerated()
        where segment.0 == current || segment.1 == current {
            if pick == -1 { pick = i } else {
                // Prefer the lower far node so pinched boundaries walk the
                // same way every run.
                let far = remaining[i].0 == current ? remaining[i].1 : remaining[i].0
                let best = remaining[pick].0 == current ? remaining[pick].1 : remaining[pick].0
                if far < best { pick = i }
            }
        }
        guard pick >= 0 else { return nil }
        let segment = remaining.remove(at: pick)
        current = segment.0 == current ? segment.1 : segment.0
        if current == edge.beginNode { return ring }
        ring.append(current)
    }
    return nil
}

// MARK: - The wavefront engine (file-private)

/// One skeleton node: a point the wavefront reached at some inset distance.
private struct SkelNode {
    var point: Vector2
    var distance: Double
}

/// An original boundary edge: the fixed supporting line a wavefront segment
/// slides along, with the initial bisectors at its endpoints (the wedge a
/// split candidate must land in).
private final class SkelEdge {
    let id: Int
    let begin: Vector2
    let end: Vector2
    let direction: Vector2
    let normal: Vector2
    let beginNode: Int
    let endNode: Int
    var bisectorAtBegin = SkelRay(origin: .zero, direction: .zero)
    var bisectorAtEnd = SkelRay(origin: .zero, direction: .zero)

    init(id: Int, begin: Vector2, end: Vector2, beginNode: Int, endNode: Int) {
        self.id = id
        self.begin = begin
        self.end = end
        direction = (end - begin).normalized
        normal = direction.perpendicular
        self.beginNode = beginNode
        self.endNode = endNode
    }

    /// Perpendicular distance from `point` to this edge's line.
    func distance(to point: Vector2) -> Double {
        abs((point - begin).dot(normal))
    }
}

/// A wavefront vertex: one corner of the shrinking boundary, moving along
/// its bisector, linked into a circular list (its LAV).
private final class SkelVertex {
    let id: Int
    let point: Vector2
    let distance: Double
    let bisector: SkelRay
    let previousEdge: SkelEdge
    let nextEdge: SkelEdge
    let originNode: Int
    var deathNode: Int?
    var processed = false
    var prev: SkelVertex?
    var next: SkelVertex?
    weak var lav: LAV?

    init(id: Int, point: Vector2, distance: Double, bisector: SkelRay,
         previousEdge: SkelEdge, nextEdge: SkelEdge, originNode: Int) {
        self.id = id
        self.point = point
        self.distance = distance
        self.bisector = bisector
        self.previousEdge = previousEdge
        self.nextEdge = nextEdge
        self.originNode = originNode
    }
}

/// A circular list of active wavefront vertices.
private final class LAV {
    var head: SkelVertex?
    var count = 0

    func append(_ vertex: SkelVertex) {
        if let head {
            insert(vertex, before: head)
        } else {
            vertex.prev = vertex
            vertex.next = vertex
            vertex.lav = self
            head = vertex
            count = 1
        }
    }

    func insert(_ vertex: SkelVertex, before anchor: SkelVertex) {
        let left = anchor.prev!
        left.next = vertex
        vertex.prev = left
        vertex.next = anchor
        anchor.prev = vertex
        vertex.lav = self
        count += 1
    }

    func insert(_ vertex: SkelVertex, after anchor: SkelVertex) {
        insert(vertex, before: anchor.next!)
    }

    func remove(_ vertex: SkelVertex) {
        guard vertex.lav === self else { return }
        if count == 1 {
            head = nil
        } else {
            vertex.prev!.next = vertex.next
            vertex.next!.prev = vertex.prev
            if head === vertex { head = vertex.next }
        }
        vertex.prev = nil
        vertex.next = nil
        vertex.lav = nil
        count -= 1
    }

    var vertices: [SkelVertex] {
        guard let head else { return [] }
        var result: [SkelVertex] = []
        var v = head
        repeat {
            result.append(v)
            v = v.next!
        } while v !== head
        return result
    }
}

/// A ray with a unit direction; side tests measure true perpendicular
/// distance so tolerances stay in shape units.
private struct SkelRay {
    var origin: Vector2
    var direction: Vector2

    /// Positive on the left of the ray, negative on the right.
    func side(of point: Vector2) -> Double {
        direction.cross(point - origin)
    }

    /// Intersection with the full line through `point` along `along`,
    /// rejecting hits behind the origin (param below `minAhead`).
    func intersectLine(through point: Vector2, along: Vector2, minAhead: Double) -> Vector2? {
        let denom = direction.cross(along)
        guard abs(denom) > 1e-12 else { return nil }
        let t = (point - origin).cross(along) / denom
        guard t > minAhead else { return nil }
        return origin + direction * t
    }
}

/// The event a wavefront vertex is heading toward.
private struct SkelEvent {
    enum Kind {
        /// The edge between two neighboring vertices collapses.
        case edge(previous: SkelVertex, next: SkelVertex)
        /// A reflex vertex reaches an opposite edge (nil when it strikes the
        /// wedge boundary, a vertex-split).
        case split(parent: SkelVertex, opposite: SkelEdge?)
    }

    var point: Vector2
    var distance: Double
    var kind: Kind
    var seq: Int

    var isObsolete: Bool {
        switch kind {
        case let .edge(previous, next): return previous.processed || next.processed
        case let .split(parent, _): return parent.processed
        }
    }
}

/// One chain of the wavefront around an event point: a run of collapsing
/// edges, a split vertex, or the opposite edge a split lands on. Ends are
/// read live because LAV surgery between chain pairs moves the neighbors.
private enum SkelChain {
    case edges(events: [SkelEvent], closed: Bool)
    case split(parent: SkelVertex, opposite: SkelEdge?)
    case opposite(edge: SkelEdge, next: SkelVertex, previous: SkelVertex)

    var previousEdge: SkelEdge {
        switch self {
        case let .edges(events, _):
            guard case let .edge(previous, _) = events[0].kind else { fatalError() }
            return previous.previousEdge
        case let .split(parent, _): return parent.previousEdge
        case let .opposite(edge, _, _): return edge
        }
    }

    var nextEdge: SkelEdge {
        switch self {
        case let .edges(events, _):
            guard case let .edge(_, next) = events[events.count - 1].kind else { fatalError() }
            return next.nextEdge
        case let .split(parent, _): return parent.nextEdge
        case let .opposite(edge, _, _): return edge
        }
    }

    var previousVertex: SkelVertex {
        switch self {
        case let .edges(events, _):
            guard case let .edge(previous, _) = events[0].kind else { fatalError() }
            return previous
        case let .split(parent, _): return parent.prev!
        case let .opposite(_, _, previous): return previous
        }
    }

    var nextVertex: SkelVertex {
        switch self {
        case let .edges(events, _):
            guard case let .edge(_, next) = events[events.count - 1].kind else { fatalError() }
            return next
        case let .split(parent, _): return parent.next!
        case let .opposite(_, next, _): return next
        }
    }

    var splitParent: SkelVertex? {
        if case let .split(parent, _) = self { return parent }
        return nil
    }
}

/// The wavefront simulation for one region (an outer ring and its holes,
/// interior on the left of every edge).
private final class SkeletonEngine {
    let tolerance: Double
    var edges: [SkelEdge] = []
    var vertices: [SkelVertex] = []
    var nodes: [SkelNode] = []
    var bridges: [(nodeA: Int, nodeB: Int, edgeA: Int, edgeB: Int)] = []
    private var slav: [LAV] = []
    private var heap: [SkelEvent] = []
    private var nextSeq = 0
    private var nextVertexID = 0

    init(rings: [[Vector2]], tolerance: Double) {
        self.tolerance = tolerance
        for ring in rings {
            let lav = LAV()
            slav.append(lav)
            let edgeBase = edges.count
            let n = ring.count
            let nodeBase = nodes.count
            for i in 0 ..< n {
                nodes.append(SkelNode(point: ring[i], distance: 0))
            }
            for i in 0 ..< n {
                edges.append(SkelEdge(id: edgeBase + i,
                                      begin: ring[i], end: ring[(i + 1) % n],
                                      beginNode: nodeBase + i,
                                      endNode: nodeBase + (i + 1) % n))
            }
            for i in 0 ..< n {
                let previousEdge = edges[edgeBase + (i + n - 1) % n]
                let nextEdge = edges[edgeBase + i]
                let bisector = SkelRay(origin: ring[i],
                                       direction: bisectorDirection(previousEdge.direction,
                                                                    nextEdge.direction))
                previousEdge.bisectorAtEnd = bisector
                nextEdge.bisectorAtBegin = bisector
                let vertex = SkelVertex(id: nextVertexID, point: ring[i], distance: 0,
                                        bisector: bisector,
                                        previousEdge: previousEdge, nextEdge: nextEdge,
                                        originNode: nodeBase + i)
                nextVertexID += 1
                vertices.append(vertex)
                lav.append(vertex)
            }
        }
    }

    func run() {
        for lav in slav {
            for vertex in lav.vertices {
                enqueueSplitEvents(for: vertex, closerThan: nil)
            }
        }
        for lav in slav {
            for vertex in lav.vertices {
                enqueueEdgeEvent(previous: vertex, next: vertex.next!)
            }
        }

        var iterations = 0
        let iterationCap = max(10_000, vertices.count * 40)
        while !heap.isEmpty {
            iterations += 1
            if iterations > iterationCap { break }

            var level = loadLevelEvents()
            guard !level.isEmpty else { continue }
            let levelHeight = level[0].distance
            // A deterministic pass order regardless of heap internals.
            level.sort {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                if $0.point != $1.point { return pointBefore($0.point, $1.point) }
                return $0.seq < $1.seq
            }

            for event in makeLevelEvents(level) {
                switch event {
                case let .pick(point, distance, chain):
                    processPick(point: point, distance: distance, chain: chain)
                case let .multiEdge(point, distance, chain):
                    processMultiEdge(point: point, distance: distance, chain: chain)
                case let .multiSplit(point, distance, chains):
                    processMultiSplit(point: point, distance: distance, chains: chains)
                }
            }

            mergeCoincidentNeighbors()
            closeSmallLavs()

            // Events computed during this level that fall back onto it are
            // stale echoes of the processed cluster, never real progress.
            while let top = heap.first, top.distance <= levelHeight + tolerance {
                _ = pop()
            }
            slav.removeAll { $0.count == 0 }
        }

        // Anything still alive never met an event (degenerate input); close
        // it in place so its faces are dropped rather than corrupted.
        for lav in slav {
            for vertex in lav.vertices {
                vertex.processed = true
            }
        }
    }

    // MARK: Level assembly

    private enum LevelEvent {
        case pick(point: Vector2, distance: Double, chain: [SkelEvent])
        case multiEdge(point: Vector2, distance: Double, chain: [SkelEvent])
        case multiSplit(point: Vector2, distance: Double, chains: [SkelChain])
    }

    /// Pops every non-obsolete event within tolerance of the lowest level.
    private func loadLevelEvents() -> [SkelEvent] {
        var level: [SkelEvent] = []
        while let first = pop() {
            if first.isObsolete { continue }
            level.append(first)
            break
        }
        guard let start = level.first else { return [] }
        while let top = heap.first, top.distance - start.distance < tolerance {
            let event = pop()!
            if !event.isObsolete { level.append(event) }
        }
        return level
    }

    /// Groups a level's events into clusters that share a meeting point or a
    /// parent vertex, then turns each cluster into chains.
    private func makeLevelEvents(_ level: [SkelEvent]) -> [LevelEvent] {
        var remaining = level
        var result: [LevelEvent] = []
        while !remaining.isEmpty {
            let seed = remaining.removeFirst()
            if seed.isObsolete { continue }
            var cluster = [seed]
            var parents = Set<Int>()
            addParents(of: seed, to: &parents)
            var i = 0
            while i < remaining.count {
                let candidate = remaining[i]
                if sharesParent(candidate, parents)
                    || (candidate.point - seed.point).length < tolerance {
                    cluster.append(remaining.remove(at: i))
                    addParents(of: candidate, to: &parents)
                    i = 0
                } else {
                    i += 1
                }
            }
            cluster.removeAll { $0.isObsolete }
            guard !cluster.isEmpty else { continue }
            result.append(levelEvent(for: cluster, at: seed.point, distance: seed.distance))
        }
        return result
    }

    private func addParents(of event: SkelEvent, to parents: inout Set<Int>) {
        switch event.kind {
        case let .edge(previous, next):
            parents.insert(previous.id)
            parents.insert(next.id)
        case let .split(parent, _):
            parents.insert(parent.id)
        }
    }

    private func sharesParent(_ event: SkelEvent, _ parents: Set<Int>) -> Bool {
        switch event.kind {
        case let .edge(previous, next):
            return parents.contains(previous.id) || parents.contains(next.id)
        case let .split(parent, _):
            return parents.contains(parent.id)
        }
    }

    /// Builds chains from one cluster: edge events link into runs by shared
    /// vertices, split events attach only when their parent is not already
    /// inside a run, and vertex-splits defer to real splits per parent.
    private func levelEvent(for cluster: [SkelEvent], at point: Vector2,
                            distance: Double) -> LevelEvent {
        // Every real split joins (one parent can strike two opposite edges
        // at once, a multi-way split); a vertex-split only stands in when
        // its parent has no real split here.
        var edgeEvents: [SkelEvent] = []
        var splitEvents: [SkelEvent] = []
        var splitParents = Set<Int>()
        for event in cluster {
            switch event.kind {
            case .edge:
                edgeEvents.append(event)
            case let .split(parent, opposite):
                if opposite != nil {
                    splitParents.insert(parent.id)
                    splitEvents.append(event)
                }
            }
        }
        for event in cluster {
            if case let .split(parent, opposite) = event.kind, opposite == nil,
               splitParents.insert(parent.id).inserted {
                splitEvents.append(event)
            }
        }

        var chains: [SkelChain] = []
        while !edgeEvents.isEmpty {
            var run = [edgeEvents.removeFirst()]
            var grew = true
            while grew {
                grew = false
                guard case let .edge(first, _) = run[0].kind,
                      case let .edge(_, last) = run[run.count - 1].kind else { break }
                for (i, event) in edgeEvents.enumerated() {
                    guard case let .edge(previous, next) = event.kind else { continue }
                    if previous === last {
                        run.append(edgeEvents.remove(at: i))
                        grew = true
                        break
                    }
                    if next === first {
                        run.insert(edgeEvents.remove(at: i), at: 0)
                        grew = true
                        break
                    }
                }
            }
            guard case let .edge(first, _) = run[0].kind,
                  case let .edge(_, last) = run[run.count - 1].kind else { continue }
            chains.append(.edges(events: run, closed: first === last))
        }
        let runs = chains
        for event in splitEvents {
            guard case let .split(parent, opposite) = event.kind else { continue }
            let inRun = runs.contains { chain in
                guard case let .edges(events, _) = chain else { return false }
                return events.contains { runEvent in
                    guard case let .edge(previous, next) = runEvent.kind else { return false }
                    return previous === parent || next === parent
                }
            }
            if !inRun {
                chains.append(.split(parent: parent, opposite: opposite))
            }
        }

        if chains.count == 1 {
            switch chains[0] {
            case let .edges(events, closed):
                return closed ? .pick(point: point, distance: distance, chain: events)
                              : .multiEdge(point: point, distance: distance, chain: events)
            case .split, .opposite:
                return .multiSplit(point: point, distance: distance, chains: chains)
            }
        }
        // A closed run beside other chains means the whole remaining loop
        // met the point: the pick absorbs it and the rest turn obsolete.
        for chain in chains {
            if case let .edges(events, true) = chain {
                return .pick(point: point, distance: distance, chain: events)
            }
        }
        return .multiSplit(point: point, distance: distance, chains: chains)
    }

    // MARK: Event processing

    private func makeNode(point: Vector2, distance: Double) -> Int {
        nodes.append(SkelNode(point: point, distance: distance))
        return nodes.count - 1
    }

    private func retire(_ vertex: SkelVertex, at node: Int) {
        guard !vertex.processed else { return }
        vertex.processed = true
        vertex.deathNode = node
        vertex.lav?.remove(vertex)
    }

    private func edgeEventVertices(_ chain: [SkelEvent]) -> [SkelVertex] {
        var seen = Set<Int>()
        var result: [SkelVertex] = []
        for event in chain {
            guard case let .edge(previous, next) = event.kind else { continue }
            for vertex in [previous, next] where seen.insert(vertex.id).inserted {
                result.append(vertex)
            }
        }
        return result
    }

    private func processPick(point: Vector2, distance: Double, chain: [SkelEvent]) {
        let node = makeNode(point: point, distance: distance)
        for vertex in edgeEventVertices(chain) {
            retire(vertex, at: node)
        }
    }

    private func processMultiEdge(point: Vector2, distance: Double, chain: [SkelEvent]) {
        guard case let .edge(chainPrevious, _) = chain[0].kind,
              case let .edge(_, chainNext) = chain[chain.count - 1].kind,
              let lav = chainPrevious.lav else { return }
        let node = makeNode(point: point, distance: distance)
        let bisector = SkelRay(origin: point,
                               direction: bisectorDirection(chainPrevious.previousEdge.direction,
                                                            chainNext.nextEdge.direction))
        let vertex = SkelVertex(id: nextVertexID, point: point, distance: distance,
                                bisector: bisector,
                                previousEdge: chainPrevious.previousEdge,
                                nextEdge: chainNext.nextEdge,
                                originNode: node)
        nextVertexID += 1
        vertices.append(vertex)
        lav.insert(vertex, before: chainPrevious)
        for participant in edgeEventVertices(chain) {
            retire(participant, at: node)
        }
        computeEvents(for: vertex)
    }

    private func processMultiSplit(point: Vector2, distance: Double, chains: [SkelChain]) {
        var chains = chains

        // Resolve each split's opposite edge against the live wavefront now,
        // because earlier events on this level may have reshaped the LAVs.
        var resolvedOpposites = Set<Int>()
        var oppositeChains: [SkelChain] = []
        var dropped = Set<Int>()
        for (i, chain) in chains.enumerated() {
            guard case let .split(_, opposite) = chain, let opposite else { continue }
            guard resolvedOpposites.insert(opposite.id).inserted else { continue }
            if let next = findOppositeVertex(edge: opposite, near: point) {
                oppositeChains.append(.opposite(edge: opposite, next: next, previous: next.prev!))
            } else {
                dropped.insert(i)
            }
        }
        chains = chains.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
        chains.append(contentsOf: oppositeChains)
        guard !chains.isEmpty else { return }

        // Sort chains around the event point so consecutive pairs bound the
        // wedges a new wavefront vertex is born into.
        let keyed = chains.map { chain in
            (chain, (chain.previousEdge.begin - point).angle, chain.previousEdge.id)
        }
        chains = keyed.sorted {
            $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2
        }.map(\.0)

        let node = makeNode(point: point, distance: distance)

        for i in chains.indices {
            let begin = chains[i]
            let end = chains[(i + 1) % chains.count]
            let previousEdge = end.previousEdge
            let nextEdge = begin.nextEdge

            var direction = bisectorDirection(previousEdge.direction, nextEdge.direction)
            let beginNext = begin.nextVertex
            let endPrevious = end.previousVertex
            // Nearly antiparallel edges leave the bisector sign to numerical
            // noise; the surviving neighbors decide it instead.
            if previousEdge.direction.dot(nextEdge.direction) < -0.97 {
                let toCenter = (point - endPrevious.point).normalized
                let fromCenter = (beginNext.point - point).normalized
                let prediction = bisectorDirection(toCenter, fromCenter)
                if direction.dot(prediction) < 0 { direction = direction * -1 }
            }

            let vertex = SkelVertex(id: nextVertexID, point: point, distance: distance,
                                    bisector: SkelRay(origin: point, direction: direction),
                                    previousEdge: previousEdge, nextEdge: nextEdge,
                                    originNode: node)
            nextVertexID += 1
            vertices.append(vertex)

            if beginNext.lav === endPrevious.lav, let lav = beginNext.lav {
                // Cut the span between the two chains out into its own LAV,
                // seeded by the new vertex.
                let fresh = LAV()
                slav.append(fresh)
                fresh.append(vertex)
                var moved: [SkelVertex] = []
                var current = beginNext
                var guardCount = lav.count
                while guardCount > 0 {
                    guardCount -= 1
                    let following = current.next!
                    moved.append(current)
                    if current === endPrevious { break }
                    current = following
                }
                for v in moved {
                    v.lav?.remove(v)
                    fresh.insert(v, before: fresh.head!)
                }
            } else if let lav = beginNext.lav, endPrevious.lav != nil {
                // The chains bridge two LAVs: merge the far one in before the
                // near vertex, then drop the new vertex between them.
                let merged = endPrevious.lav?.vertices ?? []
                if let start = merged.firstIndex(where: { $0 === endPrevious }) {
                    let ordered = Array(merged[(start + 1)...] + merged[...start])
                    for v in ordered {
                        v.lav?.remove(v)
                        lav.insert(v, before: beginNext)
                    }
                }
                lav.insert(vertex, after: endPrevious)
            } else if let lav = beginNext.lav {
                lav.insert(vertex, before: beginNext)
            }

            computeEvents(for: vertex)
        }

        // Every vertex the event point swallowed dies here: split parents
        // and any edge chain's participants. Opposite-edge chains survive.
        for chain in chains {
            switch chain {
            case let .split(parent, _):
                retire(parent, at: node)
            case let .edges(events, _):
                for vertex in edgeEventVertices(events) {
                    retire(vertex, at: node)
                }
            case .opposite:
                break
            }
        }
    }

    /// Degenerate simultaneous events can leave two wavefront vertices at
    /// one point flanking a zero-length front: a ghost corner whose mutual
    /// event always lands back on the current level and gets purged, so the
    /// LAV would starve. Fuse each such pair into the single vertex it
    /// should have been and let it look for events from there.
    private func mergeCoincidentNeighbors() {
        var again = true
        while again {
            again = false
            for lav in slav where lav.count >= 3 {
                for vertex in lav.vertices {
                    guard vertex.lav === lav, let next = vertex.next, next !== vertex,
                          (vertex.point - next.point).length < tolerance else { continue }
                    let distance = max(vertex.distance, next.distance)
                    let node = makeNode(point: vertex.point, distance: distance)
                    var direction = bisectorDirection(vertex.previousEdge.direction,
                                                      next.nextEdge.direction)
                    if vertex.previousEdge.direction.dot(next.nextEdge.direction) < -0.97,
                       let before = vertex.prev, let after = next.next {
                        let toHere = (vertex.point - before.point).normalized
                        let fromHere = (after.point - vertex.point).normalized
                        if direction.dot(bisectorDirection(toHere, fromHere)) < 0 {
                            direction = direction * -1
                        }
                    }
                    let merged = SkelVertex(id: nextVertexID, point: vertex.point,
                                            distance: distance,
                                            bisector: SkelRay(origin: vertex.point,
                                                              direction: direction),
                                            previousEdge: vertex.previousEdge,
                                            nextEdge: next.nextEdge,
                                            originNode: node)
                    nextVertexID += 1
                    vertices.append(merged)
                    lav.insert(merged, before: vertex)
                    retire(vertex, at: node)
                    retire(next, at: node)
                    computeEvents(for: merged)
                    again = true
                    break
                }
            }
        }
    }

    /// A LAV down to two vertices is a closed lens: the pair connects into
    /// the final ridge arc between where each stopped.
    private func closeSmallLavs() {
        for lav in slav where lav.count > 0 && lav.count <= 2 {
            let pair = lav.vertices
            if pair.count == 2 {
                bridges.append((nodeA: pair[0].originNode, nodeB: pair[1].originNode,
                                edgeA: pair[0].nextEdge.id, edgeB: pair[0].previousEdge.id))
            }
            for vertex in pair {
                vertex.processed = true
                vertex.deathNode = vertex.originNode
                lav.remove(vertex)
            }
        }
    }

    // MARK: Event discovery

    private func push(_ point: Vector2, _ distance: Double, _ kind: SkelEvent.Kind) {
        heap.append(SkelEvent(point: point, distance: distance, kind: kind, seq: nextSeq))
        nextSeq += 1
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard eventBefore(heap[child], heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private func pop() -> SkelEvent? {
        guard let first = heap.first else { return nil }
        heap[0] = heap[heap.count - 1]
        heap.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { break }
            let right = left + 1
            var smallest = left
            if right < heap.count, eventBefore(heap[right], heap[left]) { smallest = right }
            guard eventBefore(heap[smallest], heap[parent]) else { break }
            heap.swapAt(parent, smallest)
            parent = smallest
        }
        return first
    }

    private func eventBefore(_ a: SkelEvent, _ b: SkelEvent) -> Bool {
        a.distance != b.distance ? a.distance < b.distance : a.seq < b.seq
    }

    private func computeEvents(for vertex: SkelVertex) {
        let closest = enqueueCloserEdgeEvent(for: vertex)
        enqueueSplitEvents(for: vertex, closerThan: closest)
    }

    /// Queues the nearer of the vertex's two edge events (both when they tie
    /// within tolerance) and returns the winning source distance, the cap a
    /// split candidate must beat.
    private func enqueueCloserEdgeEvent(for vertex: SkelVertex) -> Double? {
        guard let next = vertex.next, let previous = vertex.prev else { return nil }
        let p1 = bisectorMeeting(vertex, next)
        let p2 = bisectorMeeting(previous, vertex)
        guard p1 != nil || p2 != nil else { return nil }
        let d1 = p1.map { ($0 - vertex.point).length } ?? .greatestFiniteMagnitude
        let d2 = p2.map { ($0 - vertex.point).length } ?? .greatestFiniteMagnitude
        if let p1, d1 - tolerance < d2 {
            push(p1, vertex.nextEdge.distance(to: p1), .edge(previous: vertex, next: next))
        }
        if let p2, d2 - tolerance < d1 {
            push(p2, vertex.previousEdge.distance(to: p2), .edge(previous: previous, next: vertex))
        }
        return min(d1, d2)
    }

    private func enqueueEdgeEvent(previous: SkelVertex, next: SkelVertex) {
        guard let point = bisectorMeeting(previous, next) else { return }
        push(point, previous.nextEdge.distance(to: point),
             .edge(previous: previous, next: next))
    }

    /// Where two neighboring bisectors meet, including the head-on collinear
    /// case (parallel wavefront ends approaching along one line).
    private func bisectorMeeting(_ a: SkelVertex, _ b: SkelVertex) -> Vector2? {
        let ra = a.bisector, rb = b.bisector
        let denom = ra.direction.cross(rb.direction)
        if abs(denom) > 1e-10 {
            let t = (rb.origin - ra.origin).cross(rb.direction) / denom
            let u = (rb.origin - ra.origin).cross(ra.direction) / denom
            guard t > tolerance || u > tolerance else { return nil }
            guard t > -tolerance, u > -tolerance else { return nil }
            let point = ra.origin + ra.direction * t
            if (point - a.point).length < tolerance || (point - b.point).length < tolerance {
                return nil
            }
            return point
        }
        // Parallel: only the facing collinear case meets, at the point where
        // both fronts carry equal distance.
        let offset = rb.origin - ra.origin
        guard abs(ra.direction.cross(offset)) < tolerance,
              ra.direction.dot(rb.direction) < 0,
              offset.dot(ra.direction) > tolerance else { return nil }
        let speed = ra.direction.dot(a.nextEdge.normal)
        guard abs(speed) > 1e-12 else { return nil }
        let gap = offset.length
        let s = (gap + (b.distance - a.distance) / speed) / 2
        guard s > tolerance, s < gap + tolerance else { return nil }
        return ra.origin + ra.direction * s
    }

    /// Queues split candidates for a vertex against every region edge whose
    /// initial wedge its bisector can reach, skipping candidates farther
    /// from the vertex than its own nearest edge event.
    private func enqueueSplitEvents(for vertex: SkelVertex, closerThan: Double?) {
        for edge in edges {
            if edge === vertex.previousEdge || edge === vertex.nextEdge { continue }
            guard let candidate = splitCandidate(vertex: vertex, edge: edge) else { continue }
            if let closerThan, (candidate.point - vertex.point).length > closerThan + tolerance {
                continue
            }
            push(candidate.point, candidate.distance,
                 .split(parent: vertex, opposite: candidate.vertexHit ? nil : edge))
        }
    }

    private struct SplitCandidate {
        var point: Vector2
        var distance: Double
        var vertexHit: Bool
    }

    /// The classic candidate construction: the vertex's bisector meets the
    /// bisector of the angle between one of its edges and the tested edge,
    /// and the meeting point must land inside the tested edge's initial
    /// wedge. Landing on the wedge boundary is a vertex-split.
    private func splitCandidate(vertex: SkelVertex, edge: SkelEdge) -> SplitCandidate? {
        // The tested edge's line must lie ahead of the vertex.
        guard vertex.bisector.intersectLine(through: edge.begin, along: edge.direction,
                                            minAhead: tolerance) != nil else { return nil }

        // Pair the tested edge with whichever of the vertex's edges is less
        // parallel to it, so the angle between them is well conditioned.
        let dotPrevious = abs(edge.direction.dot(vertex.previousEdge.direction))
        let dotNext = abs(edge.direction.dot(vertex.nextEdge.direction))
        guard dotPrevious + dotNext < 2 - 1e-10 else { return nil }
        let own = dotPrevious > dotNext ? vertex.nextEdge : vertex.previousEdge

        let denom = own.direction.cross(edge.direction)
        guard abs(denom) > 1e-12 else { return nil }
        let t = (edge.begin - own.begin).cross(edge.direction) / denom
        let corner = own.begin + own.direction * t
        let axis = bisectorDirection(own.direction, edge.direction)

        guard let candidate = vertex.bisector.intersectLine(through: corner, along: axis,
                                                            minAhead: tolerance)
        else { return nil }

        let sideBegin = edge.bisectorAtBegin.side(of: candidate)
        let sideEnd = edge.bisectorAtEnd.side(of: candidate)
        guard sideBegin <= tolerance, sideEnd >= -tolerance else { return nil }
        let vertexHit = sideBegin >= -tolerance || sideEnd <= tolerance
        return SplitCandidate(point: candidate,
                              distance: edge.distance(to: candidate),
                              vertexHit: vertexHit)
    }

    /// Finds the live wavefront vertex whose incoming side is the shrunk
    /// remainder of `edge` spanning the event point: project the point onto
    /// the edge and pick the segment whose span contains it.
    private func findOppositeVertex(edge: SkelEdge, near point: Vector2) -> SkelVertex? {
        var candidates: [SkelVertex] = []
        for lav in slav {
            for vertex in lav.vertices where vertex.previousEdge === edge {
                candidates.append(vertex)
            }
        }
        if candidates.count <= 1 { return candidates.first }
        let center = (point - edge.begin).dot(edge.direction)
        for end in candidates {
            guard let begin = end.prev else { continue }
            let a = (begin.point - edge.begin).dot(edge.direction)
            let b = (end.point - edge.begin).dot(edge.direction)
            if (a < center && center < b) || (b < center && center < a) {
                return end
            }
        }
        // Fall back to whichever LAV surrounds the point.
        for end in candidates {
            guard let lav = end.lav else { continue }
            let ring = lav.vertices.map(\.point)
            if pointInRing(point, ring) { return end }
        }
        return candidates.first
    }
}

// MARK: - Shared math (file-private)

/// The direction a wavefront vertex moves between two edge directions:
/// the interior angle bisector, stable through straight, convex, reflex,
/// and degenerate needle corners.
private func bisectorDirection(_ d1: Vector2, _ d2: Vector2) -> Vector2 {
    if d1.dot(d2) > 0 {
        return (d1.perpendicular + d2.perpendicular).normalized
    }
    var direction = d2 - d1
    if direction.lengthSquared < 1e-24 {
        return d1.perpendicular
    }
    if d1.perpendicular.dot(d2) < 0 {
        direction = direction * -1
    }
    return direction.normalized
}

/// Twice the signed area of a ring (positive when the interior is on the
/// left of its directed edges).
private func ringArea(_ ring: [Vector2]) -> Double {
    var sum = 0.0
    for i in ring.indices {
        let a = ring[i], b = ring[(i + 1) % ring.count]
        sum += a.x * b.y - b.x * a.y
    }
    return sum / 2
}

/// Even-odd point-in-ring test, used only to sort out which rings are holes.
private func pointInRing(_ point: Vector2, _ ring: [Vector2]) -> Bool {
    var inside = false
    var j = ring.count - 1
    for i in ring.indices {
        let a = ring[i], b = ring[j]
        if (a.y > point.y) != (b.y > point.y),
           point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
            inside.toggle()
        }
        j = i
    }
    return inside
}

/// Strict lexicographic point order, the deterministic rule canonical
/// arc directions and inset ring starts use.
private func pointBefore(_ a: Vector2, _ b: Vector2) -> Bool {
    a.x != b.x ? a.x < b.x : a.y < b.y
}
