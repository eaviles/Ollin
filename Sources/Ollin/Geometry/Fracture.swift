import Foundation

/// Breaking a shape into pieces: the filled region is cut into cells that fit
/// back together exactly, the way a dropped tile leaves its own outline behind
/// on the floor.
///
/// The cut is a Voronoi diagram of a handful of seed points inside the shape,
/// so every cell is convex and the cells tile the whole region with no gap and
/// no overlap. `fractured(into:seed:)` spreads the seeds evenly, which reads as
/// a shape that came apart on its own. `fractured(into:around:seed:)` crowds
/// them at a point, which reads as a shape that was hit there: small chips at
/// the impact, long pieces away from it.
///
/// ```swift
/// let tile = Shape(Mesh.polygon(sides: 6, radius: 160).map { $0 * 1 })
/// for piece in tile.fractured(into: 14, seed: 7) {
///     fill(.white)
///     drawShape(piece)
/// }
/// ```
///
/// Pieces are ordinary `Shape`s, so they draw, stroke, hatch, export to SVG,
/// and feed the booleans like any other geometry. Each one carries its own
/// `centroid`, which is what a rigid body wants: move the piece to its centroid
/// and hand the solver the points around it.
public extension Shape {
    /// Break the filled region into `pieces` cells, spread evenly.
    ///
    /// The same `seed` always gives the same break. Fewer pieces come back than
    /// asked for when the shape is small enough that two seeds land in the same
    /// spot, and a concave shape whose cell arrives in two separate islands
    /// gives one piece per island, so the count is a request rather than a
    /// promise. The pieces' areas sum to the shape's own.
    ///
    /// - Parameters:
    ///   - pieces: How many cells to cut, at least one.
    ///   - seed: The seed behind the cut. The same seed repeats a break.
    func fractured(into pieces: Int, seed: Int = 0) -> [Shape] {
        fractured(into: pieces, around: nil, seed: seed)
    }

    /// Break the filled region into `pieces` cells crowded around `impact`.
    ///
    /// The seeds are drawn thickest at `impact` and thin out with distance, so
    /// the break reads as a strike at that point: chips where it landed,
    /// long shards running away from it. The point can sit outside the shape,
    /// which breaks it as if struck off one edge.
    ///
    /// - Parameters:
    ///   - pieces: How many cells to cut, at least one.
    ///   - impact: Where the break starts, in the shape's own coordinates.
    ///   - seed: The seed behind the cut. The same seed repeats a break.
    func fractured(into pieces: Int, around impact: Vector2, seed: Int = 0) -> [Shape] {
        fractured(into: pieces, around: .some(impact), seed: seed)
    }

    private func fractured(into pieces: Int, around impact: Vector2?, seed: Int) -> [Shape] {
        let filled = contours.contains { $0.isClosed && $0.points.count >= 3 }
        guard pieces > 1, filled, let region = bounds,
              region.width > 0, region.height > 0 else {
            return filled ? [self] : []
        }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let sites = fractureSites(count: pieces, in: region, impact: impact, rng: &rng)
        guard sites.count > 1 else { return [self] }

        // The seeds' Voronoi cells tile `region`; each one trimmed to the shape
        // is a piece, and the pieces put back together are the shape again.
        let grown = Rectangle(x: region.x - region.width * 0.5,
                              y: region.y - region.height * 0.5,
                              width: region.width * 2,
                              height: region.height * 2)
        let diagram = PowerDiagram(sites: sites.map { WeightedSite($0) }, bounds: grown)
        let smallest = abs(area) * 1e-6
        var broken: [Shape] = []
        for cell in diagram.cells where !cell.contours.isEmpty {
            for island in cell.intersection(self).separated() where abs(island.area) > smallest {
                broken.append(island)
            }
        }
        return broken.isEmpty ? [self] : broken
    }

    /// Seeds inside the filled region: evenly spread, or crowded at a point.
    private func fractureSites(count: Int, in region: Rectangle, impact: Vector2?,
                               rng: inout SplitMix64) -> [Vector2] {
        var sites: [Vector2] = []
        sites.reserveCapacity(count)
        if let impact, contains(impact) { sites.append(impact) }

        // The reach of a crowded break: far enough that the last ring still
        // lands inside the region wherever the impact is.
        let corners = [region.topLeft, region.topRight, region.bottomLeft, region.bottomRight]
        let reach = corners.map { ($0 - (impact ?? region.center)).length }.max() ?? 1

        while sites.count < count {
            var best: Vector2?
            var bestScore = -Double.infinity
            // Mitchell's best-candidate: a few tries, keep the one standing
            // farthest from the seeds already placed, which spaces them without
            // the cost of a relaxation pass.
            for _ in 0 ..< 8 {
                guard let candidate = fractureCandidate(in: region, impact: impact,
                                                        reach: reach, rng: &rng) else { continue }
                let score = sites.map { ($0 - candidate).lengthSquared }.min() ?? .infinity
                if score > bestScore { bestScore = score; best = candidate }
            }
            guard let best else { break }
            sites.append(best)
        }
        return sites
    }

    /// One seed inside the shape, drawn uniformly or thickest at `impact`.
    private func fractureCandidate(in region: Rectangle, impact: Vector2?, reach: Double,
                                   rng: inout SplitMix64) -> Vector2? {
        for _ in 0 ..< 64 {
            let point: Vector2
            if let impact {
                // Radius as a power of a uniform draw: the exponent pulls the
                // seeds toward the strike, so the chips there are small.
                let u = Double.random(in: 0 ..< 1, using: &rng)
                let radius = reach * pow(u, 1.9)
                let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
                point = impact + Vector2(cos(angle), sin(angle)) * radius
            } else {
                point = Vector2(Double.random(in: region.x ..< region.x + region.width, using: &rng),
                                Double.random(in: region.y ..< region.y + region.height, using: &rng))
            }
            if contains(point) { return point }
        }
        return nil
    }
}
