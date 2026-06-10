import Ollin
import Testing

/// Pure-geometry checks on `Shape`'s boolean set operations and offsetting —
/// no GPU, so these run everywhere (including CI). Correctness is pinned by
/// area: every result's net signed area (shoelace over all contours, so holes
/// subtract) must land on the analytically known value.
@Suite
struct ShapeBooleanTests {

    // MARK: Helpers

    /// An axis-aligned square as a closed single-contour shape.
    private func square(x: Double, y: Double, size: Double) -> Shape {
        Shape([
            Vector2(x, y),
            Vector2(x + size, y),
            Vector2(x + size, y + size),
            Vector2(x, y + size),
        ])
    }

    private func signedArea(_ contour: Contour) -> Double {
        let points = contour.points
        var sum = 0.0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Net region area: outer boundaries count positive, holes negative.
    private func area(_ shape: Shape) -> Double {
        abs(shape.contours.map(signedArea).reduce(0, +))
    }

    // MARK: Booleans

    @Test func unionOfOverlappingSquares() {
        let result = square(x: 0, y: 0, size: 10).union(square(x: 5, y: 5, size: 10))
        #expect(result.contours.count == 1)
        #expect(abs(area(result) - 175) < 1e-6) // 100 + 100 − 25 overlap
    }

    @Test func unionOfDisjointSquaresKeepsBoth() {
        let result = square(x: 0, y: 0, size: 10).union(square(x: 20, y: 0, size: 10))
        #expect(result.contours.count == 2)
        #expect(abs(area(result) - 200) < 1e-6)
    }

    @Test func intersectionIsTheOverlap() {
        let result = square(x: 0, y: 0, size: 10).intersection(square(x: 5, y: 5, size: 10))
        #expect(result.contours.count == 1)
        #expect(abs(area(result) - 25) < 1e-6)
        for contour in result.contours {
            for point in contour.points {
                #expect(point.x >= 5 - 1e-6 && point.x <= 10 + 1e-6)
                #expect(point.y >= 5 - 1e-6 && point.y <= 10 + 1e-6)
            }
        }
    }

    @Test func intersectionOfDisjointIsEmpty() {
        let result = square(x: 0, y: 0, size: 10).intersection(square(x: 20, y: 0, size: 10))
        #expect(result.contours.isEmpty)
    }

    @Test func subtractingCutsAHole() {
        let result = square(x: 0, y: 0, size: 100).subtracting(square(x: 25, y: 25, size: 50))
        #expect(result.contours.count == 2) // boundary + hole
        #expect(abs(area(result) - 7500) < 1e-6) // 10000 − 2500
        // The hole must be wound opposite to the boundary so non-zero reads it.
        let signs = result.contours.map { signedArea($0) > 0 }
        #expect(signs.contains(true) && signs.contains(false))
        #expect(result.winding == .nonZero)
    }

    @Test func symmetricDifferenceIsUnionMinusOverlap() {
        let result = square(x: 0, y: 0, size: 10).symmetricDifference(square(x: 5, y: 5, size: 10))
        #expect(abs(area(result) - 150) < 1e-6) // 175 union − 25 overlap
    }

    @Test func unionWithEmptyIsIdentity() {
        let empty = Shape(contours: [])
        let result = square(x: 0, y: 0, size: 10).union(empty)
        #expect(abs(area(result) - 100) < 1e-6)
        #expect(empty.union(empty).contours.isEmpty)
    }

    // MARK: Winding rules

    /// One shape holding two overlapping contours: even-odd drops the overlap
    /// (crossed twice), non-zero keeps it. A union against nothing normalizes
    /// the shape under its own rule, exposing the difference.
    @Test func windingRuleDecidesSelfOverlap() {
        let contours = [
            Contour([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]),
            Contour([Vector2(5, 5), Vector2(15, 5), Vector2(15, 15), Vector2(5, 15)]),
        ]
        let evenOdd = Shape(contours: contours, winding: .evenOdd).union(Shape(contours: []))
        let nonZero = Shape(contours: contours, winding: .nonZero).union(Shape(contours: []))
        #expect(abs(area(evenOdd) - 150) < 1e-6) // overlap is a hole
        #expect(abs(area(nonZero) - 175) < 1e-6) // overlap stays filled
    }

    /// Open contours have no fill, so they sit out of region operations —
    /// the same rule the triangulated fill applies.
    @Test func openContoursAreIgnored() {
        let openOnly = Shape(contours: [
            Contour([Vector2(0, 0), Vector2(50, 0), Vector2(50, 50)], closed: false)
        ])
        let result = openOnly.union(square(x: 0, y: 0, size: 10))
        #expect(abs(area(result) - 100) < 1e-6)
        #expect(openOnly.offset(by: 5).contours.isEmpty)
    }

    // MARK: Offsetting

    @Test func offsetGrowsMiteredSquareExactly() {
        let result = square(x: 0, y: 0, size: 100).offset(by: 10)
        // 90° corners stay sharp under the miter limit: an exact 120×120.
        #expect(result.contours.count == 1)
        #expect(abs(area(result) - 14400) < 1e-3)
    }

    @Test func offsetShrinksInward() {
        let result = square(x: 0, y: 0, size: 100).offset(by: -10)
        #expect(abs(area(result) - 6400) < 1e-3) // 80 × 80
    }

    @Test func offsetPastTheWaistVanishes() {
        let result = square(x: 0, y: 0, size: 100).offset(by: -60)
        #expect(result.contours.isEmpty)
    }

    @Test func offsetMovesHolesOppositeToBoundary() {
        let ring = square(x: 0, y: 0, size: 100).subtracting(square(x: 25, y: 25, size: 50))
        let result = ring.offset(by: 5)
        // Boundary 100→110 out, hole 50→40 in: both edges thicken the band.
        #expect(abs(area(result) - (110 * 110 - 40 * 40)) < 1e-3)
    }

    @Test func roundJoinRoundsTheCorners() {
        let result = square(x: 0, y: 0, size: 100).offset(by: 10, join: .round)
        // A rounded grow loses (4 − π)·d² to the four corner arcs.
        let expected = 120.0 * 120.0 - (4.0 - Double.pi) * 100.0
        #expect(abs(area(result) - expected) < 2)
        #expect(area(result) < 14400) // strictly inside the mitered grow
    }

    @Test func bevelJoinCutsTheCorners() {
        let result = square(x: 0, y: 0, size: 100).offset(by: 10, join: .bevel)
        // Each beveled corner cuts half the d×d corner square: −4·(d²/2).
        #expect(abs(area(result) - (14400 - 200)) < 1e-3)
    }

    // MARK: Results stay ordinary shapes

    @Test func resultsSurviveMapPoints() {
        let result = square(x: 0, y: 0, size: 10).union(square(x: 5, y: 5, size: 10))
            .mapPoints { Vector2($0.x * 2, $0.y * 2) }
        #expect(abs(area(result) - 700) < 1e-6) // 175 × 4
        #expect(result.winding == .nonZero)
    }
}
