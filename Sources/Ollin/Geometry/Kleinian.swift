import Foundation

/// Kleinian limit sets: the fractal boundary curves of two-generator Möbius
/// groups. Two complex traces pick the group (the classic recipe builds the
/// generator matrices from `ta` and `tb` alone), and a depth-first walk of
/// the group's reduced words traces the limit set *in order*, so what comes
/// back is one closed curve: the Apollonian gasket at `(2, 2)`, tightening
/// double spirals just inside the quasi-Fuchsian region, lace and cusps at
/// its boundary.
///
/// ```swift
/// let lace = kleinianLimitSet(.lace)
/// noFill()
/// drawPolyline(fitted(lace.points, in: canvasRectangle.inset(by: 80)),
///              closed: true)
/// ```
///
/// The walk is rng-free and adaptive (it subdivides until each arc is under
/// `epsilon`), so points come back roughly evenly spaced along the curve,
/// plotter-ready. Deterministic given (traces, epsilon, maxDepth).

// Complex scalars and Möbius maps live in `MobiusMap.swift`, shared with the
// Schottky circle orbit.

// MARK: - The two-generator recipe

/// The generator pair built from the traces alone: unit determinant,
/// `tr(a) = ta`, `tr(b) = tb`, and a parabolic commutator, the normalization
/// the classic limit-set figures all use. The trace of `ab` comes from the
/// Markov identity's minus root (the plus root draws the mirror image).
func grandmaGenerators(ta: ComplexValue, tb: ComplexValue) -> (MobiusMap, MobiusMap)? {
    let four = ComplexValue.real(4)
    let two = ComplexValue.real(2)
    let twoI = ComplexValue(re: 0, im: 2)

    let product = ta * tb
    let discriminant = (product * product - four * (ta * ta + tb * tb)).squareRoot
    let tab = (product - discriminant) / two
    guard (tab - two).magnitude > 1e-9, (tab + two).magnitude > 1e-9 else { return nil }

    let z0 = ((tab - two) * tb) / (tb * tab - two * ta + twoI * tab)
    guard z0.magnitude > 1e-12 else { return nil }

    let fourI = ComplexValue(re: 0, im: 4)
    let a = MobiusMap(
        p: ta / two,
        q: (ta * tab - two * tb + fourI) / ((two * tab + four) * z0),
        r: (ta * tab - two * tb - fourI) * z0 / (two * tab - four),
        s: ta / two)
    let b = MobiusMap(
        p: (tb - twoI) / two,
        q: tb / two,
        r: tb / two,
        s: (tb + twoI) / two)
    return (a, b)
}

// MARK: - Presets

/// Trace pairs worth knowing by name, each a landmark of the family.
public enum KleinianPreset: CaseIterable, Sendable {
    /// `(2, 2)`: the Apollonian gasket, the family's grand ancestor.
    case gasket
    /// A tight double-spiral quasi-Fuchsian pair.
    case spiralPair
    /// A lacy quasi-Fuchsian curve, well inside the stable region.
    case lace
    /// The celebrated 1/15 double cusp, at the region's very edge.
    case doubleCusp
    /// A deep single cusp, halfway to degeneracy.
    case cusp
    /// A symmetric pair of cusps, one on each side of the curve.
    case symmetricCusps

    /// The trace pair as `(ta, tb)`, each a complex number carried as
    /// `Vector2(re, im)`.
    public var traces: (ta: Vector2, tb: Vector2) {
        switch self {
        case .gasket: (Vector2(2, 0), Vector2(2, 0))
        case .spiralPair: (Vector2(1.87, 0.1), Vector2(1.87, -0.1))
        case .lace: (Vector2(1.91, 0.05), Vector2(3, 0))
        case .doubleCusp: (Vector2(1.958591030, -0.011278560), Vector2(2, 0))
        case .cusp: (Vector2(1.64213876, -0.76658841), Vector2(2, 0))
        case .symmetricCusps: (Vector2(1.5306639, -0.8501047), Vector2(1.5306639, 0.8501047))
        }
    }
}

// MARK: - The limit-set walk

