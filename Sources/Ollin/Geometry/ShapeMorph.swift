import Foundation

/// A prepared blend from one `Shape` to another: build it once, then read the
/// in-between shape at any fraction with `shape(at:)`.
///
/// Morphing two outlines means deciding which point of one becomes which point
/// of the other. `ShapeMorph` works that correspondence out up front, per
/// contour: it matches closed outlines with closed outlines and open line-work
/// with open line-work (largest with largest, the rest by nearest center),
/// gives both sides of each match the same number of points (adding points
/// along segments, so every original corner survives), lines their windings
/// up, and picks the starting point that keeps the total travel shortest. A
/// contour with no partner shrinks to its own center, or grows out of one, so
/// mismatched counts cross-fade instead of popping.
///
/// Every in-between is a real `Shape`: fill it, stroke it, run it through the
/// booleans, hatch it, or export it as vectors like any other geometry. At
/// `t <= 0` and `t >= 1` the read returns the exact original shapes. There is
/// no randomness anywhere, so the same pair always morphs the same way.
///
/// For per-frame animation, hold the `ShapeMorph` and read it with a moving
/// `t` (`loopProgress(over:)`, an eased value, a `Timeline`'s progress).
/// `Shape` is also `Tweenable`, so a `Timeline<Shape>` tweens geometry
/// directly; that convenience rebuilds the correspondence each read, which is
/// fine for simple shapes and worth replacing with a held `ShapeMorph` when
/// the outlines get heavy.
public struct ShapeMorph: Sendable, Equatable {
    /// The shape at `t == 0`, exactly as given.
    public let from: Shape
    /// The shape at `t == 1`, exactly as given.
    public let to: Shape

    /// One matched contour pair: two equal-length point runs whose `i`-th
    /// points correspond, ready for a straight lerp.
    private struct Pair: Sendable, Equatable {
        var a: [Vector2]
        var b: [Vector2]
        var isClosed: Bool
    }

    private var pairs: [Pair]

    /// Prepare the blend. `spacing` bounds how far apart correspondence
    /// points may sit along either outline (extra points are added along
    /// segments longer than that); leave it `nil` to derive a spacing from
    /// the outlines' own lengths. Smaller spacing follows curved stretches
    /// more faithfully and costs more points; the point count is capped so a
    /// tiny spacing cannot run away.
    public init(from: Shape, to: Shape, spacing: Double? = nil) {
        self.from = from
        self.to = to

        let source = from.contours.filter { !$0.points.isEmpty }
        var target = to.contours.filter { !$0.points.isEmpty }

        // Blending a clockwise outline toward a counter-clockwise one twists
        // through itself halfway. If the dominant outlines disagree, reverse
        // every target contour: reversing all of them flips the orientations
        // without changing what either fill rule fills.
        if let sa = dominantSignedArea(source),
           let ta = dominantSignedArea(target),
           sa * ta < 0 {
            target = target.map { Contour($0.points.reversed(), closed: $0.isClosed) }
        }

        let closedPairs = Self.matchGroup(source.filter { $0.isClosed },
                                          target.filter { $0.isClosed },
                                          closed: true, spacing: spacing)
        let openPairs = Self.matchGroup(source.filter { !$0.isClosed },
                                        target.filter { !$0.isClosed },
                                        closed: false, spacing: spacing)
        pairs = closedPairs + openPairs
    }

    /// The blended shape a fraction `t` (`0...1`, clamped) of the way from
    /// `from` to `to`. `0` and `1` return the originals untouched; everything
    /// between is the pointwise blend along each matched pair. When the two
    /// shapes fill by different winding rules, the blend switches rules at
    /// the halfway mark.
    public func shape(at t: Double) -> Shape {
        let t = min(max(t, 0), 1)
        if t <= 0 { return from }
        if t >= 1 { return to }
        let contours = pairs.map { pair in
            Contour(zip(pair.a, pair.b).map { $0.lerp(to: $1, t) },
                    closed: pair.isClosed)
        }
        return Shape(contours: contours,
                     winding: t < 0.5 ? from.winding : to.winding)
    }

    // MARK: - Correspondence

