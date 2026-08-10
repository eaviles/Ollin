import Foundation
import simd
import COllinShaders

// MARK: - SDF combinators (composed signed-distance fields)
//
// `SDF` is a composable signed-distance *field*: a value you build, store, and
// transform, then draw with `drawSDF(_:)`. Unlike the immediate `draw*` primitives
// (each its own shape), combined `SDF`s *merge*: a smooth union melts two shapes
// into one blob, subtraction carves one out of another, morph blends between them.
// The whole composition fills as a single region (honoring the current
// fill/stroke/CTM), and a stroke traces the *merged* outline.
//
// A composition is a small tree (leaf shapes, binary combine ops, unary modifiers,
// and point-space transforms). `drawSDF` flattens it to a flat `SDFNode` program the
// fragment evaluates per pixel (a tiny stack machine; see ShaderCombinator.metal).
// Leaves carry no transform; positioning is transform nodes, so method-chain order
// is exact: `a.at(p).repeated(...)` tiles the moved shape, `a.repeated(...).at(p)`
// shifts the whole tiling.
//
// A leaf takes a solid color (`.colored(_:)`, or the current `fill`); a linear/radial
// gradient `fill` or `stroke` paints the whole merged region/outline by field position.
// Per-axis sizing is `stretched` (an exact elongation) or `scaled(x:y:)` (a conservative
// bound). The leaf constructors cover the common centered shapes; the scoped block form
// (`smoothUnion { drawCircle… }`) reaches every SDF primitive.
public struct SDF {
    /// Binary combine ops. Raw values are the `sel` the shader's OP node reads.
    enum Combine: UInt32 {
        case union = 0, smoothUnion = 1, subtract = 2, smoothSubtract = 3
        case intersect = 4, smoothIntersect = 5, morph = 6
        case chamferUnion = 7, chamferSubtract = 8, chamferIntersect = 9
        case stairsUnion = 10, stairsSubtract = 11, stairsIntersect = 12
        case columnsUnion = 13, columnsSubtract = 14, columnsIntersect = 15
        case pipe = 16, engrave = 17, groove = 18, tongue = 19
    }
    /// Unary distance modifiers. Raw values are the `sel` the shader's MOD node reads.
    enum Modifier: UInt32 { case round = 0, onion = 1 }
    /// Point-space transforms (a scope wrapping a subtree).
    enum Transform {
        case translate(SIMD2<Float>)
        case rotate(Float)                 // radians
        case scale(Float)                  // uniform factor > 0
        case scaleXYZ(SIMD2<Float>)        // non-uniform factors (conservative SDF bound)
        case stretch(SIMD2<Float>)         // per-axis elongation half-extent (exact SDF)
        case mirror(x: Bool, y: Bool)      // reflect across the field axes
        case repeatTiles(spacing: SIMD2<Float>, count: SIMD2<Float>)  // limited tiling
        case polar(count: Float)           // radial repeat around the origin
    }

    indirect enum Node {
        case leaf(shape: SDFShape, size: SIMD2<Float>, p0: SIMD2<Float>,
                  p1: SIMD2<Float>, p2: SIMD2<Float>, extra: Float, color: Color?)
        case combine(Combine, SDF, SDF, Float, Float)   // op, lhs, rhs, k (smoothing / morph / joint size), extra (stairs steps)
        case modify(Modifier, SDF, Float)        // round/onion, child, amount
        case transformed(Transform, SDF)         // a point-space scope around a child
    }

    var node: Node
    init(_ node: Node) { self.node = node }

    /// Guard rails for the fixed-depth shader stacks (see ShaderCombinator.metal).
    /// Real compositions stay far under these; past them the field is logged and the
    /// shape skipped (never silently mis-drawn).
    static let maxValueDepth = 16
    static let maxPointDepth = 16
    static let maxNodes = 256
}

// MARK: Leaf shapes (the common centered region shapes)

