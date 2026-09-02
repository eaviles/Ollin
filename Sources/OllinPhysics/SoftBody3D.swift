import Foundation
import simd
import Ollin
internal import CJolt

/// A body with no pose: a mesh whose vertices are simulated particles held
/// together by springs, so it drapes, folds, and squashes instead of moving as
/// one rigid piece. Cloth and a beach ball are the two ends of the same thing.
/// An open sheet drapes over whatever it lands on, and a closed surface with
/// pressure inside holds a shape it can still be dented out of.
///
/// Build one from any `Mesh` and draw the simulated mesh each frame:
///
/// ```swift
/// let cloth = world.addSoftBody(from: .plane(width: 3, depth: 3, columns: 24, rows: 24),
///                               at: Vector3(0, 3, 0),
///                               pinned: { $0.z < -1.4 })   // hung from one edge
/// // each frame:
/// world.advance(by: deltaTime)
/// drawSoftBody(cloth)
/// ```
///
/// The mesh that comes back keeps the source mesh's topology, uvs, colors, and
/// material, so a textured sheet stays textured while it moves; only the
/// positions and normals are the simulation's.
///
/// A soft body collides with the rigid bodies around it, but not with another
/// soft body, and impulses, joints, and grabs do not apply to it (its state
/// lives in the particles, not in one pose). Push it with `applyForce(_:)`, or
/// take hold of a particle with `move(_:to:)`.
///
/// `Rope3D` is the one-dimensional member of the same family: a line of
/// particles with no surface at all, built by `World3D.addRope(through:)`.
public class SoftBody3D {

    /// Anything a sketch hung on this body.
    public var userData: Any?

    /// A name for the mesh this body was built from, so a snapshot can write
    /// the name down instead of the whole surface. A soft body *is* its mesh,
    /// so unlike a rigid body this is what decides whether it can be saved at
    /// all: an unnamed one is left out with a note.
    ///
    /// ```swift
    /// let banner = world.addSoftBody(from: sheet, at: Vector3(0, 3, 0))
    /// banner.assetName = "banner"
    /// ```
    public var assetName: String?

    /// The mesh it was built from, in its own local space, unchanged. A rope
    /// was built from a polyline rather than a surface, so this is empty for
    /// one and `Rope3D.points` is what it was made from.
    public let sourceMesh: Mesh

    /// How many particles the simulation actually runs on. Coincident vertices
    /// of the source mesh merge into one particle, so this is usually smaller
    /// than `sourceMesh.positions.count`.
    public var particleCount: Int { welding.count }

    /// Whether the surface is closed, which is what makes `pressure` meaningful:
    /// a sheet has no inside to fill.
    public let isClosed: Bool

    /// The world this body belongs to.
    unowned let world: World3D

    /// The solver handle.
    let handle: OpaquePointer

    /// The solver's id for the body, so a ray cast hit can be recognized.
    let bodyID: CJoltBodyID

    /// The source mesh's vertices merged onto particles, plus the map back.
    private let welding: MeshWelding

    /// Raw pressure per unit of the `pressure` parameter: the body's own mass, rest
    /// volume, and rest area folded into one number, so `pressure` means the
    /// same at any size.
    private let pressureScale: Double

    /// One particle's share of the rest surface, in square meters: what the
    /// water pushes on when it drags the body along.
    let dragArea: Double

    /// The mean distance between neighboring particles, in meters. Buoyancy
    /// ramps in over about this much depth, since that is the width of surface
    /// one particle stands for.
    let particleSpacing: Double

    /// The last read-back, and the world step it was taken at, so drawing the
    /// same body twice in a frame costs one copy rather than two.
    private var cachedMesh: Mesh?
    private var cachedGeneration: Int = -1

    /// Scratch for the particle read-back, reused across frames.
    private var particles: [Vector3]

    /// How many Cosserat rods run through the body: the segments of a rope,
    /// and zero for an ordinary surface.
    let rodCount: Int

    /// Scratch for the rod orientation read-back, reused across frames.
    private var rodRotations: [Float]

    /// The spine of a rope: the polyline its particles sit on, in the body's
    /// own local space, and how thick it draws.
    struct RopeShape {
        var points: [Vector3]
        var thickness: Double
        var sides: Int
        /// Which way each rod is already turned, for a rope being put back
        /// where it was rather than built for the first time. Empty otherwise.
        var rodRotations: [simd_quatd] = []
    }

    /// Scratch for the water pass: how far each particle is above the fluid's
    /// surface, in meters. Kept here so the per-step buoyancyScale allocates
    /// nothing.
    var surfaceHeights: [Float] = []

    /// The numbers this body was built with. The solver takes them and works
    /// them into compliances and rest lengths it never hands back, so a body
    /// that wants to be written down keeps its own copy.
    let buildMass: Double
    let buildStiffness: Double
    let buildBend: Double
    let buildDamping: Double
    let buildFriction: Double
    let buildRestitution: Double
    let buildTwoSided: Bool
    /// How far the surface may reach from what holds it, if it was capped.
    let buildMaxStretch: Double?
    /// Where the surface was built, which is the frame its rest shape is in.
    let buildPosition: Vector3
    let buildRotation: simd_quatd

    /// The total mass, kept so `unpin` can restore a particle's share of it.
    private let totalMass: Double

    /// Set by the world when it goes, so a body a sketch still holds does not
    /// reach into a solver that no longer exists.
    var isDestroyed = false

    /// Whether a skeleton carries any of this surface, which is what makes
    /// `follow(_:)` mean anything.
    public private(set) var isSkinned = false

