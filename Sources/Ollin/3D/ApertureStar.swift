import Accelerate
import Foundation

/// The star a bright source wears, worked out from the shape of the opening its
/// light came through.
///
/// The ghosts are one half of a flare and this is the other. Where a ghost is
/// light that took a wrong path through the lens, the star is light *bending at
/// the edges of the iris*. Far from the opening, what a straight edge does to a
/// wave is exactly its Fourier transform, so the pattern on the sensor is the
/// power spectrum of the opening itself. Six blades put six arms on the star for
/// the same reason they put six sides on a ghost.
///
/// It is a bake, not a per-frame cost. The opening only changes when the blade
/// count or the f-number does, so the transform runs once and the result is a
/// small texture the flare samples.
///
/// Written from the published Fraunhofer (far-field) diffraction model, credited
/// in `ATTRIBUTION.md`.
enum ApertureStar {

    /// The wavelength in nanometers the baked coordinates are measured in. Every
    /// other wavelength samples the same spectrum at its own scale, which is what
    /// fans the arms from blue at the middle out to red at the tips.
    static let referenceWavelength = 550.0

    /// How much of the baked image the opening fills, as a fraction of the image
    /// width. A quarter leaves the spectrum room and keeps the opening's own edge
    /// well sampled.
    static let apertureFraction = 0.25

