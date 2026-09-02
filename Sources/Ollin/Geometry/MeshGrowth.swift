import Foundation

/// What decides where a growing surface grows fastest.
///
/// This is the whole character of the result, and it is worth being clear about
/// what it does and does not change. A surface here has nothing pushing it
/// outward: the only forces run along its own edges, which lie in the surface.
/// So it cannot answer new area by getting bigger the way an inflating balloon
/// does. Whatever area it makes, it has to fold. *Every* driver folds.
///
/// What the driver decides is **where** and **at what scale**. Growing evenly
/// folds evenly, all over, at one size. Growing in patches folds into lobes with
/// smooth ground between them. That is the difference between a brain coral and
/// a branching one.
public enum GrowthDriver {

    /// Every vertex grows at the same rate, so the surface folds uniformly all
    /// over at a single scale, the way a brain coral does. The useful baseline:
    /// it shows what growth alone produces, before any pattern steers it.
    case uniform

    /// Grow fastest where the surface already bulges outward. Because a bulge
    /// that grows becomes a bigger bulge, this feeds back on itself: small
    /// irregularities sharpen into lobes and the lobes ruffle at their rims.
    case curvature

    /// Grow by your own rule, given each vertex's position and outward normal
    /// and returning a rate from 0 to 1. This is how you grow only the rim of a
    /// disc (a leaf margin), only the top of a form, or along a noise field.
    case field((Vector3, Vector3) -> Double)

    /// Grow where a reaction-diffusion pattern has collected on the surface.
    /// The pattern develops in the surface as the surface grows, so the two feed
    /// each other: the chemistry decides where new area appears, and the new
    /// area gives the chemistry more room to spread into. This is the coral
    /// driver.
    case chemical(SurfaceChemistry)
}

/// A surface that grows: a triangle mesh whose vertices push apart where a
/// growth field tells them to, which makes new surface area, which the mesh has
/// to fold to accommodate. Held across frames and stepped, it turns a sphere
/// into a coral, a disc into a ruffled leaf, and a torus into something the
/// original shape does not obviously predict.
///
/// Four things happen every step:
///
/// - **Growth** pushes connected vertices apart, more where the `driver` says to
///   grow faster. This is what makes new area. The push runs along the edges,
///   which lie in the surface, so it can never inflate the form outward: the new
///   area has nowhere to go but into folds.
/// - **Repulsion** pushes apart any two vertices that come near each other
///   without being near along the surface, which is what stops a fold passing
///   through its neighbor and makes the folds stack instead.
/// - **Remeshing** keeps the triangles near a target size and shape: long edges
///   split, short ones collapse, and badly connected ones flip. Without it the
///   surface would just stretch its existing triangles into slivers instead of
///   gaining detail.
/// - **Relaxation** evens out the spacing within the surface, and damps how
///   sharply the surface bends, which is what sets how big the folds are.
///
/// The product is a `Mesh`, so everything else in 3D applies: materials,
/// lighting, shadows, subdivision, export.
///
/// ```swift
/// // Held across frames, seeded once:
/// let coral = MeshGrowth(mesh: .icosphere(subdivisions: 3),
///                        driver: .chemical(.coral), seed: 7)
///
/// // In draw():
/// coral.step()
/// material(.dielectric(roughness: 0.4))
/// drawMesh(coral.mesh)
/// ```
///
/// Growth is deliberately slow: a form takes hundreds of steps to develop, the
/// way the thing it imitates takes a season. Cost rises with the vertex count,
/// which climbs as the surface grows, so `maxVertices` is a ceiling rather than
/// a suggestion. Past it the surface stops making new area and only relaxes.
public final class MeshGrowth {

    // MARK: Parameters

    /// What decides where the surface grows fastest.
    public var driver: GrowthDriver

    /// The triangle size the remesher aims for. Everything else in the
    /// simulation is measured against it, so it sets the scale of every detail
    /// the surface can hold: halving it doubles the resolution of the ruffles
    /// and roughly quadruples the cost.
    public var edgeLength: Double

    /// How much longer than `edgeLength` an edge wants to be where growth is at
    /// its maximum. This is the growth rate: at 0 the surface only relaxes, and
    /// larger values make area faster.
    public var growthRate: Double = 0.5

    /// How hard an edge pulls back toward the length it wants.
    public var springStrength: Double = 0.25

    /// How near two separate parts of the surface may come before they push
    /// apart. Raising it holds the folds further off each other and opens the
    /// form out; lowering it lets them nest tightly.
    ///
    /// Only vertices that are far apart *along the surface* count as separate,
    /// so this is genuinely self-avoidance. Pushing it past about three times
    /// `edgeLength` starts to include neighbors that are legitimately that close
    /// on a smooth surface, and the whole form inflates rather than folding.
    public var repulsionRadius: Double

