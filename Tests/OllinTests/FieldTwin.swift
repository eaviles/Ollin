@testable import Ollin
import COllinShaders
import Foundation
import simd

/// The walk of a marched field's program on the CPU, in single precision: the
/// same instructions the fragment reads (`ollin_sdf3d_field`), written again
/// here so a test can ask two things no picture answers. Whether a program
/// written with skips returns the very value the program without them does, at
/// any point; and how many instructions a march reads, pixel by pixel, which is
/// the work a screen tile asks of the GPU.
///
/// It covers what the heavy fields are made of: the plain leaves, every combine,
/// the rounding, shell, and sine modifiers, every transform, and the skip. A
/// voxelized scope, a flat program stood up, a fractal, and a noise displacement
/// are not written here (`Unsupported`); those are compared on the GPU, both
/// ways through the same fragment.
struct FieldTwin {
    struct Unsupported: Error, CustomStringConvertible {
        let kind: UInt32
        let sel: UInt32
        var description: String { "the twin does not walk instruction kind \(kind), selector \(sel)" }
    }

    let nodes: [SDFNode3D]
    /// Instructions read by every walk so far.
    private(set) var reads = 0
    /// Walks made so far.
    private(set) var walks = 0

    private var distances = [Float](repeating: 0, count: 16)
    private var colors = [SIMD4<Float>](repeating: .zero, count: 16)
    private var points = [SIMD3<Float>](repeating: .zero, count: 16)

    init(_ nodes: [SDFNode3D]) { self.nodes = nodes }

    /// The field's distance and color at a point of its own frame.
    mutating func value(at p0: SIMD3<Float>) throws -> (distance: Float, color: SIMD4<Float>) {
        var sp = 0, pp = 0
        var p = p0
        var index = 0
        walks += 1
        while index < nodes.count {
            let node = nodes[index]
            reads += 1
            switch node.kind {
            case 0:
                let d = try Self.leaf(node, p)
                if sp < 16 { distances[sp] = d; colors[sp] = node.color; sp += 1 }
            case 1:
                if sp >= 2 {
                    let (d, c) = Self.combine(node.sel, distances[sp - 2], colors[sp - 2],
                                              distances[sp - 1], colors[sp - 1], node.k, node.extra)
                    sp -= 1
                    distances[sp - 1] = d
                    colors[sp - 1] = c
                }
            case 2:
                if sp >= 1 {
                    switch node.sel {
                    case 0: distances[sp - 1] -= node.k
                    case 1: distances[sp - 1] = abs(distances[sp - 1]) - node.k
                    case 2:
                        let f = node.extra
                        let wave = node.k * sin(f * p.x) * sin(f * p.y) * sin(f * p.z)
                        distances[sp - 1] = (distances[sp - 1] + wave) * node.geo0.x
                    default: throw Unsupported(kind: node.kind, sel: node.sel)
                    }
                }
            case 3:
                if pp < 16 { points[pp] = p; pp += 1 }
                p = Self.transformed(p, node)
            case 4:
                if pp > 0 { pp -= 1; p = points[pp] }
                if node.k != 1, sp >= 1 { distances[sp - 1] *= node.k }
            case 9:
                if sp >= 1 {
                    let q = simd_abs(p - SIMD3(node.geo0.x, node.geo0.y, node.geo0.z))
                        - SIMD3(node.geo1.x, node.geo1.y, node.geo1.z)
                    if simd_length(simd_max(q, .zero)) * node.geo0.w > abs(distances[sp - 1]) + node.k {
                        index += Int(node.extra)
                    }
                }
            default:
                throw Unsupported(kind: node.kind, sel: node.sel)
            }
            index += 1
        }
        return sp >= 1 ? (distances[sp - 1], colors[sp - 1]) : (1.0e9, .zero)
    }

    // MARK: Leaves