    /// Bake the star an opening of `blades` sides makes. `blades` under 3 is a
    /// round iris, which has no arms at all, only rings.
    ///
    /// `wear` is how worn the opening is, `0` to `1`. A clean one is a perfect
    /// polygon and throws perfect arms. A real one has blades that do not sit
    /// quite evenly, edges that are not quite straight, and specks and hairline
    /// scratches across it, and each of those bends a little light of its own:
    /// the arms split and fray, and fine needles fill the space between them.
    /// The wear is drawn from the blade count, so one opening always bakes the
    /// same star.
    ///
    /// The result is square, `size` by `size`, with the source at the middle, in
    /// linear light. Its mean is 1, so the arms sit in a workable range and the
    /// middle runs far above it, which is what a source looks like.
    static func bake(blades: Int, wear: Double = 0, size: Int = 512) -> StarPattern {
        let spectrum = powerSpectrum(blades: blades, wear: wear, size: size)
        var pixels = [Float](repeating: 0, count: size * size * 4)
        let center = Double(size) / 2

        // Sample the spectrum once per wavelength, each at its own scale, and add
        // the color that wavelength shows as. A longer wave diffracts further, so
        // it reads the spectrum nearer the middle and lands further out.
        // Steps fine enough that the rings each single wavelength makes blur
        // into one another along the arm, which is what leaves smooth needles
        // rather than beads.
        let steps = 48
        var weights: [(scale: Double, color: SIMD3<Double>)] = []
        weights.reserveCapacity(steps)
        var weightSum = SIMD3<Double>.zero
        for step in 0..<steps {
            let wavelength = 400 + (700 - 400) * Double(step) / Double(steps - 1)
            let color = linearColor(ofWavelength: wavelength)
            weights.append((referenceWavelength / wavelength, color))
            weightSum += color
        }
        // Keep the total energy neutral, so a clean opening makes a white star
        // with colored fringes rather than a colored one.
        let normalize = SIMD3<Double>(1 / max(weightSum.x, 1e-9),
                                      1 / max(weightSum.y, 1e-9),
                                      1 / max(weightSum.z, 1e-9))

        for y in 0..<size {
            for x in 0..<size {
                let offset = SIMD2<Double>(Double(x) + 0.5 - center, Double(y) + 0.5 - center)
                var sum = SIMD3<Double>.zero
                for (scale, color) in weights {
                    let value = spectrum.sample(offset * scale + SIMD2(center, center))
                    sum += color * value
                }
                sum *= normalize
                // Fade to nothing at the edge of what was measured. The arms run
                // further than the bake reaches, and without this they would end
                // in a straight cut across the picture.
                let reach = (offset.x * offset.x + offset.y * offset.y).squareRoot() / center
                let fade = min(1, max(0, (1 - reach) / 0.18))
                sum *= fade * fade * (3 - 2 * fade)
                let index = (y * size + x) * 4
                pixels[index] = Float(sum.x)
                pixels[index + 1] = Float(sum.y)
                pixels[index + 2] = Float(sum.z)
                pixels[index + 3] = 1
            }
        }

        // Scale so the mean is 1. The middle then runs orders of magnitude above
        // it, which is right: nearly all of a star's light is in its core, and
        // what makes the arms visible in a photograph is how bright the source is
        // rather than how much of the light reaches them.
        var mean = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            mean += (Double(pixels[index]) + Double(pixels[index + 1])
                     + Double(pixels[index + 2])) / 3
        }
        mean /= Double(size * size)
        let scale = Float(mean > 0 ? 1 / mean : 1)
        // A ceiling only the core ever reaches, so the pattern stays inside what
        // a half-float texture can carry. The source is drawn over its own core
        // and the tone map clips it either way.
        let ceiling: Float = 4000
        for index in 0..<pixels.count where index % 4 != 3 {
            pixels[index] = min(pixels[index] * scale, ceiling)
        }
        return StarPattern(size: size, pixels: pixels, blades: max(0, blades))
    }

    /// A small deterministic generator, so the wear on an opening is the same
    /// every time it is baked.
    private struct Wear {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        mutating func next(_ low: Double, _ high: Double) -> Double {
            low + (high - low) * next()
        }
    }

    /// The opening's own image: 1 inside, 0 outside, with a one-pixel soft edge.
    /// The softness matters. A hard-stepped edge rings against the sampling grid
    /// and lays false arms across the diagonals.
    ///
    /// With `wear` above zero the opening is a worn one. Each blade sits a little
    /// in or out of true and a little off its angle, so opposite edges stop being
    /// exactly parallel and each arm splits into a close pair. Each edge bows by
    /// a hair, which frays an arm into a narrow fan. And specks and scratches
    /// lie across the opening, each throwing a faint wide pattern of its own that
    /// the spread of colors then draws out into needles.
    private static func apertureImage(blades: Int, wear: Double, size: Int) -> [Double] {
        var image = [Double](repeating: 0, count: size * size)
        let center = Double(size) / 2
        let radius = Double(size) * apertureFraction
        let worn = min(1, max(0, wear))
        var random = Wear(state: 0x0111_0A57 &+ UInt64(max(0, blades)) &* 7919)

        // One entry per blade: the angle its edge faces, how far from the middle
        // it sits, and how much it bows.
        struct Blade { var facing: Double; var reach: Double; var bow: Double }
        var edges: [Blade] = []
        if blades >= 3 {
            let wedge = Double.pi / Double(blades)
            for k in 0..<blades {
                let facing = 2 * wedge * Double(k) + worn * random.next(-0.035, 0.035)
                let reach = radius * cos(wedge) * (1 + worn * random.next(-0.03, 0.03))
                edges.append(Blade(facing: facing, reach: reach,
                                   bow: worn * random.next(-0.02, 0.05)))
            }
        }
        for y in 0..<size {
            for x in 0..<size {
                let point = SIMD2<Double>(Double(x) + 0.5 - center, Double(y) + 0.5 - center)
                var distance: Double
                if edges.isEmpty {
                    distance = (point.x * point.x + point.y * point.y).squareRoot() - radius
                } else {
                    distance = -Double.infinity
                    for edge in edges {
                        let along = point.x * cos(edge.facing) + point.y * sin(edge.facing)
                        let across = -point.x * sin(edge.facing) + point.y * cos(edge.facing)
                        // A bowed edge is a shallow arc: it sits back from the
                        // straight line by more the further along it runs.
                        let sag = edge.bow * across * across / radius
                        distance = max(distance, along + sag - edge.reach)
                    }
                }
                image[y * size + x] = min(1, max(0, 0.5 - distance))
            }
        }
        guard worn > 0 else { return image }

        // Specks: small dark discs anywhere across the opening.
        let specks = Int((worn * 90).rounded())
        for _ in 0..<specks {
            let turn = random.next(0, 2 * Double.pi), out = radius * random.next().squareRoot()
            let middle = SIMD2(center + out * cos(turn), center + out * sin(turn))
            let size_ = random.next(0.7, 1.0 + 3.2 * worn)
            let depth = random.next(0.5, 1)
            stamp(&image, size: size, around: middle, reach: size_ + 1) { offset in
                let d = (offset.x * offset.x + offset.y * offset.y).squareRoot() - size_
                return depth * min(1, max(0, 0.5 - d))
            }
        }
        // Scratches: hairlines, a fraction of a pixel to a pixel wide.
        let scratches = Int((worn * 26).rounded())
        for _ in 0..<scratches {
            let turn = random.next(0, 2 * Double.pi), out = radius * random.next().squareRoot() * 0.8
            let middle = SIMD2(center + out * cos(turn), center + out * sin(turn))
            let heading = random.next(0, Double.pi)
            let half = radius * random.next(0.08, 0.45)
            let width = random.next(0.35, 0.9)
            let depth = random.next(0.4, 1)
            let dir = SIMD2(cos(heading), sin(heading))
            stamp(&image, size: size, around: middle, reach: half + 2) { offset in
                let along = offset.x * dir.x + offset.y * dir.y
                let across = abs(-offset.x * dir.y + offset.y * dir.x)
                let ends = min(1, max(0, 0.5 - (abs(along) - half)))
                return depth * ends * min(1, max(0, 0.5 - (across - width)))
            }
        }
        return image
    }

    /// Darken the image around a point by whatever `cover` says each texel loses.
    private static func stamp(_ image: inout [Double], size: Int, around middle: SIMD2<Double>,
                              reach: Double, cover: (SIMD2<Double>) -> Double) {
        let x0 = max(0, Int(middle.x - reach)), x1 = min(size - 1, Int(middle.x + reach) + 1)
        let y0 = max(0, Int(middle.y - reach)), y1 = min(size - 1, Int(middle.y + reach) + 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let offset = SIMD2(Double(x) + 0.5 - middle.x, Double(y) + 0.5 - middle.y)
                image[y * size + x] *= 1 - min(1, max(0, cover(offset)))
            }
        }
    }

    /// The power spectrum of the opening, with the middle of the pattern at the
    /// middle of the array.
    private static func powerSpectrum(blades: Int, wear: Double, size: Int) -> PowerSpectrum {
        let image = apertureImage(blades: blades, wear: wear, size: size)
        let count = size * size
        var real = [Float](repeating: 0, count: count)
        var imaginary = [Float](repeating: 0, count: count)
        for index in 0..<count { real[index] = Float(image[index]) }

        let log2n = vDSP_Length(log2(Double(size)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return PowerSpectrum(size: size, values: [Double](repeating: 0, count: count))
        }
        defer { vDSP_destroy_fftsetup(setup) }
        var values = [Double](repeating: 0, count: count)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!,
                                            imagp: imaginaryBuffer.baseAddress!)
                vDSP_fft2d_zip(setup, &split, 1, 0, log2n, log2n, FFTDirection(FFT_FORWARD))
                // The transform puts zero frequency at the corner; the pattern
                // reads from the middle, so fold the quadrants across.
                let half = size / 2
                for y in 0..<size {
                    for x in 0..<size {
                        let source = ((y + half) % size) * size + ((x + half) % size)
                        let re = Double(realBuffer[source]), im = Double(imaginaryBuffer[source])
                        values[y * size + x] = re * re + im * im
                    }
                }
            }
        }
        return PowerSpectrum(size: size, values: values)
    }

    /// What one wavelength looks like, in linear light.
    ///
    /// The eye's response to a single wavelength is the CIE color matching
    /// functions; this is the published analytic fit to them, then the standard
    /// conversion into the linear primaries the renderer works in. Negative
    /// values are clipped, since a display cannot show them.
    static func linearColor(ofWavelength wavelength: Double) -> SIMD3<Double> {
        func lobe(_ value: Double, _ center: Double, _ width: Double) -> Double {
            let t = (value - center) / width
            return exp(-0.5 * t * t)
        }
        func logLobe(_ value: Double, _ center: Double, _ width: Double) -> Double {
            let t = (log(value) - log(center)) / width
            return exp(-0.5 * t * t)
        }
        let x = 1.065 * lobe(wavelength, 595.8, 33.33) + 0.366 * lobe(wavelength, 446.8, 19.44)
        let y = 1.014 * logLobe(wavelength, 556.3, 0.075)
        let z = 1.839 * logLobe(wavelength, 449.8, 0.051)
        let red = 3.2406 * x - 1.5372 * y - 0.4986 * z
        let green = -0.9689 * x + 1.8758 * y + 0.0415 * z
        let blue = 0.0557 * x - 0.2040 * y + 1.0570 * z
        return SIMD3(max(0, red), max(0, green), max(0, blue))
    }
}

