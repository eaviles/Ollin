import Foundation

/// Seedable improved-Perlin noise (Ken Perlin's reference algorithm) backing
/// `Sketch.noise` / `Sketch.noiseSeed`. Lives on the `Sketch` instance, not as
/// global state. Output is contrast-calibrated and mapped to `0...1`; a seed
/// yields a reproducible field.
struct PerlinNoise: Sendable {
    private var perm: [Int]   // 512 entries (a 0...255 permutation, doubled)

    init(seed: UInt64) { perm = PerlinNoise.permutation(seed: seed) }
    mutating func reseed(_ seed: UInt64) { perm = PerlinNoise.permutation(seed: seed) }

    /// A 0...255 permutation shuffled deterministically by `seed`, then doubled
    /// so lookups never need to wrap. Shared with the simplex field (see
    /// NoiseVariants.swift), which hashes its lattice through the same table.
    static func permutation(seed: UInt64) -> [Int] {
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

    /// The lattice cell a coordinate falls in, wrapped to the table's 256.
    /// Inside an `Int`'s range this is `Int(floor(x)) & 255` exactly, so every
    /// field keeps its bits; past it (a clock run for ages, a coordinate read
    /// from a file) the floor is wrapped while it is still a `Double`, since
    /// narrowing it first traps, and a coordinate that is not a number lands
    /// on cell 0.
    @inline(__always)
    static func cell(_ x: Double) -> Int {
        let f = floor(x)
        if Swift.abs(f) < 9.0e18 { return Int(f) & 255 }
        guard f.isFinite else { return 0 }
        return Int(f - 256 * floor(f / 256)) & 255
    }

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
        let xi = PerlinNoise.cell(x), yi = PerlinNoise.cell(y), zi = PerlinNoise.cell(z)
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

    // MARK: The field with its slope

    /// The calibrated field at `(x, y, z)` together with its gradient, worked
    /// out in closed form rather than by sampling the field on either side.
    /// The curl forms read this: a curl needs six partial derivatives, and a
    /// difference per derivative costs two evaluations each, where one pass
    /// through the lattice gives the value and all three slopes at once.
    ///
    /// The gradient is of `value(_:_:_:)` exactly: `0...1`, gain applied, and
    /// zero wherever the calibration clips the field flat, so the curl of the
    /// field is the curl of the field a sketch reads, not of some other one.
    func valueAndGradient(_ x: Double, _ y: Double, _ z: Double) -> (value: Double, gradient: SIMD3<Double>) {
        let (raw, slope) = rawValueAndGradient(x, y, z)
        let scaled = raw * PerlinNoise.gain
        if scaled <= -1 { return (0, .zero) }
        if scaled >= 1 { return (1, .zero) }
        return ((scaled + 1) / 2, slope * (PerlinNoise.gain / 2))
    }

    /// The raw value and its gradient, from one walk of the cell's eight
    /// corners. The interpolation is trilinear in the faded offsets, so its
    /// derivative along an axis has two parts: the same interpolation over the
    /// corner gradients' components (the dot products' own slopes), plus the
    /// fade curve's slope times the difference the interpolation takes across
    /// that axis.
    private func rawValueAndGradient(_ x: Double, _ y: Double, _ z: Double) -> (Double, SIMD3<Double>) {
        let xi = PerlinNoise.cell(x), yi = PerlinNoise.cell(y), zi = PerlinNoise.cell(z)
        let xf = x - floor(x), yf = y - floor(y), zf = z - floor(z)
        let u = fade(xf), v = fade(yf), w = fade(zf)
        let du = fadeSlope(xf), dv = fadeSlope(yf), dw = fadeSlope(zf)

        let a = perm[xi] + yi, aa = perm[a] + zi, ab = perm[a + 1] + zi
        let b = perm[xi + 1] + yi, ba = perm[b] + zi, bb = perm[b + 1] + zi

        // The corner gradients, and each one's pull at the sample point.
        let g000 = gradVector(perm[aa]),     g100 = gradVector(perm[ba])
        let g010 = gradVector(perm[ab]),     g110 = gradVector(perm[bb])
        let g001 = gradVector(perm[aa + 1]), g101 = gradVector(perm[ba + 1])
        let g011 = gradVector(perm[ab + 1]), g111 = gradVector(perm[bb + 1])
        let n000 = g000.x * xf + g000.y * yf + g000.z * zf
        let n100 = g100.x * (xf - 1) + g100.y * yf + g100.z * zf
        let n010 = g010.x * xf + g010.y * (yf - 1) + g010.z * zf
        let n110 = g110.x * (xf - 1) + g110.y * (yf - 1) + g110.z * zf
        let n001 = g001.x * xf + g001.y * yf + g001.z * (zf - 1)
        let n101 = g101.x * (xf - 1) + g101.y * yf + g101.z * (zf - 1)
        let n011 = g011.x * xf + g011.y * (yf - 1) + g011.z * (zf - 1)
        let n111 = g111.x * (xf - 1) + g111.y * (yf - 1) + g111.z * (zf - 1)

        // Trilinear weights, once, shared by the value and every slope.
        let w000 = (1 - u) * (1 - v) * (1 - w), w100 = u * (1 - v) * (1 - w)
        let w010 = (1 - u) * v * (1 - w),       w110 = u * v * (1 - w)
        let w001 = (1 - u) * (1 - v) * w,       w101 = u * (1 - v) * w
        let w011 = (1 - u) * v * w,             w111 = u * v * w

        let value = n000 * w000 + n100 * w100 + n010 * w010 + n110 * w110
                  + n001 * w001 + n101 * w101 + n011 * w011 + n111 * w111
        // Summed a term at a time, in this order: one expression of eight
        // vector products is more than a release toolchain will type-check.
        var gradient: SIMD3<Double> = g000 * w000
        gradient += g100 * w100
        gradient += g010 * w010
        gradient += g110 * w110
        gradient += g001 * w001
        gradient += g101 * w101
        gradient += g011 * w011
        gradient += g111 * w111
        // The fade's own slope along each axis, weighted by the other two.
        let iu = 1 - u, iv = 1 - v, iw = 1 - w
        let x00: Double = (n100 - n000) * iv * iw
        let x10: Double = (n110 - n010) * v * iw
        let x01: Double = (n101 - n001) * iv * w
        let x11: Double = (n111 - n011) * v * w
        gradient.x += du * (x00 + x10 + x01 + x11)
        let y00: Double = (n010 - n000) * iu * iw
        let y10: Double = (n110 - n100) * u * iw
        let y01: Double = (n011 - n001) * iu * w
        let y11: Double = (n111 - n101) * u * w
        gradient.y += dv * (y00 + y10 + y01 + y11)
        let z00: Double = (n001 - n000) * iu * iv
        let z10: Double = (n101 - n100) * u * iv
        let z01: Double = (n011 - n010) * iu * v
        let z11: Double = (n111 - n110) * u * v
        gradient.z += dw * (z00 + z10 + z01 + z11)
        return (value, gradient)
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
        let xi = PerlinNoise.cell(x), yi = PerlinNoise.cell(y)
        let zi = PerlinNoise.cell(z), wi = PerlinNoise.cell(w)
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
    /// The fade curve's derivative, `30 t^2 (t - 1)^2`.
    private func fadeSlope(_ t: Double) -> Double { 30 * t * t * (t - 1) * (t - 1) }
    private func lerp(_ t: Double, _ a: Double, _ b: Double) -> Double { a + t * (b - a) }
    private func grad(_ hash: Int, _ x: Double, _ y: Double, _ z: Double) -> Double {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }
    /// The gradient `grad(_:_:_:_:)` dots with, as a vector: the same twelve
    /// cube-edge directions (plus the four repeats that pad the set to sixteen),
    /// picked by the same hash bits, so the two agree corner for corner.
    private func gradVector(_ hash: Int) -> SIMD3<Double> {
        let h = hash & 15
        let su: Double = (h & 1) == 0 ? 1 : -1
        let sv: Double = (h & 2) == 0 ? 1 : -1
        var g = SIMD3<Double>.zero
        if h < 8 { g.x += su } else { g.y += su }
        if h < 4 { g.y += sv } else if h == 12 || h == 14 { g.x += sv } else { g.z += sv }
        return g
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

// The classic family, on the value. `Sketch` forwards every one of these (below),
// so the bare `noise(x, y)` and `noiseFields.noise(x, y)` are one number.
public extension NoiseFields {
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

    // MARK: Tiling noise

    /// 2D noise that tiles. As `u` and `v` each run `0...1` the sample tours a
    /// closed circle in *both* directions, so the field meets itself at every
    /// edge and a picture drawn from it repeats with no seam.
    ///
    /// This is what a picture wants whenever it will be repeated, and the case
    /// that catches people out is a projected one: `triplanarTextured(_:)`
    /// repeats its picture across the whole surface, so an ordinary
    /// `fbm(u * 8, v * 8)` map draws a straight line wherever the picture wraps.
    /// The mismatch is loudest in a normal map, where the two sides of the join
    /// light differently and the line reads as a crease.
    ///
    /// `detail` is roughly how many features fit across one tile, so it reads
    /// as the frequency you would otherwise multiply into the coordinates: a
    /// map written `fbm(u * 8, v * 8)` becomes `tilingFbm(u, v, detail: 8)` and
    /// keeps its grain.
    ///
    /// ```swift
    /// // filling a map, one texel at a time
    /// let u = (Double(x) + 0.5) / 512, v = (Double(y) + 0.5) / 512
    /// let shade = Color(white: tilingFbm(u, v, detail: 5, octaves: 5))
    /// ```
    ///
    /// Under the hood both directions ride the 4D construction the looping
    /// forms use for time, spent on space twice instead.
    func tilingNoise(_ u: Double, _ v: Double, detail: Double = 4) -> Double {
        let (ux, uy) = tilePoint(u, detail)
        let (vx, vy) = tilePoint(v, detail)
        return perlin.value(ux, uy, vx, vy)
    }
    /// 2D signed tiling noise in `-1...1` (see `tilingNoise(_:_:detail:)`).
    func signedTilingNoise(_ u: Double, _ v: Double, detail: Double = 4) -> Double {
        let (ux, uy) = tilePoint(u, detail)
        let (vx, vy) = tilePoint(v, detail)
        return perlin.signedValue(ux, uy, vx, vy)
    }
    /// 2D fractal noise that tiles: every octave tours its own pair of closed
    /// circles, so the layered field still meets itself at every edge (see
    /// `tilingNoise(_:_:detail:)`).
    func tilingFbm(_ u: Double, _ v: Double, detail: Double = 4,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in
            let (ux, uy) = tilePoint(u, detail * f)
            let (vx, vy) = tilePoint(v, detail * f)
            return perlin.value(ux, uy, vx, vy)
        }
    }
    /// 2D signed tiling fractal noise in `-1...1` (see
    /// `tilingFbm(_:_:detail:octaves:gain:lacunarity:)`).
    func signedTilingFbm(_ u: Double, _ v: Double, detail: Double = 4,
                         octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        tilingFbm(u, v, detail: detail, octaves: octaves, gain: gain, lacunarity: lacunarity) * 2 - 1
    }

    // MARK: Ridged and turbulence fbm

    /// 1D ridged fractal noise in `0...1`: fbm's mountainous sibling. Each
    /// octave folds the signed field into sharp creases (one minus the
    /// absolute value, squared), and an octave only contributes where the one
    /// below it was strong, so detail gathers on the ridge lines instead of
    /// filling the valleys (the multifractal feedback that makes terrain read
    /// as terrain). Same parameters as `fbm`; bright values are the ridges.
    func ridgedFbm(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        ridgedSum(octaves, gain, lacunarity) { f in perlin.signedValue(x * f, 0, 0) }
    }
    /// 2D ridged fractal noise at `(x, y)`, in `0...1` (see `ridgedFbm(_:octaves:gain:lacunarity:)`).
    func ridgedFbm(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        ridgedSum(octaves, gain, lacunarity) { f in perlin.signedValue(x * f, y * f, 0) }
    }
    /// 3D ridged fractal noise at `(x, y, z)`, in `0...1` (see `ridgedFbm(_:octaves:gain:lacunarity:)`).
    func ridgedFbm(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        ridgedSum(octaves, gain, lacunarity) { f in perlin.signedValue(x * f, y * f, z * f) }
    }
    /// 2D ridged fractal noise that loops as `loop` runs `0...1` (see
    /// `fbm(_:_:loop:radius:octaves:gain:lacunarity:)` for the loop mechanics).
    func ridgedFbm(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        ridgedSum(octaves, gain, lacunarity) { f in
            let (cx, cy) = loopPoint(loop, radius * f)
            return perlin.signedValue(x * f, y * f, cx, cy)
        }
    }

    /// 1D turbulence in `0...1`: fbm over the folded field (each octave takes
    /// the absolute value of the signed noise), so instead of rolling hills the
    /// layers pile into billows with creased seams, the classic basis for
    /// clouds, smoke, and marble. Same parameters as `fbm`.
    func turbulence(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in Swift.abs(perlin.signedValue(x * f, 0, 0)) }
    }
    /// 2D turbulence at `(x, y)`, in `0...1` (see `turbulence(_:octaves:gain:lacunarity:)`).
    func turbulence(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in Swift.abs(perlin.signedValue(x * f, y * f, 0)) }
    }
    /// 3D turbulence at `(x, y, z)`, in `0...1` (see `turbulence(_:octaves:gain:lacunarity:)`).
    func turbulence(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in Swift.abs(perlin.signedValue(x * f, y * f, z * f)) }
    }
    /// 2D turbulence that loops as `loop` runs `0...1` (see
    /// `fbm(_:_:loop:radius:octaves:gain:lacunarity:)` for the loop mechanics).
    func turbulence(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
                    octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        fbmSum(octaves, gain, lacunarity) { f in
            let (cx, cy) = loopPoint(loop, radius * f)
            return Swift.abs(perlin.signedValue(x * f, y * f, cx, cy))
        }
    }

