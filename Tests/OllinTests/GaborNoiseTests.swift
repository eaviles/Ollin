import Accelerate
import CoreGraphics
import Testing
@testable import Ollin

/// Gabor noise, checked against the laws the technique promises rather than
/// against a picture: the field is centered and scaled to three standard
/// deviations, its spectrum peaks at the wavelength asked for and narrows with
/// the bandwidth, one direction is one direction, the phase is a period, the
/// pixel filter fades a wavelength near the pixel grid, and the GPU generator
/// paints the field the CPU form computes. The math runs on the CPU (so most
/// of this runs everywhere); one probe renders.
@MainActor
@Suite
struct GaborNoiseTests {

    /// The field sampled at pixel centers over an `n` by `n` square.
    private func field(_ noise: GaborNoise, n: Int = 256) -> [Float] {
        var out = [Float](repeating: 0, count: n * n)
        for y in 0 ..< n {
            for x in 0 ..< n {
                out[y * n + x] = Float(noise.value(Double(x) + 0.5, Double(y) + 0.5))
            }
        }
        return out
    }

    private func mean(_ v: [Float]) -> Float { v.reduce(0, +) / Float(v.count) }

    private func standardDeviation(_ v: [Float]) -> Float {
        let m = mean(v)
        return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(v.count)).squareRoot()
    }

    /// The power spectrum along one axis: every row (or, `transposed`, every
    /// column) transformed and the powers averaged, bins 0 ..< n / 2 in cycles
    /// per pixel steps of 1 / n. The mean is removed first, so bin 0 is empty.
    private func spectrum(_ v: [Float], n: Int, transposed: Bool = false) -> [Float] {
        let log2n = vDSP_Length(log2(Double(n)))
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        let m = mean(v)
        var power = [Float](repeating: 0, count: n / 2)
        var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
        for line in 0 ..< n {
            for k in 0 ..< n {
                re[k] = (transposed ? v[k * n + line] : v[line * n + k]) - m
                im[k] = 0
            }
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            for k in 0 ..< n / 2 { power[k] += re[k] * re[k] + im[k] * im[k] }
        }
        return power.map { $0 / Float(n) }
    }

    private func peakBin(_ power: [Float]) -> Int {
        var best = 1
        for k in 2 ..< power.count where power[k] > power[best] { best = k }
        return best
    }

    @Test func theFieldIsCenteredAndScaledToThreeSigma() {
        let v = field(GaborNoise(wavelength: 16, seed: 3))
        #expect(abs(mean(v) - 0.5) < 0.02, "a zero-mean noise sits at mid-gray, got \(mean(v))")
        let sd = standardDeviation(v)
        #expect(abs(sd - 1.0 / 6) < 0.03,
                "three standard deviations span the range, so one is a sixth of it; got \(sd)")
    }

    @Test func theNormalizationHoldsAtAnyImpulseCount() {
        let sparse = standardDeviation(field(GaborNoise(wavelength: 16, impulses: 8, seed: 3)))
        let dense = standardDeviation(field(GaborNoise(wavelength: 16, impulses: 64, seed: 3)))
        #expect(abs(sparse - 1.0 / 6) < 0.035, "8 impulses per kernel: \(sparse)")
        #expect(abs(dense - 1.0 / 6) < 0.035, "64 impulses per kernel: \(dense)")
    }

    @Test func theSpectrumPeaksAtTheWavelength() {
        // A wave along x, so the row spectrum carries it; 256 / wavelength is the bin.
        let n = 256
        for wavelength in [16.0, 32.0] {
            let v = field(GaborNoise(wavelength: wavelength, angle: 0, spread: 0, seed: 5), n: n)
            let bin = peakBin(spectrum(v, n: n))
            let expected = Double(n) / wavelength
            #expect(abs(Double(bin) - expected) <= 2,
                    "wavelength \(wavelength) should peak at bin \(expected), got \(bin)")
        }
    }

    @Test func aNarrowBandIsANarrowPeak() {
        let n = 256
        func share(bandwidth: Double) -> Float {
            let v = field(GaborNoise(wavelength: 16, bandwidth: bandwidth, angle: 0, spread: 0, seed: 5), n: n)
            let power = spectrum(v, n: n)
            let center = n / 16
            let near = (center - 2 ... center + 2).reduce(Float(0)) { $0 + power[$1] }
            return near / power.reduce(0, +)
        }
        let narrow = share(bandwidth: 0.2), wide = share(bandwidth: 1)
        #expect(narrow > 0.6, "bandwidth 0.2 keeps most of its power within two bins: \(narrow)")
        #expect(wide < narrow * 0.7, "bandwidth 1 spreads it: \(wide) against \(narrow)")
    }

    @Test func oneDirectionIsOneDirection() {
        let n = 256
        let bin = n / 16
        func ratio(angle: Double) -> Float {
            let v = field(GaborNoise(wavelength: 16, angle: angle, spread: 0, seed: 7), n: n)
            let along = spectrum(v, n: n)[bin], across = spectrum(v, n: n, transposed: true)[bin]
            return along / across
        }
        #expect(ratio(angle: 0) > 20, "angle 0 oscillates along x: the row spectrum holds the wave")
        #expect(ratio(angle: .pi / 2) < 1.0 / 20, "angle pi/2 turns it: the column spectrum holds it")
    }

    @Test func spreadPiIsEveryDirection() {
        let n = 256
        let bin = n / 16
        let v = field(GaborNoise(wavelength: 16, angle: 0, spread: .pi, seed: 7), n: n)
        let along = spectrum(v, n: n)[bin], across = spectrum(v, n: n, transposed: true)[bin]
        #expect(along / across > 0.5 && along / across < 2,
                "the isotropic field carries the wave on both axes alike: \(along / across)")
    }

    @Test func thePhaseIsAPeriodAndHalfOfItIsANegative() {
        let base = GaborNoise(wavelength: 20, bandwidth: 0.4, seed: 11)
        let lap = GaborNoise(wavelength: 20, bandwidth: 0.4, phase: .tau, seed: 11)
        let half = GaborNoise(wavelength: 20, bandwidth: 0.4, phase: .pi, seed: 11)
        for (x, y) in [(3.5, 7.25), (100.0, 41.0), (250.5, 250.5), (-30.0, 12.0)] {
            #expect(abs(base.signedValue(x, y) - lap.signedValue(x, y)) < 1e-6)
            #expect(abs(base.signedValue(x, y) + half.signedValue(x, y)) < 1e-6,
                    "every wave is a cosine, so half a turn of phase negates the field")
        }
    }

    @Test func theSeedPicksTheField() {
        let a = field(GaborNoise(wavelength: 16, seed: 1), n: 64)
        let again = field(GaborNoise(wavelength: 16, seed: 1), n: 64)
        let b = field(GaborNoise(wavelength: 16, seed: 2), n: 64)
        #expect(a == again, "the same seed is the same field, bit for bit")
        let gap = zip(a, b).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(a.count)
        #expect(gap > 0.05, "another seed is another field: \(gap)")
    }

    @Test func theCoordinatesArePixelsAndTheFieldIsContinuous() {
        // Halfway between two pixels the field sits between its neighbors'
        // values (a smooth sum of Gaussians), and far coordinates are as
        // ordinary as near ones.
        let noise = GaborNoise(wavelength: 24, seed: 9)
        let a = noise.value(50, 50), b = noise.value(51, 50), mid = noise.value(50.5, 50)
        #expect(abs(mid - (a + b) / 2) < 0.02)
        #expect(noise.value(10_000.5, -7_000.25) >= 0 && noise.value(10_000.5, -7_000.25) <= 1)
    }

    /// What the pixel filter leaves of the contrast, from the closed form: the
    /// filtered kernel's gain times its width ratio (the variance scales with
    /// gain squared over width squared), for a Gaussian footprint of sigma 0.5.
    private func filteredContrast(wavelength: Double, bandwidth: Double) -> Double {
        let f0 = 1 / wavelength, a0 = bandwidth * f0, aa = a0 * a0, s2 = 0.25
        let a1sq = 1 / (1 / aa + 2 * .pi * s2)
        let f1 = f0 / (1 + 2 * .pi * s2 * aa)
        let k1 = (a1sq / aa) * exp(-0.5 * f0 * f0 / (1 / (4 * .pi * .pi * s2) + aa / (2 * .pi)))
        let e0 = exp(-2 * .pi * f0 * f0 / aa), e1 = exp(-2 * .pi * f1 * f1 / a1sq)
        return k1 * (aa / a1sq).squareRoot() * ((1 + e1) / (1 + e0)).squareRoot()
    }

    @Test func aWavelengthNearThePixelGridFadesInsteadOfAliasing() {
        let fine = standardDeviation(field(GaborNoise(wavelength: 2.5, seed: 3), n: 256))
        let predicted = Float(filteredContrast(wavelength: 2.5, bandwidth: 0.5) / 6)
        #expect(fine < 0.1, "at 2.5 pixels the pixel filter takes most of the sixth: \(fine)")
        #expect(abs(fine - predicted) < 0.012,
                "the fade follows the closed form: \(fine) against \(predicted)")
        #expect(filteredContrast(wavelength: 24, bandwidth: 0.5) > 0.98,
                "at 24 pixels the filter barely touches the field")
    }

    // MARK: The GPU paints the same field

    /// The layer's red channel, linearized (the generator mixes in linear light
    /// and the export encodes sRGB).
    private func linearField(of image: CGImage) -> [Float] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var out = [Float](repeating: 0, count: w * h)
        for i in 0 ..< w * h {
            let c = Double(data[i * 4]) / 255
            out[i] = Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
        return out
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theGeneratorPaintsTheFieldTheCPUComputes() throws {
        let probe = GaborProbe()
        let image = try #require(OllinApp.image(of: probe, frame: 1))
        let painted = linearField(of: image)
        let computed = field(probe.noise, n: 256)
        var total: Float = 0, far = 0
        for (a, b) in zip(painted, computed) {
            let d = abs(a - b)
            total += d
            if d > 0.03 { far += 1 }
        }
        let meanGap = total / Float(painted.count)
        #expect(meanGap < 0.006, "the mean gap is the dither and the 8-bit step: \(meanGap)")
        #expect(Float(far) / Float(painted.count) < 0.005,
                "\(far) pixels differ by more than 0.03 in linear light")
    }
}

/// A 256-pixel canvas filled by the generator with the parameters the CPU form
/// is asked with, drawn at 1:1 so pixel (x, y) is the field at (x + 0.5, y + 0.5).
private final class GaborProbe: Sketch {
    let noise = GaborNoise(wavelength: 18, bandwidth: 0.4, angle: 0.6, spread: 0.8, seed: 21)
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let layer = generate(.gaborNoise(wavelength: noise.wavelength, bandwidth: noise.bandwidth,
                                         angle: noise.angle, spread: noise.spread,
                                         impulses: noise.impulses, seed: noise.seed),
                             width: 256, height: 256)
        drawImage(layer.image, 0, 0)
    }
}
