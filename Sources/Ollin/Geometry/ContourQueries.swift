import Foundation

// The questions an outline answers about itself: which way it runs at a
// fraction, where it passes closest to a point, the piece between two
// fractions, where it crosses another outline or itself, a lighter copy of a
// dense trace, and its corners rounded or cut. A contour holds points rather
// than curve segments, so every answer is worked out on the polyline.

public extension Contour {
    /// Where one outline meets another, or itself: the point, and how far
    /// along each of the two walks it sits.
    struct Crossing: Equatable, Sendable {
        /// Where the two outlines meet.
        public let point: Vector2
        /// The fraction (`0...1`, by walked length) along the contour that
        /// was asked, the same measure `point(at:)` takes.
        public let fraction: Double
        /// The fraction along the other outline. For a contour crossing
        /// itself, the second pass through the point, so it is always the
        /// larger of the two.
        public let otherFraction: Double
    }

    /// The direction of travel a fraction `t` (`0...1`, clamped) of the way
    /// along the contour, as a unit vector: the direction of the segment
    /// `point(at: t)` lands on. At a vertex it is the segment arriving there,
    /// and at `t = 0` the first one. A contour with no length answers `.zero`.
    func tangent(at t: Double) -> Vector2 {
        let walk = segments()
        guard let total = walk.last.map({ $0.start + $0.length }), total > 0 else {
            return .zero
        }
        let target = Swift.min(Swift.max(t, 0), 1) * total
        for segment in walk where target <= segment.start + segment.length {
            return segment.direction
        }
        return walk[walk.count - 1].direction
    }

    /// The tangent at `t` turned a quarter turn clockwise as the canvas shows
    /// it (`tangent(at: t).perpendicular`), so it points to the right of the
    /// direction of travel. For an outline running clockwise on the canvas
    /// that is inward; `reversed()` flips it.
    func normal(at t: Double) -> Vector2 {
        tangent(at: t).perpendicular
    }

    /// The point on the contour nearest to `point`, anywhere along a segment
    /// rather than only at a vertex. When two places are equally near, the
    /// earlier one along the walk wins. An empty contour answers `.zero`, as
    /// `point(at:)` does.
    func nearestPoint(to point: Vector2) -> Vector2 {
        nearest(to: point)?.point ?? points.first ?? .zero
    }

    /// The fraction (`0...1`, by walked length) at which the contour passes
    /// nearest to `point`, the inverse of `point(at:)`:
    /// `point(at: fraction(of: p))` is `nearestPoint(to: p)`. A contour with
    /// no length answers 0.
    func fraction(of point: Vector2) -> Double {
        nearest(to: point)?.fraction ?? 0
    }

    /// How far `point` is from the nearest place on the contour. A lone point
    /// measures to itself; an empty contour is infinitely far away.
    func distance(to point: Vector2) -> Double {
        if let hit = nearest(to: point) { return hit.point.distance(to: point) }
        return points.first.map { $0.distance(to: point) } ?? .infinity
    }

    /// The stretch of the contour between two fractions (each `0...1`,
    /// clamped), as an open contour that starts at `point(at: start)` and
    /// ends at `point(at: end)`, keeping every vertex in between.
    ///
    /// On a closed contour the piece always runs forward and wraps through the
    /// starting point when `end` is smaller than `start`, so
    /// `piece(from: 0.9, to: 0.1)` is the fifth of a ring around its seam, and
    /// `piece(from: 0, to: 1)` is the whole loop opened at its start. On an
    /// open contour an `end` before `start` walks backward, the piece reversed.
    func piece(from start: Double, to end: Double) -> Contour {
        let a = Swift.min(Swift.max(start, 0), 1)
        let b = Swift.min(Swift.max(end, 0), 1)
        let total = length
        guard points.count >= 2, total > 0 else {
            return Contour(points.first.map { [$0] } ?? [], closed: false)
        }
        if !isClosed && b < a {
            return piece(from: b, to: a).reversed()
        }
        var span = b - a
        if isClosed && span < 0 { span += 1 }
        let from = a * total, to = from + span * total
        // Each vertex sits at its walked distance; a closed loop is laid out
        // twice so a piece through the seam reads straight across it.
        var placed: [(at: Double, point: Vector2)] = []
        var walked = 0.0
        for (i, p) in points.enumerated() {
            if i > 0 { walked += (p - points[i - 1]).length }
            placed.append((walked, p))
        }
        if isClosed {
            placed += placed.map { ($0.at + total, $0.point) }
        }
        let margin = total * 1e-12
        var out = [point(at: a)]
        for vertex in placed where vertex.at > from + margin && vertex.at < to - margin {
            out.append(vertex.point)
        }
        out.append(isClosed && span == 1 ? out[0] : point(at: b))
        return Contour(out, closed: false)
    }

