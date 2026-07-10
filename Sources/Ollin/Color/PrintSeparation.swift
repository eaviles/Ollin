import Foundation

// Print separations: split an image into per-ink grayscale masters for
// risograph and screen printing, where each pass lays down one translucent
// spot ink and the colors mix on the paper.
//
// The physical model is the classic one for translucent ink over paper. Solid
// ink on white stock shows the ink's own color, so the ink acts as a filter:
// its transmittance is the ink color in linear light. Partial coverage is a
// halftone, a fraction of the area inked, so a layer's expected reflectance
// mixes linearly between "no ink" and "inked" in linear light, and layers
// screened at different angles multiply independently:
//
//     R  =  paper * mix(1, T1, a1) * mix(1, T2, a2) * ...
//
// where T_i is ink i's transmittance and a_i its coverage. Separating a color
// inverts that: find the coverages whose predicted overprint looks closest to
// the target. As everywhere in this module, the two color spaces split the
// job: light mixes in *linear* RGB, and "looks closest" is judged in OKLab.
// The search runs once per distinct input color (memoized), seeded by a
// nearest neighbor over a precomputed coverage lattice and refined by
// coordinate descent, so flat generative art separates in milliseconds and a
// photograph in seconds.
//
// The model's limits are physical ones: inks only darken (nothing lighter
// than the paper is reachable, and an opaque white ink on dark stock is
// outside the model), and the community-measured ink colors are screen
// approximations. The printed proof is the ground truth.

/// An image split into per-ink grayscale masters for spot-color printing,
/// plus an honest on-screen preview of the overprint.
///
/// Build one with `Image.separated(into:paper:)`, screen the masters with
/// `dithered(_:)` or `halftoned(pitch:angles:)` if the press wants 1-bit
/// films, then export with `OllinApp.exportSeparations` (or the
/// `--export-separations` flag), which writes one grayscale PNG per ink plus
/// a registration-marked composite preview.
///
/// ```swift
/// let sep = artwork.separated(into: [.fluorescentPink, .blue, .yellow])
/// drawImage(sep.preview())              // how the print will read
/// drawImage(sep.layers[0].master)       // pink's master: black = full ink
/// ```
public struct PrintSeparation {
    /// One ink's printing master.
    public struct Layer {
        /// The ink this master prints in.
        public let ink: Ink
        /// The grayscale master: black is full ink, white is bare paper.
        /// The byte value is the ink fraction directly (`0` = 100% ink),
        /// not a gamma-encoded tone.
        public let master: Image

        /// The mean ink coverage over the whole master, `0...1`. Heavy
        /// layers (roughly above a third) are worth checking against the
        /// press's appetite before printing.
        public var averageInk: Double {
            guard let bytes = master.premultipliedPixels() else { return 0 }
            var sum = 0
            var i = 0
            while i < bytes.count {
                sum += 255 - Int(bytes[i])
                i += 4
            }
            return Double(sum) / (255 * Double(master.width * master.height))
        }
    }

    /// The per-ink masters, in the order the inks were given (the intended
    /// print order).
    public let layers: [Layer]
    /// The stock the preview composites over.
    public let paper: Color
    public let width: Int
    public let height: Int

    /// Simulate the finished print: every master's coverage applied as its
    /// ink's transmittance over the paper, mixed in linear light. Run on the
    /// screened masters (after `dithered(_:)` or `halftoned(pitch:angles:)`)
    /// the preview shows the actual dots.
    public func preview() -> Image {
        let blank = Image(width: max(1, width), height: max(1, height), color: paper)
        guard !layers.isEmpty else { return blank }
        let planes = layers.compactMap { $0.master.premultipliedPixels() }
        guard planes.count == layers.count else { return blank }

        let model = OverprintModel(paper: paper, inks: layers.map(\.ink))
        let count = width * height
        var out = [UInt8](repeating: 255, count: count * 4)
        var coverages = [Double](repeating: 0, count: layers.count)
        for p in 0..<count {
            let i = p * 4
            for l in planes.indices {
                coverages[l] = 1 - Double(planes[l][i]) / 255
            }
            let linear = model.predict(coverages)
            out[i]     = UInt8((Color.linearToSrgb(min(max(linear.x, 0), 1)) * 255).rounded())
            out[i + 1] = UInt8((Color.linearToSrgb(min(max(linear.y, 0), 1)) * 255).rounded())
            out[i + 2] = UInt8((Color.linearToSrgb(min(max(linear.z, 0), 1)) * 255).rounded())
        }
        return Image(width: width, height: height, premultipliedRGBA: out) ?? blank
    }

