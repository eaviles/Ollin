import Foundation

/// A curve in the plane that can give its outline as a `Contour` and say
/// where it crosses another: a `LineSegment`, an `Arc`, a `Circle`, an
/// `Ellipse`, a `Rectangle`, a `Triangle`, or a `Contour` itself. The outline
/// is what every other geometry question is asked through (a `Shape`, a
/// boolean, `regions(enclosedBy:)`, the contour questions), and
/// `crossings(with:)` is the one question the whole family answers directly,
/// in closed form wherever one exists.
///
/// ```swift
/// let road = LineSegment(Vector2(0, 300), Vector2(1080, 420))
/// let pond = Circle(center: Vector2(540, 380), radius: 160)
/// for hit in road.crossings(with: pond) { drawCircle(center: hit, radius: 6) }
/// ```
///
/// A mixed list works the same way, since every member is a `PlaneCurve`:
///
/// ```swift
/// let curves: [any PlaneCurve] = [road, pond, Ellipse(x: 300, y: 500, radiusX: 220, radiusY: 90)]
/// for i in curves.indices {
///     for j in curves.indices where j > i {
///         for hit in curves[i].crossings(with: curves[j]) { drawCircle(center: hit, radius: 6) }
///     }
/// }
/// ```
public protocol PlaneCurve {
    /// The curve as a `Contour` of straight pieces, the outline every other
    /// geometry question takes. A closed curve gives a closed contour, and a
    /// curved one is flattened so that no piece strays more than a tenth of a
    /// unit from it.
    var contour: Contour { get }
}

public extension PlaneCurve {
    /// Every place this curve meets `other`, sorted along this curve: from
    /// the start of a segment or an arc, from the right of a circle or an
    /// ellipse going clockwise as the canvas shows it, from the first corner
    /// of a rectangle or a triangle, and along the walk of a contour. A touch
    /// counts as a crossing. Two curves that run along each other share no
    /// single point and report nothing for that stretch.
    ///
    /// A pair with a closed form is answered from it, exactly: segments,
    /// rectangles, triangles, and contours against each other, any of them
    /// against a circle, an arc, or an ellipse, and circles and arcs against
    /// each other. An ellipse against a circle, an arc, or another ellipse is
    /// found on the two outlines and then polished on the true curves to
    /// machine precision, so a bare touch, or two crossings closer together
    /// than the outlines' own pieces, may come back as one or none.
    func crossings(with other: some PlaneCurve) -> [Vector2] {
        CurveCrossings.points(self, other)
    }
}

extension Contour: PlaneCurve {
    /// The contour itself, so a contour can stand wherever a `PlaneCurve` is
    /// asked for.
    public var contour: Contour { self }
}

// MARK: - The crossing engine

/// Where two plane curves meet. Every curve is read as one of three forms, a
/// run of straight pieces, a circle or a piece of one, or an ellipse, and each
/// pair of forms has its own method: the quadratic for a straight piece
/// against a circle or an ellipse, the two-circle construction for circles and
/// arcs, the contour crossings for straights against straights, and the
/// polished outline crossings for an ellipse against anything round.
enum CurveCrossings {
    /// One straight piece.
    struct Straight {
        let a: Vector2
        let b: Vector2
    }

    /// A circle, or the piece of one between `start` and `start + sweep`.
    struct Round {
        let center: Vector2
        let radius: Double
        /// The start angle and the signed sweep in radians; `nil` for a whole
        /// circle.
        let start: Double?
        let sweep: Double?

        /// Whether `angle` lies on the piece. Angles a whole turn apart are
        /// the same angle, and an end counts.
        func contains(angle: Double) -> Bool {
            guard let start, let sweep else { return true }
            let full = 2 * Double.pi
            var rel = (angle - start).truncatingRemainder(dividingBy: full)
            if sweep >= 0 { if rel < 0 { rel += full } } else { if rel > 0 { rel -= full } }
            let slack = 1e-9
            if abs(rel) <= abs(sweep) + slack { return true }
            return abs(abs(rel) - full) <= slack
        }

        /// How far round the piece `point` sits, `0...1` along the sweep (or
        /// round the whole circle from the right), for sorting.
        func position(of point: Vector2) -> Double {
            let angle = (point - center).angle
            let full = 2 * Double.pi
            guard let start, let sweep, sweep != 0 else {
                var rel = angle.truncatingRemainder(dividingBy: full)
                if rel < 0 { rel += full }
                return rel / full
            }
            var rel = (angle - start).truncatingRemainder(dividingBy: full)
            if sweep >= 0 { if rel < 0 { rel += full } } else { if rel > 0 { rel -= full } }
            if abs(rel) > abs(sweep) + 1e-9 { rel = 0 }
            return abs(rel) / abs(sweep)
        }
    }

