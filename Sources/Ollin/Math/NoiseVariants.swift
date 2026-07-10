import Foundation

/// Seedable simplex noise (Ken Perlin's 2001 successor to his classic lattice
/// noise, implemented from Stefan Gustavson's description) backing
/// `Sketch.simplexNoise`. Where the classic field interpolates over squares,
/// simplex sums radial kernels over triangles (tetrahedra in 3D), so its grain
/// is more even in every direction, with none of the classic field's faint
/// axis-aligned bias. Output is contrast-calibrated and mapped like the Perlin
/// field's; a seed yields a reproducible field.
struct SimplexNoise {
    private var perm: [Int]   // 512 entries (a 0...255 permutation, doubled)

    init(seed: UInt64) { perm = PerlinNoise.permutation(seed: seed) }
    mutating func reseed(_ seed: UInt64) { perm = PerlinNoise.permutation(seed: seed) }

    /// The 12 gradient directions (the midpoints of a cube's edges), indexed by
    /// the corner hash. The standard set: even coverage, no axis favored.
    private static let grad3: [SIMD3<Double>] = [
        .init(1, 1, 0), .init(-1, 1, 0), .init(1, -1, 0), .init(-1, -1, 0),
        .init(1, 0, 1), .init(-1, 0, 1), .init(1, 0, -1), .init(-1, 0, -1),
        .init(0, 1, 1), .init(0, -1, 1), .init(0, 1, -1), .init(0, -1, -1),
    ]

    /// Contrast gains: the raw kernel sums cluster inside `-1...1`, so each is
    /// stretched to fill black-to-white with only a few percent clipped at the
    /// extremes (the same calibration the Perlin field applies).
    private static let gain2 = 81.3
    private static let gain3 = 87.7

    /// Unsigned 2D simplex noise in `0...1`.
    func value(_ x: Double, _ y: Double) -> Double { (signedValue(x, y) + 1) / 2 }
    /// Unsigned 3D simplex noise in `0...1`.
    func value(_ x: Double, _ y: Double, _ z: Double) -> Double { (signedValue(x, y, z) + 1) / 2 }

    /// Signed 2D simplex noise in `-1...1`.
    ///
    /// Skew the plane so the triangular lattice becomes a square grid, find the
    /// cell and which of its two triangles holds the point, then sum a radial
    /// kernel times a hashed gradient at each of the three corners.
    func signedValue(_ x: Double, _ y: Double) -> Double {
        let f2 = 0.5 * (3.0.squareRoot() - 1)      // skew: square grid -> simplex
        let g2 = (3 - 3.0.squareRoot()) / 6        // unskew, back to the plane
        let s = (x + y) * f2
        let i = floor(x + s), j = floor(y + s)
        let t = (i + j) * g2
        let x0 = x - (i - t), y0 = y - (j - t)     // offsets from the near corner

        // Which triangle: lower (walk x first) or upper (walk y first).
        let i1 = x0 > y0 ? 1 : 0, j1 = 1 - i1
        let x1 = x0 - Double(i1) + g2, y1 = y0 - Double(j1) + g2
        let x2 = x0 - 1 + 2 * g2, y2 = y0 - 1 + 2 * g2

        let ii = Int(i) & 255, jj = Int(j) & 255
        var n = corner2(x0, y0, perm[ii + perm[jj]])
        n += corner2(x1, y1, perm[ii + i1 + perm[jj + j1]])
        n += corner2(x2, y2, perm[ii + 1 + perm[jj + 1]])
        return Swift.max(-1, Swift.min(1, n * SimplexNoise.gain2))
    }

    /// Signed 3D simplex noise in `-1...1` (the 2D scheme one axis up: skew to
    /// a cubic grid, rank the offsets to pick one of the cell's six tetrahedra,
    /// sum the kernel at its four corners).
    func signedValue(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let f3 = 1.0 / 3, g3 = 1.0 / 6
        let s = (x + y + z) * f3
        let i = floor(x + s), j = floor(y + s), k = floor(z + s)
        let t = (i + j + k) * g3
        let x0 = x - (i - t), y0 = y - (j - t), z0 = z - (k - t)

        // Rank the offsets: the descent order through the tetrahedron's corners.
        let i1: Int, j1: Int, k1: Int, i2: Int, j2: Int, k2: Int
        if x0 >= y0 {
            if y0 >= z0 { (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 1, 0) }
            else if x0 >= z0 { (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 0, 1) }
            else { (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 1, 0, 1) }
        } else {
            if y0 < z0 { (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 0, 1, 1) }
            else if x0 < z0 { (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 0, 1, 1) }
            else { (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 1, 1, 0) }
        }

        let x1 = x0 - Double(i1) + g3, y1 = y0 - Double(j1) + g3, z1 = z0 - Double(k1) + g3
        let x2 = x0 - Double(i2) + 2 * g3, y2 = y0 - Double(j2) + 2 * g3, z2 = z0 - Double(k2) + 2 * g3
        let x3 = x0 - 1 + 3 * g3, y3 = y0 - 1 + 3 * g3, z3 = z0 - 1 + 3 * g3

        let ii = Int(i) & 255, jj = Int(j) & 255, kk = Int(k) & 255
        var n = corner3(x0, y0, z0, perm[ii + perm[jj + perm[kk]]])
        n += corner3(x1, y1, z1, perm[ii + i1 + perm[jj + j1 + perm[kk + k1]]])
        n += corner3(x2, y2, z2, perm[ii + i2 + perm[jj + j2 + perm[kk + k2]]])
        n += corner3(x3, y3, z3, perm[ii + 1 + perm[jj + 1 + perm[kk + 1]]])
        return Swift.max(-1, Swift.min(1, n * SimplexNoise.gain3))
    }

