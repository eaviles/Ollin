import Foundation
import Ollin
internal import CJolt

/// One thing a world query found: what it touched, where, and how far along.
/// The shared answer for every question a sketch asks a `World3D` between
/// steps, the way `Contact3D` is the shared answer for what the solver noticed
/// during one.
///
/// ```swift
/// if let hit = world.raycast(from: eye, to: eye + look * 40) {
///     drawSphere(at: hit.point, radius: 0.1)   // where the look lands
/// }
/// ```
public struct Hit3D {

    /// The body the query ran into.
    public let body: Body3D

    /// Where it touched, in world units: the point on the body's surface.
    public let point: Vector3

    /// The body's outward surface normal there (unit length), which is what a
    /// bounce, a decal, or a wall slide is built from.
    public let normal: Vector3

    /// How far along the query the touch is, in world units: the distance from
    /// a ray's start, or how far a swept shape travelled before it landed. `0`
    /// for a sweep that was already touching when it set off.
    public let distance: Double
}

// Asking the world what is there. The solver can already answer these while it
// is between steps, and mouse picking has always been built on the first of
// them; this is the same machinery pointed at whatever a sketch wants to know.
extension World3D {

    // MARK: Rays

    /// The nearest body along the segment from `origin` to `end`, or `nil` if
    /// nothing is in the way. The line-of-sight question, and the ground probe:
    ///
    /// ```swift
    /// // can the sentry see the walker?
    /// let seen = world.raycast(from: sentry, to: walker.position)?.body === walker.body
    ///
    /// // how far is the floor under this point?
    /// let drop = world.raycast(from: p, to: p - Vector3(0, 20, 0))?.distance
    /// ```
    ///
    /// - Parameters:
    ///   - ignoring: bodies the ray looks straight through, usually the one it
    ///     started inside.
    ///   - includingSensors: report detector volumes too. A sensor is a region
    ///     to be inside rather than a surface to hit, so a ray passes through
    ///     one by default.
    ///   - as: ask as a body of this collision group would: the ray looks
    ///     straight through whatever that group passes through. `.default`
    ///     sees the whole world.
    public func raycast(from origin: Vector3, to end: Vector3,
                        ignoring: [Body3D] = [],
                        includingSensors: Bool = false,
                        as group: CollisionGroup = .default) -> Hit3D? {
        castRay(from: origin, to: end, ignoring: ignoring,
                includingSensors: includingSensors, group: group,
                allHits: false).first
    }

    /// Every body along the segment from `origin` to `end`, nearest first: what
    /// a shot passes through rather than what stops it.
    ///
    /// ```swift
    /// for hit in world.raycastAll(from: muzzle, to: muzzle + aim * 30) {
    ///     hit.body.applyImpulse(aim * 4)
    /// }
    /// ```
    public func raycastAll(from origin: Vector3, to end: Vector3,
                           ignoring: [Body3D] = [],
                           includingSensors: Bool = false,
                           as group: CollisionGroup = .default) -> [Hit3D] {
        castRay(from: origin, to: end, ignoring: ignoring,
                includingSensors: includingSensors, group: group, allHits: true)
    }

    // MARK: Sweeps

    /// The first body a `collider` runs into as it slides from `origin` to
    /// `end` without turning: a ray with thickness. It answers what a ray
    /// cannot, whether something *fits*, so it is the probe for a hovering
    /// drone's clearance, a camera that must not end up inside a wall, or a
    /// step a character is about to take.
    ///
    /// ```swift
    /// // ride 1.5 units above whatever passes below, crates included
    /// let below = world.sweep(.sphere(radius: 0.4), from: drone,
    ///                         to: drone - Vector3(0, 8, 0))
    /// let height = (below?.point.y ?? 0) + 1.5
    /// ```
    ///
    /// `distance` on the hit is how far the shape travelled, so its centre
    /// stopped at `origin + (end - origin).normalized * distance`. Mesh and
    /// height-field colliders describe scenery rather than a probe and cannot
    /// be swept.
    public func sweep(_ collider: Collider3D, from origin: Vector3, to end: Vector3,
                      rotated angle: Double = 0, axis: Vector3 = .unitY,
                      ignoring: [Body3D] = [],
                      includingSensors: Bool = false,
                      as group: CollisionGroup = .default) -> Hit3D? {
        castShape(collider, from: origin, to: end, rotated: angle, axis: axis,
                  ignoring: ignoring, includingSensors: includingSensors,
                  group: group, allHits: false).first
    }

    /// Every body a swept `collider` touches on its way from `origin` to `end`,
    /// nearest first.
    public func sweepAll(_ collider: Collider3D, from origin: Vector3, to end: Vector3,
                         rotated angle: Double = 0, axis: Vector3 = .unitY,
                         ignoring: [Body3D] = [],
                         includingSensors: Bool = false,
                         as group: CollisionGroup = .default) -> [Hit3D] {
        castShape(collider, from: origin, to: end, rotated: angle, axis: axis,
                  ignoring: ignoring, includingSensors: includingSensors,
                  group: group, allHits: true)
    }

