import Foundation

/// Regular tilings of the hyperbolic plane, seen through the Poincaré disk:
/// identical p-sided tiles meeting q around every vertex, repeating forever
/// into a circular horizon they never reach.
///
/// On flat paper only three regular tilings exist (triangles, squares,
/// hexagons), because the corners meeting at a vertex must sum to a full
/// turn. Hyperbolic space has room for every pair beyond them: whenever
/// `(sides - 2) * (meeting - 2) > 4`, the tiling lives on the hyperbolic
/// plane, and the disk shows all of it at once, every tile the same true
/// size, only *drawn* smaller as it approaches the rim.
///
/// ```swift
/// for tile in hyperbolicTiling(sides: 7, meeting: 3) {
///     fill(tile.parity == 0 ? .ivory : .indigo)
///     drawShape(tile.shape)
/// }
/// ```
///
/// The construction is the classic one: place the central tile from the
/// hyperbolic triangle it decomposes into, then reflect it across its own
/// edges, and keep reflecting the reflections. Each edge lies on a circle
/// that meets the horizon at right angles, and the reflection is inversion
/// in that circle, so every copy lands exactly. Tiles come back in drawing
/// order from the center outward, curved edges already flattened, with the
/// horizon circle inscribed in the given bounds. Deterministic: no
/// randomness and no time, so the same call always returns the same tiling.
public enum HyperbolicTiling {
    /// One tile of the tiling, in canvas coordinates.
    public struct Tile: Sendable, Equatable {
        /// The tile outline, its curved geodesic edges flattened to short
        /// segments sized for the tile's on-canvas footprint.
        public let points: [Vector2]

        /// The tile's hyperbolic center.
        public let center: Vector2

        /// How many edge crossings separate this tile from the central one
        /// (0 for the central tile, 1 for its direct neighbors, and so on).
        public let depth: Int

        /// 0 or 1, flipping across every shared edge. With `meeting` even
        /// this two-coloring closes consistently around every vertex, giving
        /// a perfect checkerboard; with `meeting` odd it still alternates,
        /// resolved deterministically where the two colors meet.
        public let parity: Int

        /// The outline as a fillable `Shape`.
        public var shape: Shape { Shape(points) }

        /// The outline as a closed `Contour`.
        public var contour: Contour { Contour(points, closed: true) }
    }

    /// A hard ceiling on emitted tiles, so a run with a tiny `minEdge` ends
    /// instead of exhausting memory near the horizon.
    private static let tileLimit = 100_000

