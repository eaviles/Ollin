import Foundation

// Dithering: quantize an image down to a few colors while keeping its tones.
//
// Two families, sharing one pass. *Error diffusion* (Floyd-Steinberg and its
// descendants) quantizes a pixel, then pushes the rounding error onto the
// neighbours it has not visited yet, so the mistake is paid back nearby. It is
// serial by nature: a pixel's value depends on every pixel before it, which is
// why this is CPU work and not a fragment shader. *Threshold maps* (an ordered
// Bayer matrix, a blue-noise tile) instead nudge each pixel by a fixed
// per-position offset before quantizing, so every pixel is independent.
//
// Two color spaces do two different jobs here, and mixing them up is the classic
// bug. Tone lives in *linear light*, because that is the quantity the eye
// integrates when the dots blur together: an error diffused in sRGB makes
// gradients come out too bright. *Which* color looks closest, though, is a
// perceptual question (OKLab), because nearest-in-linear over-weights the bright
// end and snaps midtones too dark.
//
// Three cases fall out of that, and the split is load-bearing.
//
// `.none` carries no error, so it simply picks the perceptually nearest color.
//
// Error diffusion must pick the *linearly* nearest color, even though that is
// the perceptually worse pick, because linear light is the space it carries its
// error in. Choosing in one space while accumulating in another leaves a residual
// the choice never tried to minimize, and along the tone where the two rules
// disagree that residual is consistently signed: a thin false contour of the
// wrong color traces the gradient, one or two pixels wide. Matching the spaces
// removes it. (It hides from tile-averaged error statistics, being so thin, so
// it is pinned below by a single-pixel test on the choice rule itself.)
//
// A threshold map has no memory, so it can have both. It picks its two candidate
// colors perceptually, then lets the threshold choose between them at the
// fraction that reproduces the pixel's linear light. Its tone is right only
// because that fraction is linear: perturbing in linear and then deciding by
// OKLab distance would put a 25% gray against black and white at 46% white
// instead of 5%.
//
// The kernels, the Bayer recurrence, and the blue-noise construction are
// implemented from the published techniques (credited in ATTRIBUTION.md).

/// How an image is dithered when its colors are reduced to a small set.
///
/// The error-diffusion kernels (`.floydSteinberg` and below) trade speed for
/// accuracy and give the organic, scattered look. The threshold maps
/// (`.ordered`, `.blueNoise`) are position-only: `.ordered` gives the familiar
/// crosshatch of retro graphics, `.blueNoise` an even, structureless grain.
public enum Dither: Sendable, Equatable {
    /// No dithering: snap each pixel to the nearest output color. Bands.
    case none
    /// Ordered dithering through a Bayer matrix `size` cells across. `size`
    /// is rounded to a power of two in `2...16`; larger is finer and less
    /// obviously patterned.
    case ordered(size: Int)
    /// Ordered dithering through a 64x64 blue-noise tile: an even grain with
    /// no visible structure and no clumps. The tile is generated once, on first
    /// use, and repeats seamlessly. Generating it costs a few milliseconds in a
    /// release build (a second or two in a debug build), once per process.
    case blueNoise
    /// Floyd-Steinberg (1976), the classic: four taps, sharp and detailed.
    case floydSteinberg
    /// Jarvis, Judice and Ninke (1976): twelve taps over three rows. Smoother
    /// and slower than Floyd-Steinberg, and it softens fine detail.
    case jarvisJudiceNinke
    /// Stucki (1981): the Jarvis layout retuned. Cleaner, slightly sharper.
    case stucki
    /// Atkinson (mid-1980s): propagates only three quarters of the error, so
    /// it blows out highlights and shadows into clean white and black. The
    /// early Macintosh look.
    case atkinson
    /// Burkes (1988): Stucki without its bottom row. Fast, close to Stucki.
    case burkes
    /// Sierra (1989): three rows, a touch sharper than Jarvis.
    case sierra
    /// Two-row Sierra: Sierra with the last row dropped.
    case twoRowSierra
    /// Sierra Lite: three taps. The cheapest error diffusion worth having.
    case sierraLite
}

// MARK: - Error-diffusion kernels

