import Foundation

// The colors an image is *made of* are a better palette than any list someone
// else curated, so the palette comes out of the picture: cluster the pixels in
// a perceptual space and keep each cluster's average.
//
// Clustering runs in OKLab rather than sRGB. Distance in sRGB is not distance
// to the eye, so sRGB clusters split the greens nobody can tell apart and
// merge the blues everybody can.
public extension Palette {
    /// The `count` colors an image is mostly made of, most-used first.
    ///
    /// ```swift
    /// let photo = loadImage("beach.jpg")!
    /// let p = Palette(extractedFrom: photo, count: 5)
    /// ```
    ///
    /// Fully deterministic: the same image, `count`, and `seed` always give
    /// the same palette, so an extracted palette is safe to snapshot and to
    /// carry in an export's recipe. Change `seed` to shake the clustering out
    /// of a local minimum when a result looks off.
    ///
    /// Transparent pixels are ignored. An image with fewer distinct colors
    /// than `count` yields only the colors it has, and a texture-backed image
    /// (a video frame, a Syphon feed) has no readable pixels, so it yields an
    /// empty palette; call `snapshot()` on the feed first.
    init(extractedFrom image: Image, count: Int = 5, seed: Int = 0) {
        guard count > 0 else { self.init([]); return }
        let samples = Palette.samples(of: image)
        guard !samples.isEmpty else { self.init([]); return }
        self.init(Palette.cluster(samples, into: count, seed: UInt64(bitPattern: Int64(seed))))
    }
}

// MARK: - Sampling

private extension Palette {
    /// A pixel and how many times it occurred, so a big image costs the same
    /// as a small one and the clustering still sees the true color weights.
    struct Sample {
        var lab: OKLab
        var weight: Double
    }

    /// Read at most `maxSamples` pixels on an even grid. A full-resolution
    /// read would dominate the cost of clustering without changing the answer:
    /// a palette is a statement about an image's broad color mass.
    static func samples(of image: Image, maxSamples: Int = 16_384) -> [Sample] {
        guard image.width > 0, image.height > 0 else { return [] }
        let total = image.width * image.height
        let stride = max(1, Int((Double(total) / Double(maxSamples)).squareRoot().rounded(.up)))

        // Merge identical pixels as we go: photographs repeat colors heavily,
        // and flat art repeats them almost entirely.
        var counts: [Color: Double] = [:]
        for y in Swift.stride(from: 0, to: image.height, by: stride) {
            for x in Swift.stride(from: 0, to: image.width, by: stride) {
                let color = image[x, y]
                guard color.alpha > 0.5 else { continue }
                counts[color.withAlpha(1), default: 0] += 1
            }
        }
        // Sort so the clustering sees a fixed order regardless of how the
        // dictionary happened to hash: determinism is a promise here.
        return counts
            .map { Sample(lab: OKLab($0.key), weight: $0.value) }
            .sorted { ($0.lab.l, $0.lab.a, $0.lab.b) < ($1.lab.l, $1.lab.a, $1.lab.b) }
    }
}

// MARK: - Weighted k-means

private extension Palette {
    static func cluster(_ samples: [Sample], into count: Int, seed: UInt64) -> [Color] {
        // Fewer distinct colors than clusters: there is nothing to cluster,
        // so hand back what the image actually has, most-used first.
        guard samples.count > count else {
            return samples.sorted { $0.weight > $1.weight }.map { Color($0.lab) }
        }

        var rng = SplitMix64(seed: seed &+ 0x9E37_79B9)
        var centers = seedCenters(samples, count: count, rng: &rng)
        var assignment = [Int](repeating: -1, count: samples.count)

        // Lloyd's algorithm. Twenty passes is well past where the assignment
        // stops moving on real images; the early exit is what usually ends it.
        for _ in 0..<20 {
            var changed = false
            for (i, sample) in samples.enumerated() {
                let nearest = nearestCenter(to: sample.lab, in: centers)
                if assignment[i] != nearest { assignment[i] = nearest; changed = true }
            }
            if !changed { break }

            var sums = [OKLab](repeating: OKLab(l: 0, a: 0, b: 0), count: count)
            var weights = [Double](repeating: 0, count: count)
            for (i, sample) in samples.enumerated() {
                let c = assignment[i]
                sums[c].l += sample.lab.l * sample.weight
                sums[c].a += sample.lab.a * sample.weight
                sums[c].b += sample.lab.b * sample.weight
                weights[c] += sample.weight
            }
            for c in 0..<count where weights[c] > 0 {
                centers[c] = OKLab(l: sums[c].l / weights[c],
                                   a: sums[c].a / weights[c],
                                   b: sums[c].b / weights[c])
            }
            // An emptied cluster would otherwise stay empty forever. Move it
            // onto the sample that the current centers explain worst.
            for c in 0..<count where weights[c] == 0 {
                if let far = farthestSample(samples, from: centers) { centers[c] = far }
            }
        }

        // Order by how much of the image each cluster accounts for, so
        // `palette[0]` is the color you'd name if asked.
        var mass = [Double](repeating: 0, count: count)
        for (i, sample) in samples.enumerated() where assignment[i] >= 0 {
            mass[assignment[i]] += sample.weight
        }
        return zip(centers, mass)
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { Color($0.0) }
    }

    /// k-means++ seeding: the first center is a random sample, and each next
    /// one is drawn with probability proportional to its squared distance from
    /// the centers already chosen. Plain random seeding lands two centers in
    /// the same blob often enough to spoil a palette.
    static func seedCenters(_ samples: [Sample], count: Int,
                            rng: inout SplitMix64) -> [OKLab] {
        var centers = [samples[Int(rng.next() % UInt64(samples.count))].lab]
        var distances = samples.map { squaredDistance($0.lab, centers[0]) }

        while centers.count < count {
            let weighted = zip(samples, distances).map { $0.weight * $1 }
            let total = weighted.reduce(0, +)
            var chosen = samples.count - 1
            if total > 0 {
                // A uniform draw scaled by the total, walked until it runs out.
                var target = Double(rng.next() >> 11) / Double(1 << 53) * total
                for (i, w) in weighted.enumerated() {
                    target -= w
                    if target <= 0 { chosen = i; break }
                }
            } else {
                chosen = Int(rng.next() % UInt64(samples.count))
            }
            centers.append(samples[chosen].lab)
            for i in samples.indices {
                distances[i] = min(distances[i], squaredDistance(samples[i].lab, centers[centers.count - 1]))
            }
        }
        return centers
    }

    static func farthestSample(_ samples: [Sample], from centers: [OKLab]) -> OKLab? {
        samples.max {
            squaredDistance($0.lab, centers[nearestCenter(to: $0.lab, in: centers)])
                < squaredDistance($1.lab, centers[nearestCenter(to: $1.lab, in: centers)])
        }?.lab
    }

    static func nearestCenter(to lab: OKLab, in centers: [OKLab]) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for (i, center) in centers.enumerated() {
            let d = squaredDistance(lab, center)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    static func squaredDistance(_ x: OKLab, _ y: OKLab) -> Double {
        let dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b
        return dl * dl + da * da + db * db
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The `count` colors an image is mostly made of, most-used first:
    /// `extractPalette(from: photo)`.
    func extractPalette(from image: Image, count: Int = 5, seed: Int = 0) -> Palette {
        Palette(extractedFrom: image, count: count, seed: seed)
    }
}
