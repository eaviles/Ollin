import Foundation
import simd
import Ollin
internal import CJolt

/// The 3D rigid-body simulation: `Body3D`s that stack, tumble, and swing inside
/// the 3D scene, joined by `Joint3D`s and stepped each frame. The spatial
/// sibling of the 2D `World`'s rigid side, sharing its shape: build a world
/// once, add bodies, call `step(dt:)` each frame, and draw each body from its
/// pose (`withBody(_:)` moves the transform stack there).
///
/// ```swift
/// let world = World3D()
/// world.ground = 0                       // a static floor at y = 0
/// let box = world.addBody(.box(width: 1, height: 1, depth: 1),
///                         at: Vector3(0, 4, 0))
/// // each frame:
/// world.step(dt: deltaTime)
/// withBody(box) { drawBox(width: 1, height: 1, depth: 1) }
/// ```
///
/// Distances are the 3D scene's world units (y-up, matching the camera), with
/// `unitsPerMeter` bridging to the solver's meters; the default of 1 treats a
/// 1-unit box as 1 m, the solver's sweet spot, which is also the scale the 3D
/// examples already draw at.
public final class World3D {

    /// Constant acceleration applied to every dynamic body, in units per
    /// second². The default pulls down the y-up world at earth strength.
    public var gravity: Vector3 = Vector3(0, -9.8, 0) {
        didSet {
            let g = meters(from: gravity)
            cjolt_world_set_gravity(handle, g.0, g.1, g.2)
        }
    }

    /// An optional static floor: the y level bodies land on. `nil` (the
    /// default) lets them fall forever. The floor is a wide static slab, so
    /// bodies can still slide off its far edges.
    public var ground: Double? {
        didSet { rebuildGround() }
    }

    /// Default restitution `0…1` for the ground and for bodies that don't pass
    /// their own: how much speed survives a bounce. Kept low so stacks settle.
    public var bounce: Double = 0.2

    /// The largest timestep a single `step(dt:)` will integrate, in seconds.
    /// `deltaTime` can spike after a stall or while a window is dragged;
    /// clamping keeps one long frame from launching everything off-screen.
    public var maxTimestep: Double = 1.0 / 30

    /// World units per simulated meter. The solver is tuned for bodies roughly
    /// 0.1…10 m, and Ollin's 3D scenes already draw at that scale, so the
    /// default of 1 maps a unit to a meter. Raise it for scenes built at a
    /// larger numeric scale (a 100-unit box at `unitsPerMeter: 100` is 1 m).
    /// Set it before adding bodies; existing bodies keep their created size.
    public var unitsPerMeter: Double = 1 {
        didSet { rebuildGround() }
    }

    /// Every rigid body in the simulation, in the order added. The slab behind
    /// `ground` is not one of them (nothing added it), so a drawing loop over
    /// `bodies` draws only what the sketch built; it is `groundBody`.
    public private(set) var bodies: [Body3D] = []

    /// The static slab behind `ground`, so a contact can be recognised as a
    /// landing: `contact.other(than: ball) === world.groundBody`. `nil` when
    /// the world has no ground.
    public private(set) var groundBody: Body3D?

    /// Every joint between bodies, in the order added.
    public private(set) var joints: [Joint3D] = []

    /// Every walking `Character3D` in the world, in the order added. Each one
    /// is swept forward by `step(dt:)` along with the bodies.
    public private(set) var characters: [Character3D] = []

    /// Every `Vehicle3D` in the world, in the order added. Each one's controls
    /// are handed to the solver by `step(dt:)`.
    public private(set) var vehicles: [Vehicle3D] = []

    /// Every touch that started or stopped during the most recent `step(dt:)`,
    /// including bodies entering and leaving a sensor. Poll it in `draw()` the
    /// way mouse state is polled; the list is replaced by the next step, and
    /// reading it twice reads the same events.
    ///
    /// ```swift
    /// world.step(dt: deltaTime)
    /// for contact in world.contacts where contact.phase == .began {
    ///     ping(at: contact.point, loudness: contact.speed)
    /// }
    /// ```
    public internal(set) var contacts: [Contact3D] = []

    /// The underlying solver world.
    let handle: OpaquePointer

    /// Bodies by solver handle, so a contact event can name the `Body3D` the
    /// sketch holds rather than a number.
    var bodyByID: [CJoltBodyID: Body3D] = [:]

