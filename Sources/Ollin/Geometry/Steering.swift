import Foundation

/// A steering creature: a point with a velocity that moves by composable
/// steering forces (the classic autonomous-steering model behind game and
/// crowd movement, and the single-creature side of `Boids`).
///
/// Every behavior builds on one move: aim at full speed toward what you want,
/// subtract the velocity you already have, and cap the turn at `maxForce`.
/// Each behavior method (`seek`, `flee`, `arrive`, `pursue`, `evade`, `wander`,
/// `follow`, `separate`, `contain`) returns that force, so you weight and sum
/// them however the creature should feel, then `applyForce(_:)` and `step()`.
///
/// ```swift
/// let creature = Vehicle(at: center, seed: 1)
///
/// override func draw() {
///     creature.applyForce(creature.wander())
///     creature.applyForce(creature.contain(in: bounds) * 1.5)
///     creature.step()
///     drawVehicle(creature)
/// }
/// ```
///
/// A vehicle is deterministic given its `seed` (only `wander` draws random
/// numbers), so a seeded creature retraces the same path every run. Give each
/// creature its own seed or they wander in lockstep.
public final class Vehicle {
    /// Where the creature is.
    public var position: Vector2
    /// Where it's going (length is speed, direction is heading).
    public var velocity: Vector2
    /// The top speed it may travel.
    public var maxSpeed: Double
    /// The strongest steering force it may apply per step (lower turns are
    /// smoother and more sluggish, higher ones snap).
    public var maxForce: Double

    private var acceleration = Vector2.zero
    private var wanderAngle = 0.0
    private var rng: SplitMix64

    /// A creature at `position`, still by default.
    public init(at position: Vector2, velocity: Vector2 = .zero,
                maxSpeed: Double = 3, maxForce: Double = 0.12, seed: UInt64 = 0) {
        self.position = position
        self.velocity = velocity
        self.maxSpeed = maxSpeed
        self.maxForce = maxForce
        self.rng = SplitMix64(seed: seed)
    }

    /// The heading (radians), from the velocity.
    public var heading: Double { velocity.angle }

    // MARK: - The steering move

    /// The steering force toward a desired direction: aim at `maxSpeed` along
    /// `direction`, subtract the current velocity, cap the turn at `maxForce`.
    /// Every behavior below is this move with a different idea of "desired".
    public func steer(toward direction: Vector2) -> Vector2 {
        guard direction.lengthSquared > 1e-12 else { return .zero }
        let desired = direction.normalized * maxSpeed
        return (desired - velocity).limited(to: maxForce)
    }

    // MARK: - Behaviors

    /// Steer toward `target` at full speed.
    public func seek(_ target: Vector2) -> Vector2 {
        steer(toward: target - position)
    }

    /// Steer away from `target` at full speed.
    public func flee(_ target: Vector2) -> Vector2 {
        steer(toward: position - target)
    }

    /// Steer toward `target`, slowing to a stop as it gets close: the desired
    /// speed ramps down linearly inside `slowingRadius`, so the creature eases
    /// in and settles instead of overshooting and orbiting.
    public func arrive(at target: Vector2, slowingRadius: Double = 100) -> Vector2 {
        let offset = target - position
        let distance = offset.length
        guard distance > 1e-9 else { return (-velocity).limited(to: maxForce) }
        let ramped = slowingRadius > 0 ? maxSpeed * (distance / slowingRadius) : maxSpeed
        let desired = offset * (Swift.min(ramped, maxSpeed) / distance)
        return (desired - velocity).limited(to: maxForce)
    }

    /// Steer toward where a moving target *will* be: seek its position
    /// projected ahead by the time it would take to get there.
    public func pursue(_ targetPosition: Vector2, velocity targetVelocity: Vector2) -> Vector2 {
        seek(predicted(targetPosition, targetVelocity))
    }

    /// Steer toward where `other` will be.
    public func pursue(_ other: Vehicle) -> Vector2 {
        pursue(other.position, velocity: other.velocity)
    }

    /// Steer away from where a moving threat *will* be.
    public func evade(_ targetPosition: Vector2, velocity targetVelocity: Vector2) -> Vector2 {
        flee(predicted(targetPosition, targetVelocity))
    }

    /// Steer away from where `other` will be.
    public func evade(_ other: Vehicle) -> Vector2 {
        evade(other.position, velocity: other.velocity)
    }

    private func predicted(_ targetPosition: Vector2, _ targetVelocity: Vector2) -> Vector2 {
        let lead = position.distance(to: targetPosition) / Swift.max(maxSpeed, 1e-9)
        return targetPosition + targetVelocity * lead
    }

    /// Roam with lifelike aimlessness: seek a point on a circle projected
    /// `distance` ahead of the creature, and jitter where on the circle the
    /// point sits by up to `jitter` radians each step. Small jitter drifts in
    /// long arcs; large jitter is twitchy. The one behavior that draws random
    /// numbers (from the vehicle's seed).
    public func wander(radius: Double = 25, distance: Double = 80, jitter: Double = 0.25) -> Vector2 {
        // A zero-width random range consumes no roll, so keep determinism by
        // rolling a unit and scaling it by the jitter.
        wanderAngle += (Double.random(in: 0 ..< 1, using: &rng) * 2 - 1) * jitter
        let center = position + Vector2(angle: heading) * distance
        let target = center + Vector2(angle: heading + wanderAngle) * radius
        return seek(target)
    }

