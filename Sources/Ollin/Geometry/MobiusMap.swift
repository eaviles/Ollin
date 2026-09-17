import Foundation

/// Möbius maps over the public `Complex` value (`Math/Complex.swift`): the
/// shared machinery behind the limit-set generators (`kleinianLimitSet`,
/// `schottkyCircles`).
///
/// A Möbius map `z → (pz + q) / (rz + s)` is the rigid motion of the Riemann
/// sphere. Two facts make the limit-set generators work: composition is
/// matrix multiplication, so a word in the generators is one product; and a
/// Möbius map carries circles to circles, so a circle orbit stays a circle
/// orbit forever.
///
/// The maps stay internal on purpose. Sketches reach them through the
/// generators built on them, not directly.

// MARK: - Möbius maps

/// A 2x2 complex matrix acting as the Möbius map z → (pz + q) / (rz + s).
struct MobiusMap {
    var p: Complex
    var q: Complex
    var r: Complex
    var s: Complex

    static let identity = MobiusMap(p: .one, q: .zero, r: .zero, s: .one)

    static func * (a: MobiusMap, b: MobiusMap) -> MobiusMap {
        MobiusMap(p: a.p * b.p + a.q * b.r,
                  q: a.p * b.q + a.q * b.s,
                  r: a.r * b.p + a.s * b.r,
                  s: a.r * b.q + a.s * b.s)
    }

    var determinant: Complex { p * s - q * r }

    /// The adjugate: the inverse of a unit-determinant matrix.
    var inverse: MobiusMap {
        MobiusMap(p: s, q: -q, r: -r, s: p)
    }

    /// The same map scaled to unit determinant, which is what makes `inverse`
    /// a true inverse and keeps a long word product from drifting in scale.
    /// A degenerate matrix comes back unchanged.
    var normalized: MobiusMap {
        let root = determinant.squareRoot()
        guard root.magnitude > 1e-150 else { return self }
        return MobiusMap(p: p / root, q: q / root, r: r / root, s: s / root)
    }

    func apply(_ z: Complex) -> Complex {
        (p * z + q) / (r * z + s)
    }

    /// The attracting fixed point (either fixed point when parabolic).
    var attractingFixedPoint: Complex {
        let trace = p + s
        let root = (trace * trace - Complex(4)).squareRoot()
        if r.magnitude < 1e-12 {
            // Fixed points are infinity and q / (s − p); return the finite one.
            return q / (s - p)
        }
        let lambda = (trace + root) / Complex(2)
        let k = lambda * lambda
        let plus = ((p - s) + root) / (r * Complex(2))
        let minus = ((p - s) - root) / (r * Complex(2))
        return k.magnitude > 1 ? plus : minus
    }

    /// The image of a circle, in closed form.
    ///
    /// A generalized circle `A|z|² + Bz̄ + B̄z + C = 0` is the Hermitian matrix
    /// `H = [[A, B], [B̄, C]]`, since `[z̄ 1] H [z 1]ᵀ` reproduces the equation.
    /// Substituting `z = M⁻¹z'` carries it to `H' = (M⁻¹)† H M⁻¹`, so the image
    /// costs a pair of 2x2 products rather than a three-point refit.
    ///
    /// Requires a unit-determinant matrix, so that `inverse` is exact.
    func image(of circle: Circle) -> Circle? {
        discImage(of: circle, exterior: false)?.circle
    }

    /// The image of a circle *carrying a disc*: `exterior` says which side of
    /// the source circle the disc is (false = the interior).
    ///
    /// The sign of the transformed form's `A'` says which side of the image
    /// circle the disc landed on: when the map's pole sits inside the source
    /// disc, the disc turns inside out and comes back as the image circle's
    /// exterior. That orientation is what a nesting walk needs, because an
    /// exterior disc is unbounded and its circle's radius bounds nothing.
    ///
    /// Returns `nil` when the image is a straight line (the source circle runs
    /// through the map's pole, so `A'` collapses to zero) or when the arithmetic
    /// leaves the finite plane. Callers treat that as a branch to drop: it is a
    /// measure-zero case for circles that stay clear of the pole.
    func discImage(of circle: Circle, exterior: Bool) -> (circle: Circle, exterior: Bool)? {
        let center = Complex(circle.center.x, circle.center.y)
        let a = Complex.one
        let b = -center
        let c = Complex(center.magnitudeSquared - circle.radius * circle.radius)

        let n = inverse
        // T = H · N
        let t00 = a * n.p + b * n.r
        let t01 = a * n.q + b * n.s
        let t10 = b.conjugate * n.p + c * n.r
        let t11 = b.conjugate * n.q + c * n.s
        // H' = N† · T
        let h00 = n.p.conjugate * t00 + n.r.conjugate * t10
        let h01 = n.p.conjugate * t01 + n.r.conjugate * t11
        let h11 = n.q.conjugate * t01 + n.s.conjugate * t11

        // A' and C' are real up to round-off; B' carries the center.
        let aPrime = h00.real
        let cPrime = h11.real
        guard abs(aPrime) > 1e-12 else { return nil }

        let imageCenter = -h01 / Complex(aPrime)
        let radiusSquared = (h01.magnitudeSquared - aPrime * cPrime) / (aPrime * aPrime)
        guard radiusSquared > 0, imageCenter.isFinite else { return nil }
        let radius = radiusSquared.squareRoot()
        guard radius.isFinite else { return nil }

        return (Circle(center: Vector2(imageCenter.real, imageCenter.imaginary), radius: radius),
                (aPrime < 0) != exterior)
    }

