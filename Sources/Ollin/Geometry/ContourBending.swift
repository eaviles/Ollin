import Foundation

// Bending an outline: the edits that move a contour's points as a whole,
// rather than answering a question about them. An outline is bent along a
// curve, pulled toward a point with its ends held, cut where it turns
// sharply, and traced into a few cubic curves. The corner-keeping smoothing
// lives beside the plain one in ClassicCurves.swift, since it shares that
// file's kernel. A contour holds points, so every edit works on the polyline
// and hands back points; the fit is the one edit that returns curves.

public extension Contour {
    /// A copy bent so that it follows `target` the way it followed `base`:
    /// lettering laid along a straight baseline bends along a wave, a row of
    /// tiles wraps round a ring. Every point is read against `base` as a
    /// fraction along it and an offset from it (how far along, how far to
    /// the side), and is put back at the same fraction and offset along
    /// `target`. A base and target that are the same curve give the outline
    /// back unchanged, and a point past an open base's end carries on past
    /// the target's end in its final direction.
    ///
    /// The fraction is what maps, so an outline laid along the whole base
    /// stretches to the whole target: a short baseline onto a long wave
    /// widens the letters. To keep their size, give the base the target's
    /// length (`target.length`). The side offset keeps its size, so tall
    /// letters stay tall and a tight bend on the target folds the far side
    /// of what crosses it.
    ///
    /// ```swift
    /// let word = textToShapes("ollin", 100, 540)
    /// let baseline = Contour([Vector2(100, 540), Vector2(980, 540)], closed: false)
    /// let wave = Contour(curveThrough: (0 ... 10).map { i in
    ///     Vector2(100 + Double(i) * 88, 540 + 60 * sin(Double(i) * 0.9 + time))
    /// }, closed: false)
    /// for glyph in word { drawShape(glyph.warped(from: baseline, along: wave)) }
    /// ```
    ///
    /// The direction of travel along a polyline is smoothed through its
    /// vertices, so a target traced from a few points still bends what
    /// crosses it without a step at each vertex. Straight runs of the outline
    /// are given extra points first, so a straight edge bends instead of
    /// staying straight between its two ends; `spacing` is the longest
    /// straight stretch left (0 keeps the points as they are). Every original
    /// point stays, so corners survive. A base or target of no length returns
    /// the outline unchanged.
    func warped(from base: Contour, along target: Contour, spacing: Double = 4) -> Contour {
        guard let baseWalk = Walk(base), let targetWalk = Walk(target) else { return self }
        let dense = refined(maxSegment: spacing)
        let scale = targetWalk.total / baseWalk.total
        let out = dense.points.map { p -> Vector2 in
            let hit = baseWalk.nearest(to: p)
            let frame = baseWalk.frame(atDistance: hit.distance)
            let offset = p - frame.point
            let along = offset.dot(frame.tangent), across = offset.dot(frame.normal)
            let landing = targetWalk.frame(atDistance: hit.distance * scale)
            return landing.point + landing.tangent * along + landing.normal * across
        }
        return Contour(out, closed: isClosed)
    }

    /// A copy with the part of the outline near `point` drawn toward it: a
    /// tug on one side of a blob, a rope caught at one place. Each point
    /// moves toward `point` by `amount` of its distance, weighted by how near
    /// it is: full weight at the point, fading smoothly to none at `radius`,
    /// so the pull makes a bump rather than a kink. An open contour's two
    /// ends stay where they are, and the pull fades out over `radius` of walk
    /// on the way to each, so a rope pulled near its end still ends where it
    /// did. `amount` 1 brings the nearest points all the way, 0.5 halfway, and
    /// a negative amount pushes away.
    ///
    /// ```swift
    /// let blob = Contour(curveThrough: ring, closed: true)
    /// drawShape(Shape(contours: [blob.pulled(toward: mouse, amount: 0.6, radius: 200)]))
    /// ```
    ///
    /// Straight runs are given extra points first so the bump is smooth;
    /// `spacing` is the longest straight stretch left (0 keeps the points as
    /// they are). A radius of zero or less, or an amount of zero, returns the
    /// outline unchanged.
    func pulled(toward point: Vector2, amount: Double, radius: Double, spacing: Double = 4) -> Contour {
        guard radius > 0, amount != 0, points.count >= 2 else { return self }
        let dense = refined(maxSegment: spacing)
        let total = dense.length
        var out = dense.points
        var walked = 0.0
        for i in out.indices {
            if i > 0 { walked += dense.points[i].distance(to: dense.points[i - 1]) }
            let p = out[i]
            let d = p.distance(to: point)
            guard d < radius else { continue }
            let q = 1 - (d / radius) * (d / radius)
            var weight = q * q
            if !isClosed {
                let toEnd = Swift.min(walked, total - walked)
                let taper = Swift.min(1, Swift.max(0, toEnd / radius))
                weight *= taper * taper * (3 - 2 * taper)
            }
            out[i] = p + (point - p) * (amount * weight)
        }
        return Contour(out, closed: isClosed)
    }

