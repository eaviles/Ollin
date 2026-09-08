import Foundation
import OllinProjects

/// The site: the repository's own writing, rendered as one set of web pages.
///
/// A lens on the markdown, not a second copy of it. The README is the front
/// page, the Guide and the reference are their own sections with the chapter
/// list and the index groups beside them, and the examples are a gallery
/// where every sketch has a page with its source. Nothing is rewritten on the
/// way: a page's prose reaches the site exactly as the file spells it, and
/// only the chrome around it is the site's own.
///
/// Paths mirror the repository, lower-cased, with `README.md` as each
/// folder's `index.html`, so every relative link a page already carries
/// resolves to the same neighbor it does on GitHub. A link to something the
/// site does not render (a source file, a folder of figures) points at the
/// file on GitHub instead, so no link a page makes goes dead.
public struct SiteBuilder {

    /// What one build produced, and what it could not place.
    public struct Report: Sendable {
        public var pages = 0
        public var examples = 0
        public var images = 0
        /// The sections the search lists: one per heading on every page,
        /// and one per example.
        public var sections = 0
        /// Links and pictures that resolved to nothing in the checkout, as
        /// `page: target`. The link checker gates these; the build reports
        /// them and goes on.
        public var missing: [String] = []
        /// What the build went without, and what would give it back.
        public var notes: [String] = []
    }

    public var root: URL
    public var repository: String
    public var branch: String
    /// The custom domain, when the site has one: writes the `CNAME` file and
    /// makes every page's canonical address absolute.
    public var domain: String?

    public init(root: URL,
                repository: String = "https://github.com/eaviles/Ollin",
                branch: String = "main",
                domain: String? = nil) {
        self.root = root
        self.repository = repository
        self.branch = branch
        self.domain = domain
    }

    // MARK: - The plan

    /// One page the site will write.
    struct Page {
        enum Kind {
            case home
            case about
            case guide
            case docs
            case examples
            case example(ExampleEntry)
        }

        /// Where the source sits in the repository: `Docs/Drawing/Color.md`,
        /// or the example's folder.
        let repoPath: String
        /// Where the page sits on the site: `docs/drawing/color.html`.
        let sitePath: String
        let kind: Kind
        var title: String
        /// The one line the index says about it, when it says one.
        var summary: String

        var siteDirectory: String {
            sitePath.split(separator: "/").dropLast().joined(separator: "/")
        }

        var section: Section {
            switch kind {
            case .home, .about: return .home
            case .guide: return .guide
            case .docs: return .docs
            case .examples, .example: return .examples
            }
        }
    }

    enum Section: String {
        case home, guide, docs, examples
    }

    struct Plan {
        var pages: [Page] = []
        /// Pages by repository path, for resolving links.
        var byRepoPath: [String: Page] = [:]
        /// Example pages by folder, for resolving a link at a sketch.
        var examples: [String: Page] = [:]
        var docsGroups: [(name: String, topics: [String])] = []
        var exampleCategories: [(name: String, path: String)] = []
        /// The small form of the logo for the bar, inlined in the page's ink.
        var mark = ""
        /// The full mark for the front page, inlined the same way.
        var logo = ""
    }

