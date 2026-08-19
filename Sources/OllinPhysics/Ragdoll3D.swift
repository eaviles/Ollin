import Foundation
import simd
import Ollin
internal import CJolt

/// How far one ragdoll joint may bend: a cone its bone may lean off where it
/// started, and a range it may roll through about that bone. The solver takes
/// both and does not hand them back, so a figure keeps its own copy.
struct RagdollLimit {
    var swing: Double
    var twist: ClosedRange<Double>
}

/// A skinned figure given weight: one rigid body per skeleton joint, hung off
/// each other by cone-limited ball joints, sized from the shape of the mesh
/// each joint carries. Build one from a loaded `Scene` that has a skin, step the
/// world, and write the simulated pose back onto the scene to draw it.
///
/// ```swift
/// var figure = loadScene("figure.gltf")!
/// let ragdoll = world.addRagdoll(from: figure, at: Vector3(0, 3, 0))!
/// // each frame:
/// world.step(dt: deltaTime)
/// figure.apply(ragdoll)        // the pose the solver just found
/// drawScene(figure)
/// ```
///
/// That is the limp figure, the one that falls down stairs. `drive(toward:)`
/// gives it back some will: the joints grow motors that pull toward whatever
/// pose the scene is holding, so a figure playing an animation resists being
/// pushed instead of collapsing.
///
/// ```swift
/// figure.apply(walk, at: time)     // where the animation wants the limbs
/// ragdoll.drive(toward: figure)    // and how hard they try to get there
/// world.step(dt: deltaTime)
/// figure.apply(ragdoll)            // where they actually ended up
/// ```
///
/// The bodies are ordinary bodies (they collide, they turn up in
/// `world.contacts`, they can be picked and dragged), but they are made and
/// destroyed as a set and kept out of `world.bodies`, since a sketch draws the
/// figure's mesh rather than the capsules underneath. They are in `limbs`.
public final class Ragdoll3D {

    /// One limb of the figure: the body standing at a joint, plus the shape it
    /// wears and where that shape sits inside it. A limb's body is posed at the
    /// *joint*, so the capsule filling the bone is pushed out from there, which
    /// is what `withLimb(_:)` accounts for.
    public struct Limb {
        /// The joint's name in the file, which is how `limit(_:swing:twist:)`
        /// finds it.
        public let name: String
        /// The rigid body standing at the joint.
        public let body: Body3D
        /// The limb this one hangs off, as an index into `limbs`, or `nil` for
        /// the root. Limbs come parents-first, so this is always a lower index.
        public let parent: Int?
        /// The shape fitted to the mesh this joint carries.
        public let collider: Collider3D
        /// Where that shape's center sits inside the body, in the body's local
        /// space.
        public let shapeCenter: Vector3
        /// How the shape is turned there: `shapeAngle` radians about
        /// `shapeAxis`, which stands a `+y` capsule up along the bone.
        public let shapeAngle: Double
        public let shapeAxis: Vector3
    }

    /// The world this figure hangs in. Unowned: the world holds it.
    unowned let world: World3D

    /// The underlying solver ragdoll.
    private var handle: OpaquePointer?

    /// Every limb, parents before children, so `limbs[0]` is the root.
    public private(set) var limbs: [Limb] = []

    /// Every limb's body, in the same order: the shortcut for a loop that only
    /// wants the bodies.
    public var bodies: [Body3D] { limbs.map(\.body) }

    /// Free-form tag so a sketch can hang its own data off a figure.
    public var userData: Any?

    /// Which scene joint each limb stands at (a file node index), and how many
    /// joints the skeleton had, so a pose handed in later can be checked
    /// against the one the figure was built from.
    let jointSource: [Int]
    let skinJointCount: Int
    /// The skin-joint index of each limb, and each limb's parent limb (-1 for
    /// the root): what a pose read off a scene is regrouped by.
    let skinIndexOfLimb: [Int]
    let parentOfLimb: [Int]

    /// The fitting this figure was built from: where each joint stood, which
    /// way its bone ran, and what shape was fitted to it. Kept because a
    /// constraint's zero is the pose it was made in, so anything that builds
    /// this figure again has to stand it back in the pose it was fitted in
    /// first, exactly as a joint does.
    let plan: RagdollPlan