    /// How hard unconnected parts of the surface push each other apart.
    public var repulsion: Double = 0.6

    /// How strongly each vertex slides toward the middle of its neighbors. The
    /// motion is kept in the surface, so this evens out spacing without
    /// smoothing the shape away.
    public var relaxation: Double = 0.2

    /// How much the surface resists bending, which is what sets the size of the
    /// folds.
    ///
    /// A sheet with no stiffness buckles at the smallest scale it can, so the
    /// folds come out the size of a triangle and the form reads as crumpled.
    /// Resisting bending makes small wrinkles expensive and large gentle ones
    /// cheap, so the same growth gathers into broader waves. Raise it for
    /// smooth, open ruffles; drop it to zero for something closer to crushed
    /// paper.
    public var stiffness: Double = 0.35

    /// A ceiling on the vertex count. Growth stops making new area once the
    /// surface reaches it, so raise it for more detail and lower it to keep a
    /// long run interactive.
    public var maxVertices: Int

    /// How many reaction steps run per growth step, when the driver is
    /// `.chemical`. The chemistry needs to develop faster than the surface moves
    /// or the pattern never gets ahead of the growth it is meant to be steering.
    public var chemistrySteps: Int = 8

    /// How many steps' worth of chemistry run on their own before the first
    /// growth step, when the driver is `.chemical`.
    ///
    /// The reaction has to organize into a pattern before it can steer
    /// anything, so a chemical growth otherwise spends its opening steps barely
    /// moving while the patches sort themselves out. Settling runs that opening
    /// work all at once, the moment the first step is taken: the surface is
    /// refined to the target triangle size (holding still), the chemistry
    /// organizes on it, and growth answers a formed pattern from the first
    /// step. Each unit is one growth step's ration of reaction
    /// (`chemistrySteps` iterations), so a value of 60 hands the pattern the
    /// head start it would have taken 60 steps to earn. 0, the default, skips
    /// it; the other drivers ignore it.
    public var settleSteps: Int = 0

    // MARK: State

    private var positions: [Vector3]
    private var triangles: [MeshTriangle]
    /// Per-vertex scalar channels carried through remeshing (the two chemical
    /// concentrations). Interpolated at a split and averaged at a collapse, so a
    /// pattern survives the topology changing underneath it.
    private var channels: [[Double]]
    /// Which triangles use each vertex. Maintained through every topological
    /// change rather than rebuilt, since it is what makes the changes local.
    private var incidence: [[Int]]
    private var rng: SplitMix64
    private var cachedMesh: Mesh?
    private var hasSettled = false

    /// How many steps have run.
    public private(set) var stepCount = 0

    // MARK: Init

    /// A growth seeded with a starting surface.
    ///
    /// The starting mesh sets the scale: unless you name an `edgeLength`, the
    /// mean edge length of the mesh you pass is used, so a coarse seed grows
    /// coarse folds and a fine one grows fine ones. Coincident vertices are
    /// welded first, so a flat-shaded cage grows as one surface rather than
    /// falling apart into plates.
    ///
    /// - Parameters:
    ///   - mesh: The surface to start from. Closed surfaces (a sphere, a torus)
    ///     grow into solid forms; open ones (a disc, a ribbon) keep their rim
    ///     and ruffle along it.
    ///   - driver: What decides where the surface grows fastest.
    ///   - edgeLength: The triangle size to hold, or `nil` to take it from the
    ///     starting mesh.
    ///   - maxVertices: The vertex-count ceiling.
    ///   - seed: The random seed. A little noise is added to the starting
    ///     positions to break its symmetry, because a perfectly symmetric
    ///     surface has no reason to buckle one way rather than another.
    public init(mesh: Mesh,
                driver: GrowthDriver = .curvature,
                edgeLength: Double? = nil,
                maxVertices: Int = 12000,
                seed: UInt64 = 0) {
        self.driver = driver
        self.maxVertices = Swift.max(maxVertices, 4)
        self.rng = SplitMix64(seed: seed)

        let welded = WeldedMesh(mesh)
        self.positions = welded.positions
        self.triangles = welded.triangles

        let mean = MeshGrowth.meanEdgeLength(positions: positions, triangles: triangles)
        let resolved = edgeLength ?? (mean > 0 ? mean : 1)
        self.edgeLength = resolved
        self.repulsionRadius = resolved * 2

        self.channels = []
        self.incidence = []
        rebuildIncidence()

        if case .chemical = driver { seedChemistry() }

        // Break the symmetry. A sphere with no noise on it grows into a slightly
        // larger sphere forever, because every direction is equally good.
        let jitter = resolved * 0.02
        for v in positions.indices {
            positions[v] = positions[v] + Vector3(Double.random(in: -1 ... 1, using: &rng),
                                                  Double.random(in: -1 ... 1, using: &rng),
                                                  Double.random(in: -1 ... 1, using: &rng)) * jitter
        }
    }

