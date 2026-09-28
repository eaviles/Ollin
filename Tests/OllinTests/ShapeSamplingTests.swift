import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on scattering points inside a `Shape` and along its
/// outline. The invariants are about area and length, which is the whole
/// point: a region receives points in proportion to its area under the shape's
/// own fill rule (a hole receives none, an island is not forgotten), an edge
/// receives them in proportion to its length, and the blue-noise form keeps
/// its distance while still filling a shape too thin for darts thrown around
/// its points to land in. Every draw is seeded, so a run repeats. No GPU.
@Suite
struct ShapeSamplingTests {

    // MARK: - Shapes picked to be awkward

    /// A square frame: a 100-point square with a 40-point square hole in the
    /// middle. Its fill is the four bands around the hole.
    static func frame() -> Shape {
        Shape(outer: [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)],
              holes: [[Vector2(30, 30), Vector2(70, 30), Vector2(70, 70), Vector2(30, 70)]])
    }

    static let hole = Shape([Vector2(30, 30), Vector2(70, 30), Vector2(70, 70), Vector2(30, 70)])

    /// Two separate squares of unequal area, one shape.
    static func islands() -> Shape {
        Shape(contours: [
            Contour([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)]),
            Contour([Vector2(200, 0), Vector2(260, 0), Vector2(260, 60), Vector2(200, 60)]),
        ])
    }

    /// A bar 400 long and 6 tall: thinner than the annulus a dart is thrown in,
    /// so nearly every dart thrown around a placed point lands outside it.
    static func bar() -> Shape {
        Shape([Vector2(0, 0), Vector2(400, 0), Vector2(400, 6), Vector2(0, 6)])
    }

    /// The bands of the frame, by which side of the hole a point lies on. The
    /// corners go to the left and right bands, so the four cover the fill.
    static func band(of p: Vector2) -> Int {
        if p.x < 30 { return 0 }
        if p.x > 70 { return 1 }
        return p.y < 30 ? 2 : 3
    }

    /// The bands' areas in the same order: two 30 by 100 sides, two 40 by 30
    /// strips.
    static let bandAreas = [3000.0, 3000.0, 1200.0, 1200.0]

    /// Pearson's statistic for observed counts against expected shares.
    static func chiSquare(_ counts: [Int], shares: [Double]) -> Double {
        let n = Double(counts.reduce(0, +))
        let total = shares.reduce(0, +)
        return zip(counts, shares).reduce(0) { sum, pair in
            let expected = n * pair.1 / total
            let d = Double(pair.0) - expected
            return sum + d * d / expected
        }
    }

    /// The distance from `p` to the nearest segment of the shape's outline.
    static func outlineDistance(_ shape: Shape, _ p: Vector2) -> Double {
        var best = Double.infinity
        for contour in shape.contours {
            let pts = contour.points
            let count = contour.isClosed ? pts.count : pts.count - 1
            for i in 0 ..< count {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                let ab = b - a
                let t = min(max((p - a).dot(ab) / ab.lengthSquared, 0), 1)
                best = min(best, (p - (a + ab * t)).length)
            }
        }
        return best
    }

    // MARK: - Inside

    /// Every point of a holed shape lands in the fill, none in the hole, and
    /// the four bands around the hole take their share by area: the
    /// chi-square over four regions stays under the 0.1% mark for three
    /// degrees of freedom (16.3), with room to spare.
    @Test func pointsInsideAHoledShapeAreEvenByAreaAndNoneFallInTheHole() {
        var rng = SplitMix64(seed: 11)
        let shape = Self.frame()
        let points = randomPoints(in: shape, count: 4000, using: &rng)
        #expect(points.count == 4000)
        #expect(points.allSatisfy { shape.contains($0) })
        #expect(!points.contains { Self.hole.contains($0) })
        var counts = [0, 0, 0, 0]
        for p in points { counts[Self.band(of: p)] += 1 }
        let chi = Self.chiSquare(counts, shares: Self.bandAreas)
        #expect(chi < 12, "chi-square \(chi) over bands \(counts)")
    }

    /// A concave region gets its share where a box around it would not: an L
    /// whose missing quarter receives nothing and whose two arms split the
    /// points by their areas.
    @Test func aConcaveShapeFillsItsArmsAndNotItsNotch() {
        var rng = SplitMix64(seed: 5)
        let l = Shape([Vector2(0, 0), Vector2(100, 0), Vector2(100, 40),
                       Vector2(40, 40), Vector2(40, 100), Vector2(0, 100)])
        let points = randomPoints(in: l, count: 3000, using: &rng)
        #expect(points.allSatisfy { l.contains($0) })
        #expect(!points.contains { $0.x > 40 && $0.y > 40 })
        // The bottom arm (100 by 40) against the upright above it (40 by 60).
        let bottom = points.filter { $0.y <= 40 }.count
        let upright = points.count - bottom
        let chi = Self.chiSquare([bottom, upright], shares: [4000, 2400])
        #expect(chi < 7, "chi-square \(chi) bottom \(bottom) upright \(upright)")
    }

    /// Two islands share the points by area: the larger square, four times
    /// the area of the smaller, takes about four fifths.
    @Test func islandsShareByArea() {
        var rng = SplitMix64(seed: 2)
        let shape = Self.islands()
        let points = randomPoints(in: shape, count: 2500, using: &rng)
        #expect(points.allSatisfy { shape.contains($0) })
        let small = points.filter { $0.x < 100 }.count
        let chi = Self.chiSquare([small, points.count - small], shares: [900, 3600])
        #expect(chi < 7, "chi-square \(chi) small \(small)")
    }

    /// The same seed lays the same points; a different seed lays others; a
    /// count of nothing, a shape with no area, and an open path give nothing.
    @Test func insideRepeatsBySeedAndHandlesTheEmptyCases() {
        var a = SplitMix64(seed: 9), b = SplitMix64(seed: 9), c = SplitMix64(seed: 10)
        let shape = Self.frame()
        #expect(randomPoints(in: shape, count: 50, using: &a) == randomPoints(in: shape, count: 50, using: &b))
        #expect(randomPoints(in: shape, count: 50, using: &a) != randomPoints(in: shape, count: 50, using: &c))
        #expect(randomPoints(in: shape, count: 0, using: &a).isEmpty)
        #expect(randomPoints(in: Shape(contours: []), count: 10, using: &a).isEmpty)
        let open = Shape([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)], closed: false)
        #expect(randomPoints(in: open, count: 10, using: &a).isEmpty)
        let line = Shape([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
        #expect(randomPoints(in: line, count: 10, using: &a).isEmpty)
    }

    // MARK: - Along the outline

    /// Every point sits on the outline, and a side receives points by its
    /// length: the long sides of a 100 by 10 rectangle carry 200 of its 220.
    @Test func pointsAlongTheOutlineSitOnItAndSpreadByLength() {
        var rng = SplitMix64(seed: 3)
        let rect = Shape([Vector2(0, 0), Vector2(100, 0), Vector2(100, 10), Vector2(0, 10)])
        let points = randomPoints(along: rect, count: 2200, using: &rng)
        #expect(points.count == 2200)
        #expect(points.allSatisfy { Self.outlineDistance(rect, $0) < 1e-9 })
        let onLongSides = points.filter { abs($0.y) < 1e-9 || abs($0.y - 10) < 1e-9 }.count
        let chi = Self.chiSquare([onLongSides, points.count - onLongSides], shares: [200, 20])
        #expect(chi < 7, "chi-square \(chi) long sides \(onLongSides)")
    }

    /// Every contour takes part, open ones included, and a closed one walks
    /// its closing segment: a holed shape scatters on both rings by length,
    /// and an open three-point path scatters on its two segments only.
    @Test func alongCoversEveryContourAndClosesTheClosedOnes() {
        var rng = SplitMix64(seed: 4)
        let shape = Self.frame()
        let points = randomPoints(along: shape, count: 2800, using: &rng)
        #expect(points.allSatisfy { Self.outlineDistance(shape, $0) < 1e-9 })
        let onHole = points.filter { Self.outlineDistance(Self.hole, $0) < 1e-9 }.count
        // The outer ring is 400 long, the hole 160.
        let chi = Self.chiSquare([points.count - onHole, onHole], shares: [400, 160])
        #expect(chi < 7, "chi-square \(chi) on hole \(onHole)")
        // The closing segment of the outer square (x = 0) gets its quarter.
        let onClosing = points.filter { abs($0.x) < 1e-9 }.count
        let chiClosing = Self.chiSquare([onClosing, points.count - onClosing], shares: [100, 460])
        #expect(chiClosing < 7, "chi-square \(chiClosing) on the closing edge \(onClosing)")

        let open = Shape([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)], closed: false)
        let along = randomPoints(along: open, count: 400, using: &rng)
        #expect(along.allSatisfy { Self.outlineDistance(open, $0) < 1e-9 })
        // Nothing lands on the segment an open path does not have.
        #expect(!along.contains { abs($0.x - $0.y) < 1e-9 && $0.x > 1e-9 })
        #expect(randomPoints(along: Shape(contours: []), count: 5, using: &rng).isEmpty)
        #expect(randomPoints(along: Shape([Vector2(1, 1), Vector2(1, 1)]), count: 5, using: &rng).isEmpty)
    }

    // MARK: - Blue noise inside

    /// The blue-noise form keeps every point in the fill, none in the hole,
    /// and no two closer than the radius; the count follows the area.
    @Test func poissonDiskInsideKeepsItsDistanceAndStaysInTheFill() {
        var rng = SplitMix64(seed: 21)
        let shape = Self.frame()
        let points = poissonDisk(in: shape, radius: 5, using: &rng)
        #expect(points.allSatisfy { shape.contains($0) })
        #expect(!points.contains { Self.hole.contains($0) })
        for i in points.indices {
            for j in (i + 1) ..< points.count {
                #expect(points[i].distance(to: points[j]) >= 5 - 1e-9)
            }
        }
        // 8400 of area at a spacing of 5: the honeycomb allows about 388,
        // Bridson's fill lands well over half of that.
        #expect(points.count > 200 && points.count < 400, "\(points.count) points")
        var counts = [0, 0, 0, 0]
        for p in points { counts[Self.band(of: p)] += 1 }
        let chi = Self.chiSquare(counts, shares: Self.bandAreas)
        #expect(chi < 16, "chi-square \(chi) over bands \(counts)")
    }

    /// A shape thinner than the dart's annulus still fills end to end: the
    /// seeds come from the fill's own triangles, and the throwing restarts
    /// from a fresh one when every placed point has retired.
    @Test func poissonDiskFillsAThinShapeEndToEnd() {
        var rng = SplitMix64(seed: 8)
        let bar = Self.bar()
        let points = poissonDisk(in: bar, radius: 4, using: &rng)
        #expect(points.allSatisfy { bar.contains($0) })
        // Along 400 at a spacing of 4 there is room for a point every 4 or
        // so; a fill that stalled at its first seed's neighborhood would
        // stop far short of both ends.
        #expect(points.count > 70, "\(points.count) points")
        let xs = points.map(\.x)
        #expect(xs.min()! < 12 && xs.max()! > 388)
        // No stretch longer than a few radii goes empty.
        let sorted = xs.sorted()
        let widestGap = zip(sorted, sorted.dropFirst()).map { $1 - $0 }.max() ?? 0
        #expect(widestGap < 3 * 4, "widest empty stretch \(widestGap)")
    }

    /// Two islands both fill, even though no dart thrown around a point in
    /// one can reach the other.
    @Test func poissonDiskReachesEveryIsland() {
        var rng = SplitMix64(seed: 13)
        let shape = Self.islands()
        let points = poissonDisk(in: shape, radius: 6, using: &rng)
        #expect(points.allSatisfy { shape.contains($0) })
        let small = points.filter { $0.x < 100 }.count
        #expect(small > 8 && points.count - small > 40, "small \(small) of \(points.count)")
    }

    /// The cap stops the fill early; the seed repeats the layout; no radius,
    /// no area, or no room gives nothing.
    @Test func poissonDiskInsideHonorsTheCapAndTheSeed() {
        var a = SplitMix64(seed: 1), b = SplitMix64(seed: 1)
        let shape = Self.frame()
        #expect(poissonDisk(in: shape, radius: 5, maxCount: 17, using: &a).count == 17)
        a = SplitMix64(seed: 1)
        #expect(poissonDisk(in: shape, radius: 5, using: &a) == poissonDisk(in: shape, radius: 5, using: &b))
        #expect(poissonDisk(in: shape, radius: 0, using: &a).isEmpty)
        #expect(poissonDisk(in: shape, radius: 5, maxCount: 0, using: &a).isEmpty)
        #expect(poissonDisk(in: Shape(contours: []), radius: 5, using: &a).isEmpty)
        // A radius wider than the shape leaves room for one point per island.
        #expect(poissonDisk(in: Self.islands(), radius: 100, using: &a).count == 2)
    }
}