    /// The outline cut into open pieces at its corners: every place it turns
    /// by more than `angle` (radians). A dense trace from the hand or a traced
    /// edge turns gradually round a corner, a few degrees at each of several
    /// points, so `span` says how far back and ahead along the walk the turn
    /// is measured (0 reads the two neighboring points). Points above the
    /// angle within `span` of each other along the walk count as one corner,
    /// cut at the sharpest of them.
    ///
    /// Neighboring pieces share the corner point, and each is open whatever
    /// the contour was. A closed outline with `k` corners gives `k` pieces,
    /// the first starting at the first corner; an open one gives `k + 1`,
    /// the first starting where it did. An outline with no corner over the
    /// angle comes back whole, as the one element. The same corner test, read
    /// at the neighboring points, is what `smoothed(neighbors:keepingCornersOver:)`
    /// keeps, and `simplified(tolerance:)` first pulls a trace's gradual
    /// corners onto single points.
    ///
    /// ```swift
    /// let pieces = trace.split(atCornersOver: .pi / 3, span: 12)
    /// for (i, piece) in pieces.enumerated() {
    ///     stroke(i.isMultiple(of: 2) ? .black : .red)
    ///     drawPolyline(piece.points)
    /// }
    /// ```
    func split(atCornersOver angle: Double, span: Double = 0) -> [Contour] {
        let n = points.count
        guard n >= 3, let walk = Walk(self) else { return [self] }
        // Where each original point sits along the walk, repeats sharing a place.
        var place = [Double](repeating: 0, count: n)
        for i in 1 ..< n { place[i] = place[i - 1] + points[i].distance(to: points[i - 1]) }

        // The turn at each point: between the two neighboring points, or
        // between the places `span` back and ahead along the walk.
        var bend = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            if !isClosed && (i == 0 || i == n - 1) { continue }
            let back: Vector2, ahead: Vector2
            if span > 0 {
                back = points[i] - walk.point(atDistance: place[i] - span)
                ahead = walk.point(atDistance: place[i] + span) - points[i]
            } else {
                guard let p = previousDistinct(i), let q = nextDistinct(i) else { continue }
                back = points[i] - p
                ahead = q - points[i]
            }
            guard back.lengthSquared > 1e-18, ahead.lengthSquared > 1e-18 else { continue }
            bend[i] = acos(Swift.min(Swift.max(back.normalized.dot(ahead.normalized), -1), 1))
        }

        // Runs of points over the angle and within `span` of each other
        // along the walk are one corner, cut at the sharpest.
        var cuts: [Int] = []
        var runStart = -1, runPeak = -1, runLast = 0.0
        func closeRun() {
            if runStart >= 0 { cuts.append(runPeak) }
            runStart = -1
        }
        for i in 0 ..< n where bend[i] > angle {
            if runStart >= 0, place[i] - runLast <= span {
                if bend[i] > bend[runPeak] { runPeak = i }
            } else {
                closeRun()
                runStart = i
                runPeak = i
            }
            runLast = place[i]
        }
        closeRun()
        // On a closed walk a corner may straddle the seam: fold the last run
        // into the first when they touch through it.
        if isClosed, cuts.count >= 2, let first = cuts.first, let last = cuts.last,
           first != last, place[first] + walk.total - place[last] <= span {
            let keep = bend[first] >= bend[last] ? first : last
            cuts.removeFirst()
            cuts.removeLast()
            if keep == first { cuts.insert(first, at: 0) } else { cuts.append(last) }
        }
        guard !cuts.isEmpty else { return [self] }