    /// What ties the surface to a skeleton: one inverse bind per joint,
    /// captured from the pose the figure was standing in when the cloth was
    /// hung on it, plus which joint carries each particle and how far it may
    /// stray. Kept whole because a snapshot writes it down: the closures that
    /// decided it are gone by then, the way the pinned list already is.
    private(set) var skinning = Skin()

    /// The pose `follow(_:)` recorded for this frame, handed to the solver by
    /// the world's step. Kept rather than applied at once so a surface is
    /// skinned exactly once per step, which is what the solver interpolates
    /// its constraints across.
    private var pendingPose: [Float]?

    /// The pose the skin was last stood on, so a figure that has actually
    /// moved can be told from one holding still.
    private var lastPose: [Float]?

    init?(world: World3D, mesh: Mesh, position: Vector3, rotation: simd_quatd,
          mass: Double, stiffness: Double, bend: Double, pressure: Double,
          damping: Double, friction: Double, restitution: Double,
          iterations: Int, vertexRadius: Double, isTwoSided twoSided: Bool,
          pinned: ((Vector3) -> Bool)?, group: CollisionGroup,
          skeleton: [SceneSkeletonJoint] = [],
          carriedBy: ((Vector3) -> String?)? = nil,
          sway: ((Vector3) -> Double)? = nil,
          backStop: Double? = nil,
          maxStretch: Double? = nil,
          restoredSkin: Skin? = nil,
          rope: RopeShape? = nil) {
        // A rope's particles *are* its points, so there is nothing to weld and
        // the map back to the caller's order is the identity. That is what
        // makes `pin`, `move`, and `positions` speak in point indices.
        let welding: MeshWelding
        if let rope {
            welding = MeshWelding(positions: rope.points, indices: [],
                                  remap: Array(rope.points.indices))
            guard welding.count >= 2 else { return nil }
        } else {
            welding = mesh.welded()
            guard welding.count >= 3, welding.indices.count >= 3 else { return nil }
        }

        self.world = world
        self.sourceMesh = mesh
        self.welding = welding
        self.particles = welding.positions
        self.buildMass = mass
        self.buildStiffness = stiffness
        self.buildBend = bend
        self.buildDamping = damping
        self.buildFriction = friction
        self.buildRestitution = restitution
        self.buildTwoSided = twoSided
        self.buildMaxStretch = maxStretch
        self.buildPosition = position
        self.buildRotation = rotation

        // Rest measurements, in meters, are what let the parameters mean the same
        // thing whatever the body's size: the pressure parameter is calibrated
        // against them and the spring compliance against the particle mass.
        let scale = world.unitsPerMeter
        var area = 0.0
        var sixVolume = 0.0
        var edgeCounts: [SoftBody3D.Edge: Int] = [:]
        var i = 0
        while i + 2 < welding.indices.count {
            let ia = Int(welding.indices[i]), ib = Int(welding.indices[i + 1])
            let ic = Int(welding.indices[i + 2])
            let a = welding.positions[ia] / scale
            let b = welding.positions[ib] / scale
            let c = welding.positions[ic] / scale
            area += (b - a).cross(c - a).length * 0.5
            sixVolume += a.dot(b.cross(c))
            for edge in [Edge(ia, ib), Edge(ib, ic), Edge(ic, ia)] {
                edgeCounts[edge, default: 0] += 1
            }
            i += 3
        }
        // A rope has no faces to measure, so its own two numbers stand in: the
        // skin of the tube it draws as is the area the water drags on, and a
        // rod is what a face's edge would have been.
        var ropeLength = 0.0
        if let rope {
            for i in 1 ..< rope.points.count {
                ropeLength += ((rope.points[i] - rope.points[i - 1]) / scale).length
            }
            area = 2 * .pi * (rope.thickness / scale) * ropeLength
        }
        // A closed surface is one where every edge belongs to exactly two
        // faces; anything else has a boundary and no inside to pressurise.
        isClosed = !edgeCounts.isEmpty && edgeCounts.values.allSatisfy { $0 == 2 }
        let volume = abs(sixVolume) / 6
        // A closed surface holds a real volume, so how heavy it is for its size
        // falls out of the mass it was given, the same way a collider's density
        // decides a solid body's. A sheet holds nothing, so there is nothing to
        // work it out from and it starts as heavy as water.
        let restDensity = isClosed && volume > 1e-9
            ? max(mass, 1e-6) / (volume * 1000) : 1

        let massKg = max(mass, 1e-6)
        totalMass = massKg
        let particleMass = massKg / Double(welding.count)
        var edgeTotal = 0.0
        for (edge, _) in edgeCounts {
            edgeTotal += ((welding.positions[edge.high] - welding.positions[edge.low]) / scale).length
        }
        var meanEdge = edgeCounts.isEmpty ? 1 : edgeTotal / Double(edgeCounts.count)
        if rope != nil, welding.count > 1 {
            meanEdge = ropeLength / Double(welding.count - 1)
        }
        // The solver's pressure is `n R T`, and the outward acceleration it
        // gives works out to pressure * area / (mass * volume). Expressing the
        // parameter as that acceleration in gravities is what makes `pressure: 1`
        // mean "just holds its own weight up" at any scale.
        let gravity = world.gravity.length > 1e-6 ? world.gravity.length : 9.8
        pressureScale = area > 1e-12 && volume > 1e-12
            ? gravity * massKg * volume / area : 0
        dragArea = area / Double(welding.count)
        particleSpacing = meanEdge

        // What the caller's closures are asked about: a mesh's own vertices, or
        // a rope's points, which are its particles one for one.
        let sourcePoints = rope?.points ?? mesh.positions

        var inverseMasses = [Float](repeating: Float(1 / particleMass),
                                    count: welding.count)
        if let pinned {
            for (source, particle) in welding.remap.enumerated()
            where source < sourcePoints.count {
                if pinned(sourcePoints[source]) { inverseMasses[particle] = 0 }
            }
        }

        // The compliance a parameter setting maps onto depends on the body it is
        // describing, so the scale is measured from the rest shape once.
        let complianceScale = meanEdge * Double(welding.count).squareRoot()
            / (massKg * gravity)

        // A rope's rods run down its spine, and every neighboring pair holds
        // the other's orientation: without those links a rod's frame spins
        // about its own axis forever and carries nothing.
        var rods: [UInt32] = []
        var rodLinks: [UInt32] = []
        if rope != nil, welding.count > 1 {
            for i in 0 ..< welding.count - 1 {
                rods.append(UInt32(i))
                rods.append(UInt32(i + 1))
            }
            for i in 0 ..< max(0, welding.count - 2) {
                rodLinks.append(UInt32(i))
                rodLinks.append(UInt32(i + 1))
            }
        }
        rodCount = rods.count / 2
        rodRotations = [Float](repeating: 0, count: rods.count / 2 * 4)

        // A rope being put back where it was hands over the orientations its
        // rods had, so the solver does not have to haul each one round to the
        // shape the rope is actually in, which is a visible spring.
        var restoredRods = [Float]()
        if let rope, rope.rodRotations.count == rods.count / 2 {
            for q in rope.rodRotations {
                restoredRods.append(contentsOf: [Float(q.imag.x), Float(q.imag.y),
                                                 Float(q.imag.z), Float(q.real)])
            }
        }

        var desc = CJoltSoftBodyDesc()
        desc.vertexCount = Int32(welding.count)
        desc.indexCount = Int32(welding.indices.count)
        desc.rodCount = Int32(rods.count / 2)
        desc.rodLinkCount = Int32(rodLinks.count / 2)
        desc.rodCompliance = Float(SoftBody3D.compliance(for: stiffness, scale: complianceScale))
        desc.rodBendCompliance = Float(SoftBody3D.compliance(
            for: bend,
            scale: SoftBody3D.rodBendScale(meanEdge: meanEdge, length: ropeLength,
                                           mass: massKg, gravity: gravity)))
        desc.compliance = Float(SoftBody3D.compliance(for: stiffness, scale: complianceScale))
        // A fold constraint measures an angle where a stretch constraint
        // measures a length, so its compliance carries two fewer powers of
        // length: dividing by the edge length squared is what puts the same
        // 0…1 parameter over the range that actually reads as limp to stiff.
        let bendScale = complianceScale / max(meanEdge * meanEdge, 1e-12)
        desc.bendCompliance = bend > 0
            ? Float(SoftBody3D.compliance(for: bend, scale: bendScale))
            : -1
        desc.pressure = Float(max(0, pressure) * pressureScale)
        desc.linearDamping = Float(max(0, damping))
        desc.friction = Float(max(0, friction))
        desc.restitution = Float(min(max(restitution, 0), 1))
        desc.gravityFactor = 1
        desc.vertexRadius = Float(vertexRadius / scale)
        desc.iterations = Int32(max(1, iterations))
        desc.allowSleep = true
        desc.twoSided = twoSided
        desc.group = world.groupIndex(group)
        let meters = world.meters(from: position)
        desc.position = (meters.0, meters.1, meters.2)
        let q = rotation.normalized
        desc.rotation = (Float(q.imag.x), Float(q.imag.y), Float(q.imag.z), Float(q.real))

        // Positions cross in meters, so a world built at a larger unit scale
        // simulates at the size the solver is tuned for.
        var restPositions = [Float](repeating: 0, count: welding.count * 3)
        for (index, p) in welding.positions.enumerated() {
            restPositions[index * 3] = Float(p.x / scale)
            restPositions[index * 3 + 1] = Float(p.y / scale)
            restPositions[index * 3 + 2] = Float(p.z / scale)
        }

        // Which skeleton joint carries each particle, worked out from the rest
        // shape before anything is built, since the bind pose is whatever the
        // figure is standing in right now.
        let skin = restoredSkin
            ?? SoftBody3D.skin(mesh: mesh, welding: welding,
                               skeleton: skeleton, carriedBy: carriedBy,
                               sway: sway, backStop: backStop,
                               pinned: pinned, position: position,
                               rotation: rotation, unitsPerMeter: scale)
        skinning = skin
        isSkinned = !skin.vertices.isEmpty
        if maxStretch != nil {
            desc.lraType = Int32(CJOLT_SOFT_LRA_GEODESIC.rawValue)
            desc.lraStretch = Float(max(1, maxStretch ?? 1))
        }

        let created: OpaquePointer? = restPositions.withUnsafeBufferPointer { points in
            welding.indices.withUnsafeBufferPointer { indices in
                inverseMasses.withUnsafeBufferPointer { masses in
                    skin.flatBinds.withUnsafeBufferPointer { binds in
                        skin.vertices.withUnsafeBufferPointer { skinned in
                            rods.withUnsafeBufferPointer { rodPairs in
                                rodLinks.withUnsafeBufferPointer { links in
                                    restoredRods.withUnsafeBufferPointer { frames in
                                    desc.positions = points.baseAddress
                                    desc.indices = indices.baseAddress
                                    desc.inverseMasses = masses.baseAddress
                                    desc.inverseBinds = binds.baseAddress
                                    desc.inverseBindCount = Int32(skin.binds.count)
                                    desc.skinned = skinned.baseAddress
                                    desc.skinnedCount = Int32(skin.vertices.count)
                                    desc.rods = rodPairs.baseAddress
                                    desc.rodLinks = links.baseAddress
                                    // An empty array's base address is not
                                    // promised to be nil, and a stray pointer
                                    // here reads as garbage orientations.
                                    desc.rodRotations = frames.isEmpty ? nil : frames.baseAddress
                                    return withUnsafePointer(to: desc) {
                                        cjolt_soft_body_create(world.handle, $0)
                                    }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Which way the winding faces, settled against the mesh's own normals
        // before anything has moved. The vote is area weighted (the derived
        // normals are unnormalized sums of cross products), so a few odd
        // triangles cannot outvote the surface.
        if mesh.normals.count == mesh.positions.count {
            let derived = SoftBody3D.normals(positions: mesh.positions,
                                             indices: mesh.indices,
                                             fallback: mesh.normals)
            var agreement = 0.0
            for (index, n) in derived.enumerated() { agreement += n.dot(mesh.normals[index]) }
            normalsAreFlipped = agreement < 0
        } else {
            normalsAreFlipped = false
        }

        guard let created else { return nil }
        handle = created
        bodyID = cjolt_soft_body_get_id(created)
        self.density = restDensity
        self.pressure = pressure
        self.iterations = max(1, iterations)
        self.vertexRadius = vertexRadius

        // The skin state starts empty, so a surface that is never posed would
        // be pulled to the frame's origin the first time the constraints are
        // solved. Standing it on the bind pose costs nothing (it is already
        // there) and is what makes the first step behave.
        //
        // The bind pose does not have to be remembered to be recovered: an
        // inverse bind is `bindWorld⁻¹ · placement`, so `placement · bind⁻¹` is
        // that joint's world transform back, exactly. Which is also why a
        // surface restored from a file, with no scene in sight, opens standing
        // in the pose it was hung in rather than collapsed on the origin.
        if isSkinned {
            let placement = SoftBody3D.placement(position: position,
                                                 rotation: rotation,
                                                 unitsPerMeter: scale)
            applySkin(SoftBody3D.flattened(skin.binds.map { placement * $0.inverse }),
                      hard: true)
        }

        if pressure > 0 && !isClosed {
            world.noteOnce("pressure needs a closed surface to fill; this mesh "
                           + "has an open edge, so the pressure is ignored.")
        }
        for name in skin.unknownJoints.sorted() {
            world.noteOnce("no joint named \"\(name)\" carries anything in this "
                           + "skeleton, so the part of the surface asking for "
                           + "it is ordinary cloth")
        }
    }

    deinit {
        guard !isDestroyed else { return }
        cjolt_soft_body_destroy(world.handle, handle)
    }

    // MARK: Reading it back

    /// The simulated surface in world space, ready to draw: the source mesh
    /// with the particles' positions and freshly derived normals.
    ///
    /// Normals are rebuilt over the *source* mesh's own topology, so a
    /// flat-shaded mesh stays faceted and a smooth one stays smooth.
    public var mesh: Mesh {
        if let cachedMesh, cachedGeneration == world.stepGeneration {
            return cachedMesh
        }
        var result = sourceMesh
        result.positions = positions
        result.normals = SoftBody3D.normals(positions: result.positions,
                                            indices: result.indices,
                                            fallback: sourceMesh.normals,
                                            flipped: normalsAreFlipped)
        cachedMesh = result
        cachedGeneration = world.stepGeneration
        return result
    }

    /// The simulated position of every vertex of the source mesh, in world
    /// space and in the source mesh's own order.
    public var positions: [Vector3] {
        let particles = particlePositions
        return welding.remap.map { particles[$0] }
    }

    /// How fast every particle is moving, in world units per second, in the
    /// same order as `particlePositions`.
    public var particleVelocities: [Vector3] {
        guard !isDestroyed else { return [] }
        var raw = [Float](repeating: 0, count: welding.count * 3)
        let written = raw.withUnsafeMutableBufferPointer { buffer in
            Int(cjolt_soft_body_get_velocities(world.handle, handle,
                                               buffer.baseAddress,
                                               Int32(welding.count)))
        }
        let scale = world.unitsPerMeter
        return (0 ..< written).map {
            Vector3(Double(raw[$0 * 3]) * scale, Double(raw[$0 * 3 + 1]) * scale,
                    Double(raw[$0 * 3 + 2]) * scale)
        }
    }

    /// Stand every particle where it was and moving as it was. This is how a
    /// saved surface is put back; while the world is running, take hold of a
    /// particle with `move(_:to:)` instead, which collides on the way.
    func restoreState(positions: [Vector3], velocities: [Vector3]) {
        guard !isDestroyed, positions.count == welding.count else { return }
        let scale = 1 / world.unitsPerMeter
        var flatPositions = [Float](repeating: 0, count: positions.count * 3)
        var flatVelocities = [Float](repeating: 0, count: positions.count * 3)
        for (index, point) in positions.enumerated() {
            flatPositions[index * 3] = Float(point.x * scale)
            flatPositions[index * 3 + 1] = Float(point.y * scale)
            flatPositions[index * 3 + 2] = Float(point.z * scale)
            let velocity = index < velocities.count ? velocities[index] : .zero
            flatVelocities[index * 3] = Float(velocity.x * scale)
            flatVelocities[index * 3 + 1] = Float(velocity.y * scale)
            flatVelocities[index * 3 + 2] = Float(velocity.z * scale)
        }
        flatPositions.withUnsafeBufferPointer { p in
            flatVelocities.withUnsafeBufferPointer { v in
                cjolt_soft_body_set_state(world.handle, handle, p.baseAddress,
                                          v.baseAddress, Int32(positions.count))
            }
        }
    }

    /// The simulated position of every particle, in world space. Shorter than
    /// `positions` wherever the source mesh had coincident vertices.
    public var particlePositions: [Vector3] {
        guard !isDestroyed else { return particles }
        var raw = [Float](repeating: 0, count: welding.count * 3)
        let written = raw.withUnsafeMutableBufferPointer { buffer in
            Int(cjolt_soft_body_get_positions(world.handle, handle,
                                              buffer.baseAddress, Int32(welding.count)))
        }
        let scale = world.unitsPerMeter
        for index in 0 ..< written {
            particles[index] = Vector3(Double(raw[index * 3]) * scale,
                                       Double(raw[index * 3 + 1]) * scale,
                                       Double(raw[index * 3 + 2]) * scale)
        }
        return particles
    }

    /// Which way each rod points, in world space, in the order the rods were
    /// built. A rod's local +z runs from the first of its two particles to the
    /// second, so this is what geometry riding the rod is turned by.
    func rodOrientations() -> [simd_quatd] {
        guard !isDestroyed, rodCount > 0 else { return [] }
        let written = rodRotations.withUnsafeMutableBufferPointer { buffer in
            Int(cjolt_soft_body_get_rod_rotations(world.handle, handle,
                                                  buffer.baseAddress,
                                                  Int32(rodCount)))
        }
        return (0 ..< written).map {
            simd_quatd(ix: Double(rodRotations[$0 * 4]),
                       iy: Double(rodRotations[$0 * 4 + 1]),
                       iz: Double(rodRotations[$0 * 4 + 2]),
                       r: Double(rodRotations[$0 * 4 + 3]))
        }
    }

    /// The average of the particle positions: where the body has drifted to.
    public var position: Vector3 {
        guard !isDestroyed else { return .zero }
        var out = (Float(0), Float(0), Float(0))
        withUnsafeMutableBytes(of: &out) { bytes in
            cjolt_soft_body_get_center(world.handle, handle,
                                       bytes.baseAddress!.assumingMemoryBound(to: Float.self))
        }
        return world.units(from: out.0, out.1, out.2)
    }

    /// The volume the surface currently encloses, in world units cubed. Only
    /// meaningful for a closed surface.
    public var volume: Double {
        guard !isDestroyed else { return 0 }
        let scale = world.unitsPerMeter
        return Double(cjolt_soft_body_get_volume(world.handle, handle)) * scale * scale * scale
    }

    /// Whether the solver is still simulating it, or it has settled to sleep.
    public var isAwake: Bool {
        guard !isDestroyed else { return false }
        return cjolt_soft_body_is_active(world.handle, handle)
    }

    /// Wakes a settled body, so a change it should answer takes effect.
    public func wake() {
        guard !isDestroyed else { return }
        cjolt_soft_body_activate(world.handle, handle)
    }

    /// Which collision group the surface is in: a cloth in a group the crates
    /// ignore drapes straight through them.
    public var group: CollisionGroup {
        get {
            guard !isDestroyed else { return .default }
            return world.group(at: cjolt_body_get_group(world.handle, bodyID))
        }
        set {
            guard !isDestroyed else { return }
            cjolt_body_set_group(world.handle, bodyID, world.groupIndex(newValue))
        }
    }

    // MARK: Touching

    /// Everything the surface is currently resting against or caught on, in a
    /// stable order: the crate a sheet has draped over, the floor it settled
    /// on, the sensor it drifted into.
    ///
    /// A soft body that settles and falls asleep stops reporting, the same way
    /// a settled pile of crates does; a sensor is the way to ask about standing
    /// occupancy.
    public var touching: [any Colliding3D] {
        (world.touchingIDs[bodyID] ?? []).compactMap { world.colliding(at: $0) }
    }

    /// Whether the surface is touching `other` right now.
    public func isTouching(_ other: any Colliding3D) -> Bool {
        guard let otherID = world.identifier(of: other) else { return false }
        return world.touchingIDs[bodyID]?.contains(otherID) ?? false
    }

    /// The touches involving this surface that started or stopped during the
    /// last `step`, out of the world's whole list.
    public var contacts: [Contact3D] {
        world.contacts.filter { $0.involves(self) }
    }

    /// What the surface landed on during the last `step`.
    public var arrivals: [any Colliding3D] {
        world.contacts.compactMap { $0.phase == .began ? $0.other(than: self) : nil }
    }

    /// What the surface came off during the last `step`.
    public var departures: [any Colliding3D] {
        world.contacts.compactMap { $0.phase == .ended ? $0.other(than: self) : nil }
    }

    // MARK: Tuning it while it runs

    /// How heavy the surface is compared with the water it may be dropped in,
    /// exactly the way a collider's `density` is: `0.3` is a cork raft riding
    /// high, `1` floats awash, and anything above sinks. It changes nothing but
    /// buoyancyScale, so the body keeps the `mass` it was built with.
    ///
    /// A closed surface starts with the density its own mass and volume work
    /// out to, so a beach ball just floats. A sheet encloses nothing to work
    /// one out from, so it starts at `1` (fabric, lying awash in the surface);
    /// set it to make a raft:
    ///
    /// ```swift
    /// raft.density = 0.3
    /// ```
    public var density: Double = 1

    /// How hard the gas inside a closed surface pushes out, in gravities: 0 is a
    /// limp bag, 1 just holds its own weight up, and 2 to 4 reads as a firm ball
    /// that still dents. Meaningless on an open sheet, which has no inside.
    public var pressure: Double = 0 {
        didSet {
            guard !isDestroyed, isClosed else { return }
            cjolt_soft_body_set_pressure(world.handle, handle,
                                         Float(max(0, pressure) * pressureScale))
        }
    }

    /// Solver passes per step. More holds the springs tighter and steadies a
    /// heavily loaded body, at a proportional cost.
    public var iterations: Int = 5 {
        didSet {
            guard !isDestroyed else { return }
            cjolt_soft_body_set_iterations(world.handle, handle, Int32(max(1, iterations)))
        }
    }

    /// How far each particle's own body reaches past its position, in world
    /// units. A little of it lifts a draped surface off whatever it lies on,
    /// which is what stops the two from flickering against each other.
    public var vertexRadius: Double = 0 {
        didSet {
            guard !isDestroyed else { return }
            cjolt_soft_body_set_vertex_radius(world.handle, handle,
                                              Float(max(0, vertexRadius) / world.unitsPerMeter))
        }
    }

    // MARK: Holding on to it

    /// Pins the particle behind a source-mesh vertex where it is: it stops
    /// falling and everything attached to it hangs from it.
    public func pin(_ vertex: Int) {
        guard let particle = particle(for: vertex), !isDestroyed else { return }
        cjolt_soft_body_set_vertex_inverse_mass(world.handle, handle, Int32(particle), 0)
    }

    /// Hands a pinned particle back to the simulation.
    public func unpin(_ vertex: Int) {
        guard let particle = particle(for: vertex), !isDestroyed else { return }
        let inverse = Float(Double(particleCount) / max(totalMass, 1e-6))
        cjolt_soft_body_set_vertex_inverse_mass(world.handle, handle,
                                                Int32(particle), inverse)
    }

    /// Whether the particle behind a source-mesh vertex is held in place.
    public func isPinned(_ vertex: Int) -> Bool {
        guard let particle = particle(for: vertex), !isDestroyed else { return false }
        return cjolt_soft_body_get_vertex_inverse_mass(world.handle, handle,
                                                       Int32(particle)) <= 0
    }

    /// Carries a particle to a world-space point over this frame, pinning it if
    /// it was free. The surface hanging off it is dragged along rather than
    /// snapped, which is what makes a corner follow the mouse.
    public func move(_ vertex: Int, to target: Vector3) {
        guard let particle = particle(for: vertex), !isDestroyed else { return }
        let meters = world.meters(from: target)
        var point = (meters.0, meters.1, meters.2)
        withUnsafeBytes(of: &point) { bytes in
            cjolt_soft_body_move_vertex(world.handle, handle, Int32(particle),
                                        bytes.baseAddress!.assumingMemoryBound(to: Float.self),
                                        Float(world.lastTimestep))
        }
    }

    /// The source-mesh vertex nearest a world-space point, so a click can find
    /// a corner to take hold of.
    public func nearestVertex(to point: Vector3) -> Int? {
        let all = positions
        guard !all.isEmpty else { return nil }
        var best = 0
        var bestDistance = Double.infinity
        for (index, p) in all.enumerated() {
            let d = (p - point).lengthSquared
            if d < bestDistance { bestDistance = d; best = index }
        }
        return best
    }

    /// Pushes the whole body with a force in newtons, spread evenly over its
    /// particles. This is how wind is applied: impulses do not reach a body
    /// whose velocity lives per particle.
    public func applyForce(_ force: Vector3) {
        guard !isDestroyed else { return }
        let meters = world.meters(from: force)
        var value = (meters.0, meters.1, meters.2)
        withUnsafeBytes(of: &value) { bytes in
            cjolt_soft_body_add_force(world.handle, handle,
                                      bytes.baseAddress!.assumingMemoryBound(to: Float.self))
        }
    }

    // MARK: Carried by a figure

    /// Pose the skin from a scene's skeleton, ready for the next `step`.
    ///
    /// Call it once a frame, after the scene has been posed (by an animation,
    /// or by `scene.apply(ragdoll)`) and before `world.advance(by:)`:
    ///
    /// ```swift
    /// figure.apply(ragdoll)
    /// cape.follow(figure)
    /// world.advance(by: deltaTime)
    /// ```
    ///
    /// The joints are read in the scene's own space, which is the space the
    /// surface was hung in and the space `drawScene(_:)` draws in, so a figure
    /// that walks carries the cloth with it. A surface no skeleton carries
    /// ignores this.
    public func follow(_ scene: Scene) {
        guard isSkinned, !isDestroyed else { return }
        pendingPose = jointPose(from: scene.skeleton())
    }

    /// Put every carried particle exactly where the skeleton says, right now,
    /// and stop it dead. This is the teleport: what a surface needs when the
    /// figure it hangs on has been stood somewhere else rather than moved
    /// there, so it should arrive with it instead of being dragged across.
    public func snap(to scene: Scene) {
        guard isSkinned, !isDestroyed,
              let pose = jointPose(from: scene.skeleton()) else { return }
        applySkin(pose, hard: true)
        pendingPose = nil
    }

    /// Whether the skin is holding the surface at all. Turn it off and only
    /// the particles held exactly on it keep following: a cape stays on the
    /// shoulders and everything below goes limp.
    public var followsSkin: Bool = true {
        didSet {
            guard !isDestroyed, isSkinned else { return }
            cjolt_soft_body_set_skin_enabled(world.handle, handle, followsSkin)
        }
    }

    /// Scales every particle's `sway` at once, so one number lets the whole
    /// surface out or reins it in while it runs. `1` is what it was built with.
    public var swayScale: Double = 1 {
        didSet {
            guard !isDestroyed, isSkinned else { return }
            cjolt_soft_body_set_skin_slack(world.handle, handle, Float(max(0, swayScale)))
        }
    }

    /// Hand the world's step whatever `follow(_:)` recorded. Applying it here
    /// rather than in `follow` is what keeps it to once per step.
    func applyPendingSkin() {
        guard let pendingPose else { return }
        self.pendingPose = nil
        applySkin(pendingPose, hard: false)
    }

    /// A skeleton's joints flattened to the column-major meter-scale matrices
    /// the bridge takes, or `nil` if the skeleton is not the one this surface
    /// was hung on.
    private func jointPose(from joints: [SceneSkeletonJoint]) -> [Float]? {
        guard joints.count >= skinning.binds.count else {
            world.noteOnce("this surface was hung on a skeleton of "
                           + "\(skinning.binds.count) joints and was handed one of "
                           + "\(joints.count), so it is not being posed")
            return nil
        }
        let scale = Float(world.unitsPerMeter)
        var flat = [Float](repeating: 0, count: joints.count * 16)
        for (index, joint) in joints.enumerated() {
            SoftBody3D.write(SoftBody3D.inMeters(joint.world, scale: scale),
                             into: &flat, at: index * 16)
        }
        return flat
    }

    private func applySkin(_ pose: [Float], hard: Bool) {
        guard !isDestroyed else { return }
        pose.withUnsafeBufferPointer { buffer in
            cjolt_soft_body_skin(world.handle, handle, buffer.baseAddress,
                                 Int32(pose.count / 16), hard)
        }
        // The skin constraints are solved by the step, so a surface that has
        // settled and gone to sleep stops answering the figure entirely: stand
        // still until a cape hangs quiet, walk away, and it is left behind. A
        // pose that has actually changed is what wakes it, which is also what
        // lets a cape on a still figure sleep, the way a settled pile does.
        if pose != lastPose {
            lastPose = pose
            wake()
        }
    }

    // MARK: Internals

    /// What ties a surface to a skeleton, worked out from the rest shape.
    struct Skin {
        /// One inverse bind per joint of the skeleton, kept so a later pose can
        /// be measured against the one the surface was hung in.
        var binds: [simd_float4x4] = []
        /// The same matrices flattened for the bridge.
        var flatBinds: [Float] = []
        /// Which particles the skeleton carries, in particle order.
        var vertices: [CJoltSoftSkinVertex] = []
        /// Joint names the closure asked for that the skeleton does not have.
        var unknownJoints: Set<String> = []
    }

    /// Work out which joint carries each particle, and how far it may stray.
    ///
    /// The bind pose is *whatever the figure is standing in right now*, which
    /// is what makes this work without authored weights: a cape hung on a
    /// figure is bound where it was hung, and every later pose is measured as
    /// the motion since. So `inverseBind` takes a particle's rest position out
    /// of the surface's own frame and into the joint's, and the frame pose puts
    /// it back.
    private static func skin(mesh: Mesh, welding: MeshWelding,
                             skeleton: [SceneSkeletonJoint],
                             carriedBy: ((Vector3) -> String?)?,
                             sway: ((Vector3) -> Double)?,
                             backStop: Double?,
                             pinned: ((Vector3) -> Bool)?,
                             position: Vector3, rotation: simd_quatd,
                             unitsPerMeter: Double) -> Skin {
        guard let carriedBy, !skeleton.isEmpty else { return Skin() }
        var out = Skin()
        let scale = Float(unitsPerMeter)

        let placement = placement(position: position, rotation: rotation,
                                  unitsPerMeter: unitsPerMeter)
        var slotOf: [String: Int] = [:]
        for (slot, joint) in skeleton.enumerated()
        where !joint.name.isEmpty && slotOf[joint.name] == nil {
            slotOf[joint.name] = slot
        }

        // Which joint holds each particle, and how far it may travel from it.
        // A mesh's coincident vertices merge onto one particle and the closures
        // answer the same for each of them, so the first joint wins and the
        // tightest leash does.
        var jointOf: [Int: Int] = [:]
        var distanceOf: [Int: Double] = [:]
        for (source, particle) in welding.remap.enumerated()
        where source < mesh.positions.count {
            let point = mesh.positions[source]
            guard let name = carriedBy(point) else { continue }
            guard let slot = slotOf[name] else {
                out.unknownJoints.insert(name)
                continue
            }
            // A pinned particle is held by whatever holds it: by the figure
            // when a joint carries it, by the world when none does.
            let held = pinned?(point) ?? false
            let distance = held ? 0 : max(0, sway?(point) ?? .infinity)
            if jointOf[particle] == nil { jointOf[particle] = slot }
            distanceOf[particle] = min(distanceOf[particle] ?? .infinity, distance)
        }
        guard !jointOf.isEmpty else { return out }

        out.binds = skeleton.map {
            SoftBody3D.inMeters($0.world, scale: scale).inverse * placement
        }
        out.flatBinds = SoftBody3D.flattened(out.binds)

        let stop = backStop.map { Float(max(0, $0) / unitsPerMeter) } ?? .infinity
        for particle in jointOf.keys.sorted() {
            var entry = CJoltSoftSkinVertex()
            entry.vertex = Int32(particle)
            entry.joints.0 = UInt32(jointOf[particle] ?? 0)
            entry.weights.0 = 1
            let distance = distanceOf[particle] ?? .infinity
            entry.maxDistance = distance.isFinite
                ? Float(distance / unitsPerMeter) : .infinity
            entry.backStopDistance = stop
            // The library's own default: a sphere big enough to read as a
            // plane behind the surface.
            entry.backStopRadius = 40
            out.vertices.append(entry)
        }
        return out
    }

    /// Where the rest shape stands, in meters: the surface's own frame, which
    /// is what an inverse bind takes a particle out of.
    private static func placement(position: Vector3, rotation: simd_quatd,
                                  unitsPerMeter: Double) -> simd_float4x4 {
        var out = simd_float4x4(simd_quatf(
            ix: Float(rotation.imag.x), iy: Float(rotation.imag.y),
            iz: Float(rotation.imag.z), r: Float(rotation.real)))
        out.columns.3 = SIMD4<Float>(Float(position.x / unitsPerMeter),
                                     Float(position.y / unitsPerMeter),
                                     Float(position.z / unitsPerMeter), 1)
        return out
    }

    /// A transform whose translation is in meters rather than world units. The
    /// rotation is untouched, so a bind and a later pose measured this way
    /// compose exactly as they do in world units.
    private static func inMeters(_ m: simd_float4x4, scale: Float) -> simd_float4x4 {
        var out = m
        out.columns.3 = SIMD4<Float>(m.columns.3.x / scale, m.columns.3.y / scale,
                                     m.columns.3.z / scale, m.columns.3.w)
        return out
    }

    /// Matrices flattened into one column-major float array, which is the
    /// shape the bridge takes them in.
    static func flattened(_ matrices: [simd_float4x4]) -> [Float] {
        var flat = [Float](repeating: 0, count: matrices.count * 16)
        for (index, m) in matrices.enumerated() { write(m, into: &flat, at: index * 16) }
        return flat
    }

    /// A matrix written into a flat column-major float array.
    private static func write(_ m: simd_float4x4, into flat: inout [Float], at start: Int) {
        for column in 0 ..< 4 {
            flat[start + column * 4] = m[column].x
            flat[start + column * 4 + 1] = m[column].y
            flat[start + column * 4 + 2] = m[column].z
            flat[start + column * 4 + 3] = m[column].w
        }
    }

    private func particle(for vertex: Int) -> Int? {
        guard vertex >= 0, vertex < welding.remap.count else { return nil }
        return welding.remap[vertex]
    }

    /// Maps a 0…1 stiffness onto the solver's compliance: the meters a spring
    /// gives per newton pulling on it.
    ///
    /// Compliance is a physical quantity, so a fixed number means different
    /// things on different bodies: the same 0.001 that visibly softens a heavy
    /// cloth does nothing at all to a light one, because the load is a
    /// thousandth of the size. The parameter is made scale-free by turning it into a
    /// *relative stretch* instead, and `scale` converts that back:
    ///
    ///     scale = meanEdgeLength * sqrt(particleCount) / (mass * gravity)
    ///
    /// which is the compliance at which one edge, carrying its share of the
    /// body's own hanging weight, stretches by its own length. So a softness of
    /// `0.1` means "the most loaded springs give about a tenth of their length",
    /// on a curtain or on a beach ball.
    /// The compliance a rod's bend-and-twist parameter maps onto, per unit of
    /// softness, in the same 0…1 terms the rest of the tier uses.
    ///
    /// A rod's bend constraint holds a *rotation*, which is a pure number, so
    /// unlike a stretch constraint there is no length in it to compare against
    /// and its scale has to be measured. Hanging a rope out sideways and asking
    /// what compliance leaves the tip drooping by a third of the rope's own
    /// length gives, across every size probed:
    ///
    ///     compliance  ∝  meanRod² / (length³ · mass · gravity)
    ///
    /// which is what makes one `bend` setting mean the same thing on a stem, a
    /// vine, and a mooring line. The constant is what puts "drooping about a
    /// third of the way" in the middle of the parameter rather than at one end.
    static func rodBendScale(meanEdge: Double, length: Double, mass: Double,
                             gravity: Double) -> Double {
        let span = max(length, 1e-9)
        return 100 * meanEdge * meanEdge / (span * span * span * mass * gravity)
    }

    private static func compliance(for stiffness: Double, scale: Double) -> Double {
        guard stiffness < 1 else { return 0 }
        let softness = (1 / max(stiffness, 1e-3) - 1) / 10
        return softness * scale
    }

    /// Whether the normals derived from the winding point the opposite way to
    /// the ones the source mesh shades with, decided once from the rest shape.
    ///
    /// A mesh's winding and its normals need not agree: some of Ollin's own
    /// generators wind one way and shade the other, and a loaded mesh can do
    /// anything. Deriving normals from the winding alone therefore lights half
    /// the catalog inside out (a plane came back black-side-up, which is what
    /// found this), so what the source mesh *shades* with is the authority.
    private let normalsAreFlipped: Bool

    /// Area-weighted vertex normals over the given topology. The cross product
    /// of two edges is already twice the triangle's area, so summing it weights
    /// each face by its size for free.
    static func normals(positions: [Vector3], indices: [UInt32],
                        fallback: [Vector3], flipped: Bool = false) -> [Vector3] {
        var sums = [Vector3](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let ia = Int(indices[i]), ib = Int(indices[i + 1]), ic = Int(indices[i + 2])
            if ia < positions.count, ib < positions.count, ic < positions.count {
                let n = (positions[ib] - positions[ia]).cross(positions[ic] - positions[ia])
                sums[ia] = sums[ia] + n
                sums[ib] = sums[ib] + n
                sums[ic] = sums[ic] + n
            }
            i += 3
        }
        let sign: Double = flipped ? -1 : 1
        for index in sums.indices {
            let length = sums[index].length
            if length > 1e-12 {
                sums[index] = sums[index] * (sign / length)
            } else if index < fallback.count {
                sums[index] = fallback[index]
            } else {
                sums[index] = Vector3(0, 1, 0)
            }
        }
        return sums
    }

    /// An undirected edge of the welded surface, for the closed-surface test.
    private struct Edge: Hashable {
        let low: Int
        let high: Int
        init(_ a: Int, _ b: Int) {
            low = min(a, b)
            high = max(a, b)
        }
    }
}
