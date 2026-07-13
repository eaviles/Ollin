import Foundation

/// A continuous dynamical system whose trajectory settles onto a strange
/// attractor: a bounded orbit that never repeats, tracing the wispy, layered
/// shapes (Lorenz's butterfly, Rössler's folded band, Aizawa's spiralling
/// torus) chaos is known for.
///
/// The system is its velocity field `derivative`: at a phase-space point it
/// returns the instantaneous rate of change. `orbit(count:settle:)` integrates
/// that field with fixed-step fourth-order Runge-Kutta from `start`, returning
/// the path as a list of `Vector3` you draw however you like. The natural home
/// is the point-cloud path: feed the points to a `PointCloud` and orbit them
/// with the camera (see `drawAttractor(_:count:settle:size:)` and the 3D
/// example), since these shapes only read in three dimensions.
///
/// Each orbit is a pure function of `start` and the parameters, so a run always
/// reproduces. Pick a system from the built-in factories (`.lorenz()`,
/// `.rossler()`, `.aizawa()`, and the rest), or supply your own `derivative` to
/// plot any first-order system you like.
public struct StrangeAttractor: Sendable {

    /// The system's velocity field: the rate of change `(dx, dy, dz)/dt` at a
    /// phase-space point. The built-in factories fill this in from a parameter
    /// set; supply your own to integrate an arbitrary first-order system.
    public var derivative: @Sendable (Vector3) -> Vector3

    /// The initial condition: a point to start integrating from. Stay off the
    /// system's fixed points (the origin is one for several systems), or the
    /// orbit never moves. The transient before the path reaches the attractor is
    /// trimmed by `settle`.
    public var start: Vector3

    /// The integration time step. Smaller is more accurate but covers less of
    /// the orbit per point; the factory defaults are tuned per system.
    public var step: Double

    /// A system defined by its velocity field, an initial condition, and an
    /// integration step.
    public init(start: Vector3, step: Double = 0.01,
                derivative: @escaping @Sendable (Vector3) -> Vector3) {
        self.start = start
        self.step = step
        self.derivative = derivative
    }

    /// Integrate `count` points along the orbit with fixed-step fourth-order
    /// Runge-Kutta, discarding `settle` warmup steps first so the path has
    /// reached the attractor (the transient from `start` is rarely wanted).
    public func orbit(count: Int, settle: Int = 0) -> [Vector3] {
        guard count > 0 else { return [] }
        var point = start
        for _ in 0..<max(0, settle) {
            point = rungeKutta4(point, step: step, derivative: derivative)
        }
        var path = [Vector3]()
        path.reserveCapacity(count)
        for _ in 0..<count {
            path.append(point)
            point = rungeKutta4(point, step: step, derivative: derivative)
        }
        return path
    }
}

// MARK: - Built-in continuous systems

public extension StrangeAttractor {

    /// Lorenz's system, the original strange attractor (a model of atmospheric
    /// convection): two lobes the orbit weaves between, the butterfly shape.
    /// The defaults are Lorenz's chaotic regime.
    static func lorenz(sigma: Double = 10, rho: Double = 28, beta: Double = 8.0 / 3.0,
                       start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.01) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            Vector3(sigma * (p.y - p.x),
                    p.x * (rho - p.z) - p.y,
                    p.x * p.y - beta * p.z)
        }
    }

    /// Rössler's system: a single spiral that stretches outward on a sheet, then
    /// folds back, a cleaner band than Lorenz's two lobes.
    static func rossler(a: Double = 0.2, b: Double = 0.2, c: Double = 5.7,
                        start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.02) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            Vector3(-(p.y + p.z),
                    p.x + a * p.y,
                    b + p.z * (p.x - c))
        }
    }

    /// Aizawa's system: an orbit that wraps a torus while drilling through its
    /// axis, a spiralling sphere-and-spindle shape.
    static func aizawa(a: Double = 0.95, b: Double = 0.7, c: Double = 0.6, d: Double = 3.5,
                       e: Double = 0.25, f: Double = 0.1,
                       start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.01) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            let x = p.x, y = p.y, z = p.z
            return Vector3((z - b) * x - d * y,
                           d * x + (z - b) * y,
                           c + a * z - (z * z * z) / 3 - (x * x + y * y) * (1 + e * z) + f * z * x * x * x)
        }
    }

    /// Thomas's cyclically symmetric system: a looping, almost knotted lattice
    /// walk, symmetric across all three axes.
    static func thomas(b: Double = 0.208186,
                       start: Vector3 = Vector3(0.1, 0, 0), step: Double = 0.05) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            Vector3(sin(p.y) - b * p.x,
                    sin(p.z) - b * p.y,
                    sin(p.x) - b * p.z)
        }
    }

    /// Halvorsen's cyclically symmetric system: three intertwined scrolls.
    static func halvorsen(a: Double = 1.89,
                          start: Vector3 = Vector3(-1.48, -1.51, 2.04), step: Double = 0.005) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            let x = p.x, y = p.y, z = p.z
            return Vector3(-a * x - 4 * y - 4 * z - y * y,
                           -a * y - 4 * z - 4 * x - z * z,
                           -a * z - 4 * x - 4 * y - x * x)
        }
    }

    /// Dadras's system: a four-winged shape with a central twist.
    static func dadras(a: Double = 3, b: Double = 2.7, c: Double = 1.7, d: Double = 2, e: Double = 9,
                       start: Vector3 = Vector3(1.1, 2.1, -2), step: Double = 0.01) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            Vector3(p.y - a * p.x + b * p.y * p.z,
                    c * p.y - p.x * p.z + p.z,
                    d * p.x * p.y - e * p.z)
        }
    }

    /// Chen's system: a double-scroll relative of Lorenz, more tightly wound.
    static func chen(alpha: Double = 5, beta: Double = -10, delta: Double = -0.38,
                     start: Vector3 = Vector3(-0.1, 0.5, -0.6), step: Double = 0.005) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            Vector3(alpha * p.x - p.y * p.z,
                    beta * p.y + p.x * p.z,
                    delta * p.z + p.x * p.y / 3)
        }
    }

    /// The Wang-Sun four-wing system: four lobes meeting at the center.
    static func fourWing(a: Double = 0.2, b: Double = 0.01, c: Double = -0.4,
                         start: Vector3 = Vector3(1, -1, 1), step: Double = 0.05) -> StrangeAttractor {
        StrangeAttractor(start: start, step: step) { p in
            Vector3(a * p.x + p.y * p.z,
                    b * p.x + c * p.y - p.x * p.z,
                    -p.z - p.x * p.y)
        }
    }
}

