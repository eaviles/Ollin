import Foundation
import Testing
import Ollin

/// `spherePoints` and `hemispherePoints`: the count is exact, every point is
/// on the surface, and the points keep nearly one distance from their nearest
/// neighbor at every count, which is what "spread evenly" means here.
@Suite("Points spread over a sphere")
struct SpherePointsTests {

    /// The distance from each point to its nearest neighbor, by looking
    /// outward along the list until the next point's height alone is farther
    /// than the nearest one found. The heights step evenly, so this is exact.
    static func nearestByHeight(_ points: [Vector3]) -> [Double] {
        let count = points.count
        guard count > 1 else { return [] }
        let step = abs(points[0].y - points[1].y)
        return (0 ..< count).map { i in
            var best = Double.infinity
            var k = 1
            while true {
                var any = false
                for j in [i - k, i + k] where j >= 0 && j < count {
                    any = true
                    best = Swift.min(best, points[i].distance(to: points[j]))
                }
                if !any || Double(k) * step > best { break }
                k += 1
            }
            return best
        }
    }

    /// The same distances, looking only at the points a Fibonacci number of
    /// places away: on this lattice a point's nearest neighbors are always
    /// among those, which `theShortcutIsExact` holds against the full search.
    static func nearestByFibonacciOffsets(_ points: [Vector3]) -> [Double] {
        let count = points.count
        var offsets = [1, 2]
        while offsets[offsets.count - 1] < count { offsets.append(offsets[offsets.count - 1] + offsets[offsets.count - 2]) }
        return (0 ..< count).map { i in
            var best = Double.infinity
            for offset in offsets where offset < count {
                if i - offset >= 0 { best = Swift.min(best, points[i].distance(to: points[i - offset])) }
                if i + offset < count { best = Swift.min(best, points[i].distance(to: points[i + offset])) }
            }
            return best
        }
    }

    /// The spacing a point would have if each had a square of its own share
    /// of the surface.
    static func nominalSpacing(count: Int, area: Double) -> Double { (area / Double(count)).squareRoot() }

    @Test("The count is exact and every point is on the surface", arguments: [0, 1, 2, 3, 10, 97, 1000])
    func countAndSurface(count: Int) {
        let sphere = spherePoints(count: count)
        let dome = hemispherePoints(count: count)
        #expect(sphere.count == count)
        #expect(dome.count == count)
        for point in sphere { #expect(abs(point.length - 1) < 1e-12) }
        for point in dome {
            #expect(abs(point.length - 1) < 1e-12)
            #expect(point.y > 0, "a dome's point is under the rim")
        }
    }

    @Test("A count of zero or less returns nothing")
    func nothingForNothing() {
        #expect(spherePoints(count: 0).isEmpty)
        #expect(spherePoints(count: -4).isEmpty)
        #expect(hemispherePoints(count: -1).isEmpty)
    }

    @Test("The points run from the top down, no two at one height, none on a pole")
    func heightsStepEvenly() {
        let points = spherePoints(count: 500)
        for i in 1 ..< points.count {
            #expect(abs((points[i - 1].y - points[i].y) - 2.0 / 500) < 1e-12)
        }
        #expect(points[0].y < 1 && points[499].y > -1)
        // Equal bands of height are equal bands of area, so the heights
        // average to the middle: no half of the sphere is favored.
        let mean = points.reduce(0) { $0 + $1.y } / 500
        #expect(abs(mean) < 1e-12)
    }

    @Test("The radius scales the points and changes nothing else")
    func radiusScales() {
        let unit = spherePoints(count: 64)
        let large = spherePoints(count: 64, radius: 3.5)
        for (a, b) in zip(unit, large) {
            #expect(abs(b.length - 3.5) < 1e-12)
            #expect((a * 3.5).distance(to: b) < 1e-12)
        }
    }

    @Test("A dome is the upper half of the sphere of twice as many points")
    func domeIsHalfASphere() {
        let dome = hemispherePoints(count: 300, radius: 2)
        let sphere = spherePoints(count: 600, radius: 2)
        #expect(dome == Array(sphere.prefix(300)))
        #expect(sphere[300].y < 0)
    }

    @Test("A point's nearest neighbor is a Fibonacci number of places away",
          arguments: [10, 13, 100, 1000, 3000])
    func theShortcutIsExact(count: Int) {
        for points in [spherePoints(count: count), hemispherePoints(count: count)] {
            let full = Self.nearestByHeight(points)
            let quick = Self.nearestByFibonacciOffsets(points)
            for (a, b) in zip(full, quick) { #expect(abs(a - b) < 1e-12) }
        }
    }

    // Measured from 2 to 100,000 points: the nearest neighbor is never closer
    // than 0.871 of the nominal spacing and never farther than it, so the
    // farthest is at most 1.146 times the closest. Points drawn at random
    // read 12 to 1 at a hundred and 150 to 1 at ten thousand.
    @Test("Every point keeps nearly one distance from its nearest neighbor",
          arguments: [10, 30, 100, 1000, 10_000, 100_000])
    func evenSpread(count: Int) {
        let cases: [(name: String, points: [Vector3], area: Double)] = [
            ("sphere", spherePoints(count: count), 4 * .pi),
            ("dome", hemispherePoints(count: count), 2 * .pi)
        ]
        for (name, points, area) in cases {
            let nearest = count <= 3000 ? Self.nearestByHeight(points) : Self.nearestByFibonacciOffsets(points)
            let closest = nearest.min() ?? 0, farthest = nearest.max() ?? 0
            let nominal = Self.nominalSpacing(count: count, area: area)
            #expect(farthest / closest < 1.15, "the \(name) of \(count): \(farthest / closest) to 1")
            #expect(closest > 0.87 * nominal, "the \(name) of \(count): two points \(closest / nominal) of the spacing apart")
            #expect(farthest < 1.0 * nominal, "the \(name) of \(count): a point \(farthest / nominal) of the spacing from any other")
        }
    }

    @Test("The same call gives the same points")
    func repeats() {
        #expect(spherePoints(count: 2000) == spherePoints(count: 2000))
    }
}
