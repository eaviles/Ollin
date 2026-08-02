import Foundation

/// The spectre: the einstein, a single shape that tiles the plane yet can
/// never repeat. Tile(1,1) is the 14-sided polygon with unit edges and all
/// corners on the 30-degree grid; giving `curve` a nonzero value bends every
/// edge into the strictly chiral "spectre" form, which tiles only without
/// reflections. Patches are grown by the substitution system from the
/// discovery paper: spectres cluster into supertiles (one special pair, the
/// "mystic", rides in each) and supertiles cluster again, as deep as the
/// bounds require. Generation is rng-free, so the same call always lays the
/// same patch.
///
/// Each tile carries the `metatile` it descends from (nine types), the
/// natural coloring hook, and `isOdd` marks the sparse mystic partners that
/// sit rotated 30 degrees from every other tile.
///
/// ```swift
/// for tile in spectreTiling(tileEdge: 26, curve: 0.5) {
///     fill(tile.isOdd ? .orange : .ivory)
///     drawShape(tile.shape)
/// }
/// ```
public enum Spectre {
    /// The nine metatile types of the substitution system. Useful as a
    /// coloring key; `gamma` is the type that carries the mystic pair.
    public enum Metatile: Sendable, Equatable, CaseIterable {
        case gamma, delta, theta, lambda, xi, pi, sigma, phi, psi
    }

    /// One placed tile: its outline (all tiles are congruent and same-handed,
    /// never mirrored), the metatile type it descends from, and whether it is
    /// the odd mystic partner (rotated 30 degrees from the rest).
    public struct Tile: Sendable, Equatable {
        public let points: [Vector2]
        public let metatile: Metatile
        public let isOdd: Bool

        /// The tile as a fillable shape.
        public var shape: Shape { Shape(points) }

        /// The tile outline as a closed contour.
        public var contour: Contour { Contour(points, closed: true) }
    }

    /// The tiles of a spectre patch covering `bounds`, with edges close to
    /// `tileEdge`. `curve` is 0 for the straight-edged Tile(1,1) polygon and
    /// up to about 1 for strongly bent spectre edges (any nonzero value gives
    /// the strictly chiral tile; around 0.5 matches the published look).
    public static func tiles(
        in bounds: Rectangle,
        tileEdge: Double = 26,
        curve: Double = 0
    ) -> [Tile] {
        let edge = max(tileEdge, 1)

        // Grow substitution levels until the patch covers the bounds (scaled
        // into tile units), then place, scale, and clip.
        let targetWidth = bounds.width / edge
        let targetHeight = bounds.height / edge
        var level = 1
        var placed = placements(level: level)
        while level < 12 {
            let box = boundingBox(of: placed)
            if box.width >= targetWidth * 1.5, box.height >= targetHeight * 1.5,
               covers(placed, target: Rectangle(center: box.center,
                                                width: targetWidth, height: targetHeight)) {
                break
            }
            level += 1
            placed = placements(level: level)
            if placed.count > 2_000_000 { break }
        }

        let box = boundingBox(of: placed)
        let offset = bounds.center
        let outline = outlinePoints(curve: curve)

        var tiles: [Tile] = []
        tiles.reserveCapacity(placed.count)
        for p in placed {
            // Anchor cheaply first: skip tiles clearly outside the bounds.
            let anchor = mapPoint(p.transform.apply(basePoints[0]),
                                  boxCenter: box.center, scale: edge, offset: offset)
            let reach = 5 * edge
            if anchor.x < bounds.x - reach || anchor.x > bounds.x + bounds.width + reach
                || anchor.y < bounds.y - reach || anchor.y > bounds.y + bounds.height + reach {
                continue
            }
            let points = outline.map {
                mapPoint(p.transform.apply($0), boxCenter: box.center, scale: edge, offset: offset)
            }
            if intersectsBounds(points, bounds) {
                tiles.append(Tile(points: points, metatile: p.metatile, isOdd: p.isOdd))
            }
        }
        return tiles
    }

    // MARK: - Base geometry

    /// Tile(1,1): a turtle walk of 14 unit edges whose directions are these
    /// multiples of 30 degrees (y-up while under construction; emission flips
    /// into canvas space).
    static let edgeDirections = [0, 10, 1, 3, 0, 2, 5, 7, 4, 6, 6, 8, 11, 9]

    static let basePoints: [Vector2] = {
        var pts: [Vector2] = []
        pts.reserveCapacity(14)
        var position = Vector2(0, 0)
        for k in edgeDirections {
            pts.append(position)
            let angle = Double(k) * .pi / 6
            position += Vector2(cos(angle), sin(angle))
        }
        return pts
    }()