extension Dither {
    /// The taps this method pushes its quantization error onto: offsets from the
    /// current pixel (`dx` along the scan, `dy` downward) and the fraction of the
    /// error each receives. Empty for the threshold maps and for `.none`.
    var diffusionKernel: [(dx: Int, dy: Int, weight: Double)] {
        func kernel(_ divisor: Double,
                    _ taps: [(Int, Int, Double)]) -> [(dx: Int, dy: Int, weight: Double)] {
            taps.map { (dx: $0.0, dy: $0.1, weight: $0.2 / divisor) }
        }
        switch self {
        case .none, .ordered, .blueNoise:
            return []
        case .floydSteinberg:
            return kernel(16, [(1, 0, 7),
                               (-1, 1, 3), (0, 1, 5), (1, 1, 1)])
        case .jarvisJudiceNinke:
            return kernel(48, [(1, 0, 7), (2, 0, 5),
                               (-2, 1, 3), (-1, 1, 5), (0, 1, 7), (1, 1, 5), (2, 1, 3),
                               (-2, 2, 1), (-1, 2, 3), (0, 2, 5), (1, 2, 3), (2, 2, 1)])
        case .stucki:
            return kernel(42, [(1, 0, 8), (2, 0, 4),
                               (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2),
                               (-2, 2, 1), (-1, 2, 2), (0, 2, 4), (1, 2, 2), (2, 2, 1)])
        case .atkinson:
            // Only 6/8 of the error is passed on. The missing quarter is what
            // crushes flat areas to pure black and white.
            return kernel(8, [(1, 0, 1), (2, 0, 1),
                              (-1, 1, 1), (0, 1, 1), (1, 1, 1),
                              (0, 2, 1)])
        case .burkes:
            return kernel(32, [(1, 0, 8), (2, 0, 4),
                               (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2)])
        case .sierra:
            return kernel(32, [(1, 0, 5), (2, 0, 3),
                               (-2, 1, 2), (-1, 1, 4), (0, 1, 5), (1, 1, 4), (2, 1, 2),
                               (-1, 2, 2), (0, 2, 3), (1, 2, 2)])
        case .twoRowSierra:
            return kernel(16, [(1, 0, 4), (2, 0, 3),
                               (-2, 1, 1), (-1, 1, 2), (0, 1, 3), (1, 1, 2), (2, 1, 1)])
        case .sierraLite:
            return kernel(4, [(1, 0, 2),
                              (-1, 1, 1), (0, 1, 1)])
        }
    }

    /// Whether this method decides by a per-position threshold rather than by
    /// carrying an error forward.
    var usesThresholdMap: Bool {
        switch self {
        case .ordered, .blueNoise: return true
        default: return false
        }
    }

    /// The per-position offset this method adds before quantizing, in `-0.5..<0.5`.
    /// Resolved once per image, not once per pixel: an `.ordered` dither would
    /// otherwise look its matrix up a million times.
    func thresholdMap() -> (Int, Int) -> Double {
        switch self {
        case .ordered(let size):
            let matrix = BayerMatrix.shared(size: size)
            return { matrix.threshold(x: $0, y: $1) }
        case .blueNoise:
            let ranks = BlueNoiseTile.ranks
            let n = BlueNoiseTile.size
            let scale = Double(n * n)
            return { x, y in (Double(ranks[(y % n) * n + (x % n)]) + 0.5) / scale - 0.5 }
        default:
            return { _, _ in 0 }
        }
    }
}

// MARK: - Public entry points

