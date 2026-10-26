import Foundation
import Ollin
internal import CBox2D

/// A rigid `Body` as the soft side sees it through one step: its shapes in its
/// own frame, where its center of mass will be when the step ends, and the
/// corrections the soft particles have handed it so far, which it takes as one
/// impulse before the rigid side steps.
///
/// The soft side moves positions and the rigid side moves velocities, so a
/// contact between them is split the way a contact between two particles is,
/// by inverse mass at the point of contact: the particle takes its share as a
/// move, and the body's share is kept here as a pending shift and turn of its
/// pose, so the next pass measures the particle against where the body is
/// going rather than pushing it again for a move the body has not made yet.
/// When the passes end, that pending motion over the step is the impulse the
/// body is given, equal and opposite to the particles' change of momentum.
struct RigidProxy {

    /// A collider in the body's own frame, in points.
    enum Shape {
        case circle(center: Vector2, radius: Double)
        case capsule(a: Vector2, b: Vector2, radius: Double)
        case polygon(vertices: [Vector2], normals: [Vector2], radius: Double)
    }

    let body: Body

    /// The body's colliders, each with its friction.
    let shapes: [(shape: Shape, friction: Double)]

    /// The center of mass in the body's frame.
    let localCenter: Vector2

    /// Where the center of mass will be when the step ends, before any
    /// correction, and the body's angle then: the pose the particles, which
    /// have already taken their step, are measured against.
    let center: Vector2
    let angle: Double

    /// The body's motion, in points per second and radians per second.
    let velocity: Vector2
    let spin: Double

    /// The inverse mass, and the inverse rotational inertia per mass times
    /// points squared; both zero for a static or kinematic body.
    let inverseMass: Double
    let inverseInertia: Double

    /// The farthest any point of any shape lies from the center of mass.
    let reach: Double

    /// The corrections handed to the body so far this step: a shift of its
    /// center and a turn about it.
    var shift = Vector2.zero
    var turn = 0.0

    /// The same corrections as the impulse they are over the step, in
    /// mass·points per second and mass·points² per second.
    var impulse = Vector2.zero
    var angularImpulse = 0.0

    /// The box round the body where the passes have put it, the broad phase.
    var box: SoftBody.Box {
        let c = center + shift
        return SoftBody.Box(minX: c.x - reach, minY: c.y - reach, maxX: c.x + reach, maxY: c.y + reach)
    }

    /// Whether the body can be moved by what it touches.
    var moves: Bool { inverseMass > 0 }

    /// The body's pose as the passes have corrected it: the center and the
    /// cosine and sine of the angle.
    var pose: (center: Vector2, cosine: Double, sine: Double) {
        let a = angle + turn
        return (center + shift, cos(a), sin(a))
    }

    /// `point` in the body's frame under the corrected pose.
    func local(_ point: Vector2, under pose: (center: Vector2, cosine: Double, sine: Double)) -> Vector2 {
        let d = point - pose.center
        return Vector2(pose.cosine * d.x + pose.sine * d.y, -pose.sine * d.x + pose.cosine * d.y)
            + localCenter
    }

    /// A point of the body's frame in the world under the corrected pose.
    func world(_ point: Vector2, under pose: (center: Vector2, cosine: Double, sine: Double)) -> Vector2 {
        let d = point - localCenter
        return Vector2(pose.cosine * d.x - pose.sine * d.y, pose.sine * d.x + pose.cosine * d.y)
            + pose.center
    }

    /// A direction of the body's frame in the world under the corrected pose.
    func direction(_ v: Vector2, under pose: (center: Vector2, cosine: Double, sine: Double)) -> Vector2 {
        Vector2(pose.cosine * v.x - pose.sine * v.y, pose.sine * v.x + pose.cosine * v.y)
    }

    /// How a point of the body moves over the step, with the corrections so
    /// far: `arm` is the point relative to the center of mass.
    func displacement(at arm: Vector2, over h: Double) -> Vector2 {
        (velocity + arm.perpendicular * spin) * h + shift + arm.perpendicular * turn
    }

    /// The shallowest way out for a point inside the body, in the body's
    /// frame: how deep it is, the outward normal there, and the surface point.
    /// `nil` when the point is outside every shape.
    func penetration(ofLocal p: Vector2) -> (depth: Double, normal: Vector2, point: Vector2, friction: Double)? {
        var best: (depth: Double, normal: Vector2, point: Vector2, friction: Double)?
        for (shape, friction) in shapes {
            guard let hit = RigidProxy.penetration(of: p, in: shape) else { continue }
            if best == nil || hit.depth < best!.depth {
                best = (hit.depth, hit.normal, hit.point, friction)
            }
        }
        return best
    }