    /// Who is currently touching whom, kept up to date from the drained
    /// contact events (sorted, so `Body3D.touching` reads the same order every
    /// run).
    var touchingIDs: [CJoltBodyID: [CJoltBodyID]] = [:]

    /// The timestep used on the previous `step`, so a grab drag knows how fast
    /// the hand is allowed to move its anchor.
    var lastTimestep: Double = 1.0 / 60

    /// The solver handle of the slab backing `ground`, if any.
    private var groundID: CJoltBodyID = CJOLT_BODY_INVALID

    /// Creates an empty world. `maxBodies` bounds how many bodies can ever be
    /// live at once (the solver reserves its tables up front).
    public init(maxBodies: Int = 4096) {
        handle = cjolt_world_create(0, Float(gravity.y), 0, UInt32(max(64, maxBodies)))!
    }

    deinit {
        // A sketch may still be holding a character or a vehicle when its
        // world goes. Both tear their solver object down in their own deinit,
        // which would reach into a world that no longer exists, so they are
        // told here that the whole thing is already gone.
        for character in characters { character.isDestroyed = true }
        for vehicle in vehicles { vehicle.isDestroyed = true }
        cjolt_world_destroy(handle)
    }

    // MARK: Building the world

    /// Add a rigid `Body3D` with `collider` at `position` and return it.
    /// - Parameters:
    ///   - kind: `.dynamic` (default) is moved by forces; `.static` is
    ///     immovable; `.kinematic` follows only the velocity you set.
    ///   - isSensor: make it a detector volume instead of a solid: it reports
    ///     what overlaps it through `contacts` and `Body3D.touching` but never
    ///     pushes anything, never falls, and can't be grabbed. A sensor sets
    ///     its own `kind`.
    ///   - rotated: an opening rotation about `axis`, in radians.
    ///   - density: relative mass per volume (`1` is the default material);
    ///     heavier bodies shove lighter ones.
    ///   - friction: surface friction, `0` slick … `1` grippy.
    ///   - restitution: bounciness `0…1`; defaults to the world's `bounce`.
    @discardableResult
    public func addBody(_ collider: Collider3D, at position: Vector3,
                        kind: Body3D.Kind = .dynamic, isSensor: Bool = false,
                        rotated angle: Double = 0, axis: Vector3 = .unitY,
                        density: Double = 1, friction: Double = 0.5,
                        restitution: Double? = nil) -> Body3D {
        addBody(collider, at: position, kind: kind, isSensor: isSensor,
                rotated: angle, axis: axis, density: density, friction: friction,
                restitution: restitution, mass: nil, centerOfMass: .zero)
    }

    /// The full body-creation path, with the two extras only a vehicle chassis
    /// needs so far: a mass that replaces what the shape's volume would give,
    /// and a center of mass moved off the shape's origin (which is what keeps
    /// a car from rolling over). The body's reported position stays the shape
    /// origin either way, so drawing is unaffected.
    @discardableResult
    func addBody(_ collider: Collider3D, at position: Vector3,
                 kind: Body3D.Kind, isSensor: Bool, rotated angle: Double,
                 axis: Vector3, density: Double, friction: Double,
                 restitution: Double?, mass: Double?,
                 centerOfMass: Vector3) -> Body3D {
        var desc = CJoltBodyDesc()
        let p = meters(from: position)
        desc.position = (p.0, p.1, p.2)
        let unit = axis.normalized
        let half = angle / 2
        let s = sin(half)
        desc.rotation = (Float(unit.x * s), Float(unit.y * s), Float(unit.z * s),
                         Float(cos(half)))
        desc.motion = kind.cjolt
        desc.friction = Float(max(0, friction))
        desc.restitution = Float(restitution ?? bounce)
        desc.linearDamping = 0.05
        desc.angularDamping = 0.05
        desc.gravityFactor = 1
        desc.allowSleep = true
        desc.isSensor = isSensor
        desc.mass = Float(mass ?? 0)
        let com = meters(from: centerOfMass)
        desc.centerOfMass = (com.0, com.1, com.2)

        // The collider's flat data (hull points, mesh indices, height samples,
        // compound children) lives in the arena for the span of the create.
        let arena = ShapeDescArena()
        desc.shape = collider.shapeDesc(unitsPerMeter: unitsPerMeter,
                                        density: density, arena: arena)
        if kind == .dynamic, collider.mustBeStatic {
            noteOnce("mesh and heightfield colliders are static-only; the body "
                     + "is pinned in place (use hull or a compound of solid "
                     + "shapes for moving bodies)")
        }
        let id = withExtendedLifetime(arena) {
            withUnsafePointer(to: &desc) {
                cjolt_body_create(handle, $0)
            }
        }

        // A sensor is kinematic whatever was asked for, so it stays awake and
        // keeps reporting bodies that fall asleep inside it.
        let body = Body3D(world: self, id: id, collider: collider,
                          kind: isSensor ? .kinematic : kind, density: density,
                          isSensor: isSensor)
        bodies.append(body)
        bodyByID[id] = body
        return body
    }