    /// Each limb's swing cone and twist range, which the solver takes but does
    /// not hand back. Set at build time and updated by `limit(_:swing:twist:)`.
    private(set) var jointLimits: [RagdollLimit]

    /// The surface friction and collision group every limb was built with.
    let limbFriction: Double
    let limbGroup: CollisionGroup

    /// Set by the world when it goes away first, so this object's own teardown
    /// doesn't reach into a solver that no longer exists.
    var isDestroyed = false

    /// Builds the figure from a scene. Fails (returning nil) when the scene has
    /// no skin or the solver can't make the bodies.
    convenience init?(world: World3D, scene: Scene, at position: Vector3?,
                      joints names: [String]?, swing: Double,
                      twist: ClosedRange<Double>, mass: Double, friction: Double,
                      group: CollisionGroup) {
        let skeleton = scene.skeleton()
        guard !skeleton.isEmpty else {
            world.noteOnce("addRagdoll needs a scene with a skin (a skeleton posing "
                           + "a mesh); this one has none.")
            return nil
        }
        let plan = RagdollPlan(skeleton: skeleton, vertices: scene.skinnedVertices(),
                               names: names, mass: mass,
                               offset: RagdollPlan.placement(of: skeleton, at: position))
        let limits = plan.limbs.map { _ in RagdollLimit(swing: swing, twist: twist) }
        self.init(world: world, plan: plan, limits: limits, friction: friction,
                  group: group)
    }

    /// Builds the figure from a fitting. This is the one that reaches the
    /// solver: the fitting is what a scene is worked down to, and it is also
    /// what a snapshot holds, so a restored figure is built by the same code as
    /// a fitted one.
    init?(world: World3D, plan: RagdollPlan, limits: [RagdollLimit],
          friction: Double, group: CollisionGroup) {
        self.world = world
        guard !plan.limbs.isEmpty, limits.count == plan.limbs.count else { return nil }

        skinJointCount = plan.skinJointCount
        skinIndexOfLimb = plan.limbs.map(\.skinIndex)
        parentOfLimb = plan.limbs.map(\.parent)
        jointSource = plan.limbs.map(\.sourceIndex)
        self.plan = plan
        self.jointLimits = limits
        self.limbFriction = friction
        self.limbGroup = group

        // Every fitted shape's flat data lives in the arena for the span of the
        // create, the body-creation rule.
        let arena = ShapeDescArena()
        var parts = zip(plan.limbs, limits).map { limb, limit -> CJoltRagdollPartDesc in
            var desc = CJoltRagdollPartDesc()
            desc.parent = Int32(limb.parent)
            desc.shape = limb.collider.shapeDesc(unitsPerMeter: world.unitsPerMeter,
                                                 density: 1, arena: arena)
            let center = world.meters(from: limb.shapeCenter)
            desc.shapeOffset = (center.0, center.1, center.2)
            desc.shapeRotation = Ragdoll3D.quaternion(limb.shapeAngle, limb.shapeAxis)
            let origin = world.meters(from: limb.jointOrigin)
            desc.position = (origin.0, origin.1, origin.2)
            desc.rotation = Ragdoll3D.quaternion(of: limb.jointRotation)
            desc.mass = Float(limb.mass)
            // The pivot is the joint itself, and the bone it turns runs along
            // the limb's own axis.
            desc.pivot = (origin.0, origin.1, origin.2)
            let axis = limb.worldAxis
            desc.twistAxis = (Float(axis.x), Float(axis.y), Float(axis.z))
            let plane = axis.anyPerpendicular
            desc.planeAxis = (Float(plane.x), Float(plane.y), Float(plane.z))
            desc.swingLimit = Float(min(max(limit.swing, 0), .pi))
            desc.twistMin = Float(min(max(limit.twist.lowerBound, -.pi), 0))
            desc.twistMax = Float(max(min(limit.twist.upperBound, .pi), 0))
            return desc
        }
        let created: OpaquePointer? = withExtendedLifetime(arena) {
            parts.withUnsafeMutableBufferPointer {
                cjolt_ragdoll_create(world.handle, $0.baseAddress, Int32($0.count),
                                     Float(friction), Float(world.bounce),
                                     world.groupIndex(group))
            }
        }
        guard let created else {
            world.noteOnce("the ragdoll could not be built from this skeleton.")
            return nil
        }
        handle = created

        limbs = plan.limbs.enumerated().map { index, limb in
            let id = cjolt_ragdoll_get_body(created, Int32(index))
            let body = Body3D(world: world, id: id, collider: limb.collider,
                              kind: .dynamic, density: 1)
            // Registered so a contact, a ray pick, or a sensor can name the
            // limb, but kept out of `world.bodies`: the sketch draws the mesh
            // these carry, not the capsules.
            world.bodyByID[id] = body
            return Limb(name: limb.name, body: body,
                        parent: limb.parent >= 0 ? limb.parent : nil,
                        collider: limb.collider, shapeCenter: limb.shapeCenter,
                        shapeAngle: limb.shapeAngle, shapeAxis: limb.shapeAxis)
        }
    }

