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
// Per-axis sizing is `stretched` (an exact elongation) or `scaled(x:y:z:)` (a conservative
// bound); a leaf takes a solid color (`.colored(_:)`, or the current `fill`), and a gradient
// `fill` paints the whole merged surface by screen position.
public struct SDF3D {
    /// Binary combine ops. Raw values are the `sel` the shader's OP node reads
    /// (shared with the 2D `SDF.Combine` encoding).
    enum Combine: UInt32 {
        case union = 0, smoothUnion = 1, subtract = 2, smoothSubtract = 3
        case intersect = 4, smoothIntersect = 5, morph = 6
        case chamferUnion = 7, chamferSubtract = 8, chamferIntersect = 9
        case stairsUnion = 10, stairsSubtract = 11, stairsIntersect = 12
        case columnsUnion = 13, columnsSubtract = 14, columnsIntersect = 15
        case pipe = 16, engrave = 17, groove = 18, tongue = 19
    }
    /// Unary distance modifiers. Raw values are the `sel` the shader's MOD node reads.
    enum Modifier: UInt32 { case round = 0, onion = 1, displaceSine = 2, displaceNoise = 3 }
    /// Point-space transforms (a scope wrapping a subtree).
    enum Transform {
        case translate(SIMD3<Float>)
        case rotate(axis: SIMD3<Float>, angle: Float)   // unit axis, radians
        case scale(Float)                               // uniform factor > 0
        case scaleXYZ(SIMD3<Float>)                     // non-uniform factors (conservative SDF bound)
        case stretch(SIMD3<Float>)                      // per-axis elongation half-extent (exact SDF)
        case mirror(x: Bool, y: Bool, z: Bool)          // reflect across the field planes
        case repeatTiles(spacing: SIMD3<Float>, count: SIMD3<Float>)  // limited tiling
        case polar(axis: SIMD3<Float>, count: Float)    // radial repeat around an axis
        case twist(Float)                               // radians per unit of height, around y
        case bend(Float)                                // radians per unit along x, about z
    }

    indirect enum Node {
        case leaf(shape: SDF3DShape, geo0: SIMD4<Float>, geo1: SIMD4<Float>, color: Color?)
        case combine(Combine, SDF3D, SDF3D, Float, Float)   // op, lhs, rhs, k (smoothing / morph / joint size), extra (stairs steps)
        case modify(Modifier, SDF3D, Float, Float)   // round/onion/displace, child, amount, frequency (displace only)
        case transformed(Transform, SDF3D)           // a point-space scope around a child
        case voxelized(SDF3D, Voxels)                // the child rebuilt as blocks on a grid
        case extruded(SDF, Float)                    // a flat field stood up, half this depth each way in z
    }