    // MARK: Domain warping

    /// 2D fbm sampled through two rounds of self-displacement: the field warps
    /// its own coordinates, then warps them again, which smears the layers into
    /// the flowing marble-and-cloud look no amount of plain layering produces.
    /// `warp` scales the displacement: 0 is exactly `fbm(x, y)`, 1 the classic
    /// strength, and beyond 1 the field tears into churn. The other parameters pass
    /// through to the underlying `fbm`.
    func warpedFbm(_ x: Double, _ y: Double, warp: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        func layer(_ px: Double, _ py: Double) -> Double {
            fbm(px, py, octaves: octaves, gain: gain, lacunarity: lacunarity)
        }
        let k = 4 * warp
        let qx = layer(x, y), qy = layer(x + 5.2, y + 1.3)
        let rx = layer(x + k * qx + 1.7, y + k * qy + 9.2)
        let ry = layer(x + k * qx + 8.3, y + k * qy + 2.8)
        return layer(x + k * rx, y + k * ry)
    }
    /// 2D warped fbm that loops as `loop` runs `0...1`: every layer of the
    /// warp tours the same closed circle, so the whole churning field drifts
    /// and returns home each lap (see `noise(loop:radius:)`).
    func warpedFbm(_ x: Double, _ y: Double, warp: Double = 1, loop: Double, radius: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        func layer(_ px: Double, _ py: Double) -> Double {
            fbm(px, py, loop: loop, radius: radius, octaves: octaves, gain: gain, lacunarity: lacunarity)
        }
        let k = 4 * warp
        let qx = layer(x, y), qy = layer(x + 5.2, y + 1.3)
        let rx = layer(x + k * qx + 1.7, y + k * qy + 9.2)
        let ry = layer(x + k * qx + 8.3, y + k * qy + 2.8)
        return layer(x + k * rx, y + k * ry)
    }

