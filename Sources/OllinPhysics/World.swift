import Foundation
import Ollin
internal import CBox2D

/// The simulation: a bag of `Particle`s and the `Spring`s between them, plus the
/// global rules they live under — gravity, drag, an optional container, and
/// whether particles collide as disks. A sketch builds a world once, then calls
/// `advance(by:)` each frame and draws from `particles`.
///
/// ```swift
/// let world = World()
/// world.gravity = Vector2(0, 1200)
/// world.bounds = Rectangle(x: 0, y: 0, width: width, height: height)
/// world.particlesCollide = true
/// for _ in 0..<200 {
///     world.addParticle(at: Vector2(random(width), random(height)),
///                       radius: 12 * scale)
/// }
/// // each frame:
/// world.advance(by: deltaTime)
/// for p in world.particles { drawCircle(center: p.position, radius: p.radius) }
/// ```
///
/// The solver is **Verlet with relaxation**: integrate every particle, then run
/// several passes that pull springs back to length, push overlapping disks
/// apart, and keep everything inside `bounds`. More `iterations` makes stiff
/// stacks and tight packings hold together better, at a linear cost. It's tuned
/// for "a few hundred bodies that feel right", not exact physical accuracy.
public final class World {

    /// Every particle in the simulation, in the order added.
    public private(set) var particles: [Particle] = []

    /// Every spring in the simulation.
    public private(set) var springs: [Spring] = []

    /// Constant acceleration applied to every (unpinned) particle, in points per
    /// second². The default pulls down the screen (y-down). Set `.zero` for a
    /// free-floating, gravity-less field.
    public var gravity: Vector2 = Vector2(0, 980)

    /// Velocity damping applied each step, `0…1` — a stand-in for air friction.
    /// `0` conserves motion (bodies drift forever); a small value bleeds energy
    /// so things settle. Verlet has no separate velocity to scale, so this
    /// shrinks the implicit `position - previous` gap.
    public var drag: Double = 0.01

    /// How many relaxation passes run per step. Higher holds springs and
    /// particlesCollide together under stress (a tall stack, a stiff cloth); lower is
    /// cheaper and looser. Costs scale linearly.
    public var iterations: Int = 8

    /// An optional rectangle particles are kept inside. `nil` lets them leave the
    /// canvas. Particles collide with the walls accounting for their `radius`. The
    /// rigid `Body` sub-system also collides with these walls.
    public var bounds: Rectangle? {
        didSet {
            if let id = rigidWorldId { rebuildWalls(in: id) }
        }
    }

    /// Wall restitution, `0…1`: how much speed a particle keeps when it bounces
    /// off `bounds`. `0` sticks, `1` bounces with no loss.
    public var restitution: Double = 0.5

    /// When `true`, particles with a positive `radius` push apart as solid disks,
    /// broad-phased through a spatial hash so it scales to thousands of bodies.
    /// Off by default — a cloth or chain doesn't want its own points colliding,
    /// and it adds a per-frame pass — so a sketch opts in for a packing or a pile.
    /// Points with `radius == 0` never collide.
    public var particlesCollide: Bool = false

    /// The largest timestep a single `advance(by:)` will integrate, in seconds.
    /// `deltaTime` can spike after a stall or while a window is dragged; clamping
    /// keeps one long frame from launching everything off-screen. The simulation
    /// runs a little slow through a hitch rather than exploding.
    public var maxTimestep: Double = 1.0 / 30

    /// Sketch points (the unit particles use) per simulated meter for the rigid
    /// `Body` sub-system. Box2D is tuned for objects roughly 0.1–10 m, so the
    /// default of 100 puts a 100-point shape at 1 m — its sweet spot. The Verlet
    /// particle/spring side works directly in points and ignores this.
    public var pixelsPerMeter: Double = 100

    /// Every rigid `Body` in the simulation, in the order added.
    public private(set) var bodies: [Body] = []

    /// Every `Joint` between rigid bodies, in the order added.
    public private(set) var joints: [Joint] = []

    /// The timestep used on the previous `step`, for time-corrected Verlet (so a
    /// variable frame rate doesn't change how fast things move).
    private var lastTimestep: Double = 0

    /// The Box2D world backing the rigid `Body` sub-system, created lazily on the
    /// first `addBody` so a pure particle/spring sketch never spins one up.
    private var rigidWorldId: b2WorldId?