    private static func leaf(_ node: SDFNode3D, _ p: SIMD3<Float>) throws -> Float {
        let g = node.geo0
        switch node.sel {
        case 0:
            return simd_length(p) - g.x
        case 1:
            let d = simd_abs(p) - SIMD3(g.x, g.y, g.z)
            return simd_length(simd_max(d, .zero)) + min(max(d.x, max(d.y, d.z)), 0)
        case 2:
            let q = SIMD2(simd_length(SIMD2(p.x, p.z)) - g.x, p.y)
            return simd_length(q) - g.y
        case 3:
            var q = p
            q.y -= min(max(q.y, -g.y), g.y)
            return simd_length(q) - g.x
        case 4:
            let q = simd_abs(p) - SIMD3(g.x, g.y, g.z) + SIMD3(repeating: g.w)
            return simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0) - g.w
        case 5:
            let d = simd_abs(SIMD2(simd_length(SIMD2(p.x, p.z)), p.y)) - SIMD2(g.x, g.y)
            return min(max(d.x, d.y), 0) + simd_length(simd_max(d, .zero))
        case 8:
            let r = SIMD3(g.x, g.y, g.z)
            let k0 = simd_length(p / r), k1 = simd_length(p / (r * r))
            return k0 * (k0 - 1) / k1
        case 10:
            let a = SIMD3(g.x, g.y, g.z), b = SIMD3(node.geo1.x, node.geo1.y, node.geo1.z)
            let pa = p - a, ba = b - a
            let h = min(max(simd_dot(pa, ba) / max(simd_dot(ba, ba), 1e-8), 0), 1)
            return simd_length(pa - ba * h) - g.w
        default:
            throw Unsupported(kind: node.kind, sel: node.sel)
        }
    }

    // MARK: Combines

    private static func mix(_ x: Float, _ y: Float, _ a: Float) -> Float { x + (y - x) * a }
    private static func mix(_ x: SIMD4<Float>, _ y: SIMD4<Float>, _ a: Float) -> SIMD4<Float> { x + (y - x) * a }
    private static func emod(_ x: Float, _ y: Float) -> Float { x - y * (x / y).rounded(.down) }

    private static func stairs(_ a: Float, _ b: Float, _ r: Float, _ n: Float) -> Float {
        let s = max(r, 1e-5) / max(n, 1)
        let u = b - r
        return min(min(a, b), 0.5 * (u + a + abs(emod(u - a + s, 2 * s) - s)))
    }

    private static func columnsUnion(_ a: Float, _ b: Float, _ r: Float, _ n: Float) -> Float {
        guard a < r, b < r else { return min(a, b) }
        var p = SIMD2(a, b)
        let radius = r * 1.41421356 / ((n - 1) * 2 + 1.41421356)
        p = (p + SIMD2(p.y, -p.x)) * 0.70710678
        p.x -= 0.70710678 * r
        p.x += radius * 1.41421356
        if emod(n, 2) >= 1 { p.y += radius }
        let size = radius * 2
        p.y = emod(p.y + size * 0.5, size) - size * 0.5
        var result = simd_length(p) - radius
        result = min(result, p.x)
        result = min(result, a)
        return min(result, b)
    }

    private static func columnsDifference(_ a0: Float, _ b: Float, _ r: Float, _ n: Float) -> Float {
        let a = -a0
        let m = min(a, b)
        guard a < r, b < r else { return -m }
        var p = SIMD2(a, b)
        let radius = r * 1.41421356 / ((n - 1) * 2 + 1.41421356)
        p = (p + SIMD2(p.y, -p.x)) * 0.70710678
        p.y += radius
        p.x -= 0.70710678 * r
        p.x += -radius * 0.70710678
        if emod(n, 2) >= 1 { p.y += radius }
        let size = radius * 2
        p.y = emod(p.y + size * 0.5, size) - size * 0.5
        var result = -simd_length(p) + radius
        result = max(result, p.x)
        result = min(result, a)
        return -min(result, b)
    }

    // swiftlint:disable:next cyclomatic_complexity function_parameter_count
    private static func combine(_ op: UInt32, _ da: Float, _ ca: SIMD4<Float>, _ db: Float, _ cb: SIMD4<Float>,
                                _ k: Float, _ n: Float) -> (Float, SIMD4<Float>) {
        let kk = max(k, 1e-5)
        switch op {
        case 0:
            return da <= db ? (da, ca) : (db, cb)
        case 1:
            let h = min(max(0.5 + 0.5 * (db - da) / kk, 0), 1)
            if h >= 1 { return (da, ca) }
            return (mix(db, da, h) - kk * h * (1 - h), mix(cb, ca, h))
        case 2:
            return (max(da, -db), ca)
        case 3:
            let h = min(max(0.5 - 0.5 * (da + db) / kk, 0), 1)
            if h <= 0 { return (da, ca) }
            return (mix(da, -db, h) + kk * h * (1 - h), ca)
        case 4:
            return da >= db ? (da, ca) : (db, cb)
        case 5:
            let h = min(max(0.5 - 0.5 * (db - da) / kk, 0), 1)
            return (mix(db, da, h) + kk * h * (1 - h), mix(cb, ca, h))
        case 7:
            return (min(min(da, db), (da + db - k) * 0.70710678), da <= db ? ca : cb)
        case 8:
            return (max(max(da, -db), (da + k - db) * 0.70710678), ca)
        case 9:
            return (max(max(da, db), (da + k + db) * 0.70710678), da >= db ? ca : cb)
        case 10:
            return (stairs(da, db, k, n), da <= db ? ca : cb)
        case 11:
            return (-stairs(-da, db, k, n), ca)
        case 12:
            return (-stairs(-da, -db, k, n), da >= db ? ca : cb)
        case 13:
            return (columnsUnion(da, db, k, n), da <= db ? ca : cb)
        case 14:
            return (columnsDifference(da, db, k, n), ca)
        case 15:
            return (columnsDifference(da, -db, k, n), da >= db ? ca : cb)
        case 16:
            return (simd_length(SIMD2(da, db)) - k, da <= db ? ca : cb)
        case 17:
            return (max(da, (da + k - abs(db)) * 0.70710678), ca)
        case 18:
            return (max(da, min(da + k, n - abs(db))), ca)
        case 19:
            return (min(da, max(da - k, abs(db) - n)), ca)
        default:
            return (mix(da, db, k), mix(ca, cb, k))
        }
    }

    // MARK: Transforms

    private static func transformed(_ p: SIMD3<Float>, _ node: SDFNode3D) -> SIMD3<Float> {
        let g0 = SIMD3(node.geo0.x, node.geo0.y, node.geo0.z)
        let g1 = SIMD3(node.geo1.x, node.geo1.y, node.geo1.z)
        switch node.sel {
        case 0:
            return p - g0
        case 1:
            let c = cos(-node.geo1.x), s = sin(-node.geo1.x)
            return p * c + simd_cross(g0, p) * s + g0 * simd_dot(g0, p) * (1 - c)
        case 2:
            return p / max(node.k, 1e-4)
        case 3:
            var q = p
            if g0.x > 0.5 { q.x = abs(q.x) }
            if g0.y > 0.5 { q.y = abs(q.y) }
            if g0.z > 0.5 { q.z = abs(q.z) }
            return q
        case 4:
            var q = p
            for axis in 0 ..< 3 where g0[axis] > 0 {
                let r = min(max((q[axis] / g0[axis]).rounded(.toNearestOrEven), -g1[axis]), g1[axis])
                q[axis] -= g0[axis] * r
            }
            return q
        case 5:
            let axis = simd_normalize(g0)
            let reps = max(node.geo1.x, 1)
            let ref: SIMD3<Float> = abs(axis.x) < 0.99 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
            let u = simd_normalize(ref - axis * simd_dot(axis, ref))
            let v = simd_cross(axis, u)
            let a0 = simd_dot(p, u), b0 = simd_dot(p, v), axial = simd_dot(p, axis)
            let ang = 6.28318530718 / reps
            var a = atan2(b0, a0) + ang * 0.5
            let r = simd_length(SIMD2(a0, b0))
            a = a - ang * (a / ang).rounded(.down) - ang * 0.5
            return u * (cos(a) * r) + v * (sin(a) * r) + axis * axial
        case 6:
            return p / simd_max(g0, SIMD3(repeating: 1e-4))
        case 7:
            return p - simd_clamp(p, -g0, g0)
        case 8:
            let c = cos(node.geo1.x * p.y), s = sin(node.geo1.x * p.y)
            return SIMD3(c * p.x - s * p.z, p.y, s * p.x + c * p.z)
        case 9:
            let c = cos(node.geo1.x * p.x), s = sin(node.geo1.x * p.x)
            return SIMD3(c * p.x - s * p.y, s * p.x + c * p.y, p.z)
        default:
            return p
        }
    }
}

