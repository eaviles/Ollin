import Foundation
import simd
import Ollin
internal import CJolt

/// The 3D rigid-body simulation: `Body3D`s that stack, tumble, and swing inside
/// the 3D scene, joined by `Joint3D`s and stepped each frame. The spatial
/// sibling of the 2D `World`'s rigid side, sharing its shape: build a world
/// once, add bodies, call `advance(by:)` each frame, and draw each body from its
/// pose (`withBody(_:)` moves the transform stack there).
///
/// ```swift
/// let world = World3D()
/// world.ground = 0                       // a static floor at y = 0
/// let box = world.addBody(.box(width: 1, height: 1, depth: 1),
///                         at: Vector3(0, 4, 0))
/// // each frame:
/// world.advance(by: deltaTime)
/// withBody(box) { drawBox(width: 1, height: 1, depth: 1) }
/// ```
///
/// Distances are the 3D scene's world units (y-up, matching the camera), with
/// `unitsPerMeter` bridging to the solver's meters; the default of 1 treats a
/// 1-unit box as 1 m, the solver's sweet spot, which is also the scale the 3D
/// examples already draw at.
public final class World3D {

    /// The grab `dragBodies(in:)` is holding, and whether the current press
    /// already tried and missed (so a miss does not retry every held frame).
    /// On the world rather than the sketch, so several worlds drag on their
    /// own.
    var pointerGrab: Joint3D?
    var pointerGrabAttempted = false

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

    /// Water filling the world below a level, or `nil` (the default) for a dry
    /// world. Bodies lighter than it float, bob, and drift; heavier ones sink
    /// through. Nothing opts in: setting this floats whatever is already here.
    ///
    /// ```swift
    /// world.water = Water(level: 0)
    /// ```
    public var water: Water? {
        didSet { if water != oldValue { waterMoved = true } }
    }

    /// Default restitution `0…1` for the ground and for bodies that don't pass
    /// their own: how much speed survives a restitution. Kept low so stacks settle.
    public var restitution: Double = 0.2

    /// The largest timestep a single `advance(by:)` will integrate, in seconds.
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

    /// The static slab behind `ground`, so a contact can be recognized as a
    /// landing: `contact.other(than: ball) === world.groundBody`. `nil` when
    /// the world has no ground.
    public private(set) var groundBody: Body3D?

    /// Every joint between bodies, in the order added.
    public private(set) var joints: [Joint3D] = []

    /// Every walking `Character3D` in the world, in the order added. Each one
    /// is swept forward by `advance(by:)` along with the bodies.
    public private(set) var characters: [Character3D] = []

    /// Every `Vehicle3D` in the world, in the order added. Each one's controls
    /// are handed to the solver by `advance(by:)`.
    public private(set) var vehicles: [Vehicle3D] = []

    /// Every `Ragdoll3D` in the world, in the order added. Their limb bodies
    /// are simulated with everything else; they are not in `bodies`, since a
    /// sketch draws the figure's mesh rather than the capsules under it.
    public private(set) var ragdolls: [Ragdoll3D] = []

    /// Every `SoftBody3D` in the world, in the order added. Their bodies are
    /// simulated with everything else; they are not in `bodies`, whose surface
    /// (one pose, one velocity, impulses) does not describe them.
    public private(set) var softBodies: [SoftBody3D] = []

    /// Every `Tensegrity3D` in the world, in the order added. Their struts are
    /// ordinary bodies and sit in `bodies` too; their cables sit in `joints`.
    public private(set) var tensegrities: [Tensegrity3D] = []

    /// Every touch that started or stopped during the most recent `advance(by:)`,
    /// including bodies entering and leaving a sensor. Poll it in `draw()` the
    /// way mouse state is polled; the list is replaced by the next step, and
    /// reading it twice reads the same events.
    ///
    /// ```swift
    /// world.advance(by: deltaTime)
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

    /// Soft bodies by the same handles, since a contact or a query hit may
    /// name one of those instead (`colliding(at:)` asks both).
    var softBodyByID: [CJoltBodyID: SoftBody3D] = [:]

    /// The collision groups this world knows, in the order first named, which
    /// is also the solver's own indexing: slot 0 is `.default`.
    var groupNames: [CollisionGroup] = [.default]
    var groupIndices: [CollisionGroup: Int32] = [.default: 0]

    /// Who is currently touching whom, kept up to date from the drained
    /// contact events (sorted, so `Body3D.touching` reads the same order every
    /// run).
    var touchingIDs: [CJoltBodyID: [CJoltBodyID]] = [:]

    /// The timestep used on the previous `step`, so a grab drag knows how fast
    /// the hand is allowed to move its anchor.
    var lastTimestep: Double = 1.0 / 60

    /// Counts the steps taken, so a soft body can tell whether the mesh it read
    /// back last is still the current one.
    private(set) var stepGeneration: Int = 0

    /// The solver handle of the slab backing `ground`, if any.
    var groundID: CJoltBodyID = CJOLT_BODY_INVALID

    /// Which collision group the floor slab is in. Remembered on the world
    /// rather than on the slab, because moving the ground or changing the unit
    /// scale builds a whole new slab, which would otherwise arrive back in the
    /// default group having quietly forgotten what it was told.
    var groundGroup: CollisionGroup = .default

