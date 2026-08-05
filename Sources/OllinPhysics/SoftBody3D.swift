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
/// world.step(dt: deltaTime)
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
public final class SoftBody3D {

    /// Anything a sketch hung on this body.
    public var userData: Any?

    /// The mesh it was built from, in its own local space, unchanged.
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

    /// The solver's id for the body, so a ray cast hit can be recognised.
    let bodyID: CJoltBodyID

    /// The source mesh's vertices merged onto particles, plus the map back.
    private let welding: MeshWelding

    /// Raw pressure per unit of the `pressure` knob: the body's own mass, rest
    /// volume, and rest area folded into one number, so `pressure` means the
    /// same at any size.
    private let pressureScale: Double

    /// The last read-back, and the world step it was taken at, so drawing the
    /// same body twice in a frame costs one copy rather than two.
    private var cachedMesh: Mesh?
    private var cachedGeneration: Int = -1

    /// Scratch for the particle read-back, reused across frames.
    private var particles: [Vector3]

    /// The total mass, kept so `unpin` can restore a particle's share of it.
    private let totalMass: Double

    /// Set by the world when it goes, so a body a sketch still holds does not
    /// reach into a solver that no longer exists.
    var isDestroyed = false

    init?(world: World3D, mesh: Mesh, position: Vector3, rotation: simd_quatd,
          mass: Double, stiffness: Double, bend: Double, pressure: Double,
          damping: Double, friction: Double, restitution: Double,
          iterations: Int, vertexRadius: Double, twoSided: Bool,
          pinned: ((Vector3) -> Bool)?) {
        let welding = mesh.welded()
        guard welding.count >= 3, welding.indices.count >= 3 else { return nil }

        self.world = world
        self.sourceMesh = mesh
        self.welding = welding
        self.particles = welding.positions

        // Rest measurements, in meters, are what let the knobs mean the same
        // thing whatever the body's size: the pressure knob is calibrated
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
        // A closed surface is one where every edge belongs to exactly two
        // faces; anything else has a boundary and no inside to pressurise.
        isClosed = !edgeCounts.isEmpty && edgeCounts.values.allSatisfy { $0 == 2 }
        let volume = abs(sixVolume) / 6

        let massKg = max(mass, 1e-6)
        totalMass = massKg
        let particleMass = massKg / Double(welding.count)
        var edgeTotal = 0.0
        for (edge, _) in edgeCounts {
            edgeTotal += ((welding.positions[edge.high] - welding.positions[edge.low]) / scale).length
        }
        let meanEdge = edgeCounts.isEmpty ? 1 : edgeTotal / Double(edgeCounts.count)
        // The solver's pressure is `n R T`, and the outward acceleration it
        // gives works out to pressure * area / (mass * volume). Expressing the
        // knob as that acceleration in gravities is what makes `pressure: 1`
        // mean "just holds its own weight up" at any scale.
        let gravity = world.gravity.length > 1e-6 ? world.gravity.length : 9.8
        pressureScale = area > 1e-12 && volume > 1e-12
            ? gravity * massKg * volume / area : 0

        var inverseMasses = [Float](repeating: Float(1 / particleMass),
                                    count: welding.count)
        if let pinned {
            for (source, particle) in welding.remap.enumerated()
            where source < mesh.positions.count {
                if pinned(mesh.positions[source]) { inverseMasses[particle] = 0 }
            }
        }

        // The compliance a knob setting maps onto depends on the body it is
        // describing, so the scale is measured from the rest shape once.
        let complianceScale = meanEdge * Double(welding.count).squareRoot()
            / (massKg * gravity)

        var desc = CJoltSoftBodyDesc()
        desc.vertexCount = Int32(welding.count)
        desc.indexCount = Int32(welding.indices.count)
        desc.compliance = Float(SoftBody3D.compliance(for: stiffness, scale: complianceScale))
        // A fold constraint measures an angle where a stretch constraint
        // measures a length, so its compliance carries two fewer powers of
        // length: dividing by the edge length squared is what puts the same
        // 0…1 knob over the range that actually reads as limp to stiff.
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

        let created: OpaquePointer? = restPositions.withUnsafeBufferPointer { points in
            welding.indices.withUnsafeBufferPointer { indices in
                inverseMasses.withUnsafeBufferPointer { masses in
                    desc.positions = points.baseAddress
                    desc.indices = indices.baseAddress
                    desc.inverseMasses = masses.baseAddress
                    return withUnsafePointer(to: desc) {
                        cjolt_soft_body_create(world.handle, $0)
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
        self.pressure = pressure
        self.iterations = max(1, iterations)
        self.vertexRadius = vertexRadius

        if pressure > 0 && !isClosed {
            world.noteOnce("pressure needs a closed surface to fill; this mesh "
                           + "has an open edge, so the pressure is ignored.")
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

    /// The average of the particle positions: where the body has drifted to.
    public var center: Vector3 {
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

    // MARK: Tuning it while it runs

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

    // MARK: Internals

    private func particle(for vertex: Int) -> Int? {
        guard vertex >= 0, vertex < welding.remap.count else { return nil }
        return welding.remap[vertex]
    }

    /// Maps a 0…1 stiffness onto the solver's compliance: the metres a spring
    /// gives per newton pulling on it.
    ///
    /// Compliance is a physical quantity, so a fixed number means different
    /// things on different bodies: the same 0.001 that visibly softens a heavy
    /// cloth does nothing at all to a light one, because the load is a
    /// thousandth of the size. The knob is made scale-free by turning it into a
    /// *relative stretch* instead, and `scale` converts that back:
    ///
    ///     scale = meanEdgeLength * sqrt(particleCount) / (mass * gravity)
    ///
    /// which is the compliance at which one edge, carrying its share of the
    /// body's own hanging weight, stretches by its own length. So a softness of
    /// `0.1` means "the most loaded springs give about a tenth of their length",
    /// on a curtain or on a beach ball.
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