    /// A point against one shape in the shape's own frame.
    static func penetration(of p: Vector2, in shape: Shape) -> (depth: Double, normal: Vector2, point: Vector2)? {
        switch shape {
        case .circle(let c, let r):
            let d = p - c
            let distance = d.length
            guard distance < r else { return nil }
            let normal = distance > 1e-9 ? d / distance : Vector2(1, 0)
            return (r - distance, normal, c + normal * r)

        case .capsule(let a, let b, let r):
            let ab = b - a
            let lengthSquared = ab.lengthSquared
            let t = lengthSquared > 1e-18 ? Swift.min(1, Swift.max(0, (p - a).dot(ab) / lengthSquared)) : 0
            let q = a + ab * t
            let d = p - q
            let distance = d.length
            guard distance < r else { return nil }
            let normal = distance > 1e-9 ? d / distance
                : (lengthSquared > 1e-18 ? ab.perpendicular.normalized : Vector2(1, 0))
            return (r - distance, normal, q + normal * r)

        case .polygon(let vertices, let normals, let radius):
            guard vertices.count >= 3 else { return nil }
            // The side the point is least inside of is the way out of the
            // core polygon; a rounded polygon adds its radius to that.
            var deepest = -Double.infinity
            var side = 0
            for i in vertices.indices {
                let s = normals[i].dot(p - vertices[i])
                if s > deepest { deepest = s; side = i }
            }
            if deepest < 0 {
                let depth = radius - deepest
                return (depth, normals[side], p + normals[side] * depth)
            }
            guard radius > 0 else { return nil }
            // Outside the core but maybe within its rounding: the nearest
            // point of the core's edges decides.
            var nearest = p
            var nearestSquared = Double.infinity
            for i in vertices.indices {
                let a = vertices[i], b = vertices[(i + 1) % vertices.count]
                let ab = b - a
                let lengthSquared = ab.lengthSquared
                let t = lengthSquared > 1e-18 ? Swift.min(1, Swift.max(0, (p - a).dot(ab) / lengthSquared)) : 0
                let q = a + ab * t
                let squared = (p - q).lengthSquared
                if squared < nearestSquared { nearestSquared = squared; nearest = q }
            }
            let distance = nearestSquared.squareRoot()
            guard distance < radius, distance > 1e-9 else { return nil }
            let normal = (p - nearest) / distance
            return (radius - distance, normal, nearest + normal * radius)
        }
    }

    /// The polygon shapes' corners in the world under the corrected pose,
    /// which are tested against the soft outlines the other way round.
    func corners(under pose: (center: Vector2, cosine: Double, sine: Double)) -> [(point: Vector2, friction: Double)] {
        var result: [(point: Vector2, friction: Double)] = []
        for (shape, friction) in shapes {
            guard case .polygon(let vertices, _, let radius) = shape, radius == 0 else { continue }
            for v in vertices { result.append((world(v, under: pose), friction)) }
        }
        return result
    }
}

extension World {