    // MARK: Reading the surface

    /// The surface as it stands, with smooth normals. Rebuilt only when the
    /// surface has actually changed, so reading it every frame is free.
    public var mesh: Mesh {
        if let cachedMesh { return cachedMesh }
        var indices: [UInt32] = []
        indices.reserveCapacity(triangles.count * 3)
        for t in triangles where !t.isDegenerate {
            indices.append(UInt32(t.a))
            indices.append(UInt32(t.b))
            indices.append(UInt32(t.c))
        }
        let built = Mesh(positions: positions, indices: indices).generatingSmoothNormals()
        cachedMesh = built
        return built
    }

    /// How many vertices the surface has.
    public var vertexCount: Int { positions.count }

    /// The growth field's value at each vertex, 0 to 1, as it was on the last
    /// step. Empty before the first step.
    public private(set) var growthField: [Double] = []

    /// The reaction-diffusion concentration at each vertex when the driver is
    /// `.chemical`, matching `mesh.positions` by index. Empty otherwise.
    public var chemistry: [Double] { channels.count > 1 ? channels[1] : [] }

    // MARK: Stepping

    /// Advance the growth by `steps` steps.
    public func step(_ steps: Int = 1) {
        for _ in 0 ..< Swift.max(steps, 0) { stepOnce() }
    }

    private func stepOnce() {
        guard positions.count >= 3, !triangles.isEmpty else { return }

        // The settle runs once, all at once, so a live sketch never sits
        // through frames of a still surface waiting for the pattern to form.
        if !hasSettled {
            hasSettled = true
            if case let .chemical(settings) = driver, settleSteps > 0 { settle(settings) }
        }

        let rings = ringTable()
        let normals = vertexNormals()

        if case let .chemical(settings) = driver { advanceChemistry(settings) }
        growthField = growthRates(normals: normals)

        applyForces(rings: rings)
        remesh()

        stepCount += 1
        cachedMesh = nil
    }

    // MARK: Growth field

    private func growthRates(normals: [Vector3]) -> [Double] {
        // At the ceiling the remesher can no longer add vertices, so growth has
        // to stop as well. Left running, the springs would keep pulling toward a
        // rest length no longer reachable by splitting and would simply stretch
        // the existing triangles out of shape.
        guard positions.count < maxVertices else {
            return [Double](repeating: 0, count: positions.count)
        }
        switch driver {
        case .uniform:
            return [Double](repeating: 1, count: positions.count)

        case .curvature:
            let ops = MeshOperators(positions: positions, triangles: triangles)
            let curvature = ops.meanCurvatureNormals(of: positions)
            // Mean curvature carries units of 1 over length, so it is scaled by
            // the form's own size to become a plain 0-to-1 rate: a sphere reads
            // about 1 all over, a flat sheet 0, a saddle 0.
            let scale = Swift.max(extent() * 0.5, 1e-9)
            return (0 ..< positions.count).map { v in
                let signed = curvature[v].dot(normals[v]) * 0.5 * scale
                return Swift.min(Swift.max(signed, 0), 1)
            }

        case let .field(rule):
            return (0 ..< positions.count).map { v in
                Swift.min(Swift.max(rule(positions[v], normals[v]), 0), 1)
            }

        case .chemical:
            guard channels.count > 1 else { return [Double](repeating: 0, count: positions.count) }
            return channels[1].map { Swift.min(Swift.max($0, 0), 1) }
        }
    }

    private func seedChemistry() {
        var substrate = [Double](repeating: 1, count: positions.count)
        var values = [Double](repeating: 0, count: positions.count)
        guard !positions.isEmpty else {
            channels = [substrate, values]
            return
        }
        // Floored at a few edge lengths, or a patch on a fine mesh diffuses away
        // before the reaction can take hold.
        let reach = Swift.max(extent() * 0.08, edgeLength * 3)
        // Half substrate, a quarter reagent: the standard seed. A patch of pure
        // reagent has nothing to react with and decays instead of igniting.
        for _ in 0 ..< 8 {
            let center = positions[Int.random(in: 0 ..< positions.count, using: &rng)]
            for v in positions.indices where positions[v].distance(to: center) < reach {
                substrate[v] = 0.5
                values[v] = 0.25
            }
        }
        channels = [substrate, values]
    }

    /// The head start `settleSteps` asks for: refine the surface to the target
    /// triangle size, then run the opening chemistry on it all at once.
    ///
    /// The refinement is not optional. The reaction can only establish at the
    /// scale it will run at: on the coarse seed cage the seeded patch is a
    /// vertex or two wide and decays before igniting, so chemistry run there
    /// dies at exactly zero and the settle is simply lost. The surface holds
    /// still through all of it; only the triangulation changes.
    private func settle(_ settings: SurfaceChemistry) {
        var lastCount = -1
        var passes = 0
        while positions.count != lastCount, passes < 12 {
            lastCount = positions.count
            remesh()
            passes += 1
        }
        for _ in 0 ..< settleSteps { advanceChemistry(settings) }
    }

