import Foundation

/// A gravitational n-body simulation: every body pulls on every other, and
/// out of nothing but that one rule come spinning disks, tidal tails, slingshot
/// ejections, and slow-motion galaxy collisions. Hold one, `step()` it each
/// frame, and draw the `positions` (small points over an accumulation surface
/// read best).
///
/// ```swift
/// let galaxy = NBody.disk(count: 2000, center: center, radius: 380)
///
/// override func draw() {
///     galaxy.step()
///     drawPoints(galaxy.positions)
/// }
/// ```
///
/// Forces are computed through a quadtree (the hierarchical far-field
/// approximation that makes thousands of bodies cheap): distant clumps of
/// bodies act as single points, controlled by `theta` (0 forces the exact
/// all-pairs sum; around 0.7 is a good balance; 1 is faster and looser).
/// Close encounters are softened by `softening` so nothing slingshots to
/// infinity, and the integrator is the standard leapfrog for gravity, which
/// keeps orbits stable over long runs instead of slowly decaying. Everything
/// is deterministic: fixed iteration orders throughout, and the factories
/// roll from a seed, so a run replays exactly.
///
/// Implemented from the published technique (Barnes and Hut, *A hierarchical
/// O(N log N) force-calculation algorithm*, Nature 324, 1986, with Plummer
/// softening), not ported.
public final class NBody {

    /// One body: a position, a velocity, and a mass.
    public struct Body: Sendable {
        /// Where it is, in canvas units.
        public var position: Vector2
        /// Where it's going, in canvas units per second.
        public var velocity: Vector2
        /// How much it pulls. Only ratios matter; scale `gravity` for pace.
        public var mass: Double

        public init(position: Vector2, velocity: Vector2 = .zero, mass: Double = 1) {
            self.position = position
            self.velocity = velocity
            self.mass = mass
        }
    }

    /// The bodies. Mutate freely between steps (add, remove, or stir); the
    /// simulation picks up the change on the next `step()`.
    public var bodies: [Body]

    /// The gravitational constant: the one pace knob, in canvas units.
    public var gravity: Double

    /// The far-field accuracy dial: a clump of bodies whose region looks
    /// smaller than this fraction of its distance acts as a single point.
    /// `0` is the exact all-pairs sum, `0.7` the balanced default (force
    /// errors of a couple percent, invisible in motion), `0.5` when accuracy
    /// shows, `1` fast and loose.
    public var theta: Double

    /// The close-encounter softening length, in canvas units: inside this
    /// distance gravity levels off instead of diverging, so near-collisions
    /// swing through smoothly rather than slingshotting. A few pixels,
    /// roughly the typical body spacing, reads well.
    public var softening: Double

    /// A simulation over explicit bodies.
    public init(bodies: [Body], gravity: Double = 1, theta: Double = 0.7,
                softening: Double = 4) {
        self.bodies = bodies
        self.gravity = gravity
        self.theta = theta
        self.softening = softening
    }

    /// The body positions, in body order. The draw-side read surface.
    public var positions: [Vector2] { bodies.map(\.position) }

    /// The mass-weighted center of the whole system. Useful for keeping a
    /// camera or a `translate` anchored on drifting action.
    public var centerOfMass: Vector2 {
        var mass = 0.0
        var weighted = Vector2.zero
        for body in bodies {
            mass += body.mass
            weighted += body.position * body.mass
        }
        return mass > 0 ? weighted / mass : .zero
    }

    // MARK: - Stepping

    private var accelerations: [Vector2] = []

    /// Advance the simulation by `dt` seconds (one frame at 60 fps by
    /// default) with a leapfrog step: half a velocity kick, a full position
    /// drift, one fresh force pass, half a kick. Keep `dt` fixed frame to
    /// frame; that fixedness is what keeps orbits from drifting.
    public func step(_ dt: Double = 1.0 / 60.0) {
        guard dt > 0, !bodies.isEmpty else { return }
        // Forces at the current positions: reused from the last step's tail
        // when the bodies haven't been touched, recomputed when they have.
        if accelerations.count != bodies.count {
            accelerations = computeAccelerations()
        }
        let half = dt / 2
        for i in bodies.indices {
            bodies[i].velocity += accelerations[i] * half
            bodies[i].position += bodies[i].velocity * dt
        }
        accelerations = computeAccelerations()
        for i in bodies.indices {
            bodies[i].velocity += accelerations[i] * half
        }
    }

    // MARK: - Seeded starting arrangements