    /// Match one closedness group: biggest with biggest, then each following
    /// contour with the nearest unused partner by center. Leftovers on either
    /// side pair against a run of their own center point, so lerping them
    /// scales the contour down to nothing (or up from it).
    private static func matchGroup(_ a: [Contour], _ b: [Contour],
                                   closed: Bool, spacing: Double?) -> [Pair] {
        // Prominence order: closed contours by enclosed area, open ones by
        // walked length. Ties keep the original contour order.
        func prominenceOrder(_ contours: [Contour]) -> [Int] {
            let keys = contours.map { closed ? abs(signedArea(ring(of: $0))) : $0.length }
            return contours.indices.sorted {
                keys[$0] != keys[$1] ? keys[$0] > keys[$1] : $0 < $1
            }
        }
        let aOrder = prominenceOrder(a)
        var bRemaining = prominenceOrder(b)
        var pairs: [Pair] = []

        for (rank, ai) in aOrder.enumerated() {
            guard !bRemaining.isEmpty else {
                pairs.append(collapsePair(a[ai], closed: closed, spacing: spacing, growing: false))
                continue
            }
            let pick: Int
            if rank == 0 {
                pick = 0 // the two most prominent contours always pair up
            } else {
                let center = a[ai].points.centroid ?? .zero
                var best = 0
                var bestDist = Double.infinity
                for (slot, bi) in bRemaining.enumerated() {
                    let d = ((b[bi].points.centroid ?? .zero) - center).lengthSquared
                    if d < bestDist { bestDist = d; best = slot }
                }
                pick = best
            }
            let bi = bRemaining.remove(at: pick)
            pairs.append(makePair(a[ai], b[bi], closed: closed, spacing: spacing))
        }
        for bi in bRemaining {
            pairs.append(collapsePair(b[bi], closed: closed, spacing: spacing, growing: true))
        }
        return pairs
    }

    /// Build the aligned point runs for one matched contour pair.
    private static func makePair(_ a: Contour, _ b: Contour,
                                 closed: Bool, spacing: Double?) -> Pair {
        var ra = ring(of: a)
        var rb = ring(of: b)
        ra = densified(ra, spacing: resolvedSpacing(ra, closed: closed, requested: spacing), closed: closed)
        rb = densified(rb, spacing: resolvedSpacing(rb, closed: closed, requested: spacing), closed: closed)
        if ra.count < rb.count {
            ra = withAddedPoints(ra, adding: rb.count - ra.count, closed: closed)
        } else if rb.count < ra.count {
            rb = withAddedPoints(rb, adding: ra.count - rb.count, closed: closed)
        }
        if closed {
            let offset = bestRotation(ra, rb)
            if offset > 0 { rb = Array(rb[offset...]) + Array(rb[..<offset]) }
        } else {
            // An open run has no rotation to choose, only a direction.
            var straight = 0.0
            var reversed = 0.0
            for i in ra.indices {
                straight += (ra[i] - rb[i]).lengthSquared
                reversed += (ra[i] - rb[rb.count - 1 - i]).lengthSquared
            }
            if reversed < straight { rb.reverse() }
        }
        return Pair(a: ra, b: rb, isClosed: closed)
    }

    /// A pair that scales `contour` to (or from) its own center point.
    private static func collapsePair(_ contour: Contour, closed: Bool,
                                     spacing: Double?, growing: Bool) -> Pair {
        var run = ring(of: contour)
        run = densified(run, spacing: resolvedSpacing(run, closed: closed, requested: spacing), closed: closed)
        let center = Array(repeating: run.centroid ?? .zero, count: run.count)
        return growing
            ? Pair(a: center, b: run, isClosed: contour.isClosed)
            : Pair(a: run, b: center, isClosed: contour.isClosed)
    }

    /// The correspondence spacing for one outline: the requested one, else
    /// 1/128 of its own length, floored so no run can exceed ~4096 points.
    /// Deriving it per outline keeps added points spread at even fractions
    /// along each side of a match even when their lengths differ, so the
    /// count equalizer only ever tops up a small remainder.
    private static func resolvedSpacing(_ run: [Vector2],
                                        closed: Bool, requested: Double?) -> Double {
        let total = perimeter(run, closed: closed)
        guard total > 0 else { return 0 }
        let chosen = requested.flatMap { $0 > 0 ? $0 : nil } ?? total / 128
        return max(chosen, total / 4096)
    }
}

// MARK: - Tweenable geometry

extension Shape: Tweenable {
    /// The morphed in-between (see `ShapeMorph`). This convenience rebuilds
    /// the point correspondence on every call, which suits simple outlines; a
    /// held `ShapeMorph` pays that cost once for per-frame work.
    public static func lerp(_ a: Shape, _ b: Shape, _ t: Double) -> Shape {
        ShapeMorph(from: a, to: b).shape(at: t)
    }
}

extension Contour: Tweenable {
    /// The morphed in-between of two lone contours (see `ShapeMorph`).
    public static func lerp(_ a: Contour, _ b: Contour, _ t: Double) -> Contour {
        ShapeMorph(from: Shape(contours: [a]), to: Shape(contours: [b]))
            .shape(at: t).contours.first ?? a
    }
}