    /// How `voxelized` cuts and shades its blocks (field units and 0...1 amounts).
    struct Voxels {
        var size: Float
        var gap: Float
        var jitter: Float
        var seams: Float
        var occlusion: Float
        var seed: Float
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
    case plane = 9
    case line = 10, hexPrism = 11, pyramid = 12, cappedTorus = 13, link = 14
    case mandelbulb = 15, mengerSponge = 16, mandelbox = 17
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
    /// An ellipsoid centered at the origin, with semi-axis radii `radiusX`/`radiusY`/`radiusZ`.
    static func ellipsoid(radiusX: Double, radiusY: Double, radiusZ: Double) -> SDF3D {
        .init(.leaf(shape: .ellipsoid,
                    geo0: SIMD4(Float(max(radiusX, 1e-4)), Float(max(radiusY, 1e-4)), Float(max(radiusZ, 1e-4)), 0),
                    geo1: .zero, color: nil))
    }
    /// An infinite plane: the half-space boundary at signed distance `offset` from the origin
    /// along `normal` (the default is a horizontal ground plane through the origin, facing up,
    /// so `offset` reads as its height). A plane has no finite bounds, so it marches to the
    /// camera's far plane; merge it with the scene's shapes as one field (and `castShadows()`)
    /// to ground them with soft self-shadows. A plane is the one leaf the scoped block form
    /// can't capture (it has no mesh primitive), so build it through the `SDF3D` value type.
    static func plane(normal: Vector3 = Vector3(0, 1, 0), offset: Double = 0) -> SDF3D {
        let n = normal.simd3
        let len = simd_length(n)
        let unit = len > 1e-6 ? n / len : SIMD3<Float>(0, 1, 0)
        return .init(.leaf(shape: .plane, geo0: SIMD4(unit.x, unit.y, unit.z, Float(offset)),
                           geo1: .zero, color: nil))
    }
    /// A capsule stroke between two arbitrary points (the free-form sibling of the centered
    /// `capsule`): the armature primitive; chain a few to sketch limbs, branches, scaffolds.
    static func line(from a: Vector3, to b: Vector3, radius: Double) -> SDF3D {
        .init(.leaf(shape: .line,
                    geo0: SIMD4(Float(a.x), Float(a.y), Float(a.z), Float(max(radius, 0))),
                    geo1: SIMD4(Float(b.x), Float(b.y), Float(b.z), 0), color: nil))
    }
    /// A hexagonal prism along the y-axis, centered at the origin: `radius` is measured to
    /// the flat sides (the inradius), `height` the full length along y.
    static func hexPrism(radius: Double, height: Double) -> SDF3D {
        .init(.leaf(shape: .hexPrism, geo0: SIMD4(Float(radius), Float(height / 2), 0, 0),
                    geo1: .zero, color: nil))
    }
    /// A square pyramid centered at the origin: `base` on a side, rising `height` from its
    /// base plane to the apex.
    static func pyramid(base: Double, height: Double) -> SDF3D {
        .init(.leaf(shape: .pyramid, geo0: SIMD4(Float(max(base, 1e-4)), Float(max(height, 1e-4)), 0, 0),
                    geo1: .zero, color: nil))
    }
    /// An open arc of a torus in the xz-plane (a horseshoe / croissant): the ring spans
    /// `angle` radians to each side of +z, `radius` from the center to the tube's center,
    /// `tube` the tube's own radius. A full turn (`angle: .pi`) closes back into `torus`.
    static func cappedTorus(radius: Double, tube: Double, angle: Double) -> SDF3D {
        let half = min(max(angle, 0.01), .pi)
        return .init(.leaf(shape: .cappedTorus,
                           geo0: SIMD4(Float(sin(half)), Float(cos(half)), Float(radius), Float(tube)),
                           geo1: .zero, color: nil))
    }
    /// A chain link along the y-axis, centered at the origin: a torus stretched straight for
    /// `height` in the middle, `radius` from the axis to the tube's center, `tube` the tube's
    /// own radius. Stack a few with alternating `rotatedY(.pi / 2)` for a chain.
    static func link(height: Double, radius: Double, tube: Double) -> SDF3D {
        .init(.leaf(shape: .link,
                    geo0: SIMD4(Float(max(height, 0) / 2), Float(radius), Float(tube), 0),
                    geo1: .zero, color: nil))
    }
}

// MARK: Fractal leaves (distance-estimated)
//
// Three classic 3D fractals as leaves. None has a closed-form distance: each one *estimates*
// it by iterating the fractal's own map and reading the escape rate, so the march leans on
// the step fudge the way a smooth union does. They compose like any other leaf (melt, carve,
// mirror, repeat), each carries its own bound, and `iterations` is the detail-versus-cost
// dial (every march step runs the loop). Value-type-only: no mesh primitive stands in for
// them in the scoped block form.

public extension SDF3D {
    /// The Mandelbulb: the triplex power-`power` map iterated from each point, kept where the
    /// orbit stays bounded. `power` 8 is the classic bulb, with the family's (`power` - 1)-fold
    /// symmetry about the y-axis (seven lobes around the equator), and a fractional value is
    /// a different picture (sweep it for the breathing animation). `radius` is the ball the
    /// set fits in; a low `iterations` draws a skin a few percent past it. Each march step
    /// costs `iterations` trigonometric rounds, so raise it for close-ups only.
    static func mandelbulb(power: Double = 8, iterations: Int = 8, radius: Double = 1) -> SDF3D {
        let n = min(max(power, 1.5), 32)
        // Any point past the escape radius 2^(1/(n-1)) diverges, so the set lies inside it;
        // mapping that ball onto `radius` makes the parameter the bulb's outer size.
        let escape = pow(2.0, 1.0 / (n - 1.0))
        let r = max(radius, 1e-4)
        return .init(.leaf(shape: .mandelbulb,
                           geo0: SIMD4(Float(r / escape), Float(n), Float(min(max(iterations, 1), 32)), Float(r)),
                           geo1: .zero, color: nil))
    }
    /// The Menger sponge: a cube `size` on a side with the middle third of every face bored
    /// through, `iterations` times over (0 is the plain cube, 4 is sub-pixel at a typical
    /// framing). Its silhouette down any axis is the Sierpinski carpet.
    static func mengerSponge(iterations: Int = 4, size: Double = 2) -> SDF3D {
        .init(.leaf(shape: .mengerSponge,
                    geo0: SIMD4(Float(max(size, 1e-4) / 2), Float(min(max(iterations, 0), 8)), 0, 0),
                    geo1: .zero, color: nil))
    }
    /// The Mandelbox: a box fold and a sphere fold, then a scale, iterated from each point.
    /// `scale` is the fractal's own parameter (-1.5 is the classic; a magnitude near 1 makes
    /// the set blow up, so it is held at 1.1 or more). The canonical set sits in a known cube
    /// for each scale, and that cube is scaled onto `size` on a side and clipped to it, so
    /// the leaf is bounded whatever the scale.
    static func mandelbox(scale: Double = -1.5, iterations: Int = 12, size: Double = 2) -> SDF3D {
        let magnitude = min(max(abs(scale), 1.1), 4)
        let s = scale < 0 ? -magnitude : magnitude
        // The half-width of the cube the canonical set (fold limit 1, radii 0.5 and 1) sits
        // in: for a positive scale the far points settle at 2(s+1)/(s-1) per axis; a negative
        // scale keeps everything inside 2 (the corner at (2, 2, 2) is the farthest point).
        let halfWidth = s > 0 ? 2 * (s + 1) / (s - 1) : 2
        let clip = max(size, 1e-4) / 2
        return .init(.leaf(shape: .mandelbox,
                           geo0: SIMD4(Float(clip / halfWidth), Float(s), Float(min(max(iterations, 1), 32)), Float(clip)),
                           geo1: SIMD4(0.25, 1.0, 1.0, 0), color: nil))
    }
}

// MARK: Transforms (point-space scopes)

public extension SDF3D {
    /// Move the field so its origin lands at `(x, y, z)`.
    func at(_ x: Double, _ y: Double, _ z: Double) -> SDF3D {
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
    /// Uniformly scale the field about its origin. Uniform scale is an exact SDF operation;
    /// for per-axis sizing prefer `stretched` (exact) or `scaled(x:y:z:)` (a bound).
    func scaled(_ s: Double) -> SDF3D { .init(.transformed(.scale(Float(max(s, 1e-4))), self)) }
    /// Non-uniformly scale the field per axis about its origin. Non-uniform scale isn't a valid
    /// distance field (it distorts space), so the result is a conservative *bound*: the surface
    /// is right, but smooth blends, rounding, and onion shells distort under strong anisotropy
    /// (fine up to ~2–3×). For the common "stretch a shape longer" case, prefer `stretched`,
    /// which stays exact.
    func scaled(x: Double, y: Double, z: Double) -> SDF3D {
        .init(.transformed(.scaleXYZ(SIMD3(Float(max(x, 1e-4)), Float(max(y, 1e-4)), Float(max(z, 1e-4)))), self))
    }
    /// Stretch (elongate) the field per axis by inserting straight space, the way a sphere becomes
    /// a capsule: each value extends the field by that much in *each* direction along the axis (a
    /// sphere of radius r stretched by `x` reaches r + x along ±x). Unlike `scaled(x:y:z:)` this
    /// stays an exact distance field, so smooth blends, rounding, and onion shells don't distort.
    func stretched(x: Double = 0, y: Double = 0, z: Double = 0) -> SDF3D {
        .init(.transformed(.stretch(SIMD3(Float(max(x, 0)), Float(max(y, 0)), Float(max(z, 0)))), self))
    }
    /// Mirror the field across the chosen field planes (folds the negative side onto the
    /// positive), so one built lobe reflects into a symmetric set.
    func mirrored(x: Bool = true, y: Bool = false, z: Bool = false) -> SDF3D {
        .init(.transformed(.mirror(x: x, y: y, z: z), self))
    }
    /// Twist the field around the y-axis: the cross-section rotates by `radiansPerUnit`
    /// for every unit of height (a screw of the whole form). Rotate the field first to
    /// twist around another axis. The march compensates for the distorted field, so a
    /// strong twist trades some speed for a surface that never breaks up.
    func twisted(_ radiansPerUnit: Double) -> SDF3D {
        .init(.transformed(.twist(Float(radiansPerUnit)), self))
    }
    /// Bend the field about the z-axis: the form curls by `radiansPerUnit` for every unit
    /// it runs along x (a bar arcs, a slab curls). Same march compensation as `twisted`.
    func bent(_ radiansPerUnit: Double) -> SDF3D {
        .init(.transformed(.bend(Float(radiansPerUnit)), self))
    }
    /// Tile the field on a grid of `spacing`, `count` copies to each side along each axis
    /// (a zero spacing component leaves that axis untiled). Finite, so the field stays bounded.
    func repeated(spacing: Vector3, count: Int) -> SDF3D {
        let n = Float(max(0, count))
        return .init(.transformed(.repeatTiles(
            spacing: SIMD3(Float(spacing.x), Float(spacing.y), Float(spacing.z)),
            count: SIMD3(n, n, n)), self))
    }
    /// Repeat the field as an evenly spaced ring of `count` copies around `axis` (through the
    /// origin), folding one built wedge into a radial array (a rosette or sunburst). Offset
    /// the wedge off the axis first (`.at(x: r, …)`) so the copies fan out around it.
    func repeatedRadially(count: Int, around axis: Vector3 = Vector3(0, 1, 0)) -> SDF3D {
        let a = axis.simd3
        let len = simd_length(a)
        let unit = len > 1e-6 ? a / len : SIMD3<Float>(0, 1, 0)
        return .init(.transformed(.polar(axis: unit, count: Float(max(count, 1))), self))
    }
    /// Paint every still-unpainted leaf of the field this color (an explicit leaf
    /// `.colored` wins; the current `fill` is the fallback for whatever's left).
    func colored(_ color: Color) -> SDF3D { painting(color) }

    internal func translated(_ t: SIMD3<Float>) -> SDF3D { .init(.transformed(.translate(t), self)) }

    private func painting(_ color: Color) -> SDF3D {
        switch node {
        case let .leaf(shape, geo0, geo1, existing):
            return .init(.leaf(shape: shape, geo0: geo0, geo1: geo1, color: existing ?? color))
        case let .combine(op, a, b, k, n):
            return .init(.combine(op, a.painting(color), b.painting(color), k, n))
        case let .modify(m, c, amt, freq):
            return .init(.modify(m, c.painting(color), amt, freq))
        case let .transformed(t, c):
            return .init(.transformed(t, c.painting(color)))
        case let .voxelized(c, v):
            return .init(.voxelized(c.painting(color), v))
        case let .extruded(f, h):
            return .init(.extruded(f.colored(color), h))
        }
    }

    /// The field with every `voxelized` scope inside it replaced by its child: the
    /// shader keeps one voxel scope's state at a time, so a scope nested in another
    /// takes the outer one's blocks only.
    internal func strippingVoxels() -> SDF3D {
        switch node {
        case .leaf:
            return self
        case let .combine(op, a, b, k, n):
            return .init(.combine(op, a.strippingVoxels(), b.strippingVoxels(), k, n))
        case let .modify(m, c, amt, freq):
            return .init(.modify(m, c.strippingVoxels(), amt, freq))
        case let .transformed(t, c):
            return .init(.transformed(t, c.strippingVoxels()))
        case let .voxelized(c, _):
            return c.strippingVoxels()
        case .extruded:
            return self
        }
    }
}

// MARK: A flat field as a slab

public extension SDF {
    /// The flat field stood up as a solid `depth` thick: the 2D composition, every
    /// shape, combine, modifier, and transform in it, read in the x and y plane of the
    /// 3D field and extruded half of `depth` each way along z, centered on z = 0. The
    /// result is an `SDF3D`, so it takes the 3D transforms, joins other 3D fields,
    /// and voxelizes:
    ///
    /// ```swift
    /// let badge = SDF.circle(radius: 1).smoothUnion(SDF.rect(width: 1.6, height: 0.5).at(0.9, 0), k: 0.3)
    /// drawSDF3D(badge.extruded(depth: 0.4).rotatedX(-0.5))
    /// drawSDF3D(badge.extruded(depth: 0.25).voxelized(size: 0.25).at(3, 0, 0))   // pixel art
    /// ```
    ///
    /// The flat program is run as the 3D walk's own instructions, so a smooth union
    /// melts in the plane and the slab's faces stay flat: the distance is the exact
    /// extrusion of the 2D field's distance, which for a circle is the cylinder and
    /// for a rectangle the box, to the last bit. The slab stands as the canvas shows
    /// the field: the flat program was composed where y runs down, so the walk runs
    /// it inside a half turn about x, the turn `Mesh.text` gives a word, and a
    /// composition drawn with `drawSDF` stands up the way it was drawn. A `depth`
    /// below a thousandth is raised to it.
    func extruded(depth: Double) -> SDF3D {
        SDF3D(.extruded(self, Float(max(depth, 1e-3) / 2)))
    }
}

// MARK: Combine ops & modifiers

public extension SDF3D {
    /// Hard union: the volume covered by either field.
    func union(_ other: SDF3D) -> SDF3D { .init(.combine(.union, self, other, 0, 0)) }
    /// Smooth union: the two solids melt together over a blend of radius `k`.
    func smoothUnion(_ other: SDF3D, k: Double) -> SDF3D { .init(.combine(.smoothUnion, self, other, Float(k), 0)) }
    /// Hard subtraction: `other` carved out of `self`.
    func subtract(_ other: SDF3D) -> SDF3D { .init(.combine(.subtract, self, other, 0, 0)) }
    /// Smooth subtraction: `other` carved out with a blend of radius `k`.
    func smoothSubtract(_ other: SDF3D, k: Double) -> SDF3D { .init(.combine(.smoothSubtract, self, other, Float(k), 0)) }
    /// Hard intersection: only where both fields overlap.
    func intersect(_ other: SDF3D) -> SDF3D { .init(.combine(.intersect, self, other, 0, 0)) }
    /// Smooth intersection: the overlap, with a blend of radius `k`.
    func smoothIntersect(_ other: SDF3D, k: Double) -> SDF3D { .init(.combine(.smoothIntersect, self, other, Float(k), 0)) }
    /// Morph between two fields: `amount` 0 is `self`, 1 is `other` (the shape itself
    /// interpolates, not a crossfade).
    func morph(_ other: SDF3D, amount: Double) -> SDF3D {
        .init(.combine(.morph, self, other, Float(min(max(amount, 0), 1)), 0))
    }
    /// Grow the field outward by `radius` with rounded corners (`opRound`).
    func rounded(_ radius: Double) -> SDF3D { .init(.modify(.round, self, Float(radius), 0)) }
    /// Hollow the field into a shell of the given `thickness` straddling its surface (`opOnion`).
    func onion(_ thickness: Double) -> SDF3D { .init(.modify(.onion, self, Float(thickness), 0)) }
    /// Chamfer union: the solids join with a 45° bevel of the given size along the seam
    /// (a machined joint; colors stay a crisp pick of the nearer solid, not a melt).
    func chamferUnion(_ other: SDF3D, radius: Double) -> SDF3D {
        .init(.combine(.chamferUnion, self, other, Float(max(radius, 0)), 0))
    }
    /// Chamfer subtraction: `other` carved out of `self`, the cut's rim beveled at 45°.
    func chamferSubtract(_ other: SDF3D, radius: Double) -> SDF3D {
        .init(.combine(.chamferSubtract, self, other, Float(max(radius, 0)), 0))
    }
    /// Chamfer intersection: the overlap, its edge beveled at 45°.
    func chamferIntersect(_ other: SDF3D, radius: Double) -> SDF3D {
        .init(.combine(.chamferIntersect, self, other, Float(max(radius, 0)), 0))
    }
    /// Stairs union: the solids join through a staircase of `steps` steps over `radius`
    /// along the seam (colors stay a crisp pick of the nearer solid).
    func stairsUnion(_ other: SDF3D, radius: Double, steps: Int) -> SDF3D {
        .init(.combine(.stairsUnion, self, other, Float(max(radius, 0)), Float(max(steps, 1))))
    }
    /// Stairs subtraction: `other` carved out of `self`, the cut's rim stepped.
    func stairsSubtract(_ other: SDF3D, radius: Double, steps: Int) -> SDF3D {
        .init(.combine(.stairsSubtract, self, other, Float(max(radius, 0)), Float(max(steps, 1))))
    }
    /// Stairs intersection: the overlap, its edge stepped.
    func stairsIntersect(_ other: SDF3D, radius: Double, steps: Int) -> SDF3D {
        .init(.combine(.stairsIntersect, self, other, Float(max(radius, 0)), Float(max(steps, 1))))
    }
    /// Columns union: the solids join through a row of `count` circular ribs of overall
    /// size `radius` along the seam (a fluted, reeded joint).
    func columnsUnion(_ other: SDF3D, radius: Double, count: Int) -> SDF3D {
        .init(.combine(.columnsUnion, self, other, Float(max(radius, 0)), Float(max(count, 1))))
    }
    /// Columns subtraction: `other` carved out of `self`, the cut's rim fluted with ribs.
    func columnsSubtract(_ other: SDF3D, radius: Double, count: Int) -> SDF3D {
        .init(.combine(.columnsSubtract, self, other, Float(max(radius, 0)), Float(max(count, 1))))
    }
    /// Columns intersection: the overlap, its edge fluted with ribs.
    func columnsIntersect(_ other: SDF3D, radius: Double, count: Int) -> SDF3D {
        .init(.combine(.columnsIntersect, self, other, Float(max(radius, 0)), Float(max(count, 1))))
    }
    /// Pipe: only a round bead of the given `radius` running along the two surfaces'
    /// intersection curve remains (not a boolean; both bodies vanish). A sphere piped
    /// with a plane leaves a ring; a box piped with a sphere leaves the crossing loops.
    func pipe(_ other: SDF3D, radius: Double) -> SDF3D {
        .init(.combine(.pipe, self, other, Float(max(radius, 0)), 0))
    }
    /// Engrave: a v-shaped notch of the given `depth` cut into this solid along the
    /// other's surface (score lines, inscriptions, panel joints).
    func engrave(_ other: SDF3D, depth: Double) -> SDF3D {
        .init(.combine(.engrave, self, other, Float(max(depth, 0)), 0))
    }
    /// Groove: a flat-bottomed channel cut into this solid along the other's surface,
    /// `depth` deep and reaching `width` to each side of that surface.
    func groove(_ other: SDF3D, depth: Double, width: Double) -> SDF3D {
        .init(.combine(.groove, self, other, Float(max(depth, 0)), Float(max(width, 0))))
    }
    /// Tongue: a flat-topped ridge raised on this solid along the other's surface,
    /// `height` tall and reaching `width` to each side of that surface (the mate of
    /// `groove(_:depth:width:)`, the carpentry joint).
    func tongue(_ other: SDF3D, height: Double, width: Double) -> SDF3D {
        .init(.combine(.tongue, self, other, Float(max(height, 0)), Float(max(width, 0))))
    }
    /// Ripple the surface with a sine-product displacement: `amplitude` is how far the
    /// surface swells and dents (in field units), `frequency` how tightly the ripples
    /// pack. The march compensates for the displaced field's steeper gradient, so strong
    /// settings trade some speed for a surface that never breaks up.
    func displaced(amplitude: Double, frequency: Double) -> SDF3D {
        .init(.modify(.displaceSine, self, Float(max(amplitude, 0)), Float(max(frequency, 0))))
    }
    /// Roughen the surface with signed 3D value noise: an organic, rock-like relief of
    /// the given `amplitude` (field units) and `frequency`. Same march compensation as
    /// `displaced(amplitude:frequency:)`.
    func roughened(amplitude: Double, frequency: Double) -> SDF3D {
        .init(.modify(.displaceNoise, self, Float(max(amplitude, 0)), Float(max(frequency, 0))))
    }