    /// Add every mesh in a loaded `Scene` as static scenery the dynamic bodies
    /// collide with: one static mesh body per mesh node, its triangles baked
    /// at the node's world transform (nested nodes, authored rotations, and
    /// scales all compose). Colliders take each mesh as authored, at rest:
    /// skins and morph targets aren't posed. Returns the bodies, mostly to
    /// ignore; the scene keeps drawing through `drawScene(_:)`.
    ///
    /// ```swift
    /// let hall = loadScene("hall.usdz")!
    /// world.addStaticColliders(from: hall)
    /// ```
    @discardableResult
    public func addStaticColliders(from scene: Scene, friction: Double = 0.5,
                                   restitution: Double? = nil) -> [Body3D] {
        var added: [Body3D] = []
        Scene.visitWorlds(scene.nodes, parent: matrix_identity_float4x4) { node, world in
            guard var mesh = node.mesh, !mesh.isEmpty else { return }
            mesh.positions = mesh.positions.map { position in
                let w = world * SIMD4<Float>(Float(position.x), Float(position.y),
                                             Float(position.z), 1)
                return Vector3(Double(w.x), Double(w.y), Double(w.z))
            }
            added.append(addBody(.mesh(mesh), at: .zero, kind: .static,
                                 friction: friction, restitution: restitution))
        }
        // Many statics arrived at once; rebuild the broad-phase tree.
        cjolt_world_optimize(handle)
        return added
    }

    /// Add a walking `Character3D`: a capsule standing on its feet at
    /// `position` that walks over the scenery, climbs steps, and jumps, driven
    /// from `draw()`. Unlike a body it is never tumbled or thrown; it goes
    /// where you steer it and stops where the geometry says it must.
    ///
    /// ```swift
    /// let walker = world.addCharacter(radius: 0.3, height: 1.8,
    ///                                 at: Vector3(0, 3, 0))
    /// ```
    ///
    /// - Parameters:
    ///   - radius: how wide the capsule is; also how far it stays off walls.
    ///   - height: the whole standing height, both caps included.
    ///   - stepHeight: the tallest step it walks up without jumping.
    ///   - maxSlope: the steepest slope it can climb, in radians.
    ///   - mass: what it presses down with, in kilograms.
    ///   - pushStrength: the hardest it can shove a dynamic body, in newtons
    ///     (`0` to make crates immovable).
    @discardableResult
    public func addCharacter(radius: Double = 0.3, height: Double = 1.8,
                             at position: Vector3, stepHeight: Double = 0.4,
                             stickToFloorDistance: Double = 0.5,
                             maxSlope: Double = 50 * .pi / 180,
                             mass: Double = 70,
                             pushStrength: Double = 100) -> Character3D {
        let character = Character3D(world: self, radius: radius, height: height,
                                    position: position, stepHeight: stepHeight,
                                    stickToFloorDistance: stickToFloorDistance,
                                    maxSlope: maxSlope, mass: mass,
                                    pushStrength: pushStrength)!
        characters.append(character)
        return character
    }

