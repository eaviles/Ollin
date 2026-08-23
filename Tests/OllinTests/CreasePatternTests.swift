@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on crease patterns. Every one of these is a law rather than
/// a matter of taste, and that is the point: a fold pattern that is slightly
/// wrong draws exactly as well as a right one, and only fails when somebody
/// tries to fold the paper.
///
/// The load-bearing pair is Kawasaki's law on the flat sheet and the folded
/// sheet built from the same numbers. The first says the pattern *could* fold
/// flat. The second is worked out independently, from lengths and angles
/// alone, and it is what settles the mountain and valley marks: the flat
/// pattern claims them, the folded sheet proves them.
@Suite
struct CreasePatternTests {

    // MARK: - Helpers

    /// The mountain or valley mark that a folded sheet actually shows along one
    /// crease, worked out from the three-dimensional shape rather than from the
    /// rule the pattern was built with.
    ///
    /// Take the two panels that meet along the crease, and look at where their
    /// middles sit once the direction of the crease itself is taken out. If
    /// they both lean below the crease, the crease stands up as a ridge, which
    /// is a mountain. If they lean above it, it is a groove, which is a valley.
    private func foldedMark(_ sheet: MiuraFold,
                            from start: Vector3, to end: Vector3,
                            panels: [[Vector3]]) -> CreasePattern.Assignment {
        let along = (end - start)
        let direction = along / along.length
        let middle = (start + end) * 0.5
        var lean = Vector3.zero
        for panel in panels {
            var centroid = Vector3.zero
            for corner in panel { centroid += corner }
            centroid /= Double(panel.count)
            let offset = centroid - middle
            lean += offset - direction * offset.dot(direction)
        }
        return lean.z < 0 ? .mountain : .valley
    }

    /// The panel with these two vertices as one of its sides.
    private func panels(of sheet: MiuraFold, touching a: (Int, Int), and b: (Int, Int)) -> [[Vector3]] {
        var found: [[Vector3]] = []
        for row in 0 ..< sheet.rows {
            for column in 0 ..< sheet.columns {
                let corners = [(column, row), (column + 1, row), (column + 1, row + 1), (column, row + 1)]
                if corners.contains(where: { $0 == a }) && corners.contains(where: { $0 == b }) {
                    found.append(corners.map { sheet.point(column: $0.0, row: $0.1) })
                }
            }
        }
        return found
    }

    // MARK: - Reading a pattern

    /// Lines that end at the same place share a vertex. A Miura sheet is a
    /// lattice, so the count is known before anything is built.
    @Test func linesThatMeetShareAVertex() {
        let sheet = MiuraFold(columns: 7, rows: 5)
        let pattern = sheet.pattern
        #expect(pattern.vertices.count == 8 * 6)
        #expect(pattern.creases.count == 7 * 6 + 8 * 5)
        // Fitting the sheet to a canvas-sized frame must not split any of them.
        let placed = pattern.fitted(in: Rectangle(x: 0, y: 0, width: 1080, height: 1080))
        #expect(placed.vertices.count == 8 * 6)
    }

    /// Lines of one kind that carry straight on through a vertex come out as
    /// one stroke, because that is what a pen or a blade wants.
    @Test func onePenStrokeRunsThroughAVertex() {
        let straight = CreasePattern([
            .init(from: Vector2(0, 0), to: Vector2(1, 0), .mountain),
            .init(from: Vector2(1, 0), to: Vector2(2, 0), .mountain),
            .init(from: Vector2(2, 0), to: Vector2(3, 0), .mountain),
        ])
        let strokes = straight.contours(.mountain)
        #expect(strokes.count == 1)
        #expect(strokes[0].points.count == 4)
        #expect(strokes[0].isClosed == false)
        let ends = [strokes[0].points.first!, strokes[0].points.last!].sorted { $0.x < $1.x }
        #expect(ends[0].distance(to: Vector2(0, 0)) < 1e-12)
        #expect(ends[1].distance(to: Vector2(3, 0)) < 1e-12)
    }

