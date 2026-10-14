import Testing
import Foundation
import Ollin

/// The curved patch and the warp into it, each pinned by what it promises:
/// the corners land on the corners, each side is followed exactly and read
/// by the fraction walked along it, a patch made from a rectangle is that
/// rectangle, four corners give the bilinear map, a side given backward is
/// turned, and a straight edge warped into the patch bends with its side.
@Suite
struct CurvedPatchTests {

    /// A cushion: every side a different curve, unevenly spaced, the ends
    /// meeting at the four corners.
    static let topLeft = Vector2(100, 120), topRight = Vector2(700, 80)
    static let bottomRight = Vector2(760, 560), bottomLeft = Vector2(60, 600)

    static func curve(from a: Vector2, to b: Vector2, bulge: Double, count: Int, phase: Double) -> Contour {
        let normal = (b - a).perpendicular.normalized
        var points: [Vector2] = []
        for i in 0 ... count {
            // Uneven spacing: the fractions crowd toward one end.
            let s = Double(i) / Double(count)
            let t = s * s * (3 - 2 * s) * 0.5 + s * 0.5
            let lift = bulge * sin(t * .pi) + 12 * sin(t * 5 * .pi + phase)
            points.append(a + (b - a) * t + normal * lift)
        }
        points[0] = a
        points[count] = b
        return Contour(points, closed: false)
    }

    static let cushion = CoonsPatch(
        top: curve(from: topLeft, to: topRight, bulge: 60, count: 37, phase: 0.3),
        right: curve(from: topRight, to: bottomRight, bulge: -40, count: 23, phase: 1.1),
        bottom: curve(from: bottomLeft, to: bottomRight, bulge: 50, count: 41, phase: 2.0),
        left: curve(from: topLeft, to: bottomLeft, bulge: 35, count: 19, phase: 0.7))

    /// The point a fraction `t` of the way along `contour` by length,
    /// walked independently of the patch.
    static func pointAlong(_ contour: Contour, _ t: Double) -> Vector2 {
        let p = contour.points
        var lengths: [Double] = [0]
        for i in 1 ..< p.count { lengths.append(lengths[i - 1] + p[i].distance(to: p[i - 1])) }
        let target = t * lengths[lengths.count - 1]
        for i in 1 ..< p.count where lengths[i] >= target {
            let span = lengths[i] - lengths[i - 1]
            let u = span > 0 ? (target - lengths[i - 1]) / span : 0
            return p[i - 1] + (p[i] - p[i - 1]) * u
        }
        return p[p.count - 1]
    }

    @Test func theCornersLandOnTheCorners() {
        let patch = Self.cushion
        #expect(patch.point(u: 0, v: 0).distance(to: Self.topLeft) < 1e-9)
        #expect(patch.point(u: 1, v: 0).distance(to: Self.topRight) < 1e-9)
        #expect(patch.point(u: 1, v: 1).distance(to: Self.bottomRight) < 1e-9)
        #expect(patch.point(u: 0, v: 1).distance(to: Self.bottomLeft) < 1e-9)
        #expect(patch.topLeft == Self.topLeft && patch.bottomRight == Self.bottomRight)
    }