    /// Every place this contour meets `other`, sorted along this contour.
    /// Each carries the point and the fraction along both walks, so either
    /// outline can be cut there with `piece(from:to:)`. Outlines that run
    /// along each other in parallel share no single point and report nothing
    /// for that stretch; a touch counts the same as a crossing.
    func crossings(with other: Contour) -> [Crossing] {
        let mine = segments(), theirs = other.segments()
        guard let myTotal = mine.last.map({ $0.start + $0.length }), myTotal > 0,
              let theirTotal = theirs.last.map({ $0.start + $0.length }), theirTotal > 0
        else { return [] }
        var found: [Crossing] = []
        Contour.sweep(mine, theirs) { i, j in
            guard let hit = Contour.meet(mine[i], mine[i].isLast && !isClosed,
                                         theirs[j], theirs[j].isLast && !other.isClosed)
            else { return }
            found.append(Crossing(
                point: hit.point,
                fraction: (mine[i].start + hit.s * mine[i].length) / myTotal,
                otherFraction: (theirs[j].start + hit.u * theirs[j].length) / theirTotal))
        }
        return Contour.settled(found)
    }

    /// Every place the contour crosses itself, sorted along the walk. Each is
    /// reported once: `fraction` is the first pass through the point and
    /// `otherFraction` the second. Neighboring segments meeting at their
    /// shared vertex are not crossings, and a closed contour's return leg
    /// meets its first segment the same way.
    func crossings() -> [Crossing] {
        let walk = segments()
        guard let total = walk.last.map({ $0.start + $0.length }), total > 0,
              walk.count >= 3 || (walk.count == 2 && !isClosed) else { return [] }
        var found: [Crossing] = []
        let last = walk.count - 1
        Contour.sweep(walk, nil) { i, j in
            let (lo, hi) = (Swift.min(i, j), Swift.max(i, j))
            if hi - lo == 1 || (isClosed && lo == 0 && hi == last) { return }
            guard let hit = Contour.meet(walk[lo], walk[lo].isLast && !isClosed,
                                         walk[hi], walk[hi].isLast && !isClosed)
            else { return }
            found.append(Crossing(
                point: hit.point,
                fraction: (walk[lo].start + hit.s * walk[lo].length) / total,
                otherFraction: (walk[hi].start + hit.u * walk[hi].length) / total))
        }
        return Contour.settled(found)
    }

    /// A lighter copy that keeps only the points needed to stay within
    /// `tolerance` of the original (Ramer–Douglas–Peucker): every point of
    /// the original lies within `tolerance` of the simplified outline. A
    /// dense trace, like a mouse stroke or a traced edge, comes back as a few
    /// points along its straights and more where it bends. An open contour
    /// keeps both ends and a closed one keeps its first point.
    func simplified(tolerance: Double) -> Contour {
        guard points.count > 2 else { return self }
        let tolerance = Swift.max(tolerance, 0)
        guard isClosed else {
            return Contour(Contour.douglasPeucker(points, tolerance: tolerance), closed: false)
        }
        // Split the loop at the point farthest from the start, so each half is
        // an open run with two points that must stay.
        var far = 0, best = 0.0
        for (i, p) in points.enumerated() {
            let d = p.distanceSquared(to: points[0])
            if d > best { best = d; far = i }
        }
        guard far > 0 else { return Contour([points[0]], closed: true) }
        let there = Contour.douglasPeucker(Array(points[0...far]), tolerance: tolerance)
        let back = Contour.douglasPeucker(Array(points[far...]) + [points[0]],
                                          tolerance: tolerance)
        return Contour(there + back.dropFirst().dropLast(), closed: true)
    }