public extension SDF {
    /// A circle of the given radius, centered at the field origin.
    static func circle(radius: Double) -> SDF {
        .init(.leaf(shape: .ellipse, size: SIMD2(Float(radius), Float(radius)),
                    p0: .zero, p1: .zero, p2: .zero, extra: 0, color: nil))
    }
    /// An axis-aligned ellipse with horizontal radius `rx`, vertical radius `ry`.
    static func ellipse(rx: Double, ry: Double) -> SDF {
        .init(.leaf(shape: .ellipse, size: SIMD2(Float(rx), Float(ry)),
                    p0: .zero, p1: .zero, p2: .zero, extra: 0, color: nil))
    }
    /// A rectangle `width` by `height`, with optional rounded corners.
    static func rect(width: Double, height: Double, cornerRadius: Double = 0) -> SDF {
        let r = max(0, min(cornerRadius, min(width, height) / 2))
        return .init(.leaf(shape: .box, size: SIMD2(Float(width / 2), Float(height / 2)),
                           p0: .zero, p1: .zero, p2: .zero, extra: Float(r), color: nil))
    }
    /// A square of the given side, with optional rounded corners.
    static func square(_ side: Double, cornerRadius: Double = 0) -> SDF {
        rect(width: side, height: side, cornerRadius: cornerRadius)
    }
    /// A regular polygon of `sides` (3+), one vertex pointing up, circumradius `radius`.
    static func ngon(radius: Double, sides: Int) -> SDF {
        star(outerRadius: radius, innerRadius: radius * cos(.pi / Double(max(3, sides))),
             points: max(3, sides))
    }
    /// A star with `points` tips alternating `outerRadius`/`innerRadius`, one tip up.
    static func star(outerRadius: Double, innerRadius: Double, points n: Int) -> SDF {
        let outer = max(outerRadius, 1e-4)
        let inner = max(min(innerRadius, outerRadius), 1e-4)
        let an = Double.pi / Double(max(3, n))
        let acs = SIMD2<Float>(Float(cos(an)), Float(sin(an)))
        let en = atan2(sin(an), cos(an) - inner / outer)
        let ecs = SIMD2<Float>(Float(cos(en)), Float(sin(en)))
        return .init(.leaf(shape: .star, size: SIMD2(Float(outer), Float(outer)),
                           p0: acs, p1: ecs, p2: .zero, extra: Float(an), color: nil))
    }
    /// A rhombus (diamond) `width` by `height` (full diagonals), optional corner rounding.
    static func rhombus(width: Double, height: Double, cornerRadius: Double = 0) -> SDF {
        let r = max(0, min(cornerRadius, min(width, height) / 2))
        return .init(.leaf(shape: .rhombus, size: SIMD2(Float(width / 2), Float(height / 2)),
                           p0: .zero, p1: .zero, p2: .zero, extra: Float(r), color: nil))
    }
    /// A filled annulus (ring) between `innerRadius` and `outerRadius`.
    static func ring(innerRadius: Double, outerRadius: Double) -> SDF {
        let mid = (outerRadius + innerRadius) / 2
        let half = (outerRadius - innerRadius) / 2
        return .init(.leaf(shape: .ring, size: SIMD2(Float(outerRadius), Float(outerRadius)),
                           p0: SIMD2(Float(mid), Float(half)), p1: .zero, p2: .zero,
                           extra: 0, color: nil))
    }
    /// An equilateral triangle, point-up, with circumradius `radius`, centered on its
    /// centroid (so `.at(p)` places the centroid at `p`, matching `drawTriangle`).
    static func triangle(radius: Double) -> SDF {
        let height = radius * 1.5
        let halfBase = radius * 0.8660254037844386   // radius * √3/2
        let leaf = SDF(.leaf(shape: .triangle, size: SIMD2(Float(halfBase), Float(height)),
                             p0: .zero, p1: .zero, p2: .zero, extra: 0, color: nil))
        // The isosceles SDF's apex is its origin, `radius` above the centroid (y-down),
        // so translate the apex there and the centroid lands at the field origin.
        return leaf.translated(SIMD2(0, Float(-radius)))
    }
}

// MARK: Transforms (point-space scopes)

