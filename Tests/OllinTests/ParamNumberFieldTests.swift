import AppKit
import Foundation
import Testing
@testable import Ollin

/// The inspector's number boxes: what a value reads as, what typed text means,
/// the grid a drag lands on, and what typing does to a value. The cases are the
/// ones a hands-on audit of the live host found (a first "2" in a box over
/// 10...375 turned into "10.00" before the second key; "300" over 50...500 came
/// out as 500; "90" in a range's maximum moved its minimum; Return rounded
/// 0.007 up to 0.01). No GPU, so it runs in CI.
@Suite
struct ParamNumberFieldTests {

    // MARK: Reading a value

    @Test func aValueReadsWithItsTrailingZerosTakenOff() {
        #expect(ParamNumberText.display(175) == "175")
        #expect(ParamNumberText.display(175.5) == "175.5")
        #expect(ParamNumberText.display(2.5) == "2.5")
        #expect(ParamNumberText.display(0.004) == "0.004")
        #expect(ParamNumberText.display(0.0064) == "0.0064")
        #expect(ParamNumberText.display(-2.25) == "-2.25")
        #expect(ParamNumberText.display(0) == "0")
        #expect(ParamNumberText.display(-0.0) == "0")
    }

    @Test func aValueNeverCarriesAGroupingSeparator() {
        #expect(ParamNumberText.display(1080) == "1080")
        #expect(ParamNumberText.display(25000) == "25000")
        #expect(ParamNumberText.display(1_234_567) == "1234567")
    }

    @Test func binaryNoiseDoesNotReachTheBox() {
        #expect(ParamNumberText.display(0.1 + 0.2) == "0.3")
        #expect(ParamNumberText.display(0.01 * 196) == "1.96")
        #expect(ParamNumberText.display(9.9999996) == "10")
        #expect(ParamNumberText.display(1e-15) == "0")
        // A value from outside (a rule, a MIDI binding) keeps six figures.
        #expect(ParamNumberText.display(243.28374629) == "243.284")
    }

    @Test func whatABoxShowsReadsBackAsTheSameValue() {
        for value in [175.0, 175.5, 0.004, 0.0064, 1080, 25000, -2.25, 3.75, 0.007, 1.864] {
            #expect(ParamNumberText.parse(ParamNumberText.display(value), decimalSeparator: ".") == value)
        }
    }

    // MARK: Reading typed text

    @Test func typedTextReadsAsANumberOnceItIsOne() {
        #expect(ParamNumberText.parse("2", decimalSeparator: ".") == 2)
        #expect(ParamNumberText.parse(" 12 ", decimalSeparator: ".") == 12)
        #expect(ParamNumberText.parse("5.", decimalSeparator: ".") == 5)
        #expect(ParamNumberText.parse(".5", decimalSeparator: ".") == 0.5)
        #expect(ParamNumberText.parse("\u{2212}3", decimalSeparator: ".") == -3)
        #expect(ParamNumberText.parse("1_000", decimalSeparator: ".") == 1000)
        for partial in ["", "-", ".", "abc", "inf", "nan"] {
            #expect(ParamNumberText.parse(partial, decimalSeparator: ".") == nil, "\(partial)")
        }
    }

    @Test func aCommaFollowsTheLocale() {
        #expect(ParamNumberText.parse("1,080", decimalSeparator: ".") == 1080)
        #expect(ParamNumberText.parse("0,5", decimalSeparator: ",") == 0.5)
        #expect(ParamNumberText.parse("1.5", decimalSeparator: ",") == 1.5)
    }

    // MARK: The drag's grid

    @Test func aDragLandsOnAPowerOfTenUnderAPointOfTravel() {
        #expect(ParamNumberText.dragQuantum(perPoint: 4.0 / 250) == 0.01)     // 0...4
        #expect(ParamNumberText.dragQuantum(perPoint: 365.0 / 250) == 1)      // 10...375
        #expect(ParamNumberText.dragQuantum(perPoint: 100_000.0 / 250) == 100)
        let tiny = try! #require(ParamNumberText.dragQuantum(perPoint: 0.01 / 250))
        #expect(abs(tiny - 0.00001) < 1e-18)
        #expect(ParamNumberText.dragQuantum(perPoint: 0) == nil)
    }

