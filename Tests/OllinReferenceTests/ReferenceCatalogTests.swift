import Foundation
import Testing
@testable import OllinReference

/// Which pages exist, what the index says about them, and which one somebody
/// meant. Pure but for the reads of this repository's own folders.
@Suite("The reference catalog")
struct ReferenceCatalogTests {

    static func repositoryRoot() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let manifest = directory.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8),
               text.contains("name: \"Ollin\"") {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    // MARK: - The index

    @Test("The index gives a page its heading and its line")
    func indexEntries() throws {
        let index = """
        ### Concepts

        - [`The frame`](./Concepts/Frame.md) - what a drawing call actually does

        ### Drawing

        - [`Color`](./Drawing/Color.md) - the Color type and the OKLab family
        - not a page at all
        """
        let catalog = ReferenceLibrary.index(index)
        #expect(catalog.count == 2)
        let color = try #require(catalog["drawing/color"])
        #expect(color.group == "Drawing")
        #expect(color.summary == "the Color type and the OKLab family")
        #expect(catalog["concepts/frame"]?.group == "Concepts")
    }

    @Test("A page's own heading is its title")
    func titles() {
        let page = "#### <sup>a trail</sup>\n\n---\n\n## `Color`\n\nBody.\n"
        #expect(ReferenceLibrary.title(of: page) == "Color")
        #expect(ReferenceLibrary.title(of: "no heading here") == nil)
    }

    // MARK: - Against the repository

    @Test("Every page in this checkout is found, titled, and filed")
    func realPages() throws {
        let root = try #require(Self.repositoryRoot())
        let pages = ReferenceLibrary.pages(inDocs: root.appendingPathComponent("Docs"))

        #expect(pages.count > 100, "found \(pages.count) pages")
        #expect(!pages.contains { $0.topic.hasSuffix("README") }, "a folder listing is not a page")
        for page in pages {
            #expect(!page.title.isEmpty, "\(page.topic) has no heading")
            #expect(!page.group.isEmpty, "\(page.topic) is filed nowhere")
        }

        // The index is the catalog, so a page it does not reach is a page
        // nobody browsing can find. `Scripts/check-links.sh` gates the same
        // rule from the other direction.
        let index = try String(contentsOf: root.appendingPathComponent("Docs/README.md"), encoding: .utf8)
        let unreachable = pages.filter { !index.contains("\($0.topic).md") }.map(\.topic)
        #expect(unreachable.isEmpty, "not linked from Docs/README.md: \(unreachable.joined(separator: ", "))")
    }

    @Test("Every page in this checkout renders as terminal text")
    func realPagesRender() throws {
        let root = try #require(Self.repositoryRoot())
        let pages = ReferenceLibrary.pages(inDocs: root.appendingPathComponent("Docs"))
        let style = TerminalStyle(color: false, width: 92)

        for page in pages {
            let markdown = try String(contentsOf: page.url, encoding: .utf8)
            let text = Markdown.render(markdown, style: style)
            #expect(!text.isEmpty, "\(page.topic) rendered to nothing")
            #expect(text.hasPrefix(page.title), "\(page.topic) does not open on its own heading")

            for line in text.components(separatedBy: "\n") {
                // Code is printed as it was written, so only prose is checked.
                guard !line.hasPrefix("    ") else { continue }
                #expect(!line.contains("]("), "\(page.topic) has an unrendered link: \(line)")
                #expect(!line.contains("<img"), "\(page.topic) has an unrendered figure: \(line)")
                #expect(!line.contains("|--"), "\(page.topic) has an unrendered table rule")
            }
        }
    }

    @Test("The groups come out in the order the index uses them")
    func groupOrder() throws {
        let root = try #require(Self.repositoryRoot())
        let groups = ReferenceLibrary.groups(inDocs: root.appendingPathComponent("Docs"))
        #expect(groups.first == "Concepts")
        #expect(groups.contains("Drawing"))
        #expect(groups.count > 5)
    }

    // MARK: - Finding one

    static let sample: [ReferencePage] = [
        page("Drawing/Color", "Color", "Drawing", "the Color type, the OKLab family and mixing"),
        page("Drawing/Spectrum", "Spectral color", "Drawing", "the reflectance curve behind a color"),
        page("Concepts/Light", "Light and color", "Concepts", "why color mixes in linear light"),
        page("Output/Export", "Export", "Output", "writing a frame out"),
    ]

    static func page(_ topic: String, _ title: String, _ group: String, _ summary: String) -> ReferencePage {
        ReferencePage(topic: topic,
                      url: URL(fileURLWithPath: "/dev/null"),
                      title: title,
                      group: group,
                      summary: summary)
    }

    @Test("An exact name beats every page that merely mentions it")
    func exactBeatsLoose() {
        // Three of the four pages say "color" somewhere, so a substring match
        // would be useless here. This is the whole reason the ranks stop at
        // the first one that finds anything.
        #expect(PageQuery.resolve("color", in: Self.sample) == .one(Self.sample[0]))
        #expect(PageQuery.resolve("Drawing/Color", in: Self.sample) == .one(Self.sample[0]))
        #expect(PageQuery.resolve("drawing/color.md", in: Self.sample) == .one(Self.sample[0]))
    }

    @Test("A word that fits several pages equally asks which")
    func ambiguity() {
        guard case .several(let matches) = PageQuery.resolve("drawing", in: Self.sample) else {
            Issue.record("expected several matches")
            return
        }
        #expect(matches.count == 2, "the two pages filed under it")
    }

    @Test("A word no page carries is not answered with the wrong page")
    func nothing() {
        #expect(PageQuery.resolve("banana", in: Self.sample) == .none)
        #expect(PageQuery.resolve("   ", in: Self.sample) == .none)
    }

    @Test("A word in a summary still finds its page")
    func summaryMatch() {
        #expect(PageQuery.resolve("reflectance", in: Self.sample) == .one(Self.sample[1]))
    }
}