    /// The tiles of the regular hyperbolic tiling with `sides`-sided tiles
    /// meeting `meeting` to a vertex, drawn in the disk inscribed in
    /// `bounds`.
    ///
    /// `viewpoint` is the point of the hyperbolic plane (in disk units,
    /// length below 1) brought to the middle of the disk, so animating it
    /// pans the camera across the tiling while the horizon stays put.
    /// Tiles whose longest edge would draw shorter than `minEdge` canvas
    /// units are pruned, which is what bounds the otherwise endless tiling;
    /// `maxDepth` is a backstop on the reflection depth.
    public static func tiles(
        sides: Int,
        meeting: Int,
        in bounds: Rectangle,
        viewpoint: Vector2 = Vector2(0, 0),
        minEdge: Double = 3,
        maxDepth: Int = 64
    ) -> [Tile] {
        precondition(sides >= 3 && meeting >= 3,
                     "A hyperbolic tiling needs at least 3 sides and 3 tiles to a vertex")
        precondition((sides - 2) * (meeting - 2) > 4,
                     "{\(sides),\(meeting)} is not hyperbolic: (sides - 2) * (meeting - 2) must exceed 4")

        let fitRadius = min(bounds.width, bounds.height) / 2
        let origin = bounds.center
        guard fitRadius > 0 else { return [] }

        // The central tile: its vertices sit at the Euclidean radius that
        // makes the corner angle exactly a `meeting`-th of a full turn. From
        // the right triangle with angles pi/sides and pi/meeting, the
        // hyperbolic circumradius c has cosh(c) = cot(pi/sides) *
        // cot(pi/meeting), and the disk shows that as sqrt((cosh(c) - 1) /
        // (cosh(c) + 1)) from the center.
        let coshC = 1 / (tan(.pi / Double(sides)) * tan(.pi / Double(meeting)))
        let vertexRadius = ((coshC - 1) / (coshC + 1)).squareRoot()
        var seed: [Vector2] = (0 ..< sides).map { k in
            let angle = 2 * .pi * Double(k) / Double(sides) - .pi / 2
            return Vector2(cos(angle), sin(angle)) * vertexRadius
        }
        var seedCenter = Vector2(0, 0)

        // Re-seat the tiling so `viewpoint` lands at the middle of the disk,
        // before any pruning, so sizes are judged as actually drawn.
        if viewpoint.lengthSquared > 0 {
            var w = viewpoint
            if w.length > 0.9999 { w = w.normalized * 0.9999 }
            seed = seed.map { diskTranslate($0, taking: w) }
            seedCenter = diskTranslate(seedCenter, taking: w)
        }

        let minEdgeDisk = minEdge / fitRadius

        // Breadth-first over edge reflections, deduplicated by tile center.
        // Centers of distinct tiles sit at least a tile apart while copies of
        // one tile agree to rounding error, so a fixed epsilon separates the
        // two cleanly at any size `minEdge` lets through.
        let epsilon = 1e-6
        var seen: [SeenKey: [Vector2]] = [:]
        func claim(_ center: Vector2) -> Bool {
            let cellX = Int((center.x / epsilon).rounded(.down))
            let cellY = Int((center.y / epsilon).rounded(.down))
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    for other in seen[SeenKey(x: cellX + dx, y: cellY + dy)] ?? [] {
                        if (other - center).lengthSquared < epsilon * epsilon { return false }
                    }
                }
            }
            seen[SeenKey(x: cellX, y: cellY), default: []].append(center)
            return true
        }

        struct Node {
            var vertices: [Vector2]
            var center: Vector2
            var depth: Int
            var parity: Int
        }

        var tiles: [Tile] = []
        var queue: [Node] = []
        var head = 0

        func admit(_ node: Node) {
            guard longestEdge(of: node.vertices) >= minEdgeDisk else { return }
            guard claim(node.center) else { return }
            tiles.append(makeTile(node.vertices, center: node.center,
                                  depth: node.depth, parity: node.parity,
                                  origin: origin, fitRadius: fitRadius))
            queue.append(node)
        }

        admit(Node(vertices: seed, center: seedCenter, depth: 0, parity: 0))

        while head < queue.count, tiles.count < tileLimit {
            let node = queue[head]
            head += 1
            guard node.depth < maxDepth else { continue }
            for i in 0 ..< sides {
                let mirror = Geodesic(through: node.vertices[i],
                                      and: node.vertices[(i + 1) % sides])
                admit(Node(vertices: node.vertices.map { mirror.reflect($0) },
                           center: mirror.reflect(node.center),
                           depth: node.depth + 1,
                           parity: 1 - node.parity))
            }
        }

        return tiles
    }

    // MARK: - The disk machinery

    private struct SeenKey: Hashable {
        var x: Int
        var y: Int
    }

    /// A hyperbolic line: a circle meeting the horizon at right angles, or a
    /// straight diameter when the two points line up with the center.
    private struct Geodesic {
        var isDiameter: Bool
        var center: Vector2
        var radiusSquared: Double
        var direction: Vector2

        init(through a: Vector2, and b: Vector2) {
            // Orthogonality to the unit circle pins the circle's center:
            // 2 c.a = 1 + |a|^2 and 2 c.b = 1 + |b|^2, a linear system whose
            // determinant vanishes exactly when the geodesic is a diameter.
            let det = a.x * b.y - a.y * b.x
            if abs(det) < 1e-11 {
                isDiameter = true
                center = Vector2(0, 0)
                radiusSquared = 0
                direction = (b - a).normalized
            } else {
                let ra = (1 + a.lengthSquared) / 2
                let rb = (1 + b.lengthSquared) / 2
                isDiameter = false
                center = Vector2((ra * b.y - rb * a.y) / det,
                                 (rb * a.x - ra * b.x) / det)
                radiusSquared = center.lengthSquared - 1
                direction = Vector2(0, 0)
            }
        }

        /// Hyperbolic reflection: inversion in the circle, or a plain mirror
        /// across the diameter.
        func reflect(_ z: Vector2) -> Vector2 {
            if isDiameter {
                let along = z.x * direction.x + z.y * direction.y
                return direction * (2 * along) - z
            }
            let d = z - center
            let scale = radiusSquared / max(d.lengthSquared, 1e-300)
            return center + d * scale
        }
    }

    /// The rigid motion of the disk that carries `w` to the center.
    private static func diskTranslate(_ z: Vector2, taking w: Vector2) -> Vector2 {
        // As complex numbers, z maps to (z - w) / (1 - conj(w) z).
        let top = z - w
        let bottom = Vector2(1 - (w.x * z.x + w.y * z.y), w.y * z.x - w.x * z.y)
        let d = max(bottom.lengthSquared, 1e-300)
        return Vector2((top.x * bottom.x + top.y * bottom.y) / d,
                       (top.y * bottom.x - top.x * bottom.y) / d)
    }

    private static func longestEdge(of vertices: [Vector2]) -> Double {
        var longest = 0.0
        for i in vertices.indices {
            let edge = (vertices[(i + 1) % vertices.count] - vertices[i]).lengthSquared
            if edge > longest { longest = edge }
        }
        return longest.squareRoot()
    }

    /// Flattens the tile's geodesic edges into canvas points, sampling each
    /// arc to its drawn length so big central tiles curve smoothly and rim
    /// tiles stay cheap.
    private static func makeTile(_ vertices: [Vector2], center: Vector2,
                                 depth: Int, parity: Int,
                                 origin: Vector2, fitRadius: Double) -> Tile {
        var points: [Vector2] = []
        for i in vertices.indices {
            let a = vertices[i]
            let b = vertices[(i + 1) % vertices.count]
            points.append(origin + a * fitRadius)
            let geodesic = Geodesic(through: a, and: b)
            if geodesic.isDiameter { continue }
            let fromCenter = a - geodesic.center
            let toCenter = b - geodesic.center
            var sweep = atan2(toCenter.y, toCenter.x) - atan2(fromCenter.y, fromCenter.x)
            if sweep > .pi { sweep -= 2 * .pi }
            if sweep < -.pi { sweep += 2 * .pi }
            let radius = max(geodesic.radiusSquared, 0).squareRoot()
            let segments = max(Int(abs(sweep) * radius * fitRadius / 6), 1)
            guard segments > 1 else { continue }
            let start = atan2(fromCenter.y, fromCenter.x)
            for k in 1 ..< segments {
                let angle = start + sweep * Double(k) / Double(segments)
                let sample = geodesic.center + Vector2(cos(angle), sin(angle)) * radius
                points.append(origin + sample * fitRadius)
            }
        }
        return Tile(points: points,
                    center: origin + center * fitRadius,
                    depth: depth, parity: parity)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The tiles of a regular hyperbolic tiling, `sides`-sided tiles meeting
    /// `meeting` to a vertex, filling the disk inscribed in `bounds` (the
    /// whole canvas by default). Iterate the tiles for per-tile color by
    /// `parity` or `depth`, or stroke each tile's `contour` for the bare
    /// lace. Animate `viewpoint` to pan across the tiling. Deterministic: no
    /// randomness is involved.
    ///
    /// ```swift
    /// for tile in hyperbolicTiling(sides: 5, meeting: 4) {
    ///     fill(tile.parity == 0 ? .ivory : .indigo)
    ///     drawShape(tile.shape)
    /// }
    /// ```
    func hyperbolicTiling(
        sides: Int = 7,
        meeting: Int = 3,
        in bounds: Rectangle? = nil,
        viewpoint: Vector2 = Vector2(0, 0),
        minEdge: Double = 3
    ) -> [HyperbolicTiling.Tile] {
        HyperbolicTiling.tiles(sides: sides, meeting: meeting,
                               in: bounds ?? canvasRectangle,
                               viewpoint: viewpoint, minEdge: minEdge)
    }
}
