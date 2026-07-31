import Foundation

/// The standing-wave field of a vibrating square plate: the pattern behind
/// **Chladni figures**, the symmetric line drawings sand traces on a resonating
/// plate as it gathers along the still (nodal) lines.
///
/// The closed form superposes a plate mode with its mirror image,
///
/// ```
/// s(x, y) = a·cos(nπx)·cos(mπy) + b·cos(mπx)·cos(nπy)
/// ```
///
/// over plate coordinates `x`, `y` in `0…1`, normalized so the result spans
/// `-1…1`. The zero set of `s` is the figure: sand collects where the plate
/// stands still, so draw the region near `s == 0` (or hand the field to
/// `isolines(at: 0, ...)` for the nodal lines as plotter-ready contours).
/// Outside `0…1` the field continues as mirrored plates, seamlessly.
///
/// `m` and `n` are the mode numbers: integers ring true modes of the square
/// plate (higher numbers, finer figures), and fractional values morph smoothly
/// between them, so animating `m` or `n` melts one figure into the next. With
/// the default amplitudes `a: 1, b: -1` (a plate driven at its center) the
/// field is antisymmetric across the diagonal: swapping `m` and `n` negates it,
/// and `m == n` cancels to zero everywhere (no figure; the plate isn't ringing).
/// Other `a`/`b` mixes ring the two mirrored modes unevenly and open up the
/// wider family of figures.
///
/// The GPU sibling is `generate(.chladni(...))`, which fills a layer with the
/// same field styled as sand or as the breathing wave; this function is the
/// composable form for geometry (nodal isolines, particles settling toward
/// nodes, fields sampled per point).
public func chladni(_ x: Double, _ y: Double, m: Double, n: Double,
                    a: Double = 1, b: Double = -1) -> Double {
    let span = abs(a) + abs(b)
    guard span > 0 else { return 0 }
    let value = a * cos(n * .pi * x) * cos(m * .pi * y)
              + b * cos(m * .pi * x) * cos(n * .pi * y)
    return value / span
}