public extension Image {
    /// Dither this image down to `palette`, returning a new image whose every
    /// pixel is one of the palette's colors.
    ///
    /// The companion to `Palette(extractedFrom:)`: pull the colors out of a
    /// picture, then redraw the picture in them.
    ///
    /// ```swift
    /// let photo = loadImage("photo.jpg")!
    /// let colors = Palette(extractedFrom: photo, count: 6)
    /// let poster = photo.dithered(.floydSteinberg, to: colors)
    /// ```
    ///
    /// `amount` scales the grain of the threshold maps (`.ordered`, `.blueNoise`),
    /// clamped to `0...1`: at `1` they hold the image's tone exactly, and at `0`
    /// they band like `.none`. It is ignored by the error-diffusion kernels, which
    /// carry their error exactly. `serpentine` reverses every other row of an error-diffusion scan,
    /// which breaks up the directional streaks a pure left-to-right pass leaves;
    /// it is ignored by the threshold maps.
    ///
    /// This is CPU work over every pixel, so call it in `setup()` and hold the
    /// result, not once per frame. Alpha passes through untouched. A GPU-backed
    /// image (an effects layer, a compute texture, a live video texture) has no
    /// CPU pixels to read and comes back unchanged: call `snapshot()` first.
    /// An empty palette also returns the image unchanged.
    ///
    /// Deterministic: the same image, method, and palette always give the same
    /// pixels, so a dithered result is safe to snapshot and to export.
    func dithered(_ method: Dither = .floydSteinberg,
                  to palette: Palette,
                  amount: Double = 1,
                  serpentine: Bool = true) -> Image {
        guard hasCPUPixels, !palette.colors.isEmpty else { return self }
        return Dither.apply(method, to: self, amount: amount, serpentine: serpentine,
                            quantizer: PaletteQuantizer(palette))
    }

    /// Dither this image down to `levels` evenly spaced steps per channel, the
    /// posterizing form: `levels: 2` gives the eight corners of the color cube
    /// (black, white, and the primaries), `levels: 4` gives 64 colors.
    ///
    /// The steps are evenly spaced in sRGB, the way an 8-bit output ramp is, but
    /// the error is still carried in linear light. `levels` is clamped to at
    /// least 2. See ``dithered(_:to:amount:serpentine:)`` for the shared notes on
    /// `amount`, `serpentine`, cost, and determinism.
    func dithered(_ method: Dither = .floydSteinberg,
                  levels: Int,
                  amount: Double = 1,
                  serpentine: Bool = true) -> Image {
        guard hasCPUPixels else { return self }
        return Dither.apply(method, to: self, amount: amount, serpentine: serpentine,
                            quantizer: LevelQuantizer(levels: max(2, levels)))
    }
}

// MARK: - The shared pass

/// A quantizer's answer: the chosen output color, in both the linear light the
/// error is measured in and the sRGB the pixel is written as.
private struct Choice {
    var linear: SIMD3<Double>
    var srgb: SIMD3<Double>
}

/// Snapping a pixel to the output colors, by the three rules the families need.
private protocol Quantizing {
    /// The output that looks closest. For `.none`, which carries no error.
    func perceptualNearest(_ value: SIMD3<Double>) -> Choice
    /// The output closest in linear light. For the error-diffusion kernels,
    /// which must choose in the space they accumulate their error in.
    func linearNearest(_ value: SIMD3<Double>) -> Choice
    /// Pick between the two outputs bracketing `value`, using `threshold`
    /// (in `-0.5..<0.5`). For the threshold maps.
    func mix(_ value: SIMD3<Double>, threshold: Double) -> Choice
}