    /// The isometric circle: the locus where the map neither stretches nor
    /// shrinks, `|cz + d| = 1` for a unit-determinant matrix. The map carries
    /// the *outside* of its isometric circle onto the *inside* of its
    /// inverse's, which is exactly a Schottky pairing, so a group given by
    /// matrices instead of circles can still feed the orbit walk. `nil` for a
    /// map fixing infinity (`c ≈ 0`), which has no isometric circle.
    var isometricCircle: Circle? {
        let c = r.magnitude
        guard c > 1e-12 else { return nil }
        let center = -(s / r)
        return Circle(center: Vector2(center.real, center.imaginary), radius: 1 / c)
    }

    /// The involution sending `point` to infinity (and infinity to `point`),
    /// scaled by `radius`: `z → z₀ + R²/(z − z₀)`. This is the "move a point to
    /// the horizon" viewing transform: the plane turns inside out around the
    /// point, and whichever disc contained it becomes the picture's outside.
    static func horizon(at point: Vector2, radius: Double) -> MobiusMap {
        let z0 = Complex(point.x, point.y)
        let r2 = Complex(radius * radius)
        return MobiusMap(p: z0, q: r2 - z0 * z0, r: .one, s: -z0).normalized
    }

    /// The pairing map carrying the complement of the `from` disc onto the
    /// `to` disc, turned by `twist`. Each disc is its circle's interior
    /// unless flagged exterior, which is what lets one pairing circle
    /// *contain* the rest of an arrangement.
    ///
    /// Built by composition: the from side normalizes its disc complement onto
    /// the unit disc, a rotation applies the twist, and the to side carries
    /// the unit disc onto the target disc. For the everyday interior-interior
    /// case this collapses to `g(z) = q − s·r·u²·e^{iθ}/(z − p)` with `u` the
    /// unit vector between the centers; the `−u²` factor sets the twist's zero
    /// point so that two *touching* interior discs paired at `twist == 0` hold
    /// their tangency point fixed, making the generator parabolic. That is the
    /// case worth having as the default, because a parabolic generator barely
    /// contracts near its fixed point, so the orbit stays large for many
    /// generations instead of collapsing in three. An exterior-interior
    /// pairing gets the same courtesy for internal tangency: at `twist == 0`
    /// a `to` circle internally tangent to an exterior `from` holds the
    /// tangency point fixed.
    static func pairing(from: Circle, fromExterior: Bool = false,
                        to: Circle, toExterior: Bool = false,
                        twist: Double) -> MobiusMap {
        let p = Complex(from.center.x, from.center.y)
        let q = Complex(to.center.x, to.center.y)
        let rf = Complex(from.radius)
        let rt = Complex(to.radius)

        // The twist's zero point: interior-interior folds in −u², so touching
        // discs pair parabolically at zero; the flagged cases use the plain
        // rotation, which does the same for internal tangency.
        var rotation = Complex.unit(twist)
        if !fromExterior && !toExterior {
            let span = q - p
            let length = span.magnitude
            let u = length > 1e-12 ? span / Complex(length) : Complex.one
            rotation = -(u * u * rotation)
        }

        // Complement of the from disc → unit disc.
        let normalize = fromExterior
            ? MobiusMap(p: .one, q: -p, r: .zero, s: rf)   // (z − p) / r
            : MobiusMap(p: .zero, q: rf, r: .one, s: -p)   // r / (z − p)
        // Unit disc → to disc.
        let place = toExterior
            ? MobiusMap(p: q, q: rt, r: .one, s: .zero)    // q + r/w
            : MobiusMap(p: rt, q: q, r: .zero, s: .one)    // q + r·w
        let rotate = MobiusMap(p: rotation, q: .zero, r: .zero, s: .one)
        return (place * rotate * normalize).normalized
    }
}
