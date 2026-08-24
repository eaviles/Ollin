import Foundation

/// A ball loose in a room, bouncing forever, and the line it draws.
///
/// One rule, applied over and over: go straight until you meet the wall, then
/// leave at the angle you arrived at. Everything interesting comes from the
/// shape of the room. A circle draws a rosette of chords that never crosses a
/// smaller circle in the middle. An ellipse draws two entirely different
/// pictures depending on whether the ball passes between the foci. A stadium,
/// which is a circle cut in half and pulled apart, draws neither: it fills the
/// room, and two balls sent off a hair apart end up nowhere near each other.
///
/// ```swift
/// let room = Billiard(.circle(Circle(center: middle, radius: 380)))
/// drawPolyline(room.path(from: start, heading: 0.7, bounces: 400))
/// ```
///
/// The path comes back as the points it turns at, so it is ordinary geometry:
/// stroke it, fade it along its length, or send it to a pen.
///
/// Written from the published billiard results (see `ATTRIBUTION.md`).
public struct Billiard: Sendable {
    /// The room.
    public enum Table: Sendable, Equatable {
        /// A circle. Every chord of a path stays clear of one smaller circle in
        /// the middle, and every chord is the same length as every other.
        case circle(Circle)

        /// An ellipse, by its center and its two radii. A path that passes
        /// between the foci keeps passing between them; one that does not,
        /// never does.
        case ellipse(center: Vector2, radii: Vector2)

        /// Any closed outline, straight-sided. Corners are the one place a path
        /// has no answer, and it stops there.
        case polygon(Contour)

        /// A circle cut through the middle and pulled apart by `straight`: two
        /// flats joined by two half-circles. The shape that turns an orderly
        /// room into a disorderly one.
        case stadium(center: Vector2, straight: Double, radius: Double)
    }

    /// The room the ball is in.
    public var table: Table

    /// Circles standing in the room that the ball also bounces off. One of
    /// these in the middle of a square is the other classic way to make an
    /// orderly room disorderly.
    public var obstacles: [Circle]

    public init(_ table: Table, obstacles: [Circle] = []) {
        self.table = table
        self.obstacles = obstacles
    }
}

// MARK: - Running a ball

public extension Billiard {
    /// The path of a ball let go at `start` in the direction `heading` faces,
    /// as the points it turns at, `start` first.
    ///
    /// It stops early where there is no answer: a corner it arrives exactly at,
    /// a start outside the room, or a direction that finds no wall.
    func path(from start: Vector2, heading: Double, bounces: Int) -> [Vector2] {
        path(from: start, direction: Vector2(cos(heading), sin(heading)), bounces: bounces)
    }

    /// The path of a ball let go at `start` traveling along `direction`, as the
    /// points it turns at, `start` first.
    func path(from start: Vector2, direction: Vector2, bounces: Int) -> [Vector2] {
        var heading = direction.normalized
        guard heading.lengthSquared > 0, bounces > 0 else { return [start] }

        var points = [start]
        var here = start
        for _ in 0 ..< bounces {
            guard let hit = firstWall(from: here, along: heading) else { break }
            points.append(hit.point)
            heading = (heading - hit.normal * (2 * heading.dot(hit.normal))).normalized
            // Step off the wall so the next search cannot find the same point.
            here = hit.point + heading * 1e-9
        }
        return points
    }

    /// Whether a point is inside the room, and clear of anything standing in
    /// it. Useful for choosing somewhere to let a ball go.
    func contains(_ point: Vector2) -> Bool {
        for obstacle in obstacles where point.distance(to: obstacle.center) <= obstacle.radius {
            return false
        }
        switch table {
        case let .circle(circle):
            return point.distance(to: circle.center) < circle.radius
        case let .ellipse(center, radii):
            guard radii.x > 0, radii.y > 0 else { return false }
            let d = point - center
            return (d.x * d.x) / (radii.x * radii.x) + (d.y * d.y) / (radii.y * radii.y) < 1
        case let .polygon(outline):
            return Shape(contours: [outline]).contains(point)
        case let .stadium(center, straight, radius):
            let d = point - center
            let half = straight / 2
            let toAxis = Vector2(max(0, abs(d.x) - half), d.y)
            return toAxis.length < radius
        }
    }

    /// The room's own outline, as geometry to draw. `segments` is how finely
    /// the curved parts are cut.
    func outline(segments: Int = 240) -> Contour {
        switch table {
        case let .circle(circle):
            return Contour((0 ..< segments).map { i in
                let a = .tau * Double(i) / Double(segments)
                return circle.center + Vector2(cos(a), sin(a)) * circle.radius
            }, closed: true)
        case let .ellipse(center, radii):
            return Contour((0 ..< segments).map { i in
                let a = .tau * Double(i) / Double(segments)
                return center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
            }, closed: true)
        case let .polygon(outline):
            return outline
        case let .stadium(center, straight, radius):
            let half = straight / 2
            let cap = max(2, segments / 2)
            var points: [Vector2] = []
            for i in 0 ... cap {                       // right cap, bottom to top
                let a = -Double.pi / 2 + .pi * Double(i) / Double(cap)
                points.append(center + Vector2(half + cos(a) * radius, sin(a) * radius))
            }
            for i in 0 ... cap {                       // left cap, top to bottom
                let a = Double.pi / 2 + .pi * Double(i) / Double(cap)
                points.append(center + Vector2(-half + cos(a) * radius, sin(a) * radius))
            }
            return Contour(points, closed: true)
        }
    }