extension Dither {
    /// One pass over the image. Threshold maps and error diffusion share it: a
    /// threshold method has an empty kernel and a nonzero per-pixel offset, an
    /// error-diffusion method the reverse.
    fileprivate static func apply<Q: Quantizing>(_ method: Dither,
                                                 to image: Image,
                                                 amount: Double,
                                                 serpentine: Bool,
                                                 quantizer: Q) -> Image {
        let width = image.width, height = image.height
        let kernel = method.diffusionKernel
        let thresholdAt = method.thresholdMap()
        let usesThreshold = method.usesThresholdMap
        let grain = min(max(amount, 0), 1)
        var output = [UInt8](repeating: 0, count: width * height * 4)

        // Error rides a rolling three-row buffer: no kernel reaches further than
        // two rows down, and a finished row is cleared so it can serve as row+3.
        var error = [SIMD3<Double>](repeating: .zero, count: 3 * width)
        func slot(_ y: Int, _ x: Int) -> Int { (y % 3) * width + x }

        for y in 0..<height {
            // Serpentine: every other row runs right to left, and the kernel's
            // horizontal offsets mirror with it.
            let direction = (serpentine && !kernel.isEmpty && y % 2 == 1) ? -1 : 1
            for step in 0..<width {
                let x = direction == 1 ? step : width - 1 - step

                let color = image[x, y]
                let target = SIMD3(Color.srgbToLinear(color.red),
                                   Color.srgbToLinear(color.green),
                                   Color.srgbToLinear(color.blue))

                // Carried error is never clamped away (that would lose the light
                // it represents and shift the tones), only bounded against a
                // runaway on a pathological palette.
                var value = target + error[slot(y, x)]
                value = value.clamped(lowerBound: SIMD3(repeating: -1),
                                      upperBound: SIMD3(repeating: 2))

                let chosen: Choice
                if usesThreshold {
                    chosen = quantizer.mix(value, threshold: thresholdAt(x, y) * grain)
                } else if kernel.isEmpty {
                    chosen = quantizer.perceptualNearest(value)   // .none
                } else {
                    chosen = quantizer.linearNearest(value)
                }

                if !kernel.isEmpty {
                    let residual = value - chosen.linear
                    for tap in kernel {
                        let tx = x + direction * tap.dx
                        let ty = y + tap.dy
                        guard tx >= 0, tx < width, ty < height else { continue }
                        error[slot(ty, tx)] += residual * tap.weight
                    }
                }

                let alpha = color.alpha
                let i = (y * width + x) * 4
                output[i]     = premultipliedByte(chosen.srgb.x, alpha)
                output[i + 1] = premultipliedByte(chosen.srgb.y, alpha)
                output[i + 2] = premultipliedByte(chosen.srgb.z, alpha)
                output[i + 3] = UInt8((min(max(alpha, 0), 1) * 255).rounded())
            }
            for x in 0..<width { error[slot(y, x)] = .zero }
        }

        return Image(width: width, height: height, premultipliedRGBA: output) ?? image
    }

    private static func premultipliedByte(_ component: Double, _ alpha: Double) -> UInt8 {
        let v = min(max(component, 0), 1) * min(max(alpha, 0), 1)
        return UInt8((v * 255).rounded())
    }
}

// MARK: - Quantizers

/// Snaps to entries of a palette.
private struct PaletteQuantizer: Quantizing {
    private let linear: [SIMD3<Double>]
    private let srgb: [SIMD3<Double>]
    private let lab: [OKLab]

    init(_ palette: Palette) {
        let colors = palette.colors
        srgb = colors.map { SIMD3($0.red, $0.green, $0.blue) }
        linear = colors.map {
            SIMD3(Color.srgbToLinear($0.red),
                  Color.srgbToLinear($0.green),
                  Color.srgbToLinear($0.blue))
        }
        lab = colors.map { OKLab($0) }
    }

    func perceptualNearest(_ value: SIMD3<Double>) -> Choice {
        choice(at: perceptualIndex(to: value, skipping: -1))
    }

    func linearNearest(_ value: SIMD3<Double>) -> Choice {
        choice(at: linearIndex(to: value))
    }

    /// The near color is the one that looks closest. The far color is the one
    /// that looks closest to the point just *past* `value` on the same ray, so
    /// the two straddle the pixel. `fraction` is then how far along that segment
    /// the pixel's linear light actually sits, and choosing the far color exactly
    /// that often is what reproduces the original tone once the dots blur: over a
    /// flat field the threshold sweeps uniformly, so the far color wins a
    /// `fraction` share of the pixels and the average lands back on `value`.
    func mix(_ value: SIMD3<Double>, threshold: Double) -> Choice {
        let nearIndex = perceptualIndex(to: value, skipping: -1)
        let near = linear[nearIndex]

        // Reflect past the pixel, away from the near color, and look there.
        let beyond = value + (value - near)
        let farIndex = perceptualIndex(to: beyond, skipping: nearIndex)
        guard farIndex >= 0 else { return choice(at: nearIndex) }
        let far = linear[farIndex]

        let axis = far - near
        let lengthSquared = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z
        guard lengthSquared > 1e-12 else { return choice(at: nearIndex) }
        let offset = value - near
        let projection = offset.x * axis.x + offset.y * axis.y + offset.z * axis.z
        let fraction = min(max(projection / lengthSquared, 0), 1)

        return choice(at: (threshold + 0.5) < fraction ? farIndex : nearIndex)
    }

