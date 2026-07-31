import Foundation

/// Mathematical paper marbling: floating inks combed into feathers, veins,
/// and swirls, the centuries-old technique in closed form. A `Marbling` bath
/// holds colored ink regions as vector outlines; dropping a new ink pushes
/// every earlier region aside, and each raking tool bends all of them at
/// once. Because every operation is an exact point transform, the result
/// stays pure geometry: fill it on canvas, or export it as plotter-ready
/// paths through `--export-svg`.
///
/// ```swift
/// var bath = Marbling()
/// for i in 0 ..< 20 {
///     bath.drop(at: center, radius: 200 - Double(i) * 9,
///               color: i.isMultiple(of: 2) ? .indigo : .ivory)
/// }
/// bath.comb(through: center, direction: .unitY, spacing: 90, strength: 260)
/// drawMarbling(bath)
/// ```
///
/// The transforms are the classic closed-form marbling equations: the
/// area-preserving ink drop and the exponential-falloff stylus family (tine
/// line, comb, circular tine, vortex). Each displaces points only along the
/// tool's motion by an amount that decays with distance from the tool, so
/// regions deform without ever tearing or crossing. Everything is
/// deterministic: the same operations always marble the same paper.
///
/// Cost note: outlines refine as they stretch, so a bath grows points as
/// operations accumulate. Marbling is setup-time-shaped work; compose the
/// bath once (or per interaction) and redraw the held result.

/// One floating ink region in a marbling bath: a fillable shape (usually a
/// single closed outline; a floated glyph keeps its holes) and the ink color
/// that fills it. Later inks sit above earlier ones, exactly like paint
/// dropped onto the bath.
public struct MarbledInk: Equatable, Sendable {
    /// The region's outline(s).
    public var shape: Shape
    /// The ink's fill color.
    public var color: Color

    public init(shape: Shape, color: Color) {
        self.shape = shape
        self.color = color
    }
}

/// A marbling bath: an ordered stack of `MarbledInk` regions plus the verbs
/// that drop and rake them. A value type, so a copied bath is a snapshot you
/// can keep raking while the original stays put.
public struct Marbling: Equatable, Sendable {
    /// The ink regions, oldest first; draw them in order so later drops
    /// cover earlier ones.
    public private(set) var inks: [MarbledInk]

    /// The refinement spacing in canvas units: while a transform stretches
    /// an outline, its segments subdivide until no longer than about this.
    /// Smaller is smoother and heavier; the default suits a full canvas.
    public var spacing: Double

    /// An empty bath.
    public init(spacing: Double = 4) {
        inks = []
        self.spacing = max(spacing, 0.5)
    }

    // MARK: - Dropping ink

    /// Drop a circle of ink at `center`: every existing region is pushed
    /// radially away to make room (each point lands at `√(d² + r²)` from the
    /// center, the area-preserving displacement, so regions thin but never
    /// vanish), then the new disk joins the top of the stack. Alternating
    /// drop colors at one center is the classic bull's-eye that every raked
    /// pattern starts from.
    public mutating func drop(at center: Vector2, radius: Double, color: Color) {
        guard radius > 0 else { return }
        let r2 = radius * radius
        transformInks { p in
            let offset = p - center
            let d2 = offset.lengthSquared
            // The limit of the displacement as d → 0 lands on the new rim;
            // the direction there is arbitrary, so pick one deterministically.
            guard d2 > 1e-12 else { return center + Vector2(radius, 0) }
            return center + offset * (1 + r2 / d2).squareRoot()
        }
        let count = max(24, Int((radius * .tau / spacing).rounded(.up)))
        let rim = (0 ..< count).map { i -> Vector2 in
            let angle = Double(i) / Double(count) * .tau
            return center + Vector2(cos(angle), sin(angle)) * radius
        }
        inks.append(MarbledInk(shape: Shape(rim), color: color))
    }

    /// Drop a circle of ink, `drop(at:radius:color:)`, at (`x`, `y`).
    public mutating func drop(_ x: Double, _ y: Double, radius: Double, color: Color) {
        drop(at: Vector2(x, y), radius: radius, color: color)
    }

    /// Float an arbitrary shape onto the bath as one ink: it joins the top
    /// of the stack as-is (only drops displace what's already floating), and
    /// every later operation rakes it like any other ink, holes included.
    /// Floating text outlines and combing them is the classic trick.
    public mutating func add(_ shape: Shape, color: Color) {
        inks.append(MarbledInk(shape: shape, color: color))
    }

    /// Float a single closed outline onto the bath, `add(_:color:)`.
    public mutating func add(_ contour: Contour, color: Color) {
        add(Shape(contours: [contour]), color: color)
    }

    // MARK: - Raking tools

