import Foundation

/// The blooms of a corrosion over a region: the blobs a rust bloom or a
/// verdigris patina grows from, as geometry a sketch can hold, draw, and plot.
/// Each `Blob` is a circle whose radius wavers around it in two octaves (four
/// harmonics of its angle, the low pair the big lobes and the high pair the
/// ragged edge), with two nested masses of the same waver at smaller scales
/// shifted off center, the darker cores of the bloom, and a few blisters, the
/// small raised circles inside it. `scatter(in:count:radius:seed:)` throws the
/// blooms over a region from a seed, keeping their centers apart so they
/// overlap at their edges and never stack.
///
/// The generators `Generator.rust` and `Generator.verdigris` paint a `Patina`:
/// hand them one and the GPU reads these very blobs, so an outline stroked from
/// `blobs[i].outline` lands on the painted bloom, or let them scatter their
/// own over the layer.
///
/// ```swift
/// let blooms = Patina.scatter(in: canvasRectangle, count: 12, seed: 3)
/// drawImage(generate(.rust(blobs: blooms)).image, 0, 0)
/// stroke(.black); noFill()
/// for blob in blooms.blobs { drawPolygon(blob.outline.points) }
/// ```
public struct Patina: Equatable, Sendable {

    /// One bloom: a wavering circle with nested masses and blisters.
    public struct Blob: Equatable, Sendable {
        /// The center the outline wavers around.
        public let center: Vector2
        /// The mean radius: the outline's radius before its waver.
        public let radius: Double
        /// The amplitudes of the four harmonics that shape the outline, as
        /// fractions of `radius`; their waves around the blob are `harmonics`.
        public let amplitudes: SIMD4<Double>
        /// Where each harmonic's wave starts, in radians.
        public let phases: SIMD4<Double>
        /// Where the nested masses sit, as a fraction of the radius from the
        /// center: the first mass at this offset, the second at 1.7 times it.
        public let massOffset: Vector2
        /// The blisters, small circles inside the bloom.
        public let blisters: [Circle]
        /// A draw in `0…1` that picks the blob's tone within a palette.
        public let tone: Double

        /// The number of waves each harmonic makes around the blob: two and
        /// three for the big lobes, five and eight for the ragged edge.
        public static let harmonics = SIMD4<Double>(2, 3, 5, 8)
        /// The nested masses' radii as fractions of the blob's.
        public static let massScales = [0.62, 0.36]

        public init(center: Vector2, radius: Double, amplitudes: SIMD4<Double>, phases: SIMD4<Double>,
                    massOffset: Vector2, blisters: [Circle], tone: Double) {
            self.center = center
            self.radius = max(radius, 0)
            self.amplitudes = amplitudes
            self.phases = phases
            self.massOffset = massOffset
            self.blisters = blisters
            self.tone = min(max(tone, 0), 1)
        }

        /// How far the outline wavers from `radius`, as a fraction of it: the
        /// outline's radius stays within `radius * (1 ± swing)`.
        public var swing: Double { abs(amplitudes[0]) + abs(amplitudes[1]) + abs(amplitudes[2]) + abs(amplitudes[3]) }

        /// The outline's radius at `angle` around the center: the mean radius
        /// times one plus the four harmonics' waves.
        public func boundaryRadius(at angle: Double) -> Double {
            radius * (1 + Blob.waver(angle, amplitudes: amplitudes, phases: phases))
        }

        /// Whether `point` lies inside the outline.
        public func contains(_ point: Vector2) -> Bool {
            let d = point - center
            return d.length <= boundaryRadius(at: atan2(d.y, d.x))
        }

        /// The outline as a closed contour of 96 points.
        public var outline: Contour {
            Blob.ring(center: center, radius: radius, amplitudes: amplitudes, phases: phases)
        }

        /// The nested masses as closed contours, the larger first: the same
        /// waver at `massScales` of the radius, each with its phases turned,
        /// around centers moved by `massOffset`.
        public var masses: [Contour] {
            Blob.massScales.enumerated().map { k, scale in
                Blob.ring(center: massCenter(k), radius: radius * scale,
                          amplitudes: amplitudes, phases: phases + SIMD4(repeating: 0.9 * Double(k + 1)))
            }
        }

        /// The center of mass `k`.
        func massCenter(_ k: Int) -> Vector2 {
            center + massOffset * (radius * (k == 0 ? 1 : 1.7))
        }