    @Test func eachSideIsFollowedAndReadByTheFractionWalked() {
        let patch = Self.cushion
        // The midpoint by length, and every fraction between.
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(patch.point(u: t, v: 0).distance(to: Self.pointAlong(patch.top, t)) < 1e-9)
            #expect(patch.point(u: t, v: 1).distance(to: Self.pointAlong(patch.bottom, t)) < 1e-9)
            #expect(patch.point(u: 0, v: t).distance(to: Self.pointAlong(patch.left, t)) < 1e-9)
            #expect(patch.point(u: 1, v: t).distance(to: Self.pointAlong(patch.right, t)) < 1e-9)
        }
        // The midpoint is not the middle point: the spacing is uneven.
        let middleIndex = patch.top.points[patch.top.points.count / 2]
        #expect(patch.point(u: 0.5, v: 0).distance(to: middleIndex) > 5)
    }

    @Test func aPatchMadeFromARectangleIsThatRectangle() {
        let rect = Rectangle(x: 40, y: 70, width: 500, height: 300)
        let patch = CoonsPatch(rect)
        for u in stride(from: -0.5, through: 1.5, by: 0.25) {
            for v in stride(from: -0.5, through: 1.5, by: 0.25) {
                #expect(patch.point(u: u, v: v).distance(to: rect.point(u: u, v: v)) < 1e-9)
            }
        }
        // An outline warped from the rectangle into it comes back where it
        // was, its straight runs given their extra points.
        let star = Contour((0 ..< 10).map { i -> Vector2 in
            let a = Double(i) / 10 * 2 * .pi
            return rect.center + Vector2(angle: a, length: i.isMultiple(of: 2) ? 140 : 60)
        }, closed: true)
        let warped = star.warped(from: rect, into: patch)
        #expect(warped.points.count > star.points.count)
        for p in warped.points { #expect(star.distance(to: p) < 1e-9) }
        for p in star.points { #expect(warped.points.contains { $0.distance(to: p) < 1e-9 }) }
    }

    @Test func fourCornersGiveTheBilinearMap() {
        let a = Vector2(10, 20), b = Vector2(300, -15), c = Vector2(420, 260), d = Vector2(-30, 200)
        let patch = CoonsPatch(topLeft: a, topRight: b, bottomRight: c, bottomLeft: d)
        for u in stride(from: 0.0, through: 1.0, by: 0.125) {
            for v in stride(from: 0.0, through: 1.0, by: 0.125) {
                let expected = a * ((1 - u) * (1 - v)) + b * (u * (1 - v)) + d * ((1 - u) * v) + c * (u * v)
                #expect(patch.point(u: u, v: v).distance(to: expected) < 1e-9)
            }
        }
    }

    @Test func straightSidesOfManyUnevenPointsAreStillBilinear() {
        let a = Vector2(0, 0), b = Vector2(400, 40), c = Vector2(380, 300), d = Vector2(20, 280)
        func line(_ p: Vector2, _ q: Vector2) -> Contour {
            Contour([0, 0.05, 0.1, 0.4, 0.45, 0.9, 1].map { p + (q - p) * $0 }, closed: false)
        }
        let curved = CoonsPatch(top: line(a, b), right: line(b, c), bottom: line(d, c), left: line(a, d))
        let flat = CoonsPatch(topLeft: a, topRight: b, bottomRight: c, bottomLeft: d)
        for u in stride(from: 0.0, through: 1.0, by: 0.1) {
            for v in stride(from: 0.0, through: 1.0, by: 0.1) {
                #expect(curved.point(u: u, v: v).distance(to: flat.point(u: u, v: v)) < 1e-9)
            }
        }
    }

    @Test func aSideGivenBackwardIsTurnedToMeetTheTop() {
        let given = Self.cushion
        let reversed = CoonsPatch(top: given.top,
                                  right: Contour(given.right.points.reversed(), closed: false),
                                  bottom: Contour(given.bottom.points.reversed(), closed: false),
                                  left: Contour(given.left.points.reversed(), closed: false))
        #expect(reversed == given)
        for (u, v) in [(0.3, 0.7), (0.5, 0.5), (0.9, 0.1)] {
            #expect(reversed.point(u: u, v: v).distance(to: given.point(u: u, v: v)) < 1e-12)
        }
    }

    @Test func cornersThatMissMeetHalfwayAndTheSidesKeepTheirShape() {
        let top = Contour([Vector2(0, 0), Vector2(100, 0)], closed: false)
        let right = Contour([Vector2(110, 0), Vector2(110, 100)], closed: false)   // 10 off the top's end
        let bottom = Contour([Vector2(0, 100), Vector2(110, 100)], closed: false)
        let left = Contour([Vector2(0, 0), Vector2(0, 100)], closed: false)
        let patch = CoonsPatch(top: top, right: right, bottom: bottom, left: left)
        #expect(patch.topRight == Vector2(105, 0))
        #expect(patch.point(u: 1, v: 0).distance(to: Vector2(105, 0)) < 1e-9)
        // The right side keeps its shape (a vertical line), moved to meet.
        for v in stride(from: 0.0, through: 1.0, by: 0.25) {
            #expect(abs(patch.point(u: 1, v: v).x - (110 - 5 * (1 - v))) < 1e-9)
        }
    }

    @Test func aStraightEdgeBendsWithItsSide() {
        let box = Rectangle(x: 0, y: 0, width: 200, height: 100)
        let outline = box.contour    // four points, two of them on the top edge
        let warped = outline.warped(from: box, into: Self.cushion, spacing: 4)
        #expect(warped.points.count > 140)
        // The top edge, 200 long at a spacing of 4, became fifty pieces, and
        // every point it became lies on the patch's top curve.
        for k in 0 ... 50 {
            let landed = Self.cushion.point(u: Double(k) / 50, v: 0)
            #expect(Self.cushion.top.distance(to: landed) < 1e-9)
            #expect(warped.points.contains { $0.distance(to: landed) < 1e-9 })
        }
        // And the warp of the whole outline is the patch's outline.
        for p in warped.points { #expect(Self.cushion.contour.distance(to: p) < 1e-6) }
    }

    @Test func theShapeFormKeepsItsWindingAndItsHoles() {
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let ring = Shape(contours: [
            Contour([Vector2(10, 10), Vector2(90, 10), Vector2(90, 90), Vector2(10, 90)], closed: true),
            Contour([Vector2(40, 40), Vector2(60, 40), Vector2(60, 60), Vector2(40, 60)], closed: true),
        ], winding: .nonZero)
        let bent = ring.warped(from: rect, into: Self.cushion)
        #expect(bent.contours.count == 2)
        #expect(bent.winding == .nonZero)
        #expect(bent.contours.allSatisfy { $0.isClosed })
    }

    @Test func theOutlineIsTheFourSides() {
        let patch = Self.cushion
        let outline = patch.contour
        #expect(outline.isClosed)
        let sides = [patch.top, patch.right, patch.bottom, patch.left]
        for p in outline.points {
            #expect(sides.contains { $0.distance(to: p) < 1e-9 })
        }
        // Every point of every side is on the outline, the corners once.
        let expected = sides.map(\.points.count).reduce(0, +) - 4
        #expect(outline.points.count == expected)
    }

    @Test func aPointOutsideCarriesOnPastTheSides() {
        let patch = Self.cushion
        let start = patch.top.points[0], next = patch.top.points[1]
        let out = patch.point(u: -0.1, v: 0)
        // On the line through the top's first segment, behind its start.
        let along = (next - start).normalized
        let offset = out - start
        #expect(abs(offset.cross(along)) < 1e-9)
        #expect(offset.dot(along) < 0)
    }
}
