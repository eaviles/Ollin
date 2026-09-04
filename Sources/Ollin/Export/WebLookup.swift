import Foundation

/// The split-sum BRDF integration table a physically-based finish prices its
/// specular energy against (`ollin_pbr_ess`), baked for the page the way the
/// Mac bakes it (`ollin_ibl_brdf_lut`): over (N·V, roughness), the (scale,
/// bias) pair of Schlick's Fresnel under the GGX lobe with the height-correlated
/// Smith term, 512 Hammersley samples a texel, 256 texels a side. Stored as
/// half floats, the Mac's own storage, so a texel reads the same value there
/// and here. Baked once per process, and only when a recording carries such a
/// finish on a field.
enum WebBRDFLUT {
    static let size = 256
    static let samples = 512

    /// The table as `size * size` (scale, bias) pairs of half-float bits, row
    /// by row from roughness 0.
    static let shared: [UInt16] = bake()

    static func bake() -> [UInt16] {
        let n = size
        var out = [UInt16](repeating: 0, count: n * n * 2)
        for y in 0 ..< n {
            let rough = (Float(y) + 0.5) / Float(n)
            for x in 0 ..< n {
                let ndv = max((Float(x) + 0.5) / Float(n), 1e-4)
                let (a, b) = integrate(ndv: ndv, rough: rough)
                out[(y * n + x) * 2] = WebHalf.bits(a)
                out[(y * n + x) * 2 + 1] = WebHalf.bits(b)
            }
        }
        return out
    }

    /// One texel: the integral the Mac's fragment runs, sample for sample.
    static func integrate(ndv: Float, rough: Float) -> (Float, Float) {
        let v = SIMD3<Float>((1 - ndv * ndv).squareRoot(), 0, ndv)
        var a: Float = 0, b: Float = 0
        let count = UInt32(samples)
        let alpha = rough * rough
        for i in 0 ..< count {
            // Hammersley: the sequence index over the count, and the radical inverse.
            let xi = SIMD2<Float>(Float(i) / Float(count), radicalInverse(i))
            // The GGX-importance-sampled half vector about +z (the normal), through
            // the frame the Mac builds for n = (0, 0, 1): tx = (0, -1, 0), ty = (1, 0, 0).
            let phi = 2 * Float.pi * xi.x
            let cosT = ((1 - xi.y) / (1 + (alpha * alpha - 1) * xi.y)).squareRoot()
            let sinT = (1 - cosT * cosT).squareRoot()
            let hl = SIMD3<Float>(cos(phi) * sinT, sin(phi) * sinT, cosT)
            var h = SIMD3<Float>(hl.y, -hl.x, hl.z)
            h /= (h.x * h.x + h.y * h.y + h.z * h.z).squareRoot()
            let vdh0 = v.x * h.x + v.y * h.y + v.z * h.z
            var l = 2 * vdh0 * h - v
            l /= (l.x * l.x + l.y * l.y + l.z * l.z).squareRoot()
            let ndl = max(l.z, 0)
            let ndh = max(h.z, 0)
            let vdh = max(vdh0, 0)
            if ndl > 0 {
                let g = geometry(ndv: ndv, ndl: ndl, rough: rough)
                let gvis = g * vdh / max(ndh * ndv, 1e-4)
                let fc = pow(1 - vdh, 5)
                a += (1 - fc) * gvis
                b += fc * gvis
            }
        }
        return (a / Float(count), b / Float(count))
    }

    /// Height-correlated Smith for the lobe, times the 4·N·L·N·V the shading
    /// visibility folds in (`ollin_ibl_geometry`).
    static func geometry(ndv: Float, ndl: Float, rough: Float) -> Float {
        let a = rough * rough
        let a2 = a * a
        let gv = ndl * (ndv * ndv * (1 - a2) + a2).squareRoot()
        let gl = ndv * (ndl * ndl * (1 - a2) + a2).squareRoot()
        return (2 * ndl * ndv) / max(gv + gl, 1e-5)
    }

    /// The van der Corput radical inverse in base 2 (`ollin_ibl_radical_inverse`).
    static func radicalInverse(_ i: UInt32) -> Float {
        var bits = i
        bits = (bits << 16) | (bits >> 16)
        bits = ((bits & 0x5555_5555) << 1) | ((bits & 0xAAAA_AAAA) >> 1)
        bits = ((bits & 0x3333_3333) << 2) | ((bits & 0xCCCC_CCCC) >> 2)
        bits = ((bits & 0x0F0F_0F0F) << 4) | ((bits & 0xF0F0_F0F0) >> 4)
        bits = ((bits & 0x00FF_00FF) << 8) | ((bits & 0xFF00_FF00) >> 8)
        return Float(bits) * 2.3283064365386963e-10
    }
}

/// IEEE half-float bits from a float, rounded to nearest even, the conversion
/// a GPU applies storing a 16-bit float texel.
enum WebHalf {
    static func bits(_ value: Float) -> UInt16 {
        let f = value.bitPattern
        let sign = UInt16((f >> 16) & 0x8000)
        let exponent = Int((f >> 23) & 0xFF) - 127 + 15
        var mantissa = f & 0x7F_FFFF
        if (f & 0x7F80_0000) == 0x7F80_0000 {
            // Infinity or NaN.
            return sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0)
        }
        if exponent >= 0x1F { return sign | 0x7C00 }
        if exponent <= 0 {
            if exponent < -10 { return sign }
            // A subnormal half: shift the hidden bit in and round.
            mantissa |= 0x80_0000
            let shift = UInt32(14 - exponent)
            var half = UInt16(mantissa >> shift)
            let remainder = mantissa & ((1 << shift) - 1)
            let halfway = UInt32(1) << (shift - 1)
            if remainder > halfway || (remainder == halfway && (half & 1) == 1) { half += 1 }
            return sign | half
        }
        var half = UInt16(exponent << 10) | UInt16(mantissa >> 13)
        let remainder = mantissa & 0x1FFF
        if remainder > 0x1000 || (remainder == 0x1000 && (half & 1) == 1) { half += 1 }
        return sign | half
    }
}