    @Test func aDraggedValueHasTheDigitsAPersonWouldType() {
        let slid = ParamNumberText.dragged(2.4027931415929205, perPoint: 4.0 / 250, in: 0...4)
        #expect(slid == 2.4)
        #expect(String(describing: slid) == "2.4")
        #expect(ParamNumberText.quantized(0.01 * 196, quantum: 0.01) == 1.96)
    }

    @Test func aDragReachesEitherEndWhateverTheGrid() {
        #expect(ParamNumberText.dragged(0.03, perPoint: 0.05, in: 0.05...12) == 0.05)
        #expect(ParamNumberText.dragged(12.4, perPoint: 0.05, in: 0.05...12) == 12)
        #expect(ParamNumberText.dragged(2.4, perPoint: 0.2, in: 2.37...2.43) == 2.4)
        // Rounding near an end never leaves the range.
        #expect(ParamNumberText.dragged(2.428, perPoint: 0.1, in: 2.37...2.43) <= 2.43)
    }

    // MARK: How far a box moves

    /// A whole number drags at a step per eight points on a small range, as it
    /// always did, and covers a large range in a track's length rather than in
    /// thousands of points.
    @Test func aWholeNumberDragsAtARateThatFollowsItsRange() {
        let small = ParamStepping(range: 0...10, step: 1)
        #expect(small.perPoint == 1.0 / 8)
        let large = ParamStepping(range: 0...10_000, step: 1)
        #expect(large.perPoint == 40)
        #expect(large.dragged(from: 0, points: 250, pace: .plain) == 10_000)
        #expect(large.dragged(from: 5_000, points: 10, pace: .plain) == 5_400)
        // Option is a tenth of the pace, and it still lands on whole steps.
        #expect(large.dragged(from: 5_000, points: 10, pace: .fine) == 5_040)
        #expect(small.dragged(from: 3, points: 41, pace: .plain) == 8)
        // A free number keeps the track-length rate it had.
        #expect(ParamStepping(range: 10...375).perPoint == 365.0 / 250)
    }

    /// Shift lands a drag on round marks, four to forty of them across the
    /// range, at the plain rate, so it steps through the range instead of
    /// running to an end in a few points.
    @Test func shiftStepsThroughTheRangeRatherThanRunningToAnEnd() {
        let free = ParamStepping(range: 0...1)
        #expect(free.coarse == 0.1)
        #expect(free.dragged(from: 0.437, points: 10, pace: .coarse) == 0.5)
        #expect(free.dragged(from: 0.437, points: 30, pace: .coarse) == 0.6)
        #expect(free.dragged(from: 0.437, points: -30, pace: .coarse) == 0.3)
        // Twenty-five points under Shift used to be the whole range.
        #expect(free.dragged(from: 0.5, points: 25, pace: .coarse) == 0.6)
        #expect(free.dragged(from: 0.5, points: 400, pace: .coarse) == 1)

        let wide = ParamStepping(range: 10...375)
        #expect(wide.coarse == 10)
        #expect(wide.dragged(from: 175, points: 20, pace: .coarse) == 200)
        #expect(wide.dragged(from: 370, points: 20, pace: .coarse) == 375)

        let whole = ParamStepping(range: 0...10_000, step: 1)
        #expect(whole.coarse == 1_000)
        #expect(whole.dragged(from: 4_321, points: 20, pace: .coarse) == 5_000)
        // A small whole range has no coarser round number than its step.
        #expect(ParamStepping(range: 0...10, step: 1).coarse == 1)
        // A step that is not a power of ten takes Shift in whole steps.
        let threes = ParamStepping(range: 0...300, step: 3)
        #expect(threes.coarse == 30)
        #expect(threes.dragged(from: 0, points: 300, pace: .coarse) == 300)
    }