public extension SDF {
    /// Move the field so its origin lands at `(x, y)`.
    func at(x: Double, y: Double) -> SDF { translated(SIMD2(Float(x), Float(y))) }
    /// Move the field so its origin lands at `p`.
    func at(_ p: Vector2) -> SDF { translated(SIMD2(Float(p.x), Float(p.y))) }
    /// Rotate the field about its origin by `radians` (clockwise in y-down space).
    func rotated(_ radians: Double) -> SDF { .init(.transformed(.rotate(Float(radians)), self)) }
    /// Uniformly scale the field about its origin. Uniform scale is an exact SDF operation;
    /// for per-axis sizing prefer `stretched` (exact) or `scaled(x:y:)` (a bound).
    func scaled(_ s: Double) -> SDF { .init(.transformed(.scale(Float(max(s, 1e-4))), self)) }
    /// Non-uniformly scale the field per axis about its origin. Non-uniform scale isn't a valid
    /// distance field (it distorts space), so the result is a conservative *bound*: the outline
    /// is right, but smooth blends, rounding, and onion shells distort under strong anisotropy
    /// (fine up to ~2–3×). For the common "stretch a shape longer" case, prefer `stretched`,
    /// which stays exact.
    func scaled(x: Double, y: Double) -> SDF {
        .init(.transformed(.scaleXYZ(SIMD2(Float(max(x, 1e-4)), Float(max(y, 1e-4)))), self))
    }
    /// Stretch (elongate) the field per axis by inserting straight space, the way a circle becomes
    /// a stadium: each value extends the field by that much in *each* direction along the axis (a
    /// circle of radius r stretched by `x` reaches r + x along ±x). Unlike `scaled(x:y:)` this
    /// stays an exact distance field, so smooth blends, rounding, and onion shells don't distort.
    func stretched(x: Double = 0, y: Double = 0) -> SDF {
        .init(.transformed(.stretch(SIMD2(Float(max(x, 0)), Float(max(y, 0)))), self))
    }
    /// Paint every still-unpainted leaf of the field this color (an explicit leaf
    /// `.colored` wins; the current `fill` is the fallback for whatever's left).
    func colored(_ color: Color) -> SDF { painting(color) }

    internal func translated(_ t: SIMD2<Float>) -> SDF { .init(.transformed(.translate(t), self)) }

    private func painting(_ color: Color) -> SDF {
        switch node {
        case let .leaf(shape, size, p0, p1, p2, extra, existing):
            return .init(.leaf(shape: shape, size: size, p0: p0, p1: p1, p2: p2,
                               extra: extra, color: existing ?? color))
        case let .combine(op, a, b, k, n):
            return .init(.combine(op, a.painting(color), b.painting(color), k, n))
        case let .modify(m, c, amt):
            return .init(.modify(m, c.painting(color), amt))
        case let .transformed(t, c):
            return .init(.transformed(t, c.painting(color)))
        }
    }
}

// MARK: Combine ops & modifiers