        var pieces: [Contour] = []
        func piece(_ from: Int, _ to: Int) {
            var run: [Vector2] = []
            var i = from
            while true {
                run.append(points[i])
                if i == to { break }
                i = (i + 1) % n
            }
            if run.count >= 2, run.contains(where: { $0.distance(to: run[0]) > 1e-9 }) {
                pieces.append(Contour(run, closed: false))
            }
        }
        if isClosed {
            for (k, cut) in cuts.enumerated() {
                piece(cut, cuts[(k + 1) % cuts.count])
            }
        } else {
            piece(0, cuts[0])
            for k in 1 ..< cuts.count { piece(cuts[k - 1], cuts[k]) }
            piece(cuts[cuts.count - 1], n - 1)
        }
        return pieces.isEmpty ? [self] : pieces
    }

    /// A few smooth cubic curves through a dense trace, as a `Path`: a
    /// mouse stroke of hundreds of points comes back as a handful of
    /// Béziers that pass within `tolerance` of every point, joined smoothly.
    /// The path is closed when the contour is, and the join at its seam is
    /// smooth too. Draw it with `drawShape(path.shape)`, read its curves
    /// through `path.cubics`, or walk it through `path.contour`.
    ///
    /// Schneider's method: the points are given parameters by the distance
    /// walked, one cubic is fitted to them by least squares with its end
    /// directions held, the parameters are improved by Newton's method when
    /// the fit is close, and otherwise the trace is cut at its worst point
    /// and each half fitted again, the two halves sharing the direction
    /// there. A tighter tolerance gives more curves; `simplified(tolerance:)`
    /// first removes nothing the fit needs and makes it faster. A trace's
    /// true corners are better cut first with `split(atCornersOver:span:)`
    /// and fitted piece by piece, since one smooth run cannot turn sharply.
    ///
    /// ```swift
    /// let curves = trace.fitted(tolerance: 1.5)
    /// drawShape(curves.shape)
    /// let count = curves.cubics.count
    /// ```
    ///
    /// Consecutive repeated points are dropped first. A contour of one point
    /// gives a path that only moves there, and one of two points a straight
    /// curve.
    func fitted(tolerance: Double) -> Path {
        var d: [Vector2] = []
        for p in points where d.last.map({ $0.distance(to: p) > 1e-9 }) ?? true { d.append(p) }
        if isClosed, d.count > 1, d[0].distance(to: d[d.count - 1]) <= 1e-9 { d.removeLast() }
        var path = Path()
        guard d.count >= 2 else {
            if let p = d.first { path.move(to: p) }
            return path
        }
        let closed = isClosed
        if closed { d.append(d[0]) }
        let n = d.count
        let startTangent: Vector2, endTangent: Vector2
        if closed {
            // The seam reads the same direction from both sides, so the loop
            // joins smoothly there.
            let through = d[1] - d[n - 2]
            startTangent = through.lengthSquared > 1e-18 ? through.normalized : (d[1] - d[0]).normalized
            endTangent = -startTangent
        } else {
            startTangent = (d[1] - d[0]).normalized
            endTangent = (d[n - 2] - d[n - 1]).normalized
        }
        let tolerance = Swift.max(tolerance, 0)
        var cubics: [CubicBezier] = []
        // Pending stretches on a list rather than the call stack: the depth
        // is the trace's. The later half is pushed first so the curves come
        // out in walk order.
        var pending: [(first: Int, last: Int, start: Vector2, end: Vector2)] = [(0, n - 1, startTangent, endTangent)]
        while let job = pending.popLast() {
            switch CurveFit.fit(d, first: job.first, last: job.last,
                                startTangent: job.start, endTangent: job.end, tolerance: tolerance) {
            case .fitted(let cubic):
                cubics.append(cubic)
            case .split(let at):
                // The direction through the cut, read backward as the first
                // half's end direction and forward as the second's start.
                var center = (d[at - 1] - d[at]) + (d[at] - d[at + 1])
                if center.lengthSquared <= 1e-18 { center = d[at - 1] - d[at] }
                center = center.normalized
                pending.append((at, job.last, -center, job.end))
                pending.append((job.first, at, job.start, center))
            }
        }
        path.move(to: d[0])
        for cubic in cubics {
            path.cubicCurve(to: cubic.end, control1: cubic.control1, control2: cubic.control2)
        }
        if closed { path.close() }
        return path
    }
}

public extension Shape {
    /// Every contour bent from `base` along `target` (see
    /// `Contour.warped(from:along:spacing:)`), keeping the `winding` rule, so
    /// a glyph's counter bends with its outline.
    func warped(from base: Contour, along target: Contour, spacing: Double = 4) -> Shape {
        Shape(contours: contours.map { $0.warped(from: base, along: target, spacing: spacing) },
              winding: winding)
    }

