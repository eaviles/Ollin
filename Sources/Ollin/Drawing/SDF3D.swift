import Foundation
import simd
import COllinShaders

// MARK: - 3D SDF combinators (raymarched composed signed-distance fields)
//
// `SDF3D` is the 3D sibling of `SDF`: a composable signed-distance *field* in space
// you build, store, and transform, then draw with `drawSDF3D(_:)` inside a 3D camera.
// Where the mesh primitives (`drawSphere`, `drawBox`, …) each rasterize as their own
// solid, combined `SDF3D`s *merge*: a smooth union melts two solids into one blob,
// subtraction carves one out of another, morph blends between them, and the whole
// composition is sphere-traced as a single surface, lit by the scene's lights and
// depth-composited with the rasterized meshes.
//
// A composition is a small tree (leaf shapes, binary combine ops, unary modifiers,
// and point-space transforms), flattened to a flat `SDFNode3D` program a fragment
// walks per march step (a tiny stack machine; see ShaderRaymarch.metal). Leaves carry
// no transform; positioning is transform nodes, so method-chain order is exact:
// `a.at(p).repeated…` moves then repeats, `a.repeated….at(p)` repeats then shifts.
//
// v1 is solid color per leaf (`.colored(_:)`, or the current `fill` as the default),
// uniform scale only, and self-shading without cast shadows from the marched field;
// gradient paint, domain mirror/repeat, and the scoped block form are follow-ups.
public struct SDF3D {
    /// Binary combine ops. Raw values are the `sel` the shader's OP node reads
    /// (shared with the 2D `SDF.Combine` encoding).
    enum Combine: UInt32 {
        case union = 0, smoothUnion = 1, subtract = 2, smoothSubtract = 3
        case intersect = 4, smoothIntersect = 5, morph = 6
    }
    /// Unary distance modifiers. Raw values are the `sel` the shader's MOD node reads.
    enum Modifier: UInt32 { case round = 0, onion = 1 }
    /// Point-space transforms (a scope wrapping a subtree).
    enum Transform {
        case translate(SIMD3<Float>)
        case rotate(axis: SIMD3<Float>, angle: Float)   // unit axis, radians
        case scale(Float)                               // uniform factor > 0
        case mirror(x: Bool, y: Bool, z: Bool)          // reflect across the field planes
        case repeatTiles(spacing: SIMD3<Float>, count: SIMD3<Float>)  // limited tiling
    }

    indirect enum Node {
        case leaf(shape: SDF3DShape, geo0: SIMD4<Float>, geo1: SIMD4<Float>, color: Color?)
        case combine(Combine, SDF3D, SDF3D, Float)   // op, lhs, rhs, k (smoothing / morph)
        case modify(Modifier, SDF3D, Float)          // round/onion, child, amount
        case transformed(Transform, SDF3D)           // a point-space scope around a child
    }

    var node: Node
    init(_ node: Node) { self.node = node }

    /// Guard rails for the fixed-depth shader stacks (see ShaderRaymarch.metal); a
    /// field past them is logged and skipped, never silently mis-drawn.
    static let maxValueDepth = 16
    static let maxPointDepth = 16
    static let maxNodes = 256
}

/// The leaf shapes the 3D field VM evaluates. Raw values are the `sel` an EVAL node
/// carries; the shader's `ollin_sdf3d_eval` switch must stay in sync with these.
enum SDF3DShape: UInt32 {
    case sphere = 0, box = 1, torus = 2, capsule = 3
    case roundBox = 4, cylinder = 5, cone = 6, octahedron = 7, ellipsoid = 8
}

// MARK: Leaf shapes (the common centered solids)