    deinit {
        destroyBackingRagdoll()
    }

    // MARK: Driving the figure

    /// Power every joint toward the pose `scene` is currently holding: the
    /// joints grow motors that pull the limbs into that shape, so the figure
    /// resists a shove instead of folding under it. Call it each frame, after
    /// posing the scene (from an animation, or by hand) and before stepping.
    ///
    /// The root has no joint above it, so a powered figure still falls as a
    /// whole: the motors hold its *shape*, not its place.
    ///
    /// - Parameters:
    ///   - frequency: how fast a joint pulls, in Hz. 20 holds a pose firmly;
    ///     2 is a slow, rubbery recovery.
    ///   - damping: 1 settles cleanly, lower overshoots and wobbles.
    ///   - strength: the most torque a joint may use, in newton-meters. Lower
    ///     it and heavy limbs sag out of the pose, which is how a figure looks
    ///     tired rather than switched off.
    ///
    /// A ragdoll switched to `.kinematic` follows the pose exactly instead,
    /// shoving whatever it walks through.
    public func drive(toward scene: Scene, frequency: Double = 20,
                      damping: Double = 1, strength: Double = .infinity) {
        guard let handle, let worlds = jointWorlds(of: scene) else { return }
        if kind == .kinematic {
            let matrices = poseMatrices(from: worlds)
            matrices.withUnsafeBufferPointer {
                cjolt_ragdoll_move_to_pose(world.handle, handle, $0.baseAddress,
                                           Float(world.lastTimestep))
            }
            return
        }
        // Each joint's motor is aimed at the child's rotation *relative to its
        // parent*, which is exactly what the skeleton's local pose is.
        var rotations = [Float]()
        rotations.reserveCapacity(4 * worlds.count)
        for (index, world) in worlds.enumerated() {
            let parent = parentOfLimb[index]
            let local = parent >= 0
                ? simd_normalize(simd_inverse(rotation(of: worlds[parent]))
                    * rotation(of: world))
                : simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            rotations.append(contentsOf: [local.vector.x, local.vector.y,
                                          local.vector.z, local.vector.w])
        }
        rotations.withUnsafeBufferPointer {
            cjolt_ragdoll_drive_to_pose(world.handle, handle, $0.baseAddress,
                                        Float(frequency), Float(damping),
                                        Float(strength))
        }
    }

    /// Cut the power: the joints go slack and only their limits hold the figure
    /// together. This is the fall.
    public func goLimp() {
        guard let handle else { return }
        cjolt_ragdoll_stop_motors(handle)
        cjolt_ragdoll_activate(world.handle, handle)
    }

    /// Place every limb instantly at the pose `scene` is holding, velocities
    /// left where they were: the reset, and how a figure is stood back up.
    public func pose(from scene: Scene) {
        guard let handle, let worlds = jointWorlds(of: scene) else { return }
        let matrices = poseMatrices(from: worlds)
        matrices.withUnsafeBufferPointer {
            cjolt_ragdoll_set_pose(world.handle, handle, $0.baseAddress)
        }
        for limb in limbs {
            limb.body.velocity = .zero
            limb.body.angularVelocity = .zero
        }
    }

