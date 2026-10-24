import Foundation
import simd
import OllinExpander
import COllinShaders

/// A fill cut into bands that follow its outline inward, every corner carrying
/// its distance to the outline and the direction out through it: what a fill
/// medium shades from (see `FillMedium`). The bands are the region between one
/// inset of the outline and the next, each inset the outline moved in by a
/// fixed distance with round corners, so every corner of an inset lies that
/// distance from the outline, and the distance at a point inside a band is the
/// blend of its corners'. Past the last inset the fill is one flat piece.
struct FillRings: Sendable {
    /// Triangle corners in the shape's own coordinates, every three a triangle.
    var positions: [Vector2] = []
    /// Each corner's distance to the outline, in the shape's own units.
    var distances: [Float] = []
    /// Each corner's direction out through the outline, a unit vector in the
    /// shape's own coordinates.
    var outward: [SIMD2<Float>] = []

    /// The bands of `shape` out to `reach` units in from its outline, `step`
    /// units apart.
    static func make(_ shape: Shape, reach: Double, step: Double) -> FillRings {
        // The region resolved under its own winding, its outer boundaries and
        // holes wound opposite ways (the offset of zero only cleans it).
        let base = shape.offset(by: 0, join: .round)
        guard !base.contours.isEmpty else { return FillRings() }
        // Which way is out: the region lies to one side of travel along every
        // contour, the side its largest contour (an outer one) encloses.
        let areas = base.contours.map { Shape.signedArea($0.points) }
        let largest = areas.max { abs($0) < abs($1) } ?? 1
        let flip: Double = largest >= 0 ? 1 : -1

        var rings: [(distance: Double, contours: [[Vector2]])] = [(0, base.contours.map(\.points))]
        let stepCount = max(Int((reach / max(step, 1e-6)).rounded(.up)), 1)
        for k in 1...stepCount {
            let d = min(Double(k) * step, reach)
            let inset = base.offset(by: -d, join: .round)
            guard !inset.contours.isEmpty else { break }
            rings.append((d, inset.contours.map(\.points)))
        }

        // Each corner's distance and outward direction, found again by its place
        // once the tessellator hands the triangles back (it reads its corners as
        // floats, so the key is the float place).
        var known: [SIMD2<Float>: (Float, SIMD2<Float>)] = [:]
        for ring in rings {
            for contour in ring.contours {
                let n = contour.count
                guard n >= 3 else { continue }
                for i in 0..<n {
                    let prev = contour[(i + n - 1) % n], here = contour[i], next = contour[(i + 1) % n]
                    let a = edgeNormal(prev, here, flip), b = edgeNormal(here, next, flip)
                    var sum = a + b
                    let length = (sum.x * sum.x + sum.y * sum.y).squareRoot()
                    sum = length > 1e-9 ? sum / length : b
                    known[SIMD2<Float>(Float(here.x), Float(here.y))] =
                        (Float(ring.distance), SIMD2<Float>(Float(sum.x), Float(sum.y)))
                }
            }
        }

        var out = FillRings()
        for (index, ring) in rings.enumerated() {
            var contours = ring.contours
            if index + 1 < rings.count { contours += rings[index + 1].contours }
            let triangles = FillExpander.triangulate(contours.map { $0.map { Point2D($0.x, $0.y) } },
                                                     nonZero: false)
            out.positions.reserveCapacity(out.positions.count + triangles.count)
            for p in triangles {
                let key = SIMD2<Float>(Float(p.x), Float(p.y))
                let (d, dir) = known[key] ?? nearest(key, in: known, fallback: Float(ring.distance))
                out.positions.append(Vector2(p.x, p.y))
                out.distances.append(d)
                out.outward.append(dir)
            }
        }
        return out
    }

    /// The direction out through the edge from `a` to `b`: the side of travel
    /// the region does not lie on.
    private static func edgeNormal(_ a: Vector2, _ b: Vector2, _ flip: Double) -> Vector2 {
        let e = b - a
        let length = (e.x * e.x + e.y * e.y).squareRoot()
        guard length > 1e-12 else { return Vector2(0, 0) }
        return Vector2(e.y, -e.x) * (flip / length)
    }

    /// A corner the tessellator made itself (where two contours touched): the
    /// nearest known corner's values, or `fallback` and no direction.
    private static func nearest(_ p: SIMD2<Float>, in known: [SIMD2<Float>: (Float, SIMD2<Float>)],
                                fallback: Float) -> (Float, SIMD2<Float>) {
        var best: (Float, SIMD2<Float>) = (fallback, .zero)
        var bestDistance = Float.greatestFiniteMagnitude
        for (q, value) in known {
            let d = simd_distance_squared(p, q)
            if d < bestDistance { bestDistance = d; best = value }
        }
        return best
    }
}

/// The bands of the fills drawn lately, kept for two frames so a fill drawn
/// again unchanged (the same outline, at the same settings) is not cut again.
final class FillRingCache {
    struct Key: Hashable {
        var contours: [[Vector2]]
        var winding: FillWinding
        var reach: Double
        var step: Double
    }

