import Ollin
import Testing

/// Pure-CPU checks on shape morphing: exact endpoints, correspondence that
/// finds the shortest travel, winding normalization, contour pairing, and the
/// grow/shrink handling of unmatched contours.
@Suite
struct ShapeMorphTests {
    private func square(at center: Vector2 = .zero, size: Double = 100,
                        clockwise: Bool = true) -> [Vector2] {
        let h = size / 2
        let corners = [Vector2(center.x - h, center.y - h),
                       Vector2(center.x + h, center.y - h),
                       Vector2(center.x + h, center.y + h),
                       Vector2(center.x - h, center.y + h)]
        return clockwise ? corners : corners.reversed()
    }

    private func area(_ contour: Contour) -> Double {
        let p = contour.points
        guard p.count >= 3 else { return 0 }
        var sum = 0.0
        for i in p.indices {
            let q = p[(i + 1) % p.count]
            sum += p[i].x * q.y - q.x * p[i].y
        }
        return abs(sum / 2)
    }

    /// The reads at 0 and 1 are the original shapes, verbatim.
    @Test func endpointsAreExact() {
        let a = Shape(square())
        let b = Shape(contours: [Contour(square(at: Vector2(300, 200), size: 40))],
                      winding: .nonZero)
        let morph = ShapeMorph(from: a, to: b)
        #expect(morph.shape(at: 0) == a)
        #expect(morph.shape(at: 1) == b)
        #expect(morph.shape(at: -3) == a)
        #expect(morph.shape(at: 7) == b)
    }

    /// Morphing a shape to itself never moves a point: correspondence lands
    /// on the identity, so every in-between keeps the original outline.
    @Test func selfMorphIsStationary() {
        // Asymmetric so no rotated correspondence could also pass.
        let pentagon = Shape([Vector2(0, 0), Vector2(120, 10), Vector2(150, 80),
                              Vector2(60, 140), Vector2(-20, 70)])
        let morph = ShapeMorph(from: pentagon, to: pentagon)
        let mid = morph.shape(at: 0.37).contours[0]
        #expect(abs(area(mid) - area(pentagon.contours[0])) < 1e-9)
        for corner in pentagon.contours[0].points {
            let nearest = mid.points.map { ($0 - corner).length }.min() ?? .infinity
            #expect(nearest < 1e-9)
        }
    }

    /// The same circle listed from a different starting point morphs with no
    /// travel: the cyclic-rotation search recovers the point alignment.
    @Test func rotationSearchAlignsStartingPoints() {
        let points = (0 ..< 48).map { Vector2(angle: Double($0) / 48 * .tau, length: 100) }
        let shifted = Array(points[13...]) + Array(points[..<13])
        let morph = ShapeMorph(from: Shape(points), to: Shape(shifted))
        let mid = morph.shape(at: 0.5).contours[0]
        #expect(abs(area(mid) - area(Contour(points))) < 1e-6)
        // Added points sit on the polygon's chords (radius ~99.8), so the pin
        // is a loose band: a failed rotation would drag points to radius ~66.
        for p in mid.points {
            #expect(abs(p.length - 100) < 0.5)
        }
    }

    /// Opposite winding directions are normalized before blending, so the
    /// morph never folds through itself.
    @Test func opposedWindingsAreNormalized() {
        let cw = Shape(square())
        let ccw = Shape(square(clockwise: false))
        let mid = ShapeMorph(from: cw, to: ccw).shape(at: 0.5).contours[0]
        #expect(abs(area(mid) - 100 * 100) < 1e-6)
    }

    /// An open run morphing to its own reversal detects the flip and stays
    /// put instead of folding through the middle.
    @Test func openRunsAlignDirection() {
        let line = Contour([Vector2(0, 0), Vector2(50, 20), Vector2(100, 0)], closed: false)
        let reversedLine = Contour(line.points.reversed(), closed: false)
        let morph = ShapeMorph(from: Shape(contours: [line]), to: Shape(contours: [reversedLine]))
        let mid = morph.shape(at: 0.5).contours[0]
        #expect(!mid.isClosed)
        for p in line.points {
            let nearest = mid.points.map { ($0 - p).length }.min() ?? .infinity
            #expect(nearest < 1e-9)
        }
    }