    /// The same outline walked the other way, keeping `isClosed`: the points
    /// in reverse order, as the collection's own `reversed()` walks them, but
    /// still a `Contour`. `reversed().point(at: t)` on an open contour is
    /// `point(at: 1 - t)`. Reversing a closed outline flips its winding,
    /// which is what turns an outline into a hole under the non-zero rule.
    func reversed() -> Contour {
        Contour(points.reversed(), closed: isClosed)
    }

    /// A copy with every corner rounded into an arc of `radius`, tangent to
    /// both edges. A corner is limited by its shorter neighboring edge: each
    /// edge lends at most half its length to a corner at either end (all of
    /// it to a corner beside an open contour's endpoint), so neighboring arcs
    /// meet rather than overlap, and a radius too large for a corner rounds
    /// it as far as its edges allow. An open contour keeps its two ends.
    func rounded(_ radius: Double) -> Contour {
        guard radius > 0 else { return self }
        // An arc of `radius` tangent to both edges touches each one this far
        // back from the corner.
        return trimmingCorners(wanted: { radius / tan($0 / 2) }) { corner, cut in
            let half = corner.angle / 2
            let arcRadius = cut * tan(half)
            let center = corner.vertex + corner.bisector * (cut / cos(half))
            let from = corner.inbound - center, to = corner.outbound - center
            let start = atan2(from.y, from.x)
            var sweep = atan2(to.y, to.x) - start
            if sweep > .pi { sweep -= 2 * .pi }
            if sweep < -.pi { sweep += 2 * .pi }
            // Enough steps that no chord strays a tenth of a unit off the arc.
            let step = arcRadius > 0.05 ? 2 * acos(1 - 0.1 / arcRadius) : .pi
            let steps = Swift.min(128, Swift.max(1, Int((abs(sweep) / step).rounded(.up))))
            var arc = [corner.inbound]
            for k in 1..<steps {
                let angle = start + sweep * Double(k) / Double(steps)
                arc.append(center + Vector2(cos(angle), sin(angle)) * arcRadius)
            }
            arc.append(corner.outbound)
            return arc
        }
    }

    /// A copy with every corner cut straight across, `size` back from the
    /// corner along each edge, so a square becomes an octagon. The same
    /// limit as `rounded(_:)` applies: each edge lends at most half its
    /// length to a corner. An open contour keeps its two ends.
    func chamfered(_ size: Double) -> Contour {
        guard size > 0 else { return self }
        return trimmingCorners(wanted: { _ in size }) { corner, _ in [corner.inbound, corner.outbound] }
    }
}

public extension Shape {
    /// A copy with every contour simplified to within `tolerance` (see
    /// `Contour.simplified(tolerance:)`), keeping the `winding` rule.
    func simplified(tolerance: Double) -> Shape {
        Shape(contours: contours.map { $0.simplified(tolerance: tolerance) }, winding: winding)
    }

    /// A copy with every corner of every contour rounded to `radius` (see
    /// `Contour.rounded(_:)`), keeping the `winding` rule.
    func rounded(_ radius: Double) -> Shape {
        Shape(contours: contours.map { $0.rounded(radius) }, winding: winding)
    }

    /// A copy with every corner of every contour cut `size` back (see
    /// `Contour.chamfered(_:)`), keeping the `winding` rule.
    func chamfered(_ size: Double) -> Shape {
        Shape(contours: contours.map { $0.chamfered(size) }, winding: winding)
    }
}

// MARK: - The walk the questions share

extension Contour {
    /// One straight piece of the walk: where it starts and ends, its length,
    /// its unit direction, and the length walked before it.
    struct Segment {
        let a: Vector2
        let b: Vector2
        let start: Double
        let length: Double
        let direction: Vector2
        /// The final segment of the walk, which owns its far end on an open
        /// contour (every other segment leaves its far end to the next).
        var isLast = false
    }

    /// The walk's segments in order, the return leg included when closed.
    /// A zero-length segment carries no direction and is left out, which is
    /// the same choice `point(at:)` makes.
    func segments() -> [Segment] {
        guard points.count >= 2 else { return [] }
        var out: [Segment] = []
        out.reserveCapacity(points.count)
        var walked = 0.0
        let count = isClosed ? points.count : points.count - 1
        for i in 0..<count {
            let a = points[i], b = points[(i + 1) % points.count]
            let d = (b - a).length
            if d > 0 {
                out.append(Segment(a: a, b: b, start: walked, length: d, direction: (b - a) / d))
            }
            walked += d
        }
        if !out.isEmpty { out[out.count - 1].isLast = true }
        return out
    }