    /// The ridged accumulator: each octave's signed sample folds into a crease
    /// ((1 - |n|) squared), attenuated by how strong the previous octave's
    /// crease was (clamped at twice its value), summed under the same
    /// gain-per-octave weights as `fbmSum` and normalized to `0...1`.
    private func ridgedSum(_ octaves: Int, _ gain: Double, _ lacunarity: Double,
                           _ sample: (Double) -> Double) -> Double {
        var sum = 0.0, weight = 0.0
        var amp = 1.0, frequency = 1.0, feedback = 1.0
        for _ in 0..<Swift.max(1, octaves) {
            var signal = 1 - Swift.abs(sample(frequency))
            signal *= signal
            signal *= feedback
            sum += signal * amp
            weight += amp
            feedback = Swift.min(Swift.max(signal * 2, 0), 1)
            amp *= gain
            frequency *= lacunarity
        }
        return sum / weight
    }

    /// The point `loop` of the way around the sampling circle. `loop` wraps
    /// first (so 0 and 1 are the same point, exactly, and any lap closes), and
    /// the circle is centered off the integer lattice, where a lattice noise
    /// is livelier.
    private func loopPoint(_ loop: Double, _ radius: Double) -> (Double, Double) {
        let angle = fract(loop) * .tau
        return (0.5 + cos(angle) * radius, 0.5 + sin(angle) * radius)
    }

