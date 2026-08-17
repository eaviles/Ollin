import Foundation

/// The **Buddhabrot**: the Mandelbrot set displayed by its escaping orbits.
/// Random points `c` are tested with the same z = z² + c loop the escape-time
/// generators run; the ones that escape are run again, and every plane point
/// their orbit visited brightens the pixel under it. The density of all those
/// visits, developed like a long photographic exposure, is the picture: a
/// ghostly seated figure that shares every filament with the set itself.
///
/// `iterations` is one cap or three. One cap develops a grayscale plate; three
/// caps expose the red, green, and blue channels at different orbit lengths
/// (the classic false-color split, long orbits red and short ones blue by
/// default), so depth of detail reads as color.
///
/// A pass this heavy is meant to be *watched*: make a `Renderer` once, feed it
/// a slice of samples each frame, and develop every few frames while the
/// figure rises out of the noise. The one-shot `render` sits on top for small
/// stills and tests. Deterministic: the same configuration, seed, and total
/// samples always develop the same image.
public struct Buddhabrot: Sendable {

    /// The orbit-length cap per channel: one entry for grayscale, three for
    /// the RGB false-color split. An orbit that escapes within a channel's cap
    /// exposes that channel; one that outlives every cap is taken to be inside
    /// the set and plots nothing.
    public var iterations: [Int]

    /// The window on the plane, in the classic upright framing: `x` spans the
    /// imaginary axis (the figure's width), `y` the real axis running down
    /// (the antenna at the top, the cardioid at the bottom).
    public var window: Rectangle

    /// The develop curve: counts map through `pow(count / ceiling, 1/gamma)`,
    /// so 1 is linear exposure and the default 2 lifts the faint veils.
    public var gamma: Double

    /// Exposure multiplier applied before the develop curve clips at white.
    public var brightness: Double

    public init(iterations: [Int] = [5000, 500, 50],
                window: Rectangle = Rectangle(x: -1.6, y: -2.05, width: 3.2, height: 3.2),
                gamma: Double = 2,
                brightness: Double = 1) {
        self.iterations = iterations
        self.window = window
        self.gamma = gamma
        self.brightness = brightness
    }

    /// Render a still: `quality` orbit samples per output pixel, from `rng`'s
    /// current state. The `Renderer` below is the progressive form.
    public func render<R: RandomNumberGenerator>(
        width: Int,
        height: Int,
        quality: Double = 10,
        using rng: inout R
    ) -> Image {
        let renderer = Renderer(self, width: width, height: height,
                                seed: Int(truncatingIfNeeded: UInt64.random(in: .min ... .max,
                                                                            using: &rng)))
        renderer.accumulate(samples: Int(quality * Double(max(1, width)) * Double(max(1, height))))
        return renderer.image()
    }

    /// The channel caps resolved to exactly three entries (r, g, b), the
    /// grayscale case repeating its one cap.
    var channelCaps: [Int] {
        let caps = iterations.isEmpty ? [5000] : iterations.map { min(max($0, 1), 200_000) }
        if caps.count == 1 { return [caps[0], caps[0], caps[0]] }
        return [caps[0], caps.count > 1 ? caps[1] : caps[0], caps.count > 2 ? caps[2] : caps[caps.count - 1]]
    }

    /// True when one cap serves all three channels, so the plate is developed
    /// as grayscale.
    var isGrayscale: Bool { iterations.count <= 1 }

    /// One orbit test: iterate z = z² + c and return the escape step (the
    /// first whose |z| left the radius-2 circle), writing the in-bound orbit
    /// points into `orbit` as x,y pairs. Returns nil when the orbit survives
    /// `cap` steps (taken to be inside the set) or is skipped by the interior
    /// shortcut. The main cardioid and the period-2 bulb are closed-form
    /// interior, so their points are rejected without iterating.
    static func escapeOrbit(cx: Double, cy: Double, cap: Int,
                            orbit: inout [Double]) -> Int? {
        // Interior shortcuts: the main cardioid and the period-2 bulb.
        let mx = cx - 0.25
        let q = mx * mx + cy * cy
        if q * (q + mx) < 0.25 * cy * cy { return nil }
        let bx = cx + 1
        if bx * bx + cy * cy < 0.0625 { return nil }

        orbit.removeAll(keepingCapacity: true)
        var zx = 0.0, zy = 0.0
        for step in 1 ... cap {
            let nx = zx * zx - zy * zy + cx
            let ny = 2 * zx * zy + cy
            zx = nx; zy = ny
            if zx * zx + zy * zy > 4 { return step }
            orbit.append(zx)
            orbit.append(zy)
        }
        return nil
    }

    /// The incremental Buddhabrot renderer: holds one density plate per
    /// channel, tests orbit samples in slices, and develops the current state
    /// into an image on demand. Orbits are deposited mirrored about the real
    /// axis (the set's own symmetry: the orbit of a conjugate seed is the
    /// conjugate orbit), so each sample exposes both halves of the figure.
    public final class Renderer {
        public let buddhabrot: Buddhabrot
        public let width: Int
        public let height: Int
        /// Total orbit samples (points c tested) so far.
        public private(set) var samples = 0

        private let caps: [Int]
        private let maxCap: Int
        private var plates: [[Float]]   // one width*height histogram per channel
        private var rng: SplitMix64
        private var orbit: [Double]