    /// Read every rigid body into a proxy for this step, when the world has
    /// soft bodies for them to meet. A segment (the walls) has no inside and
    /// is left out; the bounds already hold a soft particle.
    func beginRigidContacts(step h: Double) {
        rigidProxies.removeAll(keepingCapacity: true)
        guard !softBodies.isEmpty, !bodies.isEmpty else { return }
        let upm = unitsPerMeter
        var shapeIds = [b2ShapeId](repeating: b2ShapeId(), count: 8)
        for body in bodies {
            let count = Int(b2Body_GetShapes(body.id, &shapeIds, 8))
            var shapes: [(shape: RigidProxy.Shape, friction: Double)] = []
            let localCenter = points(from: b2Body_GetLocalCenterOfMass(body.id))
            var reach = 0.0
            for shapeId in shapeIds.prefix(count) {
                let friction = Double(b2Shape_GetFriction(shapeId))
                switch b2Shape_GetType(shapeId) {
                case b2_circleShape:
                    let circle = b2Shape_GetCircle(shapeId)
                    let center = points(from: circle.center), radius = Double(circle.radius) * upm
                    shapes.append((.circle(center: center, radius: radius), friction))
                    reach = Swift.max(reach, (center - localCenter).length + radius)
                case b2_capsuleShape:
                    let capsule = b2Shape_GetCapsule(shapeId)
                    let a = points(from: capsule.center1), b = points(from: capsule.center2)
                    let radius = Double(capsule.radius) * upm
                    shapes.append((.capsule(a: a, b: b, radius: radius), friction))
                    reach = Swift.max(reach, (a - localCenter).length + radius, (b - localCenter).length + radius)
                case b2_polygonShape:
                    let polygon = b2Shape_GetPolygon(shapeId)
                    let n = Int(polygon.count)
                    let radius = Double(polygon.radius) * upm
                    var vertices: [Vector2] = [], normals: [Vector2] = []
                    withUnsafeBytes(of: polygon.vertices) { raw in
                        let buffer = raw.bindMemory(to: b2Vec2.self)
                        for i in 0 ..< n { vertices.append(points(from: buffer[i])) }
                    }
                    withUnsafeBytes(of: polygon.normals) { raw in
                        let buffer = raw.bindMemory(to: b2Vec2.self)
                        for i in 0 ..< n { normals.append(Vector2(Double(buffer[i].x), Double(buffer[i].y))) }
                    }
                    shapes.append((.polygon(vertices: vertices, normals: normals, radius: radius), friction))
                    for v in vertices { reach = Swift.max(reach, (v - localCenter).length + radius) }
                default:
                    continue
                }
            }
            guard !shapes.isEmpty else { continue }
            let dynamic = body.kind == .dynamic
            let mass = Double(b2Body_GetMass(body.id))
            let inertia = Double(b2Body_GetRotationalInertia(body.id)) * upm * upm
            let velocity = points(from: b2Body_GetLinearVelocity(body.id))
            let spin = Double(b2Body_GetAngularVelocity(body.id))
            let center = points(from: b2Body_GetWorldCenterOfMass(body.id)) + velocity * h
            let angle = Double(b2Rot_GetAngle(b2Body_GetRotation(body.id))) + spin * h
            rigidProxies.append(RigidProxy(
                body: body, shapes: shapes, localCenter: localCenter, center: center, angle: angle,
                velocity: velocity, spin: spin,
                inverseMass: dynamic && mass > 0 ? 1 / mass : 0,
                inverseInertia: dynamic && inertia > 0 ? 1 / inertia : 0,
                reach: reach))
        }
    }

    /// One pass of every soft particle out of every rigid body it has
    /// entered, and every rigid corner out of every soft outline it has
    /// entered, each body handed its share of the correction. Walked in the
    /// order bodies and soft bodies were added, so a seeded run repeats.
    func solveRigidContacts(step h: Double) {
        for n in rigidProxies.indices {
            let box = rigidProxies[n].box
            for body in softBodies {
                body.refreshBoxes()
                for k in body.islands.indices where body.boxes[k].overlaps(box) {
                    for r in body.islands[k] {
                        for i in body.rings[r] where box.holds(body.particles[i].position, margin: 0) {
                            push(body.particles[i], of: body, outOf: &rigidProxies[n], step: h)
                        }
                    }
                    pushCorners(of: &rigidProxies[n], outOf: body, island: k, step: h)
                }
            }
        }
    }

    /// Move `particle` out of the body by its share of the depth, the body
    /// taking the rest as a pending shift and turn, then rub.
    private func push(_ particle: Particle, of soft: SoftBody, outOf proxy: inout RigidProxy, step h: Double) {
        let pose = proxy.pose
        guard let hit = proxy.penetration(ofLocal: proxy.local(particle.position, under: pose)) else { return }
        let normal = proxy.direction(hit.normal, under: pose)
        let point = proxy.world(hit.point, under: pose)
        let arm = point - pose.center
        let wp = particle.isPinned ? 0 : particle.inverseMass
        let lever = arm.cross(normal)
        let wb = proxy.inverseMass + lever * lever * proxy.inverseInertia
        let denominator = wp + wb
        guard denominator > 1e-18 else { return }
        let lambda = hit.depth / denominator
        particle.position += normal * (lambda * wp)
        proxy.shift -= normal * (lambda * proxy.inverseMass)
        proxy.turn -= lever * lambda * proxy.inverseInertia
        proxy.impulse -= normal * (lambda / h)
        proxy.angularImpulse -= lever * lambda / h

        // The rub (Macklin, Müller, Chentanez and Kim 2014): the part of the
        // step's relative motion along the surface comes out, up to the pair's
        // friction times the depth just corrected.
        let friction = (soft.friction * hit.friction).squareRoot()
        guard friction > 0 else { return }
        let relative = (particle.position - particle.previous) - proxy.displacement(at: arm, over: h)
        let along = relative - normal * relative.dot(normal)
        let slide = along.length
        guard slide > 1e-12 else { return }
        let tangent = along / slide
        let twist = arm.cross(tangent)
        let wbt = proxy.inverseMass + twist * twist * proxy.inverseInertia
        let rub = Swift.min(slide, friction * hit.depth) / (wp + wbt)
        particle.position -= tangent * (rub * wp)
        proxy.shift += tangent * (rub * proxy.inverseMass)
        proxy.turn += twist * rub * proxy.inverseInertia
        proxy.impulse += tangent * (rub / h)
        proxy.angularImpulse += twist * rub / h
    }

