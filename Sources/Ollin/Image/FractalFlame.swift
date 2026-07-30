import Foundation

/// Fractal flames: the chaos game grown up. Each transform is an affine map
/// followed by a weighted blend of nonlinear "variations" (sinusoidal folds,
/// spherical inversions, swirls), the orbit carries a color coordinate that
/// remembers which transforms shaped it (structural coloring), and the
/// render accumulates a density histogram displayed through a logarithm, so
/// filaments, veils, and cores all stay visible at once.
///
/// ```swift
/// var rng = SplitMix64(seed: 12)
/// let picture = FractalFlame.random(using: &rng)
///     .render(width: 540, height: 540, quality: 80, using: &rng)
/// drawImage(picture, in: canvasRectangle)
/// ```
///
/// Rendering is CPU work: `quality` is chaos-game samples per output pixel,
/// so cost scales with both. A few dozen per pixel previews; hundreds make a
/// clean still. Deterministic given (flame, size, quality, seed).
public struct FractalFlame: Sendable {
    /// The nonlinear plane-warps a transform can blend. Formulas follow the
    /// standard catalog, including its polar convention: theta is measured
    /// from the y axis (`atan2(x, y)`), which is what gives `disc`, `heart`,
    /// and friends their canonical orientation.
    public enum Variation: Sendable, Hashable {
        case linear, sinusoidal, spherical, swirl, horseshoe, polar,
             handkerchief, heart, disc, spiral, hyperbolic, diamond, ex, julia
    }

    /// One entry of a transform's variation blend: the warp and its weight in
    /// the sum (weights need not add to 1).
    public struct Blend: Sendable {
        public var variation: Variation
        public var amount: Double

        public init(_ variation: Variation, _ amount: Double = 1) {
            self.variation = variation
            self.amount = amount
        }
    }

    /// One flame transform: a pre-affine map (its `weight` is the pick
    /// probability), a variation blend applied to the affine's output, an
    /// optional post-affine map on the blended sum, and a palette index the
    /// orbit's color coordinate averages toward.
    public struct Transform: Sendable {
        public var map: IFS.Map
        public var variations: [Blend]
        public var post: IFS.Map?
        public var color: Double

        public init(map: IFS.Map,
                    variations: [Blend] = [Blend(.linear)],
                    post: IFS.Map? = nil,
                    color: Double = 0) {
            self.map = map
            self.variations = variations
            self.post = post
            self.color = min(max(color, 0), 1)
        }
    }

    public var transforms: [Transform]
    /// The palette the color coordinate reads, as evenly spaced stops.
    public var colors: [Color]
    /// Display gamma; 2.2 is the classic default, up to 4 pulls faint
    /// structure out of the veils (and wants more `quality` to stay clean).
    public var gamma: Double
    /// Where gamma is applied: `1` derives one scale factor from density and
    /// keeps colors saturated; `0` curves each channel independently, which
    /// washes strong gammas toward pastel.
    public var vibrancy: Double
    /// Linear multiplier on the log-scaled density before gamma.
    public var brightness: Double
    /// The camera window in flame space (the attractor of contractive maps
    /// lives around the bi-unit square, the default view).
    public var window: Rectangle

    public init(transforms: [Transform],
                colors: [Color] = [Color(hex: 0x0A0E24), Color(hex: 0x274690),
                                   Color(hex: 0xE4572E), Color(hex: 0xF3A712),
                                   Color(hex: 0xFFF8E1)],
                gamma: Double = 2.2,
                vibrancy: Double = 1,
                brightness: Double = 1,
                window: Rectangle = Rectangle(x: -1, y: -1, width: 2, height: 2)) {
        self.transforms = transforms
        self.colors = colors.isEmpty ? [.white] : colors
        self.gamma = max(0.1, gamma)
        self.vibrancy = min(max(vibrancy, 0), 1)
        self.brightness = max(0, brightness)
        self.window = window
    }

