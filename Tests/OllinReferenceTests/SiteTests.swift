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

        // The logo: the favicon is the small form in paper on an ink tile,
        // Safari's pinned-tab icon the small form alone, every page's bar
        // wears the full mark in the page's own color, and the README's own
        // picture of the mark stays off the front page, whose bar has it.
        let favicon = try String(contentsOf: output.appendingPathComponent("favicon.svg"), encoding: .utf8)
        let small = try String(contentsOf: root.appendingPathComponent(SiteLogo.small), encoding: .utf8)
        #expect(favicon == SiteLogo.tiled(small, ink: SiteLogo.paper, tile: SiteLogo.ink), "the favicon is not the small form on its tile")
        let pinned = try String(contentsOf: output.appendingPathComponent("mask-icon.svg"), encoding: .utf8)
        #expect(pinned == SiteLogo.colored(small, ink: SiteLogo.ink), "the pinned-tab icon is not the small form in ink")
        for (name, page) in [("the front page", home), ("a chapter", chapter), ("an example", example)] {
            #expect(page.contains("<svg class=\"mark\" aria-hidden=\"true\" focusable=\"false\" viewBox=\"0 0 100 100\""),
                    "\(name) does not wear the full mark in its bar")
            #expect(!page.contains("viewBox=\"0 0 14 14\""), "\(name) wears the small form somewhere")
            #expect(page.contains("<link rel=\"mask-icon\" href=") && page.contains("<link rel=\"apple-touch-icon\" href="),
                    "\(name) names no pinned-tab or touch icon")
            #expect(!page.contains(SiteLogo.paper) && !page.contains("fill=\"#000"),
                    "\(name) draws the mark in its own ink, not the page's")
        }
        #expect(!home.contains("class=\"logo\"") && !home.contains("ollin-mark"), "the README's picture reached the front page beside the bar's mark")
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("apple-touch-icon.png").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("assets/social.png").path))

        // What a link to a page unfurls as: the card, at an absolute address
        // under the domain, on every page.
        for (name, page, path) in [("the front page", home, ""), ("a chapter", chapter, "guide/02-color.html"), ("an example", example, "examples/basic/hellocircle.html")] {
            #expect(page.contains("<meta property=\"og:image\" content=\"https://ollin.example/assets/social.png\">"), "\(name) has no card")
            #expect(page.contains("<meta property=\"og:url\" content=\"https://ollin.example/\(path)\">"), "\(name) has no address")
            #expect(page.contains("<meta name=\"twitter:card\" content=\"summary_large_image\">"))
        }

        // The front page shows the README's opening and the sections SiteHome
        // names, laid out in blocks, and hands every other section to the
        // About page, which is the README whole; every link the front page
        // makes at a README section lands on a page that carries the anchor.
        let about = try String(contentsOf: output.appendingPathComponent("about.html"), encoding: .utf8)
        for heading in SiteHome.shown {
            #expect(home.contains("<section class=\"home-section home-\(HTML.slug(heading))\">"), "the front page has no block for \(heading)")
        }
        #expect(home.contains("<div class=\"home-pair\">"))
        #expect(home.contains("<section class=\"home-section home-opening\">"))
        #expect(home.contains("<section class=\"home-section home-more\">"))
        #expect(!home.contains("class=\"badges\""), "the badge row reached the front page")
        #expect(!home.contains("id=\"live-reload\"") && !home.contains("id=\"built-with-ai\""), "a section left for the About page is on the front page")
        #expect(about.contains("id=\"live-reload\"") && about.contains("id=\"built-with-ai\"") && about.contains("id=\"hello-circle\""), "the About page is not the whole README")
        #expect(about.contains("class=\"badges\"") && about.contains("class=\"trail\"") == false, "the About page is the README as written")
        #expect(about.contains("<nav class=\"sidebar\"") && about.contains("<nav class=\"rail\""), "the About page reads like a project page")
        let aboutIds = Self.ids(in: about)
        let homeIds = Self.ids(in: home)
        var lost: [String] = []
        for href in Self.hrefs(in: home) {
            if href.hasPrefix("#") {
                if !homeIds.contains(String(href.dropFirst())) { lost.append(href) }
            } else if href.hasPrefix("about.html#") {
                if !aboutIds.contains(String(href.dropFirst("about.html#".count))) { lost.append(href) }
            }
        }
        #expect(lost.isEmpty, "front-page links at nothing: \(lost.joined(separator: ", "))")
        for href in Self.hrefs(in: about) where href.hasPrefix("#") {
            #expect(aboutIds.contains(String(href.dropFirst())), "the About page links at nothing: \(href)")
        }
        // A README anchor linked from the reference lands on the About page.
        let drag = try String(contentsOf: output.appendingPathComponent("docs/tools/dragtoedit.html"), encoding: .utf8)
        #expect(drag.contains("href=\"../../about.html#live-reload\""), "a README section linked from the reference does not reach the About page")
        #expect(aboutIds.contains("live-reload"))

        // The README's dark twin is the master in paper, written by
        // Scripts/logo.sh; a re-export that skipped the script shows up here.
        let master = try String(contentsOf: root.appendingPathComponent(SiteLogo.mark), encoding: .utf8)
        let twin = try String(contentsOf: root.appendingPathComponent("Logo/ollin-mark-dark.svg"), encoding: .utf8)
        #expect(twin == SiteLogo.colored(master, ink: SiteLogo.paper), "Logo/ollin-mark-dark.svg is not the mark in paper; run Scripts/logo.sh")
        for file in [SiteLogo.mark, SiteLogo.small] {
            let svg = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            #expect(!svg.contains("fill=") && !svg.contains("<title") && !svg.contains("transform=") && !svg.contains("<?xml"),
                    "\(file) is a raw export; run Scripts/logo.sh")
        }

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
    /// Every `href` on a page.
    static func hrefs(in html: String) -> [String] {
        var found: [String] = []
        var searchFrom = html.startIndex
        while let range = html.range(of: "href=\"", range: searchFrom ..< html.endIndex) {
            guard let close = html[range.upperBound...].firstIndex(of: "\"") else { break }
            found.append(String(html[range.upperBound ..< close]))
            searchFrom = close
        }
        return found
    }

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

    // MARK: - The front page

    @Test("The README splits at its sections, the chrome's rows leave the opening, and a heading inside code is code")
    func homeSplit() {
        let readme = """
        <picture>
          <img src="Logo/ollin-mark.svg" alt="" width="96">
        </picture>

        # Ollin

        **One line.**

        ![Platform](https://img.shields.io/badge/platform-blue) [![License](https://img.shields.io/badge/license-green)](LICENSE)

        [Guide](Guide/README.md) · [Docs](Docs/README.md) · [Examples](Examples/)

        Ollin is for generative art. See [the catalog](Docs/README.md#the-catalog) and [Status](#status--contributing).

        - **Platform:** macOS 26+

        ## Hello, circle

        ```swift
        // ## not a heading
        drawCircle(1, 2, 3)
        ```

        A circle. See [Live reload](#live-reload).

        ## Live reload

        Text.

        ### Inside

        More.

        ## Status & contributing

        Alpha.
        """
        let (opening, sections) = SiteHome.split(readme)
        #expect(sections.map(\.heading) == ["Hello, circle", "Live reload", "Status & contributing"])
        #expect(sections.map(\.anchor) == ["hello-circle", "live-reload", "status-contributing"])
        #expect(sections[0].markdown.hasPrefix("## Hello, circle\n"))
        #expect(sections[0].markdown.contains("// ## not a heading"))
        #expect(sections[1].markdown.contains("### Inside"))
        #expect(opening.contains("# Ollin") && opening.contains("- **Platform:** macOS 26+"))

        let trimmed = SiteHome.trimmedOpening(opening)
        #expect(!trimmed.contains("shields.io"), "the badge row stayed")
        #expect(!trimmed.contains("[Guide](Guide/README.md) ·"), "the navigation row stayed")
        #expect(trimmed.contains("Ollin is for generative art."))
        #expect(trimmed.contains("- **Platform:** macOS 26+"))
        #expect(SiteHome.isNavigationRow("[Guide](Guide/README.md) · [Docs](Docs/README.md)"))
        #expect(!SiteHome.isNavigationRow("[Guide](Guide/README.md) · then some words"))
        #expect(!SiteHome.isNavigationRow("See [Guide](Guide/README.md) · [Docs](Docs/README.md)"))

        #expect(SiteHome.anchors(in: sections[1].markdown) == ["live-reload", "inside"])
        #expect(SiteHome.anchors(in: sections[0].markdown) == ["hello-circle"], "a heading inside code counted")
        #expect(SiteHome.shown == ["Hello, circle", "Run it", "Install", "What's in it"])
        #expect(SiteBuilder.anchor("#status--contributing") == "#status-contributing")
        #expect(SiteBuilder.anchor("#a-b") == "#a-b")
    }

    @Test("The address GitHub Pages serves a repository at")
    func pagesAddress() {
        #expect(SiteBuilder.pagesAddress(of: "https://github.com/eaviles/Ollin") == "https://eaviles.github.io/Ollin/")
        #expect(SiteBuilder.pagesAddress(of: "https://github.com/Eaviles/Ollin.git") == "https://eaviles.github.io/Ollin/")
        #expect(SiteBuilder.pagesAddress(of: "https://example.com/eaviles/Ollin") == nil)
        #expect(SiteBuilder.pagesAddress(of: "https://github.com/eaviles") == nil)
    }

    // MARK: - The logo

    @Test("A master inlines in the page's color, writes in one color, or sits on a tile")
    func logoColors() {
        // A master: ink on nothing, no color of its own.
        let master = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">
          <path d="M1 1h3v3z"/>

          <circle cx="7" cy="7" r=".77"/>
        </svg>

        """
        let inline = SiteLogo.inline(master, className: "mark")
        #expect(inline == """
        <svg class="mark" aria-hidden="true" focusable="false" viewBox="0 0 14 14" fill="currentColor">
        <path d="M1 1h3v3z"/>
        <circle cx="7" cy="7" r=".77"/>
        </svg>
        """, "\(inline)")

        // A color set on the root reaches every shape, so a file keeps its
        // layout and gains one attribute; the tile is the first child and
        // fills the viewport whatever the box.
        #expect(SiteLogo.colored(master, ink: "#F4F3F0") == """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14" fill="#F4F3F0">
          <path d="M1 1h3v3z"/>

          <circle cx="7" cy="7" r=".77"/>
        </svg>

        """)
        #expect(SiteLogo.tiled(master, ink: "#F4F3F0", tile: "#0B0F14").hasPrefix("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14" fill="#F4F3F0">
          <rect width="100%" height="100%" fill="#0B0F14"/>
          <path d="M1 1h3v3z"/>
        """))

        // A raw export writes its black out and carries a prolog; both go,
        // or the color set on the root would reach nothing.
        let raw = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">
          <path d="M1 1h3v3z" fill="#000000"/>
          <circle cx="7" cy="7" r=".77" fill="#000"/>
        </svg>
        """
        let rawInline = SiteLogo.inline(raw, className: "logo")
        #expect(rawInline.hasPrefix("<svg class=\"logo\""))
        #expect(!rawInline.contains("#000") && !rawInline.contains("xml"), "\(rawInline)")
        #expect(SiteLogo.colored(raw, ink: "#F4F3F0").contains("<path d=\"M1 1h3v3z\"/>"))

        // Text with no drawing in it, and a file that is not there, give
        // nothing, which the build notes.
        #expect(SiteLogo.inline("not a drawing", className: "mark").isEmpty)
        #expect(SiteLogo.inline(readingAt: URL(fileURLWithPath: "/nowhere/ollin-mark.svg"), className: "mark").isEmpty)
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

    @Test("The site carries an index for an agent, and it points at markdown")
    func llmsIndex() throws {
        let root = try #require(Self.repositoryRoot())
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-llms-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }
        let builder = SiteBuilder(root: root, domain: "ollin.example")
        _ = try builder.build(into: output)

        let index = try String(contentsOf: output.appendingPathComponent("llms.txt"), encoding: .utf8)
        #expect(index.hasPrefix("# Ollin"), "the convention wants a title first")
        #expect(index.contains("\n> "), "and a blockquote saying what this is")
        // Every link has to reach markdown, or an agent following one falls
        // back into HTML halfway through.
        var links = 0
        var index2 = Substring(index)
        while let open = index2.range(of: "](https://") {
            guard let close = index2[open.upperBound...].firstIndex(of: ")") else { break }
            let url = String(index2[open.upperBound ..< close])
            #expect(url.hasSuffix(".md"), "\(url) is not markdown")
            links += 1
            index2 = index2[close...]
        }
        #expect(links > 100, "found only \(links) links")

        // The page and its twin sit at the same address but for the suffix,
        // and the page says where its twin is.
        let page = output.appendingPathComponent("docs/drawing/color.html")
        let twin = output.appendingPathComponent("docs/drawing/color.md")
        #expect(FileManager.default.fileExists(atPath: twin.path))
        let html = try String(contentsOf: page, encoding: .utf8)
        #expect(html.contains("rel=\"alternate\" type=\"text/markdown\" href=\"color.md\""))
        #expect(html.contains("rel=\"describedby\""))
        let markdown = try String(contentsOf: twin, encoding: .utf8)
        #expect(!markdown.contains("<html"), "the twin is markdown, not a page")
        #expect(markdown.contains(".md)"), "its own links reach markdown too")
    }

    // MARK: - The example media

    @Test("The manifest reads, and its absence is not a failure")
    func mediaManifest() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(ExampleMedia.read(inExamples: folder).entries.isEmpty,
                "a checkout with no manifest builds without pictures")

        let json = """
        {
          "base": "https://media.example/",
          "examples": {
            "Patterns/Kaleidoscope": {
              "loop": "examples/Patterns/Kaleidoscope/loop.mp4",
              "loopSmall": "examples/Patterns/Kaleidoscope/loop-640.mp4",
              "still": "examples/Patterns/Kaleidoscope/still.jpg",
              "stillSmall": "examples/Patterns/Kaleidoscope/still-640.jpg",
              "width": 1080, "height": 1080, "seconds": 8.0, "frame": 120
            }
          }
        }
        """
        try json.write(to: folder.appendingPathComponent("media.json"), atomically: true, encoding: .utf8)
        let media = ExampleMedia.read(inExamples: folder)
        let entry = try #require(media["Patterns/Kaleidoscope"])
        #expect(entry.width == 1080)
        // The trailing slash is trimmed on the way in, so joining never
        // doubles it, and a row a later field joins still decodes.
        #expect(media.address(of: try #require(entry.loop))
                == "https://media.example/examples/Patterns/Kaleidoscope/loop.mp4")
        #expect(media["Patterns/Nothing"] == nil)
    }

    @Test("The category order steps over the picture grid above it")
    func categoriesSkipTheGrid() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-index-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        // The grid's rows open the same way a category row does, and their
        // first link is the picture, so reading them would name the site's
        // sections after image files.
        try """
        ## Examples

        | [![Patterns](https://media.example/still-640.jpg)](Patterns/) | [![3D](https://media.example/b.jpg)](3D/) |
        |---|---|
        | [Patterns](Patterns/) | [3D](3D/) |

        | Category | What it holds |
        |---|---|
        | [Patterns](Patterns/) | rule-based repetition |
        | [3D](3D/) | scenes with a camera |
        """.write(to: file, atomically: true, encoding: .utf8)

        let found = SiteBuilder.categories(readingIndexAt: file)
        #expect(found.map(\.name) == ["Patterns", "3D"], "actual: \(found)")
        #expect(found.allSatisfy { !$0.path.contains("media.example") },
                "a picture's address is not a category")
    }

    @Test("A clip carries what a phone needs to play it inline")
    func clipAttributes() {
        let entry = ExampleMedia.Entry(loop: "e/loop.mp4", loopSmall: "e/loop-640.mp4",
                                       still: "e/still.jpg", stillSmall: "e/still-640.jpg",
                                       width: 1080, height: 1080, sound: nil)
        let media = ExampleMedia(base: "https://media.example", entries: [:])
        let html = SiteBuilder.clip(entry, in: media, named: "Kaleidoscope")
        // Without `playsinline` iOS Safari takes a playing video fullscreen,
        // and without `muted` it refuses to start at all.
        #expect(html.contains("playsinline"))
        #expect(html.contains("muted"))
        #expect(html.contains("loop"))
        #expect(html.contains("poster=\"https://media.example/e/still.jpg\""))
        #expect(html.contains("width=\"1080\" height=\"1080\""), "a stated size stops the page jumping")
        #expect(html.contains("prefers-reduced-motion"))
    }

    @Test("A page's opening picture becomes the clip it stands in for")
    func heroPlays() {
        let media = ExampleMedia(
            base: "https://media.example", entries: [:],
            heroes: ["guide": .init(image: "heroes/g.jpg?v=1", clip: "heroes/g.mp4?v=2",
                                    width: 1600, height: 800, of: "every chapter's sketch")])
        let body = """
        <p>before</p>
        <img src="https://media.example/heroes/g.jpg?v=1" alt="Every chapter" width="880">
        <p>after</p>
        """
        let out = SiteBuilder.playingHeroes(in: body, media: media)
        #expect(out.contains("<video src=\"https://media.example/heroes/g.mp4?v=2\""))
        // The picture becomes the poster, so a reader who blocks video or has
        // asked for less motion sees what the markdown promised.
        #expect(out.contains("poster=\"https://media.example/heroes/g.jpg?v=1\""))
        #expect(out.contains("aria-label=\"Every chapter\""), "the alt text carries over")
        #expect(!out.contains("<img"))
        #expect(out.contains("<p>before</p>") && out.contains("<p>after</p>"))

        // A page with no hero of its own is left exactly as it was.
        #expect(SiteBuilder.playingHeroes(in: "<p>plain</p>", media: media) == "<p>plain</p>")
    }

    @Test("The checkout's own manifest still names both heroes")
    func heroesSurviveTheTools() throws {
        // The tools that rewrite this file reorder it, and one of them used to
        // drop any key it did not know about, which deleted the heroes and
        // quietly turned the guide's playing grid back into a still.
        let root = try #require(Self.repositoryRoot())
        let media = ExampleMedia.read(inExamples: root.appendingPathComponent("Examples"))
        #expect(media.heroes["guide"] != nil, "the guide lost its opening clip")
        #expect(media.heroes["readme"] != nil, "the README lost its opening clip")
    }

    @Test("The front page's band names three sketches that are all still there")
    func showcaseIsWhole() throws {
        let root = try #require(Self.repositoryRoot())
        let media = ExampleMedia.read(inExamples: root.appendingPathComponent("Examples"))
        #expect(!media.showcase.isEmpty, "the front page lost its band of sketches")
        for piece in media.showcase {
            let entry = media[piece.example]
            #expect(entry != nil, "the band names \(piece.example), which has no media")
            // Without a clip there is nothing to show running, and the band's
            // whole claim is that these are running.
            #expect(entry?.loopSmall != nil, "\(piece.example) has no clip to play")
            let source = root.appendingPathComponent("Examples/\(piece.example)/Sketch.swift")
            #expect(FileManager.default.fileExists(atPath: source.path),
                    "the band names \(piece.example), which is not in the checkout")
        }
    }

    @Test("Every row in the manifest names an example that is still there")
    func mediaRowsAreNotStale() throws {
        let root = try #require(Self.repositoryRoot())
        let media = ExampleMedia.read(inExamples: root.appendingPathComponent("Examples"))
        for example in media.entries.keys.sorted() {
            let sketch = root.appendingPathComponent("Examples/\(example)/Sketch.swift")
            #expect(FileManager.default.fileExists(atPath: sketch.path),
                    "media.json names \(example), which is not in the checkout")
        }
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