public extension SDF {
    /// Hard union: the area covered by either field.
    func union(_ other: SDF) -> SDF { .init(.combine(.union, self, other, 0, 0)) }
    /// Smooth union: the two fields melt together over a blend of radius `k`.
    func smoothUnion(_ other: SDF, k: Double) -> SDF { .init(.combine(.smoothUnion, self, other, Float(k), 0)) }
    /// Hard subtraction: `other` carved out of `self`.
    func subtract(_ other: SDF) -> SDF { .init(.combine(.subtract, self, other, 0, 0)) }
    /// Smooth subtraction: `other` carved out with a blend of radius `k`.
    func smoothSubtract(_ other: SDF, k: Double) -> SDF { .init(.combine(.smoothSubtract, self, other, Float(k), 0)) }
    /// Hard intersection: only where both fields overlap.
    func intersect(_ other: SDF) -> SDF { .init(.combine(.intersect, self, other, 0, 0)) }
    /// Smooth intersection: the overlap, with a blend of radius `k`.
    func smoothIntersect(_ other: SDF, k: Double) -> SDF { .init(.combine(.smoothIntersect, self, other, Float(k), 0)) }
    /// Morph between two fields: `amount` 0 is `self`, 1 is `other` (a field blend,
    /// not a crossfade; the shape itself interpolates).
    func morph(_ other: SDF, amount: Double) -> SDF {
        .init(.combine(.morph, self, other, Float(min(max(amount, 0), 1)), 0))
    }
    /// Chamfer union: the fields join with a 45° bevel of the given size along the seam
    /// (a machined joint; colors stay a crisp pick of the nearer field, not a melt).
    func chamferUnion(_ other: SDF, radius: Double) -> SDF {
        .init(.combine(.chamferUnion, self, other, Float(max(radius, 0)), 0))
    }
    /// Chamfer subtraction: `other` carved out of `self`, the cut's rim beveled at 45°.
    func chamferSubtract(_ other: SDF, radius: Double) -> SDF {
        .init(.combine(.chamferSubtract, self, other, Float(max(radius, 0)), 0))
    }
    /// Chamfer intersection: the overlap, its edge beveled at 45°.
    func chamferIntersect(_ other: SDF, radius: Double) -> SDF {
        .init(.combine(.chamferIntersect, self, other, Float(max(radius, 0)), 0))
    }
    /// Stairs union: the fields join through a staircase of `steps` steps over `radius`
    /// along the seam (colors stay a crisp pick of the nearer field).
    func stairsUnion(_ other: SDF, radius: Double, steps: Int) -> SDF {
        .init(.combine(.stairsUnion, self, other, Float(max(radius, 0)), Float(max(steps, 1))))
    }
    /// Stairs subtraction: `other` carved out of `self`, the cut's rim stepped.
    func stairsSubtract(_ other: SDF, radius: Double, steps: Int) -> SDF {
        .init(.combine(.stairsSubtract, self, other, Float(max(radius, 0)), Float(max(steps, 1))))
    }
    /// Stairs intersection: the overlap, its edge stepped.
    func stairsIntersect(_ other: SDF, radius: Double, steps: Int) -> SDF {
        .init(.combine(.stairsIntersect, self, other, Float(max(radius, 0)), Float(max(steps, 1))))
    }
    /// Columns union: the fields join through a row of `count` circular ribs of overall
    /// size `radius` along the seam (a fluted, reeded joint).
    func columnsUnion(_ other: SDF, radius: Double, count: Int) -> SDF {
        .init(.combine(.columnsUnion, self, other, Float(max(radius, 0)), Float(max(count, 1))))
    }
    /// Columns subtraction: `other` carved out of `self`, the cut's rim fluted with ribs.
    func columnsSubtract(_ other: SDF, radius: Double, count: Int) -> SDF {
        .init(.combine(.columnsSubtract, self, other, Float(max(radius, 0)), Float(max(count, 1))))
    }
    /// Columns intersection: the overlap, its edge fluted with ribs.
    func columnsIntersect(_ other: SDF, radius: Double, count: Int) -> SDF {
        .init(.combine(.columnsIntersect, self, other, Float(max(radius, 0)), Float(max(count, 1))))
    }
    /// Pipe: only a round bead of the given `radius` running along the two outlines'
    /// crossing remains (not a boolean; both bodies vanish).
    func pipe(_ other: SDF, radius: Double) -> SDF {
        .init(.combine(.pipe, self, other, Float(max(radius, 0)), 0))
    }
    /// Engrave: a v-shaped notch of the given `depth` cut into this field along the
    /// other's outline.
    func engrave(_ other: SDF, depth: Double) -> SDF {
        .init(.combine(.engrave, self, other, Float(max(depth, 0)), 0))
    }
    /// Groove: a flat-bottomed channel cut into this field along the other's outline,
    /// `depth` deep and reaching `width` to each side of that outline.
    func groove(_ other: SDF, depth: Double, width: Double) -> SDF {
        .init(.combine(.groove, self, other, Float(max(depth, 0)), Float(max(width, 0))))
    }
    /// Tongue: a flat-topped ridge raised on this field along the other's outline,
    /// `height` tall and reaching `width` to each side of that outline (the mate of
    /// `groove(_:depth:width:)`).
    func tongue(_ other: SDF, height: Double, width: Double) -> SDF {
        .init(.combine(.tongue, self, other, Float(max(height, 0)), Float(max(width, 0))))
    }
    /// Grow the field outward by `radius` with rounded corners (`opRound`).
    func rounded(_ radius: Double) -> SDF { .init(.modify(.round, self, Float(radius))) }
    /// Hollow the field into a shell of the given `thickness` straddling its outline (`opOnion`).
    func onion(_ thickness: Double) -> SDF { .init(.modify(.onion, self, Float(thickness))) }
}

// MARK: Domain ops

public extension SDF {
    /// Mirror the field across the x and/or y axis of its frame (kaleidoscopic symmetry).
    func mirrored(x: Bool = true, y: Bool = false) -> SDF {
        .init(.transformed(.mirror(x: x, y: y), self))
    }
    /// Tile the field on a grid of `spacing`, `count` copies to each side of the
    /// origin on each axis (a spacing component of 0 leaves that axis untiled).
    func repeated(spacing: Vector2, count: Int) -> SDF {
        let n = Float(max(0, count))
        return .init(.transformed(.repeatTiles(spacing: SIMD2(Float(spacing.x), Float(spacing.y)),
                                               count: SIMD2(n, n)), self))
    }
    /// Repeat the field as `count` evenly spaced copies around the origin, folding one built
    /// wedge into a radial ring (a mandala). Offset the wedge off the origin first (`.at`) so
    /// the copies fan out around it.
    func repeatedRadially(count: Int) -> SDF {
        .init(.transformed(.polar(count: Float(max(count, 1))), self))
    }
}

// MARK: Flattening (tree -> SDFNode program + bounds)

