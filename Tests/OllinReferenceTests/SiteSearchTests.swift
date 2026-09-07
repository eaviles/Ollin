import Foundation
import Testing
@testable import OllinReference

/// The search index the site writes: what goes in an entry, what stays out
/// of the word list, and how the file is spelled.
struct SiteSearchTests {

    @Test("Words are lower-cased, once each, without stop words, short words, or bare numbers")
    func tokens() {
        let words = SiteSearch.tokens("Draw a circle with `drawCircle(x, y, radius)`; the 3D scene, a 16-bit HDR frame, and the circle again.")
        #expect(words == ["draw", "circle", "drawcircle", "radius", "3d", "scene", "bit", "hdr", "frame"])
        #expect(SiteSearch.tokens("").isEmpty)
        #expect(SiteSearch.tokens("Filter.xdog(radius:)") == ["filter", "xdog", "radius"])
    }

    @Test("An excerpt is the first sentence, or a cut at a word")
    func excerpts() {
        #expect(SiteSearch.excerpt("A short line. Then another.") == "A short line.")
        #expect(SiteSearch.excerpt("  Spaced   out\nacross lines.  ") == "Spaced out across lines.")
        // An abbreviation, a decimal, and a file name end no sentence.
        #expect(SiteSearch.excerpt("Use a step, e.g. 0.5 of it, then stop. Next.") == "Use a step, e.g. 0.5 of it, then stop.")
        #expect(SiteSearch.excerpt("Open Package.swift. Then build. Done.") == "Open Package.swift. Then build.")
        // A sentence past the limit is cut at a word and marked as cut.
        let long = Array(repeating: "word", count: 60).joined(separator: " ") + " end."
        let cut = SiteSearch.excerpt(long, limit: 40)
        #expect(cut.hasSuffix("…"))
        #expect(cut.count <= 41, "\(cut)")
        #expect(!cut.contains("wor…"), "cut inside a word: \(cut)")
        #expect(SiteSearch.excerpt("").isEmpty)
        // A question ends a sentence too, and so does a period after a number
        // when a capital follows; a small letter after the space means the
        // sentence goes on.
        #expect(SiteSearch.excerpt("Why not? Because.") == "Why not?")
        #expect(SiteSearch.excerpt("Components run in 0...1. Most types do.") == "Components run in 0...1.")
        #expect(SiteSearch.excerpt("Call it once. then again. Done.") == "Call it once. then again.")
    }