    /// Every contour pulled toward `point` (see
    /// `Contour.pulled(toward:amount:radius:spacing:)`), keeping the
    /// `winding` rule.
    func pulled(toward point: Vector2, amount: Double, radius: Double, spacing: Double = 4) -> Shape {
        Shape(contours: contours.map {
            $0.pulled(toward: point, amount: amount, radius: radius, spacing: spacing)
        }, winding: winding)
    }

    /// Every contour cut at its corners (see
    /// `Contour.split(atCornersOver:span:)`), the pieces of all of them in
    /// one list, in contour order.
    func split(atCornersOver angle: Double, span: Double = 0) -> [Contour] {
        contours.flatMap { $0.split(atCornersOver: angle, span: span) }
    }

    /// Every contour fitted with cubic curves (see
    /// `Contour.fitted(tolerance:)`), one `Path` per contour.
    func fitted(tolerance: Double) -> [Path] {
        contours.map { $0.fitted(tolerance: tolerance) }
    }
}

// MARK: - The walk, read many times

extension Contour {
    /// A copy with points added along its straight runs so no segment is
    /// longer than `maxSegment`, every original point kept. The bending edits
    /// start here, so a straight edge bends instead of staying straight
    /// between its two ends. A non-positive `maxSegment` returns the contour
    /// unchanged.
    func refined(maxSegment: Double) -> Contour {
        guard maxSegment > 0, points.count >= 2 else { return self }
        var out: [Vector2] = []
        let count = isClosed ? points.count : points.count - 1
        for i in 0 ..< count {
            let a = points[i], b = points[(i + 1) % points.count]
            out.append(a)
            let length = a.distance(to: b)
            // Bounded before it becomes a count: a segment of no finite
            // length takes the most pieces rather than trapping.
            let wanted = (length / maxSegment).rounded(.up)
            let pieces = wanted.isNaN ? 1 : Int(Swift.min(Swift.max(wanted, 1), 1e6))
            if pieces > 1 {
                for k in 1 ..< pieces { out.append(a + (b - a) * (Double(k) / Double(pieces))) }
            }
        }
        if !isClosed { out.append(points[points.count - 1]) }
        return Contour(out, closed: isClosed)
    }

    /// The nearest earlier point that is not on top of `i`, wrapping round a
    /// closed contour; nil when every point is the same place.
    func previousDistinct(_ i: Int) -> Vector2? {
        let n = points.count
        var j = i
        for _ in 0 ..< n {
            j -= 1
            if j < 0 {
                guard isClosed else { return nil }
                j += n
            }
            if points[j].distance(to: points[i]) > 1e-9 { return points[j] }
        }
        return nil
    }

    /// The nearest later point that is not on top of `i`, wrapping round a
    /// closed contour; nil when every point is the same place.
    func nextDistinct(_ i: Int) -> Vector2? {
        let n = points.count
        var j = i
        for _ in 0 ..< n {
            j += 1
            if j >= n {
                guard isClosed else { return nil }
                j -= n
            }
            if points[j].distance(to: points[i]) > 1e-9 { return points[j] }
        }
        return nil
    }

    /// The points that turn by more than `angle` between their two
    /// neighboring distinct points. An open contour's ends are not corners.
    func cornerIndices(over angle: Double) -> [Int] {
        let n = points.count
        guard n >= 3 else { return [] }
        var out: [Int] = []
        for i in 0 ..< n {
            if !isClosed && (i == 0 || i == n - 1) { continue }
            guard let p = previousDistinct(i), let q = nextDistinct(i) else { continue }
            let u = (points[i] - p).normalized, w = (q - points[i]).normalized
            let turn = acos(Swift.min(Swift.max(u.dot(w), -1), 1))
            if turn > angle { out.append(i) }
        }
        return out
    }

    /// The walk prepared for many reads: its distinct points, where each
    /// sits along the walk, and a direction of travel at each that is
    /// smoothed through the vertex, so a frame read between two vertices
    /// turns gradually rather than stepping at each one.
    struct Walk {
        let points: [Vector2]
        let closed: Bool
        /// The distance walked to reach each point.
        let cumulative: [Double]
        let total: Double
        /// The direction of travel at each point, the two neighboring
        /// segments' directions averaged (one at an open end).
        let tangents: [Vector2]