    /// A random flame in the spirit of the technique's own recipe: a few
    /// contractive affines (scale, rotation, offset), one nonlinear variation
    /// each, palette indices spread evenly. Some rolls are duds (the chaos
    /// game tolerates them); reroll the seed until one sings.
    public static func random<R: RandomNumberGenerator>(
        transformCount: Int = 4,
        variations pool: [Variation] = [.sinusoidal, .spherical, .swirl,
                                        .horseshoe, .disc, .spiral, .julia],
        using rng: inout R
    ) -> FractalFlame {
        let count = max(2, transformCount)
        let choices = pool.isEmpty ? [.linear] : pool
        var transforms: [Transform] = []
        for index in 0 ..< count {
            let scale = Double.random(in: 0.4 ... 0.8, using: &rng)
            let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
            let map = IFS.Map(cos(angle) * scale, -sin(angle) * scale,
                              sin(angle) * scale, cos(angle) * scale,
                              Double.random(in: -1 ... 1, using: &rng),
                              Double.random(in: -1 ... 1, using: &rng))
            let pick = Int.random(in: 0 ..< choices.count, using: &rng)
            transforms.append(Transform(
                map: map,
                variations: [Blend(choices[pick])],
                color: count > 1 ? Double(index) / Double(count - 1) : 0))
        }
        return FractalFlame(transforms: transforms)
    }

    // MARK: - Rendering

    /// Run the whole chaos game at once and develop the image. Convenience
    /// over `Renderer` for stills; a live sketch that wants the picture to
    /// refine on screen makes a `Renderer` and feeds it a slice of samples
    /// per frame.
    ///
    /// - Parameters:
    ///   - width, height: The output size in pixels.
    ///   - quality: Chaos-game samples per output pixel.
    ///   - supersample: Histogram buckets per output pixel side (2 sharpens
    ///     edges at 4x the memory; the sample budget stays the same).
    ///   - rng: Seeds the render's own stream; seed it for a reproducible
    ///     image.
    public func render<R: RandomNumberGenerator>(
        width: Int,
        height: Int,
        quality: Double = 60,
        supersample: Int = 1,
        using rng: inout R
    ) -> Image {
        let renderer = Renderer(self, width: width, height: height,
                                supersample: supersample,
                                seed: Int(truncatingIfNeeded: UInt64.random(in: .min ... .max,
                                                                            using: &rng)))
        renderer.accumulate(samples: Int(quality * Double(max(1, width)) * Double(max(1, height))))
        return renderer.image()
    }

    /// The incremental flame renderer: holds the density histogram and the
    /// orbit, takes chaos-game samples in slices, and develops the current
    /// state into an image on demand. The classic way to watch a flame
    /// resolve: accumulate a few hundred thousand samples each frame and
    /// redraw. Deterministic: the same (flame, size, seed) after the same
    /// total samples always develops the same image.
    public final class Renderer {
        public let flame: FractalFlame
        public let width: Int
        public let height: Int
        /// Total chaos-game samples taken so far.
        public private(set) var samples = 0

        private let ss: Int
        private let gridW: Int
        private let gridH: Int
        private var sumR: [Float]
        private var sumG: [Float]
        private var sumB: [Float]
        private var hits: [Float]
        private let strip: [Float]
        private let totalWeight: Double
        private var rng: SplitMix64
        private var x: Double
        private var y: Double
        private var c: Double
        private var fuseRemaining = 20

        public init(_ flame: FractalFlame,
                    width: Int,
                    height: Int,
                    supersample: Int = 1,
                    seed: Int = 1) {
            self.flame = flame
            self.width = max(1, width)
            self.height = max(1, height)
            ss = min(max(supersample, 1), 3)
            gridW = self.width * ss
            gridH = self.height * ss
            sumR = [Float](repeating: 0, count: gridW * gridH)
            sumG = [Float](repeating: 0, count: gridW * gridH)
            sumB = [Float](repeating: 0, count: gridW * gridH)
            hits = [Float](repeating: 0, count: gridW * gridH)
            strip = flame.paletteStrip()
            totalWeight = flame.transforms.reduce(0) { $0 + $1.map.weight }
            rng = SplitMix64(seed: UInt64(truncatingIfNeeded: seed))
            x = Double.random(in: -1 ... 1, using: &rng)
            y = Double.random(in: -1 ... 1, using: &rng)
            c = Double.random(in: 0 ... 1, using: &rng)
        }