    /// How far into the swell the water is, in seconds of simulated time, so
    /// the surface a sketch draws and the surface the bodies ride are read at
    /// the same moment. Advanced by `advance(by:)`, so a fixed timestep replays
    /// the same waves. Read it to drive a shader's own waves in step with the
    /// ones the bodies are riding.
    public internal(set) var waterPhase: Double = 0

    /// Whether the water changed since the last step, which is what tells the
    /// buoyancyScale pass to wake bodies that had settled at the old surface.
    var waterMoved = false

    /// Scratch for the buoyancyScale pass's query, kept between steps so a floating
    /// scene allocates nothing per frame.
    var waterBodies: [CJoltBodyID] = []
    var waterCenters: [Float] = []

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
        for ragdoll in ragdolls { ragdoll.isDestroyed = true }
        for soft in softBodies { soft.isDestroyed = true }
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
    ///   - restitution: bounciness `0…1`; defaults to the world's `restitution`.
    ///   - freedom: which ways it may move. `.all` (the default) leaves it
    ///     free; `.plane()` keeps it flat, `.upright` keeps it from tipping.
    ///   - gravityScale: how hard gravity pulls on this one body, against the
    ///     `1` everything else feels. `0` is weightless, negative rises.
    ///   - checksPath: sweep its shape along its whole path each step so a
    ///     small quick body can't pass through a thin wall between two steps.
    ///   - group: which collision group it joins. Everything is in `.default`
    ///     and collides with everything until `ignoreCollisions(between:and:)`
    ///     says two groups pass through each other.
    @discardableResult
    public func addBody(_ collider: Collider3D, at position: Vector3,
                        kind: Body3D.Kind = .dynamic, isSensor: Bool = false,
                        rotated angle: Double = 0, axis: Vector3 = .unitY,
                        density: Double = 1, friction: Double = 0.5,
                        restitution: Double? = nil,
                        freedom: Freedom3D = .all, gravityScale: Double = 1,
                        checksPath: Bool = false,
                        group: CollisionGroup = .default) -> Body3D {
        addBody(collider, at: position, kind: kind, isSensor: isSensor,
                rotated: angle, axis: axis, density: density, friction: friction,
                restitution: restitution, mass: nil, centerOfMass: .zero,
                freedom: freedom, gravityScale: gravityScale,
                checksPath: checksPath, group: group)
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
                 centerOfMass: Vector3,
                 freedom: Freedom3D = .all, gravityScale: Double = 1,
                 checksPath: Bool = false,
                 group: CollisionGroup = .default,
                 orientation: SIMD4<Double>? = nil,
                 velocity: Vector3 = .zero,
                 angularVelocity: Vector3 = .zero,
                 asleep: Bool = false) -> Body3D {
        var desc = CJoltBodyDesc()
        let p = meters(from: position)
        desc.position = (p.0, p.1, p.2)
        if let orientation {
            // A restored body is handed the exact quaternion it was captured
            // with, rather than an angle about an axis that would have to be
            // taken apart and put back together.
            desc.rotation = (Float(orientation.x), Float(orientation.y),
                             Float(orientation.z), Float(orientation.w))
        } else {
            let unit = axis.normalized
            let half = angle / 2
            let s = sin(half)
            desc.rotation = (Float(unit.x * s), Float(unit.y * s),
                             Float(unit.z * s), Float(cos(half)))
        }
        let v = meters(from: velocity)
        desc.linearVelocity = (v.0, v.1, v.2)
        desc.angularVelocity = (Float(angularVelocity.x), Float(angularVelocity.y),
                                Float(angularVelocity.z))
        desc.startAsleep = asleep
        desc.motion = kind.cjolt
        desc.friction = Float(max(0, friction))
        desc.restitution = Float(restitution ?? self.restitution)
        desc.linearDamping = 0.05
        desc.angularDamping = 0.05
        desc.gravityFactor = Float(gravityScale)
        desc.allowSleep = true
        desc.isSensor = isSensor
        // A body free every way sends 0, which the bridge reads as
        // unrestricted, so an ordinary body carries no restriction at all.
        desc.freedom = freedom == .all ? 0 : freedom.rawValue
        desc.continuous = checksPath
        desc.group = groupIndex(group)
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
                          isSensor: isSensor, overriddenMass: mass)
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
    /// world.addStaticBodies(from: hall)
    /// ```
    @discardableResult
    public func addStaticBodies(from scene: Scene, friction: Double = 0.5,
                                   restitution: Double? = nil,
                                   group: CollisionGroup = .default) -> [Body3D] {
        var added: [Body3D] = []
        Scene.visitWorlds(scene.nodes, parent: matrix_identity_float4x4) { node, world in
            guard var mesh = node.mesh, !mesh.isEmpty else { return }
            mesh.positions = mesh.positions.map { position in
                let w = world * SIMD4<Float>(Float(position.x), Float(position.y),
                                             Float(position.z), 1)
                return Vector3(Double(w.x), Double(w.y), Double(w.z))
            }
            added.append(addBody(.mesh(mesh), at: .zero, kind: .static,
                                 friction: friction, restitution: restitution,
                                 group: group))
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
    ///   - group: which collision group it walks in, filtering what it can walk
    ///     through, including other characters.
    @discardableResult
    public func addCharacter(radius: Double = 0.3, height: Double = 1.8,
                             at position: Vector3, stepHeight: Double = 0.4,
                             stickToFloorDistance: Double = 0.5,
                             maxSlope: Double = 50 * .pi / 180,
                             mass: Double = 70,
                             pushStrength: Double = 100,
                             group: CollisionGroup = .default) -> Character3D {
        let character = Character3D(world: self, radius: radius, height: height,
                                    position: position, stepHeight: stepHeight,
                                    stickToFloorDistance: stickToFloorDistance,
                                    maxSlope: maxSlope, mass: mass,
                                    pushStrength: pushStrength,
                                    group: group)!
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
    ///   - engineTorque: how hard the engine pulls, in newton-meters.
    ///   - topSpeed: the speed the gearing tops out at, in world units per
    ///     second. Lower gears the vehicle down for more pull.
    ///   - centerOfMass: where the weight hangs, in the chassis's local space.
    ///     `nil` (the default) drops it to the height of the wheel mounts,
    ///     which is what keeps a vehicle from rolling over in a turn.
    ///   - balances: a two-wheeler that holds itself up, leaning into turns
    ///     instead of falling over.
    ///   - tracked: a machine on two tracks rather than steered wheels. The
    ///     wheels become road wheels, split into a left and a right band by
    ///     which side of the hull they sit on, and `steering` runs one band
    ///     faster than the other rather than turning anything.
    ///   - group: which collision group the chassis and its wheels are in: the
    ///     wheels feel for the road in the same group the body collides in.
    @discardableResult
    public func addVehicle(_ chassis: Collider3D, at position: Vector3,
                           wheels: [Wheel3D], mass: Double = 1500,
                           engineTorque: Double = 500, topSpeed: Double = 30,
                           centerOfMass: Vector3? = nil,
                           rotated angle: Double = 0, axis: Vector3 = .unitY,
                           friction: Double = 0.5,
                           balances: Bool = false,
                           maxLeanAngle: Double = 45 * .pi / 180,
                           isTracked: Bool = false,
                           group: CollisionGroup = .default) -> Vehicle3D? {
        guard !wheels.isEmpty else {
            noteOnce("a vehicle needs at least one wheel")
            return nil
        }
        if isTracked, balances {
            noteOnce("a tracked machine does not lean; ignoring balances")
        }
        // Weight that hangs at axle height is what stops a vehicle from
        // toppling: it is high enough to be inside the body and low enough
        // that cornering cannot lever it over.
        let hang = centerOfMass
            ?? Vector3(0, wheels.map(\.position.y).reduce(0, +) / Double(wheels.count), 0)
        let body = addBody(chassis, at: position, kind: .dynamic, isSensor: false,
                           rotated: angle, axis: axis, density: 1,
                           friction: friction, restitution: nil, mass: mass,
                           centerOfMass: hang, group: group)
        guard let vehicle = Vehicle3D(world: self, chassis: body, wheels: wheels,
                                      engineTorque: engineTorque,
                                      topSpeed: topSpeed,
                                      antiRollStiffness: 1000,
                                      leans: balances && !isTracked,
                                      maxLeanAngle: maxLeanAngle,
                                      tracked: isTracked, mass: mass,
                                      centerOfMass: hang) else {
            remove(body)
            noteOnce(isTracked
                     ? "a tracked machine needs road wheels on both sides of "
                        + "the hull; check where its wheels sit"
                     : "the vehicle could not be built; check its wheels")
            return nil
        }
        vehicles.append(vehicle)
        return vehicle
    }

    /// Add a `Ragdoll3D`: a skinned figure from a loaded `Scene` given weight,
    /// one rigid body per skeleton joint with a shape fitted to the mesh that
    /// joint carries. Step the world, then write the simulated pose back onto
    /// the scene with `scene.apply(ragdoll)` and draw it.
    ///
    /// ```swift
    /// var figure = loadScene("figure.gltf")!
    /// let ragdoll = world.addRagdoll(from: figure, at: Vector3(0, 3, 0))
    /// ```
    ///
    /// Returns `nil` for a scene with no skin.
    ///
    /// - Parameters:
    ///   - scene: the figure, in the pose the ragdoll is built from (usually as
    ///     loaded, its rest pose).
    ///   - at: where to stand its root joint; `nil` keeps the pose the file
    ///     authored.
    ///   - joints: the names of the joints that get their own body. `nil` (the
    ///     default) gives every joint one. A named subset always keeps the
    ///     root, and every joint left out rides the nearest one that is in, so
    ///     naming a dozen joints of a hundred-bone rig makes a figure with a
    ///     dozen limbs rather than a broken one.
    ///   - swing: how far a joint's bone may lean off where it started, in
    ///     radians: a cone. The default is a loose 50°.
    ///   - twist: how far a joint may roll about its own bone, in radians.
    ///   - mass: the whole figure's weight in kilograms, split between the
    ///     limbs by how much of the mesh each one fills. `0` leaves it to the
    ///     shapes' own volume.
    ///   - friction: the limbs' surface friction, `0` slick … `1` grippy.
    ///   - group: which collision group every limb joins. The separate filter
    ///     that keeps one figure's own limbs from fighting each other is
    ///     untouched, so two figures in one group still collide.
    @discardableResult
    public func addRagdoll(from scene: Scene, at position: Vector3? = nil,
                           joints: [String]? = nil,
                           swing: Double = 50 * .pi / 180,
                           twist: ClosedRange<Double> = -0.3...0.3,
                           mass: Double = 70,
                           friction: Double = 0.5,
                           group: CollisionGroup = .default) -> Ragdoll3D? {
        guard let ragdoll = Ragdoll3D(world: self, scene: scene, at: position,
                                      joints: joints, swing: swing, twist: twist,
                                      mass: mass, friction: friction,
                                      group: group) else {
            return nil
        }
        ragdolls.append(ragdoll)
        return ragdoll
    }

    /// Add a figure from a fitting rather than from a scene: what a snapshot
    /// restores, since the fitting is what a skinned scene is worked down to.
    func addRagdoll(plan: RagdollPlan, limits: [RagdollLimit], friction: Double,
                    group: CollisionGroup) -> Ragdoll3D? {
        guard let ragdoll = Ragdoll3D(world: self, plan: plan, limits: limits,
                                      friction: friction, group: group) else {
            return nil
        }
        ragdolls.append(ragdoll)
        return ragdoll
    }

    /// Add a soft body built from `mesh` and return it: a surface of simulated
    /// particles that drapes, folds, and squashes rather than moving as one
    /// rigid piece.
    ///
    /// The mesh's coincident vertices are merged into shared particles first, so
    /// a flat-shaded generator mesh (whose triangles share no vertex index)
    /// still comes out as one connected sheet. Everything the mesh carries
    /// besides positions rides through to the simulated copy.
    ///
    /// - Parameters:
    ///   - mesh: the rest shape. An open surface is cloth; a closed one can be
    ///     pressurised into a ball.
    ///   - position: where the rest shape is placed in the world.
    ///   - rotated: how far the rest shape is turned, in radians, about
    ///     `axis`, applied before it is placed.
    ///   - axis: the axis `rotated` turns about.
    ///   - mass: the whole body's weight in kilograms, split evenly between its
    ///     particles.
    ///   - stiffness: how hard the surface resists being stretched, `0` slack
    ///     … `1` inextensible.
    ///   - bend: how hard it resists being folded, `0` (the default) limp like
    ///     fabric … `1` stiff like card. Anything above 0 costs a constraint
    ///     per pair of neighboring faces.
    ///   - pressure: how hard the inside of a closed surface pushes out, in
    ///     gravities: `1` just holds its own weight up, `2`…`4` reads as a firm
    ///     ball. Ignored on an open sheet.
    ///   - damping: how quickly particle motion bleeds away.
    ///   - friction: the surface's friction against what it lands on.
    ///   - restitution: how much speed survives a restitution; `nil` takes the world's.
    ///   - iterations: solver passes per step; more is stiffer and steadier.
    ///   - vertexRadius: how far each particle's body reaches past its
    ///     position, which lifts a draped surface clear of what it lies on.
    ///   - isTwoSided: collide with the back of every face as well as the front.
    ///   - pinned: given a vertex of `mesh` in the mesh's own space, whether it
    ///     is held in place. This is how a flag hangs from its corners. A
    ///     pinned vertex a joint carries is held by the *figure* rather than by
    ///     the world, which is how a cape stays on the shoulders.
    ///   - skinnedTo: a skinned scene whose skeleton carries part of the
    ///     surface. The pose it is standing in right now is the bind pose, so
    ///     hang the cloth where it belongs and then build it.
    ///   - carriedBy: given a vertex of `mesh`, the name of the joint that
    ///     carries it, or `nil` for ordinary cloth. Needs `skinnedTo`.
    ///   - sway: given a carried vertex, how far it may travel from where the
    ///     skeleton puts it, in world units. `0` holds it exactly there and
    ///     `.infinity` (the default) leaves it free to swing.
    ///   - backStop: how far behind the carried surface a particle may be
    ///     pushed before it is held back out, in world units, which is what
    ///     keeps a cape from sinking into the back it hangs on.
    ///   - maxStretch: how far the surface may reach from what holds it, as a
    ///     multiple of its own rest distance along the cloth: `1` is
    ///     inextensible, `1.05` allows 5%. `nil` (the default) lets the springs
    ///     alone decide, which is a hung cloth stretching under its own weight.
    ///   - group: which collision group the surface is in.
    @discardableResult
    public func addSoftBody(from mesh: Mesh, at position: Vector3 = .zero,
                            rotated angle: Double = 0, axis: Vector3 = .unitY,
                            mass: Double = 1,
                            stiffness: Double = 1,
                            bend: Double = 0,
                            pressure: Double = 0,
                            damping: Double = 0.1,
                            friction: Double = 0.5,
                            restitution: Double? = nil,
                            iterations: Int = 5,
                            vertexRadius: Double = 0,
                            isTwoSided twoSided: Bool = true,
                            pinned: ((Vector3) -> Bool)? = nil,
                            skinnedTo scene: Scene? = nil,
                            carriedBy: ((Vector3) -> String?)? = nil,
                            sway: ((Vector3) -> Double)? = nil,
                            backStop: Double? = nil,
                            maxStretch: Double? = nil,
                            group: CollisionGroup = .default) -> SoftBody3D? {
        let direction = axis.lengthSquared > 1e-18 ? axis.normalized : Vector3(0, 1, 0)
        let turn = simd_quatd(angle: angle,
                              axis: simd_double3(direction.x, direction.y, direction.z))
        if carriedBy != nil && scene == nil {
            noteOnce("carriedBy names joints of a skeleton, so it needs a "
                     + "skinnedTo: scene to look them up in; the surface is "
                     + "ordinary cloth")
        }
        return makeSoftBody(mesh: mesh, position: position, rotation: turn,
                            mass: mass, stiffness: stiffness, bend: bend,
                            pressure: pressure, damping: damping,
                            friction: friction, restitution: restitution ?? self.restitution,
                            iterations: iterations, vertexRadius: vertexRadius,
                            isTwoSided: twoSided, pinned: pinned, group: group,
                            skeleton: scene?.skeleton() ?? [],
                            carriedBy: carriedBy, sway: sway, backStop: backStop,
                            maxStretch: maxStretch, restoredSkin: nil)
    }

    /// The one place a soft body is built and registered. A restore comes
    /// through here too, handing over the skin it wrote down rather than the
    /// closures that first decided it, so a surface that comes back is one the
    /// ordinary call could have made.
    func makeSoftBody(mesh: Mesh, position: Vector3, rotation: simd_quatd,
                      mass: Double, stiffness: Double, bend: Double,
                      pressure: Double, damping: Double, friction: Double,
                      restitution: Double, iterations: Int, vertexRadius: Double,
                      isTwoSided twoSided: Bool, pinned: ((Vector3) -> Bool)?,
                      group: CollisionGroup, skeleton: [SceneSkeletonJoint],
                      carriedBy: ((Vector3) -> String?)?,
                      sway: ((Vector3) -> Double)?, backStop: Double?,
                      maxStretch: Double?,
                      restoredSkin: SoftBody3D.Skin?) -> SoftBody3D? {
        guard let soft = SoftBody3D(world: self, mesh: mesh, position: position,
                                    rotation: rotation, mass: mass,
                                    stiffness: stiffness, bend: bend,
                                    pressure: pressure, damping: damping,
                                    friction: friction,
                                    restitution: restitution,
                                    iterations: iterations,
                                    vertexRadius: vertexRadius,
                                    isTwoSided: twoSided, pinned: pinned,
                                    group: group, skeleton: skeleton,
                                    carriedBy: carriedBy, sway: sway,
                                    backStop: backStop, maxStretch: maxStretch,
                                    restoredSkin: restoredSkin)
        else {
            noteOnce("addSoftBody needs a mesh with at least one triangle whose "
                     + "corners are distinct; nothing was added.")
            return nil
        }
        softBodies.append(soft)
        softBodyByID[soft.bodyID] = soft
        return soft
    }

    /// Add a rope: a line of particles held by rigid rods, which is the soft
    /// body whose shape is a curve rather than a surface. Cable, chain, hair, a
    /// vine, the stem of a plant.
    ///
    /// It rests on the polyline it is given, so anything that makes one makes a
    /// rope: hand-placed points, a sampled `Path`, a `Contour`, a `randomWalk`.
    ///
    /// ```swift
    /// let line = world.addRope(through: (0...30).map { Vector3(0, 4 - Double($0) * 0.1, 0) },
    ///                          thickness: 0.03,
    ///                          pinned: { $0.y > 3.9 })
    /// ```
    ///
    /// Each rod carries its own orientation, which is what a rope has that a
    /// chain of springs does not: read `Rope3D.segments` to hang links, leaves,
    /// or beads along it.
    ///
    /// - Parameters:
    ///   - points: the rope's rest shape, in its own local space. Two points
    ///     make the shortest usable rope; more make it bend in more places.
    ///   - position: where the rest shape stands in the world.
    ///   - rotated: how far the rest shape is turned, in radians, about `axis`.
    ///   - thickness: the rope's radius, which is both what it draws as and how
    ///     far it stands off whatever it lies on.
    ///   - sides: how many sides the drawn tube has.
    ///   - mass: the whole rope's mass, spread evenly over its particles.
    ///   - stiffness: how much the rope resists being stretched, 0 to 1. `1` is
    ///     a steel cable and lower is elastic.
    ///   - bend: how much it resists being bent and twisted, 0 to 1. `0` is limp
    ///     rope, low values are cable, and high values are a stem or a branch
    ///     that holds its own shape.
    ///   - damping: how quickly its motion dies away.
    ///   - friction: how much it grips what it slides against.
    ///   - restitution: how much it rebounds, defaulting to the world's own.
    ///   - iterations: solver passes per step. More holds a long rope steadier.
    ///   - pinned: given a point in the rope's own space, whether it is held in
    ///     place. This is how a rope hangs from a hook.
    ///   - maxStretch: how far the rope may reach from what holds it, as a
    ///     multiple of its own rest length: `1` is inextensible. `nil` lets the
    ///     rods alone decide.
    ///   - group: which collision group the rope is in.
    @discardableResult
    public func addRope(through points: [Vector3], at position: Vector3 = .zero,
                        rotated angle: Double = 0, axis: Vector3 = .unitY,
                        thickness: Double = 0.05,
                        sides: Int = 8,
                        mass: Double = 1,
                        stiffness: Double = 1,
                        bend: Double = 0,
                        damping: Double = 0.1,
                        friction: Double = 0.5,
                        restitution: Double? = nil,
                        iterations: Int = 5,
                        pinned: ((Vector3) -> Bool)? = nil,
                        maxStretch: Double? = nil,
                        group: CollisionGroup = .default) -> Rope3D? {
        let direction = axis.lengthSquared > 1e-18 ? axis.normalized : Vector3(0, 1, 0)
        let turn = simd_quatd(angle: angle,
                              axis: simd_double3(direction.x, direction.y, direction.z))
        return makeRope(points: points, position: position, rotation: turn,
                        thickness: thickness, sides: sides, mass: mass,
                        stiffness: stiffness, bend: bend, damping: damping,
                        friction: friction, restitution: restitution ?? self.restitution,
                        iterations: iterations, pinned: pinned,
                        maxStretch: maxStretch, group: group)
    }

    /// The one place a rope is built and registered, which a restore comes
    /// through too, so a rope that comes back is one the ordinary call could
    /// have made.
    func makeRope(points: [Vector3], position: Vector3, rotation: simd_quatd,
                  thickness: Double, sides: Int, mass: Double,
                  stiffness: Double, bend: Double, damping: Double,
                  friction: Double, restitution: Double, iterations: Int,
                  pinned: ((Vector3) -> Bool)?, maxStretch: Double?,
                  group: CollisionGroup,
                  rodRotations: [simd_quatd] = []) -> Rope3D? {
        guard let rope = Rope3D(world: self, points: points, position: position,
                                rotation: rotation, thickness: thickness,
                                sides: sides, mass: mass, stiffness: stiffness,
                                bend: bend, damping: damping, friction: friction,
                                restitution: restitution, iterations: iterations,
                                pinned: pinned, maxStretch: maxStretch,
                                group: group, rodRotations: rodRotations)
        else {
            noteOnce("addRope needs at least two points that are not on top of "
                     + "each other; nothing was added.")
            return nil
        }
        softBodies.append(rope)
        softBodyByID[rope.bodyID] = rope
        return rope
    }

    /// Remove a soft body from the world.
    public func remove(_ softBody: SoftBody3D) {
        softBodyByID[softBody.bodyID] = nil
        forgetTouches(of: softBody.bodyID)
        contacts.removeAll { $0.involves(softBody) }
        softBodies.removeAll { $0 === softBody }
    }

    /// Build a tensegrity in the world and return it: one capsule body per
    /// strut, one `.cable` joint per cable, and a `.ball` joint wherever two
    /// struts meet at a node (a `tower`'s shared polygons). The structure is
    /// placed with its own coordinates offset by `position`, so a form whose
    /// `bottom` is zero stands on `ground` when `position.y` is zero.
    ///
    /// ```swift
    /// let mast = world.addTensegrity(Tensegrity.tower(levels: 3),
    ///                                at: Vector3(0, 0.02, 0))
    /// // each frame:
    /// world.advance(by: deltaTime)
    /// drawTensegrity(mast)
    /// ```
    ///
    /// - Parameters:
    ///   - structure: the geometry to build, in its own coordinates.
    ///   - position: where its origin lands in the world.
    ///   - strutRadius: the struts' thickness, capped so a strut is always
    ///     longer than it is wide.
    ///   - prestress: how much shorter than its drawn length each cable is
    ///     made, as a fraction. A real tensegrity is tensioned this way; with
    ///     none, a landing can leave a cable slack and the form loose. `0.02`
    ///     tightens without visibly shrinking.
    ///   - stiffness: the cables' give, `1` inextensible, less stretches.
    ///   - density: the struts' relative mass per volume.
    ///   - friction: the struts' surface friction, which is what keeps the
    ///     feet from skating when it lands.
    ///   - group: which collision group the struts join.
    @discardableResult
    public func addTensegrity(_ structure: Tensegrity, at position: Vector3 = .zero,
                              strutRadius: Double = 0.04, prestress: Double = 0.02,
                              stiffness: Double = 1, density: Double = 1,
                              friction: Double = 0.6,
                              group: CollisionGroup = .default) -> Tensegrity3D? {
        guard let built = Tensegrity3D(world: self, structure: structure,
                                       position: position, strutRadius: strutRadius,
                                       prestress: prestress, stiffness: stiffness,
                                       density: density, friction: friction,
                                       group: group)
        else {
            noteOnce("addTensegrity needs at least one strut whose two nodes "
                     + "are apart; nothing was added.")
            return nil
        }
        tensegrities.append(built)
        return built
    }

    /// Take in a tensegrity regrouped from parts already in the world (a
    /// snapshot's restore).
    func register(_ tensegrity: Tensegrity3D) {
        tensegrities.append(tensegrity)
    }

    /// Remove a tensegrity, its struts, and its cables from the world.
    public func remove(_ tensegrity: Tensegrity3D) {
        for joint in tensegrity.cables + tensegrity.jointsBetweenStruts { removeJoint(joint) }
        for strut in tensegrity.struts { remove(strut) }
        tensegrities.removeAll { $0 === tensegrity }
    }

    /// Remove a figure and every limb body it owns from the world.
    public func remove(_ ragdoll: Ragdoll3D) {
        ragdoll.destroyBackingRagdoll()
        ragdolls.removeAll { $0 === ragdoll }
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
        connect(a, b as Body3D?, kind)
    }

    /// Hold a body to the world itself: a hinge fixed in space, a rail that
    /// goes nowhere, a weld that pins a body where it stands. The world is not
    /// a body, so there is nothing for the joint to shove.
    ///
    /// ```swift
    /// // a sign swinging from a fixed point, with no post to hang it on
    /// world.connect(sign, toWorld: .revolute(at: Vector3(0, 3, 0), axis: .unitZ))
    /// ```
    ///
    /// This is what a scene that says a body is jointed to nothing in
    /// particular means, and what `world.ground` would otherwise have to
    /// stand in for.
    @discardableResult
    public func connect(_ body: Body3D, toWorld kind: JointKind3D) -> Joint3D {
        connect(body, nil, kind)
    }

    @discardableResult
    func connect(_ a: Body3D, _ b: Body3D?, _ kind: JointKind3D) -> Joint3D {
        // Where the two bodies stand right now is the joint's own zero, so it
        // is remembered on the joint: a snapshot restores a jointed machine by
        // standing the bodies back here to make the joint, then moving them on.
        let poseA = Pose3D(of: a)
        let poseB = b.map { Pose3D(of: $0) } ?? .identity
        var desc = CJoltConstraintDesc()
        // A track is the one kind that carries a list rather than a handful of
        // numbers, so its points ride a buffer the create call borrows.
        var spline: PathSpline?
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

        case .swingTwist(let at, let axis, let swing, let twist):
            desc.type = CJOLT_CONSTRAINT_SWING_TWIST
            let p = meters(from: at)
            desc.anchorA = (p.0, p.1, p.2)
            let unit = axis.normalized
            desc.axis = (Float(unit.x), Float(unit.y), Float(unit.z))
            desc.coneAngle = Float(min(max(swing, 0), .pi))
            // Twist is measured from the connect pose, so its range straddles
            // 0 the way a hinge's limits do.
            desc.hasLimits = true
            desc.limitMin = Float(min(max(twist.lowerBound, -.pi), 0))
            desc.limitMax = Float(max(min(twist.upperBound, .pi), 0))

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

        case .cable(let from, let to, let length, let stiffness):
            // The same solver constraint as a rod, with its lower limit at
            // zero: it stops the anchors parting past `length` and lets them
            // come as close as they like.
            desc.type = CJOLT_CONSTRAINT_DISTANCE
            let pa = meters(from: from)
            let pb = meters(from: to)
            desc.anchorA = (pa.0, pa.1, pa.2)
            desc.anchorB = (pb.0, pb.1, pb.2)
            desc.hasLimits = true
            desc.limitMin = 0
            desc.limitMax = Float(max(length ?? from.distance(to: to), 0) / unitsPerMeter)
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

        case .path(let points, let looping, let alignment):
            desc.type = CJOLT_CONSTRAINT_PATH
            desc.pathLooping = looping
            desc.pathAlignment = switch alignment {
            case .free: CJOLT_PATH_FREE
            case .rolls: CJOLT_PATH_ROLL
            case .followsPath: CJOLT_PATH_FOLLOW
            case .fixed: CJOLT_PATH_FIXED
            }
            spline = PathSpline(through: points, looping: looping,
                                scale: 1 / unitsPerMeter)
            if spline == nil {
                noteOnce("a .path joint needs at least two points that are not "
                         + "on top of each other; ignoring.")
            }

        case .pulley(let from, let over, let and, let to, let ratio, let taut):
            desc.type = CJOLT_CONSTRAINT_PULLEY
            let pa = meters(from: from)
            let pb = meters(from: to)
            let oa = meters(from: over)
            let ob = meters(from: and)
            desc.anchorA = (pa.0, pa.1, pa.2)
            desc.anchorB = (pb.0, pb.1, pb.2)
            desc.overA = (oa.0, oa.1, oa.2)
            desc.overB = (ob.0, ob.1, ob.2)
            desc.ratio = Float(max(ratio, 0.001))
            desc.hasLimits = taut

        case .allowing(let freedom, let at, let travel, let rotation):
            desc.type = CJOLT_CONSTRAINT_SIX_DOF
            let p = meters(from: at)
            desc.anchorA = (p.0, p.1, p.2)
            desc.freedom = freedom.rawValue
            if let travel {
                // Both bounds are measured from the connect pose, so the range
                // straddles 0 the way a slider's does.
                desc.hasLimits = true
                desc.limitMin = Float(min(travel.lowerBound / unitsPerMeter, 0))
                desc.limitMax = Float(max(travel.upperBound / unitsPerMeter, 0))
            }
            if let rotation {
                desc.hasRotationLimits = true
                desc.rotationMin = Float(min(max(rotation.lowerBound, -.pi), 0))
                desc.rotationMax = Float(max(min(rotation.upperBound, .pi), 0))
            }
        }

        let constraint: OpaquePointer?
        if let spline {
            constraint = spline.floats.withUnsafeBufferPointer { points in
                desc.pathPoints = points.baseAddress
                desc.pathPointCount = Int32(spline.count)
                return withUnsafePointer(to: &desc) {
                    cjolt_constraint_create(handle, a.id, worldEnd(b), $0)
                }
            }
        } else {
            constraint = withUnsafePointer(to: &desc) {
                cjolt_constraint_create(handle, a.id, worldEnd(b), $0)
            }
        }
        if constraint == nil, case .pulley = kind {
            noteOnce("a pulley holds ordinary and static bodies; a kinematic one "
                     + "is refused (move a static end instead). Ignoring.")
        }
        let joint = Joint3D(world: self, constraint: constraint, a: a.id,
                            b: worldEnd(b), kind: kind, connectPoseA: poseA,
                            connectPoseB: poseB)
        joints.append(joint)
        return joint
    }

    /// A joint's second end: a body, or the world itself, which the solver
    /// spells as no body at all.
    private func worldEnd(_ body: Body3D?) -> CJoltBodyID {
        body?.id ?? CJOLT_BODY_INVALID
    }

    /// Tie one joint's motion to another's: meshed gears, or a pinion turning
    /// a rack. Both parts need their own joint first (a gear is a hinge, a
    /// rack is a slider), because what a link constrains is the motion those
    /// joints allow.
    ///
    /// ```swift
    /// let small = world.connect(frame, pinion, .revolute(at: hub, axis: .unitZ))
    /// let big = world.connect(frame, wheel, .revolute(at: farHub, axis: .unitZ))
    /// world.connect(small, big, .gear(teeth: 12, and: 36))   // 3 turns to 1
    /// ```
    ///
    /// A link needs a hinge as its first joint, and a hinge (gear) or slider
    /// (rack and pinion) as its second; anything else notes once and does
    /// nothing. Each joint's moving part is the body that is not static, or the
    /// second body it was connected with when both can move.
    @discardableResult
    public func connect(_ a: Joint3D, _ b: Joint3D, _ link: JointLink3D) -> Joint3D {
        var ratio = 1.0
        var type = CJOLT_LINK_GEAR
        switch link {
        case .gear(let value):
            // Meshed teeth always turn opposite ways, so a gear ratio is a
            // count and has no sign; a negative one leaves the solver's own
            // drift correction pulling against its velocity rule until the
            // pair detonates. Turn a pair the same way by flipping one hinge's
            // axis instead.
            if value < 0 {
                noteOnce("a gear ratio counts teeth and has no sign; flip a "
                         + "hinge's axis to turn a pair the same way.")
            }
            ratio = abs(value)
        case .rackAndPinion(let travelPerTurn):
            type = CJOLT_LINK_RACK_PINION
            // The solver wants radians of pinion per meter of rack, where a
            // sketch thinks in how far the rack runs per turn.
            let travel = travelPerTurn / unitsPerMeter
            ratio = abs(travel) > 1e-9 ? 2 * .pi / travel : 0
        }

        let constraint = cjolt_constraint_link(handle, a.constraint, b.constraint,
                                               type, Float(ratio))
        if constraint == nil {
            noteOnce("a gear links two hinges and a rack and pinion a hinge to a "
                     + "slider, each with a part that can move; ignoring.")
        }
        // A link is written against four bodies and two joints, and removing
        // any of them has to take it with them.
        let joint = Joint3D(world: self, constraint: constraint, a: a.a, b: a.b,
                            alsoTouches: [b.a, b.b], linking: (a, b), link: link)
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
        for joint in joints where joint.touches(body.id) {
            joint.destroyBackingConstraint()
        }
        joints.removeAll { $0.touches(body.id) }
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
        // Ragdolls are constraints on bodies they own, so they come off before
        // the loose bodies do.
        for ragdoll in ragdolls { ragdoll.destroyBackingRagdoll() }
        ragdolls.removeAll()
        // Soft bodies own their own body and destroy it on release.
        softBodies.removeAll()
        softBodyByID.removeAll()
        // A tensegrity's struts are in `bodies` and its cables were in
        // `joints`, both handled here; only the grouping goes.
        tensegrities.removeAll()
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

    /// Destroy a joint (called by `Joint3D.remove()`), and with it any link
    /// written against it: a gear pair means nothing once one of its hinges is
    /// gone.
    func removeJoint(_ joint: Joint3D) {
        for link in joints where link.links(joint) {
            link.destroyBackingConstraint()
        }
        joint.destroyBackingConstraint()
        joints.removeAll { $0 === joint || $0.links(joint) }
    }

    // MARK: Stepping

    /// Advance the simulation by `dt` seconds (clamped to `maxTimestep`). Call
    /// once per frame with `deltaTime`.
    public func advance(by dt: Double) {
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
        // A surface a skeleton carries is posed from whatever `follow(_:)` was
        // handed this frame, once, which is what the solver interpolates its
        // skin constraints across the coming step.
        for soft in softBodies { soft.applyPendingSkin() }
        // Buoyancy is an impulse the caller applies, not something the solver
        // works out, so it goes on just before the step that will integrate it.
        applyBuoyancy(dt: clamped)
        // One collision pass per ~60 Hz of simulated time keeps long frames
        // stable without costing short ones anything.
        let passes = max(1, Int((clamped * 60).rounded(.up)))
        _ = cjolt_world_step(handle, Float(clamped), Int32(passes))
        stepGeneration &+= 1
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
        desc.restitution = Float(restitution)
        desc.allowSleep = true
        desc.gravityFactor = 1
        desc.group = groupIndex(groundGroup)
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

    /// A body just moved between collision groups. Everything else filters
    /// through the layer on its own, but a vehicle's wheels feel for the road
    /// through collision testers built against one layer, so a chassis that
    /// changed group needs a new set.
    func bodyChangedGroup(_ body: Body3D) {
        // The floor is rebuilt from scratch whenever `ground` or the unit scale
        // moves, so what it was put in has to be remembered here to survive.
        if body === groundBody { groundGroup = body.group }
        for vehicle in vehicles where vehicle.body === body {
            vehicle.syncGroupToChassis()
        }
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

    func units(from s: Float) -> Double {
        Double(s) * unitsPerMeter
    }
}