        static func waver(_ angle: Double, amplitudes: SIMD4<Double>, phases: SIMD4<Double>) -> Double {
            var sum = 0.0
            for k in 0 ..< 4 {
                sum += amplitudes[k] * sin(harmonics[k] * angle + phases[k])
            }
            return sum
        }

        static func ring(center: Vector2, radius: Double, amplitudes: SIMD4<Double>, phases: SIMD4<Double>) -> Contour {
            let count = 96
            let points = (0 ..< count).map { i -> Vector2 in
                let angle = Double(i) / Double(count) * 2 * .pi
                let r = radius * (1 + waver(angle, amplitudes: amplitudes, phases: phases))
                return center + Vector2(cos(angle), sin(angle)) * r
            }
            return Contour(points, closed: true)
        }
    }

    /// The blooms, in the order they were placed.
    public let blobs: [Blob]

    public init(blobs: [Blob]) {
        self.blobs = blobs
    }

    /// Every bloom's outline, for stroking or a plotter.
    public var outlines: [Contour] { blobs.map(\.outline) }

    /// Up to `count` blooms thrown over `region` from `seed`, each with a mean
    /// radius drawn from `radius`. A bloom is placed where its center is at
    /// least three quarters of the two radii away from every bloom already
    /// placed, so blooms overlap at their ragged edges and never stack; a
    /// crowded region takes fewer than `count`. The same seed makes the same
    /// patina, down to every blister.
    public static func scatter(in region: Rectangle, count: Int = 12,
                               radius: ClosedRange<Double> = 40 ... 140, seed: Int = 1) -> Patina {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        return scatter(in: region, count: count, radius: radius, using: &rng)
    }

    /// The generic form of `scatter(in:count:radius:seed:)`, drawing from any
    /// random generator you supply.
    public static func scatter<R: RandomNumberGenerator>(in region: Rectangle, count: Int = 12,
                                                         radius: ClosedRange<Double> = 40 ... 140,
                                                         using rng: inout R) -> Patina {
        guard count > 0, region.width > 0, region.height > 0 else { return Patina(blobs: []) }
        let lo = max(min(radius.lowerBound, radius.upperBound), 1)
        let hi = max(radius.upperBound, lo)
        var blobs: [Blob] = []
        blobs.reserveCapacity(count)
        for _ in 0 ..< count {
            var placed: (Vector2, Double)?
            for _ in 0 ..< 40 {
                let c = Vector2(region.x + Double.random(in: 0 ..< 1, using: &rng) * region.width,
                                region.y + Double.random(in: 0 ..< 1, using: &rng) * region.height)
                let r = Double.random(in: lo ... hi, using: &rng)
                let clear = blobs.allSatisfy { (c - $0.center).length >= 0.75 * (r + $0.radius) }
                if clear { placed = (c, r); break }
            }
            guard let (center, r) = placed else { continue }
            let amplitudes = SIMD4(Double.random(in: 0.08 ... 0.18, using: &rng),
                                   Double.random(in: 0.06 ... 0.14, using: &rng),
                                   Double.random(in: 0.03 ... 0.07, using: &rng),
                                   Double.random(in: 0.02 ... 0.05, using: &rng))
            let phases = SIMD4(Double.random(in: 0 ..< 2 * .pi, using: &rng),
                               Double.random(in: 0 ..< 2 * .pi, using: &rng),
                               Double.random(in: 0 ..< 2 * .pi, using: &rng),
                               Double.random(in: 0 ..< 2 * .pi, using: &rng))
            let offsetAngle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
            let offset = Vector2(cos(offsetAngle), sin(offsetAngle)) * Double.random(in: 0.08 ... 0.2, using: &rng)
            let blisterCount = Int.random(in: 2 ... 4, using: &rng)
            let blisters = (0 ..< blisterCount).map { _ -> Circle in
                let a = Double.random(in: 0 ..< 2 * .pi, using: &rng)
                let d = Double.random(in: 0.15 ... 0.6, using: &rng) * r
                return Circle(center: center + Vector2(cos(a), sin(a)) * d,
                              radius: Double.random(in: 0.06 ... 0.13, using: &rng) * r)
            }
            blobs.append(Blob(center: center, radius: r, amplitudes: amplitudes, phases: phases,
                              massOffset: offset, blisters: blisters,
                              tone: Double.random(in: 0 ..< 1, using: &rng)))
        }
        return Patina(blobs: blobs)
    }
}
