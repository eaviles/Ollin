import Foundation
import Testing
@testable import OllinReference

/// Markdown into the site's HTML: the same shapes the terminal renderer is
/// tested on, checked for the tags they become and the paths they carry.
@Suite("The HTML renderer")
struct HTMLTests {

    /// A resolver that marks what it was asked, so a test can see both the
    /// target and whether it was taken for a picture.
    static var marking: HTML.Resolver {
        { target, image in (image ? "img:" : "link:") + target }
    }

    static var identity: HTML.Resolver { { target, _ in target } }

    // MARK: - Inline

    @Test("Markers become tags and text is escaped")
    func inlineMarkers() {
        let html = HTML.inline("**bold** and *italic* with `a < b` & more", resolve: Self.identity)
        #expect(html == "<strong>bold</strong> and <em>italic</em> with <code>a &lt; b</code> &amp; more")
    }

    @Test("Links and pictures go through the resolver, told apart")
    func linksResolve() {
        let html = HTML.inline("see [Color](../Drawing/Color.md#ramps) and ![a wheel](Images/wheel.jpg)",
                               resolve: Self.marking)
        #expect(html.contains("<a href=\"link:../Drawing/Color.md#ramps\">Color</a>"))
        #expect(html.contains("<img src=\"img:Images/wheel.jpg\" alt=\"a wheel\">"))
    }

    @Test("A web address is marked as leaving the site")
    func externalLinks() {
        let html = HTML.inline("[web](https://example.org)", resolve: Self.identity)
        #expect(html == "<a href=\"https://example.org\" rel=\"noopener\">web</a>")
    }

    @Test("A sup written into the prose survives; any other bracket is text")
    func inlineTags() {
        let html = HTML.inline("<sup>note</sup> and <Name> here", resolve: Self.identity)
        #expect(html == "<sup>note</sup> and &lt;Name&gt; here")
    }

    // MARK: - Anchors

    @Test("A heading's anchor follows the link checker's rule")
    func slugs() {
        #expect(HTML.slug("The `draw()` loop") == "the-draw-loop")
        #expect(HTML.slug("Why Apple-only") == "why-apple-only")
        #expect(HTML.slug("Wide gamut & HDR output") == "wide-gamut-hdr-output", "runs of space collapse, as the checker collapses them")
        #expect(HTML.slug("<sup>Ollin</sup> Guide") == "ollin-guide")
        #expect(HTML.slug("  Spaced   out  ") == "spaced-out")
    }

    @Test("Two headings with one name get two anchors")
    func duplicateAnchors() {
        let page = HTML.render("## Notes\n\ntext\n\n## Notes\n", resolve: Self.identity)
        #expect(page.body.contains("<h2 id=\"notes\">Notes</h2>"))
        #expect(page.body.contains("<h2 id=\"notes-1\">Notes</h2>"))
        #expect(page.headings.map(\.anchor) == ["notes", "notes-1"])
    }

    // MARK: - Blocks

    @Test("The trail comes off the top with its rule and is rendered apart")
    func trail() {
        let source = "#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 2</sup>\n\n---\n\n# 2. Color\n\nBody.\n"
        let page = HTML.render(source, resolve: Self.marking)
        #expect(page.trail == "<a href=\"link:../README.md\">Ollin</a> → <a href=\"link:README.md\">Guide</a> → Chapter 2")
        #expect(page.title == "2. Color")
        #expect(page.body.hasPrefix("<h1 id=\"2-color\">2. Color</h1>"))
        #expect(!page.body.contains("<hr>"))
    }

    @Test("Code keeps its spelling and is colored, not rendered")
    func codeBlock() {
        let source = "```swift\nlet x = \"a [link](no.md)\" // note\n```\n"
        let page = HTML.render(source, resolve: Self.marking)
        #expect(page.body.hasPrefix("<pre><code class=\"language-swift\">"))
        #expect(page.body.contains("<span class=\"tk-keyword\">let</span>"))
        #expect(page.body.contains("<span class=\"tk-string\">&quot;a [link](no.md)&quot;</span>"))
        #expect(page.body.contains("<span class=\"tk-comment\">// note</span>"))
        #expect(!page.body.contains("<a href"))
    }