    private func choice(at index: Int) -> Choice {
        Choice(linear: linear[index], srgb: srgb[index])
    }

    /// Index of the perceptually closest entry, optionally skipping one.
    /// Returns `-1` when every entry was skipped (a one-color palette).
    private func perceptualIndex(to value: SIMD3<Double>, skipping excluded: Int) -> Int {
        let probe = OKLab(linearRed: value.x, green: value.y, blue: value.z)
        var bestIndex = -1
        var bestDistance = Double.greatestFiniteMagnitude
        for i in lab.indices where i != excluded {
            let dl = lab[i].l - probe.l
            let da = lab[i].a - probe.a
            let db = lab[i].b - probe.b
            let d = dl * dl + da * da + db * db
            if d < bestDistance { bestDistance = d; bestIndex = i }
        }
        return bestIndex
    }

    private func linearIndex(to value: SIMD3<Double>) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for i in linear.indices {
            let d = linear[i] - value
            let dd = d.x * d.x + d.y * d.y + d.z * d.z
            if dd < bestDistance { bestDistance = dd; bestIndex = i }
        }
        return bestIndex
    }
}

/// Snaps each channel to one of `levels` steps, evenly spaced in sRGB (the way
/// an 8-bit output ramp is), while measuring tone in linear light.
private struct LevelQuantizer: Quantizing {
    private let srgbSteps: [Double]
    private let linearSteps: [Double]

    init(levels: Int) {
        srgbSteps = (0..<levels).map { Double($0) / Double(levels - 1) }
        linearSteps = srgbSteps.map { Color.srgbToLinear($0) }
    }

    /// The steps are evenly spaced in sRGB, which is roughly perceptual for a
    /// gray ramp, so rounding there is the plain posterize a reader expects.
    func perceptualNearest(_ value: SIMD3<Double>) -> Choice {
        build(from: value) { channel in
            let encoded = Color.linearToSrgb(min(max(channel, 0), 1))
            var bestIndex = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for i in srgbSteps.indices {
                let d = abs(srgbSteps[i] - encoded)
                if d < bestDistance { bestDistance = d; bestIndex = i }
            }
            return bestIndex
        }
    }

    func linearNearest(_ value: SIMD3<Double>) -> Choice {
        build(from: value) { channel in
            var bestIndex = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for i in linearSteps.indices {
                let d = abs(linearSteps[i] - channel)
                if d < bestDistance { bestDistance = d; bestIndex = i }
            }
            return bestIndex
        }
    }

    /// The steps are evenly spaced in sRGB, so in linear light the gap around a
    /// value depends on where that value sits. Taking the fraction across the
    /// *linear* gap is what makes an ordered dither hold its tone across the
    /// whole ramp instead of going muddy in the shadows.
    func mix(_ value: SIMD3<Double>, threshold: Double) -> Choice {
        build(from: value) { channel in
            var lower = 0
            var upper = linearSteps.count - 1
            for i in linearSteps.indices {
                if linearSteps[i] <= channel { lower = i }
                if linearSteps[i] >= channel { upper = i; break }
            }
            let gap = linearSteps[upper] - linearSteps[lower]
            guard gap > 1e-12 else { return lower }
            let fraction = (channel - linearSteps[lower]) / gap
            return (threshold + 0.5) < fraction ? upper : lower
        }
    }

    private func build(from value: SIMD3<Double>, _ pick: (Double) -> Int) -> Choice {
        var linear = SIMD3<Double>()
        var srgb = SIMD3<Double>()
        for c in 0..<3 {
            let i = pick(value[c])
            linear[c] = linearSteps[i]
            srgb[c] = srgbSteps[i]
        }
        return Choice(linear: linear, srgb: srgb)
    }
}

// MARK: - Bayer matrix

/// The ordered-dither threshold matrix, built by the standard recurrence:
/// each level quadruples the previous matrix and offsets its four quadrants by
/// `0, 2, 3, 1`.
struct BayerMatrix: Sendable {
    let size: Int
    let values: [Int]