    /// An arrow takes a box to the next mark on its grid: a tenth of Shift's
    /// mark on a free box, the declared step on a stepped one, Shift's mark
    /// under Shift, and a tenth again under Option where the box has no step
    /// to keep.
    @Test func anArrowStepsToTheNextMarkOnTheGrid() {
        let free = ParamStepping(range: 0...1)
        #expect(free.unit == 0.01)
        #expect(free.nudged(0.437, by: 1, pace: .plain) == 0.44)
        #expect(free.nudged(0.437, by: -1, pace: .plain) == 0.43)
        #expect(free.nudged(0.44, by: 1, pace: .plain) == 0.45)
        #expect(free.nudged(0.437, by: 1, pace: .coarse) == 0.5)
        #expect(free.nudged(0.5, by: -1, pace: .coarse) == 0.4)
        #expect(free.nudged(0.437, by: 1, pace: .fine) == 0.438)
        // Binary noise on a mark still counts as the mark.
        #expect(free.nudged(0.1 + 0.2, by: 1, pace: .plain) == 0.31)
        // An arrow at an end stays there, and one past a mark lands on the end.
        #expect(free.nudged(1, by: 1, pace: .plain) == 1)
        #expect(ParamStepping(range: 10...375).nudged(370, by: 1, pace: .coarse) == 375)
        #expect(ParamStepping(range: 10...375).nudged(375, by: -1, pace: .coarse) == 370)

        let count = ParamStepping(range: 50...500, step: 10)
        #expect(count.unit == 10)
        #expect(count.nudged(120, by: 1, pace: .plain) == 130)
        #expect(count.nudged(120, by: 1, pace: .fine) == 130)
        #expect(count.coarse == 100)
        // Zero sits on this grid, so Shift's marks are the round hundreds.
        #expect(count.nudged(120, by: 1, pace: .coarse) == 200)
        #expect(count.nudged(200, by: -1, pace: .coarse) == 100)
        // Where zero is off the step's grid, the marks count from the floor.
        #expect(ParamStepping(range: 5...455, step: 10).nudged(120, by: 1, pace: .coarse) == 205)
        #expect(count.nudged(495, by: -1, pace: .plain) == 490)

        let quarters = ParamStepping(range: 0...10, step: 0.25)
        #expect(quarters.nudged(2.5, by: 1, pace: .plain) == 2.75)
        #expect(quarters.nudged(2.6, by: -1, pace: .plain) == 2.5)

        // A range with no width has nowhere to go, and says so without a NaN.
        let none = ParamStepping(range: 4...4)
        #expect(none.nudged(4, by: 1, pace: .plain) == 4)
        #expect(none.dragged(from: 4, points: 50, pace: .coarse) == 4)
    }

    /// The save's sentence goes once a value is turned by hand or put back,
    /// since it describes the values before that.
    @Test func whatASaveSaidGoesWithTheNextEdit() {
        var note = ParamSaveNote()
        #expect(note.text == nil)
        note.saved("Saved 3 values into Sketch.swift.")
        #expect(note.text == "Saved 3 values into Sketch.swift.")
        note.changed()
        #expect(note.text == nil)
        note.saved(nil)
        #expect(note.text == nil)
    }

    // MARK: Typing

    /// Types `text` one key at a time over a box holding `start`, the way the
    /// field reports it, applying every preview the way the row does. Returns
    /// what the box showed after each key and the value after the commit.
    private func typed(_ text: String, over start: Double, in range: ClosedRange<Double>,
                       accepts: (Double) -> Bool = { _ in true })
        -> (shown: [String], previews: [Double?], committed: Double?) {
        var edit = ParamNumberEdit()
        var value = start
        var shown: [String] = []
        var previews: [Double?] = []
        var sofar = ""
        for key in text {
            sofar.append(key)
            let preview = edit.type(sofar, over: value, in: range, accepts: accepts)
            if let preview { value = preview }
            previews.append(preview)
            shown.append(edit.text(for: value))
        }
        return (shown, previews, edit.commit(in: range))
    }

    @Test func aFirstKeyBelowTheRangeIsNotClampedUnderTheTypist() {
        let radius = typed("25", over: 175, in: 10...375)
        #expect(radius.shown == ["2", "25"])
        #expect(radius.previews == [nil, 25])
        #expect(radius.committed == 25)
    }

    @Test func aWholeNumberTypedIsTheNumberCommitted() {
        #expect(typed("300", over: 120, in: 50...500).committed == 300)
        #expect(typed("250", over: 300, in: 100...500).committed == 250)
        #expect(typed("250", over: 175, in: 100...1000).shown == ["2", "25", "250"])
    }