    /// The four anchor corners the substitution matches supertiles by.
    static let quadIndices = [3, 5, 7, 11]

    // MARK: - Affine plumbing

    struct Affine: Sendable {
        // Row-major 2x3: (a b tx; c d ty).
        var a: Double, b: Double, tx: Double
        var c: Double, d: Double, ty: Double

        static let identity = Affine(a: 1, b: 0, tx: 0, c: 0, d: 1, ty: 0)
        static let mirrorX = Affine(a: -1, b: 0, tx: 0, c: 0, d: 1, ty: 0)

        static func rotation(degrees: Double) -> Affine {
            let r = degrees * .pi / 180
            return Affine(a: cos(r), b: -sin(r), tx: 0, c: sin(r), d: cos(r), ty: 0)
        }

        static func translation(_ v: Vector2) -> Affine {
            Affine(a: 1, b: 0, tx: v.x, c: 0, d: 1, ty: v.y)
        }

        func apply(_ p: Vector2) -> Vector2 {
            Vector2(a * p.x + b * p.y + tx, c * p.x + d * p.y + ty)
        }

        /// self after `other` (apply `other` first).
        func concatenating(_ other: Affine) -> Affine {
            Affine(a: a * other.a + b * other.c,
                   b: a * other.b + b * other.d,
                   tx: a * other.tx + b * other.ty + tx,
                   c: c * other.a + d * other.c,
                   d: c * other.b + d * other.d,
                   ty: c * other.tx + d * other.ty + ty)
        }
    }

    // MARK: - The substitution system

    /// Per-supertile child types, eight slots each (slot 2 of gamma is
    /// empty). From the discovery paper's substitution tables.
    private static let childRules: [Metatile: [Metatile?]] = [
        .gamma:  [.pi, .delta, nil, .theta, .sigma, .xi, .phi, .gamma],
        .delta:  [.xi, .delta, .xi, .phi, .sigma, .pi, .phi, .gamma],
        .theta:  [.psi, .delta, .pi, .phi, .sigma, .pi, .phi, .gamma],
        .lambda: [.psi, .delta, .xi, .phi, .sigma, .pi, .phi, .gamma],
        .xi:     [.psi, .delta, .pi, .phi, .sigma, .psi, .phi, .gamma],
        .pi:     [.psi, .delta, .xi, .phi, .sigma, .psi, .phi, .gamma],
        .sigma:  [.xi, .delta, .xi, .phi, .sigma, .pi, .lambda, .gamma],
        .phi:    [.psi, .delta, .psi, .phi, .sigma, .pi, .phi, .gamma],
        .psi:    [.psi, .delta, .psi, .phi, .sigma, .psi, .phi, .gamma],
    ]

    /// How the eight child slots chain together: each entry is (rotation
    /// degrees added, anchor index on the previous child, anchor index on
    /// this child). The whole generation is then mirrored, which is how the
    /// layout alternates handedness per level while every tile keeps one
    /// hand.
    private static let slotRules: [(angle: Double, from: Int, to: Int)] = [
        (60, 3, 1), (0, 2, 0), (60, 3, 1), (60, 3, 1), (0, 2, 0), (60, 3, 1), (-120, 3, 3),
    ]

    /// One level's placement data: the eight child transforms and the quad
    /// anchors the next level will match against.
    private struct Level {
        var slots: [Affine]
        var quad: [Vector2]
    }

    private static func buildLevels(_ count: Int) -> [Level] {
        var levels: [Level] = []
        var quad = quadIndices.map { basePoints[$0] }
        for _ in 0..<count {
            var slots = [Affine.identity]
            var totalAngle = 0.0
            var rotation = Affine.identity
            for rule in slotRules {
                totalAngle += rule.angle
                if rule.angle != 0 {
                    rotation = .rotation(degrees: totalAngle)
                }
                let previous = slots[slots.count - 1]
                let target = previous.apply(quad[rule.from])
                let sourced = rotation.apply(quad[rule.to])
                let step = Affine.translation(target - sourced).concatenating(rotation)
                slots.append(step)
            }
            slots = slots.map { Affine.mirrorX.concatenating($0) }
            let nextQuad = [
                slots[6].apply(quad[2]),
                slots[5].apply(quad[1]),
                slots[3].apply(quad[2]),
                slots[0].apply(quad[1]),
            ]
            levels.append(Level(slots: slots, quad: nextQuad))
            quad = nextQuad
        }
        return levels
    }

    private struct Placement {
        var transform: Affine
        var metatile: Metatile
        var isOdd: Bool
    }