    /// A point on the circle one *tile* tours (see `tilingNoise(_:_:detail:)`).
    /// `detail` is the field distance the tile covers, so it becomes the
    /// circle's circumference rather than its radius, and the caller's number
    /// reads as a frequency: `detail: 8` tours the same 8 units of field that
    /// `fbm(u * 8, ...)` walks in a straight line.
    private func tilePoint(_ t: Double, _ detail: Double) -> (Double, Double) {
        loopPoint(t, detail / .tau)
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

    /// A divergence-free 2D flow vector at `(x, y)`: the curl of the Perlin
    /// field. Because it has no sources or sinks, it reads as smooth, swirling
    /// flow, which makes it the go-to for flow fields. The returned `Vector2`
    /// points along the flow; take `.normalized` for just the direction. Sample
    /// on scaled-down coordinates (e.g. `x * 0.003`) for broad, gentle swirls.
    func curlNoise(_ x: Double, _ y: Double) -> Vector2 {
        let slope = perlin.valueAndGradient(x, y, 0).gradient
        return Vector2(slope.y, -slope.x)   // gradient rotated 90° = curl of a 2D field
    }
    /// `curlNoise` sampled at the point `p`.
    func curlNoise(_ p: Vector2) -> Vector2 { curlNoise(p.x, p.y) }

    /// A divergence-free 3D flow vector at `(x, y, z)`: the curl of a vector
    /// potential made of three copies of the Perlin field, each read at its own
    /// offset. The same construction as the 2D form one dimension up, and the
    /// same promise: the flow only ever swirls, never gathers or drains, so
    /// points carried by it stay evenly spread, and geometry bent by it bends
    /// as if a fluid had passed through. Not normalized, like the 2D form; take
    /// `.normalized` for the direction alone, and scale the coordinates down
    /// (`p * 0.5` on a scene a few units across) for broad, gentle swirls.
    ///
    /// ```swift
    /// let bent = p + curlNoise(p * 0.5) * 0.3       // nudge a vertex along the flow
    /// ```
    func curlNoise(_ x: Double, _ y: Double, _ z: Double) -> Vector3 {
        let a = perlin.valueAndGradient(x, y, z).gradient
        let b = perlin.valueAndGradient(x + 31.4, y - 47.2, z + 12.9).gradient
        let c = perlin.valueAndGradient(x - 71.1, y + 23.6, z - 58.3).gradient
        // ∇ × (ψa, ψb, ψc), each component a difference of two partials.
        return Vector3(c.y - b.z, a.z - c.x, b.x - a.y)
    }
    /// `curlNoise` sampled at the point `p`.
    func curlNoise(_ p: Vector3) -> Vector3 { curlNoise(p.x, p.y, p.z) }
}

// The sketch's bare calls: each forwards to `noiseFields`, the value under them.
public extension Sketch {
    /// Seed the noise fields (`noise()`, `simplexNoise()`, `worley()`, and the
    /// fbm family) for reproducible runs.
    func noiseSeed(_ seed: Int) {
        noiseFields.reseed(seed)
        recordedNoiseSeed = seed
    }

