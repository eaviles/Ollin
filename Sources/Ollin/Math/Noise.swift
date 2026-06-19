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

    private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    private func lerp(_ t: Double, _ a: Double, _ b: Double) -> Double { a + t * (b - a) }
    private func grad(_ hash: Int, _ x: Double, _ y: Double, _ z: Double) -> Double {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }
}

public extension Sketch {
    /// Seed the Perlin field behind `noise()` for reproducible runs.
    func noiseSeed(_ seed: Int) { perlin.reseed(UInt64(bitPattern: Int64(seed))) }

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
