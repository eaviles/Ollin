import Foundation
import simd

// The xformOp evaluator over the raw tree: composes a prim's authored transform
// stack into one matrix, so consumers (light resolution today, animation and
// the native scene walk later) can place prims in world space without any
// schema machinery.
//
// Conventions honored here, each verified against the reference behavior:
//
// - `xformOpOrder` lists ops outermost first: ["translate", "rotateXYZ"] rotates
//   the prim, then translates it. With column-vector matrices that means
//   composing the listed ops left to right (M = M · op).
// - USD authors matrices row-vector (translation in the fourth row), so a
//   `matrix4d`'s four rows load directly as simd columns; the transpose that
//   converts conventions falls out of the flat read.
// - Rotation angles are degrees. A three-axis rotate applies its named axes in
//   name order (`rotateXYZ` rotates about x first), so its column-vector
//   composite multiplies them reversed.
// - An op token may carry the `!invert!` prefix (the pivot idiom pairs
//   `translate:pivot` with its inverse); `!resetXformStack!` cuts the prim
//   loose from its inherited stack, and must discard any ops listed before it.
// - `orient` quaternions are (real, i, j, k), the shape both containers
//   deliver.

extension USDPrim {

    /// The authored `xformOpOrder` tokens, or empty when the prim has none
    /// (in which case no op applies).
    var xformOpOrderTokens: [String] {
        switch attribute("xformOpOrder")?.authoredValue {
        case .tokenArray(let t): t
        case .stringArray(let s): s
        default: []
        }
    }

    /// The prim's local transform composed from its authored xformOps per
    /// `xformOpOrder`, as a column-vector matrix, plus whether the stack
    /// resets (ignores every inherited transform). No `xformOpOrder` means
    /// the identity: authored ops outside the order don't apply. Passing a
    /// time code samples each op's attribute there (`sampled(at:)`); nil
    /// reads the rest values (`authoredValue`).
    func localXform(at time: Double? = nil) -> (matrix: simd_double4x4, resetsStack: Bool) {
        var matrix = matrix_identity_double4x4
        var resets = false
        for token in xformOpOrderTokens {
            if token == "!resetXformStack!" {
                // Ops listed before the reset belong to the discarded stack.
                matrix = matrix_identity_double4x4
                resets = true
                continue
            }
            var name = token
            var inverted = false
            if name.hasPrefix("!invert!") {
                name = String(name.dropFirst("!invert!".count))
                inverted = true
            }
            let attr = attribute(name)
            let value = time.map { t in attr?.sampled(at: t) } ?? attr?.authoredValue
            guard let value,
                  let op = Self.opMatrix(opName: name, value: value, inverted: inverted)
            else { continue }  // a dangling or undecodable op is skipped, not fatal
            matrix *= op
        }
        return (matrix, resets)
    }

    /// The matrix for one op: `name` is the attribute name (`xformOp:translate`,
    /// `xformOp:rotateXYZ:spin`, …), whose second segment picks the op type;
    /// any further suffix only distinguishes multiple ops of one type.
    private static func opMatrix(opName name: String, value: USDValue,
                                 inverted: Bool) -> simd_double4x4? {
        let segments = name.split(separator: ":")
        guard segments.count >= 2, segments[0] == "xformOp" else { return nil }
        let type = String(segments[1])

        switch type {
        case "transform":
            guard let m = components(value, count: 16) else { return nil }
            var matrix = simd_double4x4(columns: (
                SIMD4(m[0], m[1], m[2], m[3]),
                SIMD4(m[4], m[5], m[6], m[7]),
                SIMD4(m[8], m[9], m[10], m[11]),
                SIMD4(m[12], m[13], m[14], m[15])))
            if inverted { matrix = matrix.inverse }
            return matrix
        case "translate":
            guard var t = components(value, count: 3).map({ SIMD3($0[0], $0[1], $0[2]) })
            else { return nil }
            if inverted { t = -t }
            return translation(t)
        case "translateX", "translateY", "translateZ":
            guard var d = scalar(value) else { return nil }
            if inverted { d = -d }
            var t = SIMD3<Double>.zero
            t[axisIndex(of: type)] = d
            return translation(t)
        case "scale":
            guard var s = components(value, count: 3).map({ SIMD3($0[0], $0[1], $0[2]) })
            else { return nil }
            if inverted { s = SIMD3(1 / s.x, 1 / s.y, 1 / s.z) }
            return scaling(s)
        case "scaleX", "scaleY", "scaleZ":
            guard var d = scalar(value) else { return nil }
            if inverted { d = 1 / d }
            var s = SIMD3<Double>(1, 1, 1)
            s[axisIndex(of: type)] = d
            return scaling(s)
        case "rotateX", "rotateY", "rotateZ":
            guard var degrees = scalar(value) else { return nil }
            if inverted { degrees = -degrees }
            return rotation(axis: axisIndex(of: type), degrees: degrees)
        case "rotateXYZ", "rotateXZY", "rotateYXZ", "rotateYZX", "rotateZXY", "rotateZYX":
            guard let angles = components(value, count: 3) else { return nil }
            let axes = type.dropFirst("rotate".count).map { axisIndex(of: String($0)) }
            var matrix = matrix_identity_double4x4
            if inverted {
                // Inv(A·B·C) applies the named axes reversed with negated
                // angles; composing in name order does exactly that.
                for i in 0..<3 { matrix *= rotation(axis: axes[i], degrees: -angles[axes[i]]) }
            } else {
                // Name order applies first, so the column composite reverses.
                for i in (0..<3).reversed() { matrix *= rotation(axis: axes[i], degrees: angles[axes[i]]) }
            }
            return matrix
        case "orient":
            guard let q = components(value, count: 4) else { return nil }
            var quat = simd_quatd(ix: q[1], iy: q[2], iz: q[3], r: q[0])
            guard quat.length > 1e-12 else { return nil }
            quat = quat.normalized
            if inverted { quat = quat.conjugate }
            return simd_double4x4(quat)
        default:
            return nil
        }
    }