extension SDF {
    /// The conservative local AABB plus the stack depths a composition needs.
    struct FlattenResult {
        var lo: SIMD2<Float>
        var hi: SIMD2<Float>
        var valueDepth: Int
        var pointDepth: Int
    }

    /// Append this field's instruction nodes to `nodes` (in evaluation order) and
    /// return its bounds + required stack depths. `defaultFill` colors leaves left
    /// unpainted.
    func flatten(defaultFill: Color, into nodes: inout [SDFNode]) -> FlattenResult {
        switch node {
        case let .leaf(shape, size, p0, p1, p2, extra, color):
            let rgba = (color ?? defaultFill).simd4
            nodes.append(SDFNode(kind: 0, sel: shape.rawValue, k: 0, extra: extra,
                                 color: rgba,
                                 geo0: SIMD4(size.x, size.y, p0.x, p0.y),
                                 geo1: SIMD4(p1.x, p1.y, p2.x, p2.y)))
            return FlattenResult(lo: -size, hi: size, valueDepth: 1, pointDepth: 0)

        case let .combine(op, a, b, k, n):
            let ra = a.flatten(defaultFill: defaultFill, into: &nodes)
            let rb = b.flatten(defaultFill: defaultFill, into: &nodes)
            nodes.append(SDFNode(kind: 1, sel: op.rawValue, k: k, extra: n,
                                 color: .zero, geo0: .zero, geo1: .zero))
            var lo: SIMD2<Float>, hi: SIMD2<Float>
            switch op {
            case .union, .smoothUnion, .morph, .chamferUnion, .stairsUnion, .columnsUnion:
                lo = simd_min(ra.lo, rb.lo); hi = simd_max(ra.hi, rb.hi)
            case .subtract, .smoothSubtract, .chamferSubtract, .stairsSubtract,
                 .columnsSubtract, .engrave, .groove, .tongue:
                lo = ra.lo; hi = ra.hi   // result ⊆ lhs (a tongue's ridge is the k-grow below)
            case .intersect, .smoothIntersect, .chamferIntersect, .stairsIntersect,
                 .columnsIntersect, .pipe:
                lo = simd_max(ra.lo, rb.lo); hi = simd_min(ra.hi, rb.hi)
            }
            // Each op's provable outward reach, mirroring the 3D flattener's rule (see the
            // derivation there): smooth/chamfer/stairs surfaces stay within k/2 of an
            // operand, columns/pipe/tongue reach k, and the subtract/intersect/morph
            // families cannot leave the hard op's region (morph's k is the blend
            // fraction, not a length). The AABB sizes the covering quad, so a blanket k
            // compounding per nested op only wastes fill.
            let grow: Float
            switch op {
            case .smoothUnion, .chamferUnion, .stairsUnion: grow = k / 2
            case .columnsUnion, .pipe, .tongue:             grow = k
            default:                                        grow = 0
            }
            if grow > 0 { lo -= SIMD2(repeating: grow); hi += SIMD2(repeating: grow) }
            if hi.x < lo.x || hi.y < lo.y { lo = .zero; hi = .zero }  // empty intersection
            // Value stack: eval lhs (leaves 1), eval rhs while it's held, then OP.
            return FlattenResult(lo: lo, hi: hi,
                                 valueDepth: max(ra.valueDepth, 1 + rb.valueDepth),
                                 pointDepth: max(ra.pointDepth, rb.pointDepth))

        case let .modify(m, c, amount):
            let rc = c.flatten(defaultFill: defaultFill, into: &nodes)
            nodes.append(SDFNode(kind: 2, sel: m.rawValue, k: amount, extra: 0,
                                 color: .zero, geo0: .zero, geo1: .zero))
            let grow = max(amount, 0)
            return FlattenResult(lo: rc.lo - SIMD2(repeating: grow),
                                 hi: rc.hi + SIMD2(repeating: grow),
                                 valueDepth: rc.valueDepth, pointDepth: rc.pointDepth)

        case let .transformed(t, c):
            nodes.append(Self.xformNode(t))
            let rc = c.flatten(defaultFill: defaultFill, into: &nodes)
            // RESTORE_P rescales the child distance: uniform scale by `s`, non-uniform by its
            // *min* component (the conservative Lipschitz bound that keeps the field safe);
            // translate/rotate/stretch/mirror/repeat are distance-preserving (scale 1).
            let distanceScale: Float = {
                switch t {
                case .scale(let s): return s
                case .scaleXYZ(let v): return min(v.x, v.y)
                default: return 1
                }
            }()
            nodes.append(SDFNode(kind: 4, sel: 0, k: distanceScale, extra: 0,
                                 color: .zero, geo0: .zero, geo1: .zero))
            let (lo, hi) = Self.transformBounds(t, lo: rc.lo, hi: rc.hi)
            return FlattenResult(lo: lo, hi: hi,
                                 valueDepth: rc.valueDepth, pointDepth: rc.pointDepth + 1)
        }
    }