    private func advanceChemistry(_ settings: SurfaceChemistry) {
        guard channels.count > 1 else { return }
        let ops = MeshOperators(positions: positions, triangles: triangles)
        var substrate = channels[0], values = channels[1]
        for _ in 0 ..< Swift.max(chemistrySteps, 0) {
            (substrate, values) = grayScottStep(operators: ops,
                                                substrate: substrate,
                                                values: values,
                                                chemistry: settings)
        }
        channels[0] = substrate
        channels[1] = values
    }

    // MARK: Forces

    private func applyForces(rings: [[Int]]) {
        var force = [Vector3](repeating: .zero, count: positions.count)

        // Growth: every edge wants to be longer than the target where the growth
        // field is high, and the spring pulling it back to that length is what
        // pushes the surface apart.
        for t in triangles where !t.isDegenerate {
            addSpring(t.a, t.b, &force)
            addSpring(t.b, t.c, &force)
            addSpring(t.c, t.a, &force)
        }

        // Self-avoidance. Without it the surface simply passes through itself
        // and the folds mean nothing.
        addRepulsion(rings: rings, into: &force)

        // A step longer than a fraction of a triangle would jump a vertex past
        // its neighbors, which the remesher cannot undo.
        let limit = edgeLength * 0.3
        for v in positions.indices {
            var d = force[v]
            let len = d.length
            if len > limit { d = d * (limit / len) }
            positions[v] = positions[v] + d
        }
    }

    /// Each edge is counted twice (once from each of its two triangles), which
    /// is harmless: it doubles every spring equally and `springStrength`
    /// absorbs it.
    private func addSpring(_ i: Int, _ j: Int, _ force: inout [Vector3]) {
        let delta = positions[j] - positions[i]
        let d = delta.length
        guard d > 1e-12 else { return }
        let rate = growthField.isEmpty ? 0 : (growthField[i] + growthField[j]) * 0.5
        let rest = edgeLength * (1 + growthRate * rate)
        let pull = (d - rest) * springStrength
        let dir = delta * (1 / d)
        force[i] = force[i] + dir * pull
        force[j] = force[j] - dir * pull
    }

