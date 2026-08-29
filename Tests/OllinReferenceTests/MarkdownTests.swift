import Foundation
import Testing
@testable import OllinReference

/// The renderer, on made-up input where every rule can be seen on one line.
/// Pure: no disk, no toolchain, no GPU.
@Suite("Markdown for a terminal")
struct MarkdownTests {

    static let wide = TerminalStyle(color: false, width: 120)

    // MARK: - Inline

    @Test("Markers come off, and the words stay")
    func inlineMarkers() {
        #expect(Markdown.plain("**bold** and *slanted* and `code`") == "bold and slanted and code")
        #expect(Markdown.plain("a [link](./Where.md) in a line") == "a link in a line")
        #expect(Markdown.plain("![a red square](./Figures/Red.png)") == "[figure: a red square]")
    }

    @Test("Plain output keeps the backticks that mark an identifier")
    func identifiersStayQuoted() {
        let plain = Markdown.render("Call `drawCircle` first.", style: Self.wide)
        #expect(plain == "Call `drawCircle` first.")

        // With color the escape codes carry the same information, so the
        // quoting would be a second marker for one thing.
        let colored = Markdown.render("Call `drawCircle` first.",
                                      style: TerminalStyle(color: true, width: 120))
        #expect(colored.contains("drawCircle"))
        #expect(!colored.contains("`"))
        #expect(colored.contains("\u{1B}["))
    }

    @Test("A web address is spelled out, a page link is not")
    func linkTargets() {
        let web = Markdown.render("See [the article](https://example.com/a).", style: Self.wide)
        #expect(web.contains("the article"))
        #expect(web.contains("<https://example.com/a>"))

        let page = Markdown.render("See [Color](./Drawing/Color.md).", style: Self.wide)
        #expect(page.contains("See Color."))
        #expect(!page.contains("Drawing/Color.md"))
    }

    @Test("A link whose own text carries brackets ends where it really ends")
    func nestedBrackets() {
        #expect(Markdown.plain("[a [b] c](./x.md) after") == "a [b] c after")
    }

    // MARK: - Blocks

    @Test("The breadcrumb line is left out")
    func breadcrumb() {
        let page = """
        #### <sup>[Ollin](../README.md) → `Color`</sup>

        ---

        ## Color

        A body line.
        """
        let text = Markdown.render(page, style: Self.wide)
        #expect(!text.contains("<sup>"))
        #expect(!text.contains("Ollin"))
        #expect(text.hasPrefix("Color"))
        #expect(text.hasSuffix("A body line."))
    }

    @Test("A page whose trail carries no rule under it keeps its body")
    func breadcrumbWithoutRule() {
        // Pages in this repository are written both ways, and hunting for a
        // rule that is not there took the whole page with it.
        let page = """
        #### <sup>[Ollin](../README.md) → Listening</sup>

        # Listening

        A body line.

        ---

        A line after a rule.
        """
        let text = Markdown.render(page, style: Self.wide)
        #expect(text.hasPrefix("Listening"))
        #expect(text.contains("A body line."))
        #expect(text.contains("A line after a rule."))
    }

    @Test("A link split across two lines is put back together")
    func wrappedParagraph() {
        // A page written with a hard wrap can break a link in half, and each
        // half alone is unreadable.
        let page = """
        The combinators, plus the [joint
        family](#combining): the chamfer and the stairs, behave as in 2D.
        """
        let text = Markdown.render(page, style: Self.wide)
        #expect(text.contains("the joint family: the chamfer"))
        #expect(!text.contains("]("))
    }

    @Test("Code is never joined to the prose above it")
    func codeIsNotJoined() {
        let page = """
        Before:

        ```swift
        let a = 1
        let b = 2
        ```
        """
        let text = Markdown.render(page, style: Self.wide)
        #expect(text.contains("    let a = 1\n    let b = 2"))
    }

