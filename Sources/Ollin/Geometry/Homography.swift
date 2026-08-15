import simd

/// The map that takes the unit square onto any four-sided shape, and takes it
/// back again.
///
/// It is the one map that turns straight lines into straight lines while
/// letting the four corners go wherever you put them, which is exactly what a
/// projector aimed at a wall from an angle does to a picture. Undoing that is
/// what corner-pinning is: you say where the four corners land, and every point
/// in between follows.
///
/// A scale, a rotation, or a shear can be written as a matrix over `(x, y)`.
/// This cannot: two parallel edges of the square may meet on the wall, and no
/// such matrix ever makes parallel lines meet. So the point carries a third
/// number through the multiply and the first two are divided by it at the end.
/// That division is the whole difference, and it is why the picture crowds
/// together at the far corner the way a road narrows into the distance.
///
/// Written from Paul Heckbert's projective-mapping equations (see
/// `ATTRIBUTION.md`). Internal: the public face is
/// ``Installation/Projection/Corners``.
struct Homography: Equatable {

    /// Unit square to the four corners. Multiplies `(u, v, 1)` and yields
    /// `(x', y', w)`, where the answer is `(x'/w, y'/w)`.
    let matrix: simd_double3x3
    /// The four corners back to the unit square: the same map read the other
    /// way, which is the one a fragment needs (it starts from where it is on
    /// the output and asks which part of the picture belongs there).
    let inverse: simd_double3x3

    /// Build the map that takes the corners of the unit square onto
    /// `topLeft`, `topRight`, `bottomRight`, `bottomLeft`, in that order.
    ///
    /// Nil when the four points do not make a shape with an inside: three of
    /// them in a line, two on top of each other, a bow tie. There is no map
    /// back from a shape with no area, and a run must not carry a matrix full
    /// of infinities.
    init?(unitSquareTo topLeft: Vector2, _ topRight: Vector2,
          _ bottomRight: Vector2, _ bottomLeft: Vector2) {
        // The corners in the order the equations below are written for: the
        // square's (0,0), (1,0), (1,1), (0,1).
        let (x0, y0) = (topLeft.x, topLeft.y)
        let (x1, y1) = (topRight.x, topRight.y)
        let (x2, y2) = (bottomRight.x, bottomRight.y)
        let (x3, y3) = (bottomLeft.x, bottomLeft.y)

        // How far the shape departs from a parallelogram. dx3/dy3 are zero for
        // one, which is the case that has no perspective in it at all.
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3

        let a: Double, b: Double, c: Double
        let d: Double, e: Double, f: Double
        let g: Double, h: Double

        if abs(dx3) < 1e-12 && abs(dy3) < 1e-12 {
            // A parallelogram: no division at the end, so this is the ordinary
            // affine map. Kept as its own case because the general one divides
            // by a determinant that is zero here.
            a = x1 - x0; b = x2 - x1; c = x0
            d = y1 - y0; e = y2 - y1; f = y0
            g = 0; h = 0
        } else {
            let denominator = dx1 * dy2 - dy1 * dx2
            guard abs(denominator) > 1e-12 else { return nil }
            g = (dx3 * dy2 - dy3 * dx2) / denominator
            h = (dx1 * dy3 - dy1 * dx3) / denominator
            a = x1 - x0 + g * x1
            b = x3 - x0 + h * x3
            c = x0
            d = y1 - y0 + g * y1
            e = y3 - y0 + h * y3
            f = y0
        }

        // Columns, because that is how the type is laid out: the first column
        // is what multiplies u, the second what multiplies v, the third the 1.
        let m = simd_double3x3(columns: (SIMD3(a, d, g), SIMD3(b, e, h), SIMD3(c, f, 1)))
        // A shape with no area collapses the map, and the inverse comes back
        // full of infinities rather than failing, so the determinant is the
        // thing to ask.
        guard abs(m.determinant) > 1e-12 else { return nil }
        matrix = m
        inverse = m.inverse
    }

    /// Where `point` in the unit square lands on the four-sided shape.
    func map(_ point: Vector2) -> Vector2 { Homography.apply(matrix, point) }

    /// Where `point` on the four-sided shape came from in the unit square.
    /// Points outside the shape come back outside the square, which is how a
    /// fragment knows it has nothing to draw.
    func unmap(_ point: Vector2) -> Vector2 { Homography.apply(inverse, point) }

    /// The multiply and the divide that follows it. A `w` of zero is the
    /// horizon, where the map sends a point infinitely far away; it answers
    /// zero rather than a not-a-number, since every caller here is asking about
    /// a point on a screen.
    private static func apply(_ m: simd_double3x3, _ point: Vector2) -> Vector2 {
        let r = m * SIMD3(point.x, point.y, 1)
        guard abs(r.z) > 1e-12 else { return Vector2(0, 0) }
        return Vector2(r.x / r.z, r.y / r.z)
    }

    /// The same matrix in the width the GPU reads.
    var shaderInverse: simd_float3x3 {
        simd_float3x3(columns: (SIMD3<Float>(inverse.columns.0),
                                SIMD3<Float>(inverse.columns.1),
                                SIMD3<Float>(inverse.columns.2)))
    }
}
