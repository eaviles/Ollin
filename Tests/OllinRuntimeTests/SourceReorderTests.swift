import Ollin
@testable import OllinRuntime
import Testing

/// Moving a shape among the shapes drawn beside it, by moving its line.
///
/// Every check takes a line and the byte column of a call's `(`, the way the
/// live host does, and asks for the file back with the shape moved past its
/// neighbor. The ink rules are the whole subject: what is carried, what is
/// put back, what is removed, and what refuses.
@Suite
struct SourceReorderTests {

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

    private func moved(_ text: String, call: String,
                       _ step: SourceReorderStep) throws -> SourceEdit.Reorder {
        let at = site(of: call, in: text)
        return try SourceEdit.reordering(text, line: at.line, column: at.column, by: step)
    }

    private func failure(_ text: String, call: String,
                         _ step: SourceReorderStep) -> SourceEdit.Failure? {
        do {
            _ = try moved(text, call: call, step)
            return nil
        } catch let failure as SourceEdit.Failure {
            return failure
        } catch {
            return nil
        }
    }

    private func block(_ body: String) -> String {
        "import Ollin\n\nfinal class S: Sketch {\n    override func draw() {\n" + body + "    }\n}\n"
    }

    // MARK: Sharing ink

    @Test func twoShapesSharingInkSwapLines() throws {
        let text = block("""
                fill(.black)
                drawCircle(1, 1, 1)
                drawRect(2, 2, 2, 2)

        """)
        let out = try moved(text, call: "drawCircle(1", .forward)
        #expect(out.text == block("""
                fill(.black)
                drawRect(2, 2, 2, 2)
                drawCircle(1, 1, 1)

        """))
        #expect(out.steps == 1)
        #expect(out.line == 7)
        // And back again is the file as it was.
        let back = try moved(out.text, call: "drawCircle(1", .backward)
        #expect(back.text == text)
    }

    @Test func aTrailingCommentTravelsWithItsLine() throws {
        let text = block("""
                drawCircle(1, 1, 1)   // under
                drawCircle(2, 2, 2)   // over

        """)
        let out = try moved(text, call: "drawCircle(1", .forward)
        #expect(out.text.contains("drawCircle(2, 2, 2)   // over\n        drawCircle(1, 1, 1)   // under"))
    }

    // MARK: Carrying ink

    @Test func forwardCarriesItsFillAndPutsTheirsBack() throws {
        let text = block("""
                fill(.red)
                drawCircle(1, 1, 1)
                fill(.white)
                drawCircle(2, 2, 2)
                drawCircle(3, 3, 3)

        """)
        let out = try moved(text, call: "drawCircle(1", .forward)
        #expect(out.text == block("""
                fill(.white)
                drawCircle(2, 2, 2)
                fill(.red)
                drawCircle(1, 1, 1)
                fill(.white)
                drawCircle(3, 3, 3)

        """))
    }

    @Test func nothingAfterMeansNothingToPutBack() throws {
        let text = block("""
                fill(.red)
                drawCircle(1, 1, 1)
                fill(.white)
                drawCircle(2, 2, 2)

        """)
        let out = try moved(text, call: "drawCircle(1", .forward)
        #expect(out.text == block("""
                fill(.white)
                drawCircle(2, 2, 2)
                fill(.red)
                drawCircle(1, 1, 1)

        """))
    }

    @Test func backwardCarriesItsInkAndLeavesTheNeighborsOwn() throws {
        let text = block("""
                fill(.red)
                drawCircle(1, 1, 1)
                fill(.white)
                drawCircle(2, 2, 2)
                drawCircle(3, 3, 3)

        """)
        let out = try moved(text, call: "drawCircle(2", .backward)
        #expect(out.text == block("""
                fill(.white)
                drawCircle(2, 2, 2)
                fill(.red)
                drawCircle(1, 1, 1)
                fill(.white)
                drawCircle(3, 3, 3)

        """))
    }

    @Test func aMoveAndItsReverseLeaveTheFileAsItWas() throws {
        let text = block("""
                fill(.black)
                drawCircle(200, 300, 80)      // under
                fill(.red)
                drawCircle(260, 300, 80)      // over
                drawRect(500, 500, 40, 40)

        """)
        let forward = try moved(text, call: "drawCircle(200", .forward)
        #expect(forward.text == block("""
                fill(.red)
                drawCircle(260, 300, 80)      // over
                fill(.black)
                drawCircle(200, 300, 80)      // under
                fill(.red)
                drawRect(500, 500, 40, 40)

        """))
        let back = try moved(forward.text, call: "drawCircle(200", .backward)
        #expect(back.text == text, "the restore the first move added is redundant once undone, and goes")
    }

    @Test func theInkTheDrawerStartsWithIsWrittenOut() throws {
        let text = block("""
                drawCircle(1, 1, 1)
                fill(.red)
                drawCircle(2, 2, 2)

        """)
        let out = try moved(text, call: "drawCircle(1", .forward)
        #expect(out.text == block("""
                fill(.red)
                drawCircle(2, 2, 2)
                fill(.white)
                drawCircle(1, 1, 1)

        """))
    }

    @Test func strokeIsCarriedLikeFill() throws {
        let text = block("""
                noStroke()
                fill(.red)
                drawCircle(1, 1, 1)
                stroke(.black)
                strokeWeight(3)
                drawLine(0, 0, 9, 9)
                drawLine(1, 1, 8, 8)

        """)
        let out = try moved(text, call: "drawCircle(1", .forward)
        #expect(out.text == block("""
                fill(.red)
                stroke(.black)
                strokeWeight(3)
                drawLine(0, 0, 9, 9)
                noStroke()
                drawCircle(1, 1, 1)
                stroke(.black)
                drawLine(1, 1, 8, 8)

        """), "the circle keeps its noStroke, the second line gets its stroke back, and the weight was never the circle's to carry")
    }

    @Test func aCommentAboveTheShapeTravelsWithIt() throws {
        let text = block("""
                // the face
                fill(.red)
                drawCircle(1, 1, 1)
                fill(.white)
                drawCircle(2, 2, 2)

        """)
        let out = try moved(text, call: "drawCircle(1", .forward)
        #expect(out.text == block("""
                fill(.white)
                drawCircle(2, 2, 2)
                // the face
                fill(.red)
                drawCircle(1, 1, 1)

        """))
    }

    @Test func aCallSpreadOverLinesMovesWhole() throws {
        let text = block("""
                drawRect(corner: Vector2(10, 10),
                         width: 200, height: 100)
                drawCircle(2, 2, 2)

        """)
        let out = try moved(text, call: "drawRect(", .forward)
        #expect(out.text == block("""
                drawCircle(2, 2, 2)
                drawRect(corner: Vector2(10, 10),
                         width: 200, height: 100)

        """))
        #expect(out.line == 6)
    }

    // MARK: All the way

    @Test func toTheFrontPassesEverySibling() throws {
        let text = block("""
                drawCircle(1, 1, 1)
                drawCircle(2, 2, 2)
                drawCircle(3, 3, 3)

        """)
        let out = try moved(text, call: "drawCircle(1", .toFront)
        #expect(out.steps == 2)
        #expect(out.stoppedBy == nil)
        #expect(out.text == block("""
                drawCircle(2, 2, 2)
                drawCircle(3, 3, 3)
                drawCircle(1, 1, 1)

        """))
        let back = try moved(out.text, call: "drawCircle(1", .toBack)
        #expect(back.text == text)
    }

    @Test func toTheFrontStopsWhereItCannotPass() throws {
        let text = block("""
                drawCircle(1, 1, 1)
                drawCircle(2, 2, 2)
                translate(10, 10)
                drawCircle(3, 3, 3)

        """)
        let out = try moved(text, call: "drawCircle(1", .toFront)
        #expect(out.steps == 1)
        #expect(out.stoppedBy == "translate(10, 10)")
        #expect(out.text.contains("drawCircle(2, 2, 2)\n        drawCircle(1, 1, 1)\n        translate"))
    }

    // MARK: Refusals

    @Test func theFirstAndLastShapesHaveNowhereToGo() {
        let text = block("""
                drawCircle(1, 1, 1)
                drawCircle(2, 2, 2)

        """)
        #expect(failure(text, call: "drawCircle(1", .backward) == .alreadyAtTheEdge)
        #expect(failure(text, call: "drawCircle(2", .forward) == .alreadyAtTheEdge)
        #expect(failure(text, call: "drawCircle(2", .toFront) == .alreadyAtTheEdge)
    }

    @Test func somethingThatIsNotInkBetweenThemRefusesByName() {
        let text = block("""
                drawCircle(1, 1, 1)
                translate(10, 10)
                drawCircle(2, 2, 2)

        """)
        #expect(failure(text, call: "drawCircle(1", .forward) == .blockedBy(statement: "translate(10, 10)"))
        #expect(failure(text, call: "drawCircle(2", .backward) == .blockedBy(statement: "translate(10, 10)"))
    }

    @Test func aNestedBlockBetweenThemRefuses() {
        let text = block("""
                drawCircle(1, 1, 1)
                withState {
                    rotate(0.3)
                    drawRect(0, 0, 5, 5)
                }
                drawCircle(2, 2, 2)

        """)
        #expect(failure(text, call: "drawCircle(1", .forward) == .blockedBy(statement: "withState {"))
        // A shape inside the nested block moves among its own siblings only.
        #expect(failure(text, call: "drawRect(0", .forward) == .alreadyAtTheEdge)
        #expect(failure(text, call: "drawRect(0", .backward) == .blockedBy(statement: "rotate(0.3)"))
    }

    @Test func inkNobodyCanReadOffTheBlockRefuses() {
        let text = block("""
                drawCircle(1, 1, 1)
                strokeCap(.round)
                drawLine(0, 0, 9, 9)

        """)
        #expect(failure(text, call: "drawCircle(1", .forward) == .inkUnknown(statement: "strokeCap(.round)"))
    }

    @Test func aCallSharingItsLineIsRefused() {
        let text = block("""
                drawCircle(1, 1, 1); count += 1
                drawCircle(2, 2, 2)

        """)
        #expect(failure(text, call: "drawCircle(1", .forward) == .notAlone(line: "drawCircle(1, 1, 1); count += 1"))
    }

    @Test func aMissingCallIsReportedAsSuch() {
        let text = block("""
                drawCircle(1, 1, 1)

        """)
        do {
            _ = try SourceEdit.reordering(text, line: 40, column: 9, by: .forward)
            Issue.record("a line past the end should not find a call")
        } catch let failure as SourceEdit.Failure {
            #expect(failure == .callNotFound)
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
}