    /// 1D Perlin noise at `x`, in `0...1` (see `NoiseFields`).
    func noise(_ x: Double) -> Double { noiseFields.noise(x) }
    /// 2D Perlin noise at `(x, y)`, in `0...1`.
    func noise(_ x: Double, _ y: Double) -> Double { noiseFields.noise(x, y) }
    /// 3D Perlin noise at `(x, y, z)`, in `0...1`.
    func noise(_ x: Double, _ y: Double, _ z: Double) -> Double { noiseFields.noise(x, y, z) }

    /// 1D signed Perlin noise at `x`, in `-1...1`.
    func signedNoise(_ x: Double) -> Double { noiseFields.signedNoise(x) }
    /// 2D signed Perlin noise at `(x, y)`, in `-1...1`.
    func signedNoise(_ x: Double, _ y: Double) -> Double { noiseFields.signedNoise(x, y) }
    /// 3D signed Perlin noise at `(x, y, z)`, in `-1...1`.
    func signedNoise(_ x: Double, _ y: Double, _ z: Double) -> Double { noiseFields.signedNoise(x, y, z) }

    /// Noise that loops as `loop` runs `0...1`, touring a closed circle through
    /// the field so a lap lands where it started (see `NoiseFields.noise(loop:radius:)`).
    func noise(loop: Double, radius: Double = 1) -> Double { noiseFields.noise(loop: loop, radius: radius) }
    /// 1D noise at `x` that loops as `loop` runs `0...1`.
    func noise(_ x: Double, loop: Double, radius: Double = 1) -> Double {
        noiseFields.noise(x, loop: loop, radius: radius)
    }
    /// 2D noise at `(x, y)` that loops as `loop` runs `0...1`.
    func noise(_ x: Double, _ y: Double, loop: Double, radius: Double = 1) -> Double {
        noiseFields.noise(x, y, loop: loop, radius: radius)
    }
    /// Signed looping noise in `-1...1` (see `noise(loop:radius:)`).
    func signedNoise(loop: Double, radius: Double = 1) -> Double {
        noiseFields.signedNoise(loop: loop, radius: radius)
    }
    /// 1D signed looping noise in `-1...1`.
    func signedNoise(_ x: Double, loop: Double, radius: Double = 1) -> Double {
        noiseFields.signedNoise(x, loop: loop, radius: radius)
    }
    /// 2D signed looping noise in `-1...1`.
    func signedNoise(_ x: Double, _ y: Double, loop: Double, radius: Double = 1) -> Double {
        noiseFields.signedNoise(x, y, loop: loop, radius: radius)
    }