/// A baked star: the pattern one opening makes, ready to be sampled at a source.
struct StarPattern: Equatable {
    /// The pattern's width and height in texels.
    let size: Int
    /// Linear rgba, row-major, the source at the middle.
    let pixels: [Float]
    /// The blade count it was baked for, which is what the cache is keyed on.
    let blades: Int

    /// How far the pattern reaches from its middle, as an angle in radians, for
    /// an iris of this radius in millimeters.
    ///
    /// Light of wavelength L bending around an opening of size D spreads by about
    /// L over D, so a *smaller* opening throws a *wider* star. That is why
    /// stopping down grows the star at the same time as it shrinks the ghosts.
    func halfAngle(irisRadiusMillimeters radius: Double) -> Double {
        guard radius > 0 else { return 0 }
        let wavelength = ApertureStar.referenceWavelength * 1e-6   // nm to mm
        // The image spans the opening's radius over `apertureFraction`, and the
        // pattern reaches the sampling limit at half the texel count.
        let span = radius / ApertureStar.apertureFraction
        return wavelength * Double(size) / (2 * span)
    }

    static func == (lhs: StarPattern, rhs: StarPattern) -> Bool {
        lhs.size == rhs.size && lhs.blades == rhs.blades
    }
}

/// A square power spectrum that can be read at a fractional position.
private struct PowerSpectrum {
    let size: Int
    let values: [Double]

    /// Bilinear read, zero outside. The pattern runs off the edge for the longer
    /// wavelengths, and zero there is the honest answer: nothing was measured.
    func sample(_ point: SIMD2<Double>) -> Double {
        let x = point.x - 0.5, y = point.y - 0.5
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        func at(_ px: Int, _ py: Int) -> Double {
            guard px >= 0, py >= 0, px < size, py < size else { return 0 }
            return values[py * size + px]
        }
        let top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx
        let bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }
}