    /// A spinning disk around a heavy central body: each light body starts on
    /// the circular orbit its radius calls for (from the mass enclosed inside
    /// it), so the disk shears and spirals instead of collapsing. `spin` sets
    /// the direction (positive is clockwise on canvas), `jitter` roughens the
    /// orbits, and `velocity` drifts the whole disk, which is how you stage a
    /// two-galaxy collision. The central body is `bodies[0]`.
    public static func disk(count: Int, center: Vector2, radius: Double,
                            innerRadius: Double? = nil,
                            centralMass: Double = 500_000, bodyMass: Double = 1,
                            spin: Double = 1, jitter: Double = 0.08,
                            velocity: Vector2 = .zero,
                            seed: UInt64 = 1) -> NBody {
        var rng = SplitMix64(seed: seed)
        let outer = max(radius, 1)
        let inner = min(max(innerRadius ?? outer * 0.12, 0), outer * 0.95)
        let mass = max(bodyMass, 0)

        // Sample the annulus with uniform area density.
        var radii = [Double]()
        var angles = [Double]()
        radii.reserveCapacity(count)
        angles.reserveCapacity(count)
        for _ in 0 ..< max(count, 0) {
            let u = Double.random(in: 0 ..< 1, using: &rng)
            radii.append((inner * inner + (outer * outer - inner * inner) * u).squareRoot())
            angles.append(Double.random(in: 0 ..< .tau, using: &rng))
        }
        // How many bodies sit inside each body's orbit, for the enclosed mass.
        let rank = ranks(of: radii)

        var bodies = [Body]()
        bodies.reserveCapacity(count + 1)
        bodies.append(Body(position: center, velocity: velocity, mass: centralMass))
        for i in 0 ..< max(count, 0) {
            let radial = Vector2(angle: angles[i])
            // The circular-orbit speed for the mass inside this orbit, at
            // the default gravity of 1. Scale `gravity` afterward to re-pace.
            let enclosed = centralMass + mass * Double(rank[i])
            var speed = (enclosed / radii[i]).squareRoot()
            speed *= 1 + (Double.random(in: 0 ..< 1, using: &rng) * 2 - 1) * jitter
            let tangent = radial.perpendicular * (spin >= 0 ? 1 : -1)
            bodies.append(Body(position: center + radial * radii[i],
                               velocity: velocity + tangent * speed,
                               mass: mass))
        }
        return NBody(bodies: bodies)
    }

    /// A cold cluster: bodies scattered evenly across a disk with no starting
    /// motion, so the whole thing collapses inward, swings through itself,
    /// and puffs into a bound swarm.
    public static func cluster(count: Int, center: Vector2, radius: Double,
                               bodyMass: Double = 40, seed: UInt64 = 1) -> NBody {
        var rng = SplitMix64(seed: seed)
        var bodies = [Body]()
        bodies.reserveCapacity(count)
        for _ in 0 ..< max(count, 0) {
            let r = max(radius, 1) * Double.random(in: 0 ..< 1, using: &rng).squareRoot()
            let a = Double.random(in: 0 ..< .tau, using: &rng)
            bodies.append(Body(position: center + Vector2(angle: a, length: r),
                               mass: bodyMass))
        }
        return NBody(bodies: bodies, softening: 8)
    }

    /// The number of entries strictly smaller than each entry (ties broken by
    /// index, so the ranking is total and deterministic).
    private static func ranks(of values: [Double]) -> [Int] {
        let order = values.indices.sorted { a, b in
            values[a] != values[b] ? values[a] < values[b] : a < b
        }
        var rank = [Int](repeating: 0, count: values.count)
        for (position, index) in order.enumerated() { rank[index] = position }
        return rank
    }

    // MARK: - The quadtree force pass

    /// One node of the quadtree: a square region holding either a chain of
    /// resident bodies (a leaf) or four children, plus the total mass and
    /// mass-weighted position sum of everything inside it.
    private struct Node {
        var centerX, centerY, half: Double
        var mass = 0.0
        var weightedX = 0.0, weightedY = 0.0
        var firstChild = -1     // index of four consecutive children; -1 = leaf
        var bodyHead = -1       // head of this leaf's body chain; -1 = empty
    }

    /// Past this depth a leaf chains coincident bodies instead of splitting:
    /// two bodies at the same point would otherwise subdivide forever.
    private static let maxDepth = 40

