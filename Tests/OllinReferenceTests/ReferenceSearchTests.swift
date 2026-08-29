import Foundation
import Testing
@testable import OllinReference

/// Reading the whole reference for a word, over a small folder written for
/// the test so the expected hits can be counted exactly.
@Suite("Searching the reference")
struct ReferenceSearchTests {

    /// A tiny reference: two pages and an index that lists them.
    static func makeDocs() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OllinReference-\(UUID().uuidString)")
        let drawing = folder.appendingPathComponent("Drawing")
        try FileManager.default.createDirectory(at: drawing, withIntermediateDirectories: true)

        try """
        ## Ollin API

        ### Drawing

        - [`Color`](./Drawing/Color.md) - the Color type and its mixing
        - [`Shapes`](./Drawing/Shapes.md) - the shapes you can draw
        """.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        #### <sup>a trail</sup>

        ---

        ## Color

        ### Mixing

        Two colors mix in linear light.

        ### Ramps

        A ramp carries stops.
        """.write(to: drawing.appendingPathComponent("Color.md"), atomically: true, encoding: .utf8)

        try """
        ## Shapes

        ### Rings

        A ring is drawn in linear light too.
        """.write(to: drawing.appendingPathComponent("Shapes.md"), atomically: true, encoding: .utf8)

        // A folder listing, which is navigation rather than a page.
        try "## Drawing\n\nlinear light lives here.\n"
            .write(to: drawing.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return folder
    }

    @Test("A word is found in every page that says it, with its line and its heading")
    func hits() throws {
        let folder = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: folder) }

        let pages = ReferenceLibrary.pages(inDocs: folder)
        #expect(pages.count == 2, "the folder listing is not a page")

        let hits = ReferenceSearch.hits(for: "linear light", in: pages)
        #expect(hits.count == 2)
        #expect(hits.map(\.section).sorted() == ["Mixing", "Rings"])
        #expect(hits.allSatisfy { $0.line > 0 })
        #expect(hits.contains { $0.text.contains("Two colors mix") })
    }

    @Test("The page whose own name carries the word is reported first")
    func naming() throws {
        let folder = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: folder) }

        let pages = ReferenceLibrary.pages(inDocs: folder)
        let hits = ReferenceSearch.hits(for: "color", in: pages)
        #expect(hits.first?.page.topic == "Drawing/Color")
    }

    @Test("One page gives up only so many lines, so one page cannot fill the answer")
    func perPageCap() throws {
        let folder = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: folder) }

        let pages = ReferenceLibrary.pages(inDocs: folder)
        let hits = ReferenceSearch.hits(for: "a", in: pages, perPage: 1)
        #expect(hits.count == 2, "one line from each page")
    }

    @Test("A word nothing says finds nothing")
    func nothing() throws {
        let folder = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: folder) }

        let pages = ReferenceLibrary.pages(inDocs: folder)
        #expect(ReferenceSearch.hits(for: "banana", in: pages).isEmpty)
        #expect(ReferenceSearch.hits(for: "  ", in: pages).isEmpty)
    }

    @Test("A page the index does not list is still a page, and says so")
    func unlisted() throws {
        let folder = try Self.makeDocs()
        defer { try? FileManager.default.removeItem(at: folder) }
        try "## Late\n\nAdded today.\n".write(to: folder.appendingPathComponent("Drawing/Late.md"),
                                              atomically: true, encoding: .utf8)

        let pages = ReferenceLibrary.pages(inDocs: folder)
        let late = try #require(pages.first { $0.topic == "Drawing/Late" })
        #expect(late.title == "Late")
        #expect(late.group == "Drawing", "with no index entry it falls back to its folder")
        #expect(late.summary.isEmpty)
        #expect(PageQuery.resolve("late", in: pages) == .one(late))
    }
}