    @Test("Code keeps its own spelling and its own line breaks")
    func codeBlock() {
        let page = """
        Before.

        ```swift
        let a = 1
            let b = 2
        ```

        After.
        """
        let text = Markdown.render(page, style: Self.wide)
        #expect(text.contains("    let a = 1"))
        #expect(text.contains("        let b = 2"))
        #expect(!text.contains("```"))
        #expect(!text.contains("swift\n"))
    }

    @Test("A table lines up, and its rule row does not survive")
    func table() throws {
        let page = """
        | Name | What it does |
        | --- | --- |
        | `a` | first |
        | `bbbb` | second |
        """
        let lines = Markdown.render(page, style: Self.wide).components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        #expect(lines.count == 4, "header, a rule of our own, and two rows")
        #expect(!lines.contains { $0.contains("---|") })
        // The second column starts at the same place on both rows.
        let first = try #require(lines.last { $0.contains("first") })
        let second = try #require(lines.last { $0.contains("second") })
        let firstAt = try #require(first.range(of: "first"))
        let secondAt = try #require(second.range(of: "second"))
        #expect(first.distance(from: first.startIndex, to: firstAt.lowerBound)
                == second.distance(from: second.startIndex, to: secondAt.lowerBound))
    }

    @Test("A list keeps its shape, and a long item hangs under its own text")
    func lists() {
        let page = "- one two three four five six seven eight nine ten eleven twelve"
        let lines = Markdown.render(page, style: TerminalStyle(color: false, width: 30))
            .components(separatedBy: "\n")
        #expect(lines.count > 1)
        #expect(lines[0].hasPrefix("- "))
        #expect(lines[1].hasPrefix("  "), "the wrap sits under the text, not under the mark")
        for line in lines { #expect(line.count <= 30) }
    }

    @Test("A figure written as a raw tag arrives as its description")
    func figures() {
        let page = """
        <picture>
        <source srcset="a.avif" type="image/avif">
        <img src="a.jpg" alt="a pale ridge under a blue sky" width="680">
        </picture>
        """
        let text = Markdown.render(page, style: Self.wide)
        #expect(text == "[figure: a pale ridge under a blue sky]")
    }

    // MARK: - Width

    @Test("Wrapping counts the columns a line takes, not the bytes it holds")
    func colorDoesNotCountAsWidth() {
        let colored = TerminalStyle(color: true, width: 40)
        let text = Markdown.render("**one two three four five six seven eight**", style: colored)
        for line in text.components(separatedBy: "\n") {
            #expect(Markdown.visibleLength(line) <= 40)
            #expect(line.count > Markdown.visibleLength(line), "the escapes are there and are not counted")
        }
    }

    // MARK: - Sections

    @Test("A section runs to the next heading of its own level")
    func sectionSlice() throws {
        let page = """
        ## Page

        Opening.

        ### Ramps

        The ramp part.

        #### Deeper

        Still the ramp part.

        ### Palettes

        Not the ramp part.
        """
        let slice = try #require(Markdown.section("ramps", in: page))
        #expect(slice.contains("The ramp part."))
        #expect(slice.contains("Still the ramp part."))
        #expect(!slice.contains("Not the ramp part."))
        #expect(!slice.contains("Opening."))
    }

    @Test("A heading is found the way somebody would type it")
    func sectionNaming() {
        let page = """
        ## Page

        ### `Ramp`s and palettes

        Body.
        """
        #expect(Markdown.section("ramps-and-palettes", in: page) != nil)
        #expect(Markdown.section("Ramps and palettes", in: page) != nil)
        #expect(Markdown.section("palettes", in: page) != nil, "part of a heading is enough")
        #expect(Markdown.section("nothing here", in: page) == nil)
    }

    @Test("Every heading of a page can be listed, which is what a miss offers")
    func headings() {
        let page = "## Page\n\n### `One`\n\n### Two\n"
        #expect(Markdown.headings(in: page) == ["Page", "One", "Two"])
    }
}
