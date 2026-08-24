import Foundation

/// A site with a weight, for a `PowerDiagram`.
///
/// The weight is not a radius and not an importance. It is subtracted from the
/// squared distance, so a site with a larger weight reaches further, and only the
/// *differences* between weights matter: adding the same amount to every weight
/// leaves the diagram exactly as it was.
public struct WeightedSite: Equatable, Sendable {
    public var point: Vector2
    public var weight: Double

    public init(_ point: Vector2, weight: Double = 0) {
        self.point = point
        self.weight = weight
    }

    /// The site of a circle: its center, weighted by the square of its radius.
    ///
    /// This is the weighting the diagram was made for. The power of a point on the
    /// circle is then exactly zero, which is why a circle that touches no other
    /// ends up inside its own cell.
    public init(_ circle: Circle) {
        point = circle.center
        weight = circle.radius * circle.radius
    }

    /// The power of `point` with respect to this site: the squared distance, less
    /// the weight. The diagram gives each point to the site whose power is least.
    public func power(to other: Vector2) -> Double {
        (other - point).lengthSquared - weight
    }
}

/// A power diagram, also called a Laguerre diagram: a Voronoi diagram where each
/// site carries a weight, and a point belongs to the site whose *power* is least
/// rather than whose distance is least.
///
/// Two facts follow from that one change, and both are why it is worth having:
/// the boundary between two cells is still a straight line, so the cells are still
/// convex polygons, and a site can lose entirely, ending up with no cell at all. A
/// small circle swallowed by a large one is the everyday case.
///
/// ```swift
/// let circles = packCircles(count: 60, minRadius: 10, maxRadius: 70)
/// for cell in powerDiagram(of: circles).cells { drawShape(cell) }
/// ```
///
/// Every cell is worked out by cutting the bounds with one half-plane per other
/// site, so the cost grows with the square of the site count. A few hundred sites
/// is comfortable; a few thousand is not.
public struct PowerDiagram: Sendable {
    /// The sites, in the order they were given.
    public let sites: [WeightedSite]
    /// The region the cells are cut to.
    public let bounds: Rectangle
    /// One cell per site, in the same order. A site that lost everything has an
    /// empty `Shape`, which draws nothing.
    public let cells: [Shape]

    /// Cut `bounds` into one cell per site.
    public init(sites: [WeightedSite], bounds: Rectangle) {
        self.sites = sites
        self.bounds = bounds
        guard !sites.isEmpty else {
            cells = []
            return
        }
        let box = [Vector2(bounds.x, bounds.y),
                   Vector2(bounds.x + bounds.width, bounds.y),
                   Vector2(bounds.x + bounds.width, bounds.y + bounds.height),
                   Vector2(bounds.x, bounds.y + bounds.height)]
        cells = sites.indices.map { i in
            var polygon = box
            for j in sites.indices where j != i {
                // A point belongs to i rather than j when its power to i is the
                // smaller, and that comparison is linear in the point: the squared
                // terms cancel, leaving one half-plane per pair.
                let normal = (sites[j].point - sites[i].point) * 2
                let offset = (sites[j].point.lengthSquared - sites[j].weight)
                    - (sites[i].point.lengthSquared - sites[i].weight)
                if normal.lengthSquared < 1e-24 {
                    // Two sites at the same place: the heavier one takes it all.
                    if offset < 0 { polygon = [] }
                    continue
                }
                polygon = PowerDiagram.clip(polygon, keeping: normal, atMost: offset)
                if polygon.isEmpty { break }
            }
            return polygon.count >= 3 ? Shape(polygon) : Shape(contours: [])
        }
    }

    /// The cell of site `i`, empty when that site lost everything.
    public func cell(_ i: Int) -> Shape { cells[i] }

    /// The site `point` belongs to: the one whose power is least. Nil when there
    /// are no sites. Answered from the sites themselves rather than by looking in
    /// the polygons, so it is exact and does not care about `bounds`.
    public func site(owning point: Vector2) -> Int? {
        guard !sites.isEmpty else { return nil }
        var best = 0
        var least = sites[0].power(to: point)
        for i in 1 ..< sites.count {
            let power = sites[i].power(to: point)
            if power < least { least = power; best = i }
        }
        return best
    }

    /// Cut a convex polygon down to the side of a line, keeping the points with
    /// `normal · p <= offset`.
    private static func clip(_ polygon: [Vector2], keeping normal: Vector2,
                             atMost offset: Double) -> [Vector2] {
        guard !polygon.isEmpty else { return [] }
        var out: [Vector2] = []
        out.reserveCapacity(polygon.count + 1)
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let da = normal.dot(a) - offset, db = normal.dot(b) - offset
            if da <= 0 { out.append(a) }
            if (da < 0 && db > 0) || (da > 0 && db < 0) {
                out.append(a + (b - a) * (da / (da - db)))
            }
        }
        return out
    }
}

/// The power diagram of `sites` inside `bounds`.
public func powerDiagram(sites: [WeightedSite], in bounds: Rectangle) -> PowerDiagram {
    PowerDiagram(sites: sites, bounds: bounds)
}

public extension Sketch {
    /// The power diagram of `sites`, cut to `bounds` (the whole canvas by default).
    func powerDiagram(sites: [WeightedSite], in bounds: Rectangle? = nil) -> PowerDiagram {
        PowerDiagram(sites: sites, bounds: bounds ?? canvasRectangle)
    }

    /// The power diagram of a set of circles, each weighted by the square of its
    /// radius. Circles that touch nothing else end up inside their own cells,
    /// which is what makes this the useful weighting.
    func powerDiagram(of circles: [Circle], in bounds: Rectangle? = nil) -> PowerDiagram {
        PowerDiagram(sites: circles.map(WeightedSite.init), bounds: bounds ?? canvasRectangle)
    }

    /// Draw every cell of the power diagram of `circles` with the current
    /// `fill`/`stroke`. For per-cell color, hold the diagram and iterate `cells`.
    func drawPowerDiagram(of circles: [Circle], in bounds: Rectangle? = nil) {
        for cell in powerDiagram(of: circles, in: bounds).cells { drawShape(cell) }
    }
}