    /// Add a `Vehicle3D`: a chassis body carried on sprung wheels, with an
    /// engine behind the throttle. Drive it from `draw()` by setting its
    /// `throttle`, `steering`, and `brake`, and draw it from its `body` and
    /// its `wheels`.
    ///
    /// ```swift
    /// let car = world.addVehicle(.box(width: 1.8, height: 0.6, depth: 4),
    ///                            at: Vector3(0, 2, 0),
    ///                            wheels: [
    ///                                .wheel(at: Vector3( 0.9, -0.1,  1.3), steers: true),
    ///                                .wheel(at: Vector3(-0.9, -0.1,  1.3), steers: true),
    ///                                .wheel(at: Vector3( 0.9, -0.1, -1.3), driven: true, handBrake: true),
    ///                                .wheel(at: Vector3(-0.9, -0.1, -1.3), driven: true, handBrake: true),
    ///                            ])
    /// ```
    ///
    /// The vehicle drives along the chassis's local **+z**.
    ///
    /// - Parameters:
    ///   - chassis: the body's shape. Anything a `Body3D` can wear.
    ///   - wheels: where the wheels are bolted on and what each one does.
    ///     Wheels level with each other along the vehicle share an axle.
    ///   - mass: the whole machine's weight in kilograms, whatever the
    ///     chassis shape's volume would otherwise give.
    ///   - engineTorque: how hard the engine pulls, in newton-metres.
    ///   - topSpeed: the speed the gearing tops out at, in world units per
    ///     second. Lower gears the vehicle down for more pull.
    ///   - centerOfMass: where the weight hangs, in the chassis's local space.
    ///     `nil` (the default) drops it to the height of the wheel mounts,
    ///     which is what keeps a vehicle from rolling over in a turn.
    ///   - balances: a two-wheeler that holds itself up, leaning into turns
    ///     instead of falling over.
    @discardableResult
    public func addVehicle(_ chassis: Collider3D, at position: Vector3,
                           wheels: [Wheel3D], mass: Double = 1500,
                           engineTorque: Double = 500, topSpeed: Double = 30,
                           centerOfMass: Vector3? = nil,
                           rotated angle: Double = 0, axis: Vector3 = .unitY,
                           friction: Double = 0.5,
                           balances: Bool = false,
                           maxLeanAngle: Double = 45 * .pi / 180) -> Vehicle3D? {
        guard !wheels.isEmpty else {
            noteOnce("a vehicle needs at least one wheel")
            return nil
        }
        // Weight that hangs at axle height is what stops a vehicle from
        // toppling: it is high enough to be inside the body and low enough
        // that cornering cannot lever it over.
        let hang = centerOfMass
            ?? Vector3(0, wheels.map(\.position.y).reduce(0, +) / Double(wheels.count), 0)
        let body = addBody(chassis, at: position, kind: .dynamic, isSensor: false,
                           rotated: angle, axis: axis, density: 1,
                           friction: friction, restitution: nil, mass: mass,
                           centerOfMass: hang)
        guard let vehicle = Vehicle3D(world: self, chassis: body, wheels: wheels,
                                      engineTorque: engineTorque,
                                      topSpeed: topSpeed,
                                      antiRollStiffness: 1000, leans: balances,
                                      maxLeanAngle: maxLeanAngle) else {
            remove(body)
            noteOnce("the vehicle could not be built; check its wheels")
            return nil
        }
        vehicles.append(vehicle)
        return vehicle
    }

    /// Remove a vehicle and its chassis body from the world.
    public func remove(_ vehicle: Vehicle3D) {
        // The constraint holds the chassis, so it comes off first.
        vehicle.destroyBackingVehicle()
        vehicles.removeAll { $0 === vehicle }
        remove(vehicle.body)
    }

    /// Remove a walking character from the world.
    public func remove(_ character: Character3D) {
        let innerID = character.body.id
        bodyByID[innerID] = nil
        forgetTouches(of: innerID)
        contacts.removeAll { $0.involves(character.body) }
        characters.removeAll { $0 === character }
    }