    /// One corner's contribution: a radial falloff kernel (fourth power of
    /// `0.5 - distance squared`, zero beyond its ring) times the hashed
    /// gradient's pull. The kernel reaches zero exactly at the ring, so
    /// corners switch on and off with no seam.
    private func corner2(_ x: Double, _ y: Double, _ hash: Int) -> Double {
        var t = 0.5 - x * x - y * y
        if t < 0 { return 0 }
        t *= t
        let g = SimplexNoise.grad3[hash % 12]
        return t * t * (g.x * x + g.y * y)
    }

    private func corner3(_ x: Double, _ y: Double, _ z: Double, _ hash: Int) -> Double {
        var t = 0.5 - x * x - y * y - z * z
        if t < 0 { return 0 }
        t *= t
        let g = SimplexNoise.grad3[hash % 12]
        return t * t * (g.x * x + g.y * y + g.z * z)
    }
}

/// Seedable cellular noise (Steven Worley's texture basis) backing
/// `Sketch.worley`. Space is divided into unit cells, each holding one hashed
/// feature point; the value at a sample is the distance to the nearest point
/// (or the second nearest, or the gap between the two), which reads as organic
/// cells: stone, foam, cracked earth, water caustics.
struct WorleyNoise {
    private var seed: UInt64

    init(seed: UInt64) { self.seed = seed }
    mutating func reseed(_ seed: UInt64) { self.seed = seed }

    /// Distances to the nearest and second-nearest feature points in 2D,
    /// scanning the 3x3 cell neighborhood (a feature point can sit anywhere in
    /// its cell, so only adjacent cells can hold the winner).
    func distances(_ x: Double, _ y: Double, jitter: Double) -> (Double, Double) {
        let xi = floor(x), yi = floor(y)
        let fx = x - xi, fy = y - yi
        var f1 = Double.infinity, f2 = Double.infinity
        for dy in -1...1 {
            for dx in -1...1 {
                let h = cellHash(Int(xi) + dx, Int(yi) + dy, 0)
                let px = Double(dx) + point01(h, 0, jitter) - fx
                let py = Double(dy) + point01(h, 1, jitter) - fy
                let d = (px * px + py * py).squareRoot()
                if d < f1 { f2 = f1; f1 = d } else if d < f2 { f2 = d }
            }
        }
        return (f1, f2)
    }

    /// Distances to the nearest and second-nearest feature points in 3D,
    /// scanning the 3x3x3 cell neighborhood.
    func distances(_ x: Double, _ y: Double, _ z: Double, jitter: Double) -> (Double, Double) {
        let xi = floor(x), yi = floor(y), zi = floor(z)
        let fx = x - xi, fy = y - yi, fz = z - zi
        var f1 = Double.infinity, f2 = Double.infinity
        for dz in -1...1 {
            for dy in -1...1 {
                for dx in -1...1 {
                    let h = cellHash(Int(xi) + dx, Int(yi) + dy, Int(zi) + dz)
                    let px = Double(dx) + point01(h, 0, jitter) - fx
                    let py = Double(dy) + point01(h, 1, jitter) - fy
                    let pz = Double(dz) + point01(h, 2, jitter) - fz
                    let d = (px * px + py * py + pz * pz).squareRoot()
                    if d < f1 { f2 = f1; f1 = d } else if d < f2 { f2 = d }
                }
            }
        }
        return (f1, f2)
    }

