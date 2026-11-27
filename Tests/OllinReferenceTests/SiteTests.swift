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

    /// The checkout planned once for the suite. A plan reads every page in the
    /// Guide, the reference, and the examples for its title, and three tests
    /// read the same one; it is written once and only read afterwards.
    nonisolated(unsafe) static let checkoutPlan: SiteBuilder.Plan? = repositoryRoot().map { SiteBuilder(root: $0).plan() }

    @Test("The plan holds every kind of page, titled")
    func plan() throws {
        let plan = try #require(Self.checkoutPlan)

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
        let plan = try #require(Self.checkoutPlan)
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

    /// One build of the whole checkout serves every check on what the site
    /// writes: the pages and their links, the logo, the front page, the search,
    /// the index for an agent with the markdown twins, and the sitemap. A build
    /// is most of this suite's time, so the checks read one rather than each
    /// building the site again.
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
        var unmarked: [String] = []
        // The floor under every page: its pictures say their size and all
        // but the first wait, a Tab reaches the way past the menu before
        // anything else, and a phone's bars take the page's own ground.
        var unsized: [String] = []
        var eager: [String] = []
        // The menus: a page with a menu carries what opens it on a phone and
        // the two scripts that place and follow, and a page with a list of
        // its sections carries the same list folded under its title.
        var unwired: [String] = []
        var unfolded: [String] = []
        var unskippable: [String] = []
        var untinted: [String] = []
        // One look across the sections: a page opens on one title at the
        // first level, its trail starts at the root and names the section
        // as the bar does, and its list of sections has a top level.
        var untitled: [String] = []
        var rootless: [String] = []
        var misnamed: [String] = []
        var indented: [String] = []
        var pictures = 0
        let mediaBase = ExampleMedia.read(inRepository: root).base
        let examplesFolder = output.appendingPathComponent("examples").resolvingSymlinksInPath().path + "/"
        for case let url as URL in walker where url.pathExtension == "html" {
            let html = try String(contentsOf: url, encoding: .utf8)
            let folder = url.deletingLastPathComponent()
            // Every page of the examples says where it is in its menu, once:
            // itself, or the row that holds it.
            if url.resolvingSymlinksInPath().path.hasPrefix(examplesFolder),
               let menu = html.range(of: "<nav class=\"sidebar\""),
               let menuEnd = html.range(of: "</nav>", range: menu.upperBound ..< html.endIndex) {
                let marks = html[menu.upperBound ..< menuEnd.lowerBound].components(separatedBy: " aria-current=\"").count - 1
                if marks != 1 { unmarked.append("\(url.lastPathComponent): \(marks)") }
            }
            for target in Self.targets(in: html) {
                guard !target.hasPrefix("#"), !target.contains("://"), !target.hasPrefix("mailto:") else { continue }
                let path = String(target.split(separator: "#", maxSplits: 1)[0])
                let file = folder.appendingPathComponent(path).standardized
                if !FileManager.default.fileExists(atPath: file.path) {
                    dead.append("\(url.lastPathComponent) -> \(target)")
                }
                checked += 1
            }
            let name = url.resolvingSymlinksInPath().path
                .replacingOccurrences(of: output.resolvingSymlinksInPath().path + "/", with: "")
            for (index, tag) in Self.pictureTags(in: html).enumerated() {
                pictures += 1
                let source = Self.value(of: "src", in: tag)
                // A picture from a host that is neither the site nor its
                // media (a badge) is the one kind whose size nothing knows.
                let known = !source.contains("://") || (!mediaBase.isEmpty && source.hasPrefix(mediaBase + "/"))
                if known, Int(Self.value(of: "width", in: tag)) == nil || Int(Self.value(of: "height", in: tag)) == nil {
                    unsized.append("\(name): \(source)")
                }
                if index > 0, !tag.contains(" loading=\"lazy\"") { eager.append("\(name): \(source)") }
                if index == 0, tag.contains(" loading=\"lazy\"") { eager.append("\(name): its first picture waits") }
            }
            let hasMenu = html.contains("<nav class=\"sidebar\"")
            let openers = html.components(separatedBy: " aria-controls=\"menu\"").count - 1
            let wired = html.contains("<nav class=\"sidebar\" id=\"menu\" aria-label=\"Section\" tabindex=\"-1\">")
                && html.contains("</nav>\n" + SiteStyle.menuPlaceScript + "\n<main ")
                && html.contains("assets/menus.js\" defer></script>")
                && html.contains("<head>") && html.contains(SiteStyle.scriptedMark)
            if hasMenu ? (openers != 1 || !wired) : (openers != 0 || html.contains("assets/menus.js")) {
                unwired.append("\(name): \(openers) openers")
            }
            let beside = Self.anchors(in: html, from: "<nav class=\"rail\"", to: "</nav>")
            let folded = Self.anchors(in: html, from: "<details class=\"onpage\">", to: "</details>")
            if beside != folded || beside.count == 1 {
                unfolded.append("\(name): \(beside.count) beside the page, \(folded.count) in the fold")
            } else if !folded.isEmpty, let article = html.range(of: "<article"),
                      let fold = html.range(of: "<details class=\"onpage\">") {
                // Right under the title: one heading stands between the
                // article's opening and the fold, and it closes just before it.
                let above = html[article.upperBound ..< fold.lowerBound]
                let headings = (1 ... 6).reduce(0) { $0 + above.components(separatedBy: "</h\($1)>").count - 1 }
                if headings != 1 || !(1 ... 6).contains(where: { above.hasSuffix("</h\($0)>\n") }) {
                    unfolded.append("\(name): the fold is not under the title")
                }
            }
            let levels = Self.headingLevels(inMainOf: html)
            if levels.first != 1 || levels.filter({ $0 == 1 }).count != 1 {
                untitled.append("\(name): \(levels.prefix(6))")
            }
            let trail = Self.trail(of: html)
            if name != "index.html", name != "404.html" {
                // The first step is a link to the front page, called Ollin.
                let first = Self.hrefs(in: trail).first ?? ""
                let home = output.appendingPathComponent("index.html").standardized.resolvingSymlinksInPath().path
                if !trail.hasPrefix("<a href=\"\(first)\">Ollin</a> → ")
                    || folder.appendingPathComponent(first).standardized.resolvingSymlinksInPath().path != home {
                    rootless.append("\(name): \(Self.words(of: trail))")
                }
            }
            let steps = Self.words(of: trail).components(separatedBy: " → ")
            let section = name.split(separator: "/").first.map(String.init) ?? ""
            if let called = ["guide": "Guide", "docs": "Reference", "examples": "Examples"][section], name.contains("/"),
               steps.count < 2 || steps[1] != called {
                misnamed.append("\(name): \(steps.prefix(3))")
            }
            if let rail = html.range(of: "<nav class=\"rail\""),
               let railEnd = html.range(of: "</nav>", range: rail.upperBound ..< html.endIndex),
               !html[rail.upperBound ..< railEnd.lowerBound].contains("<li class=\"level-2\">") {
                indented.append(name)
            }
            if let body = html.range(of: "<body>") {
                let after = html[body.upperBound...]
                let stops = ["<a ", "<button", "<input", "<summary", "<select", "<textarea", "<video", "tabindex=\"0\""]
                let first = stops.compactMap { after.range(of: $0)?.lowerBound }.min()
                if first.map({ after[$0...].hasPrefix("<a class=\"skip\" href=\"#main\">") }) != true
                    || !html.contains("<main id=\"main\" tabindex=\"-1\">") {
                    unskippable.append(name)
                }
            }
            if !html.contains("<meta name=\"theme-color\" media=\"(prefers-color-scheme: light)\" content=\"\(SiteStyle.ground)\">")
                || !html.contains("<meta name=\"theme-color\" media=\"(prefers-color-scheme: dark)\" content=\"\(SiteStyle.groundDark)\">") {
                untinted.append(name)
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
        #expect(pictures > 1_500, "read \(pictures) pictures")
        #expect(unsized.isEmpty, "pictures with no size, which take no room until they arrive: \(unsized.prefix(6)) (\(unsized.count))")
        #expect(eager.isEmpty, "pictures below a page's first that load with the page, or a first one that waits: \(eager.prefix(6)) (\(eager.count))")
        #expect(unskippable.isEmpty, "pages where a Tab does not reach the skip link first, or it has nowhere to land: \(unskippable.prefix(6)) (\(unskippable.count))")
        #expect(untinted.isEmpty, "pages that do not tell a phone the color of their ground: \(untinted.prefix(6)) (\(untinted.count))")
        #expect(unwired.isEmpty, "pages whose menu has no way in on a phone or is not placed and followed, or pages with no menu that carry one: \(unwired.prefix(6)) (\(unwired.count))")
        #expect(unfolded.isEmpty, "pages whose list of sections is not also folded under the title, link for link: \(unfolded.prefix(6)) (\(unfolded.count))")
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("assets/menus.js").path))
        #expect(untitled.isEmpty, "pages that do not open on one first-level title: \(untitled.prefix(6)) (\(untitled.count))")
        #expect(rootless.isEmpty, "pages whose trail does not start at the front page: \(rootless.prefix(6)) (\(rootless.count))")
        #expect(misnamed.isEmpty, "pages whose trail calls their section something the bar does not: \(misnamed.prefix(6)) (\(misnamed.count))")
        #expect(indented.isEmpty, "pages whose list of sections has no top level, so every entry is set in: \(indented.prefix(6)) (\(indented.count))")

        // The examples' menu names the categories in the order the index
        // shows them: the names under its pictures, row by row.
        let examplesIndex = try String(contentsOf: root.appendingPathComponent("Examples/README.md"), encoding: .utf8)
        var shown: [String] = []
        for line in examplesIndex.components(separatedBy: "\n") where line.hasPrefix("| [") && !line.hasPrefix("| [![") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // The grid's rows of names hold links and nothing else.
            guard cells.count > 1, cells.allSatisfy({ $0.hasPrefix("[") && $0.hasSuffix(")") }) else { continue }
            shown += cells.map { String($0.dropFirst().prefix { $0 != "]" }) }
        }
        let examplesMenu = Self.menu(of: try String(contentsOf: output.appendingPathComponent("examples/index.html"), encoding: .utf8))
        let listedGroups = examplesMenu.components(separatedBy: "<summary>").dropFirst().map { String($0.prefix { $0 != "<" }) }
        #expect(shown.count > 20 && listedGroups == shown, "the menu lists \(listedGroups.prefix(8)) where the index shows \(shown.prefix(8))")

        // The changelog's list is its releases, by name alone.
        let changelog = try String(contentsOf: output.appendingPathComponent("changelog.html"), encoding: .utf8)
        let releases = Self.railLabels(of: changelog)
        #expect(releases.count > 15 && releases.first == "Unreleased", "the changelog lists \(releases.prefix(4))")
        #expect(releases.dropFirst().allSatisfy { name in name.split(separator: ".").count == 3 && name.allSatisfy { $0.isNumber || $0 == "." } },
                "the changelog's list holds something that is not a release: \(releases.filter { !$0.allSatisfy { $0.isNumber || $0 == "." } })")
        #expect(changelog.contains(">[Unreleased]</h2>"), "the page itself no longer writes a release as its file does")

        // The project pages go by short names in the menu and the trail,
        // and each still opens on its own file's title.
        let conduct = try String(contentsOf: output.appendingPathComponent("code_of_conduct.html"), encoding: .utf8)
        let projectRows = Self.words(of: Self.menu(of: conduct))
        #expect(projectRows.contains("Home About Contributing Changelog Roadmap Architecture Capabilities Design notes Attribution Third-party notices Code of conduct Security"),
                "the project pages' menu reads: \(projectRows)")
        #expect(Self.words(of: Self.trail(of: conduct)) == "Ollin → Code of conduct")
        #expect(conduct.contains(">Contributor Covenant Code of Conduct</h1>"), "the page lost its own title")

        // The reference's menu has a row for every page of the reference:
        // the two beside the index sit with the overview, and a folder's
        // own index is its group's first row.
        for (file, row) in [("docs/quickreference.html", "Ollin quick reference"), ("docs/swift.html", "Swift quick reference"),
                            ("docs/core/index.html", "All Core"), ("docs/tools/index.html", "All Tools")] {
            let menu = Self.menu(of: try String(contentsOf: output.appendingPathComponent(file), encoding: .utf8))
            #expect(menu.contains(" aria-current=\"page\">\(row)</a>"), "\(file) is not marked in the reference's menu as \(row)")
        }
        var unlisted: [String] = []
        for file in try FileManager.default.subpathsOfDirectory(atPath: output.appendingPathComponent("docs").path) where file.hasSuffix(".html") {
            let menu = Self.menu(of: try String(contentsOf: output.appendingPathComponent("docs/\(file)"), encoding: .utf8))
            if menu.components(separatedBy: " aria-current=\"page\"").count - 1 != 1 { unlisted.append(file) }
        }
        #expect(unlisted.isEmpty, "reference pages with no row of their own in the menu: \(unlisted.prefix(8)) (\(unlisted.count))")

        // Every chapter and appendix ends on its cards, with nothing left of
        // the line they were made from; the first has no chapter before it
        // and the last none after.
        var unpaged: [String] = []
        var chapters = 0
        for file in try FileManager.default.contentsOfDirectory(atPath: output.appendingPathComponent("guide").path).sorted()
        where file.hasSuffix(".html") && file != "index.html" {
            let page = try String(contentsOf: output.appendingPathComponent("guide/\(file)"), encoding: .utf8)
            chapters += 1
            let cards = page.components(separatedBy: "<a class=\"pager-card ").count - 1
            if !page.contains("<nav class=\"pager\" aria-label=\"Previous and next\">") || cards < 1
                || page.contains(" · Previous: ") || page.contains(" · Next: ") || !page.contains("<a class=\"pager-up\" href=\"index.html#contents\">Contents</a>") {
                unpaged.append(file)
            }
        }
        #expect(chapters >= 52, "read \(chapters) chapters and appendices")
        #expect(unpaged.isEmpty, "chapters that do not end on their cards: \(unpaged.prefix(6)) (\(unpaged.count))")
        let firstChapter = try String(contentsOf: output.appendingPathComponent("guide/01-helloollin.html"), encoding: .utf8)
        #expect(firstChapter.contains("pager-next") && !firstChapter.contains("pager-previous"))
        let nineteenth = try String(contentsOf: output.appendingPathComponent("guide/19-layersandeffects.html"), encoding: .utf8)
        #expect(nineteenth.contains("<a class=\"pager-card pager-previous\" rel=\"prev\" href=\"18-yourfirstshader.html\"><span class=\"pager-way\">Previous</span><span class=\"pager-name\">Chapter 18, Your first shader</span></a>"),
                "chapter 19's card for the chapter before it is not the line's own link")

        // The reference's overview opens none of its groups, a page opens
        // the one it is in, and a folder's index the ones its pages are in.
        let overviewMenu = Self.menu(of: try String(contentsOf: output.appendingPathComponent("docs/index.html"), encoding: .utf8))
        #expect(!overviewMenu.isEmpty && !overviewMenu.contains("<details open>"), "the reference's overview opens groups of its menu")
        let pageMenu = Self.menu(of: try String(contentsOf: output.appendingPathComponent("docs/core/sketch.html"), encoding: .utf8))
        #expect(pageMenu.components(separatedBy: "<details open>").count - 1 == 1)
        let folderMenu = Self.menu(of: try String(contentsOf: output.appendingPathComponent("docs/core/index.html"), encoding: .utf8))
        #expect(folderMenu.contains("<details open>"), "a folder's index opens no group")
        // A size that is the picture's own: a chapter's figure written at a
        // width keeps it and gains the height that goes with its file.
        let figures = try String(contentsOf: output.appendingPathComponent("guide/19-layersandeffects.html"), encoding: .utf8)
        let layers = try #require(Self.pictureTags(in: figures).first { $0.contains("/layers.jpg\"") }, "chapter 19 lost its layer diagram")
        let onDisk = try #require(SiteBuilder.pixelSize(ofPictureAt: root.appendingPathComponent("Guide/Images/19-LayersAndEffects/Layers.jpg")))
        let written = (Double(Self.value(of: "width", in: layers)) ?? 0, Double(Self.value(of: "height", in: layers)) ?? 0)
        #expect(abs(written.0 / written.1 - Double(onDisk.width) / Double(onDisk.height)) < 0.01,
                "the layer diagram is \(onDisk.width) by \(onDisk.height) and its tag says \(layers)")

        // The page a wrong address gets: in the site's chrome, with the search
        // and the three sections, every path from the root so it works at
        // whatever depth the host serves it, and out of every index.
        let wrongAddress = try String(contentsOf: output.appendingPathComponent("404.html"), encoding: .utf8)
        #expect(wrongAddress.contains("<h1>\(SiteBuilder.notFoundTitle)</h1>") && wrongAddress.contains(HTML.escape(SiteBuilder.notFoundLine)))
        #expect(wrongAddress.contains("<header class=\"bar\">") && wrongAddress.contains("<dialog id=\"search\" class=\"search\" data-root=\"/\" aria-label=\"Search\">"),
                "the page for a wrong address has no bar, or its search cannot find the index")
        #expect(wrongAddress.contains("<button class=\"button\" type=\"button\" data-search-open hidden>"), "it offers no search of its own")
        for section in ["guide", "docs", "examples"] {
            #expect(wrongAddress.contains("<a class=\"card\" href=\"/\(section)/index.html\">"), "it does not offer the \(section) section")
        }
        #expect(wrongAddress.contains("<meta name=\"robots\" content=\"noindex\">"))
        #expect(!wrongAddress.contains("rel=\"canonical\"") && !wrongAddress.contains("rel=\"alternate\"") && !wrongAddress.contains("og:url"),
                "a page with no address of its own claims one")
        #expect(!wrongAddress.contains("<nav class=\"sidebar\"") && !wrongAddress.contains("<nav class=\"rail\""))
        var unrooted: [String] = []
        for target in Self.targets(in: wrongAddress) where !target.hasPrefix("#") && !target.contains("://") {
            if !target.hasPrefix("/") { unrooted.append(target) }
        }
        #expect(unrooted.isEmpty, "paths that only work at the root: \(unrooted)")
        #expect(wrongAddress.contains("'/favicon-dark.svg':'/favicon.svg'"), "its favicon is swapped by a relative path")

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
        #expect(example.contains("<nav class=\"trail\" aria-label=\"Breadcrumb\"><a href=\"../../index.html\">Ollin</a> → <a href=\"../index.html\">Examples</a> → <a href=\"index.html\">Basic</a> → HelloCircle</nav>"),
                "an example's trail does not run from the front page to the sketch")
        #expect(example.contains("<p class=\"lede\">The smallest program: a breathing circle. <code>draw()</code> runs"),
                "an example's first line lost its capital or its code type")
        #expect(!example.contains("class=\"pager\""), "an example's page gained cards nobody wrote a line for")

        // The artists: one row of the menu each, under the name the artist's
        // page is titled with, that page marked when it is the one open, and
        // a sketch's trail and menu naming the artist the same way.
        let artist = try String(contentsOf: output.appendingPathComponent("examples/recreations/vladimirbonacic/index.html"), encoding: .utf8)
        let artistRows = Self.labels(in: artist, group: "Recreations")
        let artistFolders = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Examples/Recreations").path)
            .filter { FileManager.default.fileExists(atPath: root.appendingPathComponent("Examples/Recreations/\($0)/README.md").path) }
        #expect(artistFolders.count > 30, "found \(artistFolders.count) artists")
        #expect(artistRows.count == artistFolders.count + 1, "the menu lists \(artistRows.count) rows for \(artistFolders.count) artists")
        #expect(artistRows.contains("Vladimir Bonačić") && !artistRows.contains { $0.contains(" / ") },
                "the menu lists sketches where it has an artist's page to list: \(artistRows.prefix(4))")
        #expect(artist.contains("aria-current=\"page\">Vladimir Bonačić</a>"), "the artist's own page is not marked in the menu")
        #expect(artist.contains("<nav class=\"trail\" aria-label=\"Breadcrumb\">") && artist.contains("→ Vladimir Bonačić</nav>"),
                "the artist's page ends its trail on something other than the name")
        let artistSketch = try String(contentsOf: output.appendingPathComponent("examples/recreations/vladimirbonacic/dynamicobject.html"), encoding: .utf8)
        #expect(artistSketch.contains("<a href=\"index.html\">Vladimir Bonačić</a> → DynamicObject</nav>"), "a sketch's trail spells the artist's folder, or does not end on the sketch")
        #expect(artistSketch.contains("aria-current=\"true\">Vladimir Bonačić</a>"), "a sketch marks nothing in the menu")
        // A sketch's follow-on paragraph and its command stay under its bullet.
        let bullet = try #require(artist.range(of: "<li><p><a href=\"dynamicobject.html\"><strong>DynamicObject</strong></a>"),
                                  "the artist's page does not open a bullet on its first sketch")
        let item = artist[bullet.upperBound...]
        let itemEnd = try #require(item.range(of: "</li>"))
        #expect(item[..<itemEnd.lowerBound].contains("<pre><code class=\"language-sh\"><span class=\"tk-keyword\">swift</span>"),
                "the command under a sketch's bullet left the bullet, or kept the indent that nests it")
        #expect(unmarked.isEmpty, "example pages that mark no row, or more than one, of their menu: \(unmarked.prefix(6)) (\(unmarked.count))")

        // The logo: the favicon is the small form on nothing in two inks,
        // Safari's pinned-tab icon the small form alone, every page's bar
        // wears the full mark in the page's own color, and the README's own
        // picture of the mark stays off the front page, whose bar has it.
        let favicon = try String(contentsOf: output.appendingPathComponent("favicon.svg"), encoding: .utf8)
        let faviconDark = try String(contentsOf: output.appendingPathComponent("favicon-dark.svg"), encoding: .utf8)
        let small = try String(contentsOf: root.appendingPathComponent(SiteLogo.small), encoding: .utf8)
        #expect(favicon == SiteLogo.colored(small, ink: SiteLogo.ink), "the favicon is not the small form in ink")
        #expect(faviconDark == SiteLogo.colored(small, ink: SiteLogo.paper), "the dark favicon is not the small form in paper")
        #expect(!favicon.contains("<rect") && !faviconDark.contains("<rect"),
                "a favicon carries a ground, which is what Safari draws a plate around")
        let pinned = try String(contentsOf: output.appendingPathComponent("mask-icon.svg"), encoding: .utf8)
        #expect(pinned == SiteLogo.colored(small, ink: SiteLogo.ink), "the pinned-tab icon is not the small form in ink")
        for (name, page) in [("the front page", home), ("a chapter", chapter), ("an example", example)] {
            #expect(page.contains("<svg class=\"mark\" aria-hidden=\"true\" focusable=\"false\" viewBox=\"0 0 100 100\""),
                    "\(name) does not wear the full mark in its bar")
            #expect(!page.contains("viewBox=\"0 0 14 14\""), "\(name) wears the small form somewhere")
            #expect(page.contains("<link rel=\"mask-icon\" href=") && page.contains("<link rel=\"apple-touch-icon\" href="),
                    "\(name) names no pinned-tab or touch icon")
            #expect(page.contains("prefers-color-scheme: dark)'),") && page.contains("favicon-dark.svg"),
                    "\(name) never swaps its favicon for a dark tab bar")
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
        for row in SiteHome.rows {
            // The band wears its own class and leads with the section's
            // heading, which is the program a stranger reads first.
            if case .carousel(let heading, _) = row {
                // The band's own heading covers every sketch in it, and the
                // README's heading names the one it came with, a level down
                // and keeping its anchor.
                #expect(home.contains("<section class=\"home-section home-band\">"), "the front page has no band")
                #expect(home.contains("<h3 id=\"\(HTML.slug(heading))\">"), "the band lost \(heading)")
                continue
            }
            for heading in row.headings {
                #expect(home.contains("<section class=\"home-section home-\(HTML.slug(heading))\">"),
                        "the front page has no block for \(heading)")
            }
        }
        // Every sketch in the band has a dot, and only the one on arrival
        // carries `autoplay`: the rest are not even fetched until somebody
        // pages to them, which is what keeps the page light.
        let slides = home.components(separatedBy: "<article class=\"band-slide\"").count - 1
        #expect(slides > 1, "the band is not a band")
        #expect(home.components(separatedBy: "<button class=\"band-dot\"").count - 1 == slides, "a sketch in the band has no dot")
        #expect(home.components(separatedBy: " autoplay ").count - 1 == 1, "more than one sketch plays on arrival")
        #expect(home.components(separatedBy: "preload=\"none\"").count - 1 == slides, "a clip in the band is fetched unasked")
        // The run command names the sketch on screen, so every slide carries
        // the target that runs it and the README's own command is marked
        // once, with the README's text untouched everywhere else.
        #expect(home.components(separatedBy: "<article class=\"band-slide\" data-target=\"").count - 1 == slides,
                "a sketch in the band cannot say how to run it")
        #expect(home.components(separatedBy: "<span data-run-target>").count - 1 == 1, "the run command is not marked once")
        #expect(!about.contains("data-run-target"), "the About page carries the front page's marking")
        #expect(home.contains("<div class=\"home-pair\">"))
        #expect(home.contains("<section class=\"home-section home-opening\">"))
        #expect(home.contains("<section class=\"home-section home-more\">"))
        #expect(!home.contains("class=\"badges\""), "the badge row reached the front page")
        #expect(!home.contains("id=\"live-reload\"") && !home.contains("id=\"built-with-ai\""), "a section left for the About page is on the front page")
        #expect(about.contains("id=\"live-reload\"") && about.contains("id=\"built-with-ai\"") && about.contains("id=\"hello-circle\""), "the About page is not the whole README")
        #expect(about.contains("class=\"badges\""), "the About page is the README as written")
        #expect(Self.words(of: Self.trail(of: about)) == "Ollin → About", "the About page's trail, which its place gives it since the README writes none")
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

        // The site carries an index for an agent, and it points at markdown.
        let llms = try String(contentsOf: output.appendingPathComponent("llms.txt"), encoding: .utf8)
        #expect(llms.hasPrefix("# Ollin"), "the convention wants a title first")
        #expect(llms.contains("\n> "), "and a blockquote saying what this is")
        // Every link has to reach markdown, or an agent following one falls
        // back into HTML halfway through.
        var llmsLinks = 0
        var llmsRest = Substring(llms)
        while let open = llmsRest.range(of: "](https://") {
            guard let close = llmsRest[open.upperBound...].firstIndex(of: ")") else { break }
            let url = String(llmsRest[open.upperBound ..< close])
            #expect(url.hasSuffix(".md"), "\(url) is not markdown")
            llmsLinks += 1
            llmsRest = llmsRest[close...]
        }
        #expect(llmsLinks > 100, "found only \(llmsLinks) links")

        // The page and its twin sit at the same address but for the suffix,
        // and the page says where its twin is.
        let colorPage = output.appendingPathComponent("docs/drawing/color.html")
        let colorTwin = output.appendingPathComponent("docs/drawing/color.md")
        #expect(FileManager.default.fileExists(atPath: colorTwin.path))
        let colorHTML = try String(contentsOf: colorPage, encoding: .utf8)
        #expect(colorHTML.contains("rel=\"alternate\" type=\"text/markdown\" href=\"color.md\""))
        #expect(colorHTML.contains("rel=\"describedby\""))
        let colorMarkdown = try String(contentsOf: colorTwin, encoding: .utf8)
        #expect(!colorMarkdown.contains("<html"), "the twin is markdown, not a page")
        #expect(colorMarkdown.contains(".md)"), "its own links reach markdown too")

        // The site lists every page for a crawler, at the addresses the pages claim.
        let base = "https://ollin.example/"
        let sitemap = try String(contentsOf: output.appendingPathComponent("sitemap.xml"), encoding: .utf8)
        #expect(sitemap.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"), "a sitemap opens with the declaration")
        #expect(sitemap.contains("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"))
        #expect(sitemap.hasSuffix("</urlset>\n"))

        var addresses: [String] = []
        var sitemapRest = Substring(sitemap)
        while let open = sitemapRest.range(of: "<loc>") {
            guard let close = sitemapRest[open.upperBound...].range(of: "</loc>") else { break }
            addresses.append(String(sitemapRest[open.upperBound ..< close.lowerBound]))
            sitemapRest = sitemapRest[close.upperBound...]
        }
        #expect(addresses.count == report.pages + report.examples,
                "listed \(addresses.count) of \(report.pages + report.examples) pages")
        #expect(Set(addresses).count == addresses.count, "a page is listed twice")
        // The twins are the same words at a second address, which is the one
        // thing a sitemap must not hand a crawler.
        #expect(!addresses.contains { $0.hasSuffix(".md") }, "a markdown twin is listed")
        for address in addresses {
            #expect(address.hasPrefix(base), "\(address) is not absolute under the site")
            #expect(address == base || address.hasSuffix(".html"), "\(address) is not a page")
        }
        #expect(addresses.contains(base), "the front page is missing, or listed as its file")
        #expect(!addresses.contains { $0.contains("404") } && !llms.contains("404") && !entries.contains { ($0["u"] ?? "").contains("404") },
                "the page for a wrong address is listed somewhere")

        // The whole point of the file is that a crawler and the page agree on
        // where the page lives, so one listed address is read back off the
        // page's own canonical link.
        let mark = "<link rel=\"canonical\" href=\""
        let start = try #require(colorHTML.range(of: mark))
        let end = try #require(colorHTML[start.upperBound...].firstIndex(of: "\""))
        let canonical = String(colorHTML[start.upperBound ..< end])
        #expect(addresses.contains(canonical), "\(canonical) is not in the sitemap")

        let robots = try String(contentsOf: output.appendingPathComponent("robots.txt"), encoding: .utf8)
        #expect(robots.contains("User-agent: *"))
        #expect(robots.contains("Sitemap: \(base)sitemap.xml"), "the file exists to name the sitemap")
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
            SiteSearch.Entry(kind: "examples", title: "DynamicObject", heading: "Recreations / Vladimir Bonačić",
                             url: "examples/recreations/vladimirbonacic/dynamicobject.html",
                             excerpt: "A square of lamps.", words: ["galois", "lamps"]),
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
            // Last, what the button is called and what it shows.
            blocks.push('name|' + toggle.getAttribute('aria-label') + '|' + toggle.querySelector('.key').textContent + '|' + innerWidth);
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
        // A window wide enough that the button shows its keys.
        let flags = HeadlessBrowser.baseFlags + ["--virtual-time-budget=20000", "--window-size=1280,800"]
        let queries = ["kuwahara", "effects", "kuwa", "colour", "kuwa colour", "nothinghere", "bonacic", "Bonačić"]
        let dom = try await HeadlessBrowser.dom(of: Self.searchProbe(queries: queries), flags: flags, timeout: 120)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        try #require(!report.hasPrefix("FAIL") && !report.hasPrefix("PENDING"), "\(report)")
        let blocks = report.components(separatedBy: "\n---\n").map { $0.split(separator: "\n").map(String.init) }
        try #require(blocks.count == queries.count + 1, "\(report)")

        // The button's spoken name holds the keys the button shows, after a
        // comma: a reader who says what is on the button reaches it, and a
        // checker of names sets aside whatever a name says in brackets.
        let name = (blocks.last?.first ?? "").split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        try #require(name.count == 4 && name[0] == "name" && (Int(name[3]) ?? 0) > 860, "the window is too narrow for the keys to show: \(report)")
        #expect(!name[2].isEmpty && name[1] == "Search, " + name[2], "the search button shows \(name[2]) and is called \(name[1])")

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

        // A name is found with its accents or without them, and marked where
        // it stands in the row either way.
        for typed in [6, 7] {
            #expect(blocks[typed].first == "1 match", "\(report)")
            let row = blocks[typed].dropFirst().first ?? ""
            #expect(row.hasPrefix("../examples/recreations/vladimirbonacic/dynamicobject.html|"), "\(report)")
            #expect(row.contains("Vladimir Bonačić") && row.split(separator: "|").dropFirst(2).first == "1",
                    "the name is not marked where it stands: \(report)")
        }
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
        // layout and gains one attribute, and nothing is put in front of the
        // drawing: a favicon that brought its own ground is what Safari draws
        // its contrast plate around.
        #expect(SiteLogo.colored(master, ink: "#F4F3F0") == """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14" fill="#F4F3F0">
          <path d="M1 1h3v3z"/>

          <circle cx="7" cy="7" r=".77"/>
        </svg>

        """)

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

    @Test("The checkout's llms.txt is what the reference writes, and every link in it is a file here")
    func checkoutIndex() throws {
        let root = try #require(Self.repositoryRoot())
        let plan = try #require(Self.checkoutPlan)
        // What `checkoutIndex()` writes, over the suite's one plan of the checkout.
        let written = SiteBuilder(root: root).llmsIndex(plan: plan, inCheckout: true)
        let committed = try String(contentsOf: root.appendingPathComponent("llms.txt"), encoding: .utf8)
        #expect(committed == written, "llms.txt is stale: run Scripts/llms.sh and commit it")
        #expect(written.hasPrefix("# Ollin"))
        #expect(written.contains("## Start here\n\n- [Ollin quick reference](Docs/QuickReference.md)"))
        #expect(written.contains("Scripts/ollin api <name>"))
        var links = 0
        var rest = Substring(written)
        while let open = rest.range(of: "]("), let close = rest[open.upperBound...].firstIndex(of: ")") {
            let path = String(rest[open.upperBound ..< close])
            #expect(!path.hasPrefix("http"), "\(path) is an address, not a path in the checkout")
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "\(path) is not in the checkout")
            links += 1
            rest = rest[close...]
        }
        #expect(links > 200, "found only \(links) links")
        #expect(!written.contains("\u{2014}"))
    }

    // MARK: - The example media

    /// The checkout's own sitemap and robots.txt are read in `realSite`, off the
    /// one build of the checkout every check there shares.
    @Test("A site that does not know its own address writes no sitemap and no robots.txt, and says so")
    func sitemapAndRobots() throws {
        // Without an address there is nothing absolute to write, and neither
        // file is written rather than written wrong. A checkout of one page is
        // enough to see it, and renders in no time.
        let bare = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-bare-\(UUID().uuidString)")
        let anonymous = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-sitemap-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: bare)
            try? FileManager.default.removeItem(at: anonymous)
        }
        // The four indexes a plan always names, and nothing else.
        for index in ["README.md", "Docs/README.md", "Guide/README.md", "Examples/README.md"] {
            let file = bare.appendingPathComponent(index)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "# Ollin\n\nA sketch.\n".write(to: file, atomically: true, encoding: .utf8)
        }
        var nowhere = SiteBuilder(root: bare)
        nowhere.repository = "https://example.com/ollin"
        #expect(nowhere.siteBase == nil, "a repository off GitHub with no domain has no address")
        let quiet = try nowhere.build(into: anonymous)
        #expect(!FileManager.default.fileExists(atPath: anonymous.appendingPathComponent("sitemap.xml").path))
        #expect(!FileManager.default.fileExists(atPath: anonymous.appendingPathComponent("robots.txt").path))
        #expect(!FileManager.default.fileExists(atPath: anonymous.appendingPathComponent("404.html").path),
                "a page whose paths start at the root was written without knowing the root")
        #expect(quiet.notes.contains { $0.contains("no sitemap") }, "and the build says so")
    }

    @Test("The manifest reads, and its absence is not a failure")
    func mediaManifest() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(ExampleMedia.read(inRepository: folder).entries.isEmpty,
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
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Media"),
                                                withIntermediateDirectories: true)
        try json.write(to: folder.appendingPathComponent("Media/media.json"), atomically: true, encoding: .utf8)
        let media = ExampleMedia.read(inRepository: folder)
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

    @Test("The categories are named in the order a reader meets them, row by row across the grid")
    func categoriesReadAcrossTheGrid() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-index-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        // Two rows of a grid three across, the second one short, over a
        // table that names the same folders in another order and says a
        // word about each, one of them with a link of its own.
        try """
        ## Examples

        | [![3D](https://media.example/a.jpg)](3D/) | [![Audio](https://media.example/b.jpg)](Audio/) | [![Basic](https://media.example/c.jpg)](Basic/) |
        |---|---|---|
        | [3D](3D/) | [Audio](Audio/) | [Basic](Basic/) |
        | [![Color](https://media.example/d.jpg)](Color/) | [![Data](https://media.example/e.jpg)](Data/) |  |
        | [Color](Color/) | [Data](Data/) |  |

        | Category | What it holds |
        |---|---|
        | [Data](Data/) | tables, and [a feed](Data/Feed/) |
        | [3D](3D/) | scenes with a camera |
        | [Audio](Audio/) | sound |
        | [Basic](Basic/) | the smallest |
        | [Color](Color/) | palettes |
        | [Late](Late/) | one the grid does not show yet |
        """.write(to: file, atomically: true, encoding: .utf8)

        let found = SiteBuilder.categories(readingIndexAt: file)
        #expect(found.map(\.name) == ["3D", "Audio", "Basic", "Color", "Data", "Late"],
                "a row's first cell alone reads down the first column: \(found.map(\.name))")
        #expect(!found.contains { $0.path.contains("Feed") }, "a link inside a cell of prose is not a category")
    }

    // MARK: - A group whose folders have pages of their own

    /// A checkout small enough to write in a test: one flat category, and one
    /// whose folders have pages of their own, each titled as a person is
    /// named rather than as the folder is spelled. One folder has no page.
    static func checkoutWithArtists() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-artists-\(UUID().uuidString)")
        func write(_ path: String, _ text: String) throws {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        for index in ["README.md", "Docs/README.md", "Guide/README.md"] {
            try write(index, "# Ollin\n\nA sketch.\n")
        }
        try write("Examples/README.md", """
        ## Examples

        | Category | What it holds |
        |---|---|
        | [Motion](Motion/) | animation |
        | [Recreations](Recreations/) | homages, by artist |
        """)
        try write("Examples/Motion/README.md", "#### <sup>[Examples](../README.md) → Motion</sup>\n\n---\n\n## Motion\n")
        try write("Examples/Motion/ArcModes/Sketch.swift", "import Ollin\n")
        try write("Examples/Recreations/README.md", "#### <sup>[Examples](../README.md) → Recreations</sup>\n\n---\n\n## Recreations\n")
        try write("Examples/Recreations/VladimirBonacic/README.md", """
        #### <sup>[Examples](../../README.md) → [Recreations](../README.md) → Vladimir Bonačić</sup>

        ---

        ## Vladimir Bonačić

        - [**DynamicObject**](DynamicObject/): after *GF.E 32-S*.

          The square of lamps.

          ```sh
          swift run Example-Recreations-VladimirBonacic-DynamicObject
          ```

        - [**GFE164**](GFE164/): after *GF.E (16,4)*.
        """)
        try write("Examples/Recreations/VladimirBonacic/DynamicObject/Sketch.swift", "import Ollin\n")
        try write("Examples/Recreations/VladimirBonacic/GFE164/Sketch.swift", "import Ollin\n")
        try write("Examples/Recreations/DoraMaurer/README.md", "## Dóra Maurer\n")
        try write("Examples/Recreations/DoraMaurer/Overlappings/Sketch.swift", "import Ollin\n")
        // Filed under M, named under E: the menu is in the order of what it shows.
        try write("Examples/Recreations/MacEntyreVidal/README.md", "## Eduardo Mac Entyre and Miguel Ángel Vidal\n")
        try write("Examples/Recreations/MacEntyreVidal/Generative/Sketch.swift", "import Ollin\n")
        try write("Examples/Recreations/ZdenekSykora/README.md", "## Zdeněk Sýkora\n")
        try write("Examples/Recreations/ZdenekSykora/Lines/Sketch.swift", "import Ollin\n")
        try write("Examples/Recreations/Studies/Grid/Sketch.swift", "import Ollin\n")
        return root
    }

    /// The labels under one group of a sidebar, in the order it lists them.
    static func labels(in sidebar: String, group: String) -> [String] {
        guard let open = sidebar.range(of: "<summary>\(group)</summary>"),
              let close = sidebar.range(of: "</details>", range: open.upperBound ..< sidebar.endIndex) else { return [] }
        var found: [String] = []
        var rest = sidebar[open.upperBound ..< close.lowerBound]
        while let link = rest.range(of: "<a "), let text = rest[link.upperBound...].firstIndex(of: ">"),
              let end = rest[text...].range(of: "</a>") {
            found.append(String(rest[rest.index(after: text) ..< end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return found
    }

    @Test("A group whose folders have pages of their own lists those pages by their titles, and marks the one you are in")
    func sidebarListsFoldersWithPages() throws {
        let root = try Self.checkoutWithArtists()
        defer { try? FileManager.default.removeItem(at: root) }
        let builder = SiteBuilder(root: root)
        let plan = builder.plan()
        let artist = try #require(plan.byRepoPath["Examples/Recreations/VladimirBonacic/README.md"])
        let sketch = try #require(plan.examples["Examples/Recreations/VladimirBonacic/DynamicObject"])
        let flat = try #require(plan.examples["Examples/Motion/ArcModes"])

        // One row for an artist, under the name the page is titled with, in
        // the order of the names shown; a folder with no page of its own
        // still lists its sketches, since nothing else leads to them.
        let onArtist = builder.sidebar(for: artist, plan: plan)
        #expect(Self.labels(in: onArtist, group: "Recreations")
                == ["All Recreations", "Dóra Maurer", "Eduardo Mac Entyre and Miguel Ángel Vidal",
                    "Vladimir Bonačić", "Zdeněk Sýkora", "Studies / Grid"],
                "actual: \(Self.labels(in: onArtist, group: "Recreations"))")
        #expect(onArtist.contains("<a href=\"index.html\" aria-current=\"page\">Vladimir Bonačić</a>"),
                "an artist's own page is not marked in the menu")
        #expect(!onArtist.contains("VladimirBonacic"), "the menu spells a folder")

        // On a sketch, the row that holds it is marked: the sketch itself is
        // listed on that page, not in the menu.
        let onSketch = builder.sidebar(for: sketch, plan: plan)
        #expect(onSketch.contains("<a href=\"index.html\" aria-current=\"true\">Vladimir Bonačić</a>"),
                "a sketch's page marks nothing in the menu")
        #expect(!onSketch.contains("aria-current=\"page\""))
        #expect(onSketch.contains("<details open><summary>Recreations</summary>"))

        // A category with no folders of its own lists its sketches as before.
        #expect(Self.labels(in: onArtist, group: "Motion") == ["All Motion", "ArcModes"])
        let onFlat = builder.sidebar(for: flat, plan: plan)
        #expect(onFlat.contains("<a href=\"arcmodes.html\" aria-current=\"page\">ArcModes</a>"))
        #expect(!onFlat.contains("aria-current=\"true\""))
    }

    @Test("A sketch's trail and its search entry name the folders above it as their own pages do")
    func trailNamesAreThePagesOwn() throws {
        let root = try Self.checkoutWithArtists()
        defer { try? FileManager.default.removeItem(at: root) }
        let builder = SiteBuilder(root: root)
        let plan = builder.plan()
        let log = SiteBuilder.LinkLog()

        let sketch = try #require(plan.examples["Examples/Recreations/VladimirBonacic/DynamicObject"])
        guard case .example(let entry) = sketch.kind else { Issue.record("not an example"); return }
        let html = builder.examplePage(entry, page: sketch, plan: plan, log: log)
        #expect(html.contains("<nav class=\"trail\" aria-label=\"Breadcrumb\"><a href=\"../../../index.html\">Ollin</a> → <a href=\"../../index.html\">Examples</a> → <a href=\"../index.html\">Recreations</a> → <a href=\"index.html\">Vladimir Bonačić</a> → DynamicObject</nav>"),
                "the trail spells the folder, or does not run from the front page to the sketch")
        #expect(log.search.last?.heading == "Recreations / Vladimir Bonačić", "actual: \(log.search.last?.heading ?? "")")

        // A folder with no page of its own has only its spelling to go by.
        let loose = try #require(plan.examples["Examples/Recreations/Studies/Grid"])
        guard case .example(let looseEntry) = loose.kind else { Issue.record("not an example"); return }
        let looseHTML = builder.examplePage(looseEntry, page: loose, plan: plan, log: log)
        #expect(looseHTML.contains("<a href=\"../index.html\">Recreations</a> → Studies → Grid</nav>"))
        #expect(log.search.last?.heading == "Recreations / Studies")

        // The artist's page keeps a sketch's follow-on lines under its bullet.
        let artist = try #require(plan.byRepoPath["Examples/Recreations/VladimirBonacic/README.md"])
        let markdown = try String(contentsOf: root.appendingPathComponent(artist.repoPath), encoding: .utf8)
        let page = builder.markdownPage(markdown, page: artist, plan: plan, log: log).replacingOccurrences(of: "\n", with: "")
        #expect(page.contains("<li><p><a href=\"dynamicobject.html\"><strong>DynamicObject</strong></a>: after <em>GF.E 32-S</em>.</p><p>The square of lamps.</p><pre>"),
                "the paragraph under a sketch's bullet left the bullet")
    }

    @Test("Every examples listing's trail ends on the page's own title")
    func listingTrailsNameThePage() throws {
        // The trail is written by hand at the top of each listing, and its last
        // step is the page itself, so it reads as the title does: an artist's
        // name with its accents, never the folder's spelling.
        let root = try #require(Self.repositoryRoot())
        let plan = try #require(Self.checkoutPlan)
        var checked = 0
        // The index above them all is the one exception: its trail ends on the
        // section, and its title says whose examples they are.
        for page in plan.pages where page.repoPath != "Examples/README.md" {
            guard case .examples = page.kind else { continue }
            var lines = try String(contentsOf: root.appendingPathComponent(page.repoPath), encoding: .utf8)
                .components(separatedBy: "\n")
            guard let trail = HTML.takeTrail(&lines) else { continue }
            let last = HTML.plainText(String(trail.components(separatedBy: "→").last ?? ""))
            #expect(last == page.title, "\(page.repoPath) ends its trail on \"\(last)\" under the title \"\(page.title)\"")
            checked += 1
        }
        #expect(checked > 60, "read \(checked) trails")
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
        let media = ExampleMedia.read(inRepository: root)
        #expect(media.heroes["guide"] != nil, "the guide lost its opening clip")
        #expect(media.heroes["readme"] != nil, "the README lost its opening clip")
    }

    @Test("The front page's band names sketches that are all still there")
    func showcaseIsWhole() throws {
        let root = try #require(Self.repositoryRoot())
        let media = ExampleMedia.read(inRepository: root)
        #expect(!media.showcase.isEmpty, "the front page lost its band of sketches")
        // The sketch the band leads with is named beside the section it leads,
        // and it plays there like any other.
        for case .carousel(_, let lead) in SiteHome.rows {
            let entry = media[lead]
            #expect(entry?.loopSmall != nil, "the band leads with \(lead), which has no clip to play")
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Examples/\(lead)/Sketch.swift").path),
                    "the band leads with \(lead), which is not in the checkout")
        }
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
        let media = ExampleMedia.read(inRepository: root)
        for example in media.entries.keys.sorted() {
            let sketch = root.appendingPathComponent("Examples/\(example)/Sketch.swift")
            #expect(FileManager.default.fileExists(atPath: sketch.path),
                    "Media/media.json names \(example), which is not in the checkout")
        }
    }

    // MARK: - The floor under every page

    /// Every `<img>` tag on a page, without its closing bracket.
    static func pictureTags(in html: String) -> [String] {
        var found: [String] = []
        var rest = Substring(html)
        while let open = rest.range(of: "<img ") {
            var quoted = false
            var end = open.upperBound
            while end < rest.endIndex, quoted || rest[end] != ">" {
                if rest[end] == "\"" { quoted.toggle() }
                end = rest.index(after: end)
            }
            found.append(String(rest[open.lowerBound ..< end]))
            rest = rest[end...]
        }
        return found
    }

    /// One attribute's value in a tag, or empty.
    static func value(of attribute: String, in tag: String) -> String {
        guard let open = tag.range(of: " \(attribute)=\""),
              let close = tag[open.upperBound...].firstIndex(of: "\"") else { return "" }
        return String(tag[open.upperBound ..< close])
    }

    /// A PNG of one flat color at a given size, for a test that reads a
    /// picture's size off its file.
    static func writePicture(width: Int, height: Int, to url: URL) throws {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    @Test("A picture's tag gains its own size, the height that goes with a written width, and every one after the first waits")
    func picturesSayTheirSize() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ollin-pictures-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writePicture(width: 300, height: 200, to: root.appendingPathComponent("Docs/Images/A.png"))
        try "not a picture".write(to: root.appendingPathComponent("Docs/Images/B.png"), atomically: true, encoding: .utf8)

        let builder = SiteBuilder(root: root)
        let page = SiteBuilder.Page(repoPath: "Docs/Topic.md", sitePath: "docs/topic.html", kind: .docs, title: "Topic", summary: "")
        var plan = SiteBuilder.Plan()
        plan.media = ExampleMedia(base: "https://media.example", entries: [
            "Group/Wide": .init(loop: nil, loopSmall: nil, still: "examples/Group/Wide/still.jpg?v=1",
                                stillSmall: "examples/Group/Wide/still-640.jpg?v=2", width: 1080, height: 608, sound: nil),
        ])
        let log = SiteBuilder.LinkLog()
        log.pictureSources = ["docs/images/a.png": "Docs/Images/A.png", "docs/images/b.png": "Docs/Images/B.png"]

        let body = """
        <p><img src="images/a.png" alt="first"></p>
        <img src="images/a.png" alt="a &gt; b, and a > c" width="150">
        <img src="https://media.example/examples/Group/Wide/still-640.jpg?v=2" alt="Wide">
        <img src="https://media.example/examples/Group/Wide/still.jpg?v=1" alt="Wide, whole">
        <img src="https://badges.example/x-y-blue" alt="badge">
        <img src="images/a.png" alt="closed" />
        <img src="images/a.png" alt="kept" width="90" height="10" loading="eager">
        <img src="images/b.png" alt="unreadable">
        <img src="images/missing.png" alt="nowhere">
        <p>after</p>
        """
        let out = builder.sizingPictures(in: body, page: page, plan: plan, log: log).components(separatedBy: "\n")
        try #require(out.count == 10, "\(out)")
        // The first is the one most likely to be showing when the page opens.
        #expect(out[0] == "<p><img src=\"images/a.png\" alt=\"first\" width=\"300\" height=\"200\"></p>")
        // A written width is kept, and a bracket inside the caption does not end the tag.
        #expect(out[1] == "<img src=\"images/a.png\" alt=\"a &gt; b, and a > c\" width=\"150\" height=\"100\" loading=\"lazy\" decoding=\"async\">")
        // On the media host a size comes from the manifest's row and the name.
        #expect(out[2].hasSuffix("alt=\"Wide\" width=\"640\" height=\"360\" loading=\"lazy\" decoding=\"async\">"), "\(out[2])")
        #expect(out[3].hasSuffix("alt=\"Wide, whole\" width=\"1080\" height=\"608\" loading=\"lazy\" decoding=\"async\">"), "\(out[3])")
        // Nothing knows a badge's size, so it gets none rather than a wrong one.
        #expect(out[4] == "<img src=\"https://badges.example/x-y-blue\" alt=\"badge\" loading=\"lazy\" decoding=\"async\">")
        #expect(out[5] == "<img src=\"images/a.png\" alt=\"closed\" width=\"300\" height=\"200\" loading=\"lazy\" decoding=\"async\" />")
        // What a page wrote out in full is left as written.
        #expect(out[6] == "<img src=\"images/a.png\" alt=\"kept\" width=\"90\" height=\"10\" loading=\"eager\">")
        // A file that is not a picture, and one that is not there, get no size.
        #expect(out[7] == "<img src=\"images/b.png\" alt=\"unreadable\" loading=\"lazy\" decoding=\"async\">")
        #expect(out[8] == "<img src=\"images/missing.png\" alt=\"nowhere\" loading=\"lazy\" decoding=\"async\">")
        #expect(out[9] == "<p>after</p>")
        #expect(builder.sizingPictures(in: "<p>no pictures</p>", page: page, plan: plan, log: log) == "<p>no pictures</p>")
    }

    @Test("A small copy's size follows the pipeline's rule, and a cover is a square")
    func mediaPictureSizes() throws {
        // Each pair was read off a real file on the media host on 2026-11-26:
        // the canvas a row records, and the size of its small still.
        let measured: [(canvas: (Int, Int), small: (Int, Int))] = [
            ((1080, 1080), (640, 640)), ((1080, 608), (640, 360)), ((1080, 1440), (480, 640)),
            ((940, 1080), (558, 640)), ((1000, 1400), (458, 640)), ((1296, 1080), (640, 534)),
            ((1400, 1000), (640, 458)), ((764, 1080), (452, 640)), ((760, 520), (640, 438)),
            ((920, 1200), (490, 640)), ((1620, 1080), (640, 426)), ((1080, 1472), (470, 640)),
            ((1919, 1003), (640, 334)), ((3200, 900), (640, 180)), ((1100, 1000), (640, 582)),
        ]
        for pair in measured {
            let size = ExampleMedia.smallSize(width: pair.canvas.0, height: pair.canvas.1)
            #expect(size == pair.small, "a \(pair.canvas) canvas: \(size), and the file is \(pair.small)")
        }
        var media = ExampleMedia(
            base: "https://media.example",
            entries: ["A/Tall": .init(loop: nil, loopSmall: nil, still: "examples/A/Tall/still.jpg?v=1",
                                      stillSmall: "examples/A/Tall/still-640.jpg?v=2", width: 1080, height: 1440, sound: nil)],
            heroes: ["guide": .init(image: "heroes/g.jpg?v=1", clip: "heroes/g.mp4?v=2", width: 1600, height: 800, of: "sketches")])
        media.groups = ["A": .init(image: "groups/A.jpg?v=3", imageSmall: "groups/A-640.jpg?v=4")]
        // With the version a page writes or without it.
        #expect(try #require(media.pictureSize(at: "examples/A/Tall/still-640.jpg?v=2")) == (480, 640))
        #expect(try #require(media.pictureSize(at: "examples/A/Tall/still.jpg")) == (1080, 1440))
        #expect(try #require(media.pictureSize(at: "groups/A-640.jpg?v=4")) == (640, 640))
        #expect(try #require(media.pictureSize(at: "groups/A.jpg?v=3")) == (1080, 1080))
        #expect(try #require(media.pictureSize(at: "heroes/g.jpg?v=1")) == (1600, 800))
        #expect(media.pictureSize(at: "examples/A/Other/still.jpg") == nil)
        // The checkout's own manifest names its covers, so a listing's grid is sized.
        let root = try #require(Self.repositoryRoot())
        #expect(ExampleMedia.read(inRepository: root).groups.count > 30, "the manifest's covers did not read")
    }

    @Test("The page for a wrong address is written from the site's root, wherever the root is")
    func wrongAddressFromTheRoot() throws {
        #expect(SiteBuilder.rootPath(of: "https://ollin.art/") == "/")
        #expect(SiteBuilder.rootPath(of: "https://someone.github.io/Thing/") == "/Thing/")
        #expect(SiteBuilder.rootPath(of: "https://someone.github.io/Thing") == "/Thing/")
        #expect(SiteBuilder.rootPath(of: "https://ollin.art") == "/")

        let root = try #require(Self.repositoryRoot())
        let plan = try #require(Self.checkoutPlan)
        let page = SiteBuilder(root: root).notFoundPage(plan: plan, root: "/Thing/")
        let local = Self.targets(in: page).filter { !$0.hasPrefix("#") && !$0.contains("://") }
        #expect(local.count > 8, "read \(local.count) paths")
        #expect(local.allSatisfy { $0.hasPrefix("/Thing/") }, "paths off the root: \(local.filter { !$0.hasPrefix("/Thing/") })")
        #expect(page.contains("data-root=\"/Thing/\""), "the search looks for its index somewhere else")
    }

    /// The color variables one scheme sets, by name, as `#rrggbb`. The dark
    /// scheme changes some and keeps the rest, so it is read over the light.
    static func palette(dark: Bool) throws -> [String: String] {
        let css = SiteStyle.css
        func block(after marker: String) throws -> Substring {
            let open = try #require(css.range(of: marker))
            let close = try #require(css[open.upperBound...].firstIndex(of: "}"))
            return css[open.upperBound ..< close]
        }
        func variables(_ block: Substring) -> [String: String] {
            var found: [String: String] = [:]
            for line in block.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0].hasPrefix("--") else { continue }
                let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "; "))
                if value.hasPrefix("#"), value.count == 7 { found[parts[0]] = value }
            }
            return found
        }
        var colors = variables(try block(after: ":root {"))
        if dark {
            let media = try #require(css.range(of: "@media (prefers-color-scheme: dark) {"))
            let open = try #require(css.range(of: ":root {", range: media.upperBound ..< css.endIndex))
            let close = try #require(css[open.upperBound...].firstIndex(of: "}"))
            colors.merge(variables(css[open.upperBound ..< close])) { _, new in new }
        }
        return colors
    }

    /// How far apart two colors read, by the accessibility guidelines' own
    /// arithmetic: 1 for the same color, 21 for black on white.
    static func contrast(_ first: String, _ second: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let value = Int(hex.dropFirst(), radix: 16) ?? 0
            let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { channel -> Double in
                let unit = Double(channel) / 255
                return unit <= 0.04045 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test("Every text color reads at 4.5 to 1 or better on each ground it is set on, in both schemes")
    func textContrast() throws {
        // Each ink with the grounds the stylesheet sets it on: prose and the
        // menus on the page, a card, and the darker chip inside a card or under
        // the pointer; a link on the page and on a card; the bar's open tab;
        // and every color of a code listing on the listing's own ground.
        let pairs: [(ink: String, grounds: [String])] = [
            ("--text", ["--bg", "--surface", "--surface-2", "--code-bg"]),
            ("--text-2", ["--bg", "--surface", "--surface-2"]),
            ("--muted", ["--bg", "--surface", "--surface-2"]),
            ("--accent", ["--bg", "--surface"]),
            ("--tab-ink", ["--tab"]),
            ("--tk-comment", ["--code-bg"]), ("--tk-string", ["--code-bg"]), ("--tk-number", ["--code-bg"]),
            ("--tk-keyword", ["--code-bg"]), ("--tk-type", ["--code-bg"]), ("--tk-attribute", ["--code-bg"]),
        ]
        for dark in [false, true] {
            let colors = try Self.palette(dark: dark)
            #expect(colors.count >= 15, "read \(colors.count) colors")
            for pair in pairs {
                let ink = try #require(colors[pair.ink], "\(pair.ink) is not a plain color")
                for name in pair.grounds {
                    let ground = try #require(colors[name], "\(name) is not a plain color")
                    let ratio = Self.contrast(ink, ground)
                    #expect(ratio >= 4.5, "\(dark ? "dark" : "light"): \(pair.ink) \(ink) on \(name) \(ground) reads at \(String(format: "%.2f", ratio)) to 1")
                }
            }
        }
        // The arithmetic itself, on the two ends of its scale.
        #expect(abs(Self.contrast("#000000", "#ffffff") - 21) < 0.001 && Self.contrast("#777777", "#777777") == 1)
        // The grounds a phone tints its bars with are the page's own.
        #expect(try Self.palette(dark: false)["--bg"] == SiteStyle.ground)
        #expect(try Self.palette(dark: true)["--bg"] == SiteStyle.groundDark)
    }

    /// A phone-wide column holding the shapes that run off a phone's screen
    /// when nothing lets them break, in the site's own stylesheet and as the
    /// site renders them,
    /// with the script that makes a scrolling block reachable. It reports
    /// each one's width against its box, how many lines a long call takes
    /// and how many of its labels were cut in two, and, in a column as wide
    /// as a desk's, how many lines a call takes that fits on one.
    static func narrowProbe() -> String {
        let ids = ["name", "heading", "address", "joined", "block", "short", "table"]
        func rendered(_ markdown: String) -> String { HTML.inline(markdown, resolve: { target, _ in target }) }
        let call = rendered("`drawSomethingWithAVeryLongName(aLabel:anotherLabel:andAThird:yetAnother:andTheLast:)`")
        let whole = rendered("`drawImage(_:topLeft:topRight:bottomRight:bottomLeft:)`")
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>\(SiteStyle.css)</style></head><body>
        <div id="column" style="width: 350px; flex: none;">
        <article class="prose">
        <p id="name">A call such as \(call) in a line.</p>
        <h2 id="heading">\(rendered("`ExampleMedia.pictureSizeOfSomethingVeryLongIndeed(at:scaledBy:)`"))</h2>
        <ul><li id="address">Upstream: https://example.com/a/very/long/address/with/no/space/in/it/anywhere/at/all/file.html</li></ul>
        <p id="joined" class="lede">The views (Front/Back/Left/Right/Top/Bottom/Isometric/Perspective/Orthographic) in one word.</p>
        <pre id="block"><code>let aLine = "of code that is far too long to fit a phone's column and has to scroll inside its own box"</code></pre>
        <pre id="short"><code>let x = 1</code></pre>
        <div class="table" id="table"><table><tr><td>\(rendered("`aVeryLongNameInATableCellThatStaysWhole(with:labels:andMore:)`"))</td><td>What it does, at some length, in words.</td></tr></table></div>
        </article>
        </div>
        <div style="width: 700px; flex: none;"><article class="prose">
        <p id="whole">A line of prose long enough that the call after it cannot share it: \(whole) follows.</p>
        </article></div>
        \(SiteStyle.scrollerScript)
        <div id="r0">PENDING</div>
        <script>
        (function () {
          var lines = \(ids).map(function (id) {
            var box = document.getElementById(id);
            return id + ' ' + box.scrollWidth + ' ' + box.clientWidth + ' ' + box.tabIndex;
          });
          lines.push('column ' + document.getElementById('column').scrollWidth + ' 350 -1');
          // The pieces of a call between its marks are its text nodes: one
          // that takes two lines was cut inside a label.
          var call = document.querySelector('#name code');
          var cut = 0;
          call.childNodes.forEach(function (node) {
            if (node.nodeType !== 3) return;
            var range = document.createRange();
            range.selectNodeContents(node);
            if (range.getClientRects().length > 1) cut += 1;
          });
          lines.push('fold ' + call.getClientRects().length + ' ' + cut + ' ' + call.querySelectorAll('wbr').length);
          lines.push('whole ' + document.querySelector('#whole code').getClientRects().length + ' ' + innerWidth + ' 0');
          document.getElementById('r0').textContent = lines.join('|');
        })();
        </script>
        </body></html>
        """
    }

    /// What the probe reported, by the name each line opens with.
    static func narrowReport(windowWidth: Int) async throws -> (read: [String: (Int, Int, Int)], text: String) {
        let flags = HeadlessBrowser.baseFlags + ["--window-size=\(windowWidth),900"]
        let dom = try await HeadlessBrowser.dom(of: Self.narrowProbe(), flags: flags, timeout: 90)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        try #require(report != "PENDING", "the probe did not run")
        var read: [String: (Int, Int, Int)] = [:]
        for line in report.split(separator: "|") {
            let parts = line.split(separator: " ")
            try #require(parts.count == 4, "\(report)")
            read[String(parts[0])] = (Int(parts[1]) ?? -1, Int(parts[2]) ?? -1, Int(parts[3]) ?? -9)
        }
        return (read, report)
    }

    @Test("At a phone's width a long name folds between its labels, nothing is wider than its column, and a block that scrolls can be reached from the keyboard",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled })
    func nothingRunsOffAPhone() async throws {
        let (read, report) = try await Self.narrowReport(windowWidth: 600)
        // A name in code type, a heading that is one, an address written
        // out, and names joined by slashes all break where the line ends.
        for id in ["name", "heading", "address", "joined", "column"] {
            let box = try #require(read[id], "\(report)")
            #expect(box.0 <= box.1, "\(id) is \(box.0) wide in a box of \(box.1): \(report)")
        }
        // The call takes more than one line, and every break in it falls
        // at one of its marks: no label is cut in two.
        let fold = try #require(read["fold"], "\(report)")
        #expect(fold.0 > 1 && fold.2 >= 5, "the call did not fold, or carries no marks: \(report)")
        #expect(fold.1 == 0, "\(fold.1) of the call's labels were cut in two: \(report)")
        // A listing and a table keep their lines whole and scroll inside
        // their own boxes, and a box that scrolls takes a place in the Tab
        // order; a listing that fits adds none.
        for id in ["block", "table"] {
            let box = try #require(read[id], "\(report)")
            #expect(box.0 > box.1, "\(id) no longer scrolls inside itself: \(report)")
            #expect(box.2 == 0, "\(id) scrolls and a keyboard cannot reach it: \(report)")
        }
        #expect(read["short"]?.2 == -1, "a listing that fits took a place in the Tab order: \(report)")
    }

    @Test("On a wide page a call that fits on one line moves to the next line whole",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled })
    func aNameStaysWholeOnAWidePage() async throws {
        let (read, report) = try await Self.narrowReport(windowWidth: 1280)
        let whole = try #require(read["whole"], "\(report)")
        try #require(whole.1 > 860, "the window is \(whole.1) wide, which is a phone's rules: \(report)")
        #expect(whole.0 == 1, "the call was folded across \(whole.0) lines on a wide page: \(report)")
        // The phone-wide column on the same page still holds its text.
        for id in ["name", "heading", "address", "joined", "column"] {
            let box = try #require(read[id], "\(report)")
            #expect(box.0 <= box.1, "\(id) is \(box.0) wide in a box of \(box.1): \(report)")
        }
    }

    // MARK: - The edge of a picture

    @Test("Every picture and clip has an edge: a picture carries the line, and a clip's is on its frame, exactly over the video",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled })
    func picturesAndClipsHaveAnEdge() async throws {
        // The site's own stylesheet over one of each thing that holds a
        // picture: a figure in prose, a plain picture, an example's clip, a
        // chapter's opening clip, a slide of the front page's band, a
        // thumbnail in a grid, and a badge, which is no picture of a sketch.
        let dot = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=="
        let page = """
        <!doctype html><html><head><meta charset="utf-8"><style>\(SiteStyle.css)</style></head><body>
        <main><article class="prose">
        <img id="plain" src="\(dot)" width="400" height="400">
        <picture><img id="figure" src="\(dot)" width="400" height="400"></picture>
        <figure class="example-clip" id="clip"><video width="1080" height="1080"></video></figure>
        <figure class="page-hero" id="hero"><video width="1080" height="1080"></video></figure>
        <div class="gallery"><figure><a href="#"><img src="\(dot)" width="640" height="640"></a><figcaption><a href="#">Name</a></figcaption></figure></div>
        <p class="badges"><img id="badge" src="\(dot)" width="80" height="20"></p>
        </article></main>
        <div class="band-slide"><figure id="band"><video width="1080" height="1080"></video></figure></div>
        <div id="r0">PENDING</div>
        <script>
        (function () {
          var report = [];
          ['plain', 'figure', 'badge'].forEach(function (id) {
            var style = getComputedStyle(document.getElementById(id));
            report.push(id + ' ' + style.outlineStyle + ' ' + style.outlineWidth + ' ' + style.outlineOffset);
          });
          // The thumbnail's link is found as the page has it, with no
          // name of its own: a link in prose that carries one is an
          // anchor, and the stylesheet lays those out another way.
          ['clip', 'hero', 'band', 'thumb'].forEach(function (id) {
            var frame = id === 'thumb' ? document.querySelector('.gallery figure > a') : document.getElementById(id), held = frame.querySelector('video, img');
            var line = getComputedStyle(frame, '::after'), f = frame.getBoundingClientRect(), h = held.getBoundingClientRect();
            var over = line.position === 'absolute' && line.top === '0px' && line.left === '0px' && line.right === '0px' && line.bottom === '0px'
              && line.pointerEvents === 'none' && getComputedStyle(frame).position === 'relative'
              // A frame that is laid out in a line gives the line over it
              // no box in every browser: one of them measures such a frame
              // by its lines of text, and a link around a picture has none.
              && getComputedStyle(frame).display !== 'inline';
            // The frame is the size of what it holds, and so is the line
            // itself: its own used size, which is what goes wrong when the
            // frame is not a box the line can be laid over.
            var fits = h.width > 100 && Math.abs(f.left - h.left) < 0.5 && Math.abs(f.top - h.top) < 0.5
              && Math.abs(f.width - h.width) < 0.5 && Math.abs(f.height - h.height) < 0.5
              && Math.abs(parseFloat(line.width) - h.width) < 0.5 && Math.abs(parseFloat(line.height) - h.height) < 0.5;
            report.push(id + ' ' + (line.boxShadow.indexOf('inset') >= 0 ? 1 : 0) + ' ' + (over ? 1 : 0) + ' ' + (fits ? 1 : 0)
              + ' ' + getComputedStyle(held).outlineStyle + ' ' + (line.borderTopLeftRadius === getComputedStyle(held).borderTopLeftRadius ? 1 : 0));
          });
          report.push('name ' + getComputedStyle(document.querySelector('.gallery figcaption a'), '::after').content);
          document.getElementById('r0').textContent = report.join('|');
        })();
        </script></body></html>
        """
        let dom = try await HeadlessBrowser.dom(of: page, flags: HeadlessBrowser.baseFlags + ["--window-size=1280,900"], timeout: 90)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        try #require(report != "PENDING", "the probe did not run")
        var read: [String: [String]] = [:]
        for line in report.split(separator: "|") {
            let parts = line.split(separator: " ").map(String.init)
            read[parts[0]] = Array(parts.dropFirst())
        }
        // A picture carries a hairline just inside its own frame, which
        // takes no room; a badge is not a picture of a sketch and has none.
        #expect(read["plain"] == ["solid", "1px", "-1px"] && read["figure"] == ["solid", "1px", "-1px"], "\(report)")
        #expect(read["badge"]?.first == "none", "a badge gained an edge: \(report)")
        // A clip's line is on the frame around it: drawn over the video,
        // covering exactly the video's box with its corners, out of the
        // pointer's way, and not set on the video, where a browser that
        // composites video would draw the video over it.
        for frame in ["clip", "hero", "band", "thumb"] {
            #expect(read[frame] == ["1", "1", "1", "none", "1"],
                    "\(frame): a line, laid over its frame, the frame the size of what it holds, nothing on the thing itself, the same corners: \(report)")
        }
        #expect(read["name"] == ["none"], "the name under a thumbnail gained a frame: \(report)")
    }

    // MARK: - The menus

    /// The anchors a block of a page links to, in order: the block that
    /// opens on `open` and runs to the next `close`.
    static func anchors(in html: String, from open: String, to close: String) -> [String] {
        guard let start = html.range(of: open),
              let end = html.range(of: close, range: start.upperBound ..< html.endIndex) else { return [] }
        return hrefs(in: String(html[start.upperBound ..< end.lowerBound])).filter { $0.hasPrefix("#") }
    }

    /// The level of every heading inside a page's `<main>`, in order, with
    /// the code listings left out (a sketch's source can hold anything).
    static func headingLevels(inMainOf html: String) -> [Int] {
        guard let open = html.range(of: "<main"), let close = html.range(of: "</main>", range: open.upperBound ..< html.endIndex) else { return [] }
        var levels: [Int] = []
        var rest = html[open.upperBound ..< close.lowerBound]
        while let tag = rest.range(of: "<") {
            let after = rest[tag.upperBound...]
            if after.hasPrefix("pre"), let end = after.range(of: "</pre>") {
                rest = after[end.upperBound...]
                continue
            }
            if after.first == "h", let digit = after.dropFirst().first, let level = digit.wholeNumberValue, (1 ... 6).contains(level),
               let next = after.dropFirst(2).first, next == " " || next == ">" {
                levels.append(level)
            }
            rest = after
        }
        return levels
    }

    /// A page's trail: what stands inside its breadcrumb, or nothing.
    static func trail(of html: String) -> String {
        guard let open = html.range(of: "<nav class=\"trail\" aria-label=\"Breadcrumb\">"),
              let close = html.range(of: "</nav>", range: open.upperBound ..< html.endIndex) else { return "" }
        return String(html[open.upperBound ..< close.lowerBound])
    }

    /// The names in the list of sections beside a page, in order.
    static func railLabels(of html: String) -> [String] {
        guard let open = html.range(of: "<nav class=\"rail\""),
              let close = html.range(of: "</nav>", range: open.upperBound ..< html.endIndex) else { return [] }
        return html[open.upperBound ..< close.lowerBound].components(separatedBy: "<li ").dropFirst().map { Self.words(of: "<li " + $0) }
    }

    /// A page's menu, from its opening tag to its close.
    static func menu(of html: String) -> String {
        guard let start = html.range(of: "<nav class=\"sidebar\""),
              let end = html.range(of: "</nav>", range: start.upperBound ..< html.endIndex) else { return "" }
        return String(html[start.lowerBound ..< end.upperBound])
    }

    /// What a reader reads of a run of markup: its tags taken out.
    static func words(of html: String) -> String {
        var out = ""
        var inTag = false
        for character in html {
            if character == "<" { inTag = true } else if character == ">" { inTag = false; out.append(" ") } else if !inTag { out.append(character) }
        }
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test("A chapter's last line becomes two cards in the line's own words, and any other ending is left alone")
    func chapterEndsOnItsCards() throws {
        let contents = "<a href=\"index.html#contents\">Contents</a>"
        let before = "Previous: <a href=\"18-a.html\">Chapter 18, Your first shader</a>"
        let after = "Next: <a href=\"20-b.html\">Chapter 20, <code>Pictures</code> restyled</a>"
        let page = "<p>Early.</p>\n<hr>\n<p>Text.</p>\n<hr>\n<p>\(contents) · \(before) · \(after)</p>\n"
        let paged = SiteBuilder.pager(in: page)
        #expect(paged.hasPrefix("<p>Early.</p>\n<hr>\n<p>Text.</p>\n<nav class=\"pager\" aria-label=\"Previous and next\">\n"),
                "the page above the line moved, or a rule further up was taken: \(paged)")
        #expect(paged.components(separatedBy: "<hr>").count == 2, "the line's own rule was kept beside the cards")
        #expect(paged.contains("<a class=\"pager-card pager-previous\" rel=\"prev\" href=\"18-a.html\"><span class=\"pager-way\">Previous</span><span class=\"pager-name\">Chapter 18, Your first shader</span></a>"))
        #expect(paged.contains("<a class=\"pager-card pager-next\" rel=\"next\" href=\"20-b.html\"><span class=\"pager-way\">Next</span><span class=\"pager-name\">Chapter 20, <code>Pictures</code> restyled</span></a>"))
        #expect(paged.contains("<a class=\"pager-up\" href=\"index.html#contents\">Contents</a>"))
        // Nothing is written that the line did not say: the cards' words,
        // in order, are the line's words without its marks.
        let line = Self.words(of: "\(contents) · \(before) · \(after)")
            .replacingOccurrences(of: " · ", with: " ").replacingOccurrences(of: ": ", with: " ")
        let opening = try #require(paged.range(of: "<nav class=\"pager\""), "the line was not made into cards: \(paged)")
        let cards = Self.words(of: String(paged[opening.lowerBound...]))
        #expect(Set(cards.split(separator: " ")) == Set(line.split(separator: " ")), "the cards read \(cards), the line \(line)")

        // The first chapter has nothing before it and the last nothing after.
        let first = SiteBuilder.pager(in: "<hr>\n<p>\(contents) · \(after)</p>")
        #expect(first.contains("pager-next") && !first.contains("pager-previous") && first.contains("pager-up"))
        let last = SiteBuilder.pager(in: "<hr>\n<p>\(contents) · \(before)</p>")
        #expect(last.contains("pager-previous") && !last.contains("pager-next"))

        // Left as they came: a page with no rule, a rule with more than one
        // paragraph after it, a closing line of prose, a line of links that
        // names no chapter, and a part that is more than its link.
        for other in ["<p>\(contents) · \(before)</p>",
                      "<hr>\n<p>\(contents) · \(before)</p>\n<p>And more.</p>",
                      "<hr>\n<p>If you get stuck, <a href=\"x\">open an issue</a>.</p>",
                      "<hr>\n<p>\(contents)</p>",
                      "<hr>\n<p>\(contents) · \(before), and <a href=\"y\">another</a></p>",
                      "<hr>\n<p>\(contents) · Previously: \(before.dropFirst(10))</p>"] {
            #expect(SiteBuilder.pager(in: other) == other, "rewritten: \(other)")
        }
    }

    @Test("A list of sections names a release by its name alone, and leaves out a level of names that repeat")
    func listsOfSections() {
        typealias Heading = (level: Int, text: String, anchor: String)
        // A changelog: every release holds the same few headings.
        let changelog: [Heading] = [(1, "Changelog", "changelog"), (2, "[Unreleased]", "unreleased"), (3, "Added", "added"), (3, "Fixed", "fixed"),
                                    (2, "[0.2.0] - 2026-01-02", "020---2026-01-02"), (3, "Added", "added-1"), (3, "Fixed", "fixed-1"), (3, "Removed", "removed")]
        let releases = SiteBuilder.listed(changelog, title: "Changelog")
        #expect(releases.map(\.text) == ["Unreleased", "0.2.0"], "actual: \(releases.map(\.text))")
        #expect(releases.map(\.anchor) == ["unreleased", "020---2026-01-02"], "a listed name still leads to its own heading")

        // A page whose sections each name their own parts keeps both levels,
        // and one name that happens to come twice among many is no habit.
        let page: [Heading] = [(1, "Sketch", "sketch"), (2, "Lifecycle", "lifecycle"), (3, "setup", "setup"), (3, "draw", "draw"), (3, "Notes", "notes"),
                               (2, "Canvas", "canvas"), (3, "width", "width"), (3, "height", "height"), (3, "Notes", "notes-1")]
        #expect(SiteBuilder.listed(page, title: "Sketch").map(\.level) == [2, 3, 3, 3, 2, 3, 3, 3])

        #expect(SiteBuilder.listedName("[0.18.0] - 2026-11-14") == "0.18.0" && SiteBuilder.listedName("[Unreleased]") == "Unreleased")
        // Brackets that are part of a sentence are left where they are.
        #expect(SiteBuilder.listedName("[x] and more words") == "[x] and more words")
        #expect(SiteBuilder.listedName("Plain") == "Plain" && SiteBuilder.listedName("[]") == "[]")
    }

    @Test("The list of a page's sections is one list in two places, and the fold goes right under the title")
    func sectionsFoldUnderTheTitle() throws {
        let root = try #require(Self.repositoryRoot())
        let builder = SiteBuilder(root: root)
        let headings: [(level: Int, text: String, anchor: String)] = [
            (2, "Title", "title"), (2, "First", "first"), (3, "Under & inside", "under-inside"),
            (4, "Too deep", "too-deep"), (2, "Second", "second"),
        ]
        let rows = "<li class=\"level-2\"><a href=\"#first\">First</a></li>\n"
            + "<li class=\"level-3\"><a href=\"#under-inside\">Under &amp; inside</a></li>\n"
            + "<li class=\"level-2\"><a href=\"#second\">Second</a></li>\n"
        #expect(builder.rail(headings, title: "Title")
                == "<nav class=\"rail\" aria-label=\"On this page\"><p class=\"rail-title\">On this page</p><ul>\n\(rows)</ul></nav>")
        #expect(builder.onPage(headings, title: "Title")
                == "<details class=\"onpage\"><summary>On this page</summary><ul>\n\(rows)</ul></details>")
        // A page with one section needs no map, beside it or under its title.
        #expect(builder.rail(Array(headings.prefix(2)), title: "Title").isEmpty)
        #expect(builder.onPage(Array(headings.prefix(2)), title: "Title").isEmpty)

        let body = "<article class=\"prose\">\n<h2 id=\"t\">Title</h2>\n<p>One.</p>\n<h3 id=\"a\">A</h3>\n</article>"
        #expect(SiteBuilder.inserting("<details>x</details>", afterTheFirstHeadingOf: body)
                == "<article class=\"prose\">\n<h2 id=\"t\">Title</h2>\n<details>x</details>\n<p>One.</p>\n<h3 id=\"a\">A</h3>\n</article>")
        // Whatever the first heading's level, and nothing for a page with none.
        #expect(SiteBuilder.inserting("F", afterTheFirstHeadingOf: "<p>x</p><h3>Late</h3><h1>Big</h1>") == "<p>x</p><h3>Late</h3>\nF<h1>Big</h1>")
        #expect(SiteBuilder.inserting("F", afterTheFirstHeadingOf: "<p>No heading.</p>") == "<p>No heading.</p>")
    }

    /// A page in the site's own stylesheet with the site's own scripts: a
    /// menu of ninety rows with the page open far down it, forty sections
    /// (most a screen tall, a few a line or two, the last three too short
    /// for the page to bring them up under the bar), the list of them beside
    /// the page and folded under the title, a bar with the section's tab,
    /// and a foot. The probe at its end walks the page and writes down what
    /// it finds.
    ///
    /// The probe is one synchronous pass, since the page is read once its
    /// scripts have run: it scrolls and then says so with a `scroll` event
    /// of its own, which is what the browser would send a frame later, and
    /// it makes the list's own scrolling land at once rather than glide.
    static func menusProbe() -> String {
        let menuRows = (1 ... 90).map { "<li><a href=\"#\"\($0 == 70 ? " aria-current=\"page\"" : "")>Row \($0)</a></li>" }.joined(separator: "\n")
        let heights = (0 ..< 40).map { $0 >= 37 ? 60 : ($0 % 7 == 3 ? 90 : 900) }
        let sections = heights.enumerated().map { "<h2 id=\"s\($0.offset)\">Section \($0.offset)</h2>\n<div style=\"height: \($0.element)px\"></div>" }.joined(separator: "\n")
        let rows = (0 ..< 40).map { "<li class=\"level-2\"><a href=\"#s\($0)\">Section \($0), under a name long enough to take two lines of the list</a></li>" }.joined(separator: "\n")
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        \(SiteStyle.scriptedMark)<style>\(SiteStyle.css)</style></head><body>
        <header class="bar"><div class="bar-inner">
        <a class="wordmark" href="#">Ollin</a>
        <nav class="sections"><a href="#" class="active has-menu" aria-current="true">Guide</a><button type="button" class="menu-toggle" aria-expanded="false" aria-controls="menu">Guide\(SiteStyle.disclosure)</button><a href="#">Reference</a></nav>
        <button class="search-toggle" type="button" hidden>Search</button>
        </div></header>
        <div class="layout with-sidebar with-rail">
        <nav class="sidebar" id="menu" aria-label="Section" tabindex="-1">
        <p class="sidebar-title">Guide</p><ul>
        \(menuRows)
        </ul>
        </nav>
        \(SiteStyle.menuPlaceScript)
        <script>
        // Read here, before the page under the menu exists and long before
        // the script that follows the reader runs: where the menu stands
        // now is where a reader first sees it.
        window.placed = (function () {
          var side = document.querySelector('.sidebar'), row = side.querySelector('[aria-current]');
          var b = side.getBoundingClientRect(), r = row.getBoundingClientRect();
          return ((r.top >= b.top && r.bottom <= b.bottom) ? 1 : 0) + ' ' + Math.round(side.scrollTop);
        })();
        </script>
        <main id="main" tabindex="-1"><article class="prose">
        <h1 id="t">Title</h1>
        <details class="onpage"><summary>On this page</summary><ul>
        \(rows)
        </ul></details>
        \(sections)
        </article></main>
        <nav class="rail" aria-label="On this page"><p class="rail-title">On this page</p><ul>
        \(rows)
        </ul></nav>
        </div>
        <footer class="foot"><div class="foot-inner"><p>The foot.</p></div></footer>
        <script>\(SiteStyle.menusScript)</script>
        <div id="r0">PENDING</div>
        <script>
        (function () {
          var report = [];
          var root = document.documentElement;
          var side = document.querySelector('.sidebar'), rail = document.querySelector('.rail'), fold = document.querySelector('.onpage');
          var toggle = document.querySelector('.menu-toggle'), main = document.querySelector('main');
          var bar = Math.round(document.querySelector('.bar').getBoundingClientRect().bottom);
          var links = [].slice.call(rail.querySelectorAll('a'));
          var page = side.querySelector('[aria-current]');
          function inside(box, row) { var b = box.getBoundingClientRect(), r = row.getBoundingClientRect(); return (r.top >= b.top - 0.5 && r.bottom <= b.bottom + 0.5) ? 1 : 0; }
          function shown(element) { return getComputedStyle(element).display === 'none' ? 0 : 1; }
          function marked() { var all = rail.querySelectorAll('[aria-current]'); return all.length === 1 ? links.indexOf(all[0]) : -1 - all.length; }
          function go(y) { window.scrollTo(0, y); window.dispatchEvent(new Event('scroll')); }
          root.style.scrollBehavior = 'auto';
          rail.scrollTo = function (to) { rail.scrollTop = to.top; };
          report.push('window ' + innerWidth + ' ' + innerHeight + ' ' + bar + ' ' + (matchMedia('(prefers-reduced-motion: reduce)').matches ? 1 : 0));
          report.push('placed ' + window.placed);
          report.push('shown ' + shown(rail) + ' ' + shown(fold) + ' ' + shown(toggle) + ' ' + shown(document.querySelector('.sections a.has-menu')));
          if (!matchMedia('(max-width: 860px)').matches) {
            // The menu opened on the page being read, and not at its top.
            report.push('menu ' + inside(side, page) + ' ' + Math.round(side.scrollTop));
            var most = root.scrollHeight - innerHeight;
            go(0);
            report.push('top ' + marked());
            // Each section that can be brought up under the bar is the one
            // marked when it is there, and its entry is in the list's window.
            var wrong = [], out = 0, tail = 0;
            links.forEach(function (link, n) {
              var heading = document.getElementById(link.hash.slice(1));
              var y = Math.round(heading.getBoundingClientRect().top + scrollY - 72);
              if (y > most) { tail += 1; return; }
              go(y);
              if (marked() !== n) wrong.push(n + ':' + marked()); else if (!inside(rail, link)) out += 1;
            });
            report.push('scrolled ' + wrong.length + ' ' + out + ' ' + tail + ' ' + (wrong.join(',') || '-'));
            // The page's end: the last section, its entry in view, and
            // neither list pushed up under the bar.
            go(most);
            report.push('end ' + marked() + ' ' + inside(rail, links[links.length - 1]) + ' '
              + Math.round(side.getBoundingClientRect().top) + ' ' + Math.round(rail.getBoundingClientRect().top) + ' '
              + Math.round(root.clientHeight - document.querySelector('.layout').getBoundingClientRect().bottom) + ' '
              + Math.round(root.clientHeight - rail.getBoundingClientRect().bottom));
            // Every one of the last sections has its turn on the way there.
            var seen = [];
            for (var y = Math.max(0, most - innerHeight); y <= most; y += 4) { go(y); if (seen[seen.length - 1] !== marked()) seen.push(marked()); }
            go(most);
            if (seen[seen.length - 1] !== marked()) seen.push(marked());
            report.push('turns ' + seen.slice(-4).join(' '));
            // A section asked for by name is the one marked, though the
            // page cannot bring it up under the bar.
            links[links.length - 2].click();
            window.dispatchEvent(new Event('scroll'));
            report.push('asked ' + marked() + ' ' + inside(rail, links[links.length - 2]));
          } else {
            // A phone: the menu is a sheet, out of the page until the tab
            // opens it on the page being read, and Escape hands it back.
            report.push('sheet ' + (getComputedStyle(side).position === 'fixed' ? 1 : 0) + ' ' + (getComputedStyle(side).visibility === 'hidden' ? 1 : 0)
              + ' ' + (root.scrollWidth <= innerWidth ? 1 : 0));
            toggle.focus();
            toggle.click();
            var box = side.getBoundingClientRect();
            report.push('open ' + (toggle.getAttribute('aria-expanded') === 'true' ? 1 : 0) + ' ' + (main.inert ? 1 : 0) + ' ' + inside(side, page)
              + ' ' + (getComputedStyle(side).visibility === 'visible' ? 1 : 0) + ' ' + (document.activeElement === side ? 1 : 0)
              + ' ' + Math.round(box.top - bar) + ' ' + Math.round(innerHeight - box.bottom));
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
            report.push('closed ' + (toggle.getAttribute('aria-expanded') === 'false' ? 1 : 0) + ' ' + (main.inert ? 0 : 1) + ' ' + (document.activeElement === toggle ? 1 : 0));
          }
          // A control that waits on its script. Read last, since it turns
          // the page's own mark off for a moment: out of sight either way,
          // its room held while a script is on its way, and no room at all
          // with none.
          var search = document.querySelector('.search-toggle'), style = getComputedStyle(search);
          var unseen = (style.display === 'none' || style.visibility === 'hidden') ? 1 : 0;
          var held = style.display !== 'none' ? 1 : 0;
          root.className = '';
          var gone = getComputedStyle(search).display === 'none' ? 1 : 0;
          root.className = 'js';
          report.push('waiting ' + unseen + ' ' + held + ' ' + gone);
          document.getElementById('r0').textContent = report.join('|');
        })();
        </script>
        </body></html>
        """
    }

    /// What the probe wrote down, by the word each line opens with.
    ///
    /// The browser is told which reader it is, one who asked the system for
    /// less motion or one who did not, and the probe says which it found.
    /// Left unsaid, the machine's own setting decides, so a desk with motion
    /// on and a build machine with it off each test half of the page and
    /// neither says so.
    static func menusReport(windowWidth: Int, reducedMotion: Bool) async throws -> (read: [String: [String]], text: String) {
        let motion = reducedMotion ? "--force-prefers-reduced-motion" : "--force-prefers-no-reduced-motion"
        let flags = HeadlessBrowser.baseFlags + ["--window-size=\(windowWidth),800", motion]
        let dom = try await HeadlessBrowser.dom(of: Self.menusProbe(), flags: flags, timeout: 90)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        try #require(report != "PENDING", "the probe did not run")
        var read: [String: [String]] = [:]
        for line in report.split(separator: "|") {
            let parts = line.split(separator: " ").map(String.init)
            read[parts[0]] = Array(parts.dropFirst())
        }
        let window = try #require(read["window"], "\(report)")
        try #require(window.count == 4 && window[3] == (reducedMotion ? "1" : "0"),
                     "the browser was asked for \(reducedMotion ? "less motion" : "motion") and the page read the other: \(report)")
        return (read, report)
    }

    /// A control that waits on its script (the search button) is out of
    /// sight until the script shows it. While a script is on its way its
    /// room is held, so the bar's tabs do not move when it appears; with no
    /// script it takes no room and nothing is left that does nothing.
    static func expectWaitingControl(_ read: [String: [String]], _ report: String) throws {
        let waiting = try #require(read["waiting"], "\(report)")
        #expect(waiting[0] == "1", "a control marked hidden is shown: \(report)")
        #expect(waiting[1] == "1", "a control that waits on its script holds no room, so what stands beside it moves when it arrives: \(report)")
        #expect(waiting[2] == "1", "with no script, a control marked hidden still takes its room or shows: \(report)")
    }

    @Test("The list beside a page marks the section being read, the menu opens on the page being read, and both stop at the foot",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled }, arguments: [false, true])
    func menusFollowTheReader(reducedMotion: Bool) async throws {
        let (read, report) = try await Self.menusReport(windowWidth: 1280, reducedMotion: reducedMotion)
        let window = try #require(read["window"], "\(report)")
        try #require((Int(window[0]) ?? 0) > 1100, "the window is \(window[0]) wide, too narrow for the list beside the page: \(report)")
        let bar = Int(window[2]) ?? -1
        try Self.expectWaitingControl(read, report)
        // On a wide screen the list is beside the page, and neither the
        // fold nor the tab's button is shown.
        #expect(read["shown"] == ["1", "0", "0", "1"], "\(report)")
        // The menu opened with the page being read in its window, which for
        // row seventy of ninety means it was moved, and it was there before
        // the page under it was drawn: the script right after the menu put
        // it there, not the one that loads later and would be seen moving it.
        let placed = try #require(read["placed"], "\(report)")
        #expect(placed[0] == "1" && (Int(placed[1]) ?? 0) > 0, "the menu was first drawn at its top with the open page out of sight: \(report)")
        let menu = try #require(read["menu"], "\(report)")
        #expect(menu[0] == "1" && menu[1] == placed[1], "the menu moved again after it was placed: \(report)")
        // At the page's top nothing is marked; every section that can be
        // brought up under the bar is the one marked when it is there, with
        // its entry inside the list's own window.
        #expect(read["top"] == ["-1"], "\(report)")
        let scrolled = try #require(read["scrolled"], "\(report)")
        #expect(scrolled[0] == "0", "sections marked wrongly when brought up under the bar (asked:marked): \(report)")
        #expect(scrolled[1] == "0", "\(scrolled[1]) marked entries were outside the list's window: \(report)")
        #expect((Int(scrolled[2]) ?? 0) >= 2, "the page has no section it cannot bring up under the bar, so the end is not being tested: \(report)")
        // At the end the last section is marked and in view, the lists
        // stand under the bar, and the list of sections stops at the foot.
        let end = try #require(read["end"], "\(report)")
        #expect(end[0] == "39" && end[1] == "1", "the page's end does not mark its last section, or its entry is out of the list's window: \(report)")
        #expect(Int(end[2]) == bar && Int(end[3]) == bar, "at the page's end a list is pushed up under the bar: \(report)")
        #expect((Int(end[4]) ?? 0) > 0 && end[4] == end[5], "the list of sections does not stop where the layout does: \(report)")
        // The sections too short to reach the bar are each marked in turn.
        #expect(read["turns"] == ["36", "37", "38", "39"], "\(report)")
        // A section asked for by name is the one marked.
        #expect(read["asked"] == ["38", "1"], "\(report)")
    }

    @Test("On a phone the section's tab opens the menu as a sheet on the page being read, and Escape hands the page back",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled }, arguments: [false, true])
    func aPhoneOpensTheMenuFromTheBar(reducedMotion: Bool) async throws {
        let (read, report) = try await Self.menusReport(windowWidth: 600, reducedMotion: reducedMotion)
        let window = try #require(read["window"], "\(report)")
        try #require((Int(window[0]) ?? 9_999) <= 860, "the window is \(window[0]) wide, which is not a phone's rules: \(report)")
        try Self.expectWaitingControl(read, report)
        // The list beside the page is gone and folded under the title; the
        // tab is a button, standing where the link stood.
        #expect(read["shown"] == ["0", "1", "1", "0"], "\(report)")
        // Out of the page and out of sight until asked for, and the page no
        // wider for it.
        #expect(read["sheet"] == ["1", "1", "1"], "\(report)")
        let open = try #require(read["open"], "\(report)")
        #expect(Array(open.prefix(5)) == ["1", "1", "1", "1", "1"],
                "open, the page behind out of reach, the open page's row in view, the sheet shown, the focus in it: \(report)")
        // As tall as the window under the bar. It slides the last few
        // pixels into place, so at the moment it opens it stands that much
        // above where it comes to rest, top and foot alike; for a reader
        // who asked for less motion it does not slide, and is there at once.
        let above = Int(open[5]) ?? 99
        #expect((reducedMotion ? 0 ... 0 : -12 ... 0).contains(above) && Int(open[6]) == -above,
                "the sheet does not run from the bar to the window's foot: \(report)")
        #expect(read["closed"] == ["1", "1", "1"], "Escape did not close the sheet, free the page, and hand the focus back: \(report)")
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