    /// Link two rigid bodies with a `Joint3D` and return it: a hinge, a
    /// ball-and-socket, a rod, a weld, or a slider (see `JointKind3D`).
    /// Anchors are world points at the moment of connecting.
    @discardableResult
    public func connect(_ a: Body3D, _ b: Body3D, _ kind: JointKind3D) -> Joint3D {
        var desc = CJoltConstraintDesc()
        switch kind {
        case .revolute(let at, let axis, let limits):
            desc.type = CJOLT_CONSTRAINT_HINGE
            let p = meters(from: at)
            desc.anchorA = (p.0, p.1, p.2)
            let unit = axis.normalized
            desc.axis = (Float(unit.x), Float(unit.y), Float(unit.z))
            if let limits {
                // The solver wants the swing measured from the connect pose,
                // min in [-pi, 0] and max in [0, pi]; clamp so a range that
                // misses 0 still creates a working hinge.
                desc.hasLimits = true
                desc.limitMin = Float(min(max(limits.lowerBound, -.pi), 0))
                desc.limitMax = Float(max(min(limits.upperBound, .pi), 0))
            }

        case .ball(let at):
            desc.type = CJOLT_CONSTRAINT_POINT
            let p = meters(from: at)
            desc.anchorA = (p.0, p.1, p.2)

        case .distance(let from, let to, let length, let stiffness):
            desc.type = CJOLT_CONSTRAINT_DISTANCE
            let pa = meters(from: from)
            let pb = meters(from: to)
            desc.anchorA = (pa.0, pa.1, pa.2)
            desc.anchorB = (pb.0, pb.1, pb.2)
            if let length {
                desc.hasLimits = true
                let l = Float(length / unitsPerMeter)
                desc.limitMin = l
                desc.limitMax = l
            }
            if stiffness < 1 {
                desc.frequency = Float(1 + max(0, stiffness) * 8) // soft … firm
                desc.damping = 0.5
            }

        case .weld:
            desc.type = CJOLT_CONSTRAINT_FIXED

        case .prismatic(let at, let axis, let limits):
            desc.type = CJOLT_CONSTRAINT_SLIDER
            let p = meters(from: at)
            desc.anchorA = (p.0, p.1, p.2)
            let unit = axis.normalized
            desc.axis = (Float(unit.x), Float(unit.y), Float(unit.z))
            if let limits {
                // Travel is measured from the connect pose, min <= 0 <= max.
                desc.hasLimits = true
                desc.limitMin = Float(min(limits.lowerBound / unitsPerMeter, 0))
                desc.limitMax = Float(max(limits.upperBound / unitsPerMeter, 0))
            }
        }

        let constraint = withUnsafePointer(to: &desc) {
            cjolt_constraint_create(handle, a.id, b.id, $0)
        }
        let joint = Joint3D(world: self, constraint: constraint, a: a.id, b: b.id,
                            kind: kind)
        joints.append(joint)
        return joint
    }

    /// Grab a body and pull it toward a moving world point (the drag joint).
    /// Update the returned joint's `target` each frame, and `remove()` it to
    /// let go. (For grabbing with the mouse through the camera, the sketch
    /// sugar `grabBody(at:in:)` / `dragGrab(_:to:)` wraps this and the ray.)
    @discardableResult
    public func grab(_ body: Body3D, at point: Vector3) -> Joint3D {
        var constraint: OpaquePointer?
        withFloats3(meters(from: point)) {
            constraint = cjolt_grab_begin(handle, body.id, $0)
        }
        let joint = Joint3D(world: self, constraint: constraint, a: body.id,
                            b: CJOLT_BODY_INVALID, isGrab: true)
        joint.target = point
        joints.append(joint)
        return joint
    }

    /// Remove a body and any joints attached to it.
    public func remove(_ body: Body3D) {
        for joint in joints where joint.a == body.id || joint.b == body.id {
            joint.destroyBackingConstraint()
        }
        joints.removeAll { $0.a == body.id || $0.b == body.id }
        cjolt_body_destroy(handle, body.id)
        bodies.removeAll { $0 === body }
        bodyByID[body.id] = nil
        forgetTouches(of: body.id)
        contacts.removeAll { $0.involves(body) }
    }

    /// Empty the world.
    public func removeAll() {
        // Joints and vehicles before bodies: both are constraints on bodies,
        // and destroying a body would invalidate them.
        for joint in joints { joint.destroyBackingConstraint() }
        joints.removeAll()
        for vehicle in vehicles { vehicle.destroyBackingVehicle() }
        vehicles.removeAll()
        // Characters own their inner bodies and destroy them on release.
        characters.removeAll()
        for body in bodies { cjolt_body_destroy(handle, body.id) }
        bodies.removeAll()
        bodyByID.removeAll()
        touchingIDs.removeAll()
        contacts.removeAll()
        // `bodyByID` was just emptied; put the floor slab back in it.
        if let groundBody { bodyByID[groundBody.id] = groundBody }
    }

    /// Destroy a joint (called by `Joint3D.remove()`).
    func removeJoint(_ joint: Joint3D) {
        joint.destroyBackingConstraint()
        joints.removeAll { $0 === joint }
    }

    // MARK: Stepping