    /// Every base-tile placement of one `delta` supertile at `level`.
    private static func placements(level: Int) -> [Placement] {
        let levels = buildLevels(level)
        var out: [Placement] = []

        func walk(_ metatile: Metatile, depth: Int, transform: Affine) {
            if depth == 0 {
                out.append(Placement(transform: transform, metatile: metatile, isOdd: false))
                if metatile == .gamma {
                    let odd = Affine.translation(basePoints[8])
                        .concatenating(.rotation(degrees: 30))
                    out.append(Placement(transform: transform.concatenating(odd),
                                         metatile: metatile, isOdd: true))
                }
                return
            }
            let slots = levels[depth - 1].slots
            for (slot, child) in childRules[metatile]!.enumerated() {
                guard let child else { continue }
                walk(child, depth: depth - 1,
                     transform: transform.concatenating(slots[slot]))
            }
        }

        walk(.delta, depth: level, transform: .identity)
        return out
    }

    // MARK: - Fitting and emission

    private static func boundingBox(of placed: [Placement]) -> Rectangle {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in placed {
            let anchor = p.transform.apply(basePoints[0])
            minX = min(minX, anchor.x); maxX = max(maxX, anchor.x)
            minY = min(minY, anchor.y); maxY = max(maxY, anchor.y)
        }
        return Rectangle(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    /// True when every corner and the center of `target` (in tile units) sits
    /// inside some tile's reach.
    private static func covers(_ placed: [Placement], target: Rectangle) -> Bool {
        let probes = [target.topLeft, target.topRight, target.bottomRight,
                      target.bottomLeft, target.center]
        return probes.allSatisfy { probe in
            placed.contains { p in
                p.transform.apply(basePoints[0]).distance(to: probe) < 3
            }
        }
    }

    /// Tile-unit point into canvas space: recenter on the patch, scale to the
    /// edge length, flip y (construction is y-up), move to the bounds center.
    private static func mapPoint(_ p: Vector2, boxCenter: Vector2, scale: Double,
                                 offset: Vector2) -> Vector2 {
        let centered = p - boxCenter
        return Vector2(offset.x + centered.x * scale, offset.y - centered.y * scale)
    }

    private static func intersectsBounds(_ points: [Vector2], _ bounds: Rectangle) -> Bool {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return minX <= bounds.x + bounds.width && maxX >= bounds.x
            && minY <= bounds.y + bounds.height && maxY >= bounds.y
    }

    /// The tile outline in tile units: the straight 14-gon for `curve` 0,
    /// else every edge bent into the same flattened cubic bump, alternating
    /// sides edge to edge. The alternation is what removes the tile's mirror
    /// symmetry, so any nonzero `curve` is strictly chiral.
    private static func outlinePoints(curve: Double) -> [Vector2] {
        guard curve != 0 else { return basePoints }
        let bump = 0.35 * min(max(curve, -1), 1)
        let samplesPerEdge = 8
        var pts: [Vector2] = []
        pts.reserveCapacity(basePoints.count * samplesPerEdge)
        for i in 0..<basePoints.count {
            let p = basePoints[i]
            let q = basePoints[(i + 1) % basePoints.count]
            let along = q - p
            let normal = Vector2(-along.y, along.x)
            let side = i.isMultiple(of: 2) ? bump : -bump
            // A flattened cubic: control points a third of the way in, both
            // pushed to the same side.
            let c1 = p + along * (1.0 / 3.0) + normal * side
            let c2 = p + along * (2.0 / 3.0) + normal * side
            for s in 0..<samplesPerEdge {
                let t = Double(s) / Double(samplesPerEdge)
                let u = 1 - t
                let point = p * (u * u * u)
                    + c1 * (3 * u * u * t)
                    + c2 * (3 * u * t * t)
                    + q * (t * t * t)
                pts.append(point)
            }
        }
        return pts
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The tiles of a spectre (einstein) patch covering `bounds` (the whole
    /// canvas by default), with edges close to `tileEdge`. `curve` 0 is the
    /// straight-edged Tile(1,1); nonzero bends the edges into the strictly
    /// chiral spectre (about 0.5 matches the published look). Deterministic:
    /// no randomness is involved.
    ///
    /// ```swift
    /// for tile in spectreTiling(tileEdge: 30, curve: 0.5) {
    ///     fill(tile.isOdd ? .tomato : .ivory)
    ///     drawShape(tile.shape)
    /// }
    /// ```
    func spectreTiling(in bounds: Rectangle? = nil, tileEdge: Double = 26,
                       curve: Double = 0) -> [Spectre.Tile] {
        Spectre.tiles(in: bounds ?? canvasRectangle, tileEdge: tileEdge, curve: curve)
    }
}