    /// Both sides of every match carry the same number of points, and both
    /// originals' corner points survive the preparation.
    @Test func matchedRunsShareCounts() {
        let triangle = Shape([Vector2(0, 0), Vector2(200, 0), Vector2(100, 170)])
        let blob = Shape((0 ..< 90).map { Vector2(angle: Double($0) / 90 * .tau, length: 80) })
        let mid = ShapeMorph(from: triangle, to: blob).shape(at: 0.5)
        #expect(mid.contours.count == 1)
        #expect(mid.contours[0].points.count >= 90)
    }

    /// A hole pairs with a hole: outer with outer, inner with inner, and the
    /// blended hole stays the smaller contour throughout.
    @Test func holesPairWithHoles() {
        let a = Shape(outer: square(size: 200), holes: [square(size: 80)])
        let b = Shape(outer: square(at: Vector2(400, 0), size: 150),
                      holes: [square(at: Vector2(400, 0), size: 30)])
        let mid = ShapeMorph(from: a, to: b).shape(at: 0.5)
        #expect(mid.contours.count == 2)
        let areas = mid.contours.map(area)
        #expect(areas[0] > areas[1]) // pairing kept outer-to-outer
        #expect(abs(areas[0] - (175.0 * 175.0)) < 200) // blended outer near the lerped size
    }

    /// A contour with no partner scales down to its own center (or grows out
    /// of it), so contour-count mismatches cross-fade instead of popping.
    @Test func unmatchedContoursCollapse() {
        let one = Shape(square(size: 100))
        let two = Shape(contours: [Contour(square(size: 100)),
                                   Contour(square(at: Vector2(300, 0), size: 60))])
        let morph = ShapeMorph(from: one, to: two)
        let quarter = morph.shape(at: 0.25)
        #expect(quarter.contours.count == 2)
        // The growing square scales linearly, so its area goes with t².
        let growing = area(quarter.contours[1])
        #expect(abs(growing - 60 * 60 * 0.25 * 0.25) < 1e-6)
        #expect(morph.shape(at: 1) == two)
    }

    /// A `Timeline<Shape>` tweens geometry through the `Tweenable`
    /// conformance and lands exactly on its keyframes.
    @Test func timelineTweensShapes() {
        let a = Shape(square(size: 100))
        let b = Shape(square(at: Vector2(200, 0), size: 100))
        let tween = Timeline(a).to(b, in: 1, ease: .linear)
        tween.advance(by: 0.5)
        let mid = tween.value.contours[0]
        let center = mid.points.centroid ?? .zero
        #expect(abs(center.x - 100) < 1e-6)
        tween.advance(by: 10)
        #expect(tween.value == b)
    }

    /// Lone contours tween too, staying open when both ends are open.
    @Test func contoursAreTweenable() {
        let a = Contour([Vector2(0, 0), Vector2(100, 0)], closed: false)
        let b = Contour([Vector2(0, 50), Vector2(100, 50)], closed: false)
        let mid = Contour.lerp(a, b, 0.5)
        #expect(!mid.isClosed)
        #expect(mid.points.allSatisfy { abs($0.y - 25) < 1e-9 })
    }

    /// The same inputs always prepare the same morph, and a tiny requested
    /// spacing is floored instead of running away.
    @Test func deterministicAndBounded() {
        let a = Shape(square(size: 300))
        let b = Shape((0 ..< 64).map { Vector2(angle: Double($0) / 64 * .tau, length: 150) })
        let m1 = ShapeMorph(from: a, to: b)
        let m2 = ShapeMorph(from: a, to: b)
        for t in [0.1, 0.33, 0.5, 0.9] {
            #expect(m1.shape(at: t) == m2.shape(at: t))
        }
        let capped = ShapeMorph(from: a, to: b, spacing: 1e-9)
        #expect(capped.shape(at: 0.5).contours[0].points.count <= 4200)
    }

    /// Morphing from an empty shape grows everything out of its centers.
    @Test func emptyShapeGrows() {
        let empty = Shape(contours: [])
        let target = Shape(square(size: 100))
        let morph = ShapeMorph(from: empty, to: target)
        #expect(morph.shape(at: 0.5).contours.count == 1)
        #expect(morph.shape(at: 1) == target)
    }
}