    @Test func aValuePastTheRangeIsClampedOnlyWhenCommitted() {
        let anchor = typed("1200", over: 540, in: 0...1080)
        #expect(anchor.shown == ["1", "12", "120", "1200"])
        #expect(anchor.previews == [1, 12, 120, nil])
        #expect(anchor.committed == 1080)
    }

    @Test func aCommitKeepsEveryDigitTyped() {
        #expect(typed("0.007", over: 0.004, in: 0...0.01).committed == 0.007)
        #expect(typed("3.75", over: 2.5, in: 0.5...12).committed == 3.75)
        #expect(typed("3.75", over: 2.5, in: 0.5...12).shown == ["3", "3.", "3.7", "3.75"])
    }

    @Test func aBoxPassedThroughIsNeverRewritten() {
        var edit = ParamNumberEdit()
        #expect(edit.commit(in: 0...1) == nil)
        #expect(edit.cancel() == nil)
    }

    @Test func textThatIsNotANumberPutsTheStartingValueBack() {
        var edit = ParamNumberEdit()
        #expect(edit.type("2", over: 175, in: 10...375) == nil)
        #expect(edit.type("25", over: 175, in: 10...375) == 25)
        #expect(edit.type("", over: 25, in: 10...375) == nil)
        #expect(edit.commit(in: 10...375) == 175)
    }

    @Test func escapePutsTheStartingValueBack() {
        var edit = ParamNumberEdit()
        #expect(edit.type("25", over: 175, in: 10...375) == 25)
        #expect(edit.cancel() == 175)
        #expect(edit.text(for: 175) == "175")
    }

    @Test func escapeAfterACommitLeavesTheCommitAlone() {
        var edit = ParamNumberEdit()
        _ = edit.type("25", over: 175, in: 10...375)
        #expect(edit.commit(in: 10...375) == 25)
        #expect(edit.cancel() == nil)
        // The next typing starts from the committed value.
        _ = edit.type("3", over: 25, in: 10...375)
        #expect(edit.cancel() == 25)
    }

    // MARK: A min/max pair

    @Test func aTypedMaximumNeverMovesTheMinimumWhileTyped() {
        let band = typed("90", over: 80, in: 0...100, accepts: { $0 >= 20 })
        #expect(band.previews == [nil, 90])
        #expect(band.committed == 90)
    }

    @Test func anEndSetPastTheOtherPushesItAlong() {
        #expect(ParamRangeEnd.upper.ordered(lower: 20, upper: 9) == 9...9)
        #expect(ParamRangeEnd.lower.ordered(lower: 85, upper: 80) == 85...85)
        #expect(ParamRangeEnd.upper.ordered(lower: 20, upper: 90) == 20...90)
        #expect(ParamRangeEnd.lower.ordered(lower: 20, upper: 80) == 20...80)
    }
}

/// The same typing through a real value box: a sketch's parameters in the
/// detached inspector, keys inserted through the field editor as a keyboard
/// would. The model above is only worth something if the box obeys it, and the
/// defect it pins lived in the binding between the two.
@Suite
@MainActor
struct ParamNumberBoxTests {

    final class Boxes: Sketch {
        @Param(10...375) var radius = 175.0
        @Param(50...500, step: 10) var count = 120
        @Param(in: 0...100) var band = 20.0...80.0
    }

    private func textFields(under view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField { found.append(field) }
        for child in view.subviews { found += textFields(under: child) }
        return found
    }

    private func settle(_ seconds: Double = 0.2) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    /// The editor typing into `field`, with the box's text selected, as a
    /// click into the box leaves it.
    private func startTyping(in field: NSTextField, on panel: NSWindow) throws -> NSTextView {
        #expect(panel.makeFirstResponder(field))
        settle()
        let editor = try #require(panel.firstResponder as? NSTextView)
        editor.selectAll(nil)
        return editor
    }