public extension Shape {
    /// The shape a fraction `t` of the way toward `other`, as a one-off. For
    /// per-frame animation build a `ShapeMorph` once and read `shape(at:)`,
    /// which skips redoing the correspondence every frame.
    func morphed(toward other: Shape, _ t: Double, spacing: Double? = nil) -> Shape {
        ShapeMorph(from: self, to: other, spacing: spacing).shape(at: t)
    }
}

// MARK: - Ring helpers

/// A contour's points as a plain run, dropping a duplicated closing point.
private func ring(of contour: Contour) -> [Vector2] {
    var points = contour.points
    if contour.isClosed, points.count > 1, points.first == points.last {
        points.removeLast()
    }
    return points
}

/// The signed area of the polygon: positive for one winding direction,
/// negative for the other, zero for degenerate runs.
private func signedArea(_ points: [Vector2]) -> Double {
    guard points.count >= 3 else { return 0 }
    var sum = 0.0
    for i in points.indices {
        let p = points[i]
        let q = points[(i + 1) % points.count]
        sum += p.x * q.y - q.x * p.y
    }
    return sum / 2
}

/// The signed area of the largest closed contour, or `nil` when there is no
/// usable closed contour to read an orientation from.
private func dominantSignedArea(_ contours: [Contour]) -> Double? {
    var best: Double?
    for contour in contours where contour.isClosed {
        let area = signedArea(ring(of: contour))
        if best == nil || abs(area) > abs(best!) { best = area }
    }
    guard let area = best, area != 0 else { return nil }
    return area
}

private func perimeter(_ run: [Vector2], closed: Bool) -> Double {
    guard run.count > 1 else { return 0 }
    var total = 0.0
    for i in 1 ..< run.count { total += (run[i] - run[i - 1]).length }
    if closed { total += (run[0] - run[run.count - 1]).length }
    return total
}

/// The run with extra points added along any segment longer than `spacing`,
/// keeping every original point (corners survive).
private func densified(_ run: [Vector2], spacing: Double, closed: Bool) -> [Vector2] {
    guard run.count >= 2, spacing > 0 else { return run }
    var out: [Vector2] = []
    let segments = closed ? run.count : run.count - 1
    for i in 0 ..< segments {
        let p = run[i]
        let q = run[(i + 1) % run.count]
        out.append(p)
        let pieces = Int(((q - p).length / spacing).rounded(.up))
        if pieces > 1 {
            for c in 1 ..< pieces {
                out.append(p.lerp(to: q, Double(c) / Double(pieces)))
            }
        }
    }
    if !closed { out.append(run[run.count - 1]) }
    return out
}

/// The run with exactly `adding` extra points, placed by repeatedly splitting
/// whichever segment currently has the longest pieces (earliest wins ties, so
/// the result is deterministic).
private func withAddedPoints(_ run: [Vector2], adding: Int, closed: Bool) -> [Vector2] {
    guard adding > 0 else { return run }
    guard run.count >= 2 else {
        return Array(repeating: run.first ?? .zero, count: run.count + adding)
    }
    let segments = closed ? run.count : run.count - 1
    let lengths = (0 ..< segments).map { (run[($0 + 1) % run.count] - run[$0]).length }
    var splits = Array(repeating: 0, count: segments)
    for _ in 0 ..< adding {
        var best = 0
        var bestPiece = -1.0
        for s in 0 ..< segments {
            let piece = lengths[s] / Double(splits[s] + 1)
            if piece > bestPiece { best = s; bestPiece = piece }
        }
        splits[best] += 1
    }
    var out: [Vector2] = []
    for s in 0 ..< segments {
        let p = run[s]
        let q = run[(s + 1) % run.count]
        out.append(p)
        if splits[s] > 0 {
            for c in 1 ... splits[s] {
                out.append(p.lerp(to: q, Double(c) / Double(splits[s] + 1)))
            }
        }
    }
    if !closed { out.append(run[run.count - 1]) }
    return out
}

/// The cyclic offset of `b` that minimizes the summed squared distance to
/// `a`, tried exhaustively (ties keep the smallest offset).
private func bestRotation(_ a: [Vector2], _ b: [Vector2]) -> Int {
    let n = a.count
    guard n > 0, b.count == n else { return 0 }
    var best = 0
    var bestSum = Double.infinity
    for offset in 0 ..< n {
        var sum = 0.0
        for i in 0 ..< n {
            sum += (a[i] - b[(i + offset) % n]).lengthSquared
            if sum >= bestSum { break }
        }
        if sum < bestSum {
            bestSum = sum
            best = offset
        }
    }
    return best
}
