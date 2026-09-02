import Ollin
@testable import OllinRuntime
import Testing

/// Writing tuned knob values back into the `@Param` lines they came from.
///
/// Every check works on text alone, the way the hosts call it: hand it a
/// sketch's source and the values the inspector holds, and read the source
/// back. No GPU, no compile. The end-to-end proof that the file it writes
/// still builds and carries the values is `OllinLive --savetest`.
@Suite
struct ParamWriteTests {

    private func written(_ source: String,
                         _ values: (name: String, stored: ParamStored)...) -> ParamWrite.Result {
        ParamWrite.writing(source, values: values)
    }

    // MARK: The everyday case

    @Test func aNumberTakesTheTunedValue() {
        let result = written("@Param(0...200) var radius = 120.0", ("radius", .number(86.5)))
        #expect(result.text == "@Param(0...200) var radius = 86.5")
        #expect(result.written == ["radius"])
        #expect(result.refused.isEmpty)
    }

    /// A dragged slider lands on a value with sixteen digits, and the line
    /// should still read as one a person typed: four significant figures,
    /// which no display resolves past, and never fewer than the value needs.
    @Test func aDraggedValueIsWrittenRounded() {
        let result = written("@Param(0...4) var speed = 1.0", ("speed", .number(2.4027931415929205)))
        #expect(result.text == "@Param(0...4) var speed = 2.403")
        let stop = written("@Param(0...1) var at = 0.5", ("at", .number(0.1757983826754386)))
        #expect(stop.text == "@Param(0...1) var at = 0.1758")
        let small = written("@Param(0...0.01) var eps = 0.005", ("eps", .number(0.00034567891)))
        #expect(small.text == "@Param(0...0.01) var eps = 0.0003457")
        let exact = written("@Param(0...4) var speed = 1.0", ("speed", .number(0.25)))
        #expect(exact.text == "@Param(0...4) var speed = 0.25")
    }

    /// The declaration's own text is not the value's: the range, the label, the
    /// group, and anything after the value stay exactly as they were.
    @Test func everythingAroundTheValueSurvives() {
        let source = """
        final class Sketch1: Sketch {
            /// How wide the ring is drawn.
            @Param("Ring", 0...200, step: 5, icon: "circle", group: "Shape")
            private var radius = 120.0   // tuned by eye

            @Param(0...10) var speed = 1.0
        }
        """
        let result = written(source, ("radius", .number(65)))
        #expect(result.text.contains(#"@Param("Ring", 0...200, step: 5, icon: "circle", group: "Shape")"#))
        #expect(result.text.contains("private var radius = 65.0   // tuned by eye"))
        #expect(result.text.contains("/// How wide the ring is drawn."))
        #expect(result.text.contains("@Param(0...10) var speed = 1.0"))   // untouched
    }

    /// A knob nobody turned is not in the set, so its line is not even read.
    @Test func onlyTheNamedKnobsMove() {
        let source = "@Param(0...5) var a = 1.0\n@Param(0...5) var b = 2.0"
        let result = written(source, ("b", .number(4)))
        #expect(result.text == "@Param(0...5) var a = 1.0\n@Param(0...5) var b = 4.0")
    }

    // MARK: The two rules that keep the file compiling

    /// A `Double` knob is a `Double` only because of the range beside it, so a
    /// fraction must keep its point. Without this the line reads as an `Int`
    /// and the declaration stops compiling.
    @Test func aFractionKeepsItsPoint() {
        let result = written("@Param(0...200) var radius = 120", ("radius", .number(86.5)))
        #expect(result.text.hasSuffix("= 86.5"))
    }

    /// A whole value written into a whole default stays whole, so a knob turned
    /// to a round number reads the way its author wrote it.
    @Test func aWholeValueStaysWhole() {
        let result = written("@Param(1...12) var rings = 5", ("rings", .number(8)))
        #expect(result.text.hasSuffix("= 8"))
    }

    @Test func aWholeValueUnderAFractionKeepsThePoint() {
        let result = written("@Param(0...200) var radius = 120.0", ("radius", .number(80)))
        #expect(result.text.hasSuffix("= 80.0"))
    }