        /// Take `count` more chaos-game samples into the histogram. The
        /// orbit carries over between calls, so slices compose exactly.
        public func accumulate(samples count: Int) {
            guard count > 0, totalWeight > 0, !flame.transforms.isEmpty,
                  flame.window.width > 0, flame.window.height > 0 else { return }
            let transforms = flame.transforms
            let window = flame.window
            let scaleX = Double(gridW) / window.width
            let scaleY = Double(gridH) / window.height
            let paletteCount = strip.count / 3
            var localX = x, localY = y, localC = c
            var localRng = rng
            var fuse = fuseRemaining
            var remaining = count

            strip.withUnsafeBufferPointer { palette in
                sumR.withUnsafeMutableBufferPointer { red in
                    sumG.withUnsafeMutableBufferPointer { green in
                        sumB.withUnsafeMutableBufferPointer { blue in
                            hits.withUnsafeMutableBufferPointer { counts in
                                while remaining > 0 {
                                    var roll = Double.random(in: 0 ..< totalWeight, using: &localRng)
                                    var index = transforms.count - 1
                                    for i in 0 ..< transforms.count {
                                        if roll < transforms[i].map.weight { index = i; break }
                                        roll -= transforms[i].map.weight
                                    }
                                    let chosen = transforms[index]

                                    let map = chosen.map
                                    let ax = map.a * localX + map.b * localY + map.e
                                    let ay = map.c * localX + map.d * localY + map.f
                                    var vx = 0.0, vy = 0.0
                                    for blend in chosen.variations {
                                        let warped = FractalFlame.applyVariation(
                                            blend.variation, ax, ay, using: &localRng)
                                        vx += blend.amount * warped.0
                                        vy += blend.amount * warped.1
                                    }
                                    if let post = chosen.post {
                                        let px = post.a * vx + post.b * vy + post.e
                                        let py = post.c * vx + post.d * vy + post.f
                                        vx = px; vy = py
                                    }
                                    localX = vx; localY = vy
                                    localC = (localC + chosen.color) / 2

                                    // A degenerate roll can fling the orbit to
                                    // infinity; restart it in the bi-unit square.
                                    if !localX.isFinite || !localY.isFinite {
                                        localX = Double.random(in: -1 ... 1, using: &localRng)
                                        localY = Double.random(in: -1 ... 1, using: &localRng)
                                        continue
                                    }
                                    if fuse > 0 { fuse -= 1; continue }
                                    remaining -= 1

                                    let px = Int((localX - window.x) * scaleX)
                                    let py = Int((localY - window.y) * scaleY)
                                    guard px >= 0, px < gridW, py >= 0, py < gridH else { continue }
                                    let slot = py * gridW + px
                                    let paletteIndex = min(Int(localC * Double(paletteCount)),
                                                           paletteCount - 1)
                                    red[slot] += palette[paletteIndex * 3]
                                    green[slot] += palette[paletteIndex * 3 + 1]
                                    blue[slot] += palette[paletteIndex * 3 + 2]
                                    counts[slot] += 1
                                }
                            }
                        }
                    }
                }
            }
            x = localX; y = localY; c = localC
            rng = localRng
            fuseRemaining = fuse
            samples += count
        }

        /// Develop the current histogram: one log factor per bucket derived
        /// from its hit count scales all three channels (logging channels
        /// independently would shift hues), buckets filter down to output
        /// pixels, and gamma lands at that final step, split by `vibrancy`
        /// between a shared density-derived factor and per-channel curves.
        public func image() -> Image {
            var maxHits: Float = 0
            for n in hits where n > maxHits { maxHits = n }
            guard maxHits > 0 else { return Image(width: width, height: height, color: .black) }
            let logMax = Double(log(maxHits + 1))

            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let invGamma = 1 / flame.gamma
            let vibrancy = flame.vibrancy
            let brightness = flame.brightness
            let boxScale = 1 / Double(ss * ss)

            for py in 0 ..< height {
                for px in 0 ..< width {
                    var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                    for sy in 0 ..< ss {
                        for sx in 0 ..< ss {
                            let slot = (py * ss + sy) * gridW + (px * ss + sx)
                            let n = Double(hits[slot])
                            guard n > 0 else { continue }
                            let scale = log(n + 1) / n / logMax * brightness
                            r += Double(sumR[slot]) * scale
                            g += Double(sumG[slot]) * scale
                            b += Double(sumB[slot]) * scale
                            a += log(n + 1) / logMax * brightness
                        }
                    }
                    r = min(r * boxScale, 1); g = min(g * boxScale, 1)
                    b = min(b * boxScale, 1); a = min(a * boxScale, 1)

                    let factor = a > 0 ? pow(a, invGamma - 1) : 0
                    func developChannel(_ value: Double) -> UInt8 {
                        let shared = value * factor
                        let independent = pow(value, invGamma)
                        let mixed = min(max(vibrancy * shared + (1 - vibrancy) * independent, 0), 1)
                        return UInt8((mixed * 255).rounded())
                    }
                    let i = (py * width + px) * 4
                    bytes[i] = developChannel(r)
                    bytes[i + 1] = developChannel(g)
                    bytes[i + 2] = developChannel(b)
                    bytes[i + 3] = 255
                }
            }
            return Image(width: width, height: height, premultipliedRGBA: bytes)
                ?? Image(width: width, height: height, color: .black)
        }
    }

