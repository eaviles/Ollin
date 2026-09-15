@testable import OllinRuntime
import Foundation
import Testing

/// Reading a sketch's declarations, finding the one the caret stands in, and
/// deciding whether the swap an edit causes can carry the run underneath it.
/// Text alone, so it costs nothing and says exactly what it means.
@Suite
struct SourceRegionsTests {

    /// A sketch in the shape the live host sees: a comment above the class, an
    /// attribute on its own line, a stored property, a `@Saved` one, and three
    /// methods.
    private let sketch = """
    import Ollin

    /// Two written instructions.
    @main
    final class Live: Sketch {
        @Param(0...4)
        var speed = 1.0
        @Saved var walked = 0.0
        private var marks: [Vector2] = []

        override func setup() {
            noClear()
            background(.black)
        }

        override func draw() {
            walked += speed
            fill(.white)
            drawCircle(walked, height / 2, 8)
        }

        private func ink() -> Color { .white }
    }
    """

    private func names(of text: String) -> [String] {
        SourceRegions.regions(in: text).map { $0.path.joined(separator: ".") + "/" + $0.name }
    }

    // MARK: Reading

    @Test func everyDeclarationIsFoundWhereItStands() {
        #expect(names(of: sketch) == [
            "/Ollin", "/Live", "Live/speed", "Live/walked", "Live/marks",
            "Live/setup()", "Live/draw()", "Live/ink()",
        ])
        let regions = SourceRegions.regions(in: sketch)
        let kinds = Dictionary(uniqueKeysWithValues: regions.map { ($0.name, $0.kind) })
        #expect(kinds["Live"] == .type)
        #expect(kinds["speed"] == .stored)
        #expect(kinds["marks"] == .stored)
        #expect(kinds["draw()"] == .method)
        #expect(kinds["ink()"] == .computed || kinds["ink()"] == .method)
    }

    /// The attribute on its own line joins the property under it rather than
    /// standing alone, and the comment above the class joins the class.
    @Test func anAttributeLineAndACommentJoinWhatTheyDecorate() throws {
        let regions = SourceRegions.regions(in: sketch)
        let speed = try #require(regions.first { $0.name == "speed" })
        #expect(speed.header == "@Param(0...4) var speed = 1.0")
        let live = try #require(regions.first { $0.name == "Live" })
        #expect(live.header == "@main final class Live: Sketch")
        let text = sketch as NSString
        #expect(text.substring(with: live.range).hasPrefix("/// Two written"))
    }

    @Test func theBlockUnderTheCaretIsTheInnermostOne() throws {
        let text = sketch as NSString
        let insideDraw = text.range(of: "fill(.white)").location + 3
        #expect(SourceRegions.region(in: sketch, containingOffset: insideDraw)?.name == "draw()")

        let insideSetup = text.range(of: "noClear()").location
        #expect(SourceRegions.region(in: sketch, containingOffset: insideSetup)?.name == "setup()")

        let onTheClassLine = text.range(of: "final class Live").location + 2
        #expect(SourceRegions.region(in: sketch, containingOffset: onTheClassLine)?.name == "Live")

        let onTheImport = text.range(of: "import Ollin").location + 2
        #expect(SourceRegions.region(in: sketch, containingOffset: onTheImport)?.name == "Ollin")

        // Between the import and the class there is no declaration to name, so
        // the editor has nothing narrower than the buffer to flash.
        let betweenDeclarations = text.range(of: "import Ollin").location + 13
        #expect(SourceRegions.region(in: sketch, containingOffset: betweenDeclarations) == nil)
    }

    @Test func linesAreOneBasedAndCoverTheWholeDeclaration() throws {
        let draw = try #require(SourceRegions.regions(in: sketch).first { $0.name == "draw()" })
        let lines = sketch.components(separatedBy: "\n")
        #expect(lines[draw.firstLine - 1].contains("override func draw()"))
        #expect(lines[draw.lastLine - 1].trimmingCharacters(in: .whitespaces) == "}")
    }

    // MARK: What an edit did

    @Test func aBodyEditKeepsTheRun() {
        let edited = sketch.replacingOccurrences(of: "drawCircle(walked, height / 2, 8)",
                                                 with: "drawCircle(walked, height / 2, 24)")
        let change = SourceRegions.change(from: sketch, to: edited)
        #expect(change == .bodies(["draw()"]))
        #expect(change.keepsTheRun)
        #expect(change.shortDescription == "draw()")
    }

    @Test func theSameTextAgainKeepsTheRun() {
        #expect(SourceRegions.change(from: sketch, to: sketch) == .nothing)
        #expect(SourceRegions.change(from: sketch, to: sketch).keepsTheRun)
    }

    @Test func aStoredPropertyEditRestarts() {
        let edited = sketch.replacingOccurrences(of: "@Saved var walked = 0.0",
                                                 with: "@Saved var walked = 200.0")
        let change = SourceRegions.change(from: sketch, to: edited)
        #expect(!change.keepsTheRun)
        #expect(change == .restarts("the declaration of `walked` changed"))
    }

    @Test func addingADeclarationRestarts() {
        let edited = sketch.replacingOccurrences(
            of: "    override func draw() {",
            with: "    private var extra = 3\n\n    override func draw() {")
        #expect(SourceRegions.change(from: sketch, to: edited)
                == .restarts("a declaration was added or removed"))
    }

    @Test func aChangedSignatureRestarts() {
        let edited = sketch.replacingOccurrences(of: "private func ink() -> Color",
                                                 with: "private func ink(_ t: Double) -> Color")
        #expect(!SourceRegions.change(from: sketch, to: edited).keepsTheRun)
    }

    /// Editing `setup()` is asking for `setup()` to run, which a swap that
    /// skips it could never show.
    @Test func editingSetupRestarts() {
        let edited = sketch.replacingOccurrences(of: "background(.black)",
                                                 with: "background(.white)")
        #expect(SourceRegions.change(from: sketch, to: edited)
                == .restarts("`setup()` is code `setup()` runs"))
    }

    /// And so is editing anything `setup()` runs, however far down.
    @Test func editingWhatSetupCallsRestarts() {
        let source = """
        import Ollin
        final class Live: Sketch {
            override func setup() { paint() }
            func paint() { background(.black) }
            override func draw() { drawCircle(0, 0, 4) }
        }
        """
        let edited = source.replacingOccurrences(of: "background(.black)",
                                                 with: "background(.white)")
        #expect(SourceRegions.change(from: source, to: edited)
                == .restarts("`paint()` is code `setup()` runs"))
    }

    /// The dangerous case, and the reason the rule exists: a sketch whose state
    /// is built in `setup()` would come back with none of it if the swap
    /// skipped `setup()`, so it restarts however small the edit was.
    @Test func setupBuildingStateThatCannotBeCarriedRestarts() {
        let source = """
        import Ollin
        final class Live: Sketch {
            private var field: [Double] = []
            override func setup() {
                field = (0..<100).map { Double($0) }
            }
            override func draw() {
                drawCircle(field[0], height / 2, 8)
            }
        }
        """
        let edited = source.replacingOccurrences(of: "8)", with: "24)")
        #expect(SourceRegions.change(from: source, to: edited)
                == .restarts("`setup()` builds `field`, which a swap cannot carry across"))
    }

    /// State built through a helper is caught the same way: the walk takes a
    /// fixed point rather than reading `setup()` alone.
    @Test func stateBuiltThroughAHelperIsCaughtToo() {
        let source = """
        import Ollin
        final class Live: Sketch {
            private var field: [Double] = []
            override func setup() { build() }
            private func build() { field = [1, 2, 3] }
            override func draw() { drawCircle(field[0], 0, 8) }
        }
        """
        let edited = source.replacingOccurrences(of: "0, 8)", with: "0, 24)")
        #expect(SourceRegions.change(from: source, to: edited)
                == .restarts("`setup()` builds `field`, which a swap cannot carry across"))
    }

    /// The same sketch with the state marked `@Saved` carries on, because that
    /// is the set a swap brings across.
    @Test func savedStateBuiltInSetupKeepsTheRun() {
        let source = """
        import Ollin
        final class Live: Sketch {
            @Saved var field: [Double] = []
            override func setup() {
                if field.isEmpty { field = [1, 2, 3] }
            }
            override func draw() { drawCircle(field[0], 0, 8) }
        }
        """
        let edited = source.replacingOccurrences(of: "0, 8)", with: "0, 24)")
        #expect(SourceRegions.change(from: source, to: edited) == .bodies(["draw()"]))
    }

    /// A note rewritten above a method is not a declaration change, and neither
    /// is a signature rewrapped over two lines.
    @Test func commentsAndWrappingAreNotDeclarationChanges() {
        let source = """
        import Ollin
        final class Live: Sketch {
            /// Draws it.
            override func draw() { drawCircle(0, 0, 8) }
        }
        """
        let reworded = source.replacingOccurrences(of: "/// Draws it.", with: "/// Draws the dot.")
        #expect(SourceRegions.change(from: source, to: reworded) == .nothing)

        let wrapped = source.replacingOccurrences(of: "override func draw() {",
                                                  with: "override\n    func draw() {")
        #expect(SourceRegions.change(from: source, to: wrapped) == .nothing)
    }

    /// A brace inside a string or a comment must not be read as a block, or
    /// every declaration after it lands in the wrong place.
    @Test func bracesInsideTextAreNotBlocks() {
        let source = """
        import Ollin
        final class Live: Sketch {
            let label = "a { brace"
            // and a } here
            let raw = #"a \\( escape ) and a " quote"#
            override func draw() { drawCircle(0, 0, 8) }
        }
        """
        #expect(names(of: source) == [
            "/Ollin", "/Live", "Live/label", "Live/raw", "Live/draw()",
        ])
    }

    /// Two types with a method of the same name are two declarations, so an
    /// edit in one is never read as an edit in the other.
    @Test func aNameIsQualifiedByWhatItStandsIn() throws {
        let source = """
        import Ollin
        struct Helper {
            func step() -> Double { 1 }
        }
        final class Live: Sketch {
            func step() -> Double { 2 }
            override func draw() { drawCircle(step(), 0, 8) }
        }
        """
        let regions = SourceRegions.regions(in: source)
        let steps = regions.filter { $0.name == "step()" }
        #expect(steps.count == 2)
        #expect(Set(steps.map(\.qualifiedName)) == ["Helper.step()", "Live.step()"])

        let edited = source.replacingOccurrences(of: "{ 1 }", with: "{ 3 }")
        #expect(SourceRegions.change(from: source, to: edited) == .bodies(["step()"]))
    }
}