    /// Cached matrices for the sizes `ordered(size:)` accepts.
    private static let cache: [Int: BayerMatrix] = {
        var built: [Int: BayerMatrix] = [:]
        for size in [2, 4, 8, 16] { built[size] = BayerMatrix(size: size) }
        return built
    }()

    /// The matrix for `size`, rounded down to a power of two in `2...16`.
    static func shared(size: Int) -> BayerMatrix {
        var n = 2
        for candidate in [2, 4, 8, 16] where candidate <= size { n = candidate }
        return cache[n]!
    }

    init(size n: Int) {
        size = n
        var matrix = [0]
        var side = 1
        while side < n {
            let wide = side * 2
            // Quadrant offsets, in reading order: top-left, top-right,
            // bottom-left, bottom-right.
            let offsets = [0, 2, 3, 1]
            var next = [Int](repeating: 0, count: wide * wide)
            for y in 0..<wide {
                for x in 0..<wide {
                    let quadrant = (y >= side ? 2 : 0) + (x >= side ? 1 : 0)
                    next[y * wide + x] = 4 * matrix[(y % side) * side + (x % side)]
                        + offsets[quadrant]
                }
            }
            matrix = next
            side = wide
        }
        values = matrix
    }

    /// The matrix entry at `x, y` as an offset in `-0.5..<0.5`.
    ///
    /// The half-step and the recentering both matter: thresholding directly
    /// against `entry / n^2` biases the whole image lighter (a nearly black area
    /// lifts to a quarter gray at the smallest matrix size). Centering the offset
    /// and adding it *before* quantizing, rather than comparing against it,
    /// leaves the average tone where it started.
    func threshold(x: Int, y: Int) -> Double {
        let entry = values[(y % size) * size + (x % size)]
        return (Double(entry) + 0.5) / Double(size * size) - 0.5
    }
}

// MARK: - Blue noise

/// A 64x64 blue-noise threshold tile, generated once by the void-and-cluster
/// method (Ulichney, 1993) and reused for every dither.
///
/// Blue noise is noise with its low frequencies removed: the dots land evenly,
/// with no clumps and no bare patches, which is what lets it break up banding
/// without laying down a visible pattern of its own. Generating it is the
/// expensive part, and it is generated rather than bundled: the recipe is short,
/// the result is exact, and nothing has to ship as an asset.
enum BlueNoiseTile {
    static let size = 64

    /// Rank of each cell, a permutation of `0..<size*size`. The rank is the order
    /// in which cells switch on as a threshold rises, so reading it as a
    /// threshold gives an evenly spread pattern at every level.
    static let ranks: [Int] = generate()

    /// The tile entry at `x, y` as an offset in `-0.5..<0.5`, wrapping seamlessly.
    static func threshold(x: Int, y: Int) -> Double {
        let n = size
        let rank = ranks[(y % n) * n + (x % n)]
        return (Double(rank) + 0.5) / Double(n * n) - 0.5
    }