    /// The masters reduced to pure black and white by dithering, the grain
    /// that prints as crisp single-drop dots. Coverage is an area fraction,
    /// which is exactly the quantity a dither's error diffusion conserves, so
    /// the screened master holds each tone: a 30% gray becomes 30% ink dots.
    /// `serpentine` reverses every other row of an error-diffusion scan (see
    /// `Image.dithered`); the threshold maps ignore it. Coverage below 2% (or
    /// above 98%) snaps to bare paper (or solid ink) first: a press cannot
    /// hold a smaller dot, and without the cutoff the sub-1% coverages left
    /// by 8-bit rounding screen into stray specks across clean paper.
    public func dithered(_ method: Dither = .blueNoise, serpentine: Bool = true) -> PrintSeparation {
        screened { plane in
            Self.ditherPlane(&plane, width: width, height: height,
                             method: method, serpentine: serpentine)
        }
    }

    /// The masters reduced to pure black and white by classic clustered-dot
    /// halftone screens: round dots on a grid `pitch` pixels apart, each
    /// layer's grid rotated to its own angle so the overprint makes the
    /// traditional rosette instead of moire.
    ///
    /// `angles` is one angle per layer, in radians; by default the darkest
    /// ink takes the least visible 45-degree screen and the others fan out
    /// over the conventional offsets (15, 75, 0, then 30 and 60 degrees).
    /// The dot threshold is area-exact, so tone is preserved: a 30% gray
    /// becomes dots covering 30% of the cell. The same 2% highlight/shadow
    /// cutoff as `dithered(_:serpentine:)` applies.
    public func halftoned(pitch: Double = 8, angles: [Double]? = nil) -> PrintSeparation {
        let cell = max(2, pitch)
        let assigned = angles ?? Self.screenAngles(for: layers.map(\.ink))
        var index = 0
        return screened { plane in
            let angle = index < assigned.count ? assigned[index] : Double(index) * .pi / 7
            index += 1
            Self.halftonePlane(&plane, width: width, height: height, pitch: cell, angle: angle)
        }
    }

    /// Rebuild each layer by running `transform` over its coverage plane
    /// (`0...1`, ink fraction per pixel, row-major).
    private func screened(_ transform: (inout [Double]) -> Void) -> PrintSeparation {
        let screenedLayers = layers.map { layer -> Layer in
            guard let bytes = layer.master.premultipliedPixels() else { return layer }
            let count = width * height
            var plane = [Double](repeating: 0, count: count)
            for p in 0..<count {
                plane[p] = 1 - Double(bytes[p * 4]) / 255
            }
            var transformed = plane
            transform(&transformed)
            var out = [UInt8](repeating: 255, count: count * 4)
            for p in 0..<count {
                let byte = UInt8(((1 - min(max(transformed[p], 0), 1)) * 255).rounded())
                out[p * 4] = byte
                out[p * 4 + 1] = byte
                out[p * 4 + 2] = byte
            }
            guard let master = Image(width: width, height: height, premultipliedRGBA: out) else {
                return layer
            }
            return Layer(ink: layer.ink, master: master)
        }
        return PrintSeparation(layers: screenedLayers, paper: paper, width: width, height: height)
    }

    /// The smallest dot a press holds: screened coverage below this prints as
    /// bare paper, and above its complement as solid ink. Without the cutoff,
    /// the sub-1% coverages left by 8-bit rounding (a 254-byte "white")
    /// screen into stray specks across clean paper.
    private static let minimumDot = 0.02