    enum Form {
        case straights([Straight], Contour)
        case round(Round)
        case oval(Ellipse)
    }

    static func form(of curve: any PlaneCurve) -> Form {
        switch curve {
        case let segment as LineSegment:
            return .straights([Straight(a: segment.start, b: segment.end)], segment.contour)
        case let circle as Circle:
            return .round(Round(center: circle.center, radius: circle.radius, start: nil, sweep: nil))
        case let arc as Arc:
            if abs(arc.sweep) >= 2 * Double.pi - 1e-12 {
                return .round(Round(center: arc.center, radius: arc.radius, start: nil, sweep: nil))
            }
            return .round(Round(center: arc.center, radius: arc.radius, start: arc.start, sweep: arc.sweep))
        case let ellipse as Ellipse:
            if ellipse.isCircular {
                return .round(Round(center: ellipse.center, radius: ellipse.radiusX, start: nil, sweep: nil))
            }
            return .oval(ellipse)
        default:
            let contour = curve.contour
            return .straights(straights(of: contour), contour)
        }
    }

    static func straights(of contour: Contour) -> [Straight] {
        let points = contour.points
        guard points.count >= 2 else { return [] }
        var out: [Straight] = []
        let count = contour.isClosed ? points.count : points.count - 1
        for i in 0 ..< count {
            let a = points[i], b = points[(i + 1) % points.count]
            if a != b { out.append(Straight(a: a, b: b)) }
        }
        return out
    }

    static func points(_ first: any PlaneCurve, _ second: any PlaneCurve) -> [Vector2] {
        let mine = form(of: first), theirs = form(of: second)
        let found: [Vector2]
        switch (mine, theirs) {
        case (.straights(_, let a), .straights(_, let b)):
            found = a.crossings(with: b).map(\.point)
        case (.straights(let a, _), .round(let r)):
            found = a.flatMap { meet($0, r) }
        case (.round(let r), .straights(let b, _)):
            found = b.flatMap { meet($0, r) }
        case (.straights(let a, _), .oval(let e)):
            found = a.flatMap { meet($0, e) }
        case (.oval(let e), .straights(let b, _)):
            found = b.flatMap { meet($0, e) }
        case (.round(let p), .round(let q)):
            found = meet(p, q)
        default:
            found = polished(first.contour, second.contour, mine, theirs)
        }
        return settled(found, along: mine)
    }

    // MARK: Closed forms

    /// Where a straight piece meets a circle or an arc: the quadratic in the
    /// piece's own parameter, a touch counted once.
    static func meet(_ s: Straight, _ r: Round) -> [Vector2] {
        let d = s.b - s.a
        let scale = Swift.max(r.radius, 1e-300)
        return parameters(of: s, circleAt: r.center, radius: r.radius).compactMap { t in
            let p = s.a + d * t
            return r.contains(angle: (p - r.center).angle) ? p : nil
        }.filter { _ in scale > 0 }
    }

    /// Where a straight piece meets an ellipse: the same quadratic, worked in
    /// the frame where the ellipse is the unit circle. The parameter along
    /// the piece survives that map, so the point is taken on the original.
    static func meet(_ s: Straight, _ e: Ellipse) -> [Vector2] {
        let unit = Straight(a: e.toUnit(s.a), b: e.toUnit(s.b))
        let d = s.b - s.a
        return parameters(of: unit, circleAt: .zero, radius: 1).map { s.a + d * $0 }
    }

    /// The parameters `0...1` along `s` where it meets the circle, by the
    /// quadratic in `t`. A discriminant within rounding of zero is a touch
    /// and gives the one root.
    static func parameters(of s: Straight, circleAt center: Vector2, radius: Double) -> [Double] {
        let d = s.b - s.a, f = s.a - center
        let a = d.dot(d)
        guard a > 0 else { return [] }
        let b = 2 * d.dot(f)
        let c = f.dot(f) - radius * radius
        let disc = b * b - 4 * a * c
        let tol = 1e-12 * a * (f.lengthSquared + radius * radius)
        let roots: [Double]
        if disc < -tol {
            return []
        } else if disc <= tol {
            roots = [-b / (2 * a)]
        } else {
            let q = disc.squareRoot()
            roots = [(-b - q) / (2 * a), (-b + q) / (2 * a)]
        }
        let slack = 1e-12
        return roots.compactMap { t in
            guard t >= -slack, t <= 1 + slack else { return nil }
            return Swift.min(Swift.max(t, 0), 1)
        }
    }