    /// Retune one joint's limits while the figure hangs: how far the named
    /// joint's bone may lean off where it started (`swing`, radians) and how
    /// far it may roll about itself (`twist`). Knees and elbows want a narrow
    /// cone; shoulders and hips a wide one. Naming the root, or a joint the
    /// figure doesn't have, does nothing.
    public func limit(_ name: String, swing: Double,
                      twist: ClosedRange<Double> = -0.3...0.3) {
        guard let handle, let index = limbs.firstIndex(where: { $0.name == name })
        else { return }
        jointLimits[index] = RagdollLimit(swing: swing, twist: twist)
        cjolt_ragdoll_set_limits(handle, Int32(index),
                                 Float(min(max(swing, 0), .pi)),
                                 Float(min(max(twist.lowerBound, -.pi), 0)),
                                 Float(max(min(twist.upperBound, .pi), 0)))
    }

    /// Shove the whole figure: the same impulse (N·s) added to every limb, so
    /// it leaves in one piece rather than tearing apart.
    public func applyImpulse(_ impulse: Vector3) {
        guard let handle else { return }
        let scale = 1 / world.unitsPerMeter
        withFloats3((Float(impulse.x * scale), Float(impulse.y * scale),
                     Float(impulse.z * scale))) {
            cjolt_ragdoll_add_impulse(world.handle, handle, $0)
        }
    }

    /// How the whole figure is simulated. `.dynamic` (the default) falls and is
    /// pushed around; `.kinematic` follows whatever pose it is driven to,
    /// unstoppably, shoving what it hits; `.static` freezes it.
    public var kind: Body3D.Kind = .dynamic {
        didSet {
            guard let handle, kind != oldValue else { return }
            cjolt_ragdoll_set_motion(world.handle, handle, kind.cjolt)
        }
    }

    /// Whether any limb is still moving. A figure that has come to rest sleeps,
    /// and stops reporting contacts until something wakes it.
    public var isAwake: Bool {
        guard let handle else { return false }
        return cjolt_ragdoll_is_active(world.handle, handle)
    }

    /// Wake every limb.
    public func wake() {
        guard let handle else { return }
        cjolt_ragdoll_activate(world.handle, handle)
    }

    /// Which collision group every limb is in. The separate filter that keeps
    /// this figure's own limbs from fighting each other is untouched, so two
    /// figures in one group still collide with each other.
    ///
    /// ```swift
    /// figure.group = "phantoms"     // falls through whatever ignores phantoms
    /// ```
    public var group: CollisionGroup {
        get { limbs.first.map(\.body.group) ?? .default }
        set {
            guard let handle else { return }
            cjolt_ragdoll_set_group(world.handle, handle, world.groupIndex(newValue))
        }
    }

    /// Where the root joint (the hips of a humanoid) currently is: the one
    /// number that says where the figure has got to.
    public var position: Vector3 { limbs.first?.body.position ?? .zero }

    // MARK: Reading and writing poses

    /// Every limb's current world transform, in world units, for the write-back
    /// onto a scene's joints.
    func limbWorlds() -> [simd_float4x4] {
        limbs.map { limb in
            var out = [Float](repeating: 0, count: 16)
            out.withUnsafeMutableBufferPointer {
                cjolt_body_get_transform(world.handle, limb.body.id, $0.baseAddress)
            }
            var m = simd_float4x4(SIMD4(out[0], out[1], out[2], out[3]),
                                  SIMD4(out[4], out[5], out[6], out[7]),
                                  SIMD4(out[8], out[9], out[10], out[11]),
                                  SIMD4(out[12], out[13], out[14], out[15]))
            let scale = Float(world.unitsPerMeter)
            m.columns.3 = SIMD4(m.columns.3.x * scale, m.columns.3.y * scale,
                                m.columns.3.z * scale, 1)
            return m
        }
    }

    /// The scene's current joint transforms, one per limb, or `nil` (with a
    /// one-time note) when the scene isn't the one this figure was built from.
    private func jointWorlds(of scene: Scene) -> [simd_float4x4]? {
        let skeleton = scene.skeleton()
        guard skeleton.count == skinJointCount else {
            world.noteOnce("this scene's skeleton is not the one the ragdoll was "
                           + "built from; the pose is ignored.")
            return nil
        }
        return skinIndexOfLimb.map { skeleton[$0].world }
    }

