import Foundation
import OllinProjects

/// The site: the repository's own writing, rendered as one set of web pages.
///
/// A lens on the markdown, not a second copy of it. The README opens the
/// front page (its opening and a few of its sections, laid out for a page)
/// and is the About page whole, the Guide and the reference are their own
/// sections with the chapter list and the index groups beside them, and the
/// examples are a gallery where every sketch has a page with its source.
/// Nothing is rewritten on the way: a page's prose reaches the site exactly
/// as the file spells it, and only the chrome around it is the site's own.
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
        /// The full mark for the bar, inlined in the page's ink.
        var mark = ""
        /// The README rendered whole, beside the front page that shows part
        /// of it; nil while the README is not in the checkout.
        var about: Page?
        /// Whether the checkout carries the two bitmaps `Scripts/logo.sh`
        /// writes: the social card and the touch icon.
        var hasSocialCard = false
        var hasTouchIcon = false
        /// The clips and stills the examples have, which is however many
        /// `Scripts/media.sh` has rendered so far.
        var media = ExampleMedia.none
    }

    /// The pages the site will hold, with their titles read ahead of time so
    /// every sidebar can name every neighbor.
    func plan() -> Plan {
        var plan = Plan()
        plan.mark = SiteLogo.inline(readingAt: root.appendingPathComponent(SiteLogo.mark), className: "mark")
        plan.hasSocialCard = exists(SiteLogo.socialCard)
        plan.hasTouchIcon = exists(SiteLogo.touchIcon)

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

        // The front page shows part of the README (`SiteHome`); the About
        // page is the same file whole, so every section the front page
        // leaves out is still one click away and every `README.md#anchor`
        // link in the tree has a page that carries the anchor. Then the
        // project pages, in the order the README's own navigation row names
        // them.
        add("README.md", .home)
        if exists("README.md") {
            let about = Page(repoPath: "README.md", sitePath: "about.html", kind: .about, title: "About", summary: "")
            plan.pages.append(about)
            plan.about = about
        }
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
        plan.media = ExampleMedia.read(inExamples: examples)
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

    /// The address GitHub Pages serves a repository's site at, from the
    /// repository's own address (`https://github.com/owner/name` becomes
    /// `https://owner.github.io/name/`), or nil for a repository hosted
    /// anywhere else.
    static func pagesAddress(of repository: String) -> String? {
        guard let url = URL(string: repository), url.host == "github.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2 else { return nil }
        let name = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        return "https://\(parts[0].lowercased()).github.io/\(name)/"
    }

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
        // A heading with no page under it (the catalog table at the top of
        // the index) is not a group.
        return groups.filter { !$0.topics.isEmpty }
    }

    /// The example categories, in the order the listing's table names them.
    static func categories(readingIndexAt url: URL) -> [(name: String, path: String)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var found: [(name: String, path: String)] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // A picture grid's rows start the same way, and their first link
            // is the still rather than the category, so they are stepped over.
            guard line.hasPrefix("| ["), !line.hasPrefix("| [!["),
                  let link = ReferenceLibrary.firstLink(in: line) else { continue }
            let name = Markdown.plain(String(line.dropFirst(3).prefix { $0 != "]" }))
            var path = link.target
            while path.hasSuffix("/") { path.removeLast() }
            // The grid's names sit under its pictures and link the same
            // folders, so a category reached twice is still one category.
            guard !found.contains(where: { $0.path == path }) else { continue }
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

        try write(llmsIndex(plan: plan), to: output.appendingPathComponent("llms.txt"))

        for page in plan.pages {
            let html: String
            // Every page is written twice: once rendered, once as the
            // markdown behind it, which is what an agent should be reading.
            let twin: String
            switch page.kind {
            case .example(let entry):
                html = examplePage(entry, page: page, plan: plan, log: log)
                twin = markdownTwin(of: entry)
                report.examples += 1
            default:
                let markdown = try String(contentsOf: root.appendingPathComponent(page.repoPath), encoding: .utf8)
                html = markdownPage(markdown, page: page, plan: plan, log: log)
                twin = markdownTwin(markdown, page: page, plan: plan, log: log)
                report.pages += 1
            }
            try write(html, to: output.appendingPathComponent(page.sitePath))
            try write(twin, to: output.appendingPathComponent(Self.markdownPath(for: page.sitePath)))
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
        // The favicon is the small form on nothing, written twice: Safari
        // draws a light plate behind an icon it reads as too close in tone to
        // the tab bar, which is what puts an icon on a dark tile inside a
        // white box there. No one ink clears that on both a white bar and a
        // near-black one, so the page picks the file on the reader's scheme.
        if let small = SiteLogo.read(root.appendingPathComponent(SiteLogo.small)) {
            try write(SiteLogo.colored(small, ink: SiteLogo.ink), to: output.appendingPathComponent("favicon.svg"))
            try write(SiteLogo.colored(small, ink: SiteLogo.paper), to: output.appendingPathComponent("favicon-dark.svg"))
        } else {
            report.notes.append("the site has no favicon: \(SiteLogo.small) is not in the checkout")
        }
        if plan.mark.isEmpty {
            report.notes.append("the bar has no mark: \(SiteLogo.mark) is not in the checkout")
        }
        // Safari's pinned-tab icon wants one color on nothing, which is what
        // a master already is; the social card and the touch icon are the
        // bitmaps Scripts/logo.sh writes beside the masters.
        if let small = SiteLogo.read(root.appendingPathComponent(SiteLogo.small)) {
            try write(SiteLogo.colored(small, ink: SiteLogo.ink), to: output.appendingPathComponent("mask-icon.svg"))
        }
        for (present, file, sitePath, what) in [(plan.hasSocialCard, SiteLogo.socialCard, "assets/social.png", "a link preview shows no card"),
                                                (plan.hasTouchIcon, SiteLogo.touchIcon, "apple-touch-icon.png", "a phone's home screen gets no icon")] {
            if present {
                let destination = output.appendingPathComponent(sitePath)
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                try manager.copyItem(at: root.appendingPathComponent(file), to: destination)
            } else {
                report.notes.append("\(what): \(file) is not in the checkout; run Scripts/logo.sh")
            }
        }
        report.notes.append(contentsOf: log.notes)
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
        /// What a page went without, for the report.
        var notes: [String] = []
    }

    // MARK: - A markdown page

    func markdownPage(_ markdown: String, page: Page, plan: Plan, log: LinkLog) -> String {
        if case .home = page.kind {
            return homePage(markdown, page: page, plan: plan, log: log)
        }
        let rendered = HTML.render(markdown) { target, image in
            resolve(target, image: image, from: page, plan: plan, log: log)
        }
        log.search.append(contentsOf: SiteSearch.entries(for: page, rendered: rendered))
        let body = "<article class=\"prose\">\n\(Self.playingHeroes(in: rendered.body, media: plan.media))\n</article>"
        let title = page.title
        let description = page.summary.isEmpty ? Self.tagline : page.summary
        return layout(page: page, title: title, description: description, trail: rendered.trail,
                      body: body, headings: rendered.headings, plan: plan)
    }

    static let tagline = "A Metal-rendered creative-coding framework for Swift on Apple platforms."

    // MARK: - The front page

    /// The front page: the hero and the cards, then the README's opening and
    /// the sections `SiteHome.rows` names, each in a block of its own so the
    /// stylesheet can lay it out for the width of a page (the code beside its
    /// paragraph, two short sections side by side, a list as a grid of cards),
    /// and a row of links to every section left for the About page. A link
    /// inside the shown text at a section that is not shown goes to the About
    /// page, where every anchor is. The search lists the front page once, by
    /// its opening; the README's sections are listed from the About page.
    func homePage(_ markdown: String, page: Page, plan: Plan, log: LinkLog) -> String {
        var (opening, sections) = SiteHome.split(markdown)
        let hero = homeHero(&opening, page: page, plan: plan)
        opening = SiteHome.trimmedOpening(opening)

        let shown = sections.filter { SiteHome.shown.contains($0.heading) }
        var anchors = SiteHome.anchors(in: opening)
        for section in shown { anchors.formUnion(SiteHome.anchors(in: section.markdown)) }
        let aboutPath = plan.about.map { relative(from: page.siteDirectory, to: $0.sitePath) }
        let resolveHome: HTML.Resolver = { target, image in
            let trimmed = Self.anchor(target.trimmingCharacters(in: .whitespaces))
            if trimmed.hasPrefix("#"), let aboutPath, !anchors.contains(String(trimmed.dropFirst())) {
                return aboutPath + trimmed
            }
            return resolve(target, image: image, from: page, plan: plan, log: log)
        }

        let openingRendered = HTML.render(opening, resolve: resolveHome)
        log.search.append(contentsOf: SiteSearch.entries(for: page, rendered: openingRendered))
        // The README's opening picture is dropped here rather than shown: the
        // front page already opens on the ring, and a second wall of sketches
        // under it is one hero too many. The picture stays in the README,
        // where it is the only one.
        var opened = Self.playingHeroes(in: openingRendered.body, media: plan.media)
        if let start = opened.range(of: "<figure class=\"page-hero\">"),
           let end = opened.range(of: "</figure>", range: start.upperBound ..< opened.endIndex) {
            opened.removeSubrange(start.lowerBound ..< end.upperBound)
        }
        var body = "<section class=\"home-section home-opening\">\n\(opened)\n</section>\n"

        func block(_ heading: String) -> String {
            guard let section = sections.first(where: { $0.heading == heading }) else {
                log.notes.append("the front page names a README section that is not there: \(heading)")
                return ""
            }
            let rendered = HTML.render(section.markdown, resolve: resolveHome)
            return "<section class=\"home-section home-\(section.anchor)\">\n\(rendered.body)\n</section>\n"
        }
        for row in SiteHome.rows {
            switch row {
            case .section(let heading):
                body += block(heading)
            case .pair(let left, let right):
                body += "<div class=\"home-pair\">\n\(block(left))\(block(right))</div>\n"
            }
        }

        let rest = sections.filter { !SiteHome.shown.contains($0.heading) }
        if let aboutPath, !rest.isEmpty {
            let links = rest.map { "<li><a href=\"\(aboutPath)#\($0.anchor)\">\(HTML.escape($0.heading))</a></li>" }
            body += "<section class=\"home-section home-more\">\n<h2>More about Ollin</h2>\n<ul>\n\(links.joined(separator: "\n"))\n</ul>\n</section>\n"
        }

        return layout(page: page, title: page.title, description: Self.tagline, trail: "",
                      body: "\(hero)\n\(showcase(plan.media, plan: plan, page: page))<article class=\"prose home\">\n\(body)</article>",
                      headings: [], plan: plan)
    }

    /// The front page's opening, lifted off the README and set as the hero:
    /// the title and the one bold line under it, beside the ring. The picture
    /// the README opens with (the mark) is taken off too, since the bar wears
    /// the mark on every page. What remains of the opening is handed back for
    /// the page to render as written.
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
        if let heading = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            // A picture before the title (the mark) is the bar's, not the page's.
            let above = lines[..<heading].map { $0.trimmingCharacters(in: .whitespaces) }
            if above.contains(where: { $0.hasPrefix("<picture") || $0.hasPrefix("<img") }),
               above.allSatisfy({ $0.isEmpty || HTML.isRawBlock($0) }) {
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

        return """
        <section class="hero">
          <div class="hero-text">
            <p class="eyebrow">Ollin</p>
            <h1>\(HTML.escape(tagline))</h1>
            <p class="hero-actions"><a class="button" href="#run-it">Run a sketch</a><a class="button quiet" href="\(guide)">Start with the Guide</a></p>
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
        if let media = plan.media[entry.path], media.loop != nil {
            body += Self.clip(media, in: plan.media, named: entry.name) + "\n"
        }
        body += facts + "\n"
        body += HTML.codeBlock(source, language: "swift") + "\n"
        body += "</article>"

        let description = entry.summary.isEmpty ? "An Ollin example sketch." : entry.summary
        return layout(page: page, title: entry.name, description: description, trail: trail,
                      body: body, headings: [], plan: plan)
    }

    /// One example's clip, with its own still as the poster.
    ///
    /// It plays on arrival because it is silent and short. `muted` and
    /// `playsinline` are what make that work on a phone: without the second,
    /// iOS Safari takes any playing video fullscreen. The poster is a real
    /// rendered frame, so a reader in low power mode, where nothing
    /// autoplays at all, still sees the sketch. The small script hands the
    /// controls back to anyone who has asked their system for less motion,
    /// which no stylesheet can do for a video.
    static func clip(_ entry: ExampleMedia.Entry, in media: ExampleMedia, named name: String) -> String {
        guard let loop = entry.loop else { return "" }
        // A sketch with its own music plays muted like the rest, since no
        // browser lets a page make noise unasked, and gains the controls that
        // let a reader turn it on.
        let controls = entry.sound == true ? " controls" : ""
        return """
        <figure class="example-clip">
        <video src="\(media.address(of: loop))" poster="\(media.address(of: entry.still))" \
        width="\(entry.width)" height="\(entry.height)" autoplay muted loop playsinline\(controls) \
        aria-label="\(HTML.escape(name)) running"></video>
        </figure>
        <script>if(matchMedia('(prefers-reduced-motion: reduce)').matches){\
        document.querySelectorAll('.example-clip video').forEach(v=>{\
        v.autoplay=false;v.controls=true;v.pause();});}</script>
        """
    }

    /// A page's opening picture, swapped for the clip it stands in for.
    ///
    /// The markdown carries the picture rather than the clip, because that is
    /// what GitHub and a plain clone can show and because a page should say
    /// something before a megabyte of video has arrived. On the site the
    /// picture becomes that clip playing, with itself as the poster, so a
    /// reader who blocks video or has asked for less motion sees exactly what
    /// the markdown promised.
    static func playingHeroes(in body: String, media: ExampleMedia) -> String {
        var out = body
        for hero in media.heroes.values {
            let picture = "\(media.base)/\(hero.image)"
            guard let start = out.range(of: "<img src=\"\(picture)\"") else { continue }
            guard let close = out[start.lowerBound...].range(of: ">") else { continue }
            let tag = String(out[start.lowerBound ..< close.upperBound])
            let alt = tag.range(of: "alt=\"").flatMap { from in
                tag[from.upperBound...].firstIndex(of: "\"").map { String(tag[from.upperBound ..< $0]) }
            } ?? hero.of
            let video = """
                <figure class="page-hero">
                <video src="\(media.base)/\(hero.clip)" poster="\(picture)" \
                width="\(hero.width)" height="\(hero.height)" autoplay muted loop playsinline \
                aria-label="\(HTML.escape(alt))"></video>
                </figure>
                """
            out.replaceSubrange(start.lowerBound ..< close.upperBound, with: video)
        }
        return out
    }

    /// The front page's band of sketches: each one running beside the whole
    /// program that draws it, which is the claim prose cannot make.
    ///
    /// The small clip rather than the full one, since three at canvas size
    /// would be nine megabytes on the page a stranger arrives at, and the
    /// cells are half that wide anyway. Nothing is fetched until it plays,
    /// and the band is hidden below the phone breakpoint, where the code
    /// beside the picture would stack into a wall: on a phone the sketch's
    /// own page is the place to read it.
    func showcase(_ media: ExampleMedia, plan: Plan, page: Page) -> String {
        var rows = ""
        for piece in media.showcase {
            guard let entry = media[piece.example], let clip = entry.loopSmall else { continue }
            let source = (try? String(contentsOf: root.appendingPathComponent("Examples/\(piece.example)/Sketch.swift"),
                                      encoding: .utf8)) ?? ""
            let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            let target = plan.examples["Examples/\(piece.example)"]
                .map { relative(from: page.siteDirectory, to: $0.sitePath) }
            let name = piece.example.split(separator: "/").last.map(String.init) ?? piece.example
            let link = target.map { " <a href=\"\($0)\">Run it</a>" } ?? ""
            rows += """
            <div class="showpiece">
            <figure><video src="\(media.address(of: clip))" poster="\(media.address(of: entry.stillSmall))" \
            width="\(entry.width)" height="\(entry.height)" autoplay muted loop playsinline preload="none" \
            aria-label="\(HTML.escape(name)) running"></video></figure>
            <div class="showpiece-code">\(HTML.codeBlock(code, language: "swift"))
            <p class="showpiece-note">\(HTML.escape(piece.note))\(link)</p>
            </div>
            </div>

            """
        }
        guard !rows.isEmpty else { return "" }
        let all = relative(from: page.siteDirectory, to: "examples/index.html")
        return """
        <section class="showcase" aria-label="What a sketch looks like">
        <div class="showcase-head"><h2>What a sketch looks like</h2>
        <p>Every one of these is the whole program.</p></div>
        \(rows)<p class="showcase-more"><a class="button quiet" href="\(all)">All \(plan.examples.count) examples</a></p>
        </section>

        """
    }

    // MARK: - The markdown a machine reads

    /// Where a page's markdown twin sits: the same address with `.md` in
    /// place of `.html`, which is one of the two spellings the convention
    /// allows and the one that keeps a folder's index readable as
    /// `index.md`.
    static func markdownPath(for sitePath: String) -> String {
        sitePath.hasSuffix(".html") ? String(sitePath.dropLast(5)) + ".md" : sitePath + ".md"
    }

    /// The same page as clean markdown, beside the rendered one.
    ///
    /// An agent fetching a documentation page gets navigation, styling and
    /// script wrapped around the few paragraphs it wanted, and turning that
    /// back into text is lossy. Here the source already *is* markdown, so the
    /// honest answer is to publish it: `docs/drawing/color.html` has
    /// `docs/drawing/color.md` beside it, holding what was actually written.
    ///
    /// Only the link targets change, rewritten through the same resolver the
    /// HTML uses and then pointed at the markdown twin, so a machine
    /// following them keeps getting markdown rather than falling back into
    /// HTML halfway through.
    func markdownTwin(_ markdown: String, page: Page, plan: Plan, log: LinkLog) -> String {
        var out = ""
        var rest = Substring(markdown)
        while let open = rest.firstIndex(of: "(") {
            // A link's target is what sits between "](" and the closing ")".
            guard open > rest.startIndex, rest[rest.index(before: open)] == "]",
                  let close = rest[open...].firstIndex(of: ")") else {
                out += rest[...open]
                rest = rest[rest.index(after: open)...]
                continue
            }
            let target = String(rest[rest.index(after: open) ..< close])
            let quiet = LinkLog()          // a twin reports nothing the page has not already
            var href = resolve(target, image: false, from: page, plan: plan, log: quiet)
            if href.hasSuffix(".html") { href = String(href.dropLast(5)) + ".md" }
            else if let hash = href.firstIndex(of: "#"), href[..<hash].hasSuffix(".html") {
                href = href[..<hash].dropLast(5) + ".md" + href[hash...]
            }
            out += rest[..<rest.index(after: open)] + href
            rest = rest[close...]
        }
        out += rest
        return out
    }

    /// An example as markdown: what it shows, how to run it, and its source.
    func markdownTwin(of entry: ExampleEntry) -> String {
        let source = (try? String(contentsOf: entry.sketch, encoding: .utf8)) ?? ""
        var out = "# \(entry.name)\n\n"
        if !entry.summary.isEmpty { out += "\(entry.summary)\n\n" }
        out += "Run it with `swift run --package-path Examples \(entry.target)`.\n\n"
        out += "```swift\n\(source.trimmingCharacters(in: .whitespacesAndNewlines))\n```\n"
        return out
    }

    /// The first sentence of a summary, ending at a full stop that is
    /// followed by a space and a capital, so `0...1.` and `p5.js` do not end
    /// one. The same rule the search excerpts use.
    static func firstSentence(of text: String) -> String? {
        let characters = Array(text)
        var index = 0
        while index + 2 < characters.count {
            if characters[index] == ".", characters[index + 1] == " ",
               characters[index + 2].isUppercase,
               index > 0, characters[index - 1].isLetter || characters[index - 1] == ")" {
                return String(characters[...index])
            }
            index += 1
        }
        return nil
    }

    /// The site's index for an agent: `/llms.txt`.
    ///
    /// A convention rather than a standard, proposed in 2024 and now served
    /// by enough documentation sites to be worth following. It is one
    /// markdown file: a title, a sentence of what this is, then lists of
    /// links. The links point at the **markdown** twins rather than the
    /// pages, so anything that follows them keeps reading markdown.
    ///
    /// It is a *curated* map, not a sitemap. Five hundred examples would
    /// bury the reference under a list nobody needs in context, so the
    /// examples are one link to their index and the detail lives behind it.
    func llmsIndex(plan: Plan) -> String {
        let base = domain.map { "https://\($0)/" } ?? Self.pagesAddress(of: repository) ?? ""
        // One sentence per page. The index's whole purpose is to be small
        // enough to hold in context while the detail waits behind the links,
        // and the reference's own summaries run to several sentences.
        func link(_ page: Page) -> String {
            let path = Self.markdownPath(for: page.sitePath)
            var summary = page.summary
            if let stop = Self.firstSentence(of: summary) { summary = stop }
            // A summary written as one long sentence still has to fit, so it
            // is cut at a word rather than mid-word and marked as cut.
            if summary.count > 180 {
                let cut = summary.prefix(180)
                let word = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
                summary = word.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")) + "…"
            }
            return "- [\(page.title)](\(base)\(path))" + (summary.isEmpty ? "" : ": \(summary)")
        }
        var out = """
        # Ollin

        > \(Self.tagline) Sketches are Swift classes with a `setup()` and a `draw()` that runs every frame; the renderer sits on Metal and composites in linear light.

        Every page on this site has a markdown twin at the same address with `.md` in place of `.html`, which is what these links point at. The reference is the authority on what exists and how it behaves; the guide teaches it in order; the examples are runnable sketches.

        """
        let chapters = plan.pages.filter { $0.repoPath.hasPrefix("Guide/") && $0.repoPath.dropFirst(6).first?.isNumber == true }
        if !chapters.isEmpty {
            out += "## Guide\n\n" + chapters.map(link).joined(separator: "\n") + "\n\n"
        }
        for group in plan.docsGroups {
            let pages = group.topics.compactMap { plan.byRepoPath["Docs/\($0).md"] }
            guard !pages.isEmpty else { continue }
            out += "## \(group.name)\n\n" + pages.map(link).joined(separator: "\n") + "\n\n"
        }
        var project: [String] = []
        if let examples = plan.byRepoPath["Examples/README.md"] {
            project.append("- [Examples](\(base)\(Self.markdownPath(for: examples.sitePath))): \(plan.examples.count) runnable sketches by category, each with its whole source")
        }
        for name in ["ARCHITECTURE.md", "CAPABILITIES.md", "CHANGELOG.md"] {
            if let page = plan.byRepoPath[name] { project.append(link(page)) }
        }
        if !project.isEmpty { out += "## The project\n\n" + project.joined(separator: "\n") + "\n\n" }
        var optional: [String] = []
        for name in ["ROADMAP.md", "DESIGN-NOTES.md", "ATTRIBUTION.md", "CONTRIBUTING.md"] {
            if let page = plan.byRepoPath[name] { optional.append(link(page)) }
        }
        if !optional.isEmpty { out += "## Optional\n\n" + optional.joined(separator: "\n") + "\n" }
        return out
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
        if trimmed.isEmpty { return trimmed }
        if trimmed.hasPrefix("#") { return Self.anchor(trimmed) }
        if trimmed.contains("://") || trimmed.hasPrefix("mailto:") { return trimmed }

        let split = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(split[0])
        let anchor = split.count > 1 ? Self.anchor("#" + split[1]) : ""
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

        // The front page shows part of the README, so a link at one of its
        // sections goes to the About page, which carries every anchor; a
        // link at the README itself goes to the front.
        if repoPath == "README.md" || repoPath.isEmpty, !anchor.isEmpty, let about = plan.about {
            return relative(from: page.siteDirectory, to: about.sitePath) + anchor
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

    /// An anchor as the site's ids spell it. A heading's id collapses the
    /// spaces around a dropped character to one dash (`status-contributing`),
    /// where GitHub keeps one dash per space (`status--contributing`); the
    /// pages link both ways, so a run of dashes in a link is read as one.
    static func anchor(_ anchor: String) -> String {
        var out = ""
        for character in anchor {
            if character == "-", out.hasSuffix("-") { continue }
            out.append(character)
        }
        return out
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
        let pagePath = page.sitePath == "index.html" ? "" : page.sitePath
        let canonical = domain.map { "<link rel=\"canonical\" href=\"https://\($0)/\(pagePath)\">" } ?? ""
        // The two relations the convention asks for, so a machine that lands
        // on the rendered page can find the markdown behind it and the index
        // that describes the site, without being told either address.
        let machine = """
        <link rel="alternate" type="text/markdown" href="\(asset(Self.markdownPath(for: page.sitePath)))">
        <link rel="describedby" type="text/markdown" href="\(asset("llms.txt"))">
        """
        // What a link to the page unfurls as, in a message or a feed: the
        // page's title and line, and the social card. A card has to be an
        // absolute address, so it is written against the custom domain or,
        // before there is one, the address GitHub Pages serves the repository
        // at, and left out when neither is known.
        var share = ""
        if let base = domain.map({ "https://\($0)/" }) ?? Self.pagesAddress(of: repository) {
            share += "<meta property=\"og:url\" content=\"\(HTML.escape(base + pagePath))\">\n"
            if plan.hasSocialCard {
                share += """
                <meta property="og:image" content="\(HTML.escape(base))assets/social.png">
                <meta property="og:image:width" content="1200">
                <meta property="og:image:height" content="630">
                <meta property="og:image:alt" content="The Ollin mark">
                <meta name="twitter:card" content="summary_large_image">

                """
            }
        }
        // Safari ignores a color-scheme media query written inside an SVG
        // favicon, so the page swaps the file instead of the drawing swapping
        // its own ink: the near-black mark on a light bar, the paper one on a
        // dark bar, and again whenever the reader changes scheme.
        var icons = "<link rel=\"icon\" href=\"\(asset("favicon.svg"))\" type=\"image/svg+xml\">\n"
        icons += """
        <script>(function(){var d=matchMedia('(prefers-color-scheme: dark)'),\
        l=document.querySelector('link[rel=icon]');if(!l)return;\
        var p=function(){l.href=d.matches?'\(asset("favicon-dark.svg"))':'\(asset("favicon.svg"))';};\
        d.addEventListener('change',p);p();})();</script>

        """
        icons += "<link rel=\"mask-icon\" href=\"\(asset("mask-icon.svg"))\" color=\"\(SiteLogo.ink)\">\n"
        if plan.hasTouchIcon {
            icons += "<link rel=\"apple-touch-icon\" href=\"\(asset("apple-touch-icon.png"))\">\n"
        }

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
        <meta property="og:site_name" content="Ollin">
        \(share)\(canonical)
        \(machine)
        \(icons)<link rel="stylesheet" href="\(asset("assets/site.css"))">
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
            // By site path, not source: the front page and the About page
            // are two pages of one file.
            let current = target.sitePath == page.sitePath ? " aria-current=\"page\"" : ""
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
                case .home: items.append(item(target, label: "Home"))
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
