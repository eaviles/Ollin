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
}