    /// Steer along a flow field: the desired direction is the field's
    /// direction at the creature's position.
    public func follow(_ field: FlowField) -> Vector2 {
        steer(toward: field.direction(at: position))
    }

    /// Steer to stay on a path (a polyline). The creature predicts its
    /// position `lookAhead` ahead, and if that prediction is more than
    /// `radius` off the path, seeks a point further along it, so it cuts back
    /// toward the path and keeps moving down it. Inside `radius` no force is
    /// returned: the path is a corridor, not a rail. Pass `closed: true` for a
    /// loop.
    public func follow(path points: [Vector2], radius: Double = 20,
                       lookAhead: Double = 50, closed: Bool = false) -> Vector2 {
        guard points.count >= 2 else { return .zero }
        let ahead = velocity.lengthSquared > 1e-12 ? velocity.normalized : Vector2(angle: heading)
        let predicted = position + ahead * lookAhead

        // The closest point on the path to the prediction, and how far along
        // the path it sits, walking every segment (the closing one too, for a
        // loop).
        var bestDistance2 = Double.infinity
        var bestAlong = 0.0
        var bestPoint = points[0]
        var walked = 0.0
        let segmentCount = closed ? points.count : points.count - 1
        for i in 0 ..< segmentCount {
            let a = points[i], b = points[(i + 1) % points.count]
            let ab = b - a
            let length2 = ab.lengthSquared
            let t = length2 > 1e-12 ? Swift.max(0, Swift.min(1, (predicted - a).dot(ab) / length2)) : 0
            let onSegment = a + ab * t
            let d2 = predicted.distanceSquared(to: onSegment)
            let segmentLength = ab.length
            if d2 < bestDistance2 {
                bestDistance2 = d2
                bestPoint = onSegment
                bestAlong = walked + segmentLength * t
            }
            walked += segmentLength
        }
        guard bestDistance2 > radius * radius else { return .zero }

        // Aim ahead of the projection so the creature rejoins the path
        // downstream instead of cutting straight across it.
        let target = point(onPath: points, at: bestAlong + Swift.max(lookAhead, 1), closed: closed,
                           totalLength: walked, fallback: bestPoint)
        return seek(target)
    }

    /// The point `along` arc length down the polyline (wrapping for a loop,
    /// clamping to the last point for an open path).
    private func point(onPath points: [Vector2], at along: Double, closed: Bool,
                       totalLength: Double, fallback: Vector2) -> Vector2 {
        guard totalLength > 1e-9 else { return fallback }
        var remaining = closed ? along.truncatingRemainder(dividingBy: totalLength) : along
        if remaining < 0 { remaining += totalLength }
        let segmentCount = closed ? points.count : points.count - 1
        for i in 0 ..< segmentCount {
            let a = points[i], b = points[(i + 1) % points.count]
            let length = a.distance(to: b)
            if remaining <= length {
                return length > 1e-12 ? a.lerp(to: b, remaining / length) : a
            }
            remaining -= length
        }
        return closed ? points[0] : points[points.count - 1]
    }

    /// Steer away from crowding: push from every other creature within
    /// `radius`, weighted stronger the closer it is. The one rule of the
    /// flocking trio that's useful alone (for a whole flock, use `Boids`).
    public func separate(from others: [Vehicle], radius: Double = 25) -> Vector2 {
        let radius2 = radius * radius
        var push = Vector2.zero
        var crowding = 0
        for other in others where other !== self {
            let offset = position - other.position
            let d2 = offset.lengthSquared
            if d2 < radius2, d2 > 1e-9 {
                push = push + offset * (1 / d2)
                crowding += 1
            }
        }
        return crowding > 0 ? steer(toward: push) : .zero
    }

    /// A force that pushes back inside `bounds` as the creature nears an edge
    /// (within `margin`), the same edge behavior a flock uses.
    public func contain(in bounds: Rectangle, margin: Double = 60) -> Vector2 {
        let push = maxForce * 1.8
        var dx = 0.0, dy = 0.0
        if position.x < bounds.x + margin { dx += push }
        if position.x > bounds.x + bounds.width - margin { dx -= push }
        if position.y < bounds.y + margin { dy += push }
        if position.y > bounds.y + bounds.height - margin { dy -= push }
        return Vector2(dx, dy)
    }

    // MARK: - Moving

    /// Accumulate a steering force for this step. Weight a behavior by scaling
    /// its force: `applyForce(creature.seek(mouse) * 2)`.
    public func applyForce(_ force: Vector2) {
        acceleration = acceleration + force
    }

    /// Move one step: add the accumulated forces to the velocity (capped at
    /// `maxSpeed`), move by the velocity, and clear the forces.
    public func step() {
        velocity = (velocity + acceleration).limited(to: maxSpeed)
        position = position + velocity
        acceleration = .zero
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Draw `vehicle` as a triangle of the given `size` pointing along its
    /// heading, filled with the current `fill`.
    func drawVehicle(_ vehicle: Vehicle, size: Double = 10) {
        let p = vehicle.position
        let a = vehicle.heading
        drawTriangle(Vector2(p.x + cos(a) * size, p.y + sin(a) * size),
                     Vector2(p.x + cos(a + 2.5) * size * 0.7, p.y + sin(a + 2.5) * size * 0.7),
                     Vector2(p.x + cos(a - 2.5) * size * 0.7, p.y + sin(a - 2.5) * size * 0.7))
    }
}