    /// The nearest place on the walk to `point`, with the fraction it sits at.
    func nearest(to point: Vector2) -> (point: Vector2, fraction: Double)? {
        let walk = segments()
        guard let total = walk.last.map({ $0.start + $0.length }), total > 0 else { return nil }
        var best = Double.infinity
        var hit = (point: walk[0].a, fraction: 0.0)
        for segment in walk {
            let along = Swift.min(Swift.max((point - segment.a).dot(segment.direction), 0),
                                  segment.length)
            let q = segment.a + segment.direction * along
            let d = q.distanceSquared(to: point)
            if d < best {
                best = d
                hit = (q, (segment.start + along) / total)
            }
        }
        return hit
    }

    /// Where two segments meet, as the point and the parameter along each
    /// (`0...1`). Each segment owns its start and not its far end, so a
    /// crossing exactly at a vertex is found once, not by both segments that
    /// meet there; `ownsEnd` hands the far end to an open contour's last one.
    /// Parallel segments share no single point and answer nil.
    static func meet(_ p: Segment, _ pOwnsEnd: Bool,
                     _ q: Segment, _ qOwnsEnd: Bool) -> (point: Vector2, s: Double, u: Double)? {
        let r = p.b - p.a, v = q.b - q.a
        let denominator = r.cross(v)
        guard abs(denominator) > 1e-12 * p.length * q.length else { return nil }
        let gap = q.a - p.a
        let s = gap.cross(v) / denominator
        let u = gap.cross(r) / denominator
        guard s >= 0, pOwnsEnd ? s <= 1 : s < 1,
              u >= 0, qOwnsEnd ? u <= 1 : u < 1 else { return nil }
        return (p.a + r * s, s, u)
    }

    /// Sweep and prune along x: every pair of segments whose x extents
    /// overlap is handed to `test` once, as indices into `first` and `second`
    /// (or twice into `first` when `second` is nil, for a walk against
    /// itself). Pairs far apart on the page never meet the segment test.
    static func sweep(_ first: [Segment], _ second: [Segment]?, _ test: (Int, Int) -> Void) {
        struct Entry { let low: Double, high: Double, lowY: Double, highY: Double
                       let index: Int, isSecond: Bool }
        func entry(_ s: Segment, _ i: Int, _ isSecond: Bool) -> Entry {
            Entry(low: Swift.min(s.a.x, s.b.x), high: Swift.max(s.a.x, s.b.x),
                  lowY: Swift.min(s.a.y, s.b.y), highY: Swift.max(s.a.y, s.b.y),
                  index: i, isSecond: isSecond)
        }
        var entries = first.indices.map { entry(first[$0], $0, false) }
        if let second { entries += second.indices.map { entry(second[$0], $0, true) } }
        entries.sort { $0.low < $1.low || ($0.low == $1.low && $0.index < $1.index) }
        var active: [Entry] = []
        for current in entries {
            active.removeAll { $0.high < current.low }
            for other in active where other.highY >= current.lowY && other.lowY <= current.highY {
                if second == nil {
                    test(other.index, current.index)
                } else if other.isSecond != current.isSecond {
                    other.isSecond ? test(current.index, other.index) : test(other.index, current.index)
                }
            }
            active.append(current)
        }
    }

    /// Crossings sorted along the asking contour, with the rare double report
    /// of one point (a crossing that lands on a vertex, measured just short of
    /// it by one segment and just past it by the next) folded into one.
    static func settled(_ found: [Crossing]) -> [Crossing] {
        let sorted = found.sorted {
            $0.fraction != $1.fraction ? $0.fraction < $1.fraction : $0.otherFraction < $1.otherFraction
        }
        var out: [Crossing] = []
        for crossing in sorted {
            if let previous = out.last,
               abs(previous.fraction - crossing.fraction) < 1e-9,
               abs(previous.otherFraction - crossing.otherFraction) < 1e-9 { continue }
            out.append(crossing)
        }
        return out
    }