    /// Rebuild the field out of cubes `size` units on a side, on a grid aligned to
    /// the field's origin: every cell whose center is inside the field becomes a
    /// block, so a sphere becomes a voxel model and a thin slab becomes pixel art.
    ///
    /// ```swift
    /// drawSDF3D(.sphere(radius: 1).smoothUnion(.torus(radius: 1.1, tube: 0.25), k: 0.3)
    ///     .voxelized(size: 0.12))
    /// ```
    ///
    /// Each block takes the color the field has at its center, and is shaded as a
    /// block: its faces are flat and square to the grid, so it lights in steps;
    /// `occlusion` darkens a face where a neighbor rises beside it, the crease
    /// darkening of stacked blocks; `seams` darkens a thin line along every face's
    /// edges, so a flat run of blocks still reads as bricks; and `jitter` moves each
    /// block's tone by a seeded amount of its own, the same block the same tone on
    /// every frame for one `seed`. `gap` from 0 to 0.9 shrinks every block inside its
    /// cell, opening real grooves between them. Smaller blocks cost more to march,
    /// since the march steps no farther than half a block near the surface. A
    /// `voxelized` field inside another takes the outer one's blocks only.
    func voxelized(size: Double, gap: Double = 0, jitter: Double = 0.08, seams: Double = 0.3,
                   occlusion: Double = 0.5, seed: Int = 0) -> SDF3D {
        .init(.voxelized(self, Voxels(size: Float(max(size, 1e-3)),
                                      gap: Float(min(max(gap, 0), 0.9)),
                                      jitter: Float(min(max(jitter, 0), 1)),
                                      seams: Float(min(max(seams, 0), 1)),
                                      occlusion: Float(min(max(occlusion, 0), 1)),
                                      seed: Float(seed % 4096))))
    }
}

// MARK: Flattening (tree -> SDFNode3D program + bounds)

extension SDF3D {
    /// What a skip may assume of a subtree: outside the box `lo…hi` its distance is at
    /// least `slope` times the distance to that box. A slope of zero says nothing is
    /// known (an estimated leaf, a plane, a flat program stood up), and no skip steps
    /// past such a subtree. This is not the drawing bounds beside it, which are padded
    /// for the march: this box is the one the inequality is proven against, node by
    /// node, and the proofs are in `ARCHITECTURE.md` (*A field's skips*).
    struct SkipBound {
        var lo: SIMD3<Float> = .zero
        var hi: SIMD3<Float> = .zero
        var slope: Float = 0