public extension SDF3D {
    /// A sphere of the given radius, centered at the field origin.
    static func sphere(radius: Double) -> SDF3D {
        .init(.leaf(shape: .sphere, geo0: SIMD4(Float(radius), 0, 0, 0), geo1: .zero, color: nil))
    }
    /// An axis-aligned box `width` × `height` × `depth`, centered at the field origin.
    static func box(width: Double, height: Double, depth: Double) -> SDF3D {
        .init(.leaf(shape: .box,
                    geo0: SIMD4(Float(width / 2), Float(height / 2), Float(depth / 2), 0),
                    geo1: .zero, color: nil))
    }
    /// A cube of the given side.
    static func box(size: Double) -> SDF3D { box(width: size, height: size, depth: size) }
    /// A torus lying in the xz-plane: `radius` from the center to the tube's center,
    /// `tube` the tube's own radius.
    static func torus(radius: Double, tube: Double) -> SDF3D {
        .init(.leaf(shape: .torus, geo0: SIMD4(Float(radius), Float(tube), 0, 0),
                    geo1: .zero, color: nil))
    }
    /// A capsule (a cylinder with hemispherical caps) along the y-axis, centered at the
    /// origin: `radius` is the tube/cap radius, `height` the straight length between the
    /// cap centers (so the full extent is `height + 2·radius`).
    static func capsule(radius: Double, height: Double) -> SDF3D {
        .init(.leaf(shape: .capsule, geo0: SIMD4(Float(radius), Float(height / 2), 0, 0),
                    geo1: .zero, color: nil))
    }
    /// An axis-aligned box with rounded edges, `width` × `height` × `depth` (the outer
    /// extent), the edges and corners filleted by `radius`.
    static func roundBox(width: Double, height: Double, depth: Double, radius: Double) -> SDF3D {
        .init(.leaf(shape: .roundBox,
                    geo0: SIMD4(Float(width / 2), Float(height / 2), Float(depth / 2),
                                Float(max(radius, 0))),
                    geo1: .zero, color: nil))
    }
    /// A rounded cube of the given `size` on each edge, filleted by `radius`.
    static func roundBox(size: Double, radius: Double) -> SDF3D {
        roundBox(width: size, height: size, depth: size, radius: radius)
    }
    /// A cylinder along the y-axis, centered at the origin: `radius` in the xz-plane,
    /// `height` the full length along y.
    static func cylinder(radius: Double, height: Double) -> SDF3D {
        .init(.leaf(shape: .cylinder, geo0: SIMD4(Float(radius), Float(height / 2), 0, 0),
                    geo1: .zero, color: nil))
    }
    /// A cone along the y-axis, centered at the origin: a base of `radius` at the bottom
    /// rising to a point at the top, `height` the full length along y.
    static func cone(radius: Double, height: Double) -> SDF3D {
        cone(bottomRadius: radius, topRadius: 0, height: height)
    }
    /// A truncated cone (frustum) along the y-axis, centered at the origin: `bottomRadius`
    /// at the bottom, `topRadius` at the top, `height` the full length along y.
    static func cone(bottomRadius: Double, topRadius: Double, height: Double) -> SDF3D {
        .init(.leaf(shape: .cone,
                    geo0: SIMD4(Float(height / 2), Float(bottomRadius), Float(topRadius), 0),
                    geo1: .zero, color: nil))
    }
    /// An octahedron centered at the origin, its vertices `radius` along each axis.
    static func octahedron(radius: Double) -> SDF3D {
        .init(.leaf(shape: .octahedron, geo0: SIMD4(Float(radius), 0, 0, 0),
                    geo1: .zero, color: nil))
    }
    /// An ellipsoid centered at the origin, with semi-axis radii `rx`/`ry`/`rz`.
    static func ellipsoid(rx: Double, ry: Double, rz: Double) -> SDF3D {
        .init(.leaf(shape: .ellipsoid,
                    geo0: SIMD4(Float(max(rx, 1e-4)), Float(max(ry, 1e-4)), Float(max(rz, 1e-4)), 0),
                    geo1: .zero, color: nil))
    }
}

// MARK: Transforms (point-space scopes)