    /// One full force pass: build the quadtree, then walk it once per body.
    /// Internal so the tests can hold it against the exact all-pairs sum.
    func computeAccelerations() -> [Vector2] {
        let count = bodies.count
        var result = [Vector2](repeating: .zero, count: count)
        guard count > 1 else { return result }

        // The bounding square, recomputed every pass (bodies drift).
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for body in bodies {
            minX = min(minX, body.position.x); maxX = max(maxX, body.position.x)
            minY = min(minY, body.position.y); maxY = max(maxY, body.position.y)
        }
        let half = max(maxX - minX, maxY - minY) / 2 + 1e-6

        var nodes = [Node]()
        nodes.reserveCapacity(count * 2)
        nodes.append(Node(centerX: (minX + maxX) / 2, centerY: (minY + maxY) / 2, half: half))
        var nextBody = [Int](repeating: -1, count: count)

        // Insert bodies one at a time, in index order (determinism), letting
        // mass and the weighted position accumulate down the descent path.
        for i in 0 ..< count {
            let p = bodies[i].position
            let m = bodies[i].mass
            var nodeIndex = 0
            var depth = 0
            while true {
                nodes[nodeIndex].mass += m
                nodes[nodeIndex].weightedX += m * p.x
                nodes[nodeIndex].weightedY += m * p.y

                if nodes[nodeIndex].firstChild >= 0 {
                    nodeIndex = childIndex(of: nodeIndex, for: p, in: nodes)
                    depth += 1
                    continue
                }
                if nodes[nodeIndex].bodyHead < 0 {
                    nodes[nodeIndex].bodyHead = i
                    break
                }
                if depth >= Self.maxDepth {
                    nextBody[i] = nodes[nodeIndex].bodyHead
                    nodes[nodeIndex].bodyHead = i
                    break
                }
                // Split the leaf: move its resident down a level, then keep
                // descending with the new body (possibly splitting again if
                // they share the next quadrant too).
                subdivide(nodeIndex, in: &nodes)
                let resident = nodes[nodeIndex].bodyHead
                nodes[nodeIndex].bodyHead = -1
                let rp = bodies[resident].position
                let rm = bodies[resident].mass
                let residentChild = childIndex(of: nodeIndex, for: rp, in: nodes)
                nodes[residentChild].mass += rm
                nodes[residentChild].weightedX += rm * rp.x
                nodes[residentChild].weightedY += rm * rp.y
                nodes[residentChild].bodyHead = resident
                nodeIndex = childIndex(of: nodeIndex, for: p, in: nodes)
                depth += 1
            }
        }

        // Walk the tree once per body: open near nodes, aggregate far ones.
        // Raw buffers keep the hot loop fast even in unoptimized builds.
        let softening2 = softening * softening
        let g = gravity
        let opening = theta
        var stack = [Int](repeating: 0, count: 256)
        nodes.withUnsafeBufferPointer { node in
            nextBody.withUnsafeBufferPointer { next in
                bodies.withUnsafeBufferPointer { body in
                    for i in 0 ..< count {
                        let px = body[i].position.x, py = body[i].position.y
                        var ax = 0.0, ay = 0.0
                        var top = 0
                        stack[0] = 0
                        while top >= 0 {
                            let n = node[stack[top]]
                            top -= 1
                            guard n.mass > 0 else { continue }
                            if n.firstChild < 0 {
                                // A leaf: sum its residents directly, skipping self.
                                var j = n.bodyHead
                                while j >= 0 {
                                    if j != i {
                                        let dx = body[j].position.x - px
                                        let dy = body[j].position.y - py
                                        let d2 = dx * dx + dy * dy + softening2
                                        let f = body[j].mass / (d2 * d2.squareRoot())
                                        ax += dx * f
                                        ay += dy * f
                                    }
                                    j = next[j]
                                }
                                continue
                            }
                            let dx = n.weightedX / n.mass - px
                            let dy = n.weightedY / n.mass - py
                            let d2 = dx * dx + dy * dy
                            if n.half * n.half * 4 < opening * opening * d2 {
                                // Far enough: the whole subtree as one point.
                                let soft2 = d2 + softening2
                                let f = n.mass / (soft2 * soft2.squareRoot())
                                ax += dx * f
                                ay += dy * f
                            } else {
                                // Too close: open it. Fixed push order for
                                // determinism (child 0 pops first).
                                if top + 4 >= stack.count {
                                    stack.append(contentsOf: repeatElement(0, count: stack.count))
                                }
                                stack[top + 1] = n.firstChild + 3
                                stack[top + 2] = n.firstChild + 2
                                stack[top + 3] = n.firstChild + 1
                                stack[top + 4] = n.firstChild
                                top += 4
                            }
                        }
                        result[i] = Vector2(ax * g, ay * g)
                    }
                }
            }
        }
        return result
    }

    private func subdivide(_ nodeIndex: Int, in nodes: inout [Node]) {
        let quarter = nodes[nodeIndex].half / 2
        let cx = nodes[nodeIndex].centerX, cy = nodes[nodeIndex].centerY
        nodes[nodeIndex].firstChild = nodes.count
        nodes.append(Node(centerX: cx - quarter, centerY: cy - quarter, half: quarter))
        nodes.append(Node(centerX: cx + quarter, centerY: cy - quarter, half: quarter))
        nodes.append(Node(centerX: cx - quarter, centerY: cy + quarter, half: quarter))
        nodes.append(Node(centerX: cx + quarter, centerY: cy + quarter, half: quarter))
    }

    private func childIndex(of nodeIndex: Int, for position: Vector2, in nodes: [Node]) -> Int {
        let node = nodes[nodeIndex]
        let dx = position.x > node.centerX ? 1 : 0
        let dy = position.y > node.centerY ? 2 : 0
        return node.firstChild + dx + dy
    }
}