        static let none = SkipBound()

        var holds: Bool {
            guard slope > 0, slope.isFinite else { return false }
            for axis in 0 ..< 3 {
                guard lo[axis].isFinite, hi[axis].isFinite, lo[axis] <= hi[axis] else { return false }
            }
            return true
        }

        /// Both subtrees in one box, at the lower of their slopes: the lesser of two
        /// distances is at least the distance to the box that holds both.
        func hull(_ other: SkipBound) -> SkipBound {
            guard holds, other.holds else { return .none }
            return SkipBound(lo: simd_min(lo, other.lo), hi: simd_max(hi, other.hi),
                             slope: min(slope, other.slope))
        }

        /// The bound once the distance may read up to `amount` lower (a rounding, a
        /// blend's bulge, a displacement): the box grows by that much over the slope,
        /// since a box grown by a length is at least that much nearer every point.
        func lowered(by amount: Float) -> SkipBound {
            guard holds, amount.isFinite else { return .none }
            guard amount > 0 else { return self }
            let grow = SIMD3<Float>(repeating: amount / slope)
            return SkipBound(lo: lo - grow, hi: hi + grow, slope: slope)
        }

        var volume: Float {
            let size = hi - lo
            return size.x * size.y * size.z
        }

        /// Whether the box holds another one whole.
        func contains(lo otherLo: SIMD3<Float>, hi otherHi: SIMD3<Float>) -> Bool {
            for axis in 0 ..< 3 where otherLo[axis] < lo[axis] || otherHi[axis] > hi[axis] { return false }
            return true
        }
    }

    /// When a field's program is written with skips (`Drawer.sdf3DSkipPolicy`).
    enum SkipPolicy {
        /// A program of `skipMinNodes` instructions or more: a field of many parts,
        /// where most of them are far from any one point.
        case automatic
        case always
        case never
    }

    /// The program length from which a field is written with skips. Below it a skip
    /// costs about what it saves; the picture is the same either way.
    static let skipMinNodes = 24

    /// The conservative local AABB plus the stack depths a composition needs.
    struct FlattenResult {
        var lo: SIMD3<Float>
        var hi: SIMD3<Float>
        var valueDepth: Int
        var pointDepth: Int
        var unbounded: Bool = false   // contains an infinite plane (no finite AABB)
        var normalEpsilon: Float = 0  // the widest gradient step a leaf asked for (local units;
                                      // 0 = the shader's default), so a fractal's normal reads
                                      // its surface rather than the estimate's sub-step noise
        var skip = SkipBound.none     // what a skip ahead of this subtree may assume of it
    }