    /// The palette stops resolved to a 256-entry strip of straight channel
    /// values, blended between adjacent stops.
    private func paletteStrip() -> [Float] {
        var strip = [Float](repeating: 0, count: 256 * 3)
        for i in 0 ..< 256 {
            let t = Double(i) / 255 * Double(colors.count - 1)
            let low = min(Int(t), colors.count - 1)
            let high = min(low + 1, colors.count - 1)
            let f = t - Double(low)
            let a = colors[low]
            let b = colors[high]
            let red = a.red + (b.red - a.red) * f
            let green = a.green + (b.green - a.green) * f
            let blue = a.blue + (b.blue - a.blue) * f
            strip[i * 3] = Float(red)
            strip[i * 3 + 1] = Float(green)
            strip[i * 3 + 2] = Float(blue)
        }
        return strip
    }

    // MARK: - Variation formulas

    /// Apply one variation to a point. `theta` is measured from the y axis
    /// (`atan2(x, y)`), the catalog's convention; swapping the arguments is
    /// the classic way to get every polar variation subtly wrong.
    static func applyVariation<R: RandomNumberGenerator>(
        _ variation: Variation,
        _ x: Double, _ y: Double,
        using rng: inout R
    ) -> (Double, Double) {
        switch variation {
        case .linear:
            return (x, y)
        case .sinusoidal:
            return (sin(x), sin(y))
        case .spherical:
            let r2 = max(x * x + y * y, 1e-12)
            return (x / r2, y / r2)
        case .swirl:
            let r2 = x * x + y * y
            return (x * sin(r2) - y * cos(r2), x * cos(r2) + y * sin(r2))
        case .horseshoe:
            let r = max((x * x + y * y).squareRoot(), 1e-9)
            return ((x - y) * (x + y) / r, 2 * x * y / r)
        case .polar:
            let r = (x * x + y * y).squareRoot()
            return (atan2(x, y) / .pi, r - 1)
        case .handkerchief:
            let r = (x * x + y * y).squareRoot()
            let theta = atan2(x, y)
            return (r * sin(theta + r), r * cos(theta - r))
        case .heart:
            let r = (x * x + y * y).squareRoot()
            let theta = atan2(x, y)
            return (r * sin(theta * r), -r * cos(theta * r))
        case .disc:
            let r = (x * x + y * y).squareRoot()
            let theta = atan2(x, y)
            return (theta / .pi * sin(.pi * r), theta / .pi * cos(.pi * r))
        case .spiral:
            let r = max((x * x + y * y).squareRoot(), 1e-9)
            let theta = atan2(x, y)
            return ((cos(theta) + sin(r)) / r, (sin(theta) - cos(r)) / r)
        case .hyperbolic:
            let r = max((x * x + y * y).squareRoot(), 1e-9)
            let theta = atan2(x, y)
            return (sin(theta) / r, r * cos(theta))
        case .diamond:
            let r = (x * x + y * y).squareRoot()
            let theta = atan2(x, y)
            return (sin(theta) * cos(r), cos(theta) * sin(r))
        case .ex:
            let r = (x * x + y * y).squareRoot()
            let theta = atan2(x, y)
            let p0 = sin(theta + r), p1 = cos(theta - r)
            return (r * (p0 * p0 * p0 + p1 * p1 * p1),
                    r * (p0 * p0 * p0 - p1 * p1 * p1))
        case .julia:
            let r = (x * x + y * y).squareRoot()
            let theta = atan2(x, y)
            let omega = Bool.random(using: &rng) ? Double.pi : 0
            return (r.squareRoot() * cos(theta / 2 + omega),
                    r.squareRoot() * sin(theta / 2 + omega))
        }
    }
}