    private static func axisIndex(of type: String) -> Int {
        switch type.last {
        case "X", "x": 0
        case "Y", "y": 1
        default: 2
        }
    }

    private static func scalar(_ value: USDValue) -> Double? {
        switch value {
        case .double(let d): d
        case .int(let i): Double(i)
        case .uint(let u): Double(u)
        default: nil
        }
    }

    private static func components(_ value: USDValue, count: Int) -> [Double]? {
        guard case .tuple(let c) = value, c.count == count else { return nil }
        return c
    }

    private static func translation(_ t: SIMD3<Double>) -> simd_double4x4 {
        var m = matrix_identity_double4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }

    private static func scaling(_ s: SIMD3<Double>) -> simd_double4x4 {
        simd_double4x4(diagonal: SIMD4(s.x, s.y, s.z, 1))
    }

    private static func rotation(axis: Int, degrees: Double) -> simd_double4x4 {
        let r = degrees * .pi / 180
        let c = cos(r), s = sin(r)
        switch axis {
        case 0:
            return simd_double4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0),
                                            SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
        case 1:
            return simd_double4x4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0),
                                            SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
        default:
            return simd_double4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0),
                                            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
        }
    }
}

extension USDAttribute {
    /// The value the attribute holds "now": its default, or the first time
    /// sample when only samples were authored (an animated prim's rest shape).
    var authoredValue: USDValue? { value ?? timeSamples.first?.value }

    /// The value at time code `time`: the bracketing samples interpolated the
    /// way the reference runtime's default (linear) stage setting does,
    /// componentwise for scalars and tuples, along the arc for quaternion
    /// types, held for everything else, clamped to the end samples outside
    /// the sampled range. (Interpolation is a runtime choice, never authored
    /// in a file; linear is the default every consumer sees.) An attribute
    /// with no samples answers with its default value at every time.
    func sampled(at time: Double) -> USDValue? {
        guard let first = timeSamples.first, let last = timeSamples.last else { return value }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        // Binary search: the last sample at or before `time` (samples ascend).
        var lo = 0, hi = timeSamples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if timeSamples[mid].time <= time { lo = mid } else { hi = mid }
        }
        let s0 = timeSamples[lo], s1 = timeSamples[lo + 1]
        let span = s1.time - s0.time
        guard span > 0 else { return s0.value }
        return Self.interpolate(s0.value, s1.value, (time - s0.time) / span,
                                isQuaternion: typeName.hasPrefix("quat"))
    }

    /// Linear interpolation between two sampled values where the type
    /// supports it (scalars, matching-arity tuples, quaternions spherically);
    /// a non-lerpable or shape-mismatched pair holds the earlier sample, the
    /// reference rule for types outside the lerp set.
    private static func interpolate(_ a: USDValue, _ b: USDValue, _ f: Double,
                                    isQuaternion: Bool) -> USDValue {
        switch (a, b) {
        case (.double(let x), .double(let y)):
            return .double(x + (y - x) * f)
        case (.tuple(let x), .tuple(let y)) where x.count == y.count:
            if isQuaternion, x.count == 4 { return .tuple(slerpComponents(x, y, f)) }
            return .tuple(zip(x, y).map { $0 + ($1 - $0) * f })
        default:
            return a
        }
    }

    /// Spherical interpolation of two (real, i, j, k) component lists.
    private static func slerpComponents(_ a: [Double], _ b: [Double], _ f: Double) -> [Double] {
        let qa = simd_quatd(ix: a[1], iy: a[2], iz: a[3], r: a[0])
        let qb = simd_quatd(ix: b[1], iy: b[2], iz: b[3], r: b[0])
        guard qa.length > 1e-12, qb.length > 1e-12 else { return a }
        let q = simd_slerp(qa.normalized, qb.normalized, f)
        return [q.real, q.imag.x, q.imag.y, q.imag.z]
    }
}

extension USDStage {
    /// Visit every prim depth-first in authored order with its composed world
    /// transform. Abstract (`class`) prims and their subtrees are skipped;
    /// a `!resetXformStack!` prim starts over from its own local transform.
    func visitPrims(_ body: (USDPrim, simd_double4x4) -> Void) {
        visitPrims { prim, _, world in body(prim, world) }
    }

    /// The same walk, with each prim's absolute path, which is what a
    /// relationship names it by.
    func visitPrims(_ body: (USDPrim, String, simd_double4x4) -> Void) {
        func walk(_ prim: USDPrim, parentPath: String, parent: simd_double4x4) {
            guard prim.specifier != .class else { return }
            let (local, resets) = prim.localXform()
            let world = resets ? local : parent * local
            let path = parentPath + "/" + prim.name
            body(prim, path, world)
            for child in prim.children { walk(child, parentPath: path, parent: world) }
        }
        for prim in prims { walk(prim, parentPath: "", parent: matrix_identity_double4x4) }
    }
}