    /// Append this field's instruction nodes to `nodes` (in evaluation order) and
    /// return its bounds + required stack depths. `defaultFill` colors leaves left
    /// unpainted. With `skips`, a SKIP instruction is written ahead of each combine's
    /// second operand that the walk can step past where the point is far from it
    /// (`skipReach`); the field's value is the same with and without them.
    func flatten(defaultFill: Color, skips: Bool = false, into nodes: inout [SDFNode3D]) -> FlattenResult {
        switch node {
        case let .leaf(shape, geo0, geo1, color):
            let rgba = (color ?? defaultFill).simd4
            nodes.append(SDFNode3D(kind: 0, sel: shape.rawValue, k: 0, extra: 0,
                                   color: rgba, geo0: geo0, geo1: geo1))
            if shape == .line {
                // The one leaf not centered at the origin: bound the two endpoints + radius.
                let a = SIMD3(geo0.x, geo0.y, geo0.z), b = SIMD3(geo1.x, geo1.y, geo1.z)
                let pad = SIMD3<Float>(repeating: geo0.w)
                let lo = simd_min(a, b) - pad, hi = simd_max(a, b) + pad
                return FlattenResult(lo: lo, hi: hi, valueDepth: 1, pointDepth: 0,
                                     skip: SkipBound(lo: lo, hi: hi, slope: 1))
            }
            let half = SDF3D.leafHalfExtent(shape, geo0)
            return FlattenResult(lo: -half, hi: half, valueDepth: 1, pointDepth: 0,
                                 unbounded: shape == .plane,
                                 normalEpsilon: SDF3D.leafNormalEpsilon(shape, geo0),
                                 skip: SDF3D.leafReadsItsDistance(shape)
                                     ? SkipBound(lo: -half, hi: half, slope: 1) : .none)

        case .combine:
            return flattenChain(defaultFill: defaultFill, skips: skips, into: &nodes)

        case let .modify(m, c, amount, frequency):
            let rc = c.flatten(defaultFill: defaultFill, skips: skips, into: &nodes)
            // A displaced field's gradient steepens to 1 + amplitude·frequency·C (C the
            // displacement's own slope bound: √3 for the sine product, ~2 for value noise),
            // so the shader multiplies the result by this factor to keep sphere tracing
            // from overshooting the rippled surface. 1 for round/onion (exact ops).
            let lipschitz: Float = {
                switch m {
                case .round, .onion: return 1
                case .displaceSine:  return 1 / (1 + amount * frequency * 1.7320508)
                case .displaceNoise: return 1 / (1 + amount * frequency * 2)
                }
            }()
            nodes.append(SDFNode3D(kind: 2, sel: m.rawValue, k: amount, extra: frequency,
                                   color: .zero, geo0: SIMD4(lipschitz, 0, 0, 0), geo1: .zero))
            let grow = max(amount, 0)   // round and displacement both reach `amount` outward
            // A rounding or a shell lowers the distance by its amount; a displacement by
            // up to its amplitude, and then the whole is scaled by the factor above.
            var skip = rc.skip.lowered(by: abs(amount))
            if m == .displaceSine || m == .displaceNoise {
                skip = lipschitz > 0 && lipschitz <= 1
                    ? SkipBound(lo: skip.lo, hi: skip.hi, slope: skip.slope * lipschitz) : .none
            }
            return FlattenResult(lo: rc.lo - SIMD3(repeating: grow),
                                 hi: rc.hi + SIMD3(repeating: grow),
                                 valueDepth: rc.valueDepth, pointDepth: rc.pointDepth,
                                 unbounded: rc.unbounded, normalEpsilon: rc.normalEpsilon,
                                 skip: skip)

        case let .voxelized(c, v):
            // A scope the shader loops over: BEGIN keeps the query point, the child
            // is read there and then at the eight nearest cell centers, and END
            // (holding the size, the shading, and how far back BEGIN is) decides
            // after each read whether to read again or to push the blocks' distance.
            let begin = nodes.count
            nodes.append(SDFNode3D(kind: 5, sel: 0, k: v.size, extra: 0,
                                   color: .zero, geo0: .zero, geo1: .zero))
            let rc = c.strippingVoxels().flatten(defaultFill: defaultFill, skips: skips, into: &nodes)
            nodes.append(SDFNode3D(kind: 6, sel: 0, k: v.size, extra: Float(nodes.count - begin),
                                   color: .zero,
                                   geo0: SIMD4(v.gap, v.jitter, v.seams, v.occlusion),
                                   geo1: SIMD4(v.seed, 0, 0, 0)))
            // A block reaches half a cell past the center that decides it, and that
            // center lies inside the child's bounds.
            let grow = SIMD3<Float>(repeating: v.size)
            // The blocks' distance is never less than the child's at the point less a
            // block's half diagonal, and a block is at most half a cell a side.
            return FlattenResult(lo: rc.lo - grow, hi: rc.hi + grow,
                                 valueDepth: rc.valueDepth, pointDepth: rc.pointDepth + 1,
                                 unbounded: rc.unbounded, normalEpsilon: rc.normalEpsilon,
                                 skip: rc.skip.lowered(by: 0.8660254 * max(v.size, 0)))

        case let .extruded(field, h):
            // The flat program lifted node for node into this walk (its leaves as the
            // EVAL2D instruction over the 2D distance functions, its combines and
            // modifiers as the shared ones, its transforms as the 3D ones in the
            // plane), then EXTRUDE, which takes the flat distance off the stack and
            // the depth and combines them as a box's two sides. The 2D flattener
            // keeps its own bounds, depths, and grow rules. The whole sits in a
            // half-turn scope about x, the turn `Mesh.text` gives a word: the flat
            // program was composed on the canvas, where y runs down, and the slab
            // stands as the canvas shows it. A turn rather than a mirror of y, since
            // the walk's mirror folds onto one side and a fold's mirror image is not
            // a fold; the extrusion reads the depth as its magnitude, so it sits
            // inside the turn unchanged.
            let turn = Transform.rotate(axis: SIMD3(1, 0, 0), angle: .pi)
            nodes.append(Self.xformNode(turn))
            var flat: [SDFNode] = []
            let rf = field.flatten(defaultFill: defaultFill, into: &flat)
            for n in flat { nodes.append(Self.lifted(n)) }
            nodes.append(SDFNode3D(kind: 8, sel: 0, k: h, extra: 0,
                                   color: .zero, geo0: .zero, geo1: .zero))
            nodes.append(SDFNode3D(kind: 4, sel: 0, k: 1, extra: 0,
                                   color: .zero, geo0: .zero, geo1: .zero))
            let (lo, hi) = Self.transformBounds(turn, lo: SIMD3(rf.lo.x, rf.lo.y, -h),
                                                hi: SIMD3(rf.hi.x, rf.hi.y, h))
            return FlattenResult(lo: lo, hi: hi, valueDepth: rf.valueDepth, pointDepth: rf.pointDepth + 1)

        case let .transformed(t, c):
            nodes.append(Self.xformNode(t))
            let rc = c.flatten(defaultFill: defaultFill, skips: skips, into: &nodes)
            // RESTORE_P rescales the child distance back to world units: a uniform scale by `s`,
            // a non-uniform scale by its *min* component (the conservative Lipschitz bound that
            // keeps the march safe), a twist/bend by 1/(1 + rate·reach): the distortion shears
            // space by up to the rate times the child's radial reach, so the rescaled distance
            // stays a safe bound. Everything else (translate/rotate/stretch/mirror/repeat) is
            // distance-preserving (scale 1).
            let distanceScale: Float = {
                switch t {
                case .scale(let s): return s
                case .scaleXYZ(let v): return min(v.x, min(v.y, v.z))
                case .twist(let rate):
                    var r: Float = 0
                    for cx in [rc.lo.x, rc.hi.x] {
                        for cz in [rc.lo.z, rc.hi.z] { r = max(r, simd_length(SIMD2(cx, cz))) }
                    }
                    return 1 / (1 + abs(rate) * r)
                case .bend(let rate):
                    var r: Float = 0
                    for cx in [rc.lo.x, rc.hi.x] {
                        for cy in [rc.lo.y, rc.hi.y] { r = max(r, simd_length(SIMD2(cx, cy))) }
                    }
                    return 1 / (1 + abs(rate) * r)
                default: return 1
                }
            }()
            nodes.append(SDFNode3D(kind: 4, sel: 0, k: distanceScale, extra: 0,
                                   color: .zero, geo0: .zero, geo1: .zero))
            let (lo, hi) = Self.transformBounds(t, lo: rc.lo, hi: rc.hi)
            var skip = SkipBound.none
            if rc.skip.holds, let factor = Self.skipSlopeFactor(t, distanceScale: distanceScale) {
                let (skipLo, skipHi) = Self.transformBounds(t, lo: rc.skip.lo, hi: rc.skip.hi)
                skip = SkipBound(lo: skipLo, hi: skipHi, slope: rc.skip.slope * factor)
            }
            return FlattenResult(lo: lo, hi: hi,
                                 valueDepth: rc.valueDepth, pointDepth: rc.pointDepth + 1,
                                 unbounded: rc.unbounded,
                                 normalEpsilon: rc.normalEpsilon * distanceScale,
                                 skip: skip)
        }
    }