    /// One scalar dither pass over a coverage plane, quantizing to 0 or 1.
    /// Coverage is already the linear quantity (an area fraction), so the
    /// error diffuses in the plane's own units and a threshold map compares
    /// the fraction directly, the same tone rule as the image dither.
    private static func ditherPlane(_ plane: inout [Double], width: Int, height: Int,
                                    method: Dither, serpentine: Bool) {
        clampToPrintableDots(&plane)
        let kernel = method.diffusionKernel
        let thresholdAt = method.thresholdMap()
        let usesThreshold = method.usesThresholdMap

        if usesThreshold {
            for y in 0..<height {
                for x in 0..<width {
                    let p = y * width + x
                    plane[p] = (thresholdAt(x, y) + 0.5) < plane[p] ? 1 : 0
                }
            }
            return
        }

        var error = [Double](repeating: 0, count: 3 * width)
        func slot(_ y: Int, _ x: Int) -> Int { (y % 3) * width + x }
        for y in 0..<height {
            let direction = (serpentine && y % 2 == 1) ? -1 : 1
            for step in 0..<width {
                let x = direction == 1 ? step : width - 1 - step
                let p = y * width + x
                let value = min(max(plane[p] + error[slot(y, x)], -1), 2)
                let chosen: Double = value < 0.5 ? 0 : 1
                plane[p] = chosen
                let residual = value - chosen
                for tap in kernel {
                    let tx = x + direction * tap.dx
                    let ty = y + tap.dy
                    guard tx >= 0, tx < width, ty < height else { continue }
                    error[slot(ty, tx)] += residual * tap.weight
                }
            }
            for x in 0..<width { error[slot(y, x)] = .zero }
        }
    }

    /// One rotated round-dot screen over a coverage plane. Each pixel
    /// thresholds against the area a growing dot has covered by the time it
    /// reaches that spot in its cell, so measure{threshold < c} = c exactly
    /// and every tone survives the screen. Dots join into the classic
    /// checkered diamonds past half coverage as the disks overrun the cell.
    private static func halftonePlane(_ plane: inout [Double], width: Int, height: Int,
                                      pitch: Double, angle: Double) {
        clampToPrintableDots(&plane)
        let cosA = cos(angle), sinA = sin(angle)

        // Fraction of the cell a centered disk of radius rho (cell half-width
        // 1) has covered: a quarter circle until it meets the edges, then the
        // circle minus the four clipped segments, reaching 1 at the corners.
        func coveredArea(_ rho: Double) -> Double {
            if rho <= 0 { return 0 }
            if rho >= 2.0.squareRoot() { return 1 }
            let quarter = .pi * rho * rho / 4
            if rho <= 1 { return quarter }
            return quarter - rho * rho * acos(1 / rho) + (rho * rho - 1).squareRoot()
        }

        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let u = (px * cosA + py * sinA) / pitch
                let v = (-px * sinA + py * cosA) / pitch
                let s = 2 * (u - u.rounded(.down)) - 1
                let t = 2 * (v - v.rounded(.down)) - 1
                let threshold = coveredArea((s * s + t * t).squareRoot())
                let p = y * width + x
                plane[p] = plane[p] > threshold ? 1 : 0
            }
        }
    }

    private static func clampToPrintableDots(_ plane: inout [Double]) {
        for i in plane.indices {
            if plane[i] < minimumDot { plane[i] = 0 }
            else if plane[i] > 1 - minimumDot { plane[i] = 1 }
        }
    }

    /// The conventional screen angles, one per layer: the darkest ink takes
    /// 45 degrees (the least visible screen), the rest fan out over the
    /// offsets furthest from it and from each other.
    static func screenAngles(for inks: [Ink]) -> [Double] {
        let conventional: [Double] = [45, 15, 75, 0, 30, 60].map { $0 * .pi / 180 }
        // Rank by luminance: index of each ink in dark-to-light order.
        let order = inks.indices.sorted { inks[$0].color.luminance < inks[$1].color.luminance }
        var angles = [Double](repeating: 0, count: inks.count)
        for (rank, index) in order.enumerated() {
            angles[index] = rank < conventional.count
                ? conventional[rank]
                : Double(rank) * .pi / Double(max(inks.count, 1))
        }
        return angles
    }
}

// MARK: - Separating an image