public extension SDF3D {
    /// Move the field so its origin lands at `(x, y, z)`.
    func at(x: Double, y: Double, z: Double) -> SDF3D {
        translated(SIMD3(Float(x), Float(y), Float(z)))
    }
    /// Move the field so its origin lands at `p`.
    func at(_ p: Vector3) -> SDF3D { translated(p.simd3) }
    /// Rotate the field about `axis` (through its origin) by `radians`.
    func rotated(_ radians: Double, axis: Vector3) -> SDF3D {
        let a = axis.simd3
        let len = simd_length(a)
        let unit = len > 1e-6 ? a / len : SIMD3<Float>(0, 1, 0)
        return .init(.transformed(.rotate(axis: unit, angle: Float(radians)), self))
    }
    /// Rotate the field about the x-axis by `radians`.
    func rotatedX(_ radians: Double) -> SDF3D { rotated(radians, axis: Vector3(1, 0, 0)) }
    /// Rotate the field about the y-axis by `radians`.
    func rotatedY(_ radians: Double) -> SDF3D { rotated(radians, axis: Vector3(0, 1, 0)) }
    /// Rotate the field about the z-axis by `radians`.
    func rotatedZ(_ radians: Double) -> SDF3D { rotated(radians, axis: Vector3(0, 0, 1)) }
    /// Uniformly scale the field about its origin (non-uniform scale isn't a valid SDF).
    func scaled(_ s: Double) -> SDF3D { .init(.transformed(.scale(Float(max(s, 1e-4))), self)) }
    /// Mirror the field across the chosen field planes (folds the negative side onto the
    /// positive), so one built lobe reflects into a symmetric set.
    func mirrored(x: Bool = true, y: Bool = false, z: Bool = false) -> SDF3D {
        .init(.transformed(.mirror(x: x, y: y, z: z), self))
    }
    /// Tile the field on a grid of `spacing`, `count` copies to each side along each axis
    /// (a zero spacing component leaves that axis untiled). Finite, so the field stays bounded.
    func repeated(spacing: Vector3, count: Int) -> SDF3D {
        let n = Float(max(0, count))
        return .init(.transformed(.repeatTiles(
            spacing: SIMD3(Float(spacing.x), Float(spacing.y), Float(spacing.z)),
            count: SIMD3(n, n, n)), self))
    }
    /// Paint every still-unpainted leaf of the field this color (an explicit leaf
    /// `.colored` wins; the current `fill` is the fallback for whatever's left).
    func colored(_ color: Color) -> SDF3D { painting(color) }

    internal func translated(_ t: SIMD3<Float>) -> SDF3D { .init(.transformed(.translate(t), self)) }

    private func painting(_ color: Color) -> SDF3D {
        switch node {
        case let .leaf(shape, geo0, geo1, existing):
            return .init(.leaf(shape: shape, geo0: geo0, geo1: geo1, color: existing ?? color))
        case let .combine(op, a, b, k):
            return .init(.combine(op, a.painting(color), b.painting(color), k))
        case let .modify(m, c, amt):
            return .init(.modify(m, c.painting(color), amt))
        case let .transformed(t, c):
            return .init(.transformed(t, c.painting(color)))
        }
    }
}

// MARK: Combine ops & modifiers

public extension SDF3D {
    /// Hard union: the volume covered by either field.
    func union(_ other: SDF3D) -> SDF3D { .init(.combine(.union, self, other, 0)) }
    /// Smooth union: the two solids melt together over a blend of radius `k`.
    func smoothUnion(_ other: SDF3D, k: Double) -> SDF3D { .init(.combine(.smoothUnion, self, other, Float(k))) }
    /// Hard subtraction: `other` carved out of `self`.
    func subtract(_ other: SDF3D) -> SDF3D { .init(.combine(.subtract, self, other, 0)) }
    /// Smooth subtraction: `other` carved out with a blend of radius `k`.
    func smoothSubtract(_ other: SDF3D, k: Double) -> SDF3D { .init(.combine(.smoothSubtract, self, other, Float(k))) }
    /// Hard intersection: only where both fields overlap.
    func intersect(_ other: SDF3D) -> SDF3D { .init(.combine(.intersect, self, other, 0)) }
    /// Smooth intersection: the overlap, with a blend of radius `k`.
    func smoothIntersect(_ other: SDF3D, k: Double) -> SDF3D { .init(.combine(.smoothIntersect, self, other, Float(k))) }
    /// Morph between two fields: `amount` 0 is `self`, 1 is `other` (the shape itself
    /// interpolates, not a crossfade).
    func morph(_ other: SDF3D, amount: Double) -> SDF3D {
        .init(.combine(.morph, self, other, Float(min(max(amount, 0), 1))))
    }
    /// Grow the field outward by `radius` with rounded corners (`opRound`).
    func rounded(_ radius: Double) -> SDF3D { .init(.modify(.round, self, Float(radius))) }
    /// Hollow the field into a shell of the given `thickness` straddling its surface (`opOnion`).
    func onion(_ thickness: Double) -> SDF3D { .init(.modify(.onion, self, Float(thickness))) }
}