    /// The bounds and depths of `op` over two flattened operands.
    private static func combined(_ op: Combine, _ ra: FlattenResult, _ rb: FlattenResult,
                                 k: Float, extra n: Float) -> FlattenResult {
        var lo: SIMD3<Float>, hi: SIMD3<Float>
        var unbounded: Bool
        switch op {
        case .union, .smoothUnion, .morph, .chamferUnion, .stairsUnion, .columnsUnion:
            lo = simd_min(ra.lo, rb.lo); hi = simd_max(ra.hi, rb.hi)
            unbounded = ra.unbounded || rb.unbounded
        case .subtract, .smoothSubtract, .chamferSubtract, .stairsSubtract,
             .columnsSubtract, .engrave, .groove, .tongue:
            lo = ra.lo; hi = ra.hi   // result ⊆ lhs (a tongue's ridge is the k-grow below)
            unbounded = ra.unbounded
        case .intersect, .smoothIntersect, .chamferIntersect, .stairsIntersect,
             .columnsIntersect, .pipe:
            lo = simd_max(ra.lo, rb.lo); hi = simd_min(ra.hi, rb.hi)
            unbounded = ra.unbounded && rb.unbounded    // bounded once either operand is
        }
        // The k-grow is each op's provable outward reach, not a blanket k. A polynomial
        // smooth op's surface bulges at most k/4 past its operands (the k*h*(1-h) term
        // tops out at k/4) and a chamfer/stairs seam reaches k/2 (its surface stays
        // within k/2 of one operand), both padded to k/2 so a bound-type child SDF
        // (ellipsoid, displaced) under-reporting distance stays covered; columns' rib
        // band, pipe's bead, and tongue's ridge genuinely reach k. The subtract,
        // intersect, and morph families cannot leave the hard op's region at all
        // (their distance is a max over terms that include the operands' own, and
        // morph is a convex blend), so they take no grow; morph's k is the blend
        // fraction, not a length. Over-padding is not harmless: the AABB drives the
        // march span, the shadow early-out, and the screen-coverage estimate behind
        // the adaptive raymarch resolution, where a blanket k compounding per nested
        // op reads a dollied-out field as near-screen-filling and holds it at reduced
        // internal resolution long after it has shrunk on screen.
        let grow: Float
        switch op {
        case .smoothUnion, .chamferUnion, .stairsUnion: grow = k / 2
        case .columnsUnion, .pipe, .tongue:             grow = k
        default:                                        grow = 0
        }
        if grow > 0 { lo -= SIMD3(repeating: grow); hi += SIMD3(repeating: grow) }
        if hi.x < lo.x || hi.y < lo.y || hi.z < lo.z { lo = .zero; hi = .zero }  // empty intersection
        // What a skip may assume of the result, from what it may assume of the two
        // operands. A union is the lesser of two distances; the smooth, chamfered,
        // and stepped ones read at most a quarter, 0.71, and a half of their size
        // below it. A cut, an engraving, or a groove never reads below its first
        // operand, a ridge or a bead by at most its size, and an intersection never
        // below either operand. The ribbed joints are left unknown.
        let skip: SkipBound
        switch op {
        case .union:
            skip = ra.skip.hull(rb.skip)
        case .morph:
            skip = k >= 0 && k <= 1 ? ra.skip.hull(rb.skip) : .none
        case .smoothUnion:
            skip = ra.skip.hull(rb.skip).lowered(by: max(k, 1e-5) / 4)
        case .chamferUnion:
            skip = ra.skip.hull(rb.skip).lowered(by: max(k, 0) * 0.70710678)
        case .stairsUnion:
            skip = ra.skip.hull(rb.skip).lowered(by: max(k, 0) / 2)
        case .subtract, .smoothSubtract, .chamferSubtract, .stairsSubtract, .engrave, .groove:
            skip = ra.skip
        case .tongue, .pipe:
            skip = ra.skip.lowered(by: max(k, 0))
        case .intersect, .smoothIntersect, .chamferIntersect, .stairsIntersect:
            if ra.skip.holds, rb.skip.holds {
                skip = rb.skip.volume < ra.skip.volume ? rb.skip : ra.skip
            } else {
                skip = ra.skip.holds ? ra.skip : rb.skip
            }
        case .columnsUnion, .columnsSubtract, .columnsIntersect:
            skip = .none
        }
        return FlattenResult(lo: lo, hi: hi,
                             valueDepth: max(ra.valueDepth, 1 + rb.valueDepth),
                             pointDepth: max(ra.pointDepth, rb.pointDepth),
                             unbounded: unbounded,
                             normalEpsilon: max(ra.normalEpsilon, rb.normalEpsilon),
                             skip: skip.holds ? skip : .none)
    }

    // MARK: Skips

    /// How far `op` reaches: where its second operand's distance is more than the
    /// first's magnitude plus this, the combine returns its first operand untouched,
    /// distance and color (`ollin_sdf3d_combine`, read case by case). `nil` for a
    /// combine whose result depends on the second operand however far it is: an
    /// intersection, a bead along the crossing, a morph.
    static func skipReach(_ op: Combine, k: Float, extra n: Float) -> Float? {
        let reach: Float
        switch op {
        case .union, .subtract:
            reach = 0
        case .smoothUnion, .smoothSubtract:
            reach = max(k, 1e-5)
        case .chamferUnion, .chamferSubtract, .stairsUnion, .stairsSubtract,
             .columnsUnion, .columnsSubtract, .engrave:
            reach = max(k, 0)
        case .groove, .tongue:
            reach = max(n, 0)
        case .intersect, .smoothIntersect, .chamferIntersect, .stairsIntersect,
             .columnsIntersect, .pipe, .morph:
            return nil
        }
        return reach.isFinite ? reach : nil
    }

    /// The SKIP instruction (kind 9) that steps past the next `count` instructions
    /// where the point is far from `bound`. The slope is taken 2% low and the reach
    /// 1% high with a small length added, so what single precision loses in the
    /// operand's own distance never puts the walk on the other side of the test
    /// from the combine it stands for.
    static func skipNode(past bound: SkipBound, reach: Float, count: Int) -> SDFNode3D {
        let center = (bound.lo + bound.hi) / 2, half = (bound.hi - bound.lo) / 2
        let scale = max(simd_reduce_max(simd_abs(bound.lo)), simd_reduce_max(simd_abs(bound.hi)))
        return SDFNode3D(kind: 9, sel: 0, k: reach * 1.01 + 1e-4 * (1 + scale), extra: Float(count),
                         color: .zero,
                         geo0: SIMD4(center.x, center.y, center.z, bound.slope * 0.98),
                         geo1: SIMD4(half.x, half.y, half.z, 0))
    }