    /// Every step of void-and-cluster scans the whole tile for a global extreme,
    /// so the work is inherently quadratic in the cell count. The scans run over
    /// unsafe buffers because a debug build's bounds checks otherwise dominate
    /// them, and this runs on the first `.blueNoise` dither a process performs.
    private static func generate() -> [Int] {
        let n = size
        let total = n * n
        let sigma = 1.5
        let radius = 8   // e^(-64 / 4.5) is under a millionth: the tail is noise

        // A gaussian splat, precomputed over the offsets it reaches.
        let span = 2 * radius + 1
        var splat = [Double](repeating: 0, count: span * span)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let d2 = Double(dx * dx + dy * dy)
                splat[(dy + radius) * span + (dx + radius)] = exp(-d2 / (2 * sigma * sigma))
            }
        }

        let pattern = UnsafeMutablePointer<Bool>.allocate(capacity: total)
        let energy = UnsafeMutablePointer<Double>.allocate(capacity: total)
        let work = UnsafeMutablePointer<Bool>.allocate(capacity: total)
        let workEnergy = UnsafeMutablePointer<Double>.allocate(capacity: total)
        defer {
            pattern.deallocate(); energy.deallocate()
            work.deallocate(); workEnergy.deallocate()
        }
        pattern.initialize(repeating: false, count: total)
        energy.initialize(repeating: 0, count: total)
        work.initialize(repeating: false, count: total)
        workEnergy.initialize(repeating: 0, count: total)

        var ranks = [Int](repeating: 0, count: total)

        splat.withUnsafeBufferPointer { splat in
            /// Add (or subtract) one cell's gaussian contribution, wrapping on the
            /// torus, which is what makes the finished tile repeat without a seam.
            func stamp(_ index: Int, _ sign: Double, _ energy: UnsafeMutablePointer<Double>) {
                let py = index / n, px = index % n
                for dy in -radius...radius {
                    let y = ((py + dy) % n + n) % n
                    for dx in -radius...radius {
                        let x = ((px + dx) % n + n) % n
                        energy[y * n + x] += sign * splat[(dy + radius) * span + (dx + radius)]
                    }
                }
            }

            /// The cell of the tightest cluster: the filled cell with the most
            /// filled neighbours. Ties go to the lowest index, so the tile is
            /// deterministic.
            func tightestCluster(_ pattern: UnsafeMutablePointer<Bool>,
                                 _ energy: UnsafeMutablePointer<Double>) -> Int {
                var best = -1
                var bestEnergy = -Double.greatestFiniteMagnitude
                for i in 0..<total where pattern[i] {
                    if energy[i] > bestEnergy { bestEnergy = energy[i]; best = i }
                }
                return best
            }

            /// The cell of the largest void: the empty cell with the fewest
            /// filled neighbours.
            ///
            /// Past the halfway point the roles invert and the algorithm wants
            /// the tightest cluster of *empty* cells instead. It needs no
            /// separate pass: every cell's empty-energy is the constant total
            /// minus its filled-energy (the splat is the same everywhere on the
            /// torus), so the tightest cluster of empty cells is exactly the
            /// largest void.
            func largestVoid(_ pattern: UnsafeMutablePointer<Bool>,
                             _ energy: UnsafeMutablePointer<Double>) -> Int {
                var best = -1
                var bestEnergy = Double.greatestFiniteMagnitude
                for i in 0..<total where !pattern[i] {
                    if energy[i] < bestEnergy { bestEnergy = energy[i]; best = i }
                }
                return best
            }

            // Phase 0: scatter a tenth of the cells, then relax them until
            // removing the tightest cluster reopens the largest void in the
            // same place.
            let seeded = max(1, total / 10)
            var rng = SplitMix64(seed: 0x9E37_79B9_7F4A_7C15)
            var placed = 0
            while placed < seeded {
                let i = Int(rng.next() % UInt64(total))
                if !pattern[i] {
                    pattern[i] = true
                    stamp(i, 1, energy)
                    placed += 1
                }
            }
            for _ in 0..<(total * 4) {
                let cluster = tightestCluster(pattern, energy)
                pattern[cluster] = false
                stamp(cluster, -1, energy)

                let void = largestVoid(pattern, energy)
                if void == cluster {
                    pattern[cluster] = true
                    stamp(cluster, 1, energy)
                    break
                }
                pattern[void] = true
                stamp(void, 1, energy)
            }

            // Phase 1: peel the seeded cells off, tightest cluster first. Each
            // takes the rank of however many are left, so the sparsest rank low.
            work.update(from: pattern, count: total)
            workEnergy.update(from: energy, count: total)
            var ones = seeded
            while ones > 0 {
                let cluster = tightestCluster(work, workEnergy)
                work[cluster] = false
                stamp(cluster, -1, workEnergy)
                ones -= 1
                ranks[cluster] = ones
            }

            // Phases 2 and 3: fill from the seeded pattern back up to full,
            // always into the largest void (see the note on `largestVoid` for
            // why the halfway inversion collapses into this one loop).
            work.update(from: pattern, count: total)
            workEnergy.update(from: energy, count: total)
            ones = seeded
            while ones < total {
                let void = largestVoid(work, workEnergy)
                work[void] = true
                stamp(void, 1, workEnergy)
                ranks[void] = ones
                ones += 1
            }
        }

        return ranks
    }
}
