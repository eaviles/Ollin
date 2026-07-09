import Foundation

/// Seedable improved-Perlin noise (Ken Perlin's reference algorithm) backing
/// `Sketch.noise` / `Sketch.noiseSeed`. Lives on the `Sketch` instance, not as
/// global state. Output is contrast-calibrated and mapped to `0...1`; a seed
/// yields a reproducible field.
struct PerlinNoise {
    private var perm: [Int]   // 512 entries (a 0...255 permutation, doubled)

    init(seed: UInt64) { perm = PerlinNoise.permutation(seed: seed) }
    mutating func reseed(_ seed: UInt64) { perm = PerlinNoise.permutation(seed: seed) }

    /// A 0...255 permutation shuffled deterministically by `seed`, then doubled
    /// so lookups never need to wrap.
    private static func permutation(seed: UInt64) -> [Int] {
        var rng = SplitMix64(seed: seed)
        var p = Array(0...255)
        for i in stride(from: 255, to: 0, by: -1) {        // Fisher–Yates
            let j = Int(rng.next() % UInt64(i + 1))
            p.swapAt(i, j)
        }
        return p + p
    }

    /// Contrast gain applied to the raw Perlin value. Classic Perlin clusters
    /// near the middle of its range; ~2.0 spreads it to fill black-to-white, with
    /// only a few percent clipped at the extremes.
    private static let gain = 2.0

    /// Unsigned noise in `0...1` (contrast-calibrated to fill the range).
    func value(_ x: Double, _ y: Double, _ z: Double) -> Double {
        (signedValue(x, y, z) + 1) / 2
    }

    /// Signed noise in `-1...1`, contrast-calibrated to fill the range.
    func signedValue(_ x: Double, _ y: Double, _ z: Double) -> Double {
        Swift.max(-1, Swift.min(1, rawValue(x, y, z) * PerlinNoise.gain))
    }

    /// Raw improved-Perlin value — roughly `[-1, 1]`, but concentrated near 0.
    private func rawValue(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let xi = Int(floor(x)) & 255, yi = Int(floor(y)) & 255, zi = Int(floor(z)) & 255
        let xf = x - floor(x), yf = y - floor(y), zf = z - floor(z)
        let u = fade(xf), v = fade(yf), w = fade(zf)

        let a = perm[xi] + yi, aa = perm[a] + zi, ab = perm[a + 1] + zi
        let b = perm[xi + 1] + yi, ba = perm[b] + zi, bb = perm[b + 1] + zi

        return lerp(w,
            lerp(v,
                lerp(u, grad(perm[aa], xf, yf, zf),         grad(perm[ba], xf - 1, yf, zf)),
                lerp(u, grad(perm[ab], xf, yf - 1, zf),     grad(perm[bb], xf - 1, yf - 1, zf))),
            lerp(v,
                lerp(u, grad(perm[aa + 1], xf, yf, zf - 1),     grad(perm[ba + 1], xf - 1, yf, zf - 1)),
                lerp(u, grad(perm[ab + 1], xf, yf - 1, zf - 1), grad(perm[bb + 1], xf - 1, yf - 1, zf - 1))))
    }

    // MARK: 4D lattice (for looping noise)

    /// Contrast gain for the 4D lattice, calibrated empirically so the spread
    /// and clipped fraction match the 3D field's feel (the 4D gradients sum
    /// three components, so the raw spread comes out close to 3D's).
    private static let gain4 = 1.9

