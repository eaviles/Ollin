import CoreGraphics
import Foundation
import ImageIO
import OllinWebGate
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
                // Both sides resolved, since a temporary directory walks out
                // with a `/private` in front of it and a plain prefix strip
                // then matches nothing, leaving the page unnamed in the failure.
                let root = output.resolvingSymlinksInPath().path + "/"
                leftovers.append(url.resolvingSymlinksInPath().path.replacingOccurrences(of: root, with: ""))
            }
            if let range = html.range(of: "<title>") {
                let title = html[range.upperBound...].prefix { $0 != "<" }
                #expect(!title.isEmpty, "\(url.lastPathComponent) has no title")
            }
        }
        #expect(checked > 5_000, "checked \(checked) targets")
        #expect(dead.isEmpty, "dead: \(dead.prefix(10).joined(separator: "; ")) (\(dead.count))")
        #expect(leftovers.isEmpty, "markdown left in: \(leftovers.prefix(10).joined(separator: ", "))")

        // The front page opens on the hero with the ring in it, and a chapter
        // opens on its trail.
        let home = try String(contentsOf: output.appendingPathComponent("index.html"), encoding: .utf8)
        #expect(home.contains("class=\"hero\""))
        #expect(home.contains("<div class=\"hero-canvas\" aria-hidden=\"true\">"), "the front page opens without its ring")
        #expect(home.contains("<canvas class=\"ollin-sketch\""))
        #expect(home.contains("player.set('paper'"))
        #expect(!home.contains("site.js"), "the ring plays from the page itself, not a deferred file")
        #expect(report.notes.isEmpty, "\(report.notes.joined(separator: "; "))")
        #expect(home.contains("<link rel=\"canonical\" href=\"https://ollin.example/\">"))
        let chapter = try String(contentsOf: output.appendingPathComponent("guide/02-color.html"), encoding: .utf8)
        #expect(chapter.contains("class=\"trail\""))
        #expect(chapter.contains("aria-current=\"page\""))
        #expect(chapter.contains("<link rel=\"canonical\" href=\"https://ollin.example/guide/02-color.html\">"))
        let example = try String(contentsOf: output.appendingPathComponent("examples/basic/hellocircle.html"), encoding: .utf8)
        #expect(example.contains("language-swift"))
        #expect(example.contains("Example-Basic-HelloCircle"))
    }

    // MARK: - The front page's ring

    @Test("The ring is the sketch's own web page, recorded whole")
    func ringIsTheRecordedPage() {
        let fragment = SiteHero.fragment
        #expect(!fragment.isEmpty, "Sources/OllinReference/SiteHero.swift holds no recording; run Scripts/site-hero.sh")
        #expect(fragment.hasPrefix("<canvas class=\"ollin-sketch\" width=\"1080\" height=\"1080\""))
        #expect(fragment.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("</script>"))
        #expect(fragment.contains("<script>"))
        // The panel's own styling travels with the player whether or not a
        // panel is built, so what says the front page draws none is the flag
        // the inline form bakes in, not the absence of the word.
        #expect(fragment.contains("var PANEL = false"), "the inline form draws no panel")
    }

    /// The front page's hero, as the site writes it, inside a page that carries
    /// the site's own colors and reports what the ring did.
    static func heroProbe(bg: String, text: String) -> String {
        let root = URL(fileURLWithPath: "/nowhere")
        let builder = SiteBuilder(root: root)
        var markdown = "# Ollin\n\n**A line.**\n"
        let page = SiteBuilder.Page(repoPath: "README.md", sitePath: "index.html", kind: .home, title: "Ollin", summary: "")
        let hero = builder.homeHero(&markdown, page: page, plan: SiteBuilder.Plan())
        return """
        <!doctype html><html><head><style>:root { --bg: \(bg); --text: \(text); }</style></head><body>
        \(hero)
        <pre id="r0">PENDING</pre>
        <script>
        (function () {
          var out = document.getElementById('r0');
          try {
            var canvas = document.querySelector('.hero-canvas canvas');
            var player = canvas && canvas.ollin;
            if (!player) { out.textContent = 'FAIL no player'; return; }
            player.pause();
            var names = player.params.map(function (p) { return p.name; }).join(',');
            player.showFrame(0);
            var themed = canvas.toDataURL('image/png');
            player.reset();
            player.showFrame(0);
            var recorded = canvas.toDataURL('image/png');
            out.textContent = names + '\\n' + themed + '\\n' + recorded;
          } catch (e) { out.textContent = 'FAIL ' + e; }
        })();
        </script>
        </body></html>
        """
    }

    @Test("The ring plays in a browser, in the page's paper and ink",
          .enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func ringFollowsTheSite() async throws {
        try #require(!SiteHero.fragment.isEmpty, "Sources/OllinReference/SiteHero.swift holds no recording; run Scripts/site-hero.sh")
        // The dark scheme's own values, where the recorded black on white is
        // the wrong way round and the difference cannot be missed.
        let dom = try await HeadlessBrowser.dom(of: Self.heroProbe(bg: "#0e0d0d", text: "#f0eeee"))
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        try #require(lines.count == 3, "\(report.prefix(300))")

        let names = lines[0].split(separator: ",").map(String.init)
        #expect(names.contains("ink") && names.contains("paper"), "controls: \(names)")

        let themed = try Self.rgba(fromDataURL: lines[1])
        let recorded = try Self.rgba(fromDataURL: lines[2])
        try #require(themed.width == 1080 && themed.height == 1080)

        // The corner is paper: the page's in the themed picture, the recorded
        // white before it. The ring is ink: something light on the dark paper,
        // something dark on the white.
        let corner = themed.pixel(5, 5)
        #expect(abs(corner.r - 14) <= 3 && abs(corner.g - 13) <= 3 && abs(corner.b - 13) <= 3, "themed corner \(corner)")
        let recordedCorner = recorded.pixel(5, 5)
        #expect(recordedCorner.r >= 250 && recordedCorner.g >= 250 && recordedCorner.b >= 250, "recorded corner \(recordedCorner)")
        #expect(themed.brightest() > 100, "no ink on the themed ring: brightest \(themed.brightest())")
        #expect(recorded.darkest() < 200, "no ink on the recorded ring: darkest \(recorded.darkest())")
    }

    struct Pixels {
        var width: Int
        var height: Int
        var bytes: [UInt8]
        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
        func brightest() -> Int {
            var best = 0
            for i in stride(from: 0, to: bytes.count, by: 4) { best = max(best, Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])) }
            return best
        }
        func darkest() -> Int {
            var best = 255
            for i in stride(from: 0, to: bytes.count, by: 4) { best = min(best, Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])) }
            return best
        }
    }

    /// The pixels of a PNG data URL the page wrote, as RGBA bytes.
    static func rgba(fromDataURL report: String) throws -> Pixels {
        let prefix = "data:image/png;base64,"
        try #require(report.hasPrefix(prefix), "\(report.prefix(200))")
        let data = try #require(Data(base64Encoded: String(report.dropFirst(prefix.count))))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                                 bytesPerRow: w * 4, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Pixels(width: w, height: h, bytes: bytes)
    }

    /// The page's text alone: no code (which keeps its own spelling), no
    /// tags, and none of their attributes.
    /// A script is skipped whole beside code, since a script is not prose and
    /// the front page carries one: the ring's recorded page, whose shaders
    /// spell an array as `vec2[6](…)`, and those two characters are what an
    /// unrendered markdown link looks like.
    ///
    /// One pass, keeping the text and stepping over everything else. Cutting a
    /// range at a time instead rereads and recopies the whole page on every
    /// tag, which the front page's recorded ring made plain: the same walk
    /// went from seven minutes to longer than the suite was willing to wait.
    static func prose(of html: String) -> String {
        let blocks = [("<script", "</script>"), ("<pre", "</pre>"), ("<code", "</code>")]
        var text = ""
        text.reserveCapacity(html.count)
        var index = html.startIndex
        while index < html.endIndex {
            guard html[index] == "<" else {
                text.append(html[index])
                index = html.index(after: index)
                continue
            }
            let rest = html[index...]
            if let block = blocks.first(where: { rest.hasPrefix($0.0) }) {
                // An unclosed block runs to the end of the page, as it does in
                // a browser.
                index = html.range(of: block.1, range: index ..< html.endIndex)?.upperBound ?? html.endIndex
                continue
            }
            if let close = rest.firstIndex(of: ">") {
                index = html.index(after: close)
            } else {
                index = html.endIndex
            }
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