    /// A chain of combines down the left side of the tree, which is what a loop of
    /// unions builds, written link by link. The chain is walked on a list rather than
    /// by recursion (its length is the sketch's to choose, and a call a link is a
    /// stack the sketch can spend), and the program it writes is the one the tree
    /// reads as: the first operand, then each link's operand and its combine.
    ///
    /// With `skips`, each link's operand is flattened aside so its length and box are
    /// known, and a skip is written ahead of every operand the walk can step past
    /// (`skipReach`), and ahead of a run of neighboring operands that sit together in
    /// a box much smaller than the chain's, one skip past the whole run. Stepping
    /// past a run is right for the same reason stepping past one operand is: every
    /// operand in the box is at least as far as the box, and a combine that hands
    /// back its first operand leaves that operand in place for the next.
    private func flattenChain(defaultFill: Color, skips: Bool, into nodes: inout [SDFNode3D]) -> FlattenResult {
        var links: [(op: Combine, operand: SDF3D, k: Float, extra: Float)] = []
        var base = self
        while case let .combine(op, a, b, k, n) = base.node {
            links.append((op, b, k, n))
            base = a
        }
        links.reverse()
        var running = base.flatten(defaultFill: defaultFill, skips: skips, into: &nodes)
        func combine(_ link: Int) -> SDFNode3D {
            SDFNode3D(kind: 1, sel: links[link].op.rawValue, k: links[link].k, extra: links[link].extra,
                      color: .zero, geo0: .zero, geo1: .zero)
        }
        guard skips else {
            for link in links.indices {
                let operand = links[link].operand.flatten(defaultFill: defaultFill, into: &nodes)
                nodes.append(combine(link))
                running = Self.combined(links[link].op, running, operand, k: links[link].k, extra: links[link].extra)
            }
            return running
        }

        var programs: [[SDFNode3D]] = []
        var operands: [FlattenResult] = []
        var reaches: [Float?] = []
        var chain = SkipBound.none
        for link in links {
            var program: [SDFNode3D] = []
            let operand = link.operand.flatten(defaultFill: defaultFill, skips: true, into: &program)
            // A skip that can never be taken is left out: one whose operand's box
            // holds everything the chain has drawn so far.
            var reach = Self.skipReach(link.op, k: link.k, extra: link.extra)
            if !operand.skip.holds || operand.skip.contains(lo: running.lo, hi: running.hi) { reach = nil }
            if reach != nil { chain = chain.holds ? chain.hull(operand.skip) : operand.skip }
            programs.append(program)
            operands.append(operand)
            reaches.append(reach)
            running = Self.combined(link.op, running, operand, k: link.k, extra: link.extra)
        }

        let runLength = max(4, Int(Double(links.count).squareRoot().rounded()))
        var index = 0
        while index < links.count {
            // A run: up to `runLength` neighboring links that each take a skip.
            var end = index
            var runBound = SkipBound.none
            var runReach: Float = 0
            var runCount = 0
            while end < links.count, end - index < runLength, let reach = reaches[end] {
                runBound = end == index ? operands[end].skip : runBound.hull(operands[end].skip)
                runReach = max(runReach, reach)
                runCount += programs[end].count + 2
                end += 1
            }
            if end - index >= 3, runBound.holds, chain.holds, runBound.volume <= 0.5 * chain.volume {
                nodes.append(Self.skipNode(past: runBound, reach: runReach, count: runCount))
            }
            end = max(end, index + 1)
            for link in index ..< end {
                if let reach = reaches[link] {
                    nodes.append(Self.skipNode(past: operands[link].skip, reach: reach,
                                               count: programs[link].count + 1))
                }
                nodes.append(contentsOf: programs[link])
                nodes.append(combine(link))
            }
            index = end
        }
        return running
    }

    /// The program with its skips taken out: the same field, every instruction read.
    /// A voxelized scope's end says how far back its start is, so that count is
    /// written again without the skips between them.
    static func strippingSkips(_ nodes: [SDFNode3D]) -> [SDFNode3D] {
        var out: [SDFNode3D] = []
        out.reserveCapacity(nodes.count)
        var scopes: [Int] = []
        for var node in nodes where node.kind != 9 {
            if node.kind == 5 { scopes.append(out.count) }
            if node.kind == 6, let begin = scopes.popLast() { node.extra = Float(out.count - begin) }
            out.append(node)
        }
        return out
    }

    /// The most one walk of a program can cost, counted in plain instructions: every
    /// instruction read (no skip taken), a fractal leaf at its iterations, a noise
    /// displacement at its lattice reads, and a voxelized scope at the nine reads of
    /// its child it can make. What the renderer divides a heavy field's march by
    /// (`MetalRenderer.fieldPasses`).
    static func walkWeight(_ nodes: ArraySlice<SDFNode3D>) -> Int {
        var outer: [Int] = []
        var weight = 0
        for node in nodes {
            switch node.kind {
            case 0:
                switch node.sel {
                case SDF3DShape.mandelbulb.rawValue:   weight += 1 + 6 * Int(max(0, min(node.geo0.z, 64)))
                case SDF3DShape.mengerSponge.rawValue: weight += 1 + 2 * Int(max(0, min(node.geo0.y, 64)))
                case SDF3DShape.mandelbox.rawValue:    weight += 1 + 2 * Int(max(0, min(node.geo0.z, 64)))
                default:                               weight += 1
                }
            case 2:
                weight += node.sel == Modifier.displaceNoise.rawValue ? 3 : 1
            case 5:
                outer.append(weight)
                weight = 0
            case 6:
                weight = (outer.popLast() ?? 0) + weight * 9 + 2
            default:
                weight += 1
            }
        }
        return weight + outer.reduce(0, +)
    }

    /// Whether a leaf's distance is never less than the distance to its box, outside
    /// it: true of every shape whose function is its true distance, and of the two
    /// fractals clipped to a cube. False of the ellipsoid (an approximation that reads
    /// low off its axes), the Mandelbulb (an estimate), and the plane (no box).
    static func leafReadsItsDistance(_ shape: SDF3DShape) -> Bool {
        switch shape {
        case .ellipsoid, .mandelbulb, .plane: return false
        default: return true
        }
    }