    /// The two foci of an elliptical room, which are what decide the two
    /// pictures it draws. Empty for any other room.
    var foci: [Vector2] {
        guard case let .ellipse(center, radii) = table else { return [] }
        let major = max(radii.x, radii.y), minor = min(radii.x, radii.y)
        let reach = (major * major - minor * minor).squareRoot()
        let along = radii.x >= radii.y ? Vector2(reach, 0) : Vector2(0, reach)
        return [center - along, center + along]
    }
}

// MARK: - Finding the wall

private extension Billiard {
    struct Wall {
        var point: Vector2
        var normal: Vector2      // pointing back into the room
        var travel: Double
    }

    /// The first thing the ball meets, walls and obstacles together.
    func firstWall(from start: Vector2, along heading: Vector2) -> Wall? {
        var best = tableWall(from: start, along: heading)
        for obstacle in obstacles {
            guard let hit = obstacleWall(obstacle, from: start, along: heading) else { continue }
            if best == nil || hit.travel < best!.travel { best = hit }
        }
        return best
    }

    func tableWall(from start: Vector2, along heading: Vector2) -> Wall? {
        switch table {
        case let .circle(circle):
            guard let travel = leavingCircle(circle.center, circle.radius, start, heading) else { return nil }
            let point = start + heading * travel
            return Wall(point: point, normal: (circle.center - point).normalized, travel: travel)

        case let .ellipse(center, radii):
            guard radii.x > 0, radii.y > 0 else { return nil }
            // Squash the ellipse into a circle, solve there, and unsquash. The
            // normal has to be taken on the ellipse itself, since squashing
            // does not carry angles.
            let squashedStart = Vector2((start.x - center.x) / radii.x, (start.y - center.y) / radii.y)
            let squashedHeading = Vector2(heading.x / radii.x, heading.y / radii.y)
            guard let travel = leavingCircle(.zero, 1, squashedStart, squashedHeading, normalized: false)
            else { return nil }
            let point = start + heading * travel
            let d = point - center
            let outward = Vector2(d.x / (radii.x * radii.x), d.y / (radii.y * radii.y))
            return Wall(point: point, normal: -outward.normalized, travel: travel)

        case let .polygon(outline):
            return polygonWall(outline, from: start, along: heading)

        case let .stadium(center, straight, radius):
            return stadiumWall(center: center, straight: straight, radius: radius,
                               from: start, along: heading)
        }
    }

    /// How far a ball inside a circle travels before it reaches the rim. With
    /// `normalized` false the heading may be any length, and the answer is in
    /// units of that length, which is what the squashed ellipse needs.
    func leavingCircle(_ center: Vector2, _ radius: Double, _ start: Vector2,
                       _ heading: Vector2, normalized: Bool = true) -> Double? {
        let d = start - center
        let a = heading.lengthSquared
        guard a > 0 else { return nil }
        let b = 2 * d.dot(heading)
        let c = d.lengthSquared - radius * radius
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let travel = (-b + discriminant.squareRoot()) / (2 * a)
        guard travel > 1e-12, travel.isFinite else { return nil }
        return normalized ? travel : travel
    }

    /// Where a ray meets a circle standing in the room, entering it. The normal
    /// points away from the obstacle, which is back into the room.
    func obstacleWall(_ obstacle: Circle, from start: Vector2, along heading: Vector2) -> Wall? {
        let d = start - obstacle.center
        let b = 2 * d.dot(heading)
        let c = d.lengthSquared - obstacle.radius * obstacle.radius
        let discriminant = b * b - 4 * c
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let near = (-b - root) / 2, far = (-b + root) / 2
        let travel = near > 1e-9 ? near : far
        guard travel > 1e-9 else { return nil }
        let point = start + heading * travel
        return Wall(point: point, normal: (point - obstacle.center).normalized, travel: travel)
    }

    func polygonWall(_ outline: Contour, from start: Vector2, along heading: Vector2) -> Wall? {
        let points = outline.points
        guard points.count >= 3 else { return nil }
        var best: Wall?
        for i in 0 ..< points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            let edge = b - a
            let denominator = heading.cross(edge)
            guard abs(denominator) > 1e-12 else { continue }
            let travel = (a - start).cross(edge) / denominator
            let along = (a - start).cross(heading) / denominator
            guard travel > 1e-9, along >= 0, along <= 1 else { continue }
            guard best == nil || travel < best!.travel else { continue }
            var normal = Vector2(-edge.y, edge.x).normalized
            if normal.dot(heading) > 0 { normal = normal * -1 }     // face the ball
            best = Wall(point: start + heading * travel, normal: normal, travel: travel)
        }
        return best
    }

    func stadiumWall(center: Vector2, straight: Double, radius: Double,
                     from start: Vector2, along heading: Vector2) -> Wall? {
        let half = straight / 2
        var best: Wall?
        func consider(_ wall: Wall?) {
            guard let wall else { return }
            if best == nil || wall.travel < best!.travel { best = wall }
        }

        // The two flats, which only count between the caps.
        for side in [-1.0, 1.0] {
            let y = center.y + side * radius
            guard abs(heading.y) > 1e-12 else { continue }
            let travel = (y - start.y) / heading.y
            guard travel > 1e-9 else { continue }
            let x = start.x + heading.x * travel
            guard abs(x - center.x) <= half else { continue }
            consider(Wall(point: Vector2(x, y), normal: Vector2(0, -side), travel: travel))
        }

        // The two caps, which only count beyond the flats.
        for side in [-1.0, 1.0] {
            let capCenter = Vector2(center.x + side * half, center.y)
            guard let travel = leavingCircle(capCenter, radius, start, heading) else { continue }
            let point = start + heading * travel
            guard (point.x - capCenter.x) * side >= 0 else { continue }
            consider(Wall(point: point, normal: (capCenter - point).normalized, travel: travel))
        }
        return best
    }
}
