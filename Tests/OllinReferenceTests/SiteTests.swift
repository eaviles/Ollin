import Foundation
import Testing
@testable import OllinReference

/// The site builder: where pages land, where links go, and the whole
/// checkout rendered end to end, since the corpus is what finds the shapes
/// nobody would invent.
@Suite("The site")
struct SiteTests {

    // MARK: - Paths

    @Test("A repository path lands lower-cased, with README as the folder's index")
    func sitePaths() {
        #expect(SiteBuilder.sitePath(forRepoPath: "README.md") == "index.html")
        #expect(SiteBuilder.sitePath(forRepoPath: "Docs/README.md") == "docs/index.html")
        #expect(SiteBuilder.sitePath(forRepoPath: "Docs/Drawing/Color.md") == "docs/drawing/color.html")
        #expect(SiteBuilder.sitePath(forRepoPath: "Examples/3D/Geometry/Ocean") == "examples/3d/geometry/ocean.html")
        #expect(SiteBuilder.sitePath(forRepoPath: "CHANGELOG.md") == "changelog.html")
    }

    @Test("A relative path is read against the page's own folder")
    func joining() {
        #expect(SiteBuilder.joined(["Docs", "Drawing"], "../Core/Sketch.md") == "Docs/Core/Sketch.md")
        #expect(SiteBuilder.joined(["Docs", "Drawing"], "./Color.md") == "Docs/Drawing/Color.md")
        #expect(SiteBuilder.joined(["Guide"], "../README.md") == "README.md")
        #expect(SiteBuilder.joined([], "Examples/") == "Examples")
        #expect(SiteBuilder.joined(["Guide"], "../../outside.md") == nil)
    }

    @Test("Pages link to each other by the shortest relative path")
    func relativePaths() {
        let builder = SiteBuilder(root: URL(fileURLWithPath: "/nowhere"))
        #expect(builder.relative(from: "docs/drawing", to: "docs/core/sketch.html") == "../core/sketch.html")
        #expect(builder.relative(from: "docs/drawing", to: "docs/drawing/color.html") == "color.html")
        #expect(builder.relative(from: "", to: "guide/index.html") == "guide/index.html")
        #expect(builder.relative(from: "guide", to: "index.html") == "../index.html")
        #expect(builder.relative(from: "examples/3d/geometry", to: "assets/site.css") == "../../../assets/site.css")
    }

    // MARK: - Against the repository

    static func repositoryRoot() -> URL? { ReferenceCatalogTests.repositoryRoot() }

    @Test("The plan holds every kind of page, titled")
    func plan() throws {
        let root = try #require(Self.repositoryRoot())
        let plan = SiteBuilder(root: root).plan()

        #expect(plan.byRepoPath["README.md"] != nil)
        #expect(plan.byRepoPath["Guide/README.md"] != nil)
        #expect(plan.byRepoPath["Guide/01-HelloOllin.md"]?.title.hasPrefix("1.") == true)
        #expect(plan.byRepoPath["Guide/AUTHORING.md"] == nil, "the authoring notes are not for readers")
        #expect(plan.byRepoPath["CLAUDE.md"] == nil, "the agent guidance is not a page")
        #expect(plan.byRepoPath["Docs/Drawing/Color.md"]?.title == "Color")
        #expect(plan.byRepoPath["Docs/Tools/README.md"] != nil, "a folder index is a page")
        #expect(plan.examples.count > 300, "found \(plan.examples.count) examples")
        #expect(plan.docsGroups.count > 5)
        #expect(plan.docsGroups.first?.name == "Concepts")
        #expect(plan.exampleCategories.count > 20)
        for page in plan.pages {
            #expect(!page.title.isEmpty, "\(page.repoPath) has no title")
        }
    }

    @Test("A link goes to the page, the listing, the sketch's page, or GitHub")
    func resolving() throws {
        let root = try #require(Self.repositoryRoot())
        let builder = SiteBuilder(root: root)
        let plan = builder.plan()
        let log = SiteBuilder.LinkLog()
        let color = try #require(plan.byRepoPath["Docs/Drawing/Color.md"])
        let home = try #require(plan.byRepoPath["README.md"])
        let motion = try #require(plan.byRepoPath["Examples/Motion/README.md"])

        func go(_ target: String, from page: SiteBuilder.Page, image: Bool = false) -> String {
            builder.resolve(target, image: image, from: page, plan: plan, log: log)
        }

        #expect(go("../Core/Sketch.md#draw", from: color) == "../core/sketch.html#draw")
        #expect(go("../README.md", from: color) == "../index.html")
        #expect(go("#ramps", from: color) == "#ramps")
        #expect(go("https://example.org", from: color) == "https://example.org")
        #expect(go("Examples/", from: home) == "examples/index.html")
        #expect(go("Guide/README.md", from: home) == "guide/index.html")
        #expect(go("LICENSE", from: home) == "https://github.com/eaviles/Ollin/blob/main/LICENSE")
        #expect(go("Sources/", from: home) == "https://github.com/eaviles/Ollin/tree/main/Sources")
        #expect(go("ArcModes/Sketch.swift", from: motion) == "arcmodes.html")
        #expect(go("ArcModes/", from: motion) == "arcmodes.html")
        #expect(go("../Images/Color/Ramps.jpg", from: color, image: true).hasSuffix("/images/color/ramps.jpg")
                || log.missing.contains { $0.contains("Ramps.jpg") })