    /// What a transform scope does to the slope a skip may assume, or `nil` where
    /// nothing can be assumed. A move, a turn, a uniform scale, a stretch, a mirror,
    /// and both repeats keep it (the folded point is never nearer the child's box
    /// than the point is to the scope's); a per-axis scale loses the ratio of its
    /// least factor to its greatest; a twist or a bend loses its own distance scale.
    static func skipSlopeFactor(_ t: Transform, distanceScale: Float) -> Float? {
        switch t {
        case .translate, .rotate, .scale, .mirror, .polar:
            return 1
        case .stretch(let h):
            return h.x >= 0 && h.y >= 0 && h.z >= 0 ? 1 : nil
        case .repeatTiles(let spacing, let count):
            return simd_reduce_min(spacing) >= 0 && simd_reduce_min(count) >= 0 ? 1 : nil
        case .scaleXYZ(let v):
            let least = simd_reduce_min(v), most = simd_reduce_max(v)
            return least > 0 ? least / most : nil
        case .twist, .bend:
            return distanceScale > 0 && distanceScale <= 1 ? distanceScale : nil
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
        case .line:       return .zero   // bounds come from both endpoints (see flatten's leaf case)
        case .hexPrism:   let c = g.x * 1.1547005; return SIMD3(c, g.y, c)  // circumradius, half-height
        case .pyramid:    return SIMD3(g.x / 2, g.y / 2, g.x / 2)           // base half-width, half-height
        case .cappedTorus: let r = g.z + g.w; return SIMD3(r, g.w, r)       // ring + tube in xz, tube in y
        case .link:       return SIMD3(g.y + g.z, g.x + g.y + g.z, g.z)     // ring + tube, stretched along y
        case .mandelbulb: return SIMD3(repeating: g.w * 1.2)   // the escape ball, padded: a low iteration
                                                              // count draws a skin a few percent past it
        case .mengerSponge: return SIMD3(repeating: g.x)       // the cube's half-side, exact
        case .mandelbox:  return SIMD3(repeating: g.w)         // the clip cube's half-side, exact
        case .plane:      return SIMD3(repeating: 64)   // no finite bound; sized only to seed
                                                        // the self-shadow march budget (the
                                                        // field is flagged unbounded for the camera)
        }
    }

    /// The gradient step a leaf's normal wants, in local units (0 = the shader's default).
    /// A closed-form leaf is smooth below any step, so the default holds; a fractal's
    /// estimate keeps varying below it, so its normal reads the surface only through a
    /// step near the size of the detail a picture can show.
    static func leafNormalEpsilon(_ shape: SDF3DShape, _ g: SIMD4<Float>) -> Float {
        switch shape {
        case .mandelbulb:   return g.w * 0.008   // of the radius: the bulb's skin is the noisiest
        case .mandelbox:    return g.w * 0.004   // of the clip half-side
        case .mengerSponge: return 0             // a clean signed bound: the default holds
        default:            return 0
        }
    }

    /// A flat program's instruction as the 3D walk's: a 2D leaf becomes EVAL2D
    /// (kind 7, the shape's distance read at the point's x and y, its geometry
    /// carried as the 2D node carries it), a combine, a modifier, and RESTORE_P
    /// keep their kinds (the arithmetic is shared), and a 2D transform becomes the
    /// 3D one in the plane: a translate, a mirror, a repeat, and a stretch leave z
    /// alone with their third component at zero, a rotate turns about z by the
    /// angle the 2D node packs as its cosine and sine, a polar repeat folds about
    /// z, and a per-axis scale keeps z at one, where a zero would blow the point
    /// up ten thousandfold along the depth.
    static func lifted(_ n: SDFNode) -> SDFNode3D {
        switch n.kind {
        case 0:
            return SDFNode3D(kind: 7, sel: n.sel, k: 0, extra: n.extra,
                             color: n.color, geo0: n.geo0, geo1: n.geo1)
        case 3:
            switch n.sel {
            case 1:
                let angle = atan2(n.geo0.y, n.geo0.x)
                return SDFNode3D(kind: 3, sel: 1, k: 0, extra: 0, color: .zero,
                                 geo0: SIMD4(0, 0, 1, 0), geo1: SIMD4(angle, 0, 0, 0))
            case 5:
                return SDFNode3D(kind: 3, sel: 5, k: 0, extra: 0, color: .zero,
                                 geo0: SIMD4(0, 0, 1, 0), geo1: n.geo1)
            case 6:
                return SDFNode3D(kind: 3, sel: 6, k: 0, extra: 0, color: .zero,
                                 geo0: SIMD4(n.geo0.x, n.geo0.y, 1, 0), geo1: .zero)
            default:
                return SDFNode3D(kind: 3, sel: n.sel, k: n.k, extra: n.extra, color: .zero,
                                 geo0: n.geo0, geo1: n.geo1)
            }
        default:
            return SDFNode3D(kind: n.kind, sel: n.sel, k: n.k, extra: n.extra, color: .zero,
                             geo0: n.kind == 2 ? SIMD4(1, 0, 0, 0) : n.geo0, geo1: n.geo1)
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
        case let .scaleXYZ(v):
            return SDFNode3D(kind: 3, sel: 6, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(v.x, v.y, v.z, 0), geo1: .zero)
        case let .stretch(h):
            return SDFNode3D(kind: 3, sel: 7, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(h.x, h.y, h.z, 0), geo1: .zero)
        case let .mirror(x, y, z):
            return SDFNode3D(kind: 3, sel: 3, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(x ? 1 : 0, y ? 1 : 0, z ? 1 : 0, 0), geo1: .zero)
        case let .repeatTiles(spacing, count):
            return SDFNode3D(kind: 3, sel: 4, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(spacing.x, spacing.y, spacing.z, 0),
                             geo1: SIMD4(count.x, count.y, count.z, 0))
        case let .polar(axis, count):
            return SDFNode3D(kind: 3, sel: 5, k: 0, extra: 0, color: .zero,
                             geo0: SIMD4(axis.x, axis.y, axis.z, 0),
                             geo1: SIMD4(count, 0, 0, 0))
        case let .twist(rate):
            return SDFNode3D(kind: 3, sel: 8, k: 0, extra: 0, color: .zero,
                             geo0: .zero, geo1: SIMD4(rate, 0, 0, 0))
        case let .bend(rate):
            return SDFNode3D(kind: 3, sel: 9, k: 0, extra: 0, color: .zero,
                             geo0: .zero, geo1: SIMD4(rate, 0, 0, 0))
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
        case let .scaleXYZ(v):
            return (lo * v, hi * v)
        case let .stretch(h):
            return (lo - h, hi + h)   // elongation extends the extent by h on each side
        case let .mirror(x, y, z):
            var nlo = lo, nhi = hi
            if x { let m = max(abs(lo.x), abs(hi.x)); nlo.x = -m; nhi.x = m }
            if y { let m = max(abs(lo.y), abs(hi.y)); nlo.y = -m; nhi.y = m }
            if z { let m = max(abs(lo.z), abs(hi.z)); nlo.z = -m; nhi.z = m }
            return (nlo, nhi)
        case let .repeatTiles(spacing, count):
            let pad = spacing * count
            return (lo - pad, hi + pad)
        case .polar:
            // A ring of copies rotated around an axis through the origin; rotation preserves
            // distance-from-origin, so the union fits the child's bounding sphere (axis-free).
            var rad: Float = 0
            for cx in [lo.x, hi.x] {
                for cy in [lo.y, hi.y] {
                    for cz in [lo.z, hi.z] { rad = max(rad, simd_length(SIMD3(cx, cy, cz))) }
                }
            }
            return (SIMD3(repeating: -rad), SIMD3(repeating: rad))
        case .twist:
            // Rotation around y at any height: the xz footprint becomes the swept disc of
            // the widest corner; the y range is untouched.
            var r: Float = 0
            for cx in [lo.x, hi.x] {
                for cz in [lo.z, hi.z] { r = max(r, simd_length(SIMD2(cx, cz))) }
            }
            return (SIMD3(-r, lo.y, -r), SIMD3(r, hi.y, r))
        case .bend:
            // The curl can carry any part of the form anywhere around the bend circle;
            // bound conservatively by the child's bounding sphere.
            var rad: Float = 0
            for cx in [lo.x, hi.x] {
                for cy in [lo.y, hi.y] {
                    for cz in [lo.z, hi.z] { rad = max(rad, simd_length(SIMD3(cx, cy, cz))) }
                }
            }
            return (SIMD3(repeating: -rad), SIMD3(repeating: rad))
        }
    }
}