    /// Where three lines of one kind meet, the stroke takes the straightest
    /// turn and the odd one out becomes its own stroke.
    @Test func aJunctionKeepsTheStraightestTurn() {
        let tee = CreasePattern([
            .init(from: Vector2(-1, 0), to: Vector2(0, 0), .valley),
            .init(from: Vector2(0, 0), to: Vector2(1, 0), .valley),
            .init(from: Vector2(0, 0), to: Vector2(0, 1), .valley),
        ])
        let strokes = tee.contours(.valley).sorted { $0.points.count > $1.points.count }
        #expect(strokes.count == 2)
        #expect(strokes[0].points.count == 3)
        #expect(strokes[1].points.count == 2)
    }

    /// A ring of lines comes back to where it started, and says so.
    @Test func aRingComesOutClosed() {
        let square = CreasePattern([
            .init(from: Vector2(0, 0), to: Vector2(1, 0), .cut),
            .init(from: Vector2(1, 0), to: Vector2(1, 1), .cut),
            .init(from: Vector2(1, 1), to: Vector2(0, 1), .cut),
            .init(from: Vector2(0, 1), to: Vector2(0, 0), .cut),
        ])
        let strokes = square.contours(.cut)
        #expect(strokes.count == 1)
        #expect(strokes[0].isClosed)
        #expect(strokes[0].points.count == 4)
    }

    /// Joining lines into strokes must not lose or repeat one.
    @Test func everyLineIsDrawnExactlyOnce() {
        let pattern = MiuraFold(columns: 6, rows: 4).pattern
        var drawn = 0
        for kind in CreasePattern.Assignment.allCases {
            for stroke in pattern.contours(kind) {
                drawn += stroke.isClosed ? stroke.points.count : stroke.points.count - 1
            }
        }
        #expect(drawn == pattern.creases.count)
    }

    // MARK: - The two laws

    /// Kawasaki's law at every interior vertex of a Miura sheet, at several
    /// shapes of parallelogram. Add the angles between one fold and the next
    /// all the way around, taking every second one away, and the answer is
    /// zero.
    @Test func kawasakiHoldsAtEveryInteriorVertex() {
        for angle in [0.4, 0.8, 1.1, Double.pi / 3] {
            let pattern = MiuraFold(columns: 6, rows: 5, major: 1.7, minor: 1.1, angle: angle).pattern
            let inside = pattern.interiorVertices
            #expect(inside.count == 5 * 4)
            for vertex in inside {
                #expect(abs(pattern.kawasakiResidual(at: vertex)) < 1e-12)
            }
        }
    }

    /// Maekawa's law at the same vertices: the mountains and the valleys
    /// meeting there differ by exactly two.
    @Test func maekawaHoldsAtEveryInteriorVertex() {
        let pattern = MiuraFold(columns: 6, rows: 5).pattern
        for vertex in pattern.interiorVertices {
            #expect(abs(pattern.maekawaResidual(at: vertex)) == 2)
        }
        #expect(pattern.isFlatFoldable)
    }

