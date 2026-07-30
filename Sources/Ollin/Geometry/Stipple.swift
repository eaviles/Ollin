import Foundation

/// Weighted-Voronoi stippling: place `count` dots so their local density
/// reproduces an image's tone. Dark areas pack dots tightly, light areas
/// spread them out, and the result reads as the picture itself: the classic
/// hand-stippled illustration look, and (because the output is just points)
/// a natural feed for the pen-plotter, hatching, and SVG paths.
///
/// The algorithm is Secord's weighted centroidal Voronoi iteration: seed the
/// dots by rejection-sampling the darkness, then repeatedly move every dot to
/// the *darkness-weighted* centroid of its Voronoi cell. Each pass evens the
/// spacing while the weighting holds the dots to the tone, converging on a
/// stipple that is locally blue-noise-even yet globally image-shaped.
///
/// ```swift
/// var rng = SplitMix64(seed: 7)
/// let dots = stipple(picture, count: 4000,
///                    in: Rectangle(fitting: picture.size, in: bounds),
///                    using: &rng)
/// for d in dots { drawCircle(center: d, radius: 2) }
/// ```
///
/// Deterministic given (input, count, seed), so a stipple is snapshot- and
/// recipe-safe. It's setup-time work (the iteration sweeps every pixel), not
/// per-frame: compute once and hold the points.

/// Stipple an image: `count` dots whose density follows the image's darkness
/// (1 − linear luminance, scaled by alpha, so transparent pixels carry no
/// ink). The image is stretched over `bounds`; pass a `Rectangle(fitting:in:)`
/// of the image's size to keep its aspect.
///
/// An image with no ink at all (fully white or transparent, or a texture-backed
/// image with no CPU pixels) yields an empty array.
///
/// - Parameters:
///   - image: The picture whose tone the dots reproduce.
///   - count: How many dots to place.
///   - bounds: The rectangle the image is mapped onto and the dots land in.
///   - iterations: Relaxation passes; 40 (the default) is visually converged,
///     fewer keeps more of the initial scatter's grain.
///   - rng: The random source for the initial scatter; seed it to reproduce.
/// - Returns: The dot positions.
public func stipple<R: RandomNumberGenerator>(
    _ image: Image,
    count: Int,
    in bounds: Rectangle,
    iterations: Int = 40,
    using rng: inout R
) -> [Vector2] {
    guard count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
    guard image.width > 0, image.height > 0 else { return [] }

    let (gridWidth, gridHeight) = stippleGridSize(count: count, bounds: bounds)
    var density = [Double](repeating: 0, count: gridWidth * gridHeight)
    for gy in 0 ..< gridHeight {
        let py = Swift.min(Int((Double(gy) + 0.5) / Double(gridHeight) * Double(image.height)),
                           image.height - 1)
        for gx in 0 ..< gridWidth {
            let px = Swift.min(Int((Double(gx) + 0.5) / Double(gridWidth) * Double(image.width)),
                               image.width - 1)
            let c = image[px, py]
            guard c.alpha > 0 else { continue }
            // The subscript already returns straight color; scale the ink by
            // coverage so soft edges stipple lighter.
            density[gy * gridWidth + gx] = (1 - c.luminance) * c.alpha
        }
    }
    return stippleGrid(count: count, bounds: bounds, iterations: iterations,
                       gridWidth: gridWidth, gridHeight: gridHeight,
                       density: density, using: &rng)
}