    /// 1D fractal (layered) noise in `0...1` (see `NoiseFields.fbm(_:octaves:gain:lacunarity:)`).
    func fbm(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.fbm(x, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D fractal noise at `(x, y)`, in `0...1`.
    func fbm(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.fbm(x, y, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 3D fractal noise at `(x, y, z)`, in `0...1`.
    func fbm(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.fbm(x, y, z, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D fractal noise that loops as `loop` runs `0...1`.
    func fbm(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
             octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.fbm(x, y, loop: loop, radius: radius, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// Signed 1D fractal noise in `-1...1`.
    func signedFbm(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.signedFbm(x, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// Signed 2D fractal noise in `-1...1`.
    func signedFbm(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.signedFbm(x, y, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// Signed 3D fractal noise in `-1...1`.
    func signedFbm(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.signedFbm(x, y, z, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// Signed 2D looping fractal noise in `-1...1`.
    func signedFbm(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.signedFbm(x, y, loop: loop, radius: radius, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }

    /// 2D noise that tiles: the field meets itself at every edge as `u` and `v`
    /// run `0...1` (see `NoiseFields.tilingNoise(_:_:detail:)`).
    func tilingNoise(_ u: Double, _ v: Double, detail: Double = 4) -> Double {
        noiseFields.tilingNoise(u, v, detail: detail)
    }
    /// 2D signed tiling noise in `-1...1`.
    func signedTilingNoise(_ u: Double, _ v: Double, detail: Double = 4) -> Double {
        noiseFields.signedTilingNoise(u, v, detail: detail)
    }
    /// 2D fractal noise that tiles.
    func tilingFbm(_ u: Double, _ v: Double, detail: Double = 4,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.tilingFbm(u, v, detail: detail, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D signed tiling fractal noise in `-1...1`.
    func signedTilingFbm(_ u: Double, _ v: Double, detail: Double = 4,
                         octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.signedTilingFbm(u, v, detail: detail, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }

    /// 1D ridged fractal noise in `0...1`: creases as bright lines, detail on
    /// the crests (see `NoiseFields.ridgedFbm(_:octaves:gain:lacunarity:)`).
    func ridgedFbm(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.ridgedFbm(x, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D ridged fractal noise at `(x, y)`, in `0...1`.
    func ridgedFbm(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.ridgedFbm(x, y, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 3D ridged fractal noise at `(x, y, z)`, in `0...1`.
    func ridgedFbm(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.ridgedFbm(x, y, z, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D ridged fractal noise that loops as `loop` runs `0...1`.
    func ridgedFbm(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.ridgedFbm(x, y, loop: loop, radius: radius, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 1D turbulence in `0...1`: layered folded noise, billows with creased
    /// seams (see `NoiseFields.turbulence(_:octaves:gain:lacunarity:)`).
    func turbulence(_ x: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.turbulence(x, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D turbulence at `(x, y)`, in `0...1`.
    func turbulence(_ x: Double, _ y: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.turbulence(x, y, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 3D turbulence at `(x, y, z)`, in `0...1`.
    func turbulence(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.turbulence(x, y, z, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D turbulence that loops as `loop` runs `0...1`.
    func turbulence(_ x: Double, _ y: Double, loop: Double, radius: Double = 1,
                    octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.turbulence(x, y, loop: loop, radius: radius, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }

    /// 2D domain-warped fbm: the field displaces its own coordinates, twice
    /// over (see `NoiseFields.warpedFbm(_:_:warp:octaves:gain:lacunarity:)`).
    func warpedFbm(_ x: Double, _ y: Double, warp: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.warpedFbm(x, y, warp: warp, octaves: octaves, gain: gain, lacunarity: lacunarity)
    }
    /// 2D warped fbm that loops as `loop` runs `0...1`.
    func warpedFbm(_ x: Double, _ y: Double, warp: Double = 1, loop: Double, radius: Double = 1,
                   octaves: Int = 4, gain: Double = 0.5, lacunarity: Double = 2) -> Double {
        noiseFields.warpedFbm(x, y, warp: warp, loop: loop, radius: radius,
                              octaves: octaves, gain: gain, lacunarity: lacunarity)
    }

    /// A divergence-free 2D flow vector at `(x, y)`, the curl of the Perlin
    /// field (see `NoiseFields.curlNoise(_:_:)`).
    func curlNoise(_ x: Double, _ y: Double) -> Vector2 { noiseFields.curlNoise(x, y) }
    /// `curlNoise` sampled at the point `p`.
    func curlNoise(_ p: Vector2) -> Vector2 { noiseFields.curlNoise(p) }
    /// A divergence-free 3D flow vector at `(x, y, z)`, the curl of three offset
    /// copies of the field (see `NoiseFields.curlNoise(_:_:_:)`).
    func curlNoise(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { noiseFields.curlNoise(x, y, z) }
    /// `curlNoise` sampled at the point `p`.
    func curlNoise(_ p: Vector3) -> Vector3 { noiseFields.curlNoise(p) }

    /// This sketch's noise field, as a plain function of three coordinates,
    /// answering `-1...1`. It is how something that reads noise outside
    /// `draw()` (a ``Formula`` driving a parameter, for one) sees the same field the
    /// sketch does, so `noiseSeed()` reaches it as well. For the whole family
    /// as a value, `noiseFields`.
    func noiseField() -> Formula.NoiseField {
        let fields = noiseFields
        return { x, y, z in fields.signedNoise(x, y, z) }
    }
}
