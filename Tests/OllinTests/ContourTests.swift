import Testing
import Ollin

/// The contour walk helpers: length, arc-length `point(at:)`, and `midpoint`.
@Suite struct ContourTests {

    @Test func lengthWalksSegmentsAndClosingEdge() {
        let square = [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]
        #expect(Contour(square, closed: false).length == 30)
        #expect(Contour(square, closed: true).length == 40)
    }

    @Test func midpointIsByWalkedLengthNotIndex() {
        // Three points, unevenly spaced: half the length lands in the long leg.
        let uneven = Contour([Vector2(0, 0), Vector2(2, 0), Vector2(10, 0)], closed: false)
        #expect(uneven.midpoint == Vector2(5, 0))
        // A two-point diagonal's midpoint is its true middle (its index middle
        // would be an endpoint).
        let diagonal = Contour([Vector2(0, 0), Vector2(10, 10)], closed: false)
        #expect(diagonal.midpoint == Vector2(5, 5))
    }

    @Test func pointAtClampsAndHitsTheEnds() {
        let contour = Contour([Vector2(0, 0), Vector2(10, 0)], closed: false)
        #expect(contour.point(at: -1) == Vector2(0, 0))
        #expect(contour.point(at: 0) == Vector2(0, 0))
        #expect(contour.point(at: 0.25) == Vector2(2.5, 0))
        #expect(contour.point(at: 1) == Vector2(10, 0))
        #expect(contour.point(at: 2) == Vector2(10, 0))
    }

    @Test func closedWalkIncludesTheReturnLeg() {
        let square = Contour([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)],
                             closed: true)
        // Halfway around the 40-long loop is 20: the far corner.
        #expect(square.midpoint == Vector2(10, 10))
        // 0.875 of the way is 35: halfway down the closing leg.
        #expect(square.point(at: 0.875) == Vector2(0, 5))
    }

    @Test func degenerateContoursDontTrap() {
        #expect(Contour([], closed: false).length == 0)
        #expect(Contour([], closed: false).midpoint == .zero)
        #expect(Contour([Vector2(3, 4)], closed: true).length == 0)
        #expect(Contour([Vector2(3, 4)], closed: true).midpoint == Vector2(3, 4))
    }
}

/// The single-tile Truchet form: chosen spins, and the connectivity invariant
/// (arcs end on edge midpoints) that makes any arrangement join up.
@Suite struct TruchetTileTests {

    @Test func arcsEndAtEdgeMidpointsForBothSpins() {
        let rect = Rectangle(x: 0, y: 0, width: 10, height: 10)
        let doorways = [Vector2(5, 0), Vector2(10, 5), Vector2(5, 10), Vector2(0, 5)]
        for flipped in [false, true] {
            let arcs = Truchet.contours(in: rect, tile: .arcs, flipped: flipped)
            #expect(arcs.count == 2)
            for arc in arcs {
                for end in [arc.points.first!, arc.points.last!] {
                    let atDoorway = doorways.contains {
                        abs($0.x - end.x) < 1e-9 && abs($0.y - end.y) < 1e-9
                    }
                    #expect(atDoorway)
                }
            }
        }
    }

    @Test func diagonalSpins() {
        let rect = Rectangle(x: 0, y: 0, width: 10, height: 10)
        let falling = Truchet.contours(in: rect, tile: .diagonals)
        #expect(falling.count == 1)
        #expect(falling[0].points == [Vector2(0, 0), Vector2(10, 10)])
        let rising = Truchet.contours(in: rect, tile: .diagonals, flipped: true)
        #expect(rising[0].points == [Vector2(10, 0), Vector2(0, 10)])
    }

    @Test func singleTileMatchesTheGridPlacement() {
        // The grid form is exactly this geometry, one seeded spin per cell.
        let frame = Rectangle(x: 0, y: 0, width: 10, height: 10)
        var gridRng = SplitMix64(seed: 9)
        let placed = Truchet.contours(grid: Grid(in: frame, columns: 1, rows: 1),
                                      tile: .arcs, using: &gridRng)
        var spinRng = SplitMix64(seed: 9)
        let spin = Bool.random(using: &spinRng)
        #expect(placed == Truchet.contours(in: frame, tile: .arcs, flipped: spin))
    }

    @Test func resampledSpacesPointsEvenly() {
        // A 30-long open L, unevenly authored: even spacing lands every 5.
        let l = Contour([Vector2(0, 0), Vector2(20, 0), Vector2(20, 10)], closed: false)
        let even = l.resampled(spacing: 5)
        #expect(even.points.count == 7)
        #expect(!even.isClosed)
        for pair in zip(even.points, even.points.dropFirst()) {
            #expect(abs((pair.1 - pair.0).length - 5) < 1e-9)
        }
    }

    @Test func resampledClosedWalksTheClosingEdge() {
        // A 40-long closed square: 8 emits at spacing 5 cover the closing edge
        // too (the final emit lands back on the start).
        let square = Contour([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
        let even = square.resampled(spacing: 5)
        #expect(even.isClosed)
        #expect(even.points.count == 9)
        #expect((even.points[8] - even.points[0]).length < 1e-9)
        for pair in zip(even.points, even.points.dropFirst()) {
            #expect(abs((pair.1 - pair.0).length - 5) < 1e-9)
        }
    }

    @Test func resampledLeavesDegeneratesUntouched() {
        let dot = Contour([Vector2(3, 4)], closed: false)
        #expect(dot.resampled(spacing: 5) == dot)
        let line = Contour([Vector2(0, 0), Vector2(10, 0)], closed: false)
        #expect(line.resampled(spacing: 0) == line)
    }

    @Test func shapeResampledKeepsWinding() {
        let glyphish = Shape(contours: [Contour([Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)])],
                             winding: .nonZero)
        let even = glyphish.resampled(spacing: 6)
        #expect(even.winding == .nonZero)
        #expect(even.contours[0].points.count == 21)   // 120/6 emits + the start
    }
}

/// The vertical-center alias: `.center` is `.middle`.
@Suite struct TextAlignTests {
    @Test func centerAliasesMiddle() {
        #expect(VerticalTextAlign.center == .middle)
    }
}