/// Stipple a density function: `count` dots packed where `density` is high and
/// spread where it's low. The function is sampled in `bounds` coordinates and
/// clamped at zero (0 = keep out, 1 = densest); any field works: noise, a
/// distance falloff, a math function.
///
/// ```swift
/// var rng = SplitMix64(seed: 3)
/// let dots = stipple(count: 3000, in: bounds, using: &rng) { p in
///     1 - p.distance(to: center) / 400   // a soft disk of dots
/// }
/// ```
///
/// A density that is zero everywhere yields an empty array.
///
/// - Parameters:
///   - count: How many dots to place.
///   - bounds: The rectangle the dots land in.
///   - iterations: Relaxation passes; 40 (the default) is visually converged.
///   - rng: The random source for the initial scatter; seed it to reproduce.
///   - density: The relative dot density at a point; sampled once up front.
/// - Returns: The dot positions.
public func stipple<R: RandomNumberGenerator>(
    count: Int,
    in bounds: Rectangle,
    iterations: Int = 40,
    using rng: inout R,
    density: (Vector2) -> Double
) -> [Vector2] {
    guard count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
    let (gridWidth, gridHeight) = stippleGridSize(count: count, bounds: bounds)
    var grid = [Double](repeating: 0, count: gridWidth * gridHeight)
    let pixelWidth = bounds.width / Double(gridWidth)
    let pixelHeight = bounds.height / Double(gridHeight)
    for gy in 0 ..< gridHeight {
        let y = bounds.y + (Double(gy) + 0.5) * pixelHeight
        for gx in 0 ..< gridWidth {
            let x = bounds.x + (Double(gx) + 0.5) * pixelWidth
            grid[gy * gridWidth + gx] = Swift.max(density(Vector2(x, y)), 0)
        }
    }
    return stippleGrid(count: count, bounds: bounds, iterations: iterations,
                       gridWidth: gridWidth, gridHeight: gridHeight,
                       density: grid, using: &rng)
}

/// The working-grid resolution: enough pixels that each dot's cell averages a
/// few hundred samples (the centroid accuracy Secord's method wants), capped
/// so huge counts stay tractable.
private func stippleGridSize(count: Int, bounds: Rectangle) -> (Int, Int) {
    let target = Double(Swift.min(Swift.max(count * 256, 65_536), 2_097_152))
    let aspect = bounds.width / bounds.height
    let w = Swift.max(Int((target * aspect).squareRoot().rounded()), 1)
    let h = Swift.max(Int((target / Double(w)).rounded()), 1)
    return (w, h)
}