// MARK: Flattening (tree -> SDFNode3D program + bounds)

extension SDF3D {
    /// The conservative local AABB plus the stack depths a composition needs.
    struct FlattenResult {
        var lo: SIMD3<Float>
        var hi: SIMD3<Float>
        var valueDepth: Int
        var pointDepth: Int
    }

    /// Append this field's instruction nodes to `nodes` (in evaluation order) and
    /// return its bounds + required stack depths. `defaultFill` colors leaves left
    /// unpainted.
    func flatten(defaultFill: Color, into nodes: inout [SDFNode3D]) -> FlattenResult {
        switch node {
        case let .leaf(shape, geo0, geo1, color):
            let rgba = (color ?? defaultFill).simd4
            nodes.append(SDFNode3D(kind: 0, sel: shape.rawValue, k: 0, extra: 0,
                                   color: rgba, geo0: geo0, geo1: geo1))
            let half = SDF3D.leafHalfExtent(shape, geo0)
            return FlattenResult(lo: -half, hi: half, valueDepth: 1, pointDepth: 0)

        case let .combine(op, a, b, k):
            let ra = a.flatten(defaultFill: defaultFill, into: &nodes)
            let rb = b.flatten(defaultFill: defaultFill, into: &nodes)
            nodes.append(SDFNode3D(kind: 1, sel: op.rawValue, k: k, extra: 0,
                                   color: .zero, geo0: .zero, geo1: .zero))
            var lo: SIMD3<Float>, hi: SIMD3<Float>
            switch op {
            case .union, .smoothUnion, .morph:
                lo = simd_min(ra.lo, rb.lo); hi = simd_max(ra.hi, rb.hi)
            case .subtract, .smoothSubtract:
                lo = ra.lo; hi = ra.hi                     // result ⊆ lhs
            case .intersect, .smoothIntersect:
                lo = simd_max(ra.lo, rb.lo); hi = simd_min(ra.hi, rb.hi)
            }
            if k > 0 { lo -= SIMD3(repeating: k); hi += SIMD3(repeating: k) }
            if hi.x < lo.x || hi.y < lo.y || hi.z < lo.z { lo = .zero; hi = .zero }  // empty intersection
            return FlattenResult(lo: lo, hi: hi,
                                 valueDepth: max(ra.valueDepth, 1 + rb.valueDepth),
                                 pointDepth: max(ra.pointDepth, rb.pointDepth))

        case let .modify(m, c, amount):
            let rc = c.flatten(defaultFill: defaultFill, into: &nodes)
            nodes.append(SDFNode3D(kind: 2, sel: m.rawValue, k: amount, extra: 0,
                                   color: .zero, geo0: .zero, geo1: .zero))
            let grow = max(amount, 0)
            return FlattenResult(lo: rc.lo - SIMD3(repeating: grow),
                                 hi: rc.hi + SIMD3(repeating: grow),
                                 valueDepth: rc.valueDepth, pointDepth: rc.pointDepth)

        case let .transformed(t, c):
            nodes.append(Self.xformNode(t))
            let rc = c.flatten(defaultFill: defaultFill, into: &nodes)
            let distanceScale: Float = { if case .scale(let s) = t { return s } else { return 1 } }()
            nodes.append(SDFNode3D(kind: 4, sel: 0, k: distanceScale, extra: 0,
                                   color: .zero, geo0: .zero, geo1: .zero))
            let (lo, hi) = Self.transformBounds(t, lo: rc.lo, hi: rc.hi)
            return FlattenResult(lo: lo, hi: hi,
                                 valueDepth: rc.valueDepth, pointDepth: rc.pointDepth + 1)
        }
    }