    private func addRepulsion(rings: [[Int]], into force: inout [Vector3]) {
        guard repulsion > 0, repulsionRadius > 0 else { return }
        let count = positions.count
        let cell = repulsionRadius

        // A flat hash grid rather than a dictionary of buckets. Every vertex
        // looks at the twenty-seven cells around it, so a dictionary would be
        // asked tens of thousands of times a step and it dominated the profile.
        // Vertices are counting-sorted into a table instead, which is a couple
        // of linear passes and no allocation per cell.
        //
        // Two cells can hash to the same slot. That is harmless: a collision
        // only offers extra candidates, and every candidate is distance-tested
        // anyway. Filling in vertex order also keeps each slot's contents in a
        // fixed order, so the forces sum the same way twice.
        let slots = Swift.max(count * 2, 64)
        var starts = [Int](repeating: 0, count: slots + 1)
        var slotOf = [Int](repeating: 0, count: count)
        for v in 0 ..< count {
            let slot = MeshGrowth.slot(Cell(positions[v], cell), slots)
            slotOf[v] = slot
            starts[slot + 1] += 1
        }
        for i in 1 ... slots { starts[i] += starts[i - 1] }
        var items = [Int](repeating: 0, count: count)
        var cursor = starts
        for v in 0 ..< count {
            items[cursor[slotOf[v]]] = v
            cursor[slotOf[v]] += 1
        }

        let r2 = repulsionRadius * repulsionRadius
        // Membership in the two-hop neighborhood is asked once per candidate
        // pair, which is often enough that a linear scan of it shows up in a
        // profile. Stamping each vertex with the neighborhood currently being
        // tested makes the test a single comparison.
        var stamp = [Int](repeating: -1, count: count)
        // Two of the twenty-seven cells can share a slot, and scanning that slot
        // once per cell would count everything in it twice. Marked the same way
        // the neighborhood is, so each slot is read at most once per vertex.
        var visited = [Int](repeating: -1, count: slots)
        for v in 0 ..< count {
            let p = positions[v]
            let base = Cell(p, cell)
            var push = Vector3.zero
            // The two-hop neighborhood, marked straight into the stamp rather
            // than gathered into a set first: it is only ever asked about, never
            // enumerated, so materializing one array per vertex is pure cost.
            stamp[v] = v
            for n in rings[v] {
                stamp[n] = v
                for m in rings[n] { stamp[m] = v }
            }
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    for dz in -1 ... 1 {
                        let slot = MeshGrowth.slot(Cell(x: base.x + dx, y: base.y + dy, z: base.z + dz), slots)
                        if visited[slot] == v { continue }
                        visited[slot] = v
                        for index in starts[slot] ..< starts[slot + 1] {
                            let other = items[index]
                            // Anything within two hops is held in place by the
                            // springs already and sits this close legitimately.
                            if stamp[other] == v { continue }
                            let diff = p - positions[other]
                            let d2 = diff.lengthSquared
                            guard d2 < r2, d2 > 1e-18 else { continue }
                            let d = d2.squareRoot()
                            let falloff = (repulsionRadius - d) / repulsionRadius
                            push = push + diff * (falloff * repulsion / d)
                        }
                    }
                }
            }
            force[v] = force[v] + push
        }
    }

    private static func slot(_ c: Cell, _ slots: Int) -> Int {
        let mixed = (c.x &* 73_856_093) ^ (c.y &* 19_349_663) ^ (c.z &* 83_492_791)
        return Swift.abs(mixed % slots)
    }

    // MARK: Remeshing

    /// One pass of isotropic remeshing: split what is too long, collapse what is
    /// too short, flip what is badly connected, then even out the spacing. The
    /// thresholds are the standard ones, a third longer and a fifth shorter than
    /// the target, which is a wide enough band that an edge does not oscillate
    /// between being split and collapsed.
    private func remesh() {
        splitLongEdges()
        // Which vertices sit on an open rim can only change where the surface
        // gains vertices, and the three passes below all decline to touch the
        // rim, so this is computed once after the split rather than by each of
        // them.
        var table = edgeTable()
        // A collapse renumbers the vertices, so the table has to be rebuilt
        // after one actually happened.
        if collapseShortEdges(edges: table.edges, boundary: table.boundary) { table = edgeTable() }
        flipForValence(edges: table.edges, boundary: table.boundary)
        relax(boundary: table.boundary)
    }

    private func splitLongEdges() {
        guard positions.count < maxVertices else { return }
        let limit = edgeLength * 4 / 3
        let limit2 = limit * limit

        var midpoint: [MeshEdge: Int] = [:]
        for t in triangles where !t.isDegenerate {
            for (i, j) in [(t.a, t.b), (t.b, t.c), (t.c, t.a)] {
                let e = MeshEdge(i, j)
                guard midpoint[e] == nil else { continue }
                guard positions.count + midpoint.count < maxVertices else { continue }
                guard positions[i].distanceSquared(to: positions[j]) > limit2 else { continue }
                midpoint[e] = -1
            }
        }
        guard !midpoint.isEmpty else { return }

        // Assign the new vertices in a fixed order so a run reproduces.
        for e in midpoint.keys.sorted() {
            let m = (positions[e.low] + positions[e.high]) * 0.5
            midpoint[e] = positions.count
            positions.append(m)
            for c in channels.indices {
                channels[c].append((channels[c][e.low] + channels[c][e.high]) * 0.5)
            }
        }

        var out: [MeshTriangle] = []
        out.reserveCapacity(triangles.count * 2)
        for t in triangles where !t.isDegenerate {
            let mab = midpoint[MeshEdge(t.a, t.b)]
            let mbc = midpoint[MeshEdge(t.b, t.c)]
            let mca = midpoint[MeshEdge(t.c, t.a)]
            switch (mab, mbc, mca) {
            case (nil, nil, nil):
                out.append(t)
            case let (m?, nil, nil):
                out.append(MeshTriangle(t.a, m, t.c)); out.append(MeshTriangle(m, t.b, t.c))
            case let (nil, m?, nil):
                out.append(MeshTriangle(t.b, m, t.a)); out.append(MeshTriangle(m, t.c, t.a))
            case let (nil, nil, m?):
                out.append(MeshTriangle(t.c, m, t.b)); out.append(MeshTriangle(m, t.a, t.b))
            case let (p?, q?, nil):
                out.append(MeshTriangle(p, t.b, q))
                out.append(MeshTriangle(t.a, p, q)); out.append(MeshTriangle(t.a, q, t.c))
            case let (nil, q?, r?):
                out.append(MeshTriangle(q, t.c, r))
                out.append(MeshTriangle(t.b, q, r)); out.append(MeshTriangle(t.b, r, t.a))
            case let (p?, nil, r?):
                out.append(MeshTriangle(r, t.a, p))
                out.append(MeshTriangle(t.c, r, p)); out.append(MeshTriangle(t.c, p, t.b))
            case let (p?, q?, r?):
                out.append(MeshTriangle(t.a, p, r)); out.append(MeshTriangle(p, t.b, q))
                out.append(MeshTriangle(r, q, t.c)); out.append(MeshTriangle(p, q, r))
            }
        }
        triangles = out
        rebuildIncidence()
    }

    /// Returns whether anything was collapsed, which tells the caller its
    /// vertex numbering has changed.
    @discardableResult
    private func collapseShortEdges(edges: [MeshEdge], boundary: [Bool]) -> Bool {
        let limit = edgeLength * 4 / 5
        let ceiling = edgeLength * 4 / 3
        var removed = [Bool](repeating: false, count: positions.count)
        var collapsed = false

        for e in edges {
            let (a, b) = (e.low, e.high)
            guard !removed[a], !removed[b] else { continue }
            guard !boundary[a], !boundary[b] else { continue }
            guard positions[a].distance(to: positions[b]) < limit else { continue }

            let shared = trianglesOn(a, b)
            guard shared.count == 2 else { continue }

            let ringA = ring(of: a), ringB = ring(of: b)
            // The link condition. If the two rings meet anywhere other than the
            // two vertices opposite the edge, welding them would fuse parts of
            // the surface that are not actually adjacent.
            let common = Set(ringA).intersection(ringB)
            guard common.count == 2 else { continue }

            let target = (positions[a] + positions[b]) * 0.5
            // The collapse must not leave an edge so long the next pass would
            // just split it again, and must not turn a triangle inside out.
            // Both rings, not just the one being merged in: moving `a` to the
            // midpoint lengthens its own surviving edges too, and checking only
            // one side lets a collapse leave an edge the next pass has to split
            // straight back.
            var safe = true
            for n in ringA + ringB where n != a && n != b {
                if target.distance(to: positions[n]) > ceiling { safe = false; break }
            }
            if safe { safe = collapseKeepsOrientation(a: a, b: b, to: target, dropping: shared) }
            guard safe else { continue }

            positions[a] = target
            for c in channels.indices {
                channels[c][a] = (channels[c][a] + channels[c][b]) * 0.5
            }
            for t in incidence[b] where !shared.holds(t) {
                triangles[t] = triangles[t].replacing(b, with: a)
                incidence[a].append(t)
            }
            for t in [shared.first, shared.second] {
                triangles[t] = MeshTriangle(0, 0, 0)
                incidence[a].removeAll { $0 == t }
            }
            incidence[b] = []
            removed[b] = true
            collapsed = true
        }

        guard collapsed else { return false }
        compact(removing: removed)
        return true
    }

    /// Would welding `a` and `b` at `target` fold any of the triangles that
    /// survive? Compared by normal direction, since a collapse that inverts a
    /// triangle leaves a spike the relaxation cannot pull back out.
    private func collapseKeepsOrientation(a: Int, b: Int, to target: Vector3, dropping: EdgeFaces) -> Bool {
        for v in [a, b] {
            for t in incidence[v] where !dropping.holds(t) {
                let tri = triangles[t]
                guard !tri.isDegenerate else { continue }
                let before = normal(of: tri)
                let moved = MeshTriangle(tri.a == b ? a : tri.a, tri.b == b ? a : tri.b, tri.c == b ? a : tri.c)
                guard !moved.isDegenerate else { return false }
                var p = (positions[moved.a], positions[moved.b], positions[moved.c])
                if moved.a == a { p.0 = target }
                if moved.b == a { p.1 = target }
                if moved.c == a { p.2 = target }
                let after = (p.1 - p.0).cross(p.2 - p.0)
                if after.lengthSquared < 1e-24 { return false }
                if before.dot(after.normalized) < 0.2 { return false }
            }
        }
        return true
    }

    private func flipForValence(edges: [MeshEdge], boundary: [Bool]) {
        for e in edges {
            let (a, b) = (e.low, e.high)
            guard !boundary[a], !boundary[b] else { continue }
            let shared = trianglesOn(a, b)
            guard shared.count == 2 else { continue }
            let t0 = triangles[shared.first], t1 = triangles[shared.second]
            guard let c = t0.opposite(a, b), let d = t1.opposite(a, b), c != d else { continue }

            // Valence first, because it is four array lengths and it rejects
            // most edges. The duplicate-edge test below has to walk a whole
            // neighborhood, so it is worth reaching only for the few edges that
            // are actually going to be flipped.
            let va = incidence[a].count, vb = incidence[b].count
            let vc = incidence[c].count, vd = incidence[d].count
            let before = abs(va - 6) + abs(vb - 6) + abs(vc - 6) + abs(vd - 6)
            let after = abs(va - 1 - 6) + abs(vb - 1 - 6) + abs(vc + 1 - 6) + abs(vd + 1 - 6)
            guard after < before else { continue }

            // Flipping onto an edge that already exists would stack two faces on
            // it.
            guard !ring(of: c).contains(d) else { continue }

            // The quad runs a -> d -> b -> c, so the flipped diagonal splits it
            // into (a, d, c) and (d, b, c).
            let new0 = MeshTriangle(a, d, c), new1 = MeshTriangle(d, b, c)
            guard !new0.isDegenerate, !new1.isDegenerate else { continue }
            let keeps = normal(of: t0).dot(normal(of: new0)) > 0.2
                && normal(of: t1).dot(normal(of: new1)) > 0.2
            guard keeps else { continue }

            triangles[shared.first] = new0
            triangles[shared.second] = new1
            incidence[a].removeAll { $0 == shared.second }
            incidence[b].removeAll { $0 == shared.first }
            incidence[c].append(shared.second)
            incidence[d].append(shared.first)
        }
    }

    /// Slide each vertex toward the middle of its neighbors, splitting the move
    /// into its two parts because they do different jobs.
    ///
    /// The part *within* the surface evens out the spacing without changing the
    /// shape, and is applied at `relaxation`. The part *along the normal* is
    /// bending: how far the vertex sits off the plane its neighbors describe.
    /// Damping that at `stiffness` is what gives the sheet resistance to
    /// folding sharply, and so what decides whether the surface gathers into
    /// broad waves or crumples at the size of its own triangles.
    ///
    /// A vertex on an open rim slides along the rim instead, which keeps the
    /// boundary its own length.
    private func relax(boundary: [Bool]) {
        guard relaxation > 0 || stiffness > 0 else { return }
        let normals = vertexNormals()
        let rings = ringTable()
        var moved = positions

        for v in positions.indices {
            let ring = rings[v]
            guard !ring.isEmpty else { continue }
            if boundary[v] {
                let rim = ring.filter { boundary[$0] }
                guard rim.count == 2 else { continue }
                let mid = (positions[rim[0]] + positions[rim[1]]) * 0.5
                moved[v] = positions[v] + (mid - positions[v]) * relaxation
            } else {
                var centroid = Vector3.zero
                for n in ring { centroid = centroid + positions[n] }
                centroid = centroid * (1 / Double(ring.count))
                let delta = centroid - positions[v]
                let alongNormal = normals[v] * delta.dot(normals[v])
                let acrossSurface = delta - alongNormal
                moved[v] = positions[v] + acrossSurface * relaxation + alongNormal * stiffness
            }
        }
        positions = moved
    }

    // MARK: Topology helpers

    private func rebuildIncidence() {
        incidence = [[Int]](repeating: [], count: positions.count)
        for (index, t) in triangles.enumerated() where !t.isDegenerate {
            incidence[t.a].append(index)
            incidence[t.b].append(index)
            incidence[t.c].append(index)
        }
    }

    /// The 1-ring of a vertex, in ascending order so every pass over it runs the
    /// same way twice.
    private func ring(of v: Int) -> [Int] {
        var found: [Int] = []
        for t in incidence[v] {
            let tri = triangles[t]
            guard !tri.isDegenerate else { continue }
            for corner in tri.corners where corner != v && !found.contains(corner) {
                found.append(corner)
            }
        }
        return found.sorted()
    }

    /// Every vertex's 1-ring, built in one pass over the triangles.
    ///
    /// Worth doing as a table rather than asking per vertex: the force pass, the
    /// relaxation, and the two-hop neighborhoods together want the ring of
    /// nearly every vertex several times over, and answering each of those
    /// separately walks the incidence lists tens of thousands of times a step.
    private func ringTable() -> [[Int]] {
        var lists = [[Int]](repeating: [], count: positions.count)
        for t in triangles where !t.isDegenerate {
            lists[t.a].append(t.b); lists[t.a].append(t.c)
            lists[t.b].append(t.c); lists[t.b].append(t.a)
            lists[t.c].append(t.a); lists[t.c].append(t.b)
        }
        for v in lists.indices where lists[v].count > 1 {
            lists[v].sort()
            var write = 1
            for read in 1 ..< lists[v].count where lists[v][read] != lists[v][write - 1] {
                lists[v][write] = lists[v][read]
                write += 1
            }
            lists[v].removeLast(lists[v].count - write)
        }
        return lists
    }

    /// Every edge once in a fixed order, and which vertices sit on an open rim.
    ///
    /// Both fall out of the same sorted list of edge keys, so they are found
    /// together: counting how many triangles use an edge is what identifies a
    /// rim, and it is the same scan that removes the duplicates. Sorting keys
    /// rather than filling a dictionary matters at this size, since the edges
    /// are walked several times a step.
    ///
    /// The order is fixed by the sort rather than by a dictionary's iteration,
    /// which is what makes a run reproduce: which edge is considered first
    /// changes what a pass does.
    private func edgeTable() -> (edges: [MeshEdge], boundary: [Bool]) {
        var keys: [UInt64] = []
        keys.reserveCapacity(triangles.count * 3)
        for t in triangles where !t.isDegenerate {
            keys.append(MeshGrowth.key(t.a, t.b))
            keys.append(MeshGrowth.key(t.b, t.c))
            keys.append(MeshGrowth.key(t.c, t.a))
        }
        keys.sort()

        var edges: [MeshEdge] = []
        edges.reserveCapacity(keys.count / 2)
        var boundary = [Bool](repeating: false, count: positions.count)
        var i = 0
        while i < keys.count {
            var j = i + 1
            while j < keys.count, keys[j] == keys[i] { j += 1 }
            let low = Int(keys[i] >> 32), high = Int(keys[i] & 0xFFFF_FFFF)
            edges.append(MeshEdge(low, high))
            if j - i == 1 {
                boundary[low] = true
                boundary[high] = true
            }
            i = j
        }
        return (edges, boundary)
    }

    private static func key(_ i: Int, _ j: Int) -> UInt64 {
        UInt64(Swift.min(i, j)) << 32 | UInt64(Swift.max(i, j))
    }

    /// The (at most two) triangles using edge *(a, b)*.
    ///
    /// Returned as a fixed pair rather than an array: the flip pass asks this of
    /// every edge in the mesh, and allocating a result for each one was a
    /// measurable part of a step.
    private func trianglesOn(_ a: Int, _ b: Int) -> EdgeFaces {
        var faces = EdgeFaces()
        for t in incidence[a] where !triangles[t].isDegenerate && triangles[t].contains(b) {
            faces.add(t)
        }
        return faces
    }

    private func normal(of t: MeshTriangle) -> Vector3 {
        let n = (positions[t.b] - positions[t.a]).cross(positions[t.c] - positions[t.a])
        return n.lengthSquared > 1e-24 ? n.normalized : .zero
    }

    private func vertexNormals() -> [Vector3] {
        var out = [Vector3](repeating: .zero, count: positions.count)
        for t in triangles where !t.isDegenerate {
            let n = (positions[t.b] - positions[t.a]).cross(positions[t.c] - positions[t.a])
            out[t.a] = out[t.a] + n
            out[t.b] = out[t.b] + n
            out[t.c] = out[t.c] + n
        }
        for v in out.indices {
            out[v] = out[v].lengthSquared > 1e-24 ? out[v].normalized : Vector3.unitY
        }
        return out
    }

    private func extent() -> Double {
        guard let first = positions.first else { return 0 }
        var lo = first, hi = first
        for p in positions {
            lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        let d = hi - lo
        return Swift.max(d.x, Swift.max(d.y, d.z))
    }

    /// Drop the removed vertices and renumber everything that referred to them.
    private func compact(removing removed: [Bool]) {
        var remap = [Int](repeating: -1, count: positions.count)
        var keptPositions: [Vector3] = []
        var keptChannels = [[Double]](repeating: [], count: channels.count)
        keptPositions.reserveCapacity(positions.count)
        for v in positions.indices where !removed[v] {
            remap[v] = keptPositions.count
            keptPositions.append(positions[v])
            for c in channels.indices { keptChannels[c].append(channels[c][v]) }
        }
        var keptTriangles: [MeshTriangle] = []
        keptTriangles.reserveCapacity(triangles.count)
        for t in triangles where !t.isDegenerate {
            let (a, b, c) = (remap[t.a], remap[t.b], remap[t.c])
            guard a >= 0, b >= 0, c >= 0 else { continue }
            let moved = MeshTriangle(a, b, c)
            if !moved.isDegenerate { keptTriangles.append(moved) }
        }
        positions = keptPositions
        channels = keptChannels
        triangles = keptTriangles
        rebuildIncidence()
    }

    // MARK: Input conditioning

    private static func meanEdgeLength(positions: [Vector3], triangles: [MeshTriangle]) -> Double {
        var seen = Set<MeshEdge>()
        var total = 0.0
        for t in triangles {
            for (i, j) in [(t.a, t.b), (t.b, t.c), (t.c, t.a)] {
                let e = MeshEdge(i, j)
                if seen.insert(e).inserted { total += positions[i].distance(to: positions[j]) }
            }
        }
        return seen.isEmpty ? 0 : total / Double(seen.count)
    }

}

/// The triangles on one edge: at most two on a manifold surface, one on an open
/// rim. A fixed pair rather than an array, so asking about every edge in the
/// mesh costs no allocations.
private struct EdgeFaces {
    var first = -1
    var second = -1
    var count = 0

    mutating func add(_ t: Int) {
        if count == 0 { first = t } else if count == 1 { second = t }
        count += 1
    }

    func holds(_ t: Int) -> Bool { (count > 0 && first == t) || (count > 1 && second == t) }
}

/// A uniform-grid cell key for the self-avoidance broad phase.
private struct Cell: Hashable {
    let x: Int
    let y: Int
    let z: Int

    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ p: Vector3, _ size: Double) {
        x = Int(floor(p.x / size))
        y = Int(floor(p.y / size))
        z = Int(floor(p.z / size))
    }
}
