import Foundation

/// The chips of a terrazzo floor over a region, as geometry a sketch can
/// hold, draw, and plot. The chips come in three size tiers, the largest
/// first, each thrown as darts (Cook, 1986): a chip is placed where its circle
/// clears every chip already placed by `gap`, and a tier ends when it has
/// covered its share of the floor or its darts keep missing. Each chip is a
/// polygon of five to eight corners inside its circle, every corner at its own
/// fraction of the radius, so no two chips are alike and none is regular.
///
/// `Generator.terrazzo` paints a `Terrazzo`: hand it one and the GPU reads
/// these very chips, so an outline stroked from `chips[i].outline` lands on
/// the painted chip, or let it scatter its own over the layer.
///
/// ```swift
/// let floor = Terrazzo.scatter(in: canvasRectangle, chipRadius: 40, seed: 2)
/// drawImage(generate(.terrazzo(chips: floor)).image, 0, 0)
/// noFill(); stroke(Color(white: 0.2))
/// for chip in floor.chips { drawShape(chip.shape) }
/// ```
public struct Terrazzo: Equatable, Sendable {

    /// One chip: a polygon inside a circle.
    public struct Chip: Equatable, Sendable {
        /// The center of the chip's circle.
        public let center: Vector2
        /// The circle's radius: every corner lies within it.
        public let radius: Double
        /// The angle of the first corner, in radians.
        public let rotation: Double
        /// The size tier, 0 the largest.
        public let tier: Int
        /// The index of the chip's color in a palette.
        public let tone: Int
        /// Each corner's distance from the center as a fraction of `radius`,
        /// in `0.72…1`, going around; the count is the number of sides.
        public let corners: [Double]

        public init(center: Vector2, radius: Double, rotation: Double, tier: Int, tone: Int, corners: [Double]) {
            self.center = center
            self.radius = max(radius, 0)
            self.rotation = rotation
            self.tier = max(tier, 0)
            self.tone = max(tone, 0)
            self.corners = corners.count >= 3 ? corners : [1, 1, 1]
        }

        /// The number of sides, five to eight for a scattered chip.
        public var sides: Int { corners.count }

        /// The corners as points, going around from `rotation`.
        public var points: [Vector2] {
            corners.enumerated().map { k, fraction in
                let angle = rotation + Double(k) / Double(corners.count) * 2 * .pi
                return center + Vector2(cos(angle), sin(angle)) * (radius * fraction)
            }
        }

        /// The chip as a closed contour.
        public var outline: Contour { Contour(points, closed: true) }

        /// The chip as a shape, for `drawShape` or a clip.
        public var shape: Shape { Shape(points) }

        /// Whether `point` lies inside the chip.
        public func contains(_ point: Vector2) -> Bool {
            Shape.contains(points, point)
        }
    }

    /// The chips, in the order they were placed: the largest tier first.
    public let chips: [Chip]
    /// The least distance between any two chips' circles.
    public let gap: Double

    public init(chips: [Chip], gap: Double = 0) {
        self.chips = chips
        self.gap = max(gap, 0)
    }

    /// The three tiers' radii as fractions of the largest.
    public static let tierScales = [1.0, 0.55, 0.3]
    /// The share of the covered floor each tier takes.
    public static let tierShares = [0.5, 0.3, 0.2]

    /// Every chip's outline, for stroking or a plotter.
    public var outlines: [Contour] { chips.map(\.outline) }

    /// Chips thrown over `region` from `seed`: three tiers of circles at
    /// `chipRadius` and `tierScales` of it, placed largest first by dart
    /// throwing until together they cover about `density` of the region's
    /// area in the shares `tierShares`, every circle clear of every other by
    /// `gap`. Each chip takes one of `tones` colors by index. The same seed
    /// makes the same floor.
    public static func scatter(in region: Rectangle, chipRadius: Double = 44, density: Double = 0.55,
                               gap: Double = 3, tones: Int = 4, seed: Int = 1) -> Terrazzo {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        return scatter(in: region, chipRadius: chipRadius, density: density, gap: gap, tones: tones, using: &rng)
    }

    /// The generic form of `scatter(in:chipRadius:density:gap:tones:seed:)`,
    /// drawing from any random generator you supply.
    public static func scatter<R: RandomNumberGenerator>(in region: Rectangle, chipRadius: Double = 44,
                                                         density: Double = 0.55, gap: Double = 3,
                                                         tones: Int = 4, using rng: inout R) -> Terrazzo {
        let largest = max(chipRadius, 1)
        let gap = max(gap, 0)
        let density = min(max(density, 0), 0.9)
        let tones = max(tones, 1)
        guard region.width > 0, region.height > 0, density > 0 else { return Terrazzo(chips: [], gap: gap) }

        // A grid of cells the size of the widest reach two chips can have,
        // so a dart checks the nine cells around it and nothing farther.
        let cell = 2 * largest + gap
        let columns = max(1, Int((region.width / cell).rounded(.up)) + 2)
        let rows = max(1, Int((region.height / cell).rounded(.up)) + 2)
        var cells = [[Int]](repeating: [], count: columns * rows)
        var chips: [Chip] = []
        func cellIndex(_ p: Vector2) -> (Int, Int) {
            (min(max(Int(((p.x - region.x) / cell).rounded(.down)) + 1, 0), columns - 1),
             min(max(Int(((p.y - region.y) / cell).rounded(.down)) + 1, 0), rows - 1))
        }
        func clear(_ c: Vector2, _ r: Double) -> Bool {
            let (cx, cy) = cellIndex(c)
            for y in max(cy - 1, 0) ... min(cy + 1, rows - 1) {
                for x in max(cx - 1, 0) ... min(cx + 1, columns - 1) {
                    for index in cells[y * columns + x] {
                        let other = chips[index]
                        if (c - other.center).length < r + other.radius + gap { return false }
                    }
                }
            }
            return true
        }

        let floorArea = region.width * region.height
        for (tier, scale) in tierScales.enumerated() {
            let r = largest * scale
            let target = floorArea * density * tierShares[tier]
            // A chip's own area: its polygon fills about three quarters of its circle.
            let chipArea = 0.75 * .pi * r * r
            var covered = 0.0
            var misses = 0
            while covered < target && misses < 80 {
                let c = Vector2(region.x + Double.random(in: 0 ..< 1, using: &rng) * region.width,
                                region.y + Double.random(in: 0 ..< 1, using: &rng) * region.height)
                guard clear(c, r) else { misses += 1; continue }
                misses = 0
                let sides = Int.random(in: 5 ... 8, using: &rng)
                var corners = (0 ..< sides).map { _ in Double.random(in: 0.72 ... 1, using: &rng) }
                let widest = corners.max() ?? 1
                corners = corners.map { $0 / widest }
                let chip = Chip(center: c, radius: r,
                                rotation: Double.random(in: 0 ..< 2 * .pi, using: &rng),
                                tier: tier, tone: Int.random(in: 0 ..< tones, using: &rng),
                                corners: corners)
                let (cx, cy) = cellIndex(c)
                cells[cy * columns + cx].append(chips.count)
                chips.append(chip)
                covered += chipArea
            }
        }
        return Terrazzo(chips: chips, gap: gap)
    }
}