    /// Moving one interior vertex breaks the sheet, and it breaks it only
    /// where the moving is felt. Without this the two laws above could be
    /// reading zero for some reason of their own.
    ///
    /// The reach is the law here, and it is wider than it first looks: the
    /// vertex that moved breaks, and so do the four it is joined to, because
    /// the folds that run between them now arrive at a different angle. Nothing
    /// further away moves at all.
    @Test func movingOneVertexBreaksTheSheetWhereItIsFelt() {
        let pattern = MiuraFold(columns: 6, rows: 5).pattern
        let target = pattern.interiorVertices[7]
        let bent = pattern.mapPoints {
            $0.distance(to: target) < 1e-9 ? $0 + Vector2(0.13, 0.07) : $0
        }
        #expect(bent.isFlatFoldable == false)

        let moved = target + Vector2(0.13, 0.07)
        let joined = bent.creases
            .filter { $0.start.distance(to: moved) < 1e-9 || $0.end.distance(to: moved) < 1e-9 }
            .map { $0.start.distance(to: moved) < 1e-9 ? $0.end : $0.start }
        #expect(joined.count == 4)

        var broken = 0
        for vertex in bent.interiorVertices {
            let residual = abs(bent.kawasakiResidual(at: vertex))
            let felt = vertex.distance(to: moved) < 1e-9
                || joined.contains { $0.distance(to: vertex) < 1e-9 }
            if felt { #expect(residual > 1e-3); broken += 1 } else { #expect(residual < 1e-12) }
        }
        #expect(broken == 5)
    }

    /// Scaling the sheet by the same amount in both directions keeps every
    /// angle, so it keeps both laws. This is what lets a pattern be fitted to
    /// the canvas and still be a foldable pattern.
    @Test func fittingTheSheetKeepsTheLaws() {
        let pattern = MiuraFold(columns: 5, rows: 4, angle: 1.0).pattern
        let placed = pattern.fitted(in: Rectangle(x: 40, y: 60, width: 900, height: 700))
        #expect(placed.isFlatFoldable)
        for vertex in placed.interiorVertices {
            #expect(abs(placed.kawasakiResidual(at: vertex)) < 1e-11)
        }
        // and it really did move and grow
        #expect(placed.bounds.width > 800)
        #expect(placed.bounds.center.x > 400)
    }

    /// A sheet that is only cut, never folded, is not asked to fold flat. There
    /// are no interior vertices at all, because a cut means the paper stops.
    @Test func aCutSheetIsNotAskedToFoldFlat() {
        let sheet = RotatingSquares(columns: 4, rows: 4, side: 10, ligament: 1)
        #expect(sheet.pattern.interiorVertices.isEmpty)
        #expect(sheet.pattern.isFlatFoldable)
    }

    // MARK: - The Miura pattern on the page

    /// The shape of a Miura pattern, which is how it is recognized: every
    /// zigzag fold running down the sheet is a mountain or a valley for its
    /// whole length, and the zigzags take turns across the sheet. Every
    /// straight fold running across the sheet changes kind at each step, and
    /// each row starts on the opposite kind from the one above.
    @Test func theZigzagsAreUniformAndTheStraightFoldsAlternate() {
        let sheet = MiuraFold(columns: 6, rows: 5)
        let pattern = sheet.pattern
        var byLine: [String: [CreasePattern.Assignment]] = [:]
        for crease in pattern.creases where crease.assignment.isFold {
            let alongX = abs(crease.start.y - crease.end.y) < 1e-12
            let key = alongX ? "row \(crease.start.y)" : "column"
            if alongX { byLine[key, default: []].append(crease.assignment) }
        }
        // Straight folds: each row alternates along its length.
        for (_, marks) in byLine {
            for index in 1 ..< marks.count { #expect(marks[index] != marks[index - 1]) }
        }
        // Zigzag folds: uniform down a column, alternating across.
        for column in 1 ..< sheet.columns {
            let wanted: CreasePattern.Assignment = column % 2 == 1 ? .mountain : .valley
            for row in 0 ..< sheet.rows {
                let a = sheet.flatPoint(column: column, row: row)
                let b = sheet.flatPoint(column: column, row: row + 1)
                let found = pattern.creases.first {
                    $0.start.distance(to: a) < 1e-12 && $0.end.distance(to: b) < 1e-12
                }
                #expect(found?.assignment == wanted)
            }
        }
        // Two rows one under the other start on opposite kinds. Which kind is
        // which is not for this test to say: turning the sheet over swaps them,
        // and the folded sheet is what settles it.
        let starts = (1 ..< sheet.rows).map { row in
            pattern.creases.first {
                $0.start.distance(to: sheet.flatPoint(column: 0, row: row)) < 1e-12
                    && $0.end.distance(to: sheet.flatPoint(column: 1, row: row)) < 1e-12
            }?.assignment
        }
        #expect(starts.allSatisfy { $0 != nil })
        for index in 1 ..< starts.count { #expect(starts[index] != starts[index - 1]) }
    }

    // MARK: - The Miura sheet folded

    /// With nothing folded, the three-dimensional sheet is the flat one.
    @Test func nothingFoldedIsTheFlatSheet() {
        let sheet = MiuraFold(columns: 4, rows: 3, major: 1.3, minor: 0.9, angle: 1.05, fold: 0)
        for row in 0 ... sheet.rows {
            for column in 0 ... sheet.columns {
                let folded = sheet.point(column: column, row: row)
                let flat = sheet.flatPoint(column: column, row: row)
                #expect(folded.z == 0)
                #expect(folded.xy.distance(to: flat) < 1e-12)
            }
        }
        #expect(abs(sheet.height) < 1e-12)
    }

    /// The load-bearing law: paper does not stretch. Every crease is the same
    /// length in the folded sheet as it is on the flat one, at every stage of
    /// the fold. A folding that fails this is not a folding at all.
    @Test func paperDoesNotStretch() {
        let angles = [0.5, 0.9, Double.pi / 3, 1.4]
        for angle in angles {
            for step in 0 ... 10 {
                var sheet = MiuraFold(columns: 5, rows: 4, major: 1.7, minor: 1.1, angle: angle)
                sheet.fold = Double(step) / 10
                for row in 0 ... sheet.rows {
                    for column in 0 ... sheet.columns {
                        let here = sheet.point(column: column, row: row)
                        if column < sheet.columns {
                            let across = sheet.point(column: column + 1, row: row)
                            #expect(abs(here.distance(to: across) - sheet.major) < 1e-12)
                        }
                        if row < sheet.rows {
                            let down = sheet.point(column: column, row: row + 1)
                            #expect(abs(here.distance(to: down) - sheet.minor) < 1e-12)
                        }
                    }
                }
            }
        }
    }

    /// Every panel stays flat, and stays the same parallelogram it was cut as.
    /// This is why stiff material folds the same way paper does: nothing has to
    /// bend except at a crease.
    @Test func everyPanelStaysFlatAndKeepsItsShape() {
        for step in 1 ... 9 {
            var sheet = MiuraFold(columns: 4, rows: 4, major: 1.4, minor: 0.8, angle: 1.1)
            sheet.fold = Double(step) / 10
            for panel in sheet.facets {
                let e1 = panel[1] - panel[0]
                let e2 = panel[3] - panel[0]
                // flat: the fourth corner is exactly where the other two sides put it
                let closing = panel[0] + e1 + e2
                #expect(closing.distance(to: panel[2]) < 1e-12)
                // the same corner it was cut with
                let corner = acos(Swift.min(1, Swift.max(-1, e1.dot(e2) / (e1.length * e2.length))))
                let matches = abs(corner - sheet.angle) < 1e-12 || abs(corner - (.pi - sheet.angle)) < 1e-12
                #expect(matches)
            }
        }
    }

    /// The mountain and valley marks on the flat pattern are the ones the
    /// folded sheet shows. The pattern works them out from a rule about odd and
    /// even; this reads them off the three-dimensional shape instead, so the
    /// two have to agree for the right reason.
    @Test func theFoldedSheetShowsTheMarksThePatternClaims() {
        for step in [2, 4, 6, 8] {
            var sheet = MiuraFold(columns: 5, rows: 4, major: 1.3, minor: 1.0, angle: 1.0)
            sheet.fold = Double(step) / 10
            let pattern = sheet.pattern
            var checked = 0
            for row in 1 ..< sheet.rows {                 // straight folds, inside the sheet
                for column in 0 ..< sheet.columns {
                    let claimed = pattern.creases.first {
                        $0.start.distance(to: sheet.flatPoint(column: column, row: row)) < 1e-12
                            && $0.end.distance(to: sheet.flatPoint(column: column + 1, row: row)) < 1e-12
                    }
                    let shown = foldedMark(sheet,
                                           from: sheet.point(column: column, row: row),
                                           to: sheet.point(column: column + 1, row: row),
                                           panels: panels(of: sheet, touching: (column, row), and: (column + 1, row)))
                    #expect(claimed?.assignment == shown)
                    checked += 1
                }
            }
            for column in 1 ..< sheet.columns {           // zigzag folds, inside the sheet
                for row in 0 ..< sheet.rows {
                    let claimed = pattern.creases.first {
                        $0.start.distance(to: sheet.flatPoint(column: column, row: row)) < 1e-12
                            && $0.end.distance(to: sheet.flatPoint(column: column, row: row + 1)) < 1e-12
                    }
                    let shown = foldedMark(sheet,
                                           from: sheet.point(column: column, row: row),
                                           to: sheet.point(column: column, row: row + 1),
                                           panels: panels(of: sheet, touching: (column, row), and: (column, row + 1)))
                    #expect(claimed?.assignment == shown)
                    checked += 1
                }
            }
            #expect(checked == 3 * 5 + 4 * 4)
        }
    }

    /// The sheet shrinks in both directions at once, which is the property the
    /// Miura fold is famous for. Pull one way and it opens the other way too.
    @Test func theSheetMovesBothWaysAtOnce() {
        var narrower = 0
        var previous = Vector3(.infinity, .infinity, 0)
        for step in 0 ... 20 {
            var sheet = MiuraFold(columns: 8, rows: 6, major: 1.2, minor: 1.0, angle: 1.0)
            sheet.fold = Double(step) / 20
            let size = sheet.size
            if step > 0 {
                #expect(size.x < previous.x)          // narrower
                #expect(size.y < previous.y)          // and shorter, at the same time
                narrower += 1
            }
            previous = size
        }
        #expect(narrower == 20)
    }

    /// The number behind that: how much narrower the sheet gets for how much
    /// shorter, measured off the folded points themselves and checked against
    /// the closed form. It is negative, which is the whole story, and the two
    /// directions multiply to one.
    @Test func theAuxeticNumberIsWhatTheGeometrySays() {
        for step in [3, 5, 7] {
            let mid = Double(step) / 10
            let nudge = 1e-6
            func sheet(_ fold: Double) -> MiuraFold {
                MiuraFold(columns: 6, rows: 5, major: 1.4, minor: 0.9, angle: 1.0, fold: fold)
            }
            func cell(_ fold: Double) -> (width: Double, length: Double) {
                let here = sheet(fold)
                let origin = here.point(column: 0, row: 0)
                return (here.point(column: 1, row: 0).x - origin.x,
                        here.point(column: 0, row: 1).y - origin.y)
            }
            let before = cell(mid - nudge), after = cell(mid + nudge), here = cell(mid)
            let dWidth = (after.width - before.width) / (2 * nudge)
            let dLength = (after.length - before.length) / (2 * nudge)
            let measured = -(dWidth / here.width) / (dLength / here.length)
            let claimed = sheet(mid).poissonRatio
            #expect(claimed < 0)
            #expect(abs(measured - claimed) < 1e-4 * abs(claimed))
            #expect(abs(claimed * (1 / claimed) - 1) < 1e-12)
        }
    }

    /// Folded all the way, the sheet is a flat packet: it has no length left,
    /// and it stands as high as one panel leaning right over.
    @Test func foldedAllTheWayItIsAFlatPacket() {
        let sheet = MiuraFold(columns: 5, rows: 4, major: 1.3, minor: 0.9, angle: 1.0, fold: 1)
        #expect(abs(sheet.cellLength) < 1e-12)
        #expect(abs(sheet.cellShift - sheet.minor) < 1e-12)
        #expect(abs(sheet.height - sheet.major * sin(sheet.angle)) < 1e-12)
        let ys = (0 ... sheet.rows).map { sheet.point(column: 0, row: $0).y }
        #expect(ys.allSatisfy { abs($0) < 1e-12 })
    }

    // MARK: - The kirigami sheet

    /// The mechanism: two squares side by side stay joined at one corner
    /// however far the lattice is pulled open. If this fails the sheet tears.
    @Test func neighboringSquaresStayJoinedAtACorner() {
        for step in 0 ... 10 {
            var lattice = RotatingSquares(columns: 4, rows: 4, side: 2.5)
            lattice.opening = Double(step) / 10
            for row in 0 ..< lattice.rows {
                for column in 0 ..< lattice.columns {
                    let here = lattice.square(column: column, row: row).points
                    for neighbor in [(column + 1, row), (column, row + 1)]
                    where neighbor.0 < lattice.columns && neighbor.1 < lattice.rows {
                        let there = lattice.square(column: neighbor.0, row: neighbor.1).points
                        let closest = here.flatMap { a in there.map { a.distance(to: $0) } }.min() ?? .infinity
                        #expect(closest < 1e-12)
                    }
                }
            }
        }
    }

    /// Nothing stretches: every square keeps its side and its right angles
    /// whatever the opening.
    @Test func everySquareKeepsItsShape() {
        for step in 0 ... 10 {
            var lattice = RotatingSquares(columns: 3, rows: 3, side: 1.7)
            lattice.opening = Double(step) / 10
            for square in lattice.squares {
                let points = square.points
                for index in points.indices {
                    let side = points[index].distance(to: points[(index + 1) % points.count])
                    #expect(abs(side - lattice.side) < 1e-12)
                }
            }
        }
    }

    /// Closed, the squares tile the sheet with nothing between them.
    @Test func closedTheSquaresTileTheSheet() {
        let lattice = RotatingSquares(columns: 4, rows: 3, side: 2)
        #expect(abs(lattice.spacing - lattice.side) < 1e-12)
        let box = lattice.bounds
        #expect(abs(box.width - 8) < 1e-12)
        #expect(abs(box.height - 6) < 1e-12)
    }

    /// The lattice grows by the same amount in both directions at once, so the
    /// number that describes it is exactly `-1`. This is the far end of what a
    /// flat material can do.
    @Test func theLatticeGrowsTheSameAmountBothWays() {
        for step in [2, 5, 8] {
            let mid = Double(step) / 10
            let nudge = 1e-6
            func spread(_ opening: Double) -> (across: Double, down: Double) {
                var lattice = RotatingSquares(columns: 5, rows: 5, side: 3)
                lattice.opening = opening
                let origin = lattice.center(column: 0, row: 0)
                return (lattice.center(column: 4, row: 0).x - origin.x,
                        lattice.center(column: 0, row: 4).y - origin.y)
            }
            let before = spread(mid - nudge), after = spread(mid + nudge), here = spread(mid)
            let dAcross = (after.across - before.across) / (2 * nudge)
            let dDown = (after.down - before.down) / (2 * nudge)
            let measured = -(dAcross / here.across) / (dDown / here.down)
            #expect(abs(measured + 1) < 1e-6)
            var lattice = RotatingSquares(columns: 5, rows: 5, side: 3)
            lattice.opening = mid
            #expect(lattice.poissonRatio == -1)
        }
    }

    /// Open all the way, the holes are as big as the squares: half the sheet is
    /// hole. That is the most a rotating-squares sheet can open.
    @Test func openAllTheWayHalfTheSheetIsHole() {
        var lattice = RotatingSquares(columns: 6, rows: 6, side: 1)
        lattice.opening = 1
        #expect(abs(lattice.spacing - 2.0.squareRoot()) < 1e-12)
        let solid = Double(lattice.columns * lattice.rows) * lattice.side * lattice.side
        let covered = Double(lattice.columns * lattice.rows) * lattice.spacing * lattice.spacing
        #expect(abs(solid / covered - 0.5) < 1e-12)
    }

    /// The cuts are the grid lines with a thread of material left at both ends,
    /// which is what holds the sheet together. Every one is short by exactly
    /// two threads.
    @Test func theCutsLeaveAThreadAtEachEnd() {
        let lattice = RotatingSquares(columns: 5, rows: 4, side: 6, ligament: 0.5)
        let cuts = lattice.pattern.creases(.cut)
        #expect(cuts.count == 4 * 4 + 3 * 5)
        for cut in cuts { #expect(abs(cut.length - (6 - 1)) < 1e-12) }
        #expect(lattice.pattern.creases(.boundary).count == 4)
        // A thread as wide as the square leaves nothing to cut.
        let uncut = RotatingSquares(columns: 5, rows: 4, side: 6, ligament: 3)
        #expect(uncut.pattern.creases(.cut).isEmpty)
    }
}