    /// Pull a stylus along the line through `point` in `direction`: every
    /// point shifts parallel to the line by `strength · 2^(−d/falloff)`,
    /// where `d` is its distance from the line, so ink on the line moves the
    /// full `strength` and the pull fades to half at every `falloff` away.
    /// The stroke that pulls a bull's-eye into a heart.
    public mutating func tine(through point: Vector2, direction: Vector2,
                              strength: Double, falloff: Double = 48) {
        let along = direction.normalized
        guard along.lengthSquared > 0.5, falloff > 0 else { return }
        let across = along.perpendicular
        transformInks { p in
            let d = abs((p - point).dot(across))
            return p + along * (strength * exp2(-d / falloff))
        }
    }

    /// Pull a whole comb across the bath: teeth run parallel through
    /// `point`, one every `spacing`, each acting like `tine(through:)`. Rows
    /// of drops under an alternating comb become the classic feathered
    /// nonpareil.
    public mutating func comb(through point: Vector2, direction: Vector2,
                              spacing teeth: Double, strength: Double,
                              falloff: Double = 24) {
        let along = direction.normalized
        guard along.lengthSquared > 0.5, falloff > 0, teeth > 0 else { return }
        let across = along.perpendicular
        transformInks { p in
            let offset = (p - point).dot(across)
            let d = abs(offset - (offset / teeth).rounded() * teeth)
            return p + along * (strength * exp2(-d / falloff))
        }
    }

    /// Drag a stylus around the circle of `radius` at `center`: points near
    /// the track slide along it (rotating about the center by an arc of
    /// `strength · 2^(−d/falloff)`, `d` their distance from the track), so
    /// the pattern shears into a ring. Negative `strength` reverses the
    /// direction of travel.
    public mutating func tine(around center: Vector2, radius: Double,
                              strength: Double, falloff: Double = 48) {
        guard falloff > 0 else { return }
        transformInks { p in
            let offset = p - center
            let distance = offset.length
            let d = abs(distance - radius)
            let arc = strength * exp2(-d / falloff)
            return center + offset.rotated(by: arc / max(distance, 1e-9))
        }
    }

    /// Stir a vortex at `center`: every point rotates about it by an arc of
    /// `strength · 2^(−d/falloff)` (`d` its distance from the center), so
    /// the middle whirls hardest and the spin dies away outward. The tight
    /// spiral at the heart of French-curl papers.
    public mutating func swirl(at center: Vector2, strength: Double,
                               falloff: Double = 96) {
        guard falloff > 0 else { return }
        transformInks { p in
            let offset = p - center
            let distance = offset.length
            let arc = strength * exp2(-distance / falloff)
            return center + offset.rotated(by: arc / max(distance, 1e-9))
        }
    }

    // MARK: - Applying transforms

    /// Run one point transform over every ink outline, subdividing segments
    /// (in the pre-transform curve, so new points land exactly on the
    /// transformed outline) wherever the transform stretches them past
    /// `spacing`.
    private mutating func transformInks(_ transform: (Vector2) -> Vector2) {
        let limit = spacing * spacing
        for index in inks.indices {
            let shape = inks[index].shape
            inks[index].shape = Shape(
                contours: shape.contours.map { refined($0, under: transform, limit: limit) },
                winding: shape.winding)
        }
    }

    /// One contour through one transform: every point maps, and segments the
    /// transform stretched past `spacing` subdivide at pre-transform
    /// midpoints (so new points land exactly on the transformed curve).
    /// Depth-capped, and never splitting a source segment already shorter
    /// than a hair, so a singular spot (a drop centered on an outline) can't
    /// recurse away.
    private func refined(_ contour: Contour, under transform: (Vector2) -> Vector2,
                         limit: Double) -> Contour {
        let points = contour.points
        guard points.count > 1 else {
            return Contour(points.map(transform), closed: contour.isClosed)
        }
        let mapped = points.map(transform)
        var refined: [Vector2] = []
        refined.reserveCapacity(points.count + points.count / 2)

        func subdivide(_ a: Vector2, _ ta: Vector2,
                       _ b: Vector2, _ tb: Vector2, _ depth: Int) {
            guard depth > 0,
                  ta.distanceSquared(to: tb) > limit,
                  a.distanceSquared(to: b) > 1e-6 else { return }
            let mid = a.lerp(to: b, 0.5)
            let tMid = transform(mid)
            subdivide(a, ta, mid, tMid, depth - 1)
            refined.append(tMid)
            subdivide(mid, tMid, b, tb, depth - 1)
        }

        let n = points.count
        let segments = contour.isClosed ? n : n - 1
        for i in 0 ..< segments {
            let j = (i + 1) % n
            refined.append(mapped[i])
            subdivide(points[i], mapped[i], points[j], mapped[j], 10)
        }
        if !contour.isClosed { refined.append(mapped[n - 1]) }
        return Contour(refined, closed: contour.isClosed)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Draw a marbling bath: each ink region fills with its own color,
    /// oldest first, so the stack reads exactly as it was dropped. The
    /// current stroke state applies to every outline (leave it off for flat
    /// marbled paper; a thin stroke reads as engraved veining), and the fill
    /// state is restored afterward.
    func drawMarbling(_ marbling: Marbling) {
        withState {
            for ink in marbling.inks {
                fill(ink.color)
                drawShape(ink.shape)
            }
        }
    }
}
