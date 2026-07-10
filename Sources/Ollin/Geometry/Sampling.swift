import Foundation

/// Low-discrepancy (quasi-random) sampling: point sets that cover a region
/// *evenly* without ever looking gridded. Plain `random` scatter clumps and
/// leaves holes; a low-discrepancy sequence fills space so uniformly that the
/// first N points are always a fair covering of the whole region, and adding
/// more points only refines it (no point ever moves).
///
/// That *prefix property* is what separates these from `poissonDisk`: a
/// Poisson-disk set is one fixed layout for one radius, while a Halton or Sobol
/// sequence is an ordered stream you can cut anywhere. Take 100 points for a
/// draft and 10,000 for the final render, and the first 100 are the same points.
/// They're also fully deterministic; no seed, no rng: index in, point out.
///
/// ```swift
/// let dots = haltonPoints(count: 500)        // even coverage, organic look
/// let finer = haltonPoints(count: 5000)      // same 500, plus 4500 more
/// ```
///
/// Two classic sequences are provided: `haltonPoints` (radical-inverse digits
/// in coprime bases, the simplest construction) and `sobolPoints` (binary
/// direction numbers: even better distributed, with a subtle dyadic structure).

// MARK: - Halton

/// The radical inverse of `index` in `base`, the scalar building block of the
/// Halton sequence. Writes `index` in `base`'s digits, then mirrors them across
/// the decimal point: in base 2, indices 1, 2, 3, 4… map to 1/2, 1/4, 3/4,
/// 1/8…, each new point landing in the largest gap left by the ones before.
///
/// Use it directly for a 1D low-discrepancy stream (spacing hues, offsetting
/// phases); `haltonPoints` pairs two bases for 2D.
///
/// - Parameters:
///   - index: The position in the sequence (1-based in practice; index 0 is 0).
///   - base: The digit base; pair *coprime* bases across dimensions.
/// - Returns: A value in [0, 1).
public func halton(_ index: Int, base: Int = 2) -> Double {
    guard index > 0, base >= 2 else { return 0 }
    var i = index
    var fraction = 1.0
    var result = 0.0
    while i > 0 {
        fraction /= Double(base)
        result += fraction * Double(i % base)
        i /= base
    }
    return result
}

/// The first `count` points of the 2D Halton sequence, scaled into `bounds`:
/// an even-but-unstructured covering in which every prefix is itself evenly
/// spread. Deterministic (no seed, no rng), so the same call always yields
/// the same points, and a longer run begins with the same ones.
///
/// ```swift
/// for (i, p) in haltonPoints(count: 800, in: bounds).enumerated() {
///     drawCircle(center: p, radius: 3 + Double(i % 5))
/// }
/// ```
///
/// The two dimensions use coprime `bases` (2 and 3 by default, the canonical
/// pair; non-coprime bases correlate the axes and the points fall on lines).
/// `startIndex` defaults to 1 because index 0 of every Halton sequence is
/// exactly 0: a point pinned in the corner.
///
/// - Parameters:
///   - count: How many points to emit.
///   - bounds: The rectangle to fill.
///   - bases: The per-axis digit bases; keep them coprime.
///   - startIndex: The sequence index of the first point emitted.
/// - Returns: Points in sequence order.
public func haltonPoints(count: Int,
                         in bounds: Rectangle,
                         bases: (Int, Int) = (2, 3),
                         startIndex: Int = 1) -> [Vector2] {
    guard count > 0 else { return [] }
    let start = Swift.max(startIndex, 0)
    var points: [Vector2] = []
    points.reserveCapacity(count)
    for index in start ..< start + count {
        points.append(Vector2(bounds.x + halton(index, base: bases.0) * bounds.width,
                              bounds.y + halton(index, base: bases.1) * bounds.height))
    }
    return points
}

// MARK: - Sobol

/// The first `count` points of the 2D Sobol sequence, scaled into `bounds`.
/// Like `haltonPoints` it's an ordered, deterministic stream whose every prefix
/// covers the region evenly, but its binary construction distributes even more
/// uniformly: every aligned power-of-two block of the sequence lands exactly
/// one point in each cell of the matching power-of-two grid.
///
/// ```swift
/// drawPoints(sobolPoints(count: 2000), size: 3)
/// ```
///
/// `startIndex` defaults to 1 because index 0 is exactly the corner point
/// (0, 0). Generated with the standard Gray-code stepping, so consecutive
/// points differ by a single direction number and the whole stream is O(1)
/// per point.
///
/// - Parameters:
///   - count: How many points to emit.
///   - bounds: The rectangle to fill.
///   - startIndex: The sequence index of the first point emitted.
/// - Returns: Points in sequence order.
public func sobolPoints(count: Int,
                        in bounds: Rectangle,
                        startIndex: Int = 1) -> [Vector2] {
    guard count > 0 else { return [] }
    let start = Swift.max(startIndex, 0)

    // 32-bit direction numbers. The first dimension is the van der Corput
    // sequence (all m_k = 1); the second follows the degree-1 primitive
    // polynomial x + 1, whose recurrence is m_k = (2·m_{k-1}) XOR m_{k-1},
    // giving m = 1, 3, 5, 15, 17, 51, 85, 255, …
    var v1 = [UInt32](repeating: 0, count: 32)
    var v2 = [UInt32](repeating: 0, count: 32)
    var m: UInt32 = 1
    for k in 0 ..< 32 {
        v1[k] = 1 << (31 - k)
        v2[k] = m << UInt32(31 - k)
        m = (m << 1) ^ m
    }

    var points: [Vector2] = []
    points.reserveCapacity(count)
    var x: UInt32 = 0
    var y: UInt32 = 0
    for i in 0 ..< start + count {
        if i >= start {
            points.append(Vector2(bounds.x + Double(x) * 0x1p-32 * bounds.width,
                                  bounds.y + Double(y) * 0x1p-32 * bounds.height))
        }
        // Gray-code step: flip the direction number of i's lowest zero bit.
        let c = (~UInt32(truncatingIfNeeded: i)).trailingZeroBitCount
        x ^= v1[c]
        y ^= v2[c]
    }
    return points
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The first `count` points of the 2D Halton sequence over `bounds` (the
    /// whole canvas by default): even-but-organic coverage in which any prefix
    /// of the stream is itself evenly spread. 100 points for a draft, 10,000
    /// for the final, and the first 100 never move. Deterministic, no seed.
    func haltonPoints(count: Int,
                      in bounds: Rectangle? = nil,
                      bases: (Int, Int) = (2, 3),
                      startIndex: Int = 1) -> [Vector2] {
        Ollin.haltonPoints(count: count,
                           in: bounds ?? canvasRectangle,
                           bases: bases,
                           startIndex: startIndex)
    }

    /// The first `count` points of the 2D Sobol sequence over `bounds` (the
    /// whole canvas by default), the more uniform sibling of `haltonPoints`,
    /// with the same cut-anywhere prefix property. Deterministic, no seed.
    func sobolPoints(count: Int,
                     in bounds: Rectangle? = nil,
                     startIndex: Int = 1) -> [Vector2] {
        Ollin.sobolPoints(count: count,
                          in: bounds ?? canvasRectangle,
                          startIndex: startIndex)
    }
}