        let before = log.missing.count
        #expect(go("NoSuchPage.md", from: color) == "NoSuchPage.md")
        #expect(log.missing.count == before + 1)
    }

    @Test("The whole checkout renders as a site with no dead link and every picture in place")
    func realSite() throws {
        let root = try #require(Self.repositoryRoot())
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-site-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }

        let builder = SiteBuilder(root: root, domain: "ollin.example")
        let report = try builder.build(into: output)

        #expect(report.pages > 250, "wrote \(report.pages) pages")
        #expect(report.examples > 300, "wrote \(report.examples) example pages")
        #expect(report.images > 500, "copied \(report.images) pictures")
        #expect(report.missing.isEmpty, "unresolved: \(report.missing.prefix(10).joined(separator: "; "))")
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("CNAME").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("assets/site.css").path))

        // Every relative link and picture on every page points at a file the
        // build wrote, and no markdown is left in the prose.
        let walker = try #require(FileManager.default.enumerator(at: output, includingPropertiesForKeys: nil))
        var checked = 0
        var dead: [String] = []
        var leftovers: [String] = []
        for case let url as URL in walker where url.pathExtension == "html" {
            let html = try String(contentsOf: url, encoding: .utf8)
            let folder = url.deletingLastPathComponent()
            for target in Self.targets(in: html) {
                guard !target.hasPrefix("#"), !target.contains("://"), !target.hasPrefix("mailto:") else { continue }
                let path = String(target.split(separator: "#", maxSplits: 1)[0])
                let file = folder.appendingPathComponent(path).standardized
                if !FileManager.default.fileExists(atPath: file.path) {
                    dead.append("\(url.lastPathComponent) -> \(target)")
                }
                checked += 1
            }
            if Self.prose(of: html).contains("](") {
                leftovers.append(url.path.replacingOccurrences(of: output.path + "/", with: ""))
            }
            if let range = html.range(of: "<title>") {
                let title = html[range.upperBound...].prefix { $0 != "<" }
                #expect(!title.isEmpty, "\(url.lastPathComponent) has no title")
            }
        }
        #expect(checked > 5_000, "checked \(checked) targets")
        #expect(dead.isEmpty, "dead: \(dead.prefix(10).joined(separator: "; ")) (\(dead.count))")
        #expect(leftovers.isEmpty, "markdown left in: \(leftovers.prefix(10).joined(separator: ", "))")

        // The front page opens on the hero, and a chapter opens on its trail.
        let home = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
        #expect(home.contains("class=\"hero\""))
        #expect(home.contains("<link rel=\"canonical\" href=\"https://ollin.example/\">"))
        let chapter = try String(contentsOf: output.appendingPathComponent("guide/02-color.html"), encoding: .utf8)
        #expect(chapter.contains("class=\"trail\""))
        #expect(chapter.contains("aria-current=\"page\""))
        #expect(chapter.contains("<link rel=\"canonical\" href=\"https://ollin.example/guide/02-color.html\">"))
        let example = try String(contentsOf: output.appendingPathComponent("examples/basic/hellocircle.html"), encoding: .utf8)
        #expect(example.contains("language-swift"))
        #expect(example.contains("Example-Basic-HelloCircle"))
    }

    /// The page's text alone: no code (which keeps its own spelling), no
    /// tags, and none of their attributes.
    static func prose(of html: String) -> String {
        var text = html
        for (open, close) in [("<pre", "</pre>"), ("<code", "</code>")] {
            while let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound ..< text.endIndex) {
                text.removeSubrange(start.lowerBound ..< end.upperBound)
            }
        }
        while let start = text.firstIndex(of: "<"), let end = text[start...].firstIndex(of: ">") {
            text.removeSubrange(start ... end)
        }
        return text
    }

    /// Every `href`, `src`, and `srcset` on a page.
    static func targets(in html: String) -> [String] {
        var found: [String] = []
        for attribute in ["href=\"", "src=\"", "srcset=\""] {
            var searchFrom = html.startIndex
            while let range = html.range(of: attribute, range: searchFrom ..< html.endIndex) {
                guard let close = html[range.upperBound...].firstIndex(of: "\"") else { break }
                found.append(String(html[range.upperBound ..< close]))
                searchFrom = close
            }
        }
        return found
    }
}