/// The shared worker: rejection-sample the initial dots from `density`, then
/// run weighted-Lloyd passes, each assigning every ink-bearing grid pixel to
/// its nearest dot (bucket-grid accelerated, fixed scan order so the result
/// is deterministic) and moving each dot to its cell's weighted centroid.
private func stippleGrid<R: RandomNumberGenerator>(
    count: Int,
    bounds: Rectangle,
    iterations: Int,
    gridWidth: Int,
    gridHeight: Int,
    density: [Double],
    using rng: inout R
) -> [Vector2] {
    guard let maxDensity = density.max(), maxDensity > 0 else { return [] }

    let pixelWidth = bounds.width / Double(gridWidth)
    let pixelHeight = bounds.height / Double(gridHeight)

    // Initial scatter: throw darts at the grid, keeping each in proportion to
    // its pixel's density, jittered inside the pixel. The cap only matters for
    // near-empty densities, where uniform fill-in keeps the call total.
    var sites: [Vector2] = []
    sites.reserveCapacity(count)
    var attempts = 0
    let maxAttempts = Swift.max(count * 400, 20_000)
    while sites.count < count && attempts < maxAttempts {
        attempts += 1
        let gx = Int.random(in: 0 ..< gridWidth, using: &rng)
        let gy = Int.random(in: 0 ..< gridHeight, using: &rng)
        guard Double.random(in: 0 ..< 1, using: &rng) * maxDensity < density[gy * gridWidth + gx] else { continue }
        sites.append(Vector2(bounds.x + (Double(gx) + Double.random(in: 0 ..< 1, using: &rng)) * pixelWidth,
                             bounds.y + (Double(gy) + Double.random(in: 0 ..< 1, using: &rng)) * pixelHeight))
    }
    while sites.count < count {
        sites.append(Vector2(bounds.x + Double.random(in: 0 ..< 1, using: &rng) * bounds.width,
                             bounds.y + Double.random(in: 0 ..< 1, using: &rng) * bounds.height))
    }

    guard iterations > 0 else { return sites }

    // Site buckets sized to the average dot spacing, so a nearest-dot query
    // scans a handful of neighbors.
    let bucketSide = (bounds.width * bounds.height / Double(count)).squareRoot()
    let bucketCols = Swift.max(Int((bounds.width / bucketSide).rounded(.up)), 1)
    let bucketRows = Swift.max(Int((bounds.height / bucketSide).rounded(.up)), 1)
    let maxRing = Swift.max(bucketCols, bucketRows)

    var weight = [Double](repeating: 0, count: count)
    var weightedX = [Double](repeating: 0, count: count)
    var weightedY = [Double](repeating: 0, count: count)

    for _ in 0 ..< iterations {
        // Rebuild the buckets (sites move every pass). Filling in site order
        // keeps within-bucket order ascending, so ties break deterministically.
        var buckets = [[Int]](repeating: [], count: bucketCols * bucketRows)
        for (i, s) in sites.enumerated() {
            let bx = Swift.min(Swift.max(Int((s.x - bounds.x) / bucketSide), 0), bucketCols - 1)
            let by = Swift.min(Swift.max(Int((s.y - bounds.y) / bucketSide), 0), bucketRows - 1)
            buckets[by * bucketCols + bx].append(i)
        }

        for i in 0 ..< count { weight[i] = 0; weightedX[i] = 0; weightedY[i] = 0 }

        for gy in 0 ..< gridHeight {
            let y = bounds.y + (Double(gy) + 0.5) * pixelHeight
            for gx in 0 ..< gridWidth {
                let d = density[gy * gridWidth + gx]
                guard d > 0 else { continue }
                let x = bounds.x + (Double(gx) + 0.5) * pixelWidth
                let p = Vector2(x, y)
                let bx = Swift.min(Swift.max(Int((x - bounds.x) / bucketSide), 0), bucketCols - 1)
                let by = Swift.min(Swift.max(Int((y - bounds.y) / bucketSide), 0), bucketRows - 1)

                // Expanding-ring nearest-dot search. A dot in ring r is at
                // least (r−1)·bucketSide from anywhere in the center bucket,
                // so before scanning ring r it's safe to stop once the best
                // find beats that bound (rings 0 and 1 are always scanned).
                var best = -1
                var bestDistance = Double.infinity
                var ring = 0
                while ring <= maxRing {
                    if best >= 0, bestDistance.squareRoot() <= Double(ring - 1) * bucketSide { break }
                    let yLo = by - ring, yHi = by + ring
                    for cy in yLo ... yHi {
                        guard cy >= 0, cy < bucketRows else { continue }
                        let onYEdge = (cy == yLo || cy == yHi)
                        var cx = bx - ring
                        while cx <= bx + ring {
                            if cx >= 0, cx < bucketCols {
                                for i in buckets[cy * bucketCols + cx] {
                                    let dist = sites[i].distanceSquared(to: p)
                                    if dist < bestDistance { bestDistance = dist; best = i }
                                }
                            }
                            // Interior rows visit only the ring's two edge columns.
                            cx += onYEdge || ring == 0 ? 1 : 2 * ring
                        }
                    }
                    ring += 1
                }
                if best >= 0 {
                    weight[best] += d
                    weightedX[best] += d * x
                    weightedY[best] += d * y
                }
            }
        }

        // Move each dot to its cell's darkness-weighted centroid; a dot whose
        // cell caught no ink stays put.
        for i in 0 ..< count where weight[i] > 0 {
            sites[i] = Vector2(weightedX[i] / weight[i], weightedY[i] / weight[i])
        }
    }
    return sites
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Stipple `image` with `count` dots inside `bounds` (the whole canvas by
    /// default): dots pack where the picture is dark and thin out where it's
    /// light, so the scatter reads as the image. Driven by the seeded `random`,
    /// so `seed(_:)` reproduces the stipple. Setup-time work: compute once and
    /// hold the points.
    func stipple(_ image: Image,
                 count: Int,
                 in bounds: Rectangle? = nil,
                 iterations: Int = 40) -> [Vector2] {
        Ollin.stipple(image, count: count,
                      in: bounds ?? canvasRectangle,
                      iterations: iterations, using: &rng)
    }

    /// Stipple a density field with `count` dots inside `bounds` (the whole
    /// canvas by default): any function of position works (noise, a falloff,
    /// pure math), sampled once up front. Driven by the seeded `random`, so
    /// `seed(_:)` reproduces the stipple.
    func stipple(count: Int,
                 in bounds: Rectangle? = nil,
                 iterations: Int = 40,
                 density: (Vector2) -> Double) -> [Vector2] {
        Ollin.stipple(count: count,
                      in: bounds ?? canvasRectangle,
                      iterations: iterations, using: &rng, density: density)
    }
}