    /// The static body carrying the `bounds` walls in the rigid world, rebuilt
    /// when `bounds` changes.
    private var wallBodyId: b2BodyId?

    /// A dummy static body that grab (mouse) joints anchor against.
    private var mouseGroundId: b2BodyId?

    /// Solver sub-steps per rigid step. Four is Box2D's recommended default.
    private let rigidSubSteps: Int32 = 4

    public init() {}

    deinit {
        if let id = rigidWorldId { b2DestroyWorld(id) }
    }

    // MARK: Building the world

    /// Add a particle at `position` and return it (so you can pin it, push it,
    /// or wire it into a spring).
    /// - Parameters:
    ///   - position: where it starts, in canvas units.
    ///   - radius: collision radius; `0` (the default) is a non-colliding point.
    ///   - mass: heavier particles resist being pushed; must be `> 0`.
    @discardableResult
    public func addParticle(at position: Vector2, radius: Double = 0, mass: Double = 1) -> Particle {
        let particle = Particle(position: position, radius: radius, mass: mass)
        particles.append(particle)
        return particle
    }

    /// Link two particles with a `Spring` and return it. `length` defaults to
    /// their current spacing, so connecting two placed particles keeps them where
    /// they are; `stiffness` is `0…1` (`1` rigid).
    @discardableResult
    public func connect(_ a: Particle, _ b: Particle, length: Double? = nil, stiffness: Double = 1) -> Spring {
        let spring = Spring(a, b, length: length, stiffness: stiffness)
        springs.append(spring)
        return spring
    }

    /// Remove a spring (by identity) — e.g. to tear a cloth.
    public func remove(_ spring: Spring) {
        springs.removeAll { $0 === spring }
    }

    /// Remove a particle and any springs attached to it.
    public func remove(_ particle: Particle) {
        springs.removeAll { $0.a === particle || $0.b === particle }
        particles.removeAll { $0 === particle }
    }

    /// Empty the world.
    public func removeAll() {
        particles.removeAll()
        springs.removeAll()
        // Joints before bodies: destroying a body would invalidate its joints.
        for joint in joints { b2DestroyJoint(joint.id) }
        joints.removeAll()
        for body in bodies { b2DestroyBody(body.id) }
        bodies.removeAll()
    }

    // MARK: Stepping

    /// Advance the simulation by `dt` seconds (pass `deltaTime`). Integrates every
    /// particle, then relaxes springs, particlesCollide, and bounds. A `dt` of `0` (a
    /// paused or first frame) is a no-op; a large `dt` is clamped to `maxTimestep`.
    public func advance(by dt: Double) {
        guard dt > 0 else { return }
        let h = Swift.min(dt, maxTimestep)

        for particle in particles {
            particle.acceleration += gravity
            integrate(particle, dt: h)
        }
        lastTimestep = h

        for _ in 0 ..< Swift.max(1, iterations) {
            for spring in springs { spring.solve() }
            if particlesCollide { solveCollisions() }
            if bounds != nil {
                for particle in particles { constrainToBounds(particle) }
            }
        }

        // Advance the rigid Body sub-system, if any, over the same clamped step.
        if let id = rigidWorldId {
            b2World_SetGravity(id, meters(from: gravity))
            b2World_Step(id, Float(h), rigidSubSteps)
        }
    }

    // MARK: Solver internals

    /// Time-corrected Verlet: `next = position + velocity·(dt/lastDt)·(1−drag) +
    /// acceleration·dt²`. Scaling the velocity term by the timestep ratio keeps
    /// speeds steady when the frame rate wanders.
    private func integrate(_ p: Particle, dt: Double) {
        guard !p.isPinned else { p.acceleration = .zero; return }
        let ratio = lastTimestep > 0 ? dt / lastTimestep : 1
        let velocity = (p.position - p.previous) * (ratio * (1 - drag))
        let next = p.position + velocity + p.acceleration * (dt * dt)
        p.previous = p.position
        p.position = next
        p.acceleration = .zero
    }

    /// A cell key for the collision spatial hash.
    private struct Cell: Hashable { let x: Int; let y: Int }