    private var current: [Key: FillRings] = [:]
    private var previous: [Key: FillRings] = [:]

    func rings(for key: Key, make: () -> FillRings) -> FillRings {
        if let kept = current[key] { return kept }
        let rings = previous.removeValue(forKey: key) ?? make()
        current[key] = rings
        return rings
    }

    /// The frame turned: what was drawn this frame is kept for one more.
    func swapAndClear() {
        previous = current
        current = [:]
    }
}

extension Drawer {
    /// Fill `shape` under `medium`: the fill cut into bands along its outline
    /// (see `FillRings`), each corner written as a vertex pair whose second slot
    /// carries its distance to the edge, its direction out, and its place in the
    /// shape's own coordinates (see `OllinVertex`), into a `.triangles` run that
    /// draws through the fill medium fragment.
    func appendMediumFill(_ shape: Shape, paint: VertexPaint, medium: FillMedium) {
        let scale = fillCTMScale
        // The distance is carried as far as the look reads it, in steps of about
        // a point and a half on the canvas, between four and sixteen of them.
        let reach = medium.reachIn / scale
        let steps = min(max(Int((medium.reachIn / 1.5).rounded(.up)), 4), 16)
        let step = reach / Double(steps)
        let key = FillRingCache.Key(contours: shape.contours.filter { $0.isClosed }.map(\.points),
                                    winding: shape.winding, reach: reach, step: step)
        let rings = fillRingCache.rings(for: key) { FillRings.make(shape, reach: reach, step: step) }
        guard !rings.positions.isEmpty else { return }
        if medium.readsGround {
            if currentTarget != nil {
                noteOnce("A fill medium that reads the ground (the wash, gouache, chrome, glass) has nothing under it inside a layer and draws from its color alone.")
            }
        }
        let saved = currentPaintFillMedium
        currentPaintFillMedium = medium
        defer { currentPaintFillMedium = saved }
        // Symmetry folds are laid here rather than by `replicated`, which moves
        // a vertex's place but not the direction its second slot carries.
        let folds = isReplicating ? nil : symmetryFolds
        for fold in folds ?? [matrix_identity_float3x3] {
            let m = fold * transform
            emitMediumFill(rings, paint: paint, transform: m, scale: Float(scale))
        }
    }

    private func emitMediumFill(_ rings: FillRings, paint: VertexPaint, transform m: matrix_float3x3,
                                scale: Float) {
        ensureBatch(.triangles)
        let linear = simd_float2x2(SIMD2<Float>(m.columns.0.x, m.columns.0.y),
                                   SIMD2<Float>(m.columns.1.x, m.columns.1.y))
        // A direction across an edge turns with the inverse transpose, which a
        // stretch or a skew tells apart from the matrix itself.
        let normalMap = linear.determinant != 0 ? linear.inverse.transpose : linear
        let solid: SIMD4<Float>? = { if case .solid(let c) = paint { return c } else { return nil } }()
        vertices.reserveCapacity(vertices.count + rings.positions.count * 2)
        for i in rings.positions.indices {
            let p = rings.positions[i]
            let q = m * SIMD3<Float>(Float(p.x), Float(p.y), 1)
            var out = normalMap * rings.outward[i]
            let length = simd_length(out)
            out = length > 1e-9 ? out / length : .zero
            let color = solid ?? paint.color(at: p)
            let material = SIMD2<Float>(Float(p.x), Float(p.y)) * scale
            vertices.append(OllinVertex(position: SIMD2<Float>(q.x, q.y), aa: SIMD2<Float>(1, 0), color: color))
            vertices.append(OllinVertex(position: SIMD2<Float>(q.x, q.y),
                                        aa: SIMD2<Float>(rings.distances[i] * scale, 0),
                                        color: SIMD4<Float>(out.x, out.y, material.x, material.y)))
        }
    }

    /// How many canvas points one unit of the current transform spans, averaged
    /// over its two axes.
    private var fillCTMScale: Double {
        guard !transformIsIdentity else { return 1 }
        let c0 = transform.columns.0, c1 = transform.columns.1
        let sx = (c0.x * c0.x + c0.y * c0.y).squareRoot()
        let sy = (c1.x * c1.x + c1.y * c1.y).squareRoot()
        return max(Double(sx + sy) / 2, 1e-6)
    }

    /// Draw `shape`'s fill under the fill medium when one is set and the fill
    /// can take it, and say whether it did. A shader fill paints its own way
    /// and keeps it.
    func drewMediumFill(_ shape: @autoclosure () -> Shape, anchor: Vector2, bounds: @autoclosure () -> PaintBox?) -> Bool {
        guard let medium = fillMediumShape, let fill = fillPaint else { return false }
        if case .shader = fill {
            noteOnce("fillMedium(_:) shades a color or gradient fill; under fill(_ shader:) the shader paints the fill.")
            return false
        }
        let region = shape()
        appendMediumFill(region, paint: vertexPaint(fill, anchor: anchor, bounds: bounds()), medium: medium)
        return true
    }
}