public extension Image {
    /// Split this image into one grayscale printing master per ink: for every
    /// pixel, the coverages whose overprint of `inks` on `paper` looks
    /// closest to the pixel (mixed in linear light, judged in OKLab).
    ///
    /// Drawing *with* the ink colors separates exactly (a fluorescent-pink
    /// shape comes back as solid pink master); everything else lands on the
    /// nearest reachable mix, so overlaps, gradients, and photographs all
    /// separate into the same few drums. Colors the inks cannot reach (anything
    /// lighter than the paper, or outside the inks' gamut) settle for the
    /// closest overprint. A translucent pixel is composited over the paper
    /// first.
    ///
    /// This is per-pixel CPU work, memoized per distinct color: call it in
    /// `setup()` (or export offline), not once per frame. A GPU-backed image
    /// has no CPU pixels and returns an empty separation (`snapshot()` first);
    /// an empty ink list returns an empty separation too. Deterministic: the
    /// same image, inks, and paper always give the same masters, so a
    /// separation is safe to snapshot and export.
    func separated(into inks: [Ink], paper: Color = .white) -> PrintSeparation {
        guard hasCPUPixels, !inks.isEmpty, let input = premultipliedPixels() else {
            return PrintSeparation(layers: [], paper: paper, width: width, height: height)
        }
        var inkSet = inks
        if inkSet.count > 8 {
            FileHandle.standardError.write(Data(
                "Ollin: separating into the first 8 of \(inkSet.count) inks (the practical press limit)\n".utf8))
            inkSet = Array(inkSet.prefix(8))
        }

        let model = OverprintModel(paper: paper, inks: inkSet)
        let solver = SeparationSolver(model: model)
        let count = width * height
        var planes = [[UInt8]](repeating: [UInt8](repeating: 255, count: count * 4),
                               count: inkSet.count)

        for p in 0..<count {
            let i = p * 4
            let key = UInt32(input[i]) << 24 | UInt32(input[i + 1]) << 16
                    | UInt32(input[i + 2]) << 8 | UInt32(input[i + 3])
            let bytes = solver.masterBytes(for: key)
            for l in bytes.indices {
                planes[l][i] = bytes[l]
                planes[l][i + 1] = bytes[l]
                planes[l][i + 2] = bytes[l]
            }
        }

        let layers = inkSet.indices.compactMap { l -> PrintSeparation.Layer? in
            guard let master = Image(width: width, height: height,
                                     premultipliedRGBA: planes[l]) else { return nil }
            return PrintSeparation.Layer(ink: inkSet[l], master: master)
        }
        return PrintSeparation(layers: layers, paper: paper, width: width, height: height)
    }
}

// MARK: - The overprint model

/// The forward model: paper reflectance times each ink's coverage-mixed
/// transmittance, all in linear light.
struct OverprintModel {
    let paperLinear: SIMD3<Double>
    /// Each ink's transmittance at full coverage: its color in linear light
    /// (solid ink on white stock shows the ink color, so the filter it applies
    /// is the color itself).
    let transmittance: [SIMD3<Double>]

    init(paper: Color, inks: [Ink]) {
        paperLinear = SIMD3(Color.srgbToLinear(paper.red),
                            Color.srgbToLinear(paper.green),
                            Color.srgbToLinear(paper.blue))
        transmittance = inks.map {
            SIMD3(Color.srgbToLinear($0.color.red),
                  Color.srgbToLinear($0.color.green),
                  Color.srgbToLinear($0.color.blue))
        }
    }

    /// The overprint's reflectance in linear light for one set of coverages.
    func predict(_ coverages: [Double]) -> SIMD3<Double> {
        var r = paperLinear
        for i in transmittance.indices {
            r *= SIMD3(repeating: 1) + coverages[i] * (transmittance[i] - SIMD3(repeating: 1))
        }
        return r
    }
}

// MARK: - The per-color search

/// Finds the coverages whose predicted overprint looks closest to a target
/// color, memoized per distinct input color. A reference type so the cache
/// survives behind the value-typed call; each `separated` call builds its own
/// solver, so the cache is never shared across threads.
private final class SeparationSolver {
    private let model: OverprintModel
    /// Master bytes per ink for an input pixel, keyed on its RGBA bytes.
    private var plans: [UInt32: [UInt8]] = [:]
    /// Beyond this many distinct colors plans are computed uncached: the
    /// search stays correct, the memory stays bounded.
    private static let capacity = 1 << 18

    /// The coverage lattice: every combination of a few levels per ink,
    /// predicted once, that seeds the refinement near the right answer (the
    /// objective has local minima; two inks can fake a third's hue).
    private let latticeCoverages: [[Double]]
    private let latticeLab: [SIMD3<Double>]