    @Test("Strings and comments hold what is inside them")
    func highlighting() {
        let multiline = HTML.highlighted("\"\"\"\nlet a = 1\n\"\"\"", language: "swift")
        #expect(!multiline.contains("tk-keyword"), "a keyword inside a multi-line string is string")
        let raw = HTML.highlighted("#\"a \\ b\"#", language: "swift")
        #expect(raw.hasPrefix("<span class=\"tk-string\">"))
        let nested = HTML.highlighted("/* a /* b */ c */ let", language: "swift")
        #expect(nested.hasSuffix("</span> <span class=\"tk-keyword\">let</span>"), "a nested comment closes once")
        let shell = HTML.highlighted("swift run X # note", language: "sh")
        #expect(shell.contains("<span class=\"tk-comment\"># note</span>"))
        #expect(HTML.highlighted("<b>", language: "text") == "&lt;b&gt;")
    }

    @Test("A table is a table with the rule row dropped")
    func table() {
        let source = "| Example | What it shows |\n|---|---|\n| [A](A/) | one |\n| `B` | two |\n"
        let page = HTML.render(source, resolve: Self.marking)
        #expect(page.body.contains("<thead><tr><th>Example</th><th>What it shows</th></tr></thead>"))
        #expect(page.body.contains("<td><a href=\"link:A/\">A</a></td><td>one</td>"))
        #expect(page.body.contains("<td><code>B</code></td><td>two</td>"))
        #expect(!page.body.contains("---"))
    }

    @Test("Lists nest by indent and close in order")
    func lists() {
        let source = "- one\n  - inside\n  - also\n- two\n\n1. first\n2. second\n"
        let page = HTML.render(source, resolve: Self.identity)
        let flat = page.body.replacingOccurrences(of: "\n", with: "")
        #expect(flat.contains("<ul><li>one<ul><li>inside</li><li>also</li></ul></li><li>two</li></ul>"))
        #expect(flat.contains("<ol><li>first</li><li>second</li></ol>"))
    }

    @Test("A quote holds its paragraphs")
    func blockquote() {
        let source = "> **Status: alpha.** Read on.\n>\n> Second.\n"
        let page = HTML.render(source, resolve: Self.identity)
        #expect(page.body == "<blockquote>\n<p><strong>Status: alpha.</strong> Read on.</p>\n<p>Second.</p>\n</blockquote>")
    }

    @Test("A figure block passes through with its paths resolved")
    func figures() {
        let source = """
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="Images/A-dark.jpg">
          <img src="Images/A.jpg" alt="A picture" width="680">
        </picture>

        <a name="color"></a>
        """
        let page = HTML.render(source, resolve: Self.marking)
        #expect(page.body.contains("srcset=\"img:Images/A-dark.jpg\""))
        #expect(page.body.contains("src=\"img:Images/A.jpg\" alt=\"A picture\" width=\"680\""))
        #expect(page.body.contains("<a name=\"color\"></a>"))
    }

    @Test("A wrapped paragraph is one paragraph")
    func wrapped() {
        let source = "The [whole\nfamily](#combining) is here.\n"
        let page = HTML.render(source, resolve: Self.identity)
        #expect(page.body == "<p>The <a href=\"#combining\">whole family</a> is here.</p>")
    }

    @Test("Each heading's prose is read out plain beside it, with code and pictures left out")
    func sectionsAsPlainText() {
        let markdown = """
        Before any heading.

        # Title

        The *opening* line, with [a link](Other.md) and `code`.

        ## First

        - One item
        - Two items

        > Quoted words.

        ```swift
        let hidden = 1
        ```

        ## Second

        <picture><img src="x.png" alt="A figure"></picture>

        | Head | Cell |
        |---|---|
        | `a` | b |

        Plain again.
        """
        let page = HTML.render(markdown) { target, _ in target }
        #expect(page.headings.count == 3)
        #expect(page.sections.count == 4)
        #expect(page.sections[0] == "Before any heading.")
        #expect(page.sections[1] == "The opening line, with a link and code.")
        #expect(page.sections[2] == "One item Two items Quoted words.")
        #expect(page.sections[3] == "Head Cell a b Plain again.")
        #expect(!page.sections.joined().contains("hidden"), "code is not prose")
        #expect(!page.sections.joined().contains("figure"), "a picture is not prose")
        #expect(HTML.plainText("**Bold** and <sup>up</sup> ![pic](p.png) 1 < 2") == "Bold and up 1 < 2")
    }

    @Test("A row of badges is marked so the layout can set it small")
    func badges() {
        let source = "![a](https://img.shields.io/a) [![b](https://img.shields.io/b)](LICENSE)\n"
        let page = HTML.render(source, resolve: Self.identity)
        #expect(page.body.hasPrefix("<p class=\"badges\">"))
        #expect(HTML.paragraphClass("![a](x) and words").isEmpty)
    }
}
