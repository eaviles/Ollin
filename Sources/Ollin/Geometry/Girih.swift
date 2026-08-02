import Foundation

/// Islamic star patterns by the polygons-in-contact method: lay any
/// edge-to-edge tiling of polygons, sprout a pair of rays from each edge
/// midpoint at a chosen contact angle, and grow them until they meet. Remove
/// the tiling and the crossings that remain *are* the star pattern, one motif
/// per tile, joining seamlessly across edges because both sides launch from
/// the same midpoints.
///
/// Works over any polygons: `Grid` squares, `HexGrid` cells, Penrose tiles,
/// or the five classic `Girih.Tile` shapes of the decagonal tradition. The
/// contact angle is the one big dial: the same tiling reads spiky, star-like,
/// or woven as it changes (54 degrees is the classic girih-tile angle).
///
/// ```swift
/// let cells = hexGrid(columns: 8, rows: 7).cells.map(\.corners)
/// stroke(.black); strokeWeight(3)
/// drawGirih(over: cells, angle: 60)
/// ```
public enum Girih {
    /// The five girih tiles: unit-edge polygons with corners in multiples of
    /// 36 degrees, the shapes of the medieval decagonal system. All five
    /// share the same edge length, so any two can sit edge to edge and one
    /// strapwork angle decorates them all consistently.
    public enum Tile: Sendable, Equatable, CaseIterable {
        /// The regular decagon.
        case decagon
        /// The regular pentagon.
        case pentagon
        /// The elongated hexagon (angles 72-144-144, twice around).
        case hexagon
        /// The non-convex bowtie (two 216-degree waists).
        case bowtie
        /// The 72/108-degree rhombus.
        case rhombus

        /// The exterior turn at each corner as the outline is walked, in
        /// degrees (multiples of 36).
        private var turnSequence: [Double] {
            switch self {
            case .decagon: return Array(repeating: 36, count: 10)
            case .pentagon: return Array(repeating: 72, count: 5)
            case .hexagon: return [108, 36, 36, 108, 36, 36]
            case .bowtie: return [108, 108, -36, 108, 108, -36]
            case .rhombus: return [108, 72, 108, 72]
            }
        }

        /// The tile's corners with unit edges, centered on its centroid, in a
        /// canonical orientation (first edge along +x).
        public var points: [Vector2] {
            // A turtle walk of unit steps through the exterior angles.
            var pts: [Vector2] = []
            var position = Vector2(0, 0)
            var heading = 0.0
            for turn in turnSequence {
                pts.append(position)
                position += Vector2(cos(heading), sin(heading))
                heading += turn * .pi / 180
            }
            let centroid = pts.centroid ?? .init(0, 0)
            return pts.map { $0 - centroid }
        }

        /// The tile's corners scaled to `edge` and moved to `center`, spun by
        /// `rotation` (radians). Girih tiles compose edge to edge, so place
        /// them by matching edges and feed the result to `girihPattern`.
        public func points(edge: Double, at center: Vector2 = .init(0, 0),
                           rotation: Double = 0) -> [Vector2] {
            points.map { center + ($0 * edge).rotated(by: rotation) }
        }

        /// The tile's corners with its first edge laid exactly along
        /// `from`-to-`to` (the edge length comes from the segment), the body
        /// on the right of that direction on the canvas. Swap the two points
        /// to flip it to the other side. This is how girih patches compose:
        /// walk an existing tile's edge backward and the new tile lands snug
        /// against it.
        public func points(onEdge from: Vector2, _ to: Vector2) -> [Vector2] {
            let step = to - from
            var position = from
            var heading = atan2(step.y, step.x)
            var pts: [Vector2] = []
            let turns = turnSequence
            pts.reserveCapacity(turns.count)
            for turn in turns {
                pts.append(position)
                position += Vector2(cos(heading), sin(heading)) * step.length
                heading += turn * .pi / 180
            }
            return pts
        }
    }