    @Test("A page gives one entry for itself and one per heading, anchored as the page anchors them")
    func pageEntries() throws {
        let markdown = """
        # Color

        A color is a value you hold. It has a hue.

        ## Ramps

        A ramp blends between stops in OKLab. See [gradients](Gradients.md).

        ```swift
        let ramp = Ramp(.red, .blue)   // secretword
        ```

        ## Ramps

        The second one, with a picture. ![alt](x.png)

        | Name | Means |
        |---|---|
        | `lighter` | A step up in lightness |
        """
        let rendered = HTML.render(markdown) { target, _ in target }
        let page = SiteBuilder.Page(repoPath: "Docs/Drawing/Color.md", sitePath: "docs/drawing/color.html",
                                    kind: .docs, title: "Color", summary: "Colors, palettes, and ramps.")
        let entries = SiteSearch.entries(for: page, rendered: rendered)
        try #require(entries.count == 3)

        // A table of contents is skipped, and a project page beside the front
        // page lists its headings and first lines but none of its words.
        let contents = HTML.render("# Notes\n\nOpening.\n\n## Contents\n\n- [Deep](#deep)\n\n## Deep\n\nMany rare words here.\n") { target, _ in target }
        let about = SiteBuilder.Page(repoPath: "ARCHITECTURE.md", sitePath: "architecture.html", kind: .about, title: "Notes", summary: "")
        let listed = SiteSearch.entries(for: about, rendered: contents)
        #expect(listed.map(\.heading) == ["", "Deep"])
        #expect(listed.map(\.kind) == ["home", "home"])
        #expect(listed[1].excerpt == "Many rare words here." && listed[1].words.isEmpty, "\(listed[1])")
        #expect(listed[0].excerpt == "Opening." && listed[0].words.isEmpty)

        #expect(entries[0] == SiteSearch.Entry(kind: "docs", title: "Color", heading: "", url: "docs/drawing/color.html",
                                               excerpt: "A color is a value you hold.",
                                               words: ["value", "hold", "hue", "colors", "palettes", "ramps"]))
        #expect(entries[1].heading == "Ramps")
        #expect(entries[1].url == "docs/drawing/color.html#ramps")
        #expect(entries[1].excerpt == "A ramp blends between stops in OKLab.")
        #expect(entries[1].words == ["ramp", "blends", "stops", "oklab", "gradients"], "\(entries[1].words)")
        #expect(!entries[1].words.contains("secretword"), "code is not prose")
        // The second heading of the same name takes the anchor the page gave it.
        #expect(entries[2].url == "docs/drawing/color.html#ramps-1")
        #expect(entries[2].excerpt == "The second one, with a picture.")
        #expect(entries[2].words.contains("lighter") && entries[2].words.contains("lightness"), "table cells are prose: \(entries[2].words)")
        #expect(!entries[2].words.contains("alt") && !entries[2].words.contains("png"), "a picture is not prose")
        for entry in entries {
            #expect(!entry.words.contains("color"), "the title's own word rides every entry already")
        }
    }

    @Test("An example's entry carries its category, its listing line, its imports, and its opening comment")
    func exampleEntry() {
        let entry = ExampleEntry(path: "3D/Geometry/Ocean", directory: URL(fileURLWithPath: "/nowhere/Ocean"),
                                 summary: "A sea surface from a spectrum.", modules: ["OllinPhysics"], resources: [])
        let page = SiteBuilder.Page(repoPath: "Examples/3D/Geometry/Ocean", sitePath: "examples/3d/geometry/ocean.html",
                                    kind: .example(entry), title: "Ocean", summary: entry.summary)
        let source = """
        // Ocean: waves by Tessendorf's method.
        // After the classic paper.

        import Ollin
        // Not part of the header.
        """
        let made = SiteSearch.entry(for: entry, page: page, source: source)
        #expect(made.kind == "examples")
        #expect(made.title == "Ocean")
        #expect(made.heading == "3D / Geometry")
        #expect(made.url == "examples/3d/geometry/ocean.html")
        #expect(made.excerpt == "A sea surface from a spectrum.")
        #expect(made.words.contains("ollinphysics") && made.words.contains("tessendorf") && made.words.contains("spectrum"), "\(made.words)")
        #expect(!made.words.contains("header"), "the comment ends at the first line of code")
        #expect(!made.words.contains("ocean") && !made.words.contains("geometry"), "the title and category ride the entry already")

        // With no listing line, the opening comment stands in for the excerpt.
        let unlisted = ExampleEntry(path: "Basic/Dot", directory: entry.directory, summary: "", modules: [], resources: [])
        let quiet = SiteSearch.entry(for: unlisted, page: page, source: "// One dot.\nimport Ollin\n")
        #expect(quiet.excerpt == "One dot.")
    }

    @Test("A word common to most entries is dropped from all of them")
    func pruning() {
        func entry(_ words: [String]) -> SiteSearch.Entry {
            SiteSearch.Entry(kind: "docs", title: "T", heading: "", url: "t.html", excerpt: "", words: words)
        }
        let entries = [entry(["sketch", "kuwahara"]), entry(["sketch", "ramp"]), entry(["sketch", "sketchy"])]
        // With a limit of one entry in ten, rounded down to the floor of one,
        // a word in two entries goes and a word in one stays.
        let pruned = SiteSearch.pruned(entries, commonAbove: 0.1)
        #expect(pruned.map(\.words) == [["kuwahara"], ["ramp"], ["sketchy"]])
        // A share that lets a word sit in every entry keeps it.
        #expect(SiteSearch.pruned(entries, commonAbove: 1).map(\.words) == entries.map(\.words))
    }

    @Test("The index is one script setting one global, its JSON sorted and its brackets escaped")
    func script() throws {
        let entries = [
            SiteSearch.Entry(kind: "guide", title: "Ink <b>", heading: "A/B", url: "guide/01.html#a-b", excerpt: "Says \"hi\".", words: ["one", "two"]),
        ]
        let text = try SiteSearch.script(entries)
        #expect(text.hasPrefix("window.ollinSearchIndex = ["))
        #expect(text.hasSuffix("];\n"))
        #expect(!text.contains("<"), "an angle bracket could close the script that carries it")
        #expect(text.contains("\"u\":\"guide/01.html#a-b\""), "slashes stay slashes")
        let json = text.dropFirst("window.ollinSearchIndex = ".count).dropLast(2)
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]])
        #expect(parsed == [["k": "guide", "t": "Ink <b>", "h": "A/B", "u": "guide/01.html#a-b", "x": "Says \"hi\".", "w": "one two"]])
        // The same entries write the same bytes, so a rebuild changes nothing.
        #expect(try SiteSearch.script(entries) == text)
    }
}