    /// The pages the site will hold, with their titles read ahead of time so
    /// every sidebar can name every neighbor.
    func plan() -> Plan {
        var plan = Plan()
        plan.mark = SiteLogo.inline(readingAt: root.appendingPathComponent(SiteLogo.small), className: "mark")
        plan.logo = SiteLogo.inline(readingAt: root.appendingPathComponent(SiteLogo.mark), className: "logo")

        func add(_ repoPath: String, _ kind: Page.Kind, title: String? = nil, summary: String = "") {
            let url = root.appendingPathComponent(repoPath)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let fallback = String(repoPath.split(separator: "/").last ?? "").replacingOccurrences(of: ".md", with: "")
            let page = Page(repoPath: repoPath,
                            sitePath: Self.sitePath(forRepoPath: repoPath),
                            kind: kind,
                            title: title ?? ReferenceLibrary.title(of: text) ?? fallback,
                            summary: summary)
            plan.pages.append(page)
            plan.byRepoPath[repoPath] = page
        }

        // The front page and the project pages beside it, in the order the
        // README's own navigation row names them.
        add("README.md", .home)
        for name in Self.aboutPages where exists(name) {
            add(name, .about)
        }

        // The Guide, in chapter order: the overview, the numbered chapters,
        // then the appendices. The authoring files beside them are for the
        // people writing it, not reading it.
        let guideFiles = markdownFiles(in: "Guide").filter { !["AUTHORING.md", "PLAN.md"].contains($0) }
        if guideFiles.contains("README.md") { add("Guide/README.md", .guide) }
        for file in guideFiles.sorted() where file != "README.md" {
            add("Guide/\(file)", .guide)
        }

        // The reference: every page, and the folder indexes.
        let docs = root.appendingPathComponent("Docs")
        let index = ReferenceLibrary.index(readingIndexAt: docs.appendingPathComponent("README.md"))
        add("Docs/README.md", .docs)
        for folder in subfolders(of: "Docs") where exists("Docs/\(folder)/README.md") {
            add("Docs/\(folder)/README.md", .docs)
        }
        for page in ReferenceLibrary.pages(inDocs: docs) {
            let listed = index[page.topic.lowercased()]
            add("Docs/\(page.topic).md", .docs, title: page.title, summary: listed?.summary ?? "")
        }
        plan.docsGroups = Self.docsGroups(readingIndexAt: docs.appendingPathComponent("README.md"))

        // The examples: the listing, each category's listing, and a page for
        // every sketch.
        let examples = root.appendingPathComponent("Examples")
        add("Examples/README.md", .examples)
        plan.exampleCategories = Self.categories(readingIndexAt: examples.appendingPathComponent("README.md"))
        for listing in readmeFiles(under: "Examples").sorted() where listing != "Examples/README.md" {
            add(listing, .examples)
        }
        for entry in ExampleCatalog.entries(inExamples: examples) {
            let repoPath = "Examples/\(entry.path)"
            let page = Page(repoPath: repoPath,
                            sitePath: Self.sitePath(forRepoPath: repoPath),
                            kind: .example(entry),
                            title: entry.name,
                            summary: entry.summary)
            plan.pages.append(page)
            plan.byRepoPath[repoPath] = page
            plan.examples[repoPath] = page
        }
        return plan
    }

    /// The project pages the front page links to, in the order it names them.
    static let aboutPages = [
        "CONTRIBUTING.md", "CHANGELOG.md", "ROADMAP.md", "ARCHITECTURE.md", "CAPABILITIES.md",
        "DESIGN-NOTES.md", "ATTRIBUTION.md", "THIRD-PARTY-NOTICES.md", "CODE_OF_CONDUCT.md", "SECURITY.md",
    ]

    /// Where a repository path lands on the site.
    static func sitePath(forRepoPath repoPath: String) -> String {
        var parts = repoPath.split(separator: "/").map { $0.lowercased() }
        guard let last = parts.last else { return "index.html" }
        if last == "readme.md" {
            parts[parts.count - 1] = "index.html"
        } else if last.hasSuffix(".md") {
            parts[parts.count - 1] = String(last.dropLast(3)) + ".html"
        } else {
            parts[parts.count - 1] = last + ".html"
        }
        return parts.joined(separator: "/")
    }

