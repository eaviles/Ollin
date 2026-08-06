import Foundation
import simd
import Ollin

// Turning a skinned skeleton into a set of limbs: which joints become bodies,
// which joint each of the others rides, and what shape each body wears. The
// shapes are fitted to the *mesh*, not guessed from bone lengths, because a
// figure's proportions live in its skin: a torso is wide and a forearm is thin
// even though both are one bone. Each limb's body stands at its joint, so the
// fitted capsule is pushed out along the bone from there, and the simulated
// body transform is the joint transform with nothing to undo.

/// The layout of a ragdoll worked out before any solver object exists, so the
/// arithmetic can be read (and tested) on its own.
struct RagdollPlan {

    struct PlannedLimb {
        /// This limb's joint, as an index into the skeleton array.
        var skinIndex: Int
        /// The joint's name in the file, which is how a limb is found by name.
        var name: String
        /// The joint's prim identity in the file, which is what a pose handed
        /// in later binds by.
        var sourceIndex: Int
        /// The limb above it, as an index into `limbs`, or -1 for the root.
        var parent: Int
        var collider: Collider3D
        /// Where the fitted shape sits inside the body, and how it is turned
        /// there (the rotation that stands a `+y` shape up along the bone).
        var shapeCenter: Vector3
        var shapeAngle: Double
        var shapeAxis: Vector3
        /// The joint's world pose, placement offset included.
        var jointOrigin: Vector3
        var jointRotation: simd_quatf
        /// The bone's direction in world space: the axis the joint twists about
        /// and the cone leans away from.
        var worldAxis: Vector3
        /// The limb's share of the figure's weight, in kg (0 leaves it to the
        /// shape's own volume).
        var mass: Double
    }

    var limbs: [PlannedLimb] = []

    /// How many joints the skeleton this was fitted from had, so a pose handed
    /// in later can be checked against it.
    var skinJointCount = 0

    /// An empty plan, filled in by whoever read one back.
    init() {}

    /// Where the figure's root joint currently is, so a caller can ask for it
    /// to stand somewhere else.
    static func placement(of skeleton: [SceneSkeletonJoint], at position: Vector3?)
        -> Vector3 {
        guard let position, let root = skeleton.first(where: { $0.parent == nil })
        else { return .zero }
        return position - Vector3(Double(root.world.columns.3.x),
                                  Double(root.world.columns.3.y),
                                  Double(root.world.columns.3.z))
    }