    /// Those transforms as the flat column-major matrices the solver takes,
    /// with rotations cleaned of any scale the scene carries and translations
    /// in meters.
    private func poseMatrices(from worlds: [simd_float4x4]) -> [Float] {
        var out = [Float]()
        out.reserveCapacity(16 * worlds.count)
        for world4 in worlds {
            let q = rotation(of: world4)
            let basis = simd_float3x3(q)
            let t = world.meters(from: Vector3(Double(world4.columns.3.x),
                                               Double(world4.columns.3.y),
                                               Double(world4.columns.3.z)))
            for column in 0..<3 {
                out.append(contentsOf: [basis[column].x, basis[column].y,
                                        basis[column].z, 0])
            }
            out.append(contentsOf: [t.0, t.1, t.2, 1])
        }
        return out
    }

    /// The rotation a (possibly scaled) transform carries.
    private func rotation(of m: simd_float4x4) -> simd_quatf {
        var basis = matrix_identity_float4x4
        for column in 0..<3 {
            let axis = SIMD3(m[column].x, m[column].y, m[column].z)
            let length = simd_length(axis)
            basis[column] = SIMD4(length > 1e-9 ? axis / length : unitAxis(column), 0)
        }
        return simd_normalize(simd_quatf(basis))
    }

    private func unitAxis(_ index: Int) -> SIMD3<Float> {
        SIMD3(index == 0 ? 1 : 0, index == 1 ? 1 : 0, index == 2 ? 1 : 0)
    }

    // MARK: Removal

    /// Destroy the solver ragdoll and forget its bodies (called by the world).
    func destroyBackingRagdoll() {
        guard let live = handle else { return }
        handle = nil
        guard !isDestroyed else { return }
        for limb in limbs {
            world.bodyByID[limb.body.id] = nil
            world.forgetTouches(of: limb.body.id)
        }
        world.contacts.removeAll { contact in
            limbs.contains { contact.involves($0.body) }
        }
        cjolt_ragdoll_destroy(world.handle, live)
    }

    // MARK: Quaternion helpers

    /// The `(x, y, z, w)` quaternion for `angle` radians about `axis`.
    static func quaternion(_ angle: Double, _ axis: Vector3) -> (Float, Float, Float, Float) {
        let unit = axis.normalized
        let half = angle / 2
        let s = sin(half)
        return (Float(unit.x * s), Float(unit.y * s), Float(unit.z * s), Float(cos(half)))
    }

    static func quaternion(of q: simd_quatf) -> (Float, Float, Float, Float) {
        (q.vector.x, q.vector.y, q.vector.z, q.vector.w)
    }
}

extension Vector3 {
    /// Some unit vector at right angles to this one, chosen from whichever
    /// world axis this leans on least, so the answer never collapses.
    var anyPerpendicular: Vector3 {
        let unit = normalized
        let other = abs(unit.x) < 0.9 ? Vector3.unitX : Vector3.unitY
        let perpendicular = unit.cross(other)
        return perpendicular.lengthSquared > 1e-12 ? perpendicular.normalized : .unitZ
    }
}

extension Scene {

    /// Pose the figure's joints from a simulated `ragdoll`: the inverse of
    /// `apply(_:at:)`, taking the pose the solver found instead of the one an
    /// animation asked for. Call it after `world.step(dt:)` and draw the scene
    /// as usual.
    ///
    /// ```swift
    /// world.step(dt: deltaTime)
    /// figure.apply(ragdoll)
    /// drawScene(figure)
    /// ```
    ///
    /// The ragdoll simulates in world space, so draw the scene without a
    /// transform of your own (or move the whole world instead) if you want the
    /// figure to land where the bodies are. Joints the ragdoll skipped keep
    /// their pose and ride the limb above them.
    public mutating func apply(_ ragdoll: Ragdoll3D) {
        let worlds = ragdoll.limbWorlds()
        guard worlds.count == ragdoll.jointSource.count else { return }
        var posed: [Int: simd_float4x4] = [:]
        for (index, source) in ragdoll.jointSource.enumerated() {
            posed[source] = worlds[index]
        }
        setJointWorlds(posed)
    }
}