    /// The local-space half-extent of a leaf shape (for the conservative AABB).
    static func leafHalfExtent(_ shape: SDF3DShape, _ g: SIMD4<Float>) -> SIMD3<Float> {
        switch shape {
        case .sphere:     return SIMD3(repeating: g.x)
        case .box:        return SIMD3(g.x, g.y, g.z)
        case .torus:      return SIMD3(g.x + g.y, g.y, g.x + g.y)
        case .capsule:    return SIMD3(g.x, g.y + g.x, g.x)
        case .roundBox:   return SIMD3(g.x, g.y, g.z)             // outer half-extents (rounding is inset)
        case .cylinder:   return SIMD3(g.x, g.y, g.x)            // radius, half-height, radius
        case .cone:       let r = max(g.y, g.z); return SIMD3(r, g.x, r)  // max radius, half-height
        case .octahedron: return SIMD3(repeating: g.x)
        case .ellipsoid:  return SIMD3(g.x, g.y, g.z)
        }
    }

    /// Encode a transform as its XFORM node (kind 3).
    private static func xformNode(_ t: Transform) -> SDFNode3D {
        switch t {
        case let .translate(v):
            return SDFNode3D(kind: 3, sel: 0, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(v.x, v.y, v.z, 0), geo1: .zero)
        case let .rotate(axis, angle):
            return SDFNode3D(kind: 3, sel: 1, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(axis.x, axis.y, axis.z, 0),
                             geo1: SIMD4(angle, 0, 0, 0))
        case let .scale(s):
            return SDFNode3D(kind: 3, sel: 2, k: s, extra: 0, color: .zero,
                             geo0: .zero, geo1: .zero)
        case let .mirror(x, y, z):
            return SDFNode3D(kind: 3, sel: 3, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(x ? 1 : 0, y ? 1 : 0, z ? 1 : 0, 0), geo1: .zero)
        case let .repeatTiles(spacing, count):
            return SDFNode3D(kind: 3, sel: 4, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(spacing.x, spacing.y, spacing.z, 0),
                             geo1: SIMD4(count.x, count.y, count.z, 0))
        }
    }

    /// Forward-transform a child AABB (the transform moves the *shape* by the
    /// inverse of what it does to the query point).
    private static func transformBounds(_ t: Transform, lo: SIMD3<Float>, hi: SIMD3<Float>)
        -> (SIMD3<Float>, SIMD3<Float>) {
        switch t {
        case let .translate(v):
            return (lo + v, hi + v)
        case let .rotate(axis, angle):
            let r = simd_float3x3(simd_quatf(angle: angle, axis: axis))
            var nlo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var nhi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for cx in [lo.x, hi.x] {
                for cy in [lo.y, hi.y] {
                    for cz in [lo.z, hi.z] {
                        let p = r * SIMD3(cx, cy, cz)
                        nlo = simd_min(nlo, p); nhi = simd_max(nhi, p)
                    }
                }
            }
            return (nlo, nhi)
        case let .scale(s):
            return (lo * s, hi * s)
        case let .mirror(x, y, z):
            var nlo = lo, nhi = hi
            if x { let m = max(abs(lo.x), abs(hi.x)); nlo.x = -m; nhi.x = m }
            if y { let m = max(abs(lo.y), abs(hi.y)); nlo.y = -m; nhi.y = m }
            if z { let m = max(abs(lo.z), abs(hi.z)); nlo.z = -m; nhi.z = m }
            return (nlo, nhi)
        case let .repeatTiles(spacing, count):
            let pad = spacing * count
            return (lo - pad, hi + pad)
        }
    }
}