/// The limit set of the two-generator group with traces `ta` and `tb`
/// (complex numbers carried as `Vector2(re, im)`), traced as one closed
/// curve.
///
/// The walk explores the tree of reduced words depth-first in cyclic order,
/// carrying the running matrix product; a branch ends when the images of its
/// three landmark limit points sit within `epsilon` of each other, and those
/// images are emitted in order, which is what keeps the polyline connected.
/// `epsilon` is in limit-set units (the curve lives around ±2; half a pixel
/// of your target size is a good value), `maxDepth` caps the recursion (a
/// branch that deep emits what it has; cusps converge slowly and want more).
///
/// Traces outside the quasi-Fuchsian region have no curve to trace; the walk
/// still terminates but the polyline degenerates. Deterministic, rng-free.
public func kleinianLimitSet(ta: Vector2, tb: Vector2,
                             epsilon: Double = 0.002,
                             maxDepth: Int = 60) -> Contour {
    guard let (a, b) = grandmaGenerators(ta: ComplexValue(re: ta.x, im: ta.y),
                                         tb: ComplexValue(re: tb.x, im: tb.y))
    else { return Contour([], closed: true) }

    // Generators in the tag order a, b, A, B; inverse(i) = (i + 2) mod 4.
    let gens = [a, b, a.inverse, b.inverse]

    // Landmark limit points per ending tag: the two commutator rotations
    // that bound the branch's arc, with the generator's own attracting
    // fixed point between them.
    var repetends = [[ComplexValue]](repeating: [], count: 4)
    for tag in 0 ..< 4 {
        let first = gens[(tag + 1) % 4] * gens[(tag + 2) % 4] * gens[(tag + 3) % 4] * gens[tag]
        let last = gens[(tag + 3) % 4] * gens[(tag + 2) % 4] * gens[(tag + 1) % 4] * gens[tag]
        repetends[tag] = [first.attractingFixedPoint,
                          gens[tag].attractingFixedPoint,
                          last.attractingFixedPoint]
    }

    let epsilonSquared = epsilon * epsilon
    var points: [Vector2] = []

    func emit(_ z: ComplexValue) {
        let point = Vector2(z.re, z.im)
        if let lastPoint = points.last {
            let dx = point.x - lastPoint.x, dy = point.y - lastPoint.y
            if dx * dx + dy * dy < 1e-16 { return }
        }
        points.append(point)
    }

    func walk(_ matrix: MobiusMap, _ tag: Int, _ depth: Int) {
        let z0 = matrix.apply(repetends[tag][0])
        let z1 = matrix.apply(repetends[tag][1])
        let z2 = matrix.apply(repetends[tag][2])
        let gap01 = (z1.re - z0.re) * (z1.re - z0.re) + (z1.im - z0.im) * (z1.im - z0.im)
        let gap12 = (z2.re - z1.re) * (z2.re - z1.re) + (z2.im - z1.im) * (z2.im - z1.im)
        if (gap01 <= epsilonSquared && gap12 <= epsilonSquared) || depth >= maxDepth {
            emit(z0); emit(z1); emit(z2)
            return
        }
        // Children in cyclic order: right turn, straight, left turn. The
        // cancelling letter (tag + 2) is never taken, so words stay reduced.
        walk(matrix * gens[(tag + 1) % 4], (tag + 1) % 4, depth + 1)
        walk(matrix * gens[tag], tag, depth + 1)
        walk(matrix * gens[(tag + 3) % 4], (tag + 3) % 4, depth + 1)
    }

    // First letters in the cyclic order that makes the four quarter-arcs
    // join tip to tip.
    for tag in [0, 3, 2, 1] {
        walk(gens[tag], tag, 1)
    }
    return Contour(points, closed: true)
}

/// The limit set of a named `KleinianPreset`.
public func kleinianLimitSet(_ preset: KleinianPreset,
                             epsilon: Double = 0.002,
                             maxDepth: Int = 60) -> Contour {
    let traces = preset.traces
    return kleinianLimitSet(ta: traces.ta, tb: traces.tb,
                            epsilon: epsilon, maxDepth: maxDepth)
}