    /// The reference index's groups and the topics under each, in its order.
    static func docsGroups(readingIndexAt url: URL) -> [(name: String, topics: [String])] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var groups: [(name: String, topics: [String])] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                groups.append((Markdown.plain(String(line.dropFirst(4))).trimmingCharacters(in: .whitespaces), []))
                continue
            }
            guard line.hasPrefix("- ["), let link = ReferenceLibrary.firstLink(in: line),
                  link.target.hasSuffix(".md"), !groups.isEmpty else { continue }
            let topic = link.target.replacingOccurrences(of: "./", with: "").replacingOccurrences(of: ".md", with: "")
            guard !topic.hasPrefix("..") else { continue }
            groups[groups.count - 1].topics.append(topic)
        }
        return groups
    }

    /// The example categories, in the order the listing's table names them.
    static func categories(readingIndexAt url: URL) -> [(name: String, path: String)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var found: [(name: String, path: String)] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("| ["), let link = ReferenceLibrary.firstLink(in: line) else { continue }
            let name = Markdown.plain(String(line.dropFirst(3).prefix { $0 != "]" }))
            var path = link.target
            while path.hasSuffix("/") { path.removeLast() }
            found.append((name, path))
        }
        return found
    }

    // MARK: - Building

    public func build(into output: URL) throws -> Report {
        let manager = FileManager.default
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let plan = plan()
        let log = LinkLog()
        var report = Report()

        for page in plan.pages {
            let html: String
            switch page.kind {
            case .example(let entry):
                html = examplePage(entry, page: page, plan: plan, log: log)
                report.examples += 1
            default:
                let markdown = try String(contentsOf: root.appendingPathComponent(page.repoPath), encoding: .utf8)
                html = markdownPage(markdown, page: page, plan: plan, log: log)
                report.pages += 1
            }
            try write(html, to: output.appendingPathComponent(page.sitePath))
        }

        for (repoPath, sitePath) in log.images {
            let source = root.appendingPathComponent(repoPath)
            let destination = output.appendingPathComponent(sitePath)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.copyItem(at: source, to: destination)
            report.images += 1
        }

        // The search: every section the pages rendered, the words common to
        // more than a tenth of them dropped, as the script the page loads on
        // the first search, beside the script that runs it.
        let entries = SiteSearch.pruned(log.search)
        try write(try SiteSearch.script(entries), to: output.appendingPathComponent("assets/search-index.js"))
        try write(SiteStyle.searchScript, to: output.appendingPathComponent("assets/search.js"))
        report.sections = entries.count

        try write(SiteStyle.css, to: output.appendingPathComponent("assets/site.css"))
        // The favicon is the small form in paper on an ink tile: a tab bar
        // is whatever color the browser makes it, so the icon brings its own.
        if let small = SiteLogo.read(root.appendingPathComponent(SiteLogo.small)) {
            try write(SiteLogo.tiled(small, ink: SiteLogo.paper, tile: SiteLogo.ink), to: output.appendingPathComponent("favicon.svg"))
        } else {
            report.notes.append("the site has no favicon: \(SiteLogo.small) is not in the checkout")
        }
        if plan.mark.isEmpty {
            report.notes.append("the bar has no mark: \(SiteLogo.small) is not in the checkout")
        }
        if plan.logo.isEmpty {
            report.notes.append("the front page has no mark: \(SiteLogo.mark) is not in the checkout")
        }
        try write("", to: output.appendingPathComponent(".nojekyll"))
        if let domain { try write(domain + "\n", to: output.appendingPathComponent("CNAME")) }

        report.missing = log.missing.sorted()
        if SiteHero.fragment.isEmpty {
            report.notes.append("the front page opens without its ring: Sources/OllinReference/SiteHero.swift holds no recording; run Scripts/site-hero.sh on a Mac to record one")
        }
        return report
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// What the pages asked for as they rendered: the pictures to copy, the
    /// targets that pointed at nothing, and the sections the search lists.
    final class LinkLog {
        var images: [String: String] = [:]
        var missing: [String] = []
        var search: [SiteSearch.Entry] = []
    }

    // MARK: - A markdown page

    func markdownPage(_ markdown: String, page: Page, plan: Plan, log: LinkLog) -> String {
        var source = markdown
        var hero = ""
        if case .home = page.kind {
            hero = homeHero(&source, page: page, plan: plan)
        }
        let rendered = HTML.render(source) { target, image in
            resolve(target, image: image, from: page, plan: plan, log: log)
        }
        log.search.append(contentsOf: SiteSearch.entries(for: page, rendered: rendered))
        let body = hero.isEmpty
            ? "<article class=\"prose\">\n\(rendered.body)\n</article>"
            : "\(hero)\n<article class=\"prose home\">\n\(rendered.body)\n</article>"
        let title = page.title
        let description = page.summary.isEmpty ? Self.tagline : page.summary
        return layout(page: page, title: title, description: description, trail: rendered.trail,
                      body: body, headings: rendered.headings, plan: plan)
    }

    static let tagline = "A Metal-rendered creative-coding framework for Swift on Apple platforms."

    /// The front page's opening, lifted off the README and set as the hero:
    /// the mark the README opens with, the title, and the one bold line under
    /// it, beside the ring. The README's prose follows exactly as written;
    /// only these lines are placed differently. The mark is drawn from the
    /// logo's own file in the page's ink (`Plan.logo`) rather than copied as
    /// the README's picture, and it appears only when the README opens with
    /// one, so the front page shows what the README shows.
    ///
    /// The ring is `Examples/Web/BreathingRing` played by its own web page: the
    /// inline fragment the exporter wrote for it, verbatim, then the site's
    /// script setting the ring's ink and paper from the page's own colors.
    /// That script runs right after the fragment rather than from a deferred
    /// file, so the recorded white paper is never painted in the dark scheme.
    /// The wrapper is hidden from assistive technology, since the ring is
    /// decoration here and the README's own words follow.
    func homeHero(_ markdown: inout String, page: Page, plan: Plan) -> String {
        var lines = markdown.components(separatedBy: "\n")
        var tagline = Self.tagline
        var opensWithMark = false
        if let heading = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            // A picture before the title (the logo) is the hero's to place.
            let above = lines[..<heading].map { $0.trimmingCharacters(in: .whitespaces) }
            if above.contains(where: { $0.hasPrefix("<picture") || $0.hasPrefix("<img") }),
               above.allSatisfy({ $0.isEmpty || HTML.isRawBlock($0) }) {
                opensWithMark = true
                lines.removeSubrange(..<heading)
            }
        }
        if let heading = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            lines.remove(at: heading)
            if let bold = lines[heading...].firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
               lines[bold].hasPrefix("**"), lines[bold].hasSuffix("**") {
                tagline = Markdown.plain(lines[bold])
                lines.remove(at: bold)
            }
        }
        markdown = lines.joined(separator: "\n")

        let guide = relative(from: page.siteDirectory, to: "guide/index.html")
        let docs = relative(from: page.siteDirectory, to: "docs/index.html")
        let examples = relative(from: page.siteDirectory, to: "examples/index.html")
        let chapters = plan.pages.filter { $0.repoPath.hasPrefix("Guide/") && $0.repoPath.dropFirst(6).first?.isNumber == true }.count
        let references = plan.pages.filter { if case .docs = $0.kind { return !$0.repoPath.hasSuffix("README.md") }; return false }.count
        let sketches = plan.examples.count
        let ring = SiteHero.fragment.isEmpty ? "" : """
          <div class="hero-canvas" aria-hidden="true">
        \(SiteHero.fragment)
        <script>
        \(SiteStyle.heroScript)
        </script>
          </div>

        """

        let mark = opensWithMark && !plan.logo.isEmpty ? plan.logo + "\n" : ""
        return """
        <section class="hero">
          <div class="hero-text">
            \(mark)<p class="eyebrow">Ollin</p>
            <h1>\(HTML.escape(tagline))</h1>
            <p class="hero-actions"><a class="button" href="\(guide)">Start with the Guide</a><a class="button quiet" href="\(HTML.escape(repository))" rel="noopener">View on GitHub</a></p>
          </div>
        \(ring)</section>
        <section class="cards">
          <a class="card" href="\(guide)"><h2>Guide</h2><p>Creative coding from zero, taught through Ollin in \(chapters) chapters.</p></a>
          <a class="card" href="\(docs)"><h2>Reference</h2><p>\(references) pages, one for each type and helper, grouped the way you meet them.</p></a>
          <a class="card" href="\(examples)"><h2>Examples</h2><p>\(sketches) runnable sketches by category, each with its source.</p></a>
        </section>
        """
    }

    // MARK: - An example page

    func examplePage(_ entry: ExampleEntry, page: Page, plan: Plan, log: LinkLog) -> String {
        let source = (try? String(contentsOf: entry.sketch, encoding: .utf8)) ?? ""
        log.search.append(SiteSearch.entry(for: entry, page: page, source: source))
        let category = entry.group.split(separator: "/").map(String.init)

        // The trail walks the category folders, linking each level that has
        // a listing of its own.
        var trail = "<a href=\"\(relative(from: page.siteDirectory, to: "examples/index.html"))\">Examples</a>"
        var walked = "Examples"
        for level in category {
            walked += "/\(level)"
            if let listing = plan.byRepoPath["\(walked)/README.md"] {
                trail += " → <a href=\"\(relative(from: page.siteDirectory, to: listing.sitePath))\">\(HTML.escape(level))</a>"
            } else {
                trail += " → \(HTML.escape(level))"
            }
        }

        let run = "swift run --package-path Examples \(entry.target)"
        let github = "\(repository)/blob/\(branch)/Examples/\(entry.path)/Sketch.swift"
        var facts = "<dl class=\"facts\">\n"
        facts += "<dt>Run</dt><dd><code>\(HTML.escape(run))</code></dd>\n"
        if !entry.modules.isEmpty {
            facts += "<dt>Imports</dt><dd>\(entry.modules.map { "<code>\(HTML.escape($0))</code>" }.joined(separator: " "))</dd>\n"
        }
        if !entry.resources.isEmpty {
            facts += "<dt>Beside it</dt><dd>\(entry.resources.map { HTML.escape($0) }.joined(separator: ", "))</dd>\n"
        }
        facts += "<dt>Source</dt><dd><a href=\"\(HTML.escape(github))\" rel=\"noopener\">Examples/\(HTML.escape(entry.path))/Sketch.swift</a></dd>\n"
        facts += "</dl>"

        var body = "<article class=\"prose example\">\n"
        body += "<h1 id=\"\(HTML.slug(entry.name))\">\(HTML.escape(entry.name))</h1>\n"
        if !entry.summary.isEmpty {
            body += "<p class=\"lede\">\(HTML.escape(entry.summary))</p>\n"
        }
        body += facts + "\n"
        body += HTML.codeBlock(source, language: "swift") + "\n"
        body += "</article>"

        let description = entry.summary.isEmpty ? "An Ollin example sketch." : entry.summary
        return layout(page: page, title: entry.name, description: description, trail: trail,
                      body: body, headings: [], plan: plan)
    }

    // MARK: - Resolving what a page points at

    /// Where a target a page wrote goes on the site.
    ///
    /// Relative paths are read against the page's own folder in the
    /// repository, then placed: a rendered page becomes a relative link to
    /// it, a folder becomes its listing (or its example page), a picture is
    /// copied into place, and anything else that exists is handed to GitHub.
    /// A target that exists nowhere is left as written and reported.
    func resolve(_ target: String, image: Bool, from page: Page, plan: Plan, log: LinkLog) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return trimmed }
        if trimmed.contains("://") || trimmed.hasPrefix("mailto:") { return trimmed }

        let split = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(split[0])
        let anchor = split.count > 1 ? "#" + split[1] : ""
        let sourceDirectory = page.repoPath.split(separator: "/").dropLast().map(String.init)
        guard let repoPath = Self.joined(sourceDirectory, path) else {
            log.missing.append("\(page.repoPath): \(target)")
            return trimmed
        }

        if image {
            guard exists(repoPath) else {
                log.missing.append("\(page.repoPath): \(target)")
                return trimmed
            }
            let sitePath = repoPath.lowercased()
            log.images[repoPath] = sitePath
            return relative(from: page.siteDirectory, to: sitePath)
        }

        if let found = plan.byRepoPath[repoPath] {
            return relative(from: page.siteDirectory, to: found.sitePath) + anchor
        }
        if let listing = plan.byRepoPath[repoPath + "/README.md"] {
            return relative(from: page.siteDirectory, to: listing.sitePath) + anchor
        }
        if repoPath.hasSuffix("/Sketch.swift"),
           let example = plan.examples[String(repoPath.dropLast("/Sketch.swift".count))] {
            return relative(from: page.siteDirectory, to: example.sitePath) + anchor
        }
        if repoPath.isEmpty, let home = plan.byRepoPath["README.md"] {
            return relative(from: page.siteDirectory, to: home.sitePath) + anchor
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(repoPath).path, isDirectory: &isDirectory) {
            let kind = isDirectory.boolValue ? "tree" : "blob"
            return "\(repository)/\(kind)/\(branch)/\(repoPath)\(anchor)"
        }

        log.missing.append("\(page.repoPath): \(target)")
        return trimmed
    }

    /// A relative path joined onto a folder, with `.` and `..` walked, as
    /// repository-relative components. Nil when it climbs out of the tree.
    static func joined(_ directory: [String], _ path: String) -> String? {
        var parts = directory
        for piece in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch piece {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(String(piece))
            }
        }
        return parts.joined(separator: "/")
    }

    /// The relative path from one site folder to a site path.
    func relative(from directory: String, to sitePath: String) -> String {
        let from = directory.split(separator: "/").map(String.init)
        var to = sitePath.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count - 1, from[common] == to[common] { common += 1 }
        let ups = Array(repeating: "..", count: from.count - common)
        to.removeFirst(common)
        return (ups + to).joined(separator: "/")
    }

    // MARK: - The chrome

    func layout(page: Page, title: String, description: String, trail: String,
                body: String, headings: [(level: Int, text: String, anchor: String)], plan: Plan) -> String {
        let here = page.siteDirectory
        let asset = { (name: String) in relative(from: here, to: name) }
        let isHome: Bool
        if case .home = page.kind { isHome = true } else { isHome = false }
        let fullTitle = isHome ? "Ollin" : "\(title) · Ollin"
        let canonical = domain.map { "<link rel=\"canonical\" href=\"https://\($0)/\(page.sitePath == "index.html" ? "" : page.sitePath)\">" } ?? ""

        func navItem(_ label: String, _ section: Section, _ path: String) -> String {
            let active = page.section == section && !isHome ? " class=\"active\" aria-current=\"true\"" : ""
            return "<a href=\"\(asset(path))\"\(active)>\(label)</a>"
        }
        // The search opens from the bar and lives in a dialog at the end of
        // the page. Its button is hidden until the script that runs it has
        // loaded, so a reader with no script sees no control that does
        // nothing; the index is loaded on the first search, from the site's
        // root, which the dialog carries as the path back up to it.
        let siteRoot = String(asset("index.html").dropLast("index.html".count))
        let nav = """
        <header class="bar">
          <div class="bar-inner">
            <a class="wordmark" href="\(asset("index.html"))" aria-label="Ollin home">\(plan.mark)<span class="name">Ollin</span></a>
            <nav class="sections" aria-label="Sections">
              \(navItem("Guide", .guide, "guide/index.html"))
              \(navItem("Reference", .docs, "docs/index.html"))
              \(navItem("Examples", .examples, "examples/index.html"))
              <a href="\(HTML.escape(repository))" rel="noopener">GitHub</a>
            </nav>
            <button class="search-toggle" type="button" aria-label="Search" title="Search" hidden>\(SiteStyle.searchIcon)<span class="key" aria-hidden="true"></span></button>
          </div>
        </header>
        """
        let search = """
        <dialog id="search" class="search" data-root="\(siteRoot)" aria-label="Search">
          <div class="search-panel">
            <form class="search-box" role="search">\(SiteStyle.searchIcon)<input type="search" placeholder="Search the Guide, the reference, and the examples" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" aria-label="Search" aria-controls="search-results"><kbd>esc</kbd></form>
            <p class="search-status" aria-live="polite"></p>
            <ul class="search-results" id="search-results"></ul>
            <p class="search-hints"><kbd>↑</kbd><kbd>↓</kbd> move <kbd>↩</kbd> open</p>
          </div>
        </dialog>
        <script src="\(asset("assets/search.js"))" defer></script>
        """

        let sidebar = isHome ? "" : self.sidebar(for: page, plan: plan)
        let rail = isHome ? "" : self.rail(headings, title: title)
        let trailBlock = trail.isEmpty ? "" : "<nav class=\"trail\" aria-label=\"Breadcrumb\">\(trail)</nav>\n"
        let layoutClass = isHome ? "home" : (sidebar.isEmpty ? "single" : (rail.isEmpty ? "with-sidebar" : "with-sidebar with-rail"))

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(HTML.escape(fullTitle))</title>
        <meta name="description" content="\(HTML.escape(description))">
        <meta property="og:title" content="\(HTML.escape(fullTitle))">
        <meta property="og:description" content="\(HTML.escape(description))">
        <meta property="og:type" content="website">
        \(canonical)
        <link rel="icon" href="\(asset("favicon.svg"))" type="image/svg+xml">
        <link rel="stylesheet" href="\(asset("assets/site.css"))">
        </head>
        <body>
        \(nav)
        <div class="layout \(layoutClass)">
        \(sidebar)
        <main id="main">
        \(trailBlock)\(body)
        </main>
        \(rail)
        </div>
        \(search)
        <footer class="foot">
          <div class="foot-inner">
            <p>Ollin is MIT licensed and built in public. <a href="\(HTML.escape(repository))" rel="noopener">The repository</a> holds everything on this site.</p>
          </div>
        </footer>
        </body>
        </html>
        """
    }

    /// The section's own map, beside the page: the chapters, the reference
    /// groups, the example categories, or the project pages.
    func sidebar(for page: Page, plan: Plan) -> String {
        let here = page.siteDirectory
        func item(_ target: Page, label: String? = nil) -> String {
            let current = target.repoPath == page.repoPath ? " aria-current=\"page\"" : ""
            return "<li><a href=\"\(relative(from: here, to: target.sitePath))\"\(current)>\(HTML.escape(label ?? target.title))</a></li>"
        }
        func group(_ name: String, open: Bool, _ items: [String]) -> String {
            guard !items.isEmpty else { return "" }
            return "<details\(open ? " open" : "")><summary>\(HTML.escape(name))</summary><ul>\n\(items.joined(separator: "\n"))\n</ul></details>"
        }

        var out = "<nav class=\"sidebar\" aria-label=\"Section\">\n"
        switch page.section {
        case .home:
            var items: [String] = []
            for target in plan.pages {
                switch target.kind {
                case .home: items.append(item(target, label: "Overview"))
                case .about: items.append(item(target))
                default: break
                }
            }
            out += "<p class=\"sidebar-title\">Ollin</p><ul>\n\(items.joined(separator: "\n"))\n</ul>"

        case .guide:
            var overview: [String] = []
            var chapters: [String] = []
            var appendices: [String] = []
            for target in plan.pages {
                guard case .guide = target.kind else { continue }
                if target.repoPath == "Guide/README.md" {
                    overview.append(item(target, label: "Overview"))
                } else if target.repoPath.dropFirst("Guide/".count).first?.isNumber == true {
                    chapters.append(item(target))
                } else {
                    appendices.append(item(target))
                }
            }
            out += "<p class=\"sidebar-title\">The Guide</p><ul>\n\(overview.joined())\n</ul>"
            out += group("Chapters", open: true, chapters)
            out += group("Appendices", open: page.repoPath.dropFirst("Guide/".count).first?.isNumber != true, appendices)

        case .docs:
            if let index = plan.byRepoPath["Docs/README.md"] {
                out += "<p class=\"sidebar-title\">Reference</p><ul>\n\(item(index, label: "Overview"))\n</ul>"
            }
            for group in plan.docsGroups {
                let items = group.topics.compactMap { plan.byRepoPath["Docs/\($0).md"] }.map { item($0) }
                let holdsPage = group.topics.contains { "Docs/\($0).md" == page.repoPath }
                    || group.topics.contains { topic in
                        page.repoPath.hasSuffix("README.md") && "Docs/\(topic)".hasPrefix(page.repoPath.replacingOccurrences(of: "README.md", with: ""))
                    }
                out += self.group(group.name, open: holdsPage, items)
            }

        case .examples:
            if let index = plan.byRepoPath["Examples/README.md"] {
                out += "<p class=\"sidebar-title\">Examples</p><ul>\n\(item(index, label: "Overview"))\n</ul>"
            }
            for category in plan.exampleCategories {
                let categoryPath = "Examples/\(category.path)"
                let inside = page.repoPath.hasPrefix(categoryPath + "/") || page.repoPath == categoryPath + "/README.md"
                var items: [String] = []
                if let listing = plan.byRepoPath[categoryPath + "/README.md"] {
                    items.append(item(listing, label: "All \(category.name)"))
                }
                for target in plan.pages {
                    guard case .example(let entry) = target.kind, entry.path.hasPrefix(category.path + "/") else { continue }
                    let rest = entry.path.dropFirst(category.path.count + 1)
                    let subgroup = rest.split(separator: "/").dropLast().joined(separator: "/")
                    items.append(item(target, label: subgroup.isEmpty ? entry.name : "\(subgroup) / \(entry.name)"))
                }
                out += group(category.name, open: inside, items)
            }
        }
        out += "\n</nav>"
        return out
    }

    func group(_ name: String, open: Bool, _ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        return "<details\(open ? " open" : "")><summary>\(HTML.escape(name))</summary><ul>\n\(items.joined(separator: "\n"))\n</ul></details>"
    }

    /// The page's own headings, for a long page.
    func rail(_ headings: [(level: Int, text: String, anchor: String)], title: String) -> String {
        let listed = headings.filter { $0.level == 2 || $0.level == 3 }.filter { $0.text != title }
        guard listed.count >= 2 else { return "" }
        var out = "<nav class=\"rail\" aria-label=\"On this page\"><p class=\"rail-title\">On this page</p><ul>\n"
        for heading in listed {
            out += "<li class=\"level-\(heading.level)\"><a href=\"#\(heading.anchor)\">\(HTML.escape(heading.text))</a></li>\n"
        }
        out += "</ul></nav>"
        return out
    }

    // MARK: - The checkout

    func exists(_ repoPath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(repoPath).path)
    }

    func markdownFiles(in folder: String) -> [String] {
        let url = root.appendingPathComponent(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }
    }

    func subfolders(of folder: String) -> [String] {
        let url = root.appendingPathComponent(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue && !name.hasPrefix(".")
        }.sorted()
    }

    /// Every `README.md` under a folder, as repository paths.
    func readmeFiles(under folder: String) -> [String] {
        let url = root.appendingPathComponent(folder)
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        let rootParts = root.resolvingSymlinksInPath().standardized.pathComponents
        var found: [String] = []
        for case let file as URL in walker where file.lastPathComponent == "README.md" {
            let parts = file.resolvingSymlinksInPath().standardized.pathComponents
            guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else { continue }
            let repoPath = parts.dropFirst(rootParts.count).joined(separator: "/")
            guard !repoPath.contains("/.build/") else { continue }
            found.append(repoPath)
        }
        return found
    }
}
