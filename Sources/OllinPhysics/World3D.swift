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

    /// Every rigid body in the simulation, in the order added.
    public private(set) var bodies: [Body3D] = []

    /// Every joint between bodies, in the order added.
    public private(set) var joints: [Joint3D] = []

    /// The underlying solver world.
    let handle: OpaquePointer

    /// The timestep used on the previous `step`, so a grab drag knows how fast
    /// the hand is allowed to move its anchor.
    var lastTimestep: Double = 1.0 / 60

    /// The static slab backing `ground`, if any.
    private var groundBody: CJoltBodyID = CJOLT_BODY_INVALID

    /// Creates an empty world. `maxBodies` bounds how many bodies can ever be
    /// live at once (the solver reserves its tables up front).
    public init(maxBodies: Int = 4096) {
        handle = cjolt_world_create(0, Float(gravity.y), 0, UInt32(max(64, maxBodies)))!
    }

    deinit {
        cjolt_world_destroy(handle)
    }

    // MARK: Building the world

    /// Add a rigid `Body3D` with `collider` at `position` and return it.
    /// - Parameters:
    ///   - kind: `.dynamic` (default) is moved by forces; `.static` is
    ///     immovable; `.kinematic` follows only the velocity you set.
    ///   - rotated: an opening rotation about `axis`, in radians.
    ///   - density: relative mass per volume (`1` is the default material);
    ///     heavier bodies shove lighter ones.
    ///   - friction: surface friction, `0` slick … `1` grippy.
    ///   - restitution: bounciness `0…1`; defaults to the world's `bounce`.
    @discardableResult
    public func addBody(_ collider: Collider3D, at position: Vector3,
                        kind: Body3D.Kind = .dynamic,
                        rotated angle: Double = 0, axis: Vector3 = .unitY,
                        density: Double = 1, friction: Double = 0.5,
                        restitution: Double? = nil) -> Body3D {
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

        let body = Body3D(world: self, id: id, collider: collider, kind: kind,
                          density: density)
        bodies.append(body)
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
    }

    /// Empty the world.
    public func removeAll() {
        // Joints before bodies: destroying a body would invalidate its joints.
        for joint in joints { joint.destroyBackingConstraint() }
        joints.removeAll()
        for body in bodies { cjolt_body_destroy(handle, body.id) }
        bodies.removeAll()
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
        guard clamped > 0 else { return }
        lastTimestep = clamped
        // Gravity re-syncs every step (the 2D world's model), so changing it
        // or the unit scale between steps always takes effect.
        let g = meters(from: gravity)
        cjolt_world_set_gravity(handle, g.0, g.1, g.2)
        // One collision pass per ~60 Hz of simulated time keeps long frames
        // stable without costing short ones anything.
        let passes = max(1, Int((clamped * 60).rounded(.up)))
        _ = cjolt_world_step(handle, Float(clamped), Int32(passes))
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
        if groundBody != CJOLT_BODY_INVALID {
            cjolt_body_destroy(handle, groundBody)
            groundBody = CJOLT_BODY_INVALID
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
        groundBody = withUnsafePointer(to: &desc) { cjolt_body_create(handle, $0) }
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
