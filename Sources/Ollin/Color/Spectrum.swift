import Foundation
import simd
import CSpectralData

/// A visible-light spectrum: 81 samples from 380 to 780 nm in 5 nm steps, the
/// typed value behind Ollin's spectral color work. Where `Color` is three
/// numbers chosen for the eye, a `Spectrum` is the physical curve those numbers
/// stand in for, and some things only work out right on the curve: pigments
/// mixing like paint, a thin film's interference colors, light split by
/// wavelength.
///
/// The reading is *reflectance in daylight*: `Spectrum(color)` builds the
/// smooth reflectance curve that reproduces `color` exactly when lit by the
/// standard daylight illuminant, and the conversion back (`spectrum.color` or
/// `Color(spectrum)`) lights the curve the same way. The round trip is exact,
/// so passing a color through a spectrum and back changes nothing.
///
/// Spectra compose as physics does: `*` between two spectra is filtering (each
/// wavelength keeps the product of what both would pass, which is subtractive
/// mixing), `+` adds light, and `mixedAsPaint(with:_:)` blends two curves the
/// way scattering pigments blend. The everyday form of that last one is
/// `Color.mix(a, b, 0.5, in: .paint)`.
///
/// ```swift
/// let green = Color.mix(.yellow, .blue, 0.5, in: .paint)   // paint, not gray
/// let stained = (glass.spectrum * light.spectrum).color        // filtered light
/// let glow = Color(.blackbody(1800))                           // candle orange
/// ```
public struct Spectrum: Equatable, Sendable {

    /// How many samples a spectrum holds (81: 380 to 780 nm every 5 nm).
    public static let sampleCount = Int(OLLIN_SPECTRAL_SAMPLE_COUNT)

    /// The wavelengths the samples sit on, in nanometers.
    public static let wavelengths: [Double] = (0..<sampleCount).map {
        OLLIN_SPECTRAL_LAMBDA_MIN + OLLIN_SPECTRAL_LAMBDA_STEP * Double($0)
    }

    /// The sample values, one per entry of `wavelengths`. For a reflectance
    /// 0 is "absorbs everything here" and 1 is "returns everything here".
    public var samples: [Double]

    /// A spectrum from raw samples. `samples` must hold exactly
    /// `Spectrum.sampleCount` values (380 to 780 nm, 5 nm apart).
    public init(samples: [Double]) {
        precondition(samples.count == Self.sampleCount,
                     "Spectrum needs exactly \(Self.sampleCount) samples (380...780 nm, 5 nm apart)")
        self.samples = samples
    }

    // MARK: Color in, color out

    /// The reflectance spectrum that reproduces `color` exactly in daylight:
    /// the color's linear components blend three fixed basis curves, one per
    /// primary. White is a flat 1, black a flat 0, and every in-gamut color
    /// lands between them, smooth and physically plausible.
    public init(_ color: Color) {
        let r = max(0, Color.srgbToLinear(color.red))
        let g = max(0, Color.srgbToLinear(color.green))
        let b = max(0, Color.srgbToLinear(color.blue))
        var out = [Double](repeating: 0, count: Self.sampleCount)
        for i in 0..<Self.sampleCount {
            out[i] = r * Self.basisR[i] + g * Self.basisG[i] + b * Self.basisB[i]
        }
        samples = out
    }

    /// A single spectral line: a narrow Gaussian centered on `wavelength`
    /// (nanometers, visible from about 380 to 780), `width` nm wide. Its color
    /// is the pure hue of that wavelength; sweep 400 to 700 for the rainbow.
    public init(wavelength: Double, width: Double = 20) {
        let sigma = max(1, width) * 0.5
        samples = Self.wavelengths.map { lambda in
            let d = (lambda - wavelength) / sigma
            return exp(-0.5 * d * d)
        }
    }

    /// The relative glow of a body heated to `temperature` kelvin (Planck's
    /// law, peak scaled to 1): 1800 K is candle orange, 3200 K lamp warm,
    /// 6500 K daylight white, 12000 K sky blue.
    public static func blackbody(_ temperature: Double) -> Spectrum {
        let t = max(100, temperature)
        // Planck's law with the constant factors dropped: the curve is
        // normalized to its own peak below, so only the shape matters.
        func planck(_ lambdaNM: Double) -> Double {
            let lambda = lambdaNM * 1e-9
            let hcOverK = 0.0143877688  // h*c/k, meter kelvin
            return 1 / (pow(lambda, 5) * (exp(hcOverK / (lambda * t)) - 1))
        }
        var values = wavelengths.map(planck)
        let peak = values.max() ?? 1
        if peak > 0 { for i in values.indices { values[i] /= peak } }
        return Spectrum(samples: values)
    }

    /// A flat spectrum of 1: the reflectance of white.
    public static let white = Spectrum(samples: [Double](repeating: 1, count: sampleCount))

    /// A flat spectrum of 0: the reflectance of black.
    public static let black = Spectrum(samples: [Double](repeating: 0, count: sampleCount))

    /// The color this spectrum shows in daylight. Exact for spectra built from
    /// a `Color`; a spectrum the display can't reach (a pure spectral line)
    /// comes back with its below-gamut components clipped to 0.
    public var color: Color { Color(self) }

    /// The sample at `wavelength` nanometers, interpolated between the 5 nm
    /// grid points; 0 outside the visible range.
    public func intensity(at wavelength: Double) -> Double {
        let position = (wavelength - OLLIN_SPECTRAL_LAMBDA_MIN) / OLLIN_SPECTRAL_LAMBDA_STEP
        guard position > -1, position < Double(Self.sampleCount) else { return 0 }
        let clamped = min(max(position, 0), Double(Self.sampleCount - 1))
        let i = Int(clamped)
        let j = min(i + 1, Self.sampleCount - 1)
        let f = clamped - Double(i)
        return samples[i] + (samples[j] - samples[i]) * f
    }

