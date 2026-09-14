import Foundation
@testable import Ollin
import Testing

/// What `--list-params` says a sketch declares. The listing's one promise is
/// that a line can be pasted back, so the law that matters is the round trip:
/// every value it prints, read through `--param`, restores the value it printed.
@Suite
@MainActor
struct ParamListingTests {

    enum Style: String, CaseIterable, ParamOption { case dots, rings, meshLines }

    /// One parameter of every kind the inspector has a control for, plus a
    /// grouped one and a hidden one, since both change what the listing says.
    final class Listed: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        @Param(0...200) var radius = 120.0
        @Param(1...12) var rings = 5
        @Param var filled = true
        @Param var tint = Color(red: 0.7, green: 0.2, blue: 0.95)
        @Param(x: 0...1080, y: 0...1080) var anchor = Vector2(540, 540)
        @Param(x: -10...10, y: -10...10, z: -10...10) var pull = Vector3(0, 1.5, 0)
        @Param(x: 0...1080, y: 0...1080, width: 0...1080, height: 0...1080)
        var plate = Rectangle(x: 0, y: 0, width: 100, height: 100)
        @Param(0...200) var margin = Insets(top: 12, right: 12, bottom: 12, left: 12)
        @Param(in: 0...1) var band = 0.2...0.8
        @Param var caption = "hello"
        @Param var style: Style = .dots
        @Param var inks = Palette([.red, .blue])
        @Param var fade = Ramp([.black, .white], in: .oklab)
        @Param(0...1, group: "Paper") var grain = 0.35
        @Param(0...1) var wobble = 0.007

        override func setup() {
            $wobble.show(when: $filled) { !$0 }
        }

        override func draw() { background(.white) }
    }

    /// Every value the listing prints, read back through the flag that sets it,
    /// lands on the value it was printed from. Exactly, for every kind but a
    /// color: a color is said in hex, which is how the flag spells one and how a
    /// person reads one, so it comes back to the nearest eight-bit step.
    @Test func everyPrintedValueReadsBackAsItself() {
        let sketch = Listed()
        sketch.runSetup()
        for handle in sketch.parameters() {
            let before = handle.param.stored
            let text = ParamListing.value(of: before)
            let problems = ParamOverride.apply([ParamOverride(name: handle.name, text: text)], to: sketch)
            #expect(problems.isEmpty, "\(handle.name)=\(text): \(problems.joined(separator: "; "))")
            #expect(same(handle.param.stored, before),
                    "\(handle.name)=\(text) came back as \(handle.param.stored), was \(before)")
        }
    }

    /// Equal, allowing a color one eight-bit step per channel and nothing else
    /// any slack at all.
    private func same(_ lhs: ParamStored, _ rhs: ParamStored) -> Bool {
        func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1.0 / 255 }
        switch (lhs, rhs) {
        case (.color(let r1, let g1, let b1, let a1), .color(let r2, let g2, let b2, let a2)):
            return close(r1, r2) && close(g1, g2) && close(b1, b2) && close(a1, a2)
        case (.colors(let one, let space1), .colors(let two, let space2)):
            return space1 == space2 && one.count == two.count
                && zip(one, two).allSatisfy {
                    $0.position == $1.position && close($0.red, $1.red)
                        && close($0.green, $1.green) && close($0.blue, $1.blue)
                        && close($0.alpha, $1.alpha)
                }
        default:
            return lhs == rhs
        }
    }

    /// A fraction keeps every digit that carries and no more, and a whole number
    /// keeps no point, so a listed number reads the way a person would write it.
    @Test func numbersAreAsShortAsTheyCanBeWithoutChanging() {
        #expect(ParamListing.number(120) == "120")
        #expect(ParamListing.number(-4) == "-4")
        #expect(ParamListing.number(0.35) == "0.35")
        #expect(ParamListing.number(0.007) == "0.007")
        #expect(Double(ParamListing.number(1.0 / 3)) == 1.0 / 3)
    }

    /// The columns: the name, the kind as a sketch spells it, what it accepts,
    /// and the value. A menu says its choices; a color and a string accept
    /// anything of their kind and say nothing.
    @Test func theListingNamesEveryKindAndWhatItTakes() {
        let sketch = Listed()
        sketch.runSetup()
        let text = ParamListing.text(for: sketch)
        #expect(text.hasPrefix("15 parameters, as --param takes them"))
        #expect(text.contains("radius"))
        #expect(text.contains("Double"))
        #expect(text.contains("0...200"))
        #expect(text.contains("Int"))
        #expect(text.contains("1...12"))
        #expect(text.contains("Bool"))
        #expect(text.contains("#B333F2"))                    // the tint, as --param takes it
        #expect(text.contains("540,540"))                    // the anchor
        #expect(text.contains("0.2...0.8"))                  // the band
        #expect(text.contains("Dots, Rings, Mesh Lines"))    // the menu's own choices
        #expect(text.contains("ClosedRange"))
        #expect(text.contains("2 to "))                      // the swatch strip's count
    }

    /// A group is a block under its own name, the way the inspector stacks its
    /// cards, and a parameter a show-rule is hiding says so rather than looking
    /// like a value nobody is reading.
    @Test func groupsAreBlocksAndAHiddenRowSaysSo() {
        let sketch = Listed()
        sketch.runSetup()
        let lines = ParamListing.text(for: sketch).split(separator: "\n", omittingEmptySubsequences: false)
        let paper = lines.firstIndex { $0 == "  Paper" }
        #expect(paper != nil)
        if let paper { #expect(lines[paper + 1].contains("grain")) }
        #expect(lines.contains { $0.contains("wobble") && $0.contains("(hidden right now)") })
    }

    /// A sketch with nothing to tune says so rather than printing an empty table.
    @Test func aSketchWithNoParametersSaysSo() {
        final class Bare: Sketch {
            override var canvasSize: CanvasSize { .square(32) }
            override func draw() { background(.white) }
        }
        #expect(ParamListing.text(for: Bare()) == "no parameters")
    }
}
