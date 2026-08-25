import Foundation
import simd

/// The per-wavelength-tap constants behind the spectral GPU passes (thin film,
/// diffraction, paint mixing), cooked once from the tables behind `Spectrum`
/// so the fragments never carry the data themselves. A pass gets a packed
/// params block appended after its own parameters:
///
///   [offset]                 (taps, 0, 0, 0)
///   [offset + 1 + i]         the reflectance basis at tap i, wavelength in .w
///   [offset + 1 + taps + i]  the daylight-weighted observer at tap i
///   [offset + 1 + 2*taps + r] row r of the taps' XYZ-to-linear-RGB inverse
///
/// The inverse is computed from these same taps rather than from the full
/// tables: whatever the tap count, converting a reflectance built from a color
/// back through the block reproduces that color exactly, so "both inputs the
/// same" and "zero amount" stay identities at every quality tier.
enum SpectralTaps {

    /// The packed block for a tap count (the dispersion tiers are precooked;
    /// any other count cooks on demand).
    static func block(_ taps: Int) -> [SIMD4<Float>] {
        precooked[taps] ?? cook(taps)
    }

    private static let precooked: [Int: [SIMD4<Float>]] = {
        var out: [Int: [SIMD4<Float>]] = [:]
        for taps in [7, 15, 31] { out[taps] = cook(taps) }
        return out
    }()

    private static func cook(_ count: Int) -> [SIMD4<Float>] {
        let n = max(3, count)
        let lambdaMin = Spectrum.wavelengths.first ?? 380
        let lambdaMax = Spectrum.wavelengths.last ?? 780
        let step = (Spectrum.wavelengths.count > 1)
            ? Spectrum.wavelengths[1] - Spectrum.wavelengths[0] : 5

        func sample(_ table: [Double], at lambda: Double) -> Double {
            let position = (lambda - lambdaMin) / step
            let clamped = min(max(position, 0), Double(table.count - 1))
            let i = Int(clamped)
            let j = min(i + 1, table.count - 1)
            let f = clamped - Double(i)
            return table[i] + (table[j] - table[i]) * f
        }

        let weightX = Spectrum.weights.map(\.x)
        let weightY = Spectrum.weights.map(\.y)
        let weightZ = Spectrum.weights.map(\.z)
        var basis: [SIMD4<Float>] = []
        var weight: [SIMD4<Float>] = []
        var toXYZ = simd_double3x3(0)
        for i in 0..<n {
            let lambda = lambdaMin + (lambdaMax - lambdaMin) * Double(i) / Double(n - 1)
            let b = SIMD3(sample(Spectrum.basisR, at: lambda),
                          sample(Spectrum.basisG, at: lambda),
                          sample(Spectrum.basisB, at: lambda))
            let w = SIMD3(sample(weightX, at: lambda),
                          sample(weightY, at: lambda),
                          sample(weightZ, at: lambda))
            basis.append(SIMD4(Float(b.x), Float(b.y), Float(b.z), Float(lambda)))
            weight.append(SIMD4(Float(w.x), Float(w.y), Float(w.z), 0))
            toXYZ += simd_double3x3(columns: (w * b.x, w * b.y, w * b.z))
        }
        let inverse = toXYZ.inverse
        func row(_ r: Int) -> SIMD4<Float> {
            SIMD4(Float(inverse[0][r]), Float(inverse[1][r]), Float(inverse[2][r]), 0)
        }
        return [SIMD4(Float(n), 0, 0, 0)] + basis + weight + [row(0), row(1), row(2)]
    }
}
