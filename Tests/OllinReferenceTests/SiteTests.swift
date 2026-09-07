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

        // The logo: the favicon is the logo's own file, every page's bar wears
        // the small form in the page's ink, and the front page opens with the
        // full mark lifted off the README rather than the README's picture,
        // each mark with a mask of its own.
        let favicon = try String(contentsOf: output.appendingPathComponent("favicon.svg"), encoding: .utf8)
        let source = try String(contentsOf: root.appendingPathComponent(SiteLogo.favicon), encoding: .utf8)
        #expect(favicon == source, "the favicon is not the logo's own file")
        for (name, page) in [("the front page", home), ("a chapter", chapter), ("an example", example)] {
            #expect(page.contains("<svg class=\"mark\" aria-hidden=\"true\""), "\(name) has no mark in its bar")
            #expect(!page.contains(SiteLogo.ink) && !page.contains(SiteLogo.paper), "\(name) draws the mark in its own ink, not the page's")
        }
        #expect(home.contains("<svg class=\"logo\" aria-hidden=\"true\""), "the front page opens without the mark")
        #expect(!home.contains("ollin-mark"), "the README's picture reached the front page beside the hero's mark")
        #expect(home.components(separatedBy: "id=\"mark-eye\"").count == 2)
        #expect(home.components(separatedBy: "id=\"logo-eye\"").count == 2)
        #expect(home.contains("mask=\"url(#logo-eye)\""))
        #expect(!chapter.contains("class=\"logo\""), "only the front page wears the full mark")

        // The search: every page carries the button, the dialog with the way
        // back to the site's root, and the script; the index lists one entry
        // per section and per example, each at a page the build wrote and an
        // anchor that page carries, and it stays small enough to load on a
        // first search.
        for (name, page, up) in [("the front page", home, ""), ("a chapter", chapter, "../"), ("an example", example, "../../")] {
            #expect(page.contains("<button class=\"search-toggle\" type=\"button\" aria-label=\"Search\" title=\"Search\" hidden>"), "\(name) has no search button")
            #expect(page.contains("<dialog id=\"search\" class=\"search\" data-root=\"\(up)\" aria-label=\"Search\">"), "\(name) has no search dialog, or the wrong way up")
            #expect(page.contains("<script src=\"\(up)assets/search.js\" defer></script>"), "\(name) does not load the search")
        }
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("assets/search.js").path))
        let indexText = try String(contentsOf: output.appendingPathComponent("assets/search-index.js"), encoding: .utf8)
        #expect(report.sections > 3_000, "indexed \(report.sections) sections")
        #expect(indexText.utf8.count < 3_000_000, "the index is \(indexText.utf8.count) bytes")
        let entries = try Self.searchEntries(in: indexText)
        #expect(entries.count == report.sections)
        var ids: [String: Set<String>] = [:]
        var broken: [String] = []
        for entry in entries {
            let url = entry["u"] ?? ""
            let parts = url.split(separator: "#", maxSplits: 1).map(String.init)
            let file = output.appendingPathComponent(parts[0])
            guard FileManager.default.fileExists(atPath: file.path) else { broken.append(url); continue }
            if parts.count == 2 {
                if ids[parts[0]] == nil { ids[parts[0]] = Self.ids(in: try String(contentsOf: file, encoding: .utf8)) }
                if ids[parts[0]]?.contains(parts[1]) != true { broken.append(url) }
            }
            if (entry["t"] ?? "").isEmpty { broken.append("untitled: \(url)") }
            if !["guide", "docs", "examples", "home"].contains(entry["k"] ?? "") { broken.append("kind \(entry["k"] ?? ""): \(url)") }
        }
        #expect(broken.isEmpty, "search entries pointing at nothing: \(broken.prefix(10)) (\(broken.count))")
        #expect(entries.contains { $0["u"] == "examples/basic/hellocircle.html" && $0["k"] == "examples" && $0["h"] == "Basic" })
        #expect(entries.contains { ($0["u"] ?? "").hasPrefix("docs/drawing/color.html#") && $0["k"] == "docs" })
        #expect(entries.contains { $0["u"] == "guide/02-color.html" && $0["h"]?.isEmpty == true && $0["k"] == "guide" && !($0["x"] ?? "").isEmpty })
        #expect(!entries.contains { ($0["w"] ?? "").split(separator: " ").contains("the") }, "a stop word reached the index")
    }

    /// The entries the site's index script carries.
    static func searchEntries(in script: String) throws -> [[String: String]] {
        let prefix = "window.ollinSearchIndex = "
        try #require(script.hasPrefix(prefix) && script.hasSuffix(";\n"), "the index is not one script setting one global")
        let json = script.dropFirst(prefix.count).dropLast(2)
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]])
    }

    /// Every `id` on a page.
    static func ids(in html: String) -> Set<String> {
        var found = Set<String>()
        var searchFrom = html.startIndex
        while let range = html.range(of: " id=\"", range: searchFrom ..< html.endIndex) {
            guard let close = html[range.upperBound...].firstIndex(of: "\"") else { break }
            found.insert(String(html[range.upperBound ..< close]))
            searchFrom = close
        }
        return found
    }

    // MARK: - The search in a browser

    /// A page carrying the search's own script and a small index of its own,
    /// that opens the search, types each query in turn, and reports what the
    /// list shows for it: one line per row as `href|text|marks`, the blocks
    /// separated by a rule.
    static func searchProbe(queries: [String]) throws -> String {
        let index = try SiteSearch.script([
            SiteSearch.Entry(kind: "docs", title: "Effects", heading: "", url: "docs/effects.html",
                             excerpt: "Filters over a layer.", words: ["blur", "sharpen"]),
            SiteSearch.Entry(kind: "docs", title: "Effects", heading: "Brushwork", url: "docs/effects.html#brushwork",
                             excerpt: "The layer as paint patches.", words: ["kuwahara", "anisotropic", "sectors"]),
            SiteSearch.Entry(kind: "guide", title: "Color", heading: "", url: "guide/02-color.html",
                             excerpt: "A color is a value.", words: ["oklab", "ramps"]),
            SiteSearch.Entry(kind: "examples", title: "Brushwork", heading: "Effects", url: "examples/effects/brushwork.html",
                             excerpt: "A photo as paint.", words: ["kuwahara", "painterly"]),
        ])
        let list = try String(decoding: JSONSerialization.data(withJSONObject: queries), as: UTF8.self)
        return """
        <!doctype html><html><head><meta charset="utf-8"></head><body>
        <button class="search-toggle" type="button" hidden><span class="key"></span></button>
        <dialog id="search" class="search" data-root="../"><div class="search-panel"><form class="search-box"><input type="search"><kbd>esc</kbd></form><p class="search-status"></p><ul class="search-results"></ul></div></dialog>
        <script>\(index)</script>
        <script>
        \(SiteStyle.searchScript)
        </script>
        <pre id="r0">PENDING</pre>
        <script>
        (function () {
          var out = document.getElementById('r0');
          var input = document.querySelector('#search input');
          var status = document.querySelector('.search-status');
          var toggle = document.querySelector('.search-toggle');
          var queries = \(list);
          var tries = 0;
          if (toggle.hidden) { out.textContent = 'FAIL the button stayed hidden'; return; }
          toggle.click();
          function poll() {
            var text = status.textContent;
            if (text.indexOf('did not load') >= 0) { out.textContent = 'FAIL ' + text; return; }
            if (text.indexOf('sections') < 0) {
              if (++tries > 600) { out.textContent = 'FAIL timeout: ' + text; return; }
              setTimeout(poll, 25);
              return;
            }
            var blocks = queries.map(function (query) {
              input.value = query;
              input.dispatchEvent(new Event('input', { bubbles: true }));
              var rows = Array.prototype.map.call(document.querySelectorAll('.search-results li'), function (item) {
                var a = item.querySelector('a');
                var text = Array.prototype.map.call(a.children, function (span) { return span.textContent; }).join(' ');
                return a.getAttribute('href') + '|' + text.replace(/\\s+/g, ' ').trim() + '|' + a.querySelectorAll('mark').length + (item.className === 'active' ? '|active' : '');
              });
              return [status.textContent].concat(rows).join('\\n');
            });
            out.textContent = blocks.join('\\n---\\n');
          }
          poll();
        })();
        </script>
        </body></html>
        """
    }

    /// Whether the library the search loads can be reached, since the probe
    /// loads it the way a reader's browser does.
    static func searchLibraryReachable() async -> Bool {
        guard let url = URL(string: SiteStyle.searchLibrary) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    @Test("The search finds a section by a word of its prose, puts a page ahead of its sections, and marks what matched",
          .enabled("a browser and the search library's network are needed") {
              guard HeadlessBrowser.isInstalled else { return false }
              return await Self.searchLibraryReachable()
          })
    func searchInABrowser() async throws {
        // Virtual time, so the index build's small steps and the library's
        // arrival both finish before the page is read.
        let flags = HeadlessBrowser.baseFlags + ["--virtual-time-budget=20000"]
        let queries = ["kuwahara", "effects", "kuwa", "colour", "kuwa colour", "nothinghere"]
        let dom = try await HeadlessBrowser.dom(of: Self.searchProbe(queries: queries), flags: flags, timeout: 120)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        try #require(!report.hasPrefix("FAIL") && !report.hasPrefix("PENDING"), "\(report)")
        let blocks = report.components(separatedBy: "\n---\n").map { $0.split(separator: "\n").map(String.init) }
        try #require(blocks.count == queries.count, "\(report)")

        // A word only the prose says finds both sections that say it, each
        // marked nowhere (the word is not in what is shown) and the first row active.
        let kuwahara = blocks[0]
        #expect(kuwahara.first == "2 matches", "\(report)")
        let found = Set(kuwahara.dropFirst().map { $0.split(separator: "|")[0] })
        #expect(found == ["../docs/effects.html#brushwork", "../examples/effects/brushwork.html"], "\(report)")
        #expect(kuwahara.dropFirst().first?.hasSuffix("|active") == true, "\(report)")

        // A title: the page's own entry first, ahead of its section, which
        // says the same word in the same field (only the page's own boost
        // tells them apart), with the example whose category says the word
        // among them; the word marked in each. The section and the example
        // are not ordered here, since on four entries the rarity of a word
        // in a field outweighs the field's boost.
        let effects = blocks[1]
        #expect(effects.first == "3 matches", "\(report)")
        let hrefs = effects.dropFirst().map { String($0.split(separator: "|")[0]) }
        #expect(hrefs.first == "../docs/effects.html", "\(report)")
        #expect(Set(hrefs) == ["../docs/effects.html", "../docs/effects.html#brushwork", "../examples/effects/brushwork.html"], "\(report)")
        #expect(effects.dropFirst().allSatisfy { $0.split(separator: "|")[2] != "0" }, "the title is not marked: \(report)")
        #expect(effects[1].contains("Reference Effects Filters over a layer."), "\(report)")

        // A prefix reaches the word, a typo in a longer word is forgiven, and
        // every word has to match, so nothing carries both.
        #expect(blocks[2].first == "2 matches", "\(report)")
        #expect(blocks[3].first == "1 match" && blocks[3].dropFirst().first?.hasPrefix("../guide/02-color.html|") == true, "\(report)")
        #expect(blocks[4].first == "Nothing matches “kuwa colour”.", "\(report)")
        #expect(blocks[5].first == "Nothing matches “nothinghere”.", "\(report)")
    }

    // MARK: - The logo

    @Test("A logo file inlines with its tile dropped, its ink as the page's, and a mask of its own")
    func inlineLogo() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" fill="none" stroke="#F4F3F0" stroke-width="9">
          <rect width="100" height="100" fill="#0B0F14" stroke="none"/>
          <mask id="eye"><rect width="100" height="100" fill="#fff"/><circle cx="50" cy="50" r="26" fill="#000"/></mask>
          <g mask="url(#eye)">
            <rect x="8" y="40" width="84" height="20" rx="10" transform="rotate(45 50 50)"/>
          </g>
          <circle cx="50" cy="50" r="5.5" fill="#F4F3F0" stroke="none"/>
        </svg>
        """
        let inline = SiteLogo.inline(svg, id: "bar-eye", className: "mark")
        #expect(inline.hasPrefix("<svg class=\"mark\" aria-hidden=\"true\" focusable=\"false\" viewBox=\"0 0 100 100\""))
        #expect(!inline.contains("xmlns"))
        #expect(!inline.contains("<rect width=\"100\" height=\"100\" fill=\"#0B0F14\""), "the tile came along")
        #expect(inline.contains("<mask id=\"bar-eye\"><rect width=\"100\" height=\"100\" fill=\"#fff\"/>"), "the mask's own white is not ink")
        #expect(inline.contains("mask=\"url(#bar-eye)\""))
        #expect(!inline.contains("id=\"eye\"") && !inline.contains("url(#eye)"))
        #expect(!inline.contains("#F4F3F0") && !inline.contains("#0B0F14"))
        #expect(inline.contains("stroke=\"currentColor\" stroke-width=\"9\""))
        #expect(inline.contains("fill=\"currentColor\" stroke=\"none\""))
        #expect(!inline.contains("\n\n"), "blank lines came along")
        #expect(!inline.contains("  <"), "indentation came along")

        // A file that is not there inlines as nothing, which the build notes.
        #expect(SiteLogo.inline(readingAt: URL(fileURLWithPath: "/nowhere/ollin-mark.svg"), id: "x", className: "mark").isEmpty)
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