        init?(_ contour: Contour) {
            var folded: [Vector2] = []
            for p in contour.points where folded.last.map({ $0.distance(to: p) > 1e-9 }) ?? true {
                folded.append(p)
            }
            if contour.isClosed, folded.count > 1,
               folded[0].distance(to: folded[folded.count - 1]) <= 1e-9 {
                folded.removeLast()
            }
            let n = folded.count
            guard n >= 2 else { return nil }
            var cumulative = [Double](repeating: 0, count: n)
            for i in 1 ..< n { cumulative[i] = cumulative[i - 1] + folded[i].distance(to: folded[i - 1]) }
            let total = cumulative[n - 1] + (contour.isClosed ? folded[n - 1].distance(to: folded[0]) : 0)
            guard total > 0 else { return nil }
            var tangents = [Vector2](repeating: .zero, count: n)
            for i in 0 ..< n {
                let into: Vector2? = (contour.isClosed || i > 0)
                    ? (folded[i] - folded[(i + n - 1) % n]).normalized : nil
                let outOf: Vector2? = (contour.isClosed || i < n - 1)
                    ? (folded[(i + 1) % n] - folded[i]).normalized : nil
                let sum = (into ?? .zero) + (outOf ?? .zero)
                tangents[i] = sum.lengthSquared > 1e-12 ? sum.normalized : (outOf ?? into ?? .zero)
            }
            self.points = folded
            self.closed = contour.isClosed
            self.cumulative = cumulative
            self.total = total
            self.tangents = tangents
        }

        /// A distance along the walk as the walk reads it: wrapped on a
        /// closed one, clamped on an open one.
        func placed(_ s: Double) -> Double {
            guard s.isFinite else { return 0 }
            if closed {
                let laps = (s / total).rounded(.down)
                return s - laps * total
            }
            return Swift.min(Swift.max(s, 0), total)
        }

        /// The point, direction of travel, and right-hand normal at a
        /// distance along the walk.
        func frame(atDistance distance: Double) -> (point: Vector2, tangent: Vector2, normal: Vector2) {
            let s = placed(distance)
            let n = points.count
            // The last segment that starts at or before s.
            var low = 0, high = n - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if cumulative[mid] <= s { low = mid } else { high = mid - 1 }
            }
            var k = low
            if !closed { k = Swift.min(k, n - 2) }
            let a = points[k], b = points[(k + 1) % n]
            let length = a.distance(to: b)
            let u = length > 0 ? Swift.min(Swift.max((s - cumulative[k]) / length, 0), 1) : 0
            let blend = tangents[k] * (1 - u) + tangents[(k + 1) % n] * u
            let tangent = blend.lengthSquared > 1e-12 ? blend.normalized
                : (length > 0 ? (b - a) / length : tangents[k])
            return (a + (b - a) * u, tangent, tangent.perpendicular)
        }

        /// The point at a distance along the walk.
        func point(atDistance distance: Double) -> Vector2 {
            frame(atDistance: distance).point
        }

        /// The nearest place on the walk to `p`, and the distance walked to
        /// reach it.
        func nearest(to p: Vector2) -> (point: Vector2, distance: Double) {
            let n = points.count
            var best = Double.infinity
            var hit = (point: points[0], distance: 0.0)
            let count = closed ? n : n - 1
            for k in 0 ..< count {
                let a = points[k], b = points[(k + 1) % n]
                let ab = b - a
                let length2 = ab.lengthSquared
                guard length2 > 0 else { continue }
                let along = Swift.min(Swift.max((p - a).dot(ab) / length2, 0), 1)
                let q = a + ab * along
                let d = q.distanceSquared(to: p)
                if d < best {
                    best = d
                    hit = (q, cumulative[k] + along * length2.squareRoot())
                }
            }
            return hit
        }
    }
}

// MARK: - The fit

/// Schneider's curve fit, one stretch at a time.
enum CurveFit {
    enum Outcome {
        case fitted(CubicBezier)
        case split(at: Int)
    }