    /// Ramer–Douglas–Peucker over an open run, measuring each point against
    /// the *segment* between the two kept ends rather than the line through
    /// them, so a run that doubles back past an end still keeps the point
    /// where it turned. Iterative, so a long trace cannot exhaust the stack.
    static func douglasPeucker(_ run: [Vector2], tolerance: Double) -> [Vector2] {
        guard run.count > 2 else { return run }
        var keep = [Bool](repeating: false, count: run.count)
        keep[0] = true
        keep[run.count - 1] = true
        var spans = [(0, run.count - 1)]
        while let (first, last) = spans.popLast() {
            guard last - first > 1 else { continue }
            var farthest = -1.0, index = first
            for i in (first + 1)..<last {
                let d = segmentDistance(run[i], run[first], run[last])
                if d > farthest { farthest = d; index = i }
            }
            if farthest > tolerance {
                keep[index] = true
                spans.append((first, index))
                spans.append((index, last))
            }
        }
        return run.indices.compactMap { keep[$0] ? run[$0] : nil }
    }

    /// How far `p` is from the segment `a`–`b`.
    static func segmentDistance(_ p: Vector2, _ a: Vector2, _ b: Vector2) -> Double {
        let ab = b - a
        let lengthSquared = ab.dot(ab)
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = Swift.min(Swift.max((p - a).dot(ab) / lengthSquared, 0), 1)
        return p.distance(to: a + ab * t)
    }

    /// One corner of the outline, for the corner edits: the vertex, the unit
    /// directions back along each edge, the angle between them, their
    /// bisector, and the two points the cut lands on.
    struct Corner {
        let vertex: Vector2
        let angle: Double
        let bisector: Vector2
        let inbound: Vector2
        let outbound: Vector2
    }

    /// Replaces each corner with the points `shape` returns for it. How far
    /// back along each edge the corner is cut is `wanted(angle)`, capped by
    /// the edges; the angle is the one between the two edges at the vertex.
    /// A straight run through a vertex, and an edge doubling back on itself,
    /// are left as they are.
    func trimmingCorners(wanted: (_ angle: Double) -> Double,
                         _ shape: (_ corner: Corner, _ cut: Double) -> [Vector2]) -> Contour {
        // Repeated points carry no edge, so fold them first.
        var run: [Vector2] = []
        for p in points where run.last.map({ $0.distance(to: p) > 1e-12 }) ?? true {
            run.append(p)
        }
        if isClosed, run.count > 1, run[0].distance(to: run[run.count - 1]) <= 1e-12 {
            run.removeLast()
        }
        let n = run.count
        guard n >= 3 else { return self }
        var out: [Vector2] = []
        for i in 0..<n {
            let isEnd = !isClosed && (i == 0 || i == n - 1)
            if isEnd { out.append(run[i]); continue }
            let previous = run[(i + n - 1) % n], next = run[(i + 1) % n]
            let back = previous - run[i], ahead = next - run[i]
            let backLength = back.length, aheadLength = ahead.length
            let u = back / backLength, w = ahead / aheadLength
            let angle = acos(Swift.min(Swift.max(u.dot(w), -1), 1))
            guard angle > 1e-6, angle < .pi - 1e-6 else { out.append(run[i]); continue }
            // An edge lends half its length to each corner it runs between,
            // or all of it when its other end is an open contour's endpoint.
            let backShare = !isClosed && i == 1 ? 1.0 : 0.5
            let aheadShare = !isClosed && i == n - 2 ? 1.0 : 0.5
            let limit = Swift.min(backLength * backShare, aheadLength * aheadShare)
            let cut = Swift.min(wanted(angle), limit)
            let corner = Corner(vertex: run[i], angle: angle, bisector: (u + w).normalized,
                                inbound: run[i] + u * cut, outbound: run[i] + w * cut)
            // Two cuts that use up an edge between them meet at one point.
            for p in shape(corner, cut) where out.last.map({ $0.distance(to: p) > 1e-9 }) ?? true {
                out.append(p)
            }
        }
        if isClosed, out.count > 1, out[0].distance(to: out[out.count - 1]) <= 1e-9 {
            out.removeLast()
        }
        return Contour(out, closed: isClosed)
    }
}