    init(skeleton: [SceneSkeletonJoint], vertices: [SceneSkinnedVertex],
         names: [String]?, mass: Double, offset: Vector3) {
        let count = skeleton.count
        skinJointCount = count
        guard count > 0 else { return }

        // Which joints get a body. A named subset keeps the roots whatever the
        // list says, since a figure with no root has nothing to hang off.
        var included = [Bool](repeating: true, count: count)
        if let names {
            let wanted = Set(names)
            for k in 0..<count {
                included[k] = wanted.contains(skeleton[k].name) || skeleton[k].parent == nil
            }
        }

        // The limb that carries each joint: itself if it has a body, otherwise
        // the nearest ancestor that does. A joint left out keeps its pose and
        // rides that limb rigidly, which is how a hand's fingers stay attached
        // without becoming twenty bodies.
        var owner = [Int](repeating: 0, count: count)
        for k in 0..<count {
            var current = k
            var guardCount = 0
            while !included[current], let parent = skeleton[current].parent,
                  guardCount < count {
                current = parent
                guardCount += 1
            }
            owner[k] = current
        }

        // Parents before children: every skeleton algorithm downstream needs
        // it, and the skin's own joint order does not promise it.
        var limbOf = [Int](repeating: -1, count: count)
        var order: [Int] = []
        var visiting = [Bool](repeating: false, count: count)
        func emit(_ k: Int) {
            guard included[k], limbOf[k] < 0, !visiting[k] else { return }
            visiting[k] = true
            if let parent = skeleton[k].parent, owner[parent] != k { emit(owner[parent]) }
            visiting[k] = false
            limbOf[k] = order.count
            order.append(k)
        }
        for k in 0..<count { emit(k) }
        guard !order.isEmpty else { return }

        // How big the figure is, which sets the floors the fits clamp against.
        var low = Vector3(.infinity, .infinity, .infinity)
        var high = Vector3(-.infinity, -.infinity, -.infinity)
        for joint in skeleton {
            let p = Vector3(Double(joint.world.columns.3.x), Double(joint.world.columns.3.y),
                            Double(joint.world.columns.3.z))
            low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
            high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        }
        let span = high - low
        let figureScale = max(max(span.x, max(span.y, span.z)), 1e-4)

        // Each vertex belongs to the limb that pulls on it hardest, so the
        // shape fitted to a limb is the part of the figure it actually moves.
        var assigned = [[Vector3]](repeating: [], count: order.count)
        var share = [Double](repeating: 0, count: order.count)
        for vertex in vertices {
            for i in share.indices { share[i] = 0 }
            for slot in 0..<4 {
                let weight = Double(vertex.weights[slot])
                guard weight > 0 else { continue }
                let joint = Int(vertex.joints[slot])
                guard joint >= 0, joint < count else { continue }
                let limb = limbOf[owner[joint]]
                guard limb >= 0 else { continue }
                share[limb] += weight
            }
            var best = -1
            var bestWeight = 0.0
            for i in share.indices where share[i] > bestWeight {
                best = i
                bestWeight = share[i]
            }
            if best >= 0 { assigned[best].append(vertex.position) }
        }

        // Fit a shape to each limb, in the joint's own frame.
        var volumes = [Double](repeating: 0, count: order.count)
        var planned: [PlannedLimb] = []
        planned.reserveCapacity(order.count)
        for (index, k) in order.enumerated() {
            let joint = skeleton[k]
            let children = order.enumerated().compactMap { childIndex, childJoint -> Vector3? in
                guard childIndex != index, let parent = skeleton[childJoint].parent,
                      limbOf[owner[parent]] == index else { return nil }
                return RagdollPlan.localOrigin(of: skeleton[childJoint].world,
                                               in: joint.inverseBind)
            }
            let parentDirection = skeleton[k].parent.map {
                RagdollPlan.localOrigin(of: skeleton[$0].world, in: joint.inverseBind)
            }
            let points = assigned[index].map {
                RagdollPlan.local($0, in: joint.inverseBind)
            }
            let fit = RagdollPlan.fit(points: points, children: children,
                                      towardParent: parentDirection, scale: figureScale)

            let rotation = RagdollPlan.rotation(of: joint.world)
            let origin = Vector3(Double(joint.world.columns.3.x),
                                 Double(joint.world.columns.3.y),
                                 Double(joint.world.columns.3.z)) + offset
            let axisWorld = rotation.act(SIMD3<Float>(Float(fit.axis.x), Float(fit.axis.y),
                                                      Float(fit.axis.z)))
            let stand = RagdollPlan.standUp(fit.axis)
            volumes[index] = fit.volume
            planned.append(PlannedLimb(
                skinIndex: k,
                name: joint.name,
                sourceIndex: joint.sourceIndex,
                parent: skeleton[k].parent.map { limbOf[owner[$0]] } ?? -1,
                collider: fit.collider, shapeCenter: fit.center,
                shapeAngle: stand.angle, shapeAxis: stand.axis,
                jointOrigin: origin, jointRotation: rotation,
                worldAxis: Vector3(Double(axisWorld.x), Double(axisWorld.y),
                                   Double(axisWorld.z)),
                mass: 0))
        }

        // The figure's weight split by how much of it each limb is: a torso
        // outweighs a forearm because it fills more space, not because a table
        // says so.
        if mass > 0 {
            let total = volumes.reduce(0, +)
            if total > 0 {
                for i in planned.indices { planned[i].mass = mass * volumes[i] / total }
            }
        }
        limbs = planned
    }

    // MARK: Fitting one limb

    struct Fit {
        var collider: Collider3D
        var center: Vector3
        var axis: Vector3
        var volume: Double
    }

    /// The capsule that best covers `points` (a limb's own share of the mesh,
    /// in the joint's frame): its long axis is the spread of the flesh, its
    /// radius the thickness most of it sits inside, and its ends the extent
    /// along that axis. With too little mesh to go on it falls back to the bone
    /// itself, and with no bone either to a small ball at the joint.
    static func fit(points: [Vector3], children: [Vector3], towardParent: Vector3?,
                    scale: Double) -> Fit {
        let floor = 0.008 * scale
        guard points.count >= 4 else {
            return fallback(children: children, towardParent: towardParent, scale: scale)
        }

        var centroid = Vector3.zero
        for p in points { centroid = centroid + p }
        centroid = centroid / Double(points.count)
        var axis = principalAxis(of: points, about: centroid)

        // The bone points away from the parent, which is the direction the
        // twist limit is measured about; with no parent, out toward the flesh.
        if let towardParent, towardParent.lengthSquared > 1e-12 {
            if axis.dot(towardParent) > 0 { axis = axis * -1 }
        } else if !children.isEmpty {
            var toChildren = Vector3.zero
            for c in children { toChildren = toChildren + c }
            if axis.dot(toChildren) < 0 { axis = axis * -1 }
        }

        var along = [Double]()
        var across = [Double]()
        along.reserveCapacity(points.count)
        across.reserveCapacity(points.count)
        for p in points {
            let d = p - centroid
            let t = d.dot(axis)
            along.append(t)
            across.append((d - axis * t).length)
        }
        // Most of the flesh, not all of it: a stray vertex on a fingertip
        // should not decide how thick an arm is.
        let radius = max(quantile(across, 0.85), floor)
        let low = quantile(along, 0.02)
        let high = quantile(along, 0.98)
        let center = centroid + axis * ((low + high) / 2)
        let half = max(0, (high - low) / 2 - radius)
        if half < floor {
            return Fit(collider: .sphere(radius: radius), center: center, axis: axis,
                       volume: 4.0 / 3 * .pi * radius * radius * radius)
        }
        return Fit(collider: .capsule(height: 2 * half, radius: radius), center: center,
                   axis: axis,
                   volume: .pi * radius * radius * 2 * half
                       + 4.0 / 3 * .pi * radius * radius * radius)
    }

