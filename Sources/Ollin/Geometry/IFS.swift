import Foundation

/// Iterated function systems: a handful of affine contractions that together
/// pin down one shape, their common attractor. Played as the chaos game
/// (apply a randomly chosen map, over and over), every orbit condenses onto
/// that attractor, so a few dozen numbers unfold into a fern, a triangle of
/// triangles, or a snowflake of squares.
///
/// ```swift
/// var rng = SplitMix64(seed: 2)
/// let leaf = IFS.barnsleyFern.points(count: 60_000, using: &rng)
/// drawPoints(fitted(leaf, in: canvasRectangle.inset(by: 60)), size: 1.5)
/// ```
///
/// Points draw from `rng`, so the same seed always condenses the same cloud,
/// and they return raw in the system's own coordinates (fit them by scaling
/// the *points*, the catalog rule), ready for `drawPoints`, density builds,
/// or the SVG path.
public struct IFS: Sendable {
    /// One affine map `x' = a·x + b·y + e`, `y' = c·x + d·y + f`, chosen with
    /// probability proportional to `weight`.
    public struct Map: Sendable {
        public var a: Double
        public var b: Double
        public var c: Double
        public var d: Double
        public var e: Double
        public var f: Double
        public var weight: Double

        public init(_ a: Double, _ b: Double, _ c: Double, _ d: Double,
                    _ e: Double, _ f: Double, weight: Double = 1) {
            self.a = a; self.b = b; self.c = c; self.d = d
            self.e = e; self.f = f
            self.weight = max(0, weight)
        }

        public func apply(_ p: Vector2) -> Vector2 {
            Vector2(a * p.x + b * p.y + e, c * p.x + d * p.y + f)
        }
    }

    public var maps: [Map]

    public init(maps: [Map]) {
        self.maps = maps
    }

    // MARK: - Presets

    /// The classic four-map fern: a stem, a main copy leaning slightly, and
    /// two leaflets. Lives in x ≈ −2.2…2.7, y ≈ 0…10, growing upward, so fit
    /// the points and flip y if the canvas should read stem-down.
    public static let barnsleyFern = IFS(maps: [
        Map(0, 0, 0, 0.16, 0, 0, weight: 0.01),
        Map(0.85, 0.04, -0.04, 0.85, 0, 1.6, weight: 0.85),
        Map(0.2, -0.26, 0.23, 0.22, 0, 1.6, weight: 0.07),
        Map(-0.15, 0.28, 0.26, 0.24, 0, 0.44, weight: 0.07),
    ])

    /// Three half-scale copies toward the corners of an equilateral triangle:
    /// the chaos game's original demonstration. Lives in the unit triangle.
    public static let sierpinskiTriangle = IFS(maps: [
        Map(0.5, 0, 0, 0.5, 0, 0),
        Map(0.5, 0, 0, 0.5, 0.5, 0),
        Map(0.5, 0, 0, 0.5, 0.25, 0.433),
    ])

    /// Eight third-scale copies skipping the center cell: the carpet sibling
    /// of the triangle. Lives in the unit square.
    public static let sierpinskiCarpet = IFS(maps: {
        var maps: [Map] = []
        for row in 0 ..< 3 {
            for column in 0 ..< 3 where !(row == 1 && column == 1) {
                maps.append(Map(1.0 / 3, 0, 0, 1.0 / 3,
                                Double(column) / 3, Double(row) / 3))
            }
        }
        return maps
    }())

    /// The chaos game: from the origin, repeatedly apply a weight-chosen map,
    /// recording each visit after a short burn-in while the orbit falls onto
    /// the attractor.
    ///
    /// - Parameters:
    ///   - count: How many points to return.
    ///   - burnIn: Steps discarded up front (20 is plenty; the contraction is
    ///     geometric).
    ///   - rng: The random source; seed it for a reproducible cloud.
    /// - Returns: `count` points on the attractor, in visit order, in the
    ///   system's own coordinates.
    public func points<R: RandomNumberGenerator>(
        count: Int,
        burnIn: Int = 20,
        using rng: inout R
    ) -> [Vector2] {
        guard !maps.isEmpty, count > 0 else { return [] }
        let total = maps.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }

        var points: [Vector2] = []
        points.reserveCapacity(count)
        var point = Vector2(0, 0)
        for step in 0 ..< count + burnIn {
            var pick = Double.random(in: 0 ..< total, using: &rng)
            var chosen = maps[maps.count - 1]
            for map in maps {
                if pick < map.weight { chosen = map; break }
                pick -= map.weight
            }
            point = chosen.apply(point)
            if step >= burnIn { points.append(point) }
        }
        return points
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The chaos game over `system`, driven by the seeded `random`, so
    /// `seed(_:)` reproduces the cloud. See `IFS.points(count:burnIn:using:)`.
    func ifsPoints(_ system: IFS, count: Int, burnIn: Int = 20) -> [Vector2] {
        system.points(count: count, burnIn: burnIn, using: &rng)
    }
}