    // MARK: Overlaps

    /// The bodies overlapping `collider` placed at `position`: what is inside a
    /// region right now, without building a sensor body to hold it. A blast
    /// radius is one call:
    ///
    /// ```swift
    /// for body in world.bodiesOverlapping(.sphere(radius: 4), at: blast) {
    ///     body.applyImpulse((body.position - blast).normalized * 12)
    /// }
    /// ```
    ///
    /// The list comes back in a stable order, one entry per body however many
    /// of its parts are inside. A sensor body added with
    /// `addBody(_:at:isSensor:)` answers the same question *continuously*
    /// through `touching`; this answers it for one frame, anywhere, with a
    /// shape that need not exist.
    public func bodiesOverlapping(_ collider: Collider3D, at position: Vector3,
                                  rotated angle: Double = 0, axis: Vector3 = .unitY,
                                  ignoring: [Body3D] = [],
                                  includingSensors: Bool = false,
                                  as group: CollisionGroup = .default) -> [Body3D] {
        guard let arena = probeArena(for: collider) else { return [] }
        var shape = arena.shape
        return withExtendedLifetime(arena.storage) {
            collectBodies(ignoring: ignoring, includingSensors: includingSensors,
                          group: group) {
                filter, out, capacity in
                withUnsafePointer(to: &shape) { shapePointer in
                    withFloats3(meters(from: position)) { positionPointer in
                        withFloats4(quaternion(angle: angle, axis: axis)) { rotationPointer in
                            cjolt_world_overlap_shape(handle, shapePointer,
                                                      positionPointer, rotationPointer,
                                                      filter, out, capacity)
                        }
                    }
                }
            }
        }
    }

    /// The bodies a world point is inside, in a stable order. The exact form of
    /// the overlap question: am I in the water, in the goal, in the room?
    ///
    /// ```swift
    /// let scored = world.bodiesContaining(ball.position).contains { $0 === goal }
    /// ```
    public func bodiesContaining(_ point: Vector3, ignoring: [Body3D] = [],
                                 includingSensors: Bool = false,
                                 as group: CollisionGroup = .default) -> [Body3D] {
        collectBodies(ignoring: ignoring, includingSensors: includingSensors,
                      group: group) {
            filter, out, capacity in
            withFloats3(meters(from: point)) { pointPointer in
                cjolt_world_overlap_point(handle, pointPointer, filter, out, capacity)
            }
        }
    }

    // MARK: Picking

    /// The nearest thing along a world-space segment with soft bodies included,
    /// named by solver handle: what the mouse pick paths ask, where a public
    /// query looks straight through a cloth it has no `Body3D` to describe.
    func pick(from origin: Vector3, to end: Vector3)
        -> (id: CJoltBodyID, point: Vector3)? {
        let along = end - origin
        guard along.lengthSquared > 0 else { return nil }
        var raw = CJoltQueryHit()
        let found = withUnsafeMutablePointer(to: &raw) { out in
            withQueryFilter(ignoring: [], includingSensors: false,
                            includingSoftBodies: true) { filter in
                withFloats3(meters(from: origin)) { originPointer in
                    withFloats3(meters(from: along)) { alongPointer in
                        cjolt_world_cast_ray(handle, originPointer, alongPointer,
                                             filter, false, out, 1)
                    }
                }
            }
        }
        guard found > 0 else { return nil }
        return (raw.body, units(from: raw.point.0, raw.point.1, raw.point.2))
    }

    // MARK: Running one

    /// The shared ray path. `allHits` false stops at the nearest, which lets the
    /// solver abandon anything further away as it goes.
    private func castRay(from origin: Vector3, to end: Vector3,
                         ignoring: [Body3D], includingSensors: Bool,
                         group: CollisionGroup, allHits: Bool) -> [Hit3D] {
        let along = end - origin
        guard along.lengthSquared > 0 else { return [] }
        return collectHits(ignoring: ignoring, includingSensors: includingSensors,
                           group: group) {
            filter, out, capacity in
            withFloats3(meters(from: origin)) { originPointer in
                withFloats3(meters(from: along)) { alongPointer in
                    cjolt_world_cast_ray(handle, originPointer, alongPointer, filter,
                                         allHits, out, capacity)
                }
            }
        }
    }