    /// Push overlapping disks apart, broad-phased through a uniform spatial hash:
    /// bucket each disk into a grid sized to the largest radius, then test only
    /// the same and neighboring cells. That drops the pass from O(n²) toward
    /// O(n), so thousands of disks stay interactive.
    private func solveCollisions() {
        var maxRadius = 0.0
        for p in particles where p.radius > 0 { maxRadius = Swift.max(maxRadius, p.radius) }
        guard maxRadius > 0 else { return }

        // A cell spans the largest disk, so two disks can only touch if they sit
        // in the same or an adjacent cell.
        let cellSize = maxRadius * 2
        var grid: [Cell: [Int]] = [:]
        for i in particles.indices where particles[i].radius > 0 {
            let p = particles[i].position
            let cell = Cell(x: Int((p.x / cellSize).rounded(.down)),
                            y: Int((p.y / cellSize).rounded(.down)))
            grid[cell, default: []].append(i)
        }

        // Each disk against its own and the eight neighboring buckets, walked
        // in particle-index order with a fixed cell scan. Resolution shifts
        // positions as it goes, so the pair order changes the outcome; a
        // Dictionary walk here would reorder per process and a seeded pile
        // would settle differently on every run. The `j > i` guard resolves
        // every pair exactly once.
        for i in particles.indices where particles[i].radius > 0 {
            let p = particles[i].position
            let cx = Int((p.x / cellSize).rounded(.down))
            let cy = Int((p.y / cellSize).rounded(.down))
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    guard let neighbors = grid[Cell(x: cx + dx, y: cy + dy)] else { continue }
                    for j in neighbors where j > i {
                        resolveCollision(particles[i], particles[j])
                    }
                }
            }
        }
    }

    private func resolveCollision(_ a: Particle, _ b: Particle) {
        let minDistance = a.radius + b.radius
        let delta = b.position - a.position
        let distanceSquared = delta.lengthSquared
        guard distanceSquared < minDistance * minDistance else { return }

        let wA = a.isPinned ? 0 : a.inverseMass
        let wB = b.isPinned ? 0 : b.inverseMass
        let wSum = wA + wB
        guard wSum > 0 else { return }

        // Almost-coincident disks have no reliable normal; shove them apart along
        // x so they separate rather than stay locked together.
        let distance = distanceSquared.squareRoot()
        let normal = distance > 1e-9 ? delta / distance : .unitX
        let overlap = minDistance - distance
        a.position -= normal * (overlap * (wA / wSum))
        b.position += normal * (overlap * (wB / wSum))
    }

    /// Keep a particle inside `bounds`, reflecting its implicit velocity by
    /// `restitution` when it hits a wall (by nudging `previous`, the Verlet way).
    private func constrainToBounds(_ p: Particle) {
        guard let bounds else { return }
        let r = p.radius
        let minX = bounds.x + r, maxX = bounds.x + bounds.width - r
        let minY = bounds.y + r, maxY = bounds.y + bounds.height - r

        var position = p.position
        var previous = p.previous

        if position.x < minX {
            let v = position.x - previous.x
            position = position.with(x: minX)
            previous = previous.with(x: minX + v * restitution)
        } else if position.x > maxX {
            let v = position.x - previous.x
            position = position.with(x: maxX)
            previous = previous.with(x: maxX + v * restitution)
        }
        if position.y < minY {
            let v = position.y - previous.y
            position = position.with(y: minY)
            previous = previous.with(y: minY + v * restitution)
        } else if position.y > maxY {
            let v = position.y - previous.y
            position = position.with(y: maxY)
            previous = previous.with(y: maxY + v * restitution)
        }

        p.position = position
        p.previous = previous
    }

    // MARK: Rigid bodies

    /// Add a rigid `Body` with `collider` at `position` and return it. Unlike a
    /// `Particle` (a soft Verlet point), a `Body` has orientation, rotates, stacks
    /// stably, and bounces with real contact response — it's backed by Box2D. It
    /// shares the world's `gravity`, `bounds` (as walls), and `restitution` (used as
    /// the wall and default contact restitution).
    /// - Parameters:
    ///   - collider: the shape it collides with.
    ///   - position: where it starts, in canvas units.
    ///   - kind: `.dynamic` (default) is moved by forces; `.static` is immovable.
    ///   - density: mass per area; heavier bodies shove lighter ones.
    ///   - friction: surface friction, `0` slick … `1` grippy.
    ///   - restitution: bounciness `0…1`; defaults to the world's `restitution`.
    @discardableResult
    public func addBody(_ collider: Collider, at position: Vector2,
                        kind: Body.Kind = .dynamic, density: Double = 1,
                        friction: Double = 0.3, restitution: Double? = nil) -> Body {
        let worldId = ensureRigidWorld()

        var bodyDef = b2DefaultBodyDef()
        bodyDef.type = kind.b2Type
        bodyDef.position = meters(from: position)
        bodyDef.linearDamping = Float(Swift.max(0, drag))
        let bodyId = b2CreateBody(worldId, &bodyDef)

        var shapeDef = b2DefaultShapeDef()
        shapeDef.density = Float(Swift.max(0.0001, density))
        shapeDef.material.friction = Float(friction)
        shapeDef.material.restitution = Float(restitution ?? self.restitution)
        switch collider {
        case .circle(let r):
            var circle = b2Circle(center: b2Vec2(x: 0, y: 0), radius: meters(from: r))
            _ = b2CreateCircleShape(bodyId, &shapeDef, &circle)
        case .box(let w, let h):
            var poly = b2MakeBox(meters(from: w / 2), meters(from: h / 2))
            _ = b2CreatePolygonShape(bodyId, &shapeDef, &poly)
        case .capsule(let from, let to, let r):
            var capsule = b2Capsule(center1: meters(from: from), center2: meters(from: to),
                                    radius: meters(from: r))
            _ = b2CreateCapsuleShape(bodyId, &shapeDef, &capsule)
        case .polygon(let points):
            let verts = points.map { meters(from: $0) }
            var hull = verts.withUnsafeBufferPointer { buffer in
                b2ComputeHull(buffer.baseAddress, Int32(buffer.count))
            }
            if hull.count >= 3 {
                var poly = b2MakePolygon(&hull, 0)
                _ = b2CreatePolygonShape(bodyId, &shapeDef, &poly)
            }
        }

        let body = Body(world: self, id: bodyId)
        bodies.append(body)
        return body
    }

    /// Take one rigid body out of the world, along with any joints holding it.
    ///
    /// What a body that has served its turn needs: a shard fallen off the
    /// bottom of the canvas, a crate the sketch is done with. The `Body` value
    /// is spent afterwards, so drop your reference to it with the same stroke.
    public func remove(_ body: Body) {
        // Box2D takes a body's joints down with it, so the world's own list is
        // pruned by asking which of them are still real.
        b2DestroyBody(body.id)
        joints.removeAll { !b2Joint_IsValid($0.id) }
        bodies.removeAll { $0 === body }
    }

    /// Link two rigid bodies with a `Joint` and return it — a hinge, rod, weld, or
    /// slider (see `JointKind`). Anchors are world points at the moment of
    /// connecting.
    @discardableResult
    public func connect(_ a: Body, _ b: Body, _ kind: JointKind) -> Joint {
        let worldId = ensureRigidWorld()
        let jointId: b2JointId

        switch kind {
        case .revolute(let at):
            var def = b2DefaultRevoluteJointDef()
            def.bodyIdA = a.id
            def.bodyIdB = b.id
            def.localAnchorA = b2Body_GetLocalPoint(a.id, meters(from: at))
            def.localAnchorB = b2Body_GetLocalPoint(b.id, meters(from: at))
            jointId = b2CreateRevoluteJoint(worldId, &def)

        case .distance(let from, let to, let length, let stiffness):
            var def = b2DefaultDistanceJointDef()
            def.bodyIdA = a.id
            def.bodyIdB = b.id
            def.localAnchorA = b2Body_GetLocalPoint(a.id, meters(from: from))
            def.localAnchorB = b2Body_GetLocalPoint(b.id, meters(from: to))
            def.length = meters(from: length ?? from.distance(to: to))
            if stiffness < 1 {
                def.enableSpring = true
                def.hertz = Float(1 + Swift.max(0, stiffness) * 8)   // soft … firm
                def.dampingRatio = 0.5
            }
            jointId = b2CreateDistanceJoint(worldId, &def)

        case .weld:
            var def = b2DefaultWeldJointDef()
            def.bodyIdA = a.id
            def.bodyIdB = b.id
            let mid = (a.position + b.position) / 2
            def.localAnchorA = b2Body_GetLocalPoint(a.id, meters(from: mid))
            def.localAnchorB = b2Body_GetLocalPoint(b.id, meters(from: mid))
            def.referenceAngle = Float(b.angle - a.angle)
            jointId = b2CreateWeldJoint(worldId, &def)

        case .prismatic(let at, let axis):
            var def = b2DefaultPrismaticJointDef()
            def.bodyIdA = a.id
            def.bodyIdB = b.id
            def.localAnchorA = b2Body_GetLocalPoint(a.id, meters(from: at))
            def.localAnchorB = b2Body_GetLocalPoint(b.id, meters(from: at))
            let unit = axis.normalized
            def.localAxisA = b2Body_GetLocalVector(a.id, b2Vec2(x: Float(unit.x), y: Float(unit.y)))
            jointId = b2CreatePrismaticJoint(worldId, &def)
        }

        let joint = Joint(world: self, id: jointId)
        joints.append(joint)
        return joint
    }

    /// Grab a rigid body and pull it toward a moving world point — the cursor-drag
    /// joint. Update the returned joint's `target` each frame, and `remove()` it to
    /// let go.
    @discardableResult
    public func grab(_ body: Body, at point: Vector2) -> Joint {
        let worldId = ensureRigidWorld()
        var def = b2DefaultMouseJointDef()
        def.bodyIdA = mouseGround(in: worldId)
        def.bodyIdB = body.id
        def.target = meters(from: point)
        def.hertz = 5
        def.dampingRatio = 0.7
        def.maxForce = Float(1000 * Swift.max(0.001, body.mass))
        let jointId = b2CreateMouseJoint(worldId, &def)
        let joint = Joint(world: self, id: jointId, isGrab: true)
        joint.target = point
        joints.append(joint)
        return joint
    }

    /// Destroy a joint (called by `Joint.remove()`).
    func removeJoint(_ joint: Joint) {
        b2DestroyJoint(joint.id)
        joints.removeAll { $0 === joint }
    }

    /// The shared static anchor body for grab joints, created on demand.
    private func mouseGround(in worldId: b2WorldId) -> b2BodyId {
        if let id = mouseGroundId { return id }
        var def = b2DefaultBodyDef()
        def.type = b2_staticBody
        let id = b2CreateBody(worldId, &def)
        mouseGroundId = id
        return id
    }

    /// Create the Box2D world on demand (with the current gravity and walls) the
    /// first time a rigid body is added.
    private func ensureRigidWorld() -> b2WorldId {
        if let id = rigidWorldId { return id }
        var def = b2DefaultWorldDef()
        def.gravity = meters(from: gravity)
        let id = b2CreateWorld(&def)
        rigidWorldId = id
        rebuildWalls(in: id)
        return id
    }

    /// (Re)build the static walls from `bounds` as four segments around its edges.
    private func rebuildWalls(in worldId: b2WorldId) {
        if let wall = wallBodyId { b2DestroyBody(wall); wallBodyId = nil }
        guard let b = bounds else { return }

        var bodyDef = b2DefaultBodyDef()
        bodyDef.type = b2_staticBody
        let wall = b2CreateBody(worldId, &bodyDef)
        wallBodyId = wall

        var shapeDef = b2DefaultShapeDef()
        shapeDef.material.restitution = Float(restitution)

        let corners = [
            b2Vec2(x: meters(from: b.x), y: meters(from: b.y)),
            b2Vec2(x: meters(from: b.x + b.width), y: meters(from: b.y)),
            b2Vec2(x: meters(from: b.x + b.width), y: meters(from: b.y + b.height)),
            b2Vec2(x: meters(from: b.x), y: meters(from: b.y + b.height))
        ]
        for i in 0 ..< 4 {
            var segment = b2Segment(point1: corners[i], point2: corners[(i + 1) % 4])
            _ = b2CreateSegmentShape(wall, &shapeDef, &segment)
        }
    }

    // Point ↔ meter conversion for the rigid sub-system (points = meters · ppm).
    func meters(from p: Vector2) -> b2Vec2 {
        b2Vec2(x: Float(p.x / pixelsPerMeter), y: Float(p.y / pixelsPerMeter))
    }
    func meters(from s: Double) -> Float {
        Float(s / pixelsPerMeter)
    }
    func points(from v: b2Vec2) -> Vector2 {
        Vector2(Double(v.x) * pixelsPerMeter, Double(v.y) * pixelsPerMeter)
    }
}
