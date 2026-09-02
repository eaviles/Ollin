import Ollin
@testable import OllinRuntime
import Testing

/// Moving a shape by rewriting the numbers in the file it was drawn from.
///
/// Every check works the way the live host does: it takes a line and the byte
/// column of a call's `(` (what `#line` and `#column` report at the call site)
/// and asks for the file back with the shape moved. No GPU, no compile.
@Suite
struct SourceEditTests {

    /// The 1-based line and byte column of the `(` after `needle` in `text`.
    private func site(of needle: String, in text: String) -> (line: Int, column: Int) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            guard let found = line.range(of: needle) else { continue }
            let before = line[line.startIndex ..< found.upperBound]
            return (index + 1, before.utf8.count + 1)
        }
        Issue.record("no \(needle) in the text")
        return (1, 1)
    }

    private func moved(_ text: String, call: String, move: SourceMove,
                       by delta: Vector2) throws -> String {
        let at = site(of: call, in: text)
        return try SourceEdit.moving(text, line: at.line, column: at.column, move: move, by: delta)
    }

    private func resized(_ text: String, call: String, move: SourceMove,
                         by factor: Vector2) throws -> String {
        let at = site(of: call, in: text)
        return try SourceEdit.resizing(text, line: at.line, column: at.column,
                                       move: move, by: factor)
    }

    private func turned(_ text: String, call: String, move: SourceMove,
                        by angle: Double) throws -> String {
        let at = site(of: call, in: text)
        return try SourceEdit.turning(text, line: at.line, column: at.column,
                                      move: move, by: angle)
    }

    private func planned(_ text: String, call: String, move: SourceMove,
                         by delta: Vector2) throws -> SourceEdit.MovePlan {
        let at = site(of: call, in: text)
        return try SourceEdit.planningMove(text, line: at.line, column: at.column,
                                           move: move, by: delta)
    }

    // MARK: The everyday case

    @Test func aWholeNumberStaysWhole() throws {
        let out = try moved("drawCircle(200, 300, 40)", call: "drawCircle",
                            move: .xy, by: Vector2(13, -7))
        #expect(out == "drawCircle(213, 293, 40)")
    }

    @Test func aFractionKeepsItsDigits() throws {
        let out = try moved("drawCircle(200.0, 300.25, 40)", call: "drawCircle",
                            move: .xy, by: Vector2(0.5, 0.5))
        #expect(out == "drawCircle(200.5, 300.75, 40)")
    }

    /// A drag under half a point leaves a whole number where it was, which is
    /// what puts a dragged shape back on the grid instead of at 200.4.
    @Test func aSmallDragDoesNotUnroundTheNumbers() throws {
        let out = try moved("drawCircle(200, 300, 40)", call: "drawCircle",
                            move: .xy, by: Vector2(0.4, -0.4))
        #expect(out == "drawCircle(200, 300, 40)")
    }

    @Test func onlyTheCoordinatesChange() throws {
        let out = try moved("drawRect(10, 20, 300, 120, cornerRadius: 8)", call: "drawRect",
                            move: .xy, by: Vector2(5, 5))
        #expect(out == "drawRect(15, 25, 300, 120, cornerRadius: 8)")
    }

    @Test func aNegativeNumberMovesToo() throws {
        let out = try moved("drawCircle(-40, -10, 12)", call: "drawCircle",
                            move: .xy, by: Vector2(50, 20))
        #expect(out == "drawCircle(10, 10, 12)")
    }

    // MARK: Points, and shapes with two ends

    @Test func aPointArgumentMovesInsideItsVector() throws {
        let out = try moved("drawCircle(center: Vector2(100, 100), radius: 30)",
                            call: "drawCircle", move: .point, by: Vector2(-20, 40))
        #expect(out == "drawCircle(center: Vector2(80, 140), radius: 30)")
    }

    @Test func bothEndsOfALineMove() throws {
        let out = try moved("drawLine(0, 0, 100, 50)", call: "drawLine",
                            move: .scalars([0, 1, 2, 3]), by: Vector2(10, 10))
        #expect(out == "drawLine(10, 10, 110, 60)")
    }

    @Test func bothPointsOfALineMove() throws {
        let out = try moved("drawLine(Vector2(0, 0), Vector2(100, 50))", call: "drawLine",
                            move: .points([0, 1]), by: Vector2(4, 4))
        #expect(out == "drawLine(Vector2(4, 4), Vector2(104, 54))")
    }

    // MARK: What the author wrote survives

    /// The whole reason this is a scanner and not a formatter: it replaces the
    /// text of numbers that are already there and touches nothing else.
    @Test func spacingAndCommentsSurvive() throws {
        let text = """
            // A dot, deliberately off center.
            drawCircle(  200 ,   300 ,  40 )   // the eye
            """
        let out = try moved(text, call: "drawCircle", move: .xy, by: Vector2(1, 1))
        #expect(out == """
            // A dot, deliberately off center.
            drawCircle(  201 ,   301 ,  40 )   // the eye
            """)
    }

    @Test func aCallSpreadOverLinesIsStillOneCall() throws {
        let text = """
            drawRect(40,
                     60,
                     200, 100)
            """
        let out = try moved(text, call: "drawRect", move: .xy, by: Vector2(-10, 10))
        #expect(out == """
            drawRect(30,
                     70,
                     200, 100)
            """)
    }

    /// Byte columns, not character columns: an accented comment ahead of the
    /// call must not shift the edit by a byte.
    @Test func anAccentedLineEditsAtTheRightPlace() throws {
        let text = "/* pequeño círculo */ drawCircle(200, 300, 40)"
        let out = try moved(text, call: "drawCircle", move: .xy, by: Vector2(2, 2))
        #expect(out == "/* pequeño círculo */ drawCircle(202, 302, 40)")
    }

    /// A comma inside a string is not an argument separator.
    @Test func aStringArgumentIsNotSplit() throws {
        let text = #"drawText("one, two", 10, 20)"#
        let at = site(of: "drawText", in: text)
        let out = try SourceEdit.moving(text, line: at.line, column: at.column,
                                        move: .scalars([1, 2]), by: Vector2(5, 5))
        #expect(out == #"drawText("one, two", 15, 25)"#)
    }

    @Test func aNestedCallIsOneArgument() throws {
        let text = "drawCircle(200, 300, max(10, 40))"
        let out = try moved(text, call: "drawCircle", move: .xy, by: Vector2(1, 0))
        #expect(out == "drawCircle(201, 300, max(10, 40))")
    }

    // MARK: What it refuses, and why

    @Test func acomputedCoordinateIsRefusedByName() throws {
        #expect(throws: SourceEdit.Failure.computed(argument: "width / 2")) {
            try moved("drawCircle(width / 2, 300, 40)", call: "drawCircle",
                      move: .xy, by: Vector2(1, 1))
        }
    }

    @Test func aNamedCoordinateIsRefusedByName() throws {
        #expect(throws: SourceEdit.Failure.computed(argument: "cx")) {
            try moved("drawCircle(cx, 300, 40)", call: "drawCircle",
                      move: .xy, by: Vector2(1, 1))
        }
    }

    /// A refused call is never half-written: the failure comes before any edit.
    @Test func aRefusalLeavesEveryNumberAlone() throws {
        let text = "drawCircle(200, cy, 40)"
        #expect(throws: SourceEdit.Failure.computed(argument: "cy")) {
            try moved(text, call: "drawCircle", move: .xy, by: Vector2(9, 9))
        }
    }

    @Test func aPointFromAVariableIsRefused() throws {
        #expect(throws: SourceEdit.Failure.notAPoint(argument: "middle")) {
            try moved("drawCircle(center: middle, radius: 30)", call: "drawCircle",
                      move: .point, by: Vector2(1, 1))
        }
    }

    @Test func aMissingArgumentIsRefused() throws {
        #expect(throws: SourceEdit.Failure.missingArgument(index: 1)) {
            try moved("drawCircle(200)", call: "drawCircle", move: .xy, by: Vector2(1, 1))
        }
    }

    @Test func aCallThatMovedAwayIsRefused() throws {
        #expect(throws: SourceEdit.Failure.callNotFound) {
            try SourceEdit.moving("drawCircle(200, 300, 40)", line: 9, column: 11,
                                  move: .xy, by: Vector2(1, 1))
        }
    }

    /// The column is a hint, not a requirement: a reformatted line still edits,
    /// because the call is found along the line it was reported on.
    @Test func aShiftedColumnStillFindsTheCall() throws {
        let out = try SourceEdit.moving("      drawCircle(200, 300, 40)", line: 1, column: 11,
                                        move: .xy, by: Vector2(1, 1))
        #expect(out == "      drawCircle(201, 301, 40)")
    }

    // MARK: Inside a real sketch

    @Test func oneCallOfManyMoves() throws {
        let text = """
            import Ollin

            @main final class Sketch: Ollin.Sketch {
                override func draw() {
                    background(.white)
                    fill(.black)
                    drawCircle(200, 200, 60)
                    drawCircle(400, 200, 60)
                    drawRect(100, 400, 300, 80)
                }
            }
            """
        // The second circle, on line 8.
        let out = try SourceEdit.moving(text, line: 8, column: 19, move: .xy, by: Vector2(0, 120))
        #expect(out.contains("drawCircle(200, 200, 60)"))
        #expect(out.contains("drawCircle(400, 320, 60)"))
        #expect(out.contains("drawRect(100, 400, 300, 80)"))
    }

    // MARK: Making it bigger

    @Test func aCornerScalesTheRadiusAndNothingElse() throws {
        let out = try resized("drawCircle(200, 300, 40)", call: "drawCircle",
                              move: .xy(radius: 2), by: Vector2(1.5, 1.5))
        #expect(out == "drawCircle(200, 300, 60)")
    }

    /// The position numbers stay as they are, so the shape grows from where the
    /// call says it stands. A corner radius is a detail, not a size.
    @Test func aResizeLeavesThePositionAndTheCornerRadius() throws {
        let out = try resized("drawRect(10, 20, 300, 120, cornerRadius: 8)", call: "drawRect",
                              move: .xy(width: 2, height: 3).fromCorner, by: Vector2(2, 0.5))
        #expect(out == "drawRect(10, 20, 600, 60, cornerRadius: 8)")
    }

    @Test func sizesThatScaleTogetherTakeOneFactor() throws {
        let out = try resized("drawStar(300, 300, 80, 40, points: 5)", call: "drawStar",
                              move: .xy(radii: [2, 3]), by: Vector2(0.5, 0.5))
        #expect(out == "drawStar(300, 300, 40, 20, points: 5)")
    }

    @Test func twoWidthsBothFollowTheSideTheyAreOn() throws {
        let out = try resized("drawTrapezoid(100, 100, 60, 120, 80)", call: "drawTrapezoid",
                              move: .xy(widths: [2, 3], height: 4), by: Vector2(2, 1))
        #expect(out == "drawTrapezoid(100, 100, 120, 240, 80)")
    }

    @Test func aResizedSizeKeepsTheDigitsItWasWrittenWith() throws {
        let out = try resized("drawCircle(200, 300, 40.5)", call: "drawCircle",
                              move: .xy(radius: 2), by: Vector2(2, 2))
        #expect(out == "drawCircle(200, 300, 81.0)")
    }

    @Test func aComputedSizeIsRefusedByName() throws {
        #expect(throws: SourceEdit.Failure.computed(argument: "radius * 2")) {
            try resized("drawCircle(200, 300, radius * 2)", call: "drawCircle",
                        move: .xy(radius: 2), by: Vector2(1.5, 1.5))
        }
    }

    @Test func aShapeWithNoSizeOnItsLineCannotBeResized() throws {
        #expect(throws: SourceEdit.Failure.nothingToSize) {
            try resized("drawLine(0, 0, 100, 50)", call: "drawLine",
                        move: .scalars([0, 1, 2, 3]), by: Vector2(2, 2))
        }
    }

    // MARK: Turning it

    /// A line swings about its own middle rather than travelling: both ends
    /// move, and the middle stays where it was.
    @Test func bothEndsSwingAboutTheMiddle() throws {
        let out = try turned("drawLine(0, 0, 100, 0)", call: "drawLine",
                             move: .scalars([0, 1, 2, 3]), by: .pi / 2)
        #expect(out == "drawLine(50, -50, 50, 50)")
    }

    @Test func aPointFormTurnsTheSameWay() throws {
        let out = try turned("drawLine(Vector2(0, 0), Vector2(100, 0))", call: "drawLine",
                             move: .points([0, 1]), by: .pi / 2)
        #expect(out == "drawLine(Vector2(50, -50), Vector2(50, 50))")
    }

    /// A half turn leaves a coordinate a hair under zero. Rounding that would
    /// write `-0`, which nobody types.
    @Test func aTurnNeverWritesNegativeZero() throws {
        let out = try turned("drawLine(0, 0, 100, 0)", call: "drawLine",
                             move: .scalars([0, 1, 2, 3]), by: .pi)
        #expect(out == "drawLine(100, 0, 0, 0)")
    }

    /// An arc carries its own angles, so turning it moves those instead of the
    /// point that places it. Three decimals at least: a whole radian is most of
    /// a quarter turn.
    @Test func anArcTurnsByItsOwnAngles() throws {
        let out = try turned("drawArc(300, 300, 100, 100, start: 0, stop: 1.5)", call: "drawArc",
                             move: .xy(width: 2, height: 3).turning(4, 5), by: 0.5)
        #expect(out == "drawArc(300, 300, 100, 100, start: 0.500, stop: 2.000)")
    }

    @Test func aShapeThatSaysNothingAboutItsAngleCannotTurn() throws {
        #expect(throws: SourceEdit.Failure.nothingToTurn) {
            try turned("drawCircle(200, 300, 40)", call: "drawCircle",
                       move: .xy(radius: 2), by: 0.4)
        }
    }

    @Test func aTurnRefusesAComputedEndByName() throws {
        #expect(throws: SourceEdit.Failure.computed(argument: "width - 20")) {
            try turned("drawLine(0, 0, width - 20, 50)", call: "drawLine",
                       move: .scalars([0, 1, 2, 3]), by: 0.4)
        }
    }

    // MARK: A coordinate that is a name

    /// The plan is what lets a host adjust a parameter where there is no number to
    /// write. The name is reported; whether it is a parameter is the host's question.
    @Test func aBareNameIsReportedRatherThanRefused() throws {
        let plan = try planned("drawCircle(cx, 300, 40)", call: "drawCircle",
                               move: .xy(radius: 2), by: Vector2(10, 5))
        #expect(plan.refused == nil)
        #expect(plan.names == [.init(name: "cx", delta: 10, isAcross: true)])
        // The coordinate that is a number is written; the one that is a name is not.
        #expect(plan.text == "drawCircle(cx, 305, 40)")
    }

    @Test func bothCoordinatesCanBeNames() throws {
        let plan = try planned("drawCircle(center: Vector2(cx, cy), radius: 40)",
                               call: "drawCircle", move: .point(radius: 1), by: Vector2(3, 4))
        #expect(plan.names == [.init(name: "cx", delta: 3, isAcross: true),
                               .init(name: "cy", delta: 4, isAcross: false)])
        #expect(plan.text == "drawCircle(center: Vector2(cx, cy), radius: 40)")
    }

    /// A calculation is not a name, and neither is a member of something: both
    /// stop the plan, and nothing is written.
    @Test func aCalculationStopsThePlan() throws {
        let plan = try planned("drawCircle(width / 2, 300, 40)", call: "drawCircle",
                               move: .xy(radius: 2), by: Vector2(10, 5))
        #expect(plan.refused == "width / 2")
        #expect(plan.text == "drawCircle(width / 2, 300, 40)")
    }

    @Test func aMemberIsNotABareName() throws {
        let plan = try planned("drawCircle(p.x, 300, 40)", call: "drawCircle",
                               move: .xy(radius: 2), by: Vector2(10, 5))
        #expect(plan.refused == "p.x")
    }
}
