import Foundation
import Testing
@testable import Ollin

/// Cutting a shape with a line: the two sides of a split add up to the whole, a
/// convex shape stays convex, a band is two half-plane clips, a hole survives
/// the cut, an open contour comes back in pieces, and a line that misses the
/// shape leaves it whole on one side and empty on the other.
@Suite struct ShapeCutTests {

    static let star = Shape((0 ..< 10).map { i -> Vector2 in
        let r = i % 2 == 0 ? 120.0 : 50.0
        let a = Double(i) / 10 * 2 * .pi - .pi / 2
        return Vector2(200 + r * cos(a), 200 + r * sin(a))
    })

    static let ring = Shape(outer: [Vector2(50, 50), Vector2(350, 50), Vector2(350, 350), Vector2(50, 350)],
                            holes: [[Vector2(150, 150), Vector2(250, 150), Vector2(250, 250), Vector2(150, 250)]])

    /// Whether every corner of a single closed contour turns the same way.
    static func isConvex(_ shape: Shape) -> Bool {
        guard shape.contours.count == 1 else { return false }
        let pts = shape.contours[0].points
        guard pts.count >= 3 else { return false }
        var sign = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count], c = pts[(i + 2) % pts.count]
            let turn = (b - a).cross(c - b)
            if abs(turn) < 1e-9 { continue }
            if sign == 0 { sign = turn } else if turn * sign < 0 { return false }
        }
        return true
    }

    // MARK: Half-planes

    @Test func aHalfPlaneKeepsOneSideAndItsLine() {
        let line = Ray2(origin: Vector2(10, 10), direction: Vector2(1, 0))
        let left = HalfPlane(leftOf: line), right = HalfPlane(rightOf: line)
        // Looking along +x on a canvas whose y runs down, left is up: smaller y.
        #expect(left.contains(Vector2(5, 0)))
        #expect(!left.contains(Vector2(5, 20)))
        #expect(right.contains(Vector2(5, 20)))
        #expect(!right.contains(Vector2(5, 0)))
        #expect(left.contains(Vector2(99, 10)), "the line itself is in")
        #expect(right.contains(Vector2(99, 10)))
        #expect(abs(left.signedDistance(to: Vector2(0, 4)) - 6) < 1e-12)
        #expect(abs(right.signedDistance(to: Vector2(0, 4)) + 6) < 1e-12)
        let half = HalfPlane(point: Vector2(3, 3), inward: Vector2(2, 0))
        #expect(half.boundary.distance(to: Vector2(3, 50)) < 1e-12, "the boundary runs through the point")
        #expect(half.contains(Vector2(4, 0)) && !half.contains(Vector2(2, 0)))
    }

    // MARK: Splitting

    @Test func theTwoSidesOfASplitAddUpToTheShape() {
        let whole = Self.star.area
        for angle in stride(from: 0.0, to: .pi, by: .pi / 7) {
            let line = Ray2(origin: Vector2(205, 190), direction: Vector2(angle: angle))
            let (left, right) = Self.star.split(along: line)
            #expect(abs(left.area + right.area - whole) < 1e-6 * whole,
                    "at \(angle): \(left.area) + \(right.area) against \(whole)")
            #expect(left.area > 0 && right.area > 0)
            // Nothing of either side crosses the line.
            for p in left.contours.flatMap(\.points) { #expect(HalfPlane(leftOf: line).signedDistance(to: p) > -1e-9) }
            for p in right.contours.flatMap(\.points) { #expect(HalfPlane(rightOf: line).signedDistance(to: p) > -1e-9) }
        }
    }

    @Test func aConvexShapeStaysConvexAndAHoleSurvives() {
        let box = Shape([Vector2(0, 0), Vector2(100, 0), Vector2(100, 60), Vector2(0, 60)])
        let line = Ray2(origin: Vector2(30, 0), direction: Vector2(1, 2))
        let (left, right) = box.split(along: line)
        #expect(Self.isConvex(left))
        #expect(Self.isConvex(right))
        #expect(abs(left.area + right.area - 6000) < 1e-9)
        // A hexagon cut three ways stays convex each time.
        let hexagon = Shape((0 ..< 6).map { Vector2(angle: Double($0) / 6 * 2 * .pi, length: 80) + Vector2(100, 100) })
        for angle in [0.3, 1.1, 2.4] {
            let piece = hexagon.clipped(to: HalfPlane(point: Vector2(110, 95), inward: Vector2(angle: angle)))
            #expect(Self.isConvex(piece), "at \(angle)")
        }
        // The ring: both sides keep their part of the hole, and the areas add.
        let (top, bottom) = Self.ring.split(along: Ray2(origin: Vector2(0, 200), direction: Vector2(1, 0)))
        #expect(top.contours.count == 2 && bottom.contours.count == 2)
        #expect(abs(top.area + bottom.area - Self.ring.area) < 1e-9)
        #expect(abs(top.area - bottom.area) < 1e-9, "the cut runs through the middle")
        #expect(!top.contains(Vector2(200, 175)), "the hole is still a hole")
        #expect(top.contains(Vector2(100, 100)))
    }

    @Test func aBandIsTheShapeWithinADistanceOfTheLine() {
        let box = Shape([Vector2(0, 0), Vector2(200, 0), Vector2(200, 100), Vector2(0, 100)])
        let line = Ray2(origin: Vector2(0, 50), direction: Vector2(1, 0))
        let band = box.clipped(within: 10, of: line)
        #expect(abs(band.area - 200 * 20) < 1e-9)
        for p in band.contours.flatMap(\.points) { #expect(abs(p.y - 50) <= 10 + 1e-9) }
        // A band wider than the shape is the shape.
        #expect(abs(box.clipped(within: 500, of: line).area - box.area) < 1e-9)
        // A band at the edge of the shape keeps the strip that is inside.
        let edge = box.clipped(within: 5, of: Ray2(origin: Vector2(0, 0), direction: Vector2(1, 0)))
        #expect(abs(edge.area - 200 * 5) < 1e-9)
    }

    @Test func aLineThatMissesLeavesTheShapeWholeOnOneSide() {
        let line = Ray2(origin: Vector2(0, 500), direction: Vector2(1, 0))
        let (left, right) = Self.star.split(along: line)
        #expect(abs(left.area - Self.star.area) < 1e-9)
        #expect(right.contours.isEmpty)
        #expect(right.area == 0)
    }

    @Test func anOpenContourComesBackInPieces() {
        let zigzag = Contour([Vector2(0, 0), Vector2(10, 20), Vector2(20, 0), Vector2(30, 20), Vector2(40, 0)], closed: false)
        let below = HalfPlane(point: Vector2(0, 10), inward: Vector2(0, 1))   // y >= 10
        let pieces = zigzag.clipped(to: below)
        #expect(pieces.count == 2)
        for piece in pieces {
            #expect(!piece.isClosed)
            #expect(piece.points.count == 3)
            #expect(piece.points.first?.y == 10 && piece.points.last?.y == 10)
        }
        // The whole of it on the other side is one piece: the first and last points, and the two dips.
        let above = zigzag.clipped(to: HalfPlane(point: Vector2(0, 10), inward: Vector2(0, -1)))
        #expect(above.count == 3)
        // A shape of open contours keeps them open.
        let shape = Shape(contours: [zigzag]).clipped(to: below)
        #expect(shape.contours.count == 2 && shape.contours.allSatisfy { !$0.isClosed })
    }
}
