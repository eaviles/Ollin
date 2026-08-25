import Testing
@testable import Ollin

/// Behavioral probes for `Spectrum` and paint mixing. The load-bearing claims:
/// a color that goes through a spectrum and back is unchanged (the conversion
/// matrix is inverted from the same tables that build the spectra, so the trip
/// is exact, not just close), white and black are the flat spectra, paint
/// mixing lands where paint lands (yellow and blue meet in green, never gray),
/// filtering multiplies, and the wavelength and blackbody doors order the
/// rainbow and the glow the way physics does. Pure CPU, no Metal.
@Suite
struct SpectrumTests {

    // MARK: Round trip

    /// A color into a spectrum and back must reproduce the input to floating-
    /// point rounding: the primaries, white, black, and unremarkable mixtures.
    /// This exactness is what lets `.paint` mixing sit beside the other
    /// `ColorSpace` cases without shifting endpoints.
    @Test func aColorSurvivesTheRoundTripExactly() {
        let colors = [
            Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 1, blue: 0),
            Color(red: 0, green: 0, blue: 1), Color(red: 1, green: 1, blue: 1),
            Color(red: 0, green: 0, blue: 0), Color(red: 0.23, green: 0.55, blue: 0.81),
            Color(red: 0.02, green: 0.97, blue: 0.4),
        ]
        for c in colors {
            let back = c.spectrum.color
            #expect(abs(back.red - c.red) < 1e-9)
            #expect(abs(back.green - c.green) < 1e-9)
            #expect(abs(back.blue - c.blue) < 1e-9)
        }
    }

    /// White's reflectance is flat 1 and black's flat 0: the basis is a
    /// partition of unity, so the two ends of the gray axis are the two flat
    /// spectra and everything else sits between them.
    @Test func whiteIsFlatOneAndBlackIsFlatZero() {
        let white = Color(red: 1, green: 1, blue: 1).spectrum
        let black = Color(red: 0, green: 0, blue: 0).spectrum
        for i in 0..<Spectrum.sampleCount {
            #expect(abs(white.samples[i] - 1) < 1e-4)
            #expect(abs(black.samples[i]) < 1e-12)
        }
    }

    /// Alpha rides on `Color`, not on the spectrum: the conversion carries it
    /// through unchanged.
    @Test func alphaPassesThrough() {
        let c = Color(red: 0.6, green: 0.3, blue: 0.1, alpha: 0.42)
        #expect(abs(Color(c.spectrum, alpha: c.alpha).alpha - 0.42) < 1e-12)
    }

    // MARK: Paint mixing

    /// The reason this exists: yellow and blue paint make green. The mix's
    /// green channel must dominate both of its own endpoints' shared channels,
    /// where a plain RGB average would sit near gray.
    @Test func yellowAndBluePaintMakeGreen() {
        let yellow = Color(red: 1, green: 0.85, blue: 0.05)
        let blue = Color(red: 0.1, green: 0.25, blue: 0.9)
        let mix = Color.mix(yellow, blue, t: 0.5, in: .paint)
        #expect(mix.green > mix.red)
        #expect(mix.green > mix.blue)
    }

    /// The knob is honest at its ends: t = 0 is the first paint, t = 1 the
    /// second, exactly.
    @Test func paintMixEndsOnItsEndpoints() {
        let a = Color(red: 0.7, green: 0.2, blue: 0.3)
        let b = Color(red: 0.1, green: 0.5, blue: 0.9)
        let at0 = Color.mix(a, b, t: 0, in: .paint)
        let at1 = Color.mix(a, b, t: 1, in: .paint)
        for (x, y) in [(at0, a), (at1, b)] {
            #expect(abs(x.red - y.red) < 1e-6)
            #expect(abs(x.green - y.green) < 1e-6)
            #expect(abs(x.blue - y.blue) < 1e-6)
        }
    }

    /// Mixing has no favorite side: a mix of A toward B at t equals the mix of
    /// B toward A at 1 - t.
    @Test func paintMixIsSymmetric() {
        let a = Color(red: 0.9, green: 0.6, blue: 0.1)
        let b = Color(red: 0.2, green: 0.3, blue: 0.7)
        let forward = Color.mix(a, b, t: 0.3, in: .paint)
        let backward = Color.mix(b, a, t: 0.7, in: .paint)
        #expect(abs(forward.red - backward.red) < 1e-9)
        #expect(abs(forward.green - backward.green) < 1e-9)
        #expect(abs(forward.blue - backward.blue) < 1e-9)
    }

    /// Paint mixes darken (pigments absorb; they never brighten each other):
    /// the mid mix of two paints is no brighter than the brighter endpoint.
    @Test func paintMixesNeverExceedTheBrighterPaint() {
        let a = Color(red: 1, green: 0.9, blue: 0.1)
        let b = Color(red: 0.1, green: 0.2, blue: 0.9)
        let mix = Color.mix(a, b, t: 0.5, in: .paint)
        let brightest = max(a.red, a.green, a.blue, b.red, b.green, b.blue)
        #expect(max(mix.red, mix.green, mix.blue) <= brightest + 1e-9)
    }

    // MARK: Filtering

    /// Subtractive filtering: yellow glass passes red and green, cyan glass
    /// green and blue, so light through both comes out green.
    @Test func yellowThroughCyanPassesGreen() {
        let yellow = Color(red: 1, green: 1, blue: 0.05).spectrum
        let cyan = Color(red: 0.05, green: 1, blue: 1).spectrum
        let through = (yellow * cyan).color
        #expect(through.green > through.red)
        #expect(through.green > through.blue)
    }

    // MARK: The two physical doors

    /// Single wavelengths order themselves along the rainbow: 460 nm reads
    /// blue, 550 nm green, 640 nm red.
    @Test func wavelengthsOrderAsTheRainbow() {
        let blue = Color(wavelength: 460)
        #expect(blue.blue > blue.red && blue.blue > blue.green)
        let green = Color(wavelength: 550)
        #expect(green.green > green.red && green.green > green.blue)
        let red = Color(wavelength: 640)
        #expect(red.red > red.green && red.red > red.blue)
    }

    /// A spectral line lands where it was asked for: the sample peaks at the
    /// line's own wavelength and dies away from it.
    @Test func aLinePeaksAtItsOwnWavelength() {
        let line = Spectrum(wavelength: 550, width: 20)
        #expect(abs(line.intensity(at: 550) - 1) < 1e-9)
        #expect(line.intensity(at: 550) > line.intensity(at: 600))
        #expect(line.intensity(at: 700) < 1e-6)
        #expect(line.intensity(at: 200) == 0)
    }

    /// The glow of a heated body runs candle orange to sky blue: the red-to-
    /// blue balance falls as the temperature climbs.
    @Test func blackbodyRunsWarmToCool() {
        func redOverBlue(_ kelvin: Double) -> Double {
            let c = Color(.blackbody(kelvin))
            return Color.srgbToLinear(c.red) / max(1e-9, Color.srgbToLinear(c.blue))
        }
        let candle = redOverBlue(1800)
        let lamp = redOverBlue(3200)
        let daylight = redOverBlue(6500)
        let sky = redOverBlue(12000)
        #expect(candle > lamp && lamp > daylight && daylight > sky)
        #expect(candle > 3)
    }
}