    init(model: OverprintModel) {
        self.model = model
        let n = model.transmittance.count
        // Levels per ink sized so the lattice stays a few thousand points.
        let levels = [64, 16, 12, 8, 6, 5, 4, 4][min(n, 8) - 1]
        var coverages: [[Double]] = []
        var assignment = [Double](repeating: 0, count: n)
        func fill(_ ink: Int) {
            if ink == n {
                coverages.append(assignment)
                return
            }
            for step in 0..<levels {
                assignment[ink] = Double(step) / Double(levels - 1)
                fill(ink + 1)
            }
        }
        fill(0)
        latticeCoverages = coverages
        latticeLab = coverages.map { Self.lab(model.predict($0)) }
    }

    private static func lab(_ linear: SIMD3<Double>) -> SIMD3<Double> {
        let lab = OKLab(linearRed: linear.x, green: linear.y, blue: linear.z)
        return SIMD3(lab.l, lab.a, lab.b)
    }

    /// The master byte per ink (255 = no ink, 0 = full) for one input pixel.
    func masterBytes(for key: UInt32) -> [UInt8] {
        if let cached = plans[key] { return cached }

        // Un-premultiply to straight sRGB, linearize, and composite over the
        // paper: what physically shows through a translucent pixel is stock.
        let alphaByte = key & 0xFF
        let alpha = Double(alphaByte) / 255
        var straight = SIMD3<Double>.zero
        if alphaByte > 0 {
            straight = SIMD3(min(1, Double((key >> 24) & 0xFF) / 255 / alpha),
                             min(1, Double((key >> 16) & 0xFF) / 255 / alpha),
                             min(1, Double((key >> 8) & 0xFF) / 255 / alpha))
        }
        let linear = SIMD3(Color.srgbToLinear(straight.x),
                           Color.srgbToLinear(straight.y),
                           Color.srgbToLinear(straight.z))
        let target = model.paperLinear + alpha * (linear - model.paperLinear)

        let coverages = separate(targetLinear: target)
        let bytes = coverages.map { UInt8(((1 - min(max($0, 0), 1)) * 255).rounded()) }
        if plans.count < Self.capacity { plans[key] = bytes }
        return bytes
    }

    /// Nearest lattice point in OKLab, then cyclic coordinate descent: each
    /// ink's coverage in turn is refined by golden-section search over `0...1`
    /// with the others held, which is cheap because the model is linear in
    /// any single coverage.
    private func separate(targetLinear: SIMD3<Double>) -> [Double] {
        let probe = Self.lab(targetLinear)

        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for i in latticeLab.indices {
            let d = latticeLab[i] - probe
            let dd = d.x * d.x + d.y * d.y + d.z * d.z
            if dd < bestDistance { bestDistance = dd; bestIndex = i }
        }
        var coverages = latticeCoverages[bestIndex]

        func score(_ linear: SIMD3<Double>) -> Double {
            let d = Self.lab(linear) - probe
            return d.x * d.x + d.y * d.y + d.z * d.z
        }

        let phi = (5.0.squareRoot() - 1) / 2
        for _ in 0..<3 {
            for ink in coverages.indices {
                // Everything but this ink, factored out once: the prediction
                // along this coordinate is base * mix(1, T, a).
                var base = model.paperLinear
                for other in coverages.indices where other != ink {
                    base *= SIMD3(repeating: 1)
                        + coverages[other] * (model.transmittance[other] - SIMD3(repeating: 1))
                }
                let axis = model.transmittance[ink] - SIMD3(repeating: 1)
                func at(_ a: Double) -> Double {
                    score(base * (SIMD3(repeating: 1) + a * axis))
                }

                var lo = 0.0, hi = 1.0
                var x1 = hi - phi * (hi - lo), x2 = lo + phi * (hi - lo)
                var f1 = at(x1), f2 = at(x2)
                for _ in 0..<28 {
                    if f1 < f2 {
                        hi = x2; x2 = x1; f2 = f1
                        x1 = hi - phi * (hi - lo); f1 = at(x1)
                    } else {
                        lo = x1; x1 = x2; f1 = f2
                        x2 = lo + phi * (hi - lo); f2 = at(x2)
                    }
                }
                var best = (x1 + x2) / 2
                var bestScore = at(best)
                // The exact endpoints matter: solid ink and bare paper are
                // the common answers, and the golden section brackets them
                // without ever landing exactly on them.
                for endpoint in [0.0, 1.0] where at(endpoint) <= bestScore {
                    best = endpoint
                    bestScore = at(endpoint)
                }
                coverages[ink] = best
            }
        }
        return coverages
    }
}