    /// Where two circles, or arcs of them, meet: the classic construction on
    /// the line between the centers. Coincident or concentric circles report
    /// nothing, and a touch counts once.
    static func meet(_ p: Round, _ q: Round) -> [Vector2] {
        let between = q.center - p.center
        let d = between.length
        let tol = 1e-9 * Swift.max(p.radius, q.radius, 1e-300)
        guard d > tol else { return [] }
        guard d <= p.radius + q.radius + tol, d >= abs(p.radius - q.radius) - tol else { return [] }
        let a = (p.radius * p.radius - q.radius * q.radius + d * d) / (2 * d)
        let h2 = p.radius * p.radius - a * a
        let h = h2 > 0 ? h2.squareRoot() : 0
        let foot = p.center + between * (a / d)
        let perp = Vector2(-between.y, between.x) / d
        let candidates = h > 0 ? [foot + perp * h, foot - perp * h] : [foot]
        return candidates.filter {
            p.contains(angle: ($0 - p.center).angle) && q.contains(angle: ($0 - q.center).angle)
        }
    }

    // MARK: An ellipse against anything round

    /// The value and gradient of a form's implicit equation at `p`, scaled so
    /// a value is dimensionless: zero on the curve, about the squared
    /// relative distance off it.
    static func evaluate(_ form: Form, at p: Vector2) -> (value: Double, gradient: Vector2)? {
        switch form {
        case .round(let r):
            let r2 = r.radius * r.radius
            guard r2 > 0 else { return nil }
            let d = p - r.center
            return (d.lengthSquared / r2 - 1, d * (2 / r2))
        case .oval(let e):
            return (e.toUnit(p).lengthSquared - 1, e.unitGradient(at: p))
        case .straights:
            return nil
        }
    }

    /// Crossings found on the two outlines and then driven onto the true
    /// curves by Newton's method on the two implicit equations. A seed that
    /// will not settle (a touch, where the two gradients are parallel) is kept
    /// where the outlines put it.
    static func polished(_ a: Contour, _ b: Contour, _ mine: Form, _ theirs: Form) -> [Vector2] {
        let seeds = a.crossings(with: b).map(\.point)
        var out: [Vector2] = []
        for seed in seeds {
            var p = seed
            var converged = false
            for _ in 0 ..< 30 {
                guard let (f, gf) = evaluate(mine, at: p), let (g, gg) = evaluate(theirs, at: p) else { break }
                let det = gf.x * gg.y - gf.y * gg.x
                guard abs(det) > 1e-300 else { break }
                let dx = (-f * gg.y + g * gf.y) / det
                let dy = (-g * gf.x + f * gg.x) / det
                p = p + Vector2(dx, dy)
                if abs(dx) + abs(dy) <= 1e-14 * Swift.max(1, abs(p.x) + abs(p.y)) {
                    converged = true
                    break
                }
            }
            if converged,
               let (f, _) = evaluate(mine, at: p), let (g, _) = evaluate(theirs, at: p),
               abs(f) < 1e-9, abs(g) < 1e-9 {
                out.append(p)
            } else {
                out.append(seed)
            }
        }
        // An arc keeps only what lies on its sweep.
        func onSweep(_ form: Form, _ p: Vector2) -> Bool {
            if case .round(let r) = form { return r.contains(angle: (p - r.center).angle) }
            return true
        }
        return out.filter { onSweep(mine, $0) && onSweep(theirs, $0) }
    }

    // MARK: Sorting and folding

    /// How far along `form` the point sits, in the form's own measure.
    static func position(of p: Vector2, along form: Form) -> Double {
        switch form {
        case .straights(_, let contour):
            return contour.fraction(of: p)
        case .round(let r):
            return r.position(of: p)
        case .oval(let e):
            let u = e.toUnit(p)
            var rel = atan2(u.y, u.x)
            if rel < 0 { rel += 2 * .pi }
            return rel / (2 * .pi)
        }
    }

    /// The points sorted along the asking curve, with a point reported twice
    /// (a crossing on a corner, found by both edges; a touch that split into
    /// two by rounding) folded into one.
    static func settled(_ found: [Vector2], along form: Form) -> [Vector2] {
        guard !found.isEmpty else { return [] }
        let scale = found.reduce(1.0) { Swift.max($0, abs($1.x), abs($1.y)) }
        let sorted = found.map { ($0, position(of: $0, along: form)) }
            .sorted { $0.1 < $1.1 }
        var out: [Vector2] = []
        for (p, _) in sorted {
            if out.contains(where: { $0.distance(to: p) <= 1e-9 * scale }) { continue }
            out.append(p)
        }
        return out
    }
}
