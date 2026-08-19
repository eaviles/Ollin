import Foundation

/// Metaballs: soft spheres whose fields add up, so they bulge toward each
/// other and merge into one skin as they meet. Each ball contributes a bump
/// that falls off to nothing at its reach; the surface is drawn where the sum
/// crosses `level`, and `mesh(resolution:)` marches it into a `Mesh`.
///
/// ```swift
/// var blobs = Metaballs()
/// blobs.add(at: Vector3(-30, 0, 0), radius: 50)
/// blobs.add(at: Vector3(30 * sin(time), 0, 0), radius: 40)
/// drawMesh(blobs.mesh())
/// ```
///
/// `radius` is the radius the ball reads at on its own: a single ball at the
/// default `level` comes back as a sphere of exactly that size. Bring two
/// within reach of each other and the sum lifts the field between them, so the
/// surface swells across the gap and the two fuse. Lowering `level` fattens
/// every ball and makes them merge from further apart; raising it thins them
/// until they separate.
///
/// The falloff is the soft-object polynomial: it reaches zero smoothly at a
/// finite distance, so a ball far away costs nothing and the field has an
/// exact extent to mesh inside.
public struct Metaballs: Sendable, Equatable {

    /// One soft sphere in the field.
    public struct Ball: Sendable, Equatable {
        /// Where the ball sits.
        public var center: Vector3
        /// The radius this ball reads at on its own, at the default `level`.
        public var radius: Double
        /// How hard the ball pushes. Above 1 it swells and merges more eagerly;
        /// a negative strength carves into its neighbors instead of joining
        /// them.
        public var strength: Double

        public init(center: Vector3, radius: Double, strength: Double = 1) {
            self.center = center
            self.radius = radius
            self.strength = strength
        }

        /// How far the ball's influence carries. The polynomial is written
        /// against this reach, and it is twice `radius` so that a lone ball at
        /// `level` 0.5 lands exactly on `radius`.
        var reach: Double { max(radius, 0) * 2 }
    }

    /// The balls, in the order they were added.
    public var balls: [Ball]

    /// The value the surface is drawn at. 0.5 is where a lone ball reads at
    /// its own `radius`.
    public var level: Double

    public init(_ balls: [Ball] = [], level: Double = 0.5) {
        self.balls = balls
        self.level = level
    }

    /// Add a ball.
    public mutating func add(at center: Vector3, radius: Double, strength: Double = 1) {
        balls.append(Ball(center: center, radius: radius, strength: strength))
    }

    /// Drop every ball, keeping `level`. Handy for refilling the field each
    /// frame from moving positions.
    public mutating func removeAll() { balls.removeAll(keepingCapacity: true) }

    /// The field at a point: every ball's falloff, summed.
    public func value(at point: Vector3) -> Double {
        var total = 0.0
        for ball in balls {
            let reach = ball.reach
            guard reach > 0 else { continue }
            let u = (point - ball.center).lengthSquared / (reach * reach)
            guard u < 1 else { continue }
            total += ball.strength * Metaballs.falloff(u)
        }
        return total
    }

    /// The box every ball's reach fits inside, or `nil` when there are none.
    public var bounds: (min: Vector3, max: Vector3)? {
        var lo = Vector3(.infinity, .infinity, .infinity)
        var hi = Vector3(-.infinity, -.infinity, -.infinity)
        var found = false
        for ball in balls where ball.reach > 0 {
            found = true
            let r = ball.reach
            lo = Vector3(min(lo.x, ball.center.x - r), min(lo.y, ball.center.y - r), min(lo.z, ball.center.z - r))
            hi = Vector3(max(hi.x, ball.center.x + r), max(hi.y, ball.center.y + r), max(hi.z, ball.center.z + r))
        }
        return found ? (min: lo, max: hi) : nil
    }

    /// The surface as a `Mesh`, marched over a grid `resolution` cells across
    /// the field's longest side. The box is taken from the balls themselves
    /// and padded by a cell, so the surface always closes rather than being
    /// clipped by the edge of the grid.
    ///
    /// Rebuilding this every frame is fine at modest resolutions; a still
    /// field is better marched once in `setup()` and kept.
    public func mesh(resolution: Int = 48) -> Mesh {
        guard let box = bounds, resolution >= 1 else { return Mesh(positions: [], indices: []) }
        let size = box.max - box.min
        let pad = max(size.x, max(size.y, size.z)) / Double(resolution) * 1.5
        let padded = (min: box.min - Vector3(pad, pad, pad),
                      max: box.max + Vector3(pad, pad, pad))
        return isosurface(at: level, in: padded, resolution: resolution) { value(at: $0) }
    }

    /// The soft-object falloff, in terms of `u`, the squared distance over the
    /// squared reach. It runs from 1 at the center to 0 at the reach, flattening
    /// out at both ends, and is written in `u` so a distance never needs a
    /// square root. At `u` = 1/4, that is halfway out, it is exactly 1/2, which
    /// is what puts a lone ball's surface on its own `radius`.
    static func falloff(_ u: Double) -> Double {
        1 - (22.0 / 9) * u + (17.0 / 9) * u * u - (4.0 / 9) * u * u * u
    }
}

public extension Metaballs {
    /// A field built from centers that all share one radius and strength.
    init(centers: [Vector3], radius: Double, strength: Double = 1, level: Double = 0.5) {
        self.init(centers.map { Ball(center: $0, radius: radius, strength: strength) }, level: level)
    }
}