    /// Move each corner of the body's polygons out of island `k` of `soft`:
    /// the edge it is behind takes its share of the move and the body the
    /// rest, so a crate's corner cannot sink between two particles of a
    /// jelly's outline.
    private func pushCorners(of proxy: inout RigidProxy, outOf soft: SoftBody, island k: Int, step h: Double) {
        let pose = proxy.pose
        for corner in proxy.corners(under: pose) {
            let p = corner.point
            guard soft.boxes[k].holds(p, margin: 0), soft.island(k, contains: p) else { continue }
            let near = soft.nearestEdge(to: p, on: soft.islands[k])
            guard near.edge >= 0, near.distance > 1e-9 else { continue }
            let normal = (near.point - p) / near.distance
            let a = soft.particles[near.edge], b = soft.particles[soft.next[near.edge]], t = near.t
            let wa = a.isPinned ? 0 : a.inverseMass, wb = b.isPinned ? 0 : b.inverseMass
            let arm = p - pose.center
            let lever = arm.cross(normal)
            let wBody = proxy.inverseMass + lever * lever * proxy.inverseInertia
            let denominator = wBody + (1 - t) * (1 - t) * wa + t * t * wb
            guard denominator > 1e-18 else { continue }
            let lambda = near.distance / denominator
            a.position -= normal * (lambda * wa * (1 - t))
            b.position -= normal * (lambda * wb * t)
            proxy.shift += normal * (lambda * proxy.inverseMass)
            proxy.turn += lever * lambda * proxy.inverseInertia
            proxy.impulse += normal * (lambda / h)
            proxy.angularImpulse += lever * lambda / h

            let friction = (soft.friction * corner.friction).squareRoot()
            guard friction > 0 else { continue }
            let edgeMove = (a.position - a.previous) * (1 - t) + (b.position - b.previous) * t
            let relative = proxy.displacement(at: arm, over: h) - edgeMove
            let along = relative - normal * relative.dot(normal)
            let slide = along.length
            guard slide > 1e-12 else { continue }
            let tangent = along / slide
            let twist = arm.cross(tangent)
            let wBodyT = proxy.inverseMass + twist * twist * proxy.inverseInertia
            let rub = Swift.min(slide, friction * near.distance)
                / (wBodyT + (1 - t) * (1 - t) * wa + t * t * wb)
            a.position += tangent * (rub * wa * (1 - t))
            b.position += tangent * (rub * wb * t)
            proxy.shift -= tangent * (rub * proxy.inverseMass)
            proxy.turn -= twist * rub * proxy.inverseInertia
            proxy.impulse -= tangent * (rub / h)
            proxy.angularImpulse -= twist * rub / h
        }
    }

    /// Hand every body the impulse its pending motion is, equal and opposite
    /// to what the particles took, so momentum crosses the contact whole. A
    /// body given one is woken; one given none is left to sleep.
    func endRigidContacts() {
        let upm = unitsPerMeter
        for proxy in rigidProxies where proxy.moves {
            if proxy.impulse != .zero {
                b2Body_ApplyLinearImpulseToCenter(proxy.body.id, meters(from: proxy.impulse), true)
            }
            if proxy.angularImpulse != 0 {
                b2Body_ApplyAngularImpulse(proxy.body.id, Float(proxy.angularImpulse / (upm * upm)), true)
            }
        }
        rigidProxies.removeAll(keepingCapacity: true)
    }
}
