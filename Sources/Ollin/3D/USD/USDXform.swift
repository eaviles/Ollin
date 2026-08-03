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

    /// The prim's local transform composed from its authored xformOps per
    /// `xformOpOrder`, as a column-vector matrix, plus whether the stack
    /// resets (ignores every inherited transform). No `xformOpOrder` means
    /// the identity: authored ops outside the order don't apply.
    func localXform() -> (matrix: simd_double4x4, resetsStack: Bool) {
        guard let order = attribute("xformOpOrder")?.authoredValue else {
            return (matrix_identity_double4x4, false)
        }
        let tokens: [String]
        switch order {
        case .tokenArray(let t): tokens = t
        case .stringArray(let s): tokens = s
        default: return (matrix_identity_double4x4, false)
        }

        var matrix = matrix_identity_double4x4
        var resets = false
        for token in tokens {
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
            guard let value = attribute(name)?.authoredValue,
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
}

extension USDStage {
    /// Visit every prim depth-first in authored order with its composed world
    /// transform. Abstract (`class`) prims and their subtrees are skipped;
    /// a `!resetXformStack!` prim starts over from its own local transform.
    func visitPrims(_ body: (USDPrim, simd_double4x4) -> Void) {
        func walk(_ prim: USDPrim, parent: simd_double4x4) {
            guard prim.specifier != .class else { return }
            let (local, resets) = prim.localXform()
            let world = resets ? local : parent * local
            body(prim, world)
            for child in prim.children { walk(child, parent: world) }
        }
        for prim in prims { walk(prim, parent: matrix_identity_double4x4) }
    }
}