/// A two-dimensional iterated map whose orbit fills a strange attractor: feed a
/// point back through `next` over and over and the dots settle into delicate,
/// symmetric filigree (Clifford's and de Jong's trigonometric webs, Hénon's
/// folded curve).
///
/// Unlike `StrangeAttractor` there is nothing to integrate; `orbit(count:)` just
/// iterates the map from `start`. The output is `[Vector2]`, drawn as a scatter
/// of points or, prettiest, accumulated additively (`blendMode(.add)` over the
/// accumulation surface) so overlapping visits brighten into a density field.
/// Each orbit reproduces, being a pure function of `start` and the parameters.
public struct ChaoticMap: Sendable {

    /// The map: the next point given the current one.
    public var next: @Sendable (Vector2) -> Vector2

    /// The point the iteration starts from. Any point in the basin works; the
    /// orbit forgets it quickly, so `settle` trims the first few steps.
    public var start: Vector2

    /// A map defined by its iteration rule and a starting point.
    public init(start: Vector2 = Vector2(0.1, 0.1),
                next: @escaping @Sendable (Vector2) -> Vector2) {
        self.start = start
        self.next = next
    }

    /// Iterate `count` points of the orbit, discarding `settle` warmup steps
    /// first.
    public func orbit(count: Int, settle: Int = 0) -> [Vector2] {
        guard count > 0 else { return [] }
        var point = start
        for _ in 0..<max(0, settle) { point = next(point) }
        var path = [Vector2]()
        path.reserveCapacity(count)
        for _ in 0..<count {
            path.append(point)
            point = next(point)
        }
        return path
    }
}

// MARK: - Built-in iterated maps

public extension ChaoticMap {

    /// Clifford's attractor: `x' = sin(a·y) + c·cos(a·x)`,
    /// `y' = sin(b·x) + d·cos(b·y)`. Coordinates stay within roughly [-2, 2].
    /// The four constants reshape it completely; the defaults are a well-known
    /// swirling form.
    static func clifford(a: Double = -1.4, b: Double = 1.6, c: Double = 1.0, d: Double = 0.7) -> ChaoticMap {
        ChaoticMap { p in
            Vector2(sin(a * p.y) + c * cos(a * p.x),
                    sin(b * p.x) + d * cos(b * p.y))
        }
    }

    /// The Peter de Jong attractor: `x' = sin(a·y) - cos(b·x)`,
    /// `y' = sin(c·x) - cos(d·y)`. Coordinates stay within roughly [-2, 2].
    static func deJong(a: Double = -2.24, b: Double = 0.43, c: Double = -0.65, d: Double = -2.43) -> ChaoticMap {
        ChaoticMap { p in
            Vector2(sin(a * p.y) - cos(b * p.x),
                    sin(c * p.x) - cos(d * p.y))
        }
    }

    /// The Hénon map: `x' = 1 - a·x² + y`, `y' = b·x`. The classic defaults
    /// trace its thin, folded boomerang curve.
    static func henon(a: Double = 1.4, b: Double = 0.3) -> ChaoticMap {
        ChaoticMap { p in
            Vector2(1 - a * p.x * p.x + p.y, b * p.x)
        }
    }
}

// MARK: - Sketch sugar

public extension Sketch {

    /// Draw a `StrangeAttractor` as a point cloud orbited by the camera: build an
    /// orbit of `count` points (after `settle` warmup steps) and splat each at
    /// `size` world units in the current `fill` color. Like `drawPointCloud`,
    /// this needs a `camera` (it is a no-op in a 2D frame). For per-point color
    /// (by speed or position), build the `PointCloud` yourself from
    /// `attractor.orbit(count:settle:)`.
    func drawAttractor(_ attractor: StrangeAttractor, count: Int = 100_000,
                       settle: Int = 1000, size: Double = 0.02) {
        let cloud = PointCloud(positions: attractor.orbit(count: count, settle: settle),
                               color: drawer.currentFillColor, size: size)
        drawPointCloud(cloud)
    }

    /// Draw a `ChaoticMap`'s orbit as a scatter of points in the current `fill`,
    /// at the current `pointSize`. The points land in the map's own coordinate
    /// space (roughly [-2, 2]); `translate`/`scale` it onto the canvas, and reach
    /// for `blendMode(.add)` over `noClear()` to build a density bloom.
    func drawAttractor(_ map: ChaoticMap, count: Int = 100_000, settle: Int = 100) {
        drawPoints(map.orbit(count: count, settle: settle))
    }
}