    /// An arrow key as the keyboard sends it, through the panel's own event
    /// path, so whatever the box does with it is what a person would get.
    private func press(_ arrow: Arrow, _ modifiers: NSEvent.ModifierFlags = [], on panel: NSWindow) throws {
        let characters = arrow == .up ? "\u{F700}" : "\u{F701}"
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers.union([.numericPad, .function]),
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: arrow == .up ? 126 : 125))
        panel.sendEvent(event)
        settle(0.15)
    }

    enum Arrow { case up, down }

    private func type(_ text: String, into editor: NSTextView) {
        for key in text {
            editor.insertText(String(key), replacementRange: editor.selectedRange())
            settle(0.15)
        }
    }

    @Test func typingIntoABoxLeavesTheTextAloneAndCommitsTheNumber() throws {
        let sketch = Boxes()
        let stats = FrameStats()
        let controller = StatsPanelController()
        controller.sync(visible: true, sketch: sketch, stats: stats)
        settle(0.4)
        defer { controller.close() }
        let panel = try #require(controller.window)
        panel.makeKey()
        let content = try #require(panel.contentView)
        // The seed box comes first, then one box per number, in declaration order.
        let fields = textFields(under: content)
        try #require(fields.count >= 5)
        let radiusBox = fields[1], countBox = fields[2], minBox = fields[3], maxBox = fields[4]
        #expect(radiusBox.stringValue == "175")

        // The audit's first case: "2" is below the range, and stays "2".
        var editor = try startTyping(in: radiusBox, on: panel)
        type("2", into: editor)
        #expect(editor.string == "2", "the box rewrote the first key to \"\(editor.string)\"")
        #expect(sketch.radius == 175, "a number under the range reached the sketch")
        type("5", into: editor)
        #expect(editor.string == "25")
        #expect(sketch.radius == 25, "a number inside the range shows at once")
        editor.insertNewline(nil)
        settle()
        #expect(sketch.radius == 25)

        // "300" over 50...500 is 300, never 500.
        editor = try startTyping(in: countBox, on: panel)
        type("300", into: editor)
        #expect(editor.string == "300")
        panel.makeFirstResponder(nil)
        settle()
        #expect(sketch.count == 300)
        #expect(countBox.stringValue == "300")

        // A maximum typed through a value under the minimum leaves the minimum be.
        editor = try startTyping(in: maxBox, on: panel)
        type("90", into: editor)
        #expect(minBox.stringValue == "20", "the minimum moved to \(minBox.stringValue)")
        panel.makeFirstResponder(nil)
        settle()
        #expect(sketch.band == 20...90)
    }

    /// The arrows step a box being typed in: to the next mark on its grid,
    /// Shift's round marks under Shift, from a number half typed, and never
    /// past an end.
    @Test func theArrowsStepABoxToItsNextMark() throws {
        let sketch = Boxes()
        let stats = FrameStats()
        let controller = StatsPanelController()
        controller.sync(visible: true, sketch: sketch, stats: stats)
        settle(0.4)
        defer { controller.close() }
        let panel = try #require(controller.window)
        panel.makeKey()
        let content = try #require(panel.contentView)
        let fields = textFields(under: content)
        try #require(fields.count >= 5)
        let radiusBox = fields[1], countBox = fields[2]

        // 10...375 has Shift's marks every 10, and an arrow every 1.
        var editor = try startTyping(in: radiusBox, on: panel)
        try press(.up, on: panel)
        #expect(sketch.radius == 176)
        try press(.up, .shift, on: panel)
        #expect(sketch.radius == 180)
        try press(.down, .shift, on: panel)
        #expect(sketch.radius == 170)
        #expect(radiusBox.stringValue == "170" || editor.string == "170")

        // A number half typed is where the arrow starts.
        editor.selectAll(nil)
        type("12", into: editor)
        try press(.up, on: panel)
        #expect(sketch.radius == 13)
        try press(.down, .shift, on: panel)
        try press(.down, .shift, on: panel)
        #expect(sketch.radius == 10, "an arrow went past the range's floor")

        // A stepped whole number takes its step, and Shift the round hundreds.
        editor = try startTyping(in: countBox, on: panel)
        try press(.up, on: panel)
        #expect(sketch.count == 130)
        try press(.up, .shift, on: panel)
        #expect(sketch.count == 200)
        panel.makeFirstResponder(nil)
        settle()
        #expect(countBox.stringValue == "200")
    }
}