    /// Unsigned 4D noise in `0...1` (contrast-calibrated to fill the range).
    func value(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> Double {
        (signedValue(x, y, z, w) + 1) / 2
    }

    /// Signed 4D noise in `-1...1`, contrast-calibrated to fill the range.
    func signedValue(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> Double {
        Swift.max(-1, Swift.min(1, rawValue(x, y, z, w) * PerlinNoise.gain4))
    }

    /// Raw classic-Perlin value on the 4D lattice: the 3D scheme extended one
    /// axis (16 hypercube corners, the standard 32-direction gradient set).
    private func rawValue(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> Double {
        let xi = Int(floor(x)) & 255, yi = Int(floor(y)) & 255
        let zi = Int(floor(z)) & 255, wi = Int(floor(w)) & 255
        let xf = x - floor(x), yf = y - floor(y), zf = z - floor(z), wf = w - floor(w)
        let u = fade(xf), v = fade(yf), s = fade(zf), t = fade(wf)

        let a = perm[xi] + yi, b = perm[xi + 1] + yi
        let aa = perm[a] + zi, ab = perm[a + 1] + zi
        let ba = perm[b] + zi, bb = perm[b + 1] + zi
        let aaa = perm[aa] + wi, aab = perm[aa + 1] + wi
        let aba = perm[ab] + wi, abb = perm[ab + 1] + wi
        let baa = perm[ba] + wi, bab = perm[ba + 1] + wi
        let bba = perm[bb] + wi, bbb = perm[bb + 1] + wi

        let n0 = lerp(s,
            lerp(v,
                lerp(u, grad(perm[aaa], xf, yf, zf, wf),         grad(perm[baa], xf - 1, yf, zf, wf)),
                lerp(u, grad(perm[aba], xf, yf - 1, zf, wf),     grad(perm[bba], xf - 1, yf - 1, zf, wf))),
            lerp(v,
                lerp(u, grad(perm[aab], xf, yf, zf - 1, wf),     grad(perm[bab], xf - 1, yf, zf - 1, wf)),
                lerp(u, grad(perm[abb], xf, yf - 1, zf - 1, wf), grad(perm[bbb], xf - 1, yf - 1, zf - 1, wf))))
        let n1 = lerp(s,
            lerp(v,
                lerp(u, grad(perm[aaa + 1], xf, yf, zf, wf - 1),         grad(perm[baa + 1], xf - 1, yf, zf, wf - 1)),
                lerp(u, grad(perm[aba + 1], xf, yf - 1, zf, wf - 1),     grad(perm[bba + 1], xf - 1, yf - 1, zf, wf - 1))),
            lerp(v,
                lerp(u, grad(perm[aab + 1], xf, yf, zf - 1, wf - 1),     grad(perm[bab + 1], xf - 1, yf, zf - 1, wf - 1)),
                lerp(u, grad(perm[abb + 1], xf, yf - 1, zf - 1, wf - 1), grad(perm[bbb + 1], xf - 1, yf - 1, zf - 1, wf - 1))))
        return lerp(t, n0, n1)
    }

    private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    private func lerp(_ t: Double, _ a: Double, _ b: Double) -> Double { a + t * (b - a) }
    private func grad(_ hash: Int, _ x: Double, _ y: Double, _ z: Double) -> Double {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }
    /// The 4D gradient: the low 5 hash bits pick one of the 32 standard
    /// directions (a zero component and three unit components, signed).
    private func grad(_ hash: Int, _ x: Double, _ y: Double, _ z: Double, _ t: Double) -> Double {
        let h = hash & 31
        let u = h < 24 ? x : y
        let v = h < 16 ? y : z
        let w = h < 8 ? z : t
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v) + ((h & 4) == 0 ? w : -w)
    }
}

public extension Sketch {
    /// Seed the Perlin field behind `noise()` for reproducible runs.
    func noiseSeed(_ seed: Int) {
        perlin.reseed(UInt64(bitPattern: Int64(seed)))
        recordedNoiseSeed = seed
    }

    /// 1D Perlin noise at `x`, in `0...1`.
    func noise(_ x: Double) -> Double { perlin.value(x, 0, 0) }
    /// 2D Perlin noise at `(x, y)`, in `0...1`.
    func noise(_ x: Double, _ y: Double) -> Double { perlin.value(x, y, 0) }
    /// 3D Perlin noise at `(x, y, z)`, in `0...1`.
    func noise(_ x: Double, _ y: Double, _ z: Double) -> Double { perlin.value(x, y, z) }

    /// 1D signed Perlin noise at `x`, in `-1...1`.
    func signedNoise(_ x: Double) -> Double { perlin.signedValue(x, 0, 0) }
    /// 2D signed Perlin noise at `(x, y)`, in `-1...1`.
    func signedNoise(_ x: Double, _ y: Double) -> Double { perlin.signedValue(x, y, 0) }
    /// 3D signed Perlin noise at `(x, y, z)`, in `-1...1`.
    func signedNoise(_ x: Double, _ y: Double, _ z: Double) -> Double { perlin.signedValue(x, y, z) }

    // MARK: Looping noise

    /// Noise that loops: as `loop` runs `0...1` the sample tours a closed
    /// circle through the field and lands exactly where it started, so a value
    /// driven by `loop: loopProgress(over: 6)` drifts organically forever and
    /// still closes a seamless 6-second export. A time input that only grows
    /// (`noise(time)`) can never do this. `radius` sets how much of the field
    /// one lap tours: bigger laps change more.
    func noise(loop: Double, radius: Double = 1) -> Double {
        let (cx, cy) = loopPoint(loop, radius)
        return perlin.value(cx, cy, 0)
    }
    /// 1D noise at `x` that loops as `loop` runs `0...1` (see `noise(loop:radius:)`).
    /// For a wave on a ring that meets itself, feed the angle: `noise(r, loop: angle / .tau)`.
    func noise(_ x: Double, loop: Double, radius: Double = 1) -> Double {
        let (cx, cy) = loopPoint(loop, radius)
        return perlin.value(x, cx, cy)
    }
    /// 2D noise at `(x, y)` that loops as `loop` runs `0...1`: a whole field
    /// that drifts and returns home each lap (see `noise(loop:radius:)`).
    func noise(_ x: Double, _ y: Double, loop: Double, radius: Double = 1) -> Double {
        let (cx, cy) = loopPoint(loop, radius)
        return perlin.value(x, y, cx, cy)
    }

    /// Signed looping noise in `-1...1` (see `noise(loop:radius:)`).
    func signedNoise(loop: Double, radius: Double = 1) -> Double {
        let (cx, cy) = loopPoint(loop, radius)
        return perlin.signedValue(cx, cy, 0)
    }
    /// 1D signed looping noise in `-1...1` (see `noise(_:loop:radius:)`).
    func signedNoise(_ x: Double, loop: Double, radius: Double = 1) -> Double {
        let (cx, cy) = loopPoint(loop, radius)
        return perlin.signedValue(x, cx, cy)
    }
    /// 2D signed looping noise in `-1...1` (see `noise(_:_:loop:radius:)`).
    func signedNoise(_ x: Double, _ y: Double, loop: Double, radius: Double = 1) -> Double {
        let (cx, cy) = loopPoint(loop, radius)
        return perlin.signedValue(x, y, cx, cy)
    }

    // MARK: Layered noise (fbm)

    /// 1D fractal (layered) noise in `0...1`: `octaves` samples of the field,
    /// each octave `lacunarity`× smaller in feature size and `gain`× lighter in
    /// weight, normalized so the sum still fills `0...1`. One call for the
    /// shape-plus-detail layering you'd otherwise sum by hand; `octaves: 1` is
    /// exactly `noise(x)`. Matches the shader library's `fbm` vocabulary.
    func fbm(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in perlin.value(x * f, 0, 0) }
    }
    /// 2D fractal noise at `(x, y)`, in `0...1` (see `fbm(_:octaves:gain:lacunarity:)`).
    func fbm(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in perlin.value(x * f, y * f, 0) }
    }
    /// 3D fractal noise at `(x, y, z)`, in `0...1` (see `fbm(_:octaves:gain:lacunarity:)`).
    func fbm(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in perlin.value(x * f, y * f, z * f) }
    }
    /// 2D fractal noise that loops as `loop` runs `0...1`: every octave tours
    /// its own closed circle, so the layered field drifts and returns home each
    /// lap (see `noise(_:_:loop:radius:)`).
    func fbm(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
             octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in
            let (cx, cy) = loopPoint(loop, radius * f)
            return perlin.value(x * f, y * f, cx, cy)
        }
    }

    /// Signed 1D fractal noise in `-1...1` (see `fbm(_:octaves:gain:lacunarity:)`).
    func signedFbm(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbm(x, octaves: octaves, gain: gain, lacunarity: lacunarity) * 2 - 1
    }
    /// Signed 2D fractal noise in `-1...1` (see `fbm(_:_:octaves:gain:lacunarity:)`).
    func signedFbm(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbm(x, y, octaves: octaves, gain: gain, lacunarity: lacunarity) * 2 - 1
    }
    /// Signed 3D fractal noise in `-1...1` (see `fbm(_:_:_:octaves:gain:lacunarity:)`).
    func signedFbm(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbm(x, y, z, octaves: octaves, gain: gain, lacunarity: lacunarity) * 2 - 1
    }
    /// Signed 2D looping fractal noise in `-1...1` (see `fbm(_:_:loop:radius:octaves:gain:lacunarity:)`).
    func signedFbm(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbm(x, y, loop: loop, radius: radius, octaves: octaves, gain: gain, lacunarity: lacunarity) * 2 - 1
    }

    /// The point `loop` of the way around the sampling circle. `loop` wraps
    /// first (so 0 and 1 are the same point, exactly, and any lap closes), and
    /// the circle is centered off the integer lattice, where a lattice noise
    /// is livelier.
    private func loopPoint(_ loop: Double, _ radius: Double) -> (Double, Double) {
        let angle = fract(loop) * .tau
        return (0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius)
    }

    /// The shared fbm accumulator: sums `octaves` samples, each taken at a
    /// `lacunarity`× higher frequency (the multiplier handed to `sample`) with
    /// a `gain`× lighter weight, normalized by the total weight so the result
    /// stays in `0...1`.
    private func fbmSum(_ octaves: Int, _ gain: Double, _ lacunarity: Double,
                        _ sample: (Double) -> Double) -> Double {
        var sum = 0.0, weight = 0.0, amp = 1.0, frequency = 1.0
        for _ in 0..<Swift.max(1, octaves) {
            sum += amp * sample(frequency)
            weight += amp
            amp *= gain
            frequency *= lacunarity
        }
        return sum / weight
    }

    /// A divergence-free 2D flow vector at `(x, y)` — the curl of the Perlin
    /// field. Because it has no sources or sinks, it reads as smooth, swirling
    /// flow, which makes it the go-to for flow fields. The returned `Vector2`
    /// points along the flow; take `.normalized` for just the direction. Sample
    /// on scaled-down coordinates (e.g. `x * 0.003`) for broad, gentle swirls.
    func curlNoise(_ x: Double, _ y: Double) -> Vector2 {
        let eps = 0.0001
        let dfdx = (perlin.value(x + eps, y, 0) - perlin.value(x - eps, y, 0)) / (2 * eps)
        let dfdy = (perlin.value(x, y + eps, 0) - perlin.value(x, y - eps, 0)) / (2 * eps)
        return Vector2(dfdy, -dfdx)   // gradient rotated 90° = curl of a 2D field
    }
    /// `curlNoise` sampled at the point `p`.
    func curlNoise(_ p: Vector2) -> Vector2 { curlNoise(p.x, p.y) }
}