    /// Advance the simulation by `dt` seconds (clamped to `maxTimestep`). Call
    /// once per frame with `deltaTime`.
    public func step(dt: Double) {
        let clamped = min(max(dt, 0), maxTimestep)
        // A skipped step leaves the last one's contacts standing rather than
        // silently emptying them, so a paused frame reads what a paused world
        // is still touching.
        guard clamped > 0 else { return }
        lastTimestep = clamped
        // Gravity re-syncs every step (the 2D world's model), so changing it
        // or the unit scale between steps always takes effect.
        let g = meters(from: gravity)
        cjolt_world_set_gravity(handle, g.0, g.1, g.2)
        // Characters are swept by hand rather than integrated by the solver,
        // so they move first, against the world as it stands: the order the
        // library's own character update runs in.
        for character in characters { character.advance(dt: clamped) }
        // A vehicle's wheels are collided and driven by the solver's own step
        // listener, so all it needs beforehand is this frame's controls.
        for vehicle in vehicles { vehicle.advance() }
        // One collision pass per ~60 Hz of simulated time keeps long frames
        // stable without costing short ones anything.
        let passes = max(1, Int((clamped * 60).rounded(.up)))
        _ = cjolt_world_step(handle, Float(clamped), Int32(passes))
        // The solver's worker threads filled a buffer while it ran; empty it
        // here, on the one thread the sketch reads from.
        drainContacts()
    }

    /// Drive a grab joint's anchor toward its `target` (called from the
    /// joint's `target` setter).
    func dragGrab(_ joint: Joint3D) {
        guard let constraint = joint.constraint else { return }
        withFloats3(meters(from: joint.target)) {
            cjolt_grab_move(handle, constraint, $0)
        }
    }

    // MARK: The ground slab

    /// (Re)build the static floor from `ground`.
    private func rebuildGround() {
        if groundID != CJOLT_BODY_INVALID {
            cjolt_body_destroy(handle, groundID)
            bodyByID[groundID] = nil
            forgetTouches(of: groundID)
            groundID = CJOLT_BODY_INVALID
            groundBody = nil
        }
        guard let level = ground else { return }

        // A wide slab whose top face sits at the ground level.
        let extent = 500.0 / unitsPerMeter
        let thickness = 1.0 / unitsPerMeter
        var desc = CJoltBodyDesc()
        desc.shape.type = CJOLT_SHAPE_BOX
        desc.shape.a = Float(extent)
        desc.shape.b = Float(thickness / 2)
        desc.shape.c = Float(extent)
        desc.position = (0, Float((level / unitsPerMeter) - thickness / 2), 0)
        desc.rotation = (0, 0, 0, 1)
        desc.motion = CJOLT_MOTION_STATIC
        desc.friction = 0.5
        desc.restitution = Float(bounce)
        desc.allowSleep = true
        desc.gravityFactor = 1
        groundID = withUnsafePointer(to: &desc) { cjolt_body_create(handle, $0) }
        // Registered so contacts with the floor name a body, but kept out of
        // `bodies`: a sketch's drawing loop never asked for a 1000-unit slab.
        let slab = Body3D(world: self, id: groundID,
                          collider: .box(width: 2 * extent * unitsPerMeter,
                                         height: thickness * unitsPerMeter,
                                         depth: 2 * extent * unitsPerMeter),
                          kind: .static, density: 1)
        bodyByID[groundID] = slab
        groundBody = slab
    }

    // MARK: One-time notes

    /// Messages printed once per world for calls a joint can't honor (a motor
    /// on a ball joint, say), keyed by message so each prints once rather than
    /// every frame.
    private var worldNotes = Set<String>()
    func noteOnce(_ message: String) {
        guard !worldNotes.contains(message) else { return }
        worldNotes.insert(message)
        print("Ollin: \(message)")
    }

    // MARK: Unit conversion (world units = meters · unitsPerMeter)

    func meters(from v: Vector3) -> (Float, Float, Float) {
        (Float(v.x / unitsPerMeter), Float(v.y / unitsPerMeter),
         Float(v.z / unitsPerMeter))
    }

    func meters(from s: Double) -> Float {
        Float(s / unitsPerMeter)
    }

    func units(from x: Float, _ y: Float, _ z: Float) -> Vector3 {
        Vector3(Double(x) * unitsPerMeter, Double(y) * unitsPerMeter,
                Double(z) * unitsPerMeter)
    }
}