    // MARK: Composing

    /// Filter one spectrum through another: each wavelength keeps the product
    /// of both. This is subtractive mixing, colored glass over colored light.
    public static func * (a: Spectrum, b: Spectrum) -> Spectrum {
        Spectrum(samples: zip(a.samples, b.samples).map(*))
    }

    /// Scale a spectrum: dim or brighten it evenly.
    public static func * (a: Spectrum, s: Double) -> Spectrum {
        Spectrum(samples: a.samples.map { $0 * s })
    }

    public static func * (s: Double, a: Spectrum) -> Spectrum { a * s }

    /// Add two spectra: light on top of light.
    public static func + (a: Spectrum, b: Spectrum) -> Spectrum {
        Spectrum(samples: zip(a.samples, b.samples).map(+))
    }

    /// Blend toward `other` the way scattering pigments blend (the
    /// Kubelka-Munk model): each wavelength mixes the two paints'
    /// absorption-to-scattering ratios by `t` and turns the result back into a
    /// reflectance. Unlike a plain average this is how paint behaves, so
    /// yellow and blue meet in green, and mixes darken the way pigment does.
    /// `t` clamps to `0...1`; 0 is this spectrum, 1 is `other`.
    public func mixedAsPaint(with other: Spectrum, _ t: Double) -> Spectrum {
        let t = min(max(t, 0), 1)
        var out = [Double](repeating: 0, count: Self.sampleCount)
        for i in 0..<Self.sampleCount {
            let ka = Self.absorptionRatio(samples[i])
            let kb = Self.absorptionRatio(other.samples[i])
            let k = ka + (kb - ka) * t
            out[i] = 1 + k - sqrt(k * k + 2 * k)
        }
        return Spectrum(samples: out)
    }

    /// The Kubelka-Munk absorption-to-scattering ratio of a reflectance.
    /// The model needs a reflectance strictly inside 0...1, so the value is
    /// clamped just off both ends before the ratio.
    private static func absorptionRatio(_ reflectance: Double) -> Double {
        let r = min(max(reflectance, 1e-4), 1 - 1e-4)
        return (1 - r) * (1 - r) / (2 * r)
    }

    // MARK: The data behind the conversions

    static let basisR = Self.load(ollin_spectral_basis_r)
    static let basisG = Self.load(ollin_spectral_basis_g)
    static let basisB = Self.load(ollin_spectral_basis_b)

    /// The daylight-weighted observer: `weights[i]` is the XYZ contribution of
    /// one unit of reflectance at sample `i`, already normalized so a flat
    /// spectrum of 1 integrates to the white point.
    static let weights: [SIMD3<Double>] = {
        let x = load(ollin_spectral_xbar), y = load(ollin_spectral_ybar), z = load(ollin_spectral_zbar)
        let d65 = load(ollin_spectral_d65)
        let luminance = zip(d65, y).reduce(0) { $0 + $1.0 * $1.1 }
        return (0..<sampleCount).map { i in
            SIMD3(x[i], y[i], z[i]) * d65[i] / luminance
        }
    }()

    /// XYZ to linear RGB, inverted from the *measured* XYZ of the three basis
    /// curves rather than the textbook primaries matrix: with the same tables
    /// on both legs a color-spectrum-color round trip is exact to
    /// floating-point rounding, not just to the data's fitting error.
    static let rgbFromXYZ: simd_double3x3 = {
        func xyz(of basis: [Double]) -> SIMD3<Double> {
            var sum = SIMD3<Double>.zero
            for i in 0..<sampleCount { sum += weights[i] * basis[i] }
            return sum
        }
        return simd_double3x3(columns: (xyz(of: basisR), xyz(of: basisG), xyz(of: basisB))).inverse
    }()

    private static func load<T>(_ tuple: T) -> [Double] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Double.self)) }
    }
}

public extension Color {
    /// The reflectance spectrum that shows as this color in daylight; the
    /// doorway from a picked color into the spectral operations.
    var spectrum: Spectrum { Spectrum(self) }

    /// The color `spectrum` shows in daylight (the reverse of
    /// `Color.spectrum`). Components a display can't reach clip to 0.
    init(_ spectrum: Spectrum, alpha: Double = 1) {
        var xyz = SIMD3<Double>.zero
        for i in 0..<Spectrum.sampleCount { xyz += Spectrum.weights[i] * spectrum.samples[i] }
        let rgb = Spectrum.rgbFromXYZ * xyz
        self.init(red: Color.linearToSrgb(max(0, rgb.x)),
                  green: Color.linearToSrgb(max(0, rgb.y)),
                  blue: Color.linearToSrgb(max(0, rgb.z)),
                  alpha: alpha)
    }

    /// The pure hue of one wavelength of light, in nanometers: 450 is blue,
    /// 550 green, 590 yellow, 650 red. The spectral locus runs past what a
    /// display can show, so the color is the nearest displayable version,
    /// scaled to full brightness. Sweep 400 to 700 for a physical rainbow.
    init(wavelength: Double) {
        let line = Spectrum(wavelength: wavelength)
        var xyz = SIMD3<Double>.zero
        for i in 0..<Spectrum.sampleCount { xyz += Spectrum.weights[i] * line.samples[i] }
        var rgb = simd_max(Spectrum.rgbFromXYZ * xyz, .zero)
        let peak = max(rgb.x, max(rgb.y, rgb.z))
        if peak > 0 { rgb /= peak }
        self.init(red: Color.linearToSrgb(rgb.x),
                  green: Color.linearToSrgb(rgb.y),
                  blue: Color.linearToSrgb(rgb.z),
                  alpha: 1)
    }
}