        public init(_ buddhabrot: Buddhabrot,
                    width: Int,
                    height: Int,
                    seed: Int = 1) {
            self.buddhabrot = buddhabrot
            self.width = max(1, width)
            self.height = max(1, height)
            caps = buddhabrot.channelCaps
            maxCap = caps.max() ?? 1
            plates = [[Float]](repeating: [Float](repeating: 0,
                                                  count: self.width * self.height),
                               count: 3)
            rng = SplitMix64(seed: UInt64(truncatingIfNeeded: seed))
            orbit = []
            orbit.reserveCapacity(maxCap * 2)
        }

        /// Test `count` more points c into the plates. Slices compose exactly:
        /// two calls of n samples land the same plates as one call of 2n.
        public func accumulate(samples count: Int) {
            guard count > 0 else { return }
            let window = buddhabrot.window
            guard window.width > 0, window.height > 0 else { return }
            let scaleX = Double(width) / window.width
            let scaleY = Double(height) / window.height
            var localRng = rng

            for _ in 0 ..< count {
                // Seeds come from the upper half of the radius-2 disc, the
                // whole region whose orbits can deposit anything (a seed
                // outside escapes on its first step and plots nothing); the
                // mirrored deposit below supplies the lower half. A smaller
                // box prints its own edge into the density as a rectangle.
                let cx = Double.random(in: -2 ... 2, using: &localRng)
                let cy = Double.random(in: 0 ... 2, using: &localRng)
                if cx * cx + cy * cy > 4 { continue }
                guard let escape = Buddhabrot.escapeOrbit(cx: cx, cy: cy,
                                                          cap: maxCap,
                                                          orbit: &orbit) else { continue }
                for channel in 0 ..< 3 where escape <= caps[channel] {
                    plates[channel].withUnsafeMutableBufferPointer { plate in
                        var i = 0
                        while i < orbit.count {
                            let zx = orbit[i], zy = orbit[i + 1]
                            i += 2
                            // The upright framing: imaginary across, real down.
                            let py = Int((zx - window.y) * scaleY)
                            guard py >= 0, py < height else { continue }
                            let px = Int((zy - window.x) * scaleX)
                            if px >= 0, px < width { plate[py * width + px] += 1 }
                            let mx = Int((-zy - window.x) * scaleX)
                            if mx >= 0, mx < width { plate[py * width + mx] += 1 }
                        }
                    }
                    if buddhabrot.isGrayscale { break }
                }
            }
            rng = localRng
            samples += count
        }

        /// Develop the current plates: each channel normalizes to a robust
        /// ceiling (the 99.9th percentile of its lit pixels, so a few hot
        /// pixels near the antenna can't dim the whole plate), then maps
        /// through the gamma curve.
        public func image() -> Image {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let invGamma = 1 / max(buddhabrot.gamma, 0.1)
            let brightness = max(buddhabrot.brightness, 0)
            let gray = buddhabrot.isGrayscale

            var developed = [[UInt8]?](repeating: nil, count: 3)
            for channel in 0 ..< (gray ? 1 : 3) {
                developed[channel] = developChannel(plates[channel],
                                                    invGamma: invGamma,
                                                    brightness: brightness)
            }

            for slot in 0 ..< width * height {
                let i = slot * 4
                if gray {
                    let v = developed[0]?[slot] ?? 0
                    bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
                } else {
                    bytes[i] = developed[0]?[slot] ?? 0
                    bytes[i + 1] = developed[1]?[slot] ?? 0
                    bytes[i + 2] = developed[2]?[slot] ?? 0
                }
                bytes[i + 3] = 255
            }
            return Image(width: width, height: height, premultipliedRGBA: bytes)
                ?? Image(width: width, height: height, color: .black)
        }

        /// Normalize one plate to its percentile ceiling and gamma-map it to
        /// bytes. The ceiling is found from a fixed 4096-bucket count
        /// histogram, so a develop stays cheap enough to run mid-accumulate.
        private func developChannel(_ plate: [Float], invGamma: Double,
                                    brightness: Double) -> [UInt8] {
            var maxCount: Float = 0
            for n in plate where n > maxCount { maxCount = n }
            guard maxCount > 0 else {
                return [UInt8](repeating: 0, count: width * height)
            }

            var buckets = [Int](repeating: 0, count: 4096)
            var lit = 0
            for n in plate where n > 0 {
                lit += 1
                let bucket = min(Int(n / maxCount * 4095), 4095)
                buckets[bucket] += 1
            }
            var remaining = Int(Double(lit) * 0.001)
            var ceilingBucket = 4095
            while ceilingBucket > 0, remaining > 0 {
                remaining -= buckets[ceilingBucket]
                ceilingBucket -= 1
            }
            let ceiling = max(Double(ceilingBucket + 1) / 4096 * Double(maxCount), 1)

            var out = [UInt8](repeating: 0, count: width * height)
            for slot in 0 ..< plate.count {
                let n = Double(plate[slot])
                guard n > 0 else { continue }
                let v = min(n / ceiling * brightness, 1)
                out[slot] = UInt8((pow(v, invGamma) * 255).rounded())
            }
            return out
        }
    }
}