    /// One cell's feature-point coordinate on `axis`, `jitter` of the way from
    /// the cell center toward fully random placement (21 bits of the hash per
    /// axis, plenty of resolution for a position).
    private func point01(_ hash: UInt64, _ axis: Int, _ jitter: Double) -> Double {
        let bits = (hash >> (21 * UInt64(axis))) & 0x1F_FFFF
        let r = Double(bits) / Double(0x1F_FFFF)
        return 0.5 + (r - 0.5) * jitter
    }

    /// A well-mixed 64-bit hash of a cell and the seed (odd-constant spreads
    /// per axis, then the SplitMix64 finalizer to decorrelate neighbors).
    private func cellHash(_ cx: Int, _ cy: Int, _ cz: Int) -> UInt64 {
        var h = seed
        h ^= UInt64(bitPattern: Int64(cx)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(cy)) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= UInt64(bitPattern: Int64(cz)) &* 0x1656_67B1_9E37_79F9
        h ^= h >> 30
        h &*= 0xBF58_476D_1CE4_E5B9
        h ^= h >> 27
        h &*= 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        return h
    }
}

/// Which reading `worley(...)` returns from its cell distances.
public enum WorleyFeature: Sendable {
    /// Distance to the nearest feature point: the classic cell field, dark at
    /// each cell's core and brightening toward its walls.
    case nearest
    /// Distance to the second-nearest point: a blunter, plateaued field that
    /// stays bright across cell interiors.
    case second
    /// The gap between the two (second minus nearest): zero exactly on the
    /// borders between cells, so low values trace the cell walls (threshold it
    /// for crack and vein line work).
    case border
}

public extension Sketch {
    // MARK: Simplex noise

    /// 1D simplex noise at `x`, in `0...1`. A different flavor of the same
    /// idea as `noise()`: smooth, seeded, organic; its grain is more even in
    /// every direction (the classic field carries a faint bias along its grid
    /// axes), and its texture reads slightly crisper at the same scale. Same
    /// seed (`noiseSeed`), separate field, so the two do not correlate.
    func simplexNoise(_ x: Double) -> Double { simplex.value(x, 0) }
    /// 2D simplex noise at `(x, y)`, in `0...1` (see `simplexNoise(_:)`).
    func simplexNoise(_ x: Double, _ y: Double) -> Double { simplex.value(x, y) }
    /// 3D simplex noise at `(x, y, z)`, in `0...1` (see `simplexNoise(_:)`).
    func simplexNoise(_ x: Double, _ y: Double, _ z: Double) -> Double { simplex.value(x, y, z) }

    /// 1D signed simplex noise at `x`, in `-1...1` (see `simplexNoise(_:)`).
    func signedSimplexNoise(_ x: Double) -> Double { simplex.signedValue(x, 0) }
    /// 2D signed simplex noise at `(x, y)`, in `-1...1` (see `simplexNoise(_:)`).
    func signedSimplexNoise(_ x: Double, _ y: Double) -> Double { simplex.signedValue(x, y) }
    /// 3D signed simplex noise at `(x, y, z)`, in `-1...1` (see `simplexNoise(_:)`).
    func signedSimplexNoise(_ x: Double, _ y: Double, _ z: Double) -> Double { simplex.signedValue(x, y, z) }

    // MARK: Worley (cellular) noise

    /// 2D cellular noise at `(x, y)`: the distance to the nearest of a field
    /// of seeded feature points, one per unit cell, which shades space into
    /// organic cells (stone, foam, cracked earth). Roughly `0...1`: zero at
    /// each cell's core, rising toward its walls, occasionally a little above
    /// 1 where cells run sparse. `feature` picks the reading (see
    /// `WorleyFeature`); `jitter` runs the cells from a regular grid (0) to
    /// fully organic (1). Sample on scaled-down coordinates (`x * 0.01`) just
    /// like `noise()`; seeded by `noiseSeed`.
    func worley(_ x: Double, _ y: Double,
                feature: WorleyFeature = .nearest, jitter: Double = 1) -> Double {
        let (f1, f2) = worleyNoise.distances(x, y, jitter: min(max(jitter, 0), 1))
        return worleyReading(f1, f2, feature)
    }

    /// 3D cellular noise at `(x, y, z)` (see `worley(_:_:feature:jitter:)`).
    /// Drift `z` over time and the cells bubble and reform in place.
    func worley(_ x: Double, _ y: Double, _ z: Double,
                feature: WorleyFeature = .nearest, jitter: Double = 1) -> Double {
        let (f1, f2) = worleyNoise.distances(x, y, z, jitter: min(max(jitter, 0), 1))
        return worleyReading(f1, f2, feature)
    }

    private func worleyReading(_ f1: Double, _ f2: Double, _ feature: WorleyFeature) -> Double {
        switch feature {
        case .nearest: return f1
        case .second: return f2
        case .border: return f2 - f1
        }
    }
}