    /// The shared sweep path.
    private func castShape(_ collider: Collider3D, from origin: Vector3,
                           to end: Vector3, rotated angle: Double, axis: Vector3,
                           ignoring: [Body3D], includingSensors: Bool,
                           group: CollisionGroup, allHits: Bool) -> [Hit3D] {
        let along = end - origin
        guard along.lengthSquared > 0, let arena = probeArena(for: collider) else {
            return []
        }
        var shape = arena.shape
        return withExtendedLifetime(arena.storage) {
            collectHits(ignoring: ignoring, includingSensors: includingSensors,
                        group: group) {
                filter, out, capacity in
                withUnsafePointer(to: &shape) { shapePointer in
                    withFloats3(meters(from: origin)) { originPointer in
                        withFloats4(quaternion(angle: angle, axis: axis)) { rotationPointer in
                            withFloats3(meters(from: along)) { alongPointer in
                                cjolt_world_cast_shape(handle, shapePointer,
                                                       originPointer, rotationPointer,
                                                       alongPointer, filter, allHits,
                                                       out, capacity)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The shape description a sweep or an overlap asks with, plus the arena
    /// holding its flat data (a hull's points, a compound's children) for as
    /// long as the call needs it. `nil` for a collider the narrow phase can
    /// only treat as scenery.
    private func probeArena(for collider: Collider3D)
        -> (shape: CJoltShapeDesc, storage: ShapeDescArena)? {
        guard !collider.mustBeStatic else {
            noteOnce("a mesh or heightfield collider describes scenery, not a "
                     + "probe: sweep or overlap with a hull, a compound, or a "
                     + "primitive shape instead")
            return nil
        }
        let storage = ShapeDescArena()
        return (collider.shapeDesc(unitsPerMeter: unitsPerMeter, density: 1,
                                   arena: storage), storage)
    }

    /// Runs a hit-returning query into a buffer, growing it once if the world
    /// held more than the first guess. The C side returns how many it *found*
    /// rather than how many it wrote, which is what makes the retry exact.
    private func collectHits(
        ignoring: [Body3D], includingSensors: Bool, group: CollisionGroup,
        _ run: (UnsafePointer<CJoltQueryFilter>, UnsafeMutablePointer<CJoltQueryHit>,
                Int32) -> Int32
    ) -> [Hit3D] {
        var capacity = 16
        var hits: [Hit3D] = []
        for _ in 0 ..< 2 {
            var buffer = [CJoltQueryHit](repeating: CJoltQueryHit(), count: capacity)
            let found = buffer.withUnsafeMutableBufferPointer { out in
                Int(withQueryFilter(ignoring: ignoring,
                                    includingSensors: includingSensors,
                                    group: group) { filter in
                    run(filter, out.baseAddress!, Int32(capacity))
                })
            }
            hits = buffer.prefix(min(found, capacity)).compactMap(hit(from:))
            if found <= capacity { break }
            capacity = found
        }
        return hits
    }

    /// Runs a body-returning query, with the same grow-once rule.
    private func collectBodies(
        ignoring: [Body3D], includingSensors: Bool, group: CollisionGroup,
        _ run: (UnsafePointer<CJoltQueryFilter>, UnsafeMutablePointer<CJoltBodyID>,
                Int32) -> Int32
    ) -> [Body3D] {
        var capacity = 16
        var matched: [Body3D] = []
        for _ in 0 ..< 2 {
            var buffer = [CJoltBodyID](repeating: CJOLT_BODY_INVALID, count: capacity)
            let found = buffer.withUnsafeMutableBufferPointer { out in
                Int(withQueryFilter(ignoring: ignoring,
                                    includingSensors: includingSensors,
                                    group: group) { filter in
                    run(filter, out.baseAddress!, Int32(capacity))
                })
            }
            matched = buffer.prefix(min(found, capacity)).compactMap { bodyByID[$0] }
            if found <= capacity { break }
            capacity = found
        }
        return matched
    }

    /// One C hit as the sketch's own value. Dropped if the world no longer
    /// knows the body it names.
    private func hit(from raw: CJoltQueryHit) -> Hit3D? {
        guard let body = bodyByID[raw.body] else { return nil }
        return Hit3D(body: body,
                     point: units(from: raw.point.0, raw.point.1, raw.point.2),
                     normal: Vector3(Double(raw.normal.0), Double(raw.normal.1),
                                     Double(raw.normal.2)),
                     distance: Double(raw.distance) * unitsPerMeter)
    }

    /// Builds the C filter over the ignore list for the span of a call. Every
    /// query travels through one struct rather than a growing argument list, so
    /// a further way to narrow one later is a field rather than a new parameter
    /// on each of them.
    func withQueryFilter<R>(ignoring: [Body3D], includingSensors: Bool,
                            includingSoftBodies: Bool = false,
                            group: CollisionGroup = .default,
                            _ body: (UnsafePointer<CJoltQueryFilter>) -> R) -> R {
        let ids = ignoring.map(\.id)
        return ids.withUnsafeBufferPointer { ignored in
            var filter = CJoltQueryFilter()
            filter.ignoreBodies = ignored.baseAddress
            filter.ignoreCount = Int32(ignored.count)
            filter.includeSensors = includingSensors
            filter.includeSoftBodies = includingSoftBodies
            filter.group = groupIndex(group)
            return withUnsafePointer(to: &filter) { body($0) }
        }
    }

    /// A rotation as the solver's `(x, y, z, w)`.
    private func quaternion(angle: Double, axis: Vector3) -> (Float, Float, Float, Float) {
        let unit = axis.normalized
        let half = angle / 2
        let s = sin(half)
        return (Float(unit.x * s), Float(unit.y * s), Float(unit.z * s),
                Float(cos(half)))
    }
}