// MARK: - The march

extension FieldTwin {
    /// What one pixel's march needs beside the ray: the field's place in the world,
    /// the step budgets, and the lights it marches a shadow toward.
    struct March {
        var group: SDF3DGroupInstance
        /// The camera's and the shadow's step budgets.
        var steps: (march: Int, shadow: Int)
        /// A pixel's half width at distance one (`kPixel` in the fragment).
        var pixel: Float
        /// The direction to each casting light that is directional.
        var casters: [SIMD3<Float>] = []
    }

    private mutating func world(_ pw: SIMD3<Float>, _ m: March) throws -> Float {
        let pl = m.group.inverseModel * SIMD4(pw.x, pw.y, pw.z, 1)
        return try value(at: SIMD3(pl.x, pl.y, pl.z)).distance * m.group.modelScale
    }

    /// One pixel of the camera's march, as the fragment makes it: the sphere trace
    /// with its near miss, the four reads of the normal, and a shadow march toward
    /// each caster. Returns whether the pixel was shaded; the instructions it read
    /// are in `reads`.
    @discardableResult
    mutating func marchPixel(origin ro: SIMD3<Float>, direction rd: SIMD3<Float>, _ m: March) throws -> Bool {
        let lo = SIMD3(m.group.boundsMin.x, m.group.boundsMin.y, m.group.boundsMin.z)
        let hi = SIMD3(m.group.boundsMax.x, m.group.boundsMax.y, m.group.boundsMax.z)
        let inverse = SIMD3<Float>(repeating: 1) / rd
        let ta = (lo - ro) * inverse, tb = (hi - ro) * inverse
        let t0 = max(simd_reduce_max(simd_min(ta, tb)), 0)
        let t1 = simd_reduce_min(simd_max(ta, tb))
        guard t1 >= t0 else { return false }
        var t = t0
        var hit = false
        var least = Float(1.0e9), nearest = t0
        for _ in 0 ..< m.steps.march {
            if t > t1 { break }
            let d = try world(ro + rd * t, m)
            if d < 0.001 { hit = true; break }
            let ratio = d / max(t * m.pixel, 1e-6)
            if ratio < least { least = ratio; nearest = t }
            t += d * 0.85
        }
        var pw = ro + rd * t
        if !hit {
            guard min(max(1 - least, 0), 1) >= 0.004 else { return false }
            pw = ro + rd * nearest
            _ = try world(pw, m)
        }
        let e: Float = m.group.normalEpsilon > 0 ? m.group.normalEpsilon : 0.0008
        let taps: [SIMD3<Float>] = [SIMD3(1, -1, -1), SIMD3(-1, -1, 1), SIMD3(-1, 1, -1), SIMD3(1, 1, 1)]
        var n = SIMD3<Float>.zero
        for tap in taps { n += tap * (try world(pw + tap * e, m)) }
        n = simd_normalize(n)
        let reach = simd_length(hi - lo)
        for toLight in m.casters {
            var along: Float = 0.02
            for _ in 0 ..< m.steps.shadow {
                if along >= reach { break }
                let h = try world(pw + n * 0.015 + toLight * along, m)
                if h < 0.001 { break }
                along += h * 0.85
            }
        }
        return true
    }
}