    /// Both ends of a range carry a point for the same reason: `40...50` reads
    /// as a range of `Int`, which no `ClosedRange<Double>` knob can take.
    @Test func bothEndsOfARangeKeepTheirPoint() {
        let result = written("@Param(in: 0...50) var sizes = 5.0...20.0",
                             ("sizes", .range(lower: 40, upper: 50)))
        #expect(result.text.hasSuffix("= 40.0...50.0"))
    }

    // MARK: Every kind of value

    @Test func aToggleWritesItsWord() {
        #expect(written("@Param var filled = true", ("filled", .boolean(false)))
                    .text.hasSuffix("= false"))
    }

    /// A case keeps the spelling its author chose, because both compile and
    /// only one of them is what the file already reads like.
    @Test func aMenuKeepsTheSpellingItWasWrittenWith() {
        #expect(written("@Param var style: Style = .dots", ("style", .option("rings")))
                    .text.hasSuffix("= .rings"))
        #expect(written("@Param var style = Style.dots", ("style", .option("rings")))
                    .text.hasSuffix("= Style.rings"))
    }

    /// A curve built from a closure carries a serial rather than a member name,
    /// so there is nothing to write and the knob says so.
    @Test func aChoiceWithNoNameIsRefused() {
        let result = written("@Param var curve: Easing = .easeOut", ("curve", .option("curve 3")))
        #expect(result.written.isEmpty)
        #expect(result.refused == [.init(name: "curve", reason: .unnamed("curve 3"))])
    }

    @Test func aColorWritesItsComponents() {
        let result = written("@Param var tint: Color = .purple",
                             ("tint", .color(red: 0.25, green: 0.5, blue: 1, alpha: 1)))
        #expect(result.text.hasSuffix("= Color(red: 0.25, green: 0.5, blue: 1)"))
    }

    @Test func aTransparentColorCarriesItsAlpha() {
        let result = written("@Param var tint: Color = .purple",
                             ("tint", .color(red: 0, green: 0, blue: 0, alpha: 0.4)))
        #expect(result.text.hasSuffix("= Color(red: 0, green: 0, blue: 0, alpha: 0.4)"))
    }

    /// A color well hands over more digits than a display can show, and four
    /// decimals is finer than one channel step (1/255).
    @Test func aColorIsWrittenToFourDecimals() {
        let result = written("@Param var tint: Color = .purple",
                             ("tint", .color(red: 0.5019607843137255, green: 0, blue: 0, alpha: 1)))
        #expect(result.text.hasSuffix("= Color(red: 0.502, green: 0, blue: 0)"))
    }

    @Test func theGeometryKindsWriteTheirFields() {
        #expect(written("@Param(x: 0...1080, y: 0...1080) var center = Vector2(540, 540)",
                        ("center", .vector(x: 300, y: 220.5)))
                    .text.hasSuffix("= Vector2(300, 220.5)"))
        #expect(written("@Param(x: -1...1, y: -1...1, z: 0...10) var eye = Vector3(0, 0, 5)",
                        ("eye", .vector3(x: 1, y: -0.5, z: 3)))
                    .text.hasSuffix("= Vector3(1, -0.5, 3)"))
        #expect(written("@Param(x: 0...9, y: 0...9, width: 1...9, height: 1...9) var r = Rectangle(x: 1, y: 1, width: 2, height: 2)",
                        ("r", .rectangle(x: 3, y: 4, width: 5, height: 6)))
                    .text.hasSuffix("= Rectangle(x: 3, y: 4, width: 5, height: 6)"))
        #expect(written("@Param(0...100) var margins = Insets.all(20)",
                        ("margins", .insets(top: 1, right: 2, bottom: 3, left: 4)))
                    .text.hasSuffix("= Insets(top: 1, right: 2, bottom: 3, left: 4)"))
    }

    @Test func textIsWrittenAsALiteralWithItsQuotesEscaped() {
        let result = written(#"@Param var caption = "hello""#, ("caption", .text(#"say "hi"\"#)))
        #expect(result.text.hasSuffix(#"= "say \"hi\"\\""#))
    }

    /// A palette holds colors alone; a ramp holds where each one sits and the
    /// space it blends through, so it writes the longer form.
    @Test func aStripWritesItsColors() {
        let palette = written("@Param(count: 1...6) var inks = Palette(.red, .white)",
                              ("inks", .colors(stops: [.init(position: 0, color: .black),
                                                       .init(position: 1, color: .white)],
                                               space: nil)))
        #expect(palette.text.hasSuffix("= Palette([Color(red: 0, green: 0, blue: 0), "
                                       + "Color(red: 1, green: 1, blue: 1)])"))

        let ramp = written("@Param var fade = Ramp([.black, .white])",
                           ("fade", .colors(stops: [.init(position: 0, color: .black),
                                                    .init(position: 0.5, color: .white)],
                                            space: "oklch")))
        #expect(ramp.text.hasSuffix("= Ramp(stops: [(position: 0, color: Color(red: 0, green: 0, blue: 0)), "
                                    + "(position: 0.5, color: Color(red: 1, green: 1, blue: 1))], in: .oklch)"))
    }

    // MARK: What it refuses, and says

    /// The destination is a value written down. A default the sketch works out
    /// has nothing to replace, and the refusal names what stands there.
    @Test func aComputedDefaultIsRefusedByName() {
        let result = written("@Param(0...900) var radius = side / 3", ("radius", .number(80)))
        #expect(result.written.isEmpty)
        #expect(result.refused == [.init(name: "radius", reason: .computed("side / 3"))])
        #expect(result.text == "@Param(0...900) var radius = side / 3")
        #expect(ParamWrite.sentence(for: result.refused[0], in: "Sketch.swift")
                    .contains("side / 3"))
    }

    /// A sum standing on its own is arithmetic the author meant, even when
    /// every part of it is a number, so it is left alone too.
    @Test func aDefaultWorkedOutFromNumbersIsRefused() {
        let result = written("@Param(0...600) var half = 600.0 / 2", ("half", .number(80)))
        #expect(result.refused == [.init(name: "half", reason: .computed("600.0 / 2"))])
    }

    /// A negative number is a value, not arithmetic, and an operator inside a
    /// call belongs to that call's own argument.
    @Test func aNegativeValueIsStillWrittenDown() {
        #expect(written("@Param(-9...9) var drift = -1.5", ("drift", .number(2))).written == ["drift"])
        #expect(written("@Param(0...100) var margins = Insets.all(20 / 2)",
                        ("margins", .insets(top: 1, right: 1, bottom: 1, left: 1)))
                    .written == ["margins"])
    }

    @Test func aDefaultNamingAnotherPropertyIsRefused() {
        let result = written("@Param(0...9) var radius = defaultRadius", ("radius", .number(4)))
        #expect(result.refused == [.init(name: "radius", reason: .computed("defaultRadius"))])
    }

    /// A type reaching for one of its own values is written down, even though
    /// it carries names: `Insets.all(20)` and `.purple` are values, `side` is not.
    @Test func aTypeReachingForItsOwnValueIsWrittenDown() {
        #expect(written("@Param(0...100) var margins = Insets.all(20)",
                        ("margins", .insets(top: 0, right: 0, bottom: 0, left: 0)))
                    .refused.isEmpty)
        #expect(written("@Param var tint: Color = Color(red: 1, green: 0, blue: 0)",
                        ("tint", .color(red: 0, green: 1, blue: 0, alpha: 1)))
                    .refused.isEmpty)
        #expect(written("@Param var tint: Color = Color(red: r, green: 0, blue: 0)",
                        ("tint", .color(red: 0, green: 1, blue: 0, alpha: 1)))
                    .refused.count == 1)
    }

    @Test func aKnobDeclaredSomewhereElseIsSaidOutLoud() {
        let result = written("@Param(0...5) var here = 1.0", ("elsewhere", .number(2)))
        #expect(result.refused == [.init(name: "elsewhere", reason: .notDeclared)])
        #expect(ParamWrite.sentence(for: result.refused[0], in: "Sketch.swift")
                == "Sketch.swift does not declare elsewhere.")
    }

    /// Two sketches in one file may carry the same knob name, and there is no
    /// way to tell which one is running, so neither is written.
    @Test func twoKnobsOfOneNameAreRefused() {
        let source = "@Param(0...5) var radius = 1.0\n@Param(0...5) var radius = 2.0"
        let result = written(source, ("radius", .number(3)))
        #expect(result.refused == [.init(name: "radius", reason: .ambiguous)])
        #expect(result.text == source)
    }

    /// A property that only looks like a knob is not one, and a `var` inside a
    /// string or a comment is not a declaration at all.
    @Test func onlyRealParamsAreFound() {
        #expect(written("var radius = 1.0", ("radius", .number(2))).refused
                    == [.init(name: "radius", reason: .notDeclared)])
        #expect(written("// @Param var radius = 1.0", ("radius", .number(2))).refused
                    == [.init(name: "radius", reason: .notDeclared)])
        #expect(written(#"let code = "@Param var radius = 1.0""#, ("radius", .number(2))).refused
                    == [.init(name: "radius", reason: .notDeclared)])
    }

    /// A set that is half writable still lands, and the sentence names the one
    /// that did not.
    @Test func aHalfWritableSetStillLands() {
        let source = "@Param(0...9) var a = 1.0\n@Param(0...9) var b = side / 2"
        let result = written(source, ("a", .number(3)), ("b", .number(4)))
        #expect(result.written == ["a"])
        #expect(result.text.contains("var a = 3.0"))
        #expect(result.text.contains("var b = side / 2"))
        let summary = ParamWrite.summary(of: result, in: "Sketch.swift")
        #expect(summary.contains("Saved 1 value into Sketch.swift."))
        #expect(summary.contains("side / 2"))
    }

    // MARK: Shapes a declaration can take

    /// The attribute, its own parentheses, the modifiers, and the value may sit
    /// on lines of their own.
    @Test func aDeclarationSpreadOverLinesIsFound() {
        let source = """
        @Param(x: 0...1080,
               y: 0...1080,
               style: .pad)
        public var center = Vector2(540, 540)
        """
        let result = written(source, ("center", .vector(x: 10, y: 20)))
        #expect(result.text.hasSuffix("public var center = Vector2(10, 20)"))
    }

    /// A value that opens a bracket carries the line breaks inside it, so the
    /// whole thing is replaced rather than its first line.
    @Test func aValueThatSpansLinesIsReplacedWhole() {
        let source = """
        @Param(count: 1...6) var inks = Palette([
            .red,
            .blue,
        ])
        let after = 1
        """
        let result = written(source, ("inks", .colors(stops: [.init(position: 0, color: .black)],
                                                      space: nil)))
        #expect(result.text == """
        @Param(count: 1...6) var inks = Palette([Color(red: 0, green: 0, blue: 0)])
        let after = 1
        """)
    }

    /// A trailing comment is not part of the value, so it stays where the
    /// author put it.
    @Test func aTrailingCommentIsLeftAlone() {
        let result = written("@Param(0...9) var a = 1.0  // why this number",
                             ("a", .number(2)))
        #expect(result.text == "@Param(0...9) var a = 2.0  // why this number")
    }

    /// A `@Param` that carries no value cannot be written into, and a computed
    /// property is not a knob at all.
    @Test func aDeclarationWithNoValueIsRefused() {
        #expect(written("@Param(0...9) var a: Double { 5 }", ("a", .number(2))).refused
                    == [.init(name: "a", reason: .noDefault)])
    }

    // MARK: The summary a host shows

    @Test func theSummaryCountsWhatLanded() {
        let none = ParamWrite.Result(text: "", written: [], refused: [])
        #expect(ParamWrite.summary(of: none, in: "Sketch.swift") == "Nothing was written into Sketch.swift.")
        let two = ParamWrite.Result(text: "", written: ["a", "b"], refused: [])
        #expect(ParamWrite.summary(of: two, in: "Sketch.swift") == "Saved 2 values into Sketch.swift.")
    }
}