    /// One cubic through `d[first...last]` leaving along `startTangent` and
    /// arriving against `endTangent` (which points back into the stretch),
    /// within `tolerance` of every point, or the point to cut at.
    static func fit(_ d: [Vector2], first: Int, last: Int, startTangent: Vector2, endTangent: Vector2,
                    tolerance: Double) -> Outcome {
        let count = last - first + 1
        if count <= 2 {
            // Two points: a straight curve with its handles a third of the way.
            let reach = d[last].distance(to: d[first]) / 3
            return .fitted(CubicBezier(start: d[first], control1: d[first] + startTangent * reach,
                                       control2: d[last] + endTangent * reach, end: d[last]))
        }
        var u = chordParameters(d, first: first, last: last)
        var cubic = leastSquares(d, first: first, last: last, parameters: u,
                                 startTangent: startTangent, endTangent: endTangent)
        var worst = maxError(d, first: first, last: last, cubic: cubic, parameters: u)
        let bar = tolerance * tolerance
        if worst.error <= bar { return .fitted(cubic) }
        // Close enough that a better parameterization may bring it in.
        if worst.error <= bar * 16 {
            for _ in 0 ..< 4 {
                u = reparameterized(d, first: first, last: last, cubic: cubic, parameters: u)
                cubic = leastSquares(d, first: first, last: last, parameters: u,
                                     startTangent: startTangent, endTangent: endTangent)
                worst = maxError(d, first: first, last: last, cubic: cubic, parameters: u)
                if worst.error <= bar { return .fitted(cubic) }
            }
        }
        return .split(at: worst.at)
    }

    /// Each point's parameter as its share of the distance walked.
    static func chordParameters(_ d: [Vector2], first: Int, last: Int) -> [Double] {
        var u = [Double](repeating: 0, count: last - first + 1)
        for i in 1 ..< u.count { u[i] = u[i - 1] + d[first + i].distance(to: d[first + i - 1]) }
        let total = u[u.count - 1]
        guard total > 0 else { return u }
        for i in 1 ..< u.count { u[i] /= total }
        return u
    }

    /// The cubic that passes nearest the points at their parameters, its
    /// ends fixed and its handle directions given, so only the two handle
    /// lengths are solved for.
    static func leastSquares(_ d: [Vector2], first: Int, last: Int, parameters u: [Double],
                             startTangent: Vector2, endTangent: Vector2) -> CubicBezier {
        let p0 = d[first], p3 = d[last]
        var c00 = 0.0, c01 = 0.0, c11 = 0.0, x0 = 0.0, x1 = 0.0
        for (i, t) in u.enumerated() {
            let s = 1 - t
            let b0 = s * s * s, b1 = 3 * s * s * t, b2 = 3 * s * t * t, b3 = t * t * t
            let a0 = startTangent * b1, a1 = endTangent * b2
            c00 += a0.dot(a0)
            c01 += a0.dot(a1)
            c11 += a1.dot(a1)
            let residual = d[first + i] - (p0 * (b0 + b1) + p3 * (b2 + b3))
            x0 += a0.dot(residual)
            x1 += a1.dot(residual)
        }
        let det = c00 * c11 - c01 * c01
        var alphaStart = 0.0, alphaEnd = 0.0
        if abs(det) > 1e-12 {
            alphaStart = (x0 * c11 - x1 * c01) / det
            alphaEnd = (c00 * x1 - c01 * x0) / det
        }
        // A handle that collapsed or turned back is replaced by the plain
        // third-of-the-chord guess.
        let chord = p3.distance(to: p0)
        let epsilon = 1e-6 * chord
        if alphaStart < epsilon || alphaEnd < epsilon || !alphaStart.isFinite || !alphaEnd.isFinite {
            alphaStart = chord / 3
            alphaEnd = chord / 3
        }
        return CubicBezier(start: p0, control1: p0 + startTangent * alphaStart,
                           control2: p3 + endTangent * alphaEnd, end: p3)
    }

    /// The largest squared distance from an interior point to the curve at
    /// its parameter, and which point it is.
    static func maxError(_ d: [Vector2], first: Int, last: Int, cubic: CubicBezier,
                         parameters u: [Double]) -> (error: Double, at: Int) {
        var worst = 0.0
        var at = (first + last) / 2
        for i in (first + 1) ..< last {
            let distance = cubic.point(at: u[i - first]).distanceSquared(to: d[i])
            if distance >= worst {
                worst = distance
                at = i
            }
        }
        return (worst, at)
    }

    /// One Newton step on each parameter toward the point on the curve
    /// nearest its data point.
    static func reparameterized(_ d: [Vector2], first: Int, last: Int, cubic: CubicBezier,
                                parameters u: [Double]) -> [Double] {
        u.enumerated().map { i, t in
            let q = cubic.point(at: t)
            let q1 = cubic.derivative(at: t)
            let q2 = cubic.secondDerivative(at: t)
            let offset = q - d[first + i]
            let numerator = offset.dot(q1)
            let denominator = q1.dot(q1) + offset.dot(q2)
            guard abs(denominator) > 1e-12 else { return t }
            let next = t - numerator / denominator
            return next.isFinite ? Swift.min(Swift.max(next, 0), 1) : t
        }
    }
}