    /// Encode a transform as its XFORM node (kind 3).
    private static func xformNode(_ t: Transform) -> SDFNode {
        switch t {
        case let .translate(v):
            return SDFNode(kind: 3, sel: 0, k: 0, extra: 0, color: .zero,
                           geo0: SIMD4(v.x, v.y, 0, 0), geo1: .zero)
        case let .rotate(a):
            return SDFNode(kind: 3, sel: 1, k: 0, extra: 0, color: .zero,
                           geo0: SIMD4(cos(a), sin(a), 0, 0), geo1: .zero)
        case let .scale(s):
            return SDFNode(kind: 3, sel: 2, k: s, extra: 0, color: .zero,
                           geo0: .zero, geo1: .zero)
        case let .scaleXYZ(v):
            return SDFNode(kind: 3, sel: 6, k: 0, extra: 0, color: .zero,
                           geo0: SIMD4(v.x, v.y, 0, 0), geo1: .zero)
        case let .stretch(h):
            return SDFNode(kind: 3, sel: 7, k: 0, extra: 0, color: .zero,
                           geo0: SIMD4(h.x, h.y, 0, 0), geo1: .zero)
        case let .mirror(x, y):
            return SDFNode(kind: 3, sel: 3, k: 0, extra: 0, color: .zero,
                           geo0: SIMD4(x ? 1 : 0, y ? 1 : 0, 0, 0), geo1: .zero)
        case let .repeatTiles(spacing, count):
            return SDFNode(kind: 3, sel: 4, k: 0, extra: 1, color: .zero,
                           geo0: SIMD4(spacing.x, spacing.y, 0, 0),
                           geo1: SIMD4(count.x, count.y, 0, 0))
        case let .polar(count):
            return SDFNode(kind: 3, sel: 5, k: 0, extra: 0, color: .zero,
                           geo0: .zero, geo1: SIMD4(count, 0, 0, 0))
        }
    }

    /// Forward-transform a child AABB (the transform moves the *shape* by the
    /// inverse of what it does to the query point).
    private static func transformBounds(_ t: Transform, lo: SIMD2<Float>, hi: SIMD2<Float>)
        -> (SIMD2<Float>, SIMD2<Float>) {
        switch t {
        case let .translate(v):
            return (lo + v, hi + v)
        case let .rotate(a):
            let c = cos(a), s = sin(a)
            let corners = [SIMD2(lo.x, lo.y), SIMD2(hi.x, lo.y), SIMD2(hi.x, hi.y), SIMD2(lo.x, hi.y)]
            var nlo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
            var nhi = SIMD2<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            for p in corners {
                let r = SIMD2(p.x * c - p.y * s, p.x * s + p.y * c)
                nlo = simd_min(nlo, r); nhi = simd_max(nhi, r)
            }
            return (nlo, nhi)
        case let .scale(s):
            return (lo * s, hi * s)
        case let .scaleXYZ(v):
            return (lo * v, hi * v)
        case let .stretch(h):
            return (lo - h, hi + h)   // elongation extends the extent by h on each side
        case let .mirror(x, y):
            var nlo = lo, nhi = hi
            if x { let m = max(abs(lo.x), abs(hi.x)); nlo.x = -m; nhi.x = m }
            if y { let m = max(abs(lo.y), abs(hi.y)); nlo.y = -m; nhi.y = m }
            return (nlo, nhi)
        case let .repeatTiles(spacing, count):
            let pad = spacing * count
            return (lo - pad, hi + pad)
        case .polar:
            // A ring of copies rotated around the origin; rotation preserves distance-from-
            // origin, so the union fits the child's bounding circle.
            var rad: Float = 0
            for p in [SIMD2(lo.x, lo.y), SIMD2(hi.x, lo.y), SIMD2(hi.x, hi.y), SIMD2(lo.x, hi.y)] {
                rad = max(rad, simd_length(p))
            }
            return (SIMD2(repeating: -rad), SIMD2(repeating: rad))
        }
    }
}