    /// The shape for a limb the skin says nothing about: a capsule along the
    /// bone to its children, or a small ball at a bare joint.
    private static func fallback(children: [Vector3], towardParent: Vector3?,
                                 scale: Double) -> Fit {
        var direction = Vector3.zero
        for c in children { direction = direction + c }
        if direction.lengthSquared < 1e-12, let towardParent {
            direction = towardParent * -1
        }
        let length = direction.length
        guard length > 1e-9 else {
            let radius = 0.05 * scale
            return Fit(collider: .sphere(radius: radius), center: .zero, axis: .unitY,
                       volume: 4.0 / 3 * .pi * radius * radius * radius)
        }
        let axis = direction / length
        let bone = children.isEmpty ? length * 0.4 : length
        let radius = max(bone * 0.18, 0.008 * scale)
        let half = max(0, bone / 2 - radius)
        let center = axis * (bone / 2)
        if half < 1e-6 {
            return Fit(collider: .sphere(radius: radius), center: center, axis: axis,
                       volume: 4.0 / 3 * .pi * radius * radius * radius)
        }
        return Fit(collider: .capsule(height: 2 * half, radius: radius), center: center,
                   axis: axis,
                   volume: .pi * radius * radius * 2 * half
                       + 4.0 / 3 * .pi * radius * radius * radius)
    }

    /// The direction the points spread furthest along: the dominant eigenvector
    /// of their covariance, found by power iteration from whichever world axis
    /// already varies most (so the start can never sit at right angles to the
    /// answer).
    static func principalAxis(of points: [Vector3], about centroid: Vector3) -> Vector3 {
        var covariance = simd_float3x3(0)
        for p in points {
            let d = SIMD3<Float>(Float(p.x - centroid.x), Float(p.y - centroid.y),
                                 Float(p.z - centroid.z))
            covariance += simd_float3x3(d * d.x, d * d.y, d * d.z)
        }
        var best = 0
        for i in 1..<3 where covariance[i][i] > covariance[best][best] { best = i }
        var v = SIMD3<Float>(best == 0 ? 1 : 0, best == 1 ? 1 : 0, best == 2 ? 1 : 0)
        for _ in 0..<48 {
            let w = covariance * v
            let length = simd_length(w)
            guard length > 1e-20 else { break }
            v = w / length
        }
        let out = Vector3(Double(v.x), Double(v.y), Double(v.z))
        return out.lengthSquared > 1e-12 ? out.normalized : .unitY
    }

    /// The `angle`/`axis` rotation that stands a `+y` shape up along `axis`.
    static func standUp(_ axis: Vector3) -> (angle: Double, axis: Vector3) {
        let unit = axis.normalized
        let cosine = max(-1, min(1, unit.y))
        if cosine > 1 - 1e-9 { return (0, .unitY) }
        if cosine < -1 + 1e-9 { return (.pi, .unitX) }
        return (acos(cosine), Vector3.unitY.cross(unit).normalized)
    }

    /// A bind-space mesh point in a joint's own frame.
    static func local(_ p: Vector3, in inverseBind: simd_float4x4) -> Vector3 {
        let v = inverseBind * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
        return Vector3(Double(v.x), Double(v.y), Double(v.z))
    }

    /// Another joint's origin in this joint's frame.
    static func localOrigin(of world: simd_float4x4,
                            in inverseBind: simd_float4x4) -> Vector3 {
        let m = inverseBind * world
        return Vector3(Double(m.columns.3.x), Double(m.columns.3.y), Double(m.columns.3.z))
    }

    /// The rotation a (possibly scaled) world transform carries.
    static func rotation(of m: simd_float4x4) -> simd_quatf {
        var basis = matrix_identity_float4x4
        for column in 0..<3 {
            let axis = SIMD3<Float>(m[column].x, m[column].y, m[column].z)
            let length = simd_length(axis)
            let unit = SIMD3<Float>(column == 0 ? 1 : 0, column == 1 ? 1 : 0,
                                    column == 2 ? 1 : 0)
            basis[column] = SIMD4<Float>(length > 1e-9 ? axis / length : unit, 0)
        }
        return simd_normalize(simd_quatf(basis))
    }

    /// The value `fraction` of the way through `values` in order.
    static func quantile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[max(0, min(sorted.count - 1, index))]
    }
}