    /// The star-pattern motif inside one polygon: from each edge midpoint two
    /// rays enter at `angle` degrees to the edge, and rays pair up greedily
    /// shortest-total-length first, each matched pair becoming one polyline
    /// through their crossing. Rays that never meet another are dropped.
    /// Returns open contours; the polygon itself is not included.
    public static func pattern(in polygon: [Vector2], angle: Double) -> [Contour] {
        let n = polygon.count
        guard n >= 3 else { return [] }

        // Interior side: signed area tells the winding, and every ray must
        // lean into the polygon.
        var area = 0.0
        for i in 0..<n {
            let p = polygon[i], q = polygon[(i + 1) % n]
            area += p.x * q.y - q.x * p.y
        }
        let interiorSign: Double = area >= 0 ? 1 : -1
        let theta = angle * .pi / 180

        // Two rays per edge midpoint, mirror-slanted so they form half an X
        // opening into the tile.
        struct Ray {
            let origin: Vector2
            let direction: Vector2
        }
        var rays: [Ray] = []
        rays.reserveCapacity(2 * n)
        for i in 0..<n {
            let p = polygon[i], q = polygon[(i + 1) % n]
            let mid = p.lerp(to: q, 0.5)
            let along = (q - p).normalized
            rays.append(Ray(origin: mid, direction: along.rotated(by: interiorSign * theta)))
            rays.append(Ray(origin: mid, direction: (along * -1).rotated(by: -interiorSign * theta)))
        }

        // Every candidate pairing, costed by the length of line work it adds:
        // crossing rays cost the two origin-to-crossing distances, collinear
        // facing rays cost the straight segment joining their origins.
        struct Pairing {
            let i: Int, j: Int
            let cost: Double
            let path: [Vector2]
        }
        var pairings: [Pairing] = []
        for i in 0..<rays.count {
            for j in (i + 1)..<rays.count {
                let a = rays[i], b = rays[j]
                let denom = a.direction.cross(b.direction)
                if abs(denom) > 1e-9 {
                    let offset = b.origin - a.origin
                    let t = offset.cross(b.direction) / denom
                    let u = offset.cross(a.direction) / denom
                    if t > 1e-9 && u > 1e-9 {
                        let crossing = a.origin + a.direction * t
                        pairings.append(Pairing(i: i, j: j, cost: t + u,
                                                path: [a.origin, crossing, b.origin]))
                    }
                } else {
                    // Parallel: pair only if collinear and pointing at each
                    // other, as one straight strand.
                    let offset = b.origin - a.origin
                    let distance = offset.length
                    if distance > 1e-9,
                       abs(a.direction.cross(offset)) < 1e-6 * distance,
                       a.direction.dot(offset) > 0,
                       b.direction.dot(offset) < 0 {
                        pairings.append(Pairing(i: i, j: j, cost: distance,
                                                path: [a.origin, b.origin]))
                    }
                }
            }
        }

        // Greedy: cheapest pairings first, each ray used once.
        pairings.sort { ($0.cost, $0.i, $0.j) < ($1.cost, $1.i, $1.j) }
        var used = [Bool](repeating: false, count: rays.count)
        var motif: [Contour] = []
        for pairing in pairings where !used[pairing.i] && !used[pairing.j] {
            used[pairing.i] = true
            used[pairing.j] = true
            motif.append(Contour(pairing.path, closed: false))
        }
        return motif
    }

    /// The star pattern over a whole tiling: one motif per polygon,
    /// concatenated. Motifs join across shared edges because both tiles
    /// launch their rays from the same edge midpoints.
    public static func pattern(over polygons: [[Vector2]], angle: Double) -> [Contour] {
        polygons.flatMap { pattern(in: $0, angle: angle) }
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The star-pattern line work over `polygons` at the given contact
    /// `angle` (degrees; 54 is the classic girih-tile angle). Returns open
    /// contours ready to stroke, hatch, or export. Deterministic: no
    /// randomness is involved.
    func girihPattern(over polygons: [[Vector2]], angle: Double = 54) -> [Contour] {
        Girih.pattern(over: polygons, angle: angle)
    }

    /// The star-pattern motif inside one polygon at contact `angle` degrees.
    func girihPattern(in polygon: [Vector2], angle: Double = 54) -> [Contour] {
        Girih.pattern(in: polygon, angle: angle)
    }

    /// Stroke the star pattern over `polygons` at contact `angle` degrees
    /// with the current `stroke`. For per-strand color or fills, iterate
    /// `girihPattern(over:angle:)` instead.
    func drawGirih(over polygons: [[Vector2]], angle: Double = 54) {
        for contour in girihPattern(over: polygons, angle: angle) {
            drawPolyline(contour.points, closed: false)
        }
    }
}
