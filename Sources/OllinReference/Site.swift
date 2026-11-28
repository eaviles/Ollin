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

    /// The absolute address the site is served at, ending in a slash: the
    /// custom domain when there is one, else the address GitHub Pages serves
    /// the repository at, and nil when neither is known.
    ///
    /// Three things need it and none of them may disagree with the others: a
    /// page's canonical link, the card a link unfurls as, and the sitemap.
    var siteBase: String? {
        domain.map { "https://\($0)/" } ?? Self.pagesAddress(of: repository)
    }

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
        /// The newest release the changelog has a section for, which the
        /// foot of every page names; nil while there is none to name.
        var release: (version: String, anchor: String)?
        /// The clips and stills the examples have, which is however many
        /// `Scripts/media.sh` has rendered so far.
        var media = ExampleMedia.none {
            didSet { pictureSizes = media.pictureSizes }
        }
        /// How big each picture on the media host is, by its path there,
        /// which is how a page gives a picture it cannot read its size.
        /// Kept beside the manifest it is read from, since a build asks it
        /// once for every picture.
        private(set) var pictureSizes: [String: (width: Int, height: Int)] = [:]
    }

    /// The pages the site will hold, with their titles read ahead of time so
    /// every sidebar can name every neighbor.
    func plan() -> Plan {
        var plan = Plan()
        plan.mark = SiteLogo.inline(readingAt: root.appendingPathComponent(SiteLogo.mark), className: "mark")
        plan.hasSocialCard = exists(SiteLogo.socialCard)
        plan.hasTouchIcon = exists(SiteLogo.touchIcon)
        if let changelog = try? String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8) {
            plan.release = Self.latestRelease(inChangelog: changelog)
        }

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
        plan.media = ExampleMedia.read(inRepository: examples.deletingLastPathComponent())
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

    /// What the site calls each project page in a menu and a trail.
    ///
    /// Each file's own title is written to stand alone at the top of the
    /// file ("Contributor Covenant Code of Conduct", "Ollin architecture &
    /// internals"), which is right there and too long for a row in a list
    /// of ten. The page keeps its title; the row and the trail take the
    /// short name. A page with no line here goes by its title.
    static let aboutLabels = [
        "CONTRIBUTING.md": "Contributing", "CHANGELOG.md": "Changelog", "ROADMAP.md": "Roadmap",
        "ARCHITECTURE.md": "Architecture", "CAPABILITIES.md": "Capabilities", "DESIGN-NOTES.md": "Design notes",
        "ATTRIBUTION.md": "Attribution", "THIRD-PARTY-NOTICES.md": "Third-party notices",
        "CODE_OF_CONDUCT.md": "Code of conduct", "SECURITY.md": "Security",
    ]

    /// The name a page goes by in a menu row and as a trail's last step.
    static func label(of page: Page) -> String {
        if case .about = page.kind, let short = aboutLabels[page.repoPath] { return short }
        return page.title
    }

    /// What each section is called, everywhere the site names it: the bar,
    /// the menu's heading, a trail, and the cards.
    static func name(of section: Section) -> String {
        switch section {
        case .home: return "Ollin"
        case .guide: return "Guide"
        case .docs: return "Reference"
        case .examples: return "Examples"
        }
    }

    /// The index each section opens on.
    static func index(of section: Section) -> String {
        switch section {
        case .home: return "index.html"
        case .guide: return "guide/index.html"
        case .docs: return "docs/index.html"
        case .examples: return "examples/index.html"
        }
    }

    /// The trail of a page whose file opens on none: the root, the section,
    /// and the page. Every page but the front one stands somewhere, and a
    /// trail says where from the root down.
    func trail(for page: Page) -> String {
        let home = "<a href=\"\(relative(from: page.siteDirectory, to: "index.html"))\">Ollin</a>"
        switch page.kind {
        case .home:
            return ""
        case .about:
            return "\(home) → \(HTML.escape(Self.label(of: page)))"
        case .guide, .docs, .examples, .example:
            let index = Self.index(of: page.section)
            guard page.sitePath != index else { return "\(home) → \(Self.name(of: page.section))" }
            return "\(home) → <a href=\"\(relative(from: page.siteDirectory, to: index))\">\(Self.name(of: page.section))</a> → \(HTML.escape(page.title))"
        }
    }

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

    /// The example categories, in the order the listing names them: as a
    /// reader meets them, row by row and left to right.
    ///
    /// A category is a table cell that holds one link and nothing else. The
    /// listing opens on a grid of pictures, four to a row, with the names
    /// on the row beneath; each of those names is such a cell, so the grid's
    /// reading order is the menu's. Taking only a row's first cell read the
    /// grid's first column and left the rest to be found further down, in
    /// another order.
    static func categories(readingIndexAt url: URL) -> [(name: String, path: String)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var found: [(name: String, path: String)] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { continue }
            for rawCell in line.split(separator: "|", omittingEmptySubsequences: false) {
                let cell = rawCell.trimmingCharacters(in: .whitespaces)
                // A picture's cell opens the same way, and its link is the
                // still rather than the category, so it is stepped over; so
                // is a cell of prose that happens to hold a link.
                guard cell.hasPrefix("["), !cell.hasPrefix("[!["), cell.hasSuffix(")"),
                      let link = ReferenceLibrary.firstLink(in: cell), link.end == cell.endIndex else { continue }
                let name = Markdown.plain(String(cell.dropFirst().prefix { $0 != "]" }))
                var path = link.target
                while path.hasSuffix("/") { path.removeLast() }
                // The grid's names and the table further down link the same
                // folders, so a category reached twice is still one category.
                guard !found.contains(where: { $0.path == path }) else { continue }
                found.append((name, path))
            }
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
        // A crawler wants the whole list and the file that names it, and both
        // have to carry absolute addresses, so neither is written until the
        // site knows the one it is served at.
        if let base = siteBase {
            try write(sitemap(plan: plan, base: base), to: output.appendingPathComponent("sitemap.xml"))
            try write(robots(base: base), to: output.appendingPathComponent("robots.txt"))
            // The page a wrong address gets. The host serves this one file
            // for every address with no page behind it, at whatever depth
            // that address has, so its paths are written from the site's root
            // and it too waits on the site knowing where it is served.
            try write(notFoundPage(plan: plan, root: Self.rootPath(of: base)),
                      to: output.appendingPathComponent("404.html"))
        } else {
            report.notes.append("no sitemap, no robots.txt, and no page for a wrong address: the site does not know its own address; pass --domain")
        }

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
        try write(SiteStyle.menusScript, to: output.appendingPathComponent("assets/menus.js"))
        try write(SiteStyle.pageScript, to: output.appendingPathComponent("assets/page.js"))
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
        /// The same pictures the other way round, by where the site put
        /// them, and the size each file turned out to be once one page has
        /// asked (zero for a file that is not a picture).
        var pictureSources: [String: String] = [:]
        var pictureSizes: [String: (width: Int, height: Int)] = [:]
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
        let rendered = HTML.render(markdown, asPage: true) { target, image in
            resolve(target, image: image, from: page, plan: plan, log: log)
        }
        log.search.append(contentsOf: SiteSearch.entries(for: page, rendered: rendered))
        // The clips are swapped in first, so a picture that became a clip's
        // poster is not counted as the page's first picture.
        var written = rendered.body
        if case .guide = page.kind { written = Self.pager(in: written) }
        var played = Self.playingHeroes(in: Self.playingChapterHook(in: written, page: page, media: plan.media),
                                        media: plan.media)
        if case .guide = page.kind { played = Self.framingOpeningPicture(in: played) }
        let body = "<article class=\"prose\">\n\(sizingPictures(in: played, page: page, plan: plan, log: log))\n</article>"
        let title = page.title
        let description = page.summary.isEmpty ? Self.tagline : page.summary
        // A link to a chapter unfurls as the picture the chapter opens on,
        // read before a clip takes that picture's place on the page.
        var card: ShareCard?
        if case .guide = page.kind {
            card = shareCard(fromTheFirstPictureIn: written, page: page, plan: plan, log: log)
        }
        return layout(page: page, title: title, description: description,
                      trail: rendered.trail.isEmpty ? trail(for: page) : rendered.trail,
                      body: body, headings: rendered.headings, plan: plan, card: card)
    }

    static let tagline = "A Metal-rendered creative-coding framework for Swift on Apple platforms."

    // MARK: - The front page

    /// The front page: the hero and the cards, then the README's opening and
    /// the sections `SiteHome.rows` names, each in a block of its own so the
    /// stylesheet can lay it out for the width of a page (the opening's facts
    /// beside its paragraphs, the code beside its paragraph, a section's text
    /// in two columns, its two parts side by side, a list as a grid of cards),
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
        var body = "<section class=\"home-section home-opening\">\n\(SiteHome.openingColumns(opened))\n</section>\n"

        // The README's run command names the sketch the band opens on, which
        // is what lets the band rewrite that one word as you page through it.
        // It is marked here rather than written: the README's own text stands
        // on the page, on the About page, and in the markdown twin, and only
        // this copy is told which word is the target.
        let led = SiteHome.rows.compactMap { row -> String? in
            if case .carousel(_, let example) = row { return example } else { return nil }
        }.first
        var runTarget: String? = led.flatMap {
            if case .example(let entry)? = plan.examples["Examples/\($0)"]?.kind { return entry.target }
            return nil
        }

        func block(_ heading: String, as row: SiteHome.Row) -> String {
            guard let section = sections.first(where: { $0.heading == heading }) else {
                log.notes.append("the front page names a README section that is not there: \(heading)")
                return ""
            }
            let rendered = HTML.render(section.markdown, resolve: resolveHome)
            var html = rendered.body
            if let target = runTarget, let found = html.range(of: target) {
                html.replaceSubrange(found, with: "<span data-run-target>\(target)</span>")
                runTarget = nil
            }
            if case .split = row { html = SiteHome.parted(html) }
            return "<section class=\"home-section home-\(section.anchor)\(row.layoutClass)\">\n\(html)\n</section>\n"
        }
        for row in SiteHome.rows {
            switch row {
            case .section(let heading), .flowing(let heading), .split(let heading):
                body += block(heading, as: row)
            case .carousel(let heading, let example):
                guard let section = sections.first(where: { $0.heading == heading }) else {
                    log.notes.append("the front page names a README section that is not there: \(heading)")
                    continue
                }
                body += band(lead: section, running: example, resolve: resolveHome, plan: plan, page: page)
            }
        }

        let rest = sections.filter { !SiteHome.shown.contains($0.heading) }
        if let aboutPath, !rest.isEmpty {
            let links = rest.map { "<li><a href=\"\(aboutPath)#\($0.anchor)\">\(HTML.escape($0.heading))</a></li>" }
            body += "<section class=\"home-section home-more\">\n<h2>More about Ollin</h2>\n<ul>\n\(links.joined(separator: "\n"))\n</ul>\n</section>\n"
        }

        return layout(page: page, title: page.title, description: Self.tagline, trail: "",
                      body: "\(hero)\n<article class=\"prose home\">\n\(sizingPictures(in: body, page: page, plan: plan, log: log))</article>",
                      headings: [], plan: plan)
    }

    /// The front page's opening, lifted off the README and set as the hero:
    /// the title and the one bold line under it, beside the ring. The picture
    /// the README opens with (the mark) is taken off too, since the bar shows
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
        \(sectionCards(plan: plan) { relative(from: page.siteDirectory, to: $0) })
        """
    }

    /// The three sections as cards, each with the one line that counts what
    /// it holds. The front page shows them under its opening and the page for
    /// a wrong address shows them as the ways back in; `address` turns a site
    /// path into the link the page showing them needs.
    func sectionCards(plan: Plan, address: (String) -> String) -> String {
        let chapters = plan.pages.filter { $0.repoPath.hasPrefix("Guide/") && $0.repoPath.dropFirst(6).first?.isNumber == true }.count
        let references = plan.pages.filter { if case .docs = $0.kind { return !$0.repoPath.hasSuffix("README.md") }; return false }.count
        let sketches = plan.examples.count
        return """
        <section class="cards">
          <a class="card" href="\(address(Self.index(of: .guide)))"><h2>\(Self.name(of: .guide))</h2><p>Creative coding from zero, taught through Ollin in \(chapters) chapters.</p></a>
          <a class="card" href="\(address(Self.index(of: .docs)))"><h2>\(Self.name(of: .docs))</h2><p>\(references) pages, one for each type and helper, grouped the way you meet them.</p></a>
          <a class="card" href="\(address(Self.index(of: .examples)))"><h2>\(Self.name(of: .examples))</h2><p>\(sketches) runnable sketches by category, each with its source.</p></a>
        </section>
        """
    }

    // MARK: - The page for a wrong address

    /// What the page for a wrong address says: its heading and the line
    /// under it. The site writes almost no prose of its own, so these two
    /// are kept here where they are easy to find and change.
    static let notFoundTitle = "Page not found"
    static let notFoundLine = "Nothing lives at this address. Search the site, or start from the Guide, the Reference, or the Examples."

    /// The site's root as a path with a slash at each end, from the address
    /// the site is served at: `/` on a domain of its own, `/Name/` under the
    /// address a project is given.
    static func rootPath(of base: String) -> String {
        guard let scheme = base.range(of: "://"),
              let slash = base[scheme.upperBound...].firstIndex(of: "/") else { return "/" }
        let path = String(base[slash...])
        return path.hasSuffix("/") ? path : path + "/"
    }

    /// The page a reader lands on at an address that has no page: the site's
    /// own bar, with its search and its three sections, two lines that say
    /// what happened, a button that opens the search, and the sections again
    /// as the cards the front page shows them as.
    ///
    /// The host serves this one file wherever the wrong address was, so
    /// nothing in it is written relative to where it sits (`layout`'s
    /// `rootedAt`). The search button stays hidden until the script that
    /// runs it has loaded, as the bar's does.
    func notFoundPage(plan: Plan, root: String) -> String {
        let page = Page(repoPath: "", sitePath: "404.html", kind: .about, title: Self.notFoundTitle, summary: "")
        let body = """
        <article class="prose notfound">
        <h1>\(HTML.escape(Self.notFoundTitle))</h1>
        <p class="lede">\(HTML.escape(Self.notFoundLine))</p>
        <p><button class="button" type="button" data-search-open hidden>Search</button></p>
        </article>
        \(sectionCards(plan: plan) { root + $0 })
        """
        return layout(page: page, title: Self.notFoundTitle, description: Self.tagline, trail: "",
                      body: body, headings: [], plan: plan, rootedAt: root)
    }

    // MARK: - An example page

    /// The folders an example is filed under, outermost first, each with the
    /// listing that stands for it, when it has one, and the name it goes by.
    /// A folder with a page of its own goes by that page's title, which is
    /// how an artist's folder reads as the artist's name, accents and all,
    /// with no second list of names to keep beside the pages; a folder with
    /// no page has only its spelling.
    static func folders(above entry: ExampleEntry, plan: Plan) -> [(name: String, listing: Page?)] {
        var walked = "Examples"
        return entry.group.split(separator: "/").map { level in
            walked += "/\(level)"
            let listing = plan.byRepoPath["\(walked)/README.md"]
            return (listing?.title ?? String(level), listing)
        }
    }

    func examplePage(_ entry: ExampleEntry, page: Page, plan: Plan, log: LinkLog) -> String {
        let source = (try? String(contentsOf: entry.sketch, encoding: .utf8)) ?? ""
        let folders = Self.folders(above: entry, plan: plan)
        log.search.append(SiteSearch.entry(for: entry, page: page, source: source, filedUnder: folders.map(\.name)))

        // The trail starts at the root, as every page's does, and walks the
        // category folders, linking each level that has a listing of its
        // own, under the name that listing is titled with. Its last step is
        // the sketch itself.
        var trail = "<a href=\"\(relative(from: page.siteDirectory, to: "index.html"))\">Ollin</a>"
        trail += " → <a href=\"\(relative(from: page.siteDirectory, to: "examples/index.html"))\">\(Self.name(of: .examples))</a>"
        for folder in folders {
            if let listing = folder.listing {
                trail += " → <a href=\"\(relative(from: page.siteDirectory, to: listing.sitePath))\">\(HTML.escape(folder.name))</a>"
            } else {
                trail += " → \(HTML.escape(folder.name))"
            }
        }
        trail += " → \(HTML.escape(entry.name))"

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
        // The listing's line about the sketch, as a sentence of its own: with
        // its capital, and with the code it names still in code type.
        if !entry.summary.isEmpty {
            let written = entry.summaryWritten.isEmpty ? entry.summary : HTML.unlinked(entry.summaryWritten)
            body += "<p class=\"lede\">\(HTML.inline(HTML.sentence(written)) { target, _ in target })</p>\n"
        }
        if let media = plan.media[entry.path], media.loop != nil {
            body += Self.clip(media, in: plan.media, named: entry.name) + "\n"
        }
        body += facts + "\n"
        body += HTML.codeBlock(source, language: "swift") + "\n"
        body += "</article>"

        let description = entry.summary.isEmpty ? "An Ollin example sketch." : HTML.sentence(entry.summary)
        // A link to the sketch unfurls as the sketch: its own still, the
        // frame its clip opens on.
        let card = plan.media[entry.path].map {
            ShareCard(address: plan.media.address(of: $0.still), width: $0.width, height: $0.height,
                      alt: "A frame of \(entry.name)")
        }
        return layout(page: page, title: entry.name, description: description, trail: trail,
                      body: body, headings: [], plan: plan, card: card)
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

    /// A chapter opens on the sketch it builds. In the markdown that is the
    /// committed still, which is what a clone, GitHub and `ollin docs` can
    /// show and what keeps the guide readable with no network. On the site the
    /// still becomes the sketch actually running, postered by itself, so a
    /// reader who blocks video or has asked for less motion still sees the
    /// picture the markdown promised rather than a hole.
    ///
    /// Keyed on the chapter's own stem, and a chapter with no clip recorded
    /// yet is left exactly as written, which is why this can land before the
    /// clips do.
    static func playingChapterHook(in body: String, page: Page, media: ExampleMedia) -> String {
        let stem = (page.repoPath as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
        guard let chapter = media.chapters[stem] else { return body }
        // The still is written relative to the chapter, and the site rewrites
        // that path when it renders, lowercasing it on the way, so match on the
        // file name without case rather than on the whole address.
        let file = (chapter.still as NSString).lastPathComponent
        guard let open = body.range(of: "<img src=\""),
              let close = body[open.lowerBound...].range(of: ">") else { return body }
        let tag = String(body[open.lowerBound ..< close.upperBound])
        guard tag.range(of: file, options: .caseInsensitive) != nil else { return body }
        let alt = tag.range(of: "alt=\"").flatMap { from in
            tag[from.upperBound...].firstIndex(of: "\"").map { String(tag[from.upperBound ..< $0]) }
        } ?? "The sketch this chapter builds"
        let poster = tag.range(of: "src=\"").flatMap { from in
            tag[from.upperBound...].firstIndex(of: "\"").map { String(tag[from.upperBound ..< $0]) }
        } ?? ""
        let video = """
            <figure class="page-hero">
            <video src="\(media.address(of: chapter.clip))" poster="\(poster)" \
            width="\(chapter.width)" height="\(chapter.height)" autoplay muted loop playsinline \
            aria-label="\(HTML.escape(alt))"></video>
            </figure>
            """
        var out = body
        out.replaceSubrange(open.lowerBound ..< close.upperBound, with: video)
        return out
    }

    /// The front page's band of sketches: each one running beside the whole
    /// program that draws it, which is the claim prose cannot make.
    ///
    /// One at a time, with dots under it, so the band costs the page the
    /// height of a single sketch however narrow the window is. That is what
    /// puts it back on a phone, where three of them stacked was a wall of
    /// code and the whole band had to be hidden instead.
    ///
    /// The README's own first program leads, since it is the one a stranger
    /// should read first and it arrives with its explanation attached; the
    /// rest come from the manifest, each with the note it carries there. The
    /// small clip rather than the full one, since the cell is half the canvas
    /// wide anyway, and only the sketch on screen plays: the others are not
    /// fetched at all until they are paged to, which is a megabyte and a half
    /// nobody pays for on arrival.
    /// The band's own heading. The README's heading names one sketch and the
    /// band holds several, so the section is titled here and carries its own
    /// anchor, as the README's sections do.
    static let bandHeading = "Examples"

    func band(lead: SiteHome.Section, running example: String, resolve: @escaping HTML.Resolver,
              plan: Plan, page: Page) -> String {
        let media = plan.media
        let lines = lead.markdown.components(separatedBy: "\n")
        // The README's heading names the sketch, not the band, so it goes
        // inside the slide it belongs to, one level down and carrying its own
        // anchor. The band's own heading has to cover all of them.
        let led = HTML.render("#" + (lines.first ?? ""), resolve: resolve).body
        let opening = HTML.render(lines.dropFirst().joined(separator: "\n"), resolve: resolve).body

        /// The target `swift run` takes for one example, when the site has a
        /// page for it.
        func target(running sketch: String) -> String? {
            guard case .example(let entry)? = plan.examples["Examples/\(sketch)"]?.kind else { return nil }
            return entry.target
        }

        /// One sketch playing, with the program that draws it beside it.
        func slide(_ sketch: String, showing body: String, first: Bool) -> String {
            var figure = ""
            if let entry = media[sketch], let clip = entry.loopSmall {
                let name = sketch.split(separator: "/").last.map(String.init) ?? sketch
                // Only the first one carries `autoplay`, so a reader running
                // no script still sees the sketch that leads run; the rest are
                // started by the script as they are paged to.
                figure = """
                    <figure><video src="\(media.address(of: clip))" poster="\(media.address(of: entry.stillSmall))" \
                    width="\(entry.width)" height="\(entry.height)"\(first ? " autoplay" : "") muted loop playsinline \
                    preload="none" aria-label="\(HTML.escape(name)) running"></video></figure>

                    """
            }
            // The command under *Run it* names whichever of these is on
            // screen, so the target it takes changes with the slide.
            let runs = target(running: sketch).map { " data-target=\"\(HTML.escape($0))\"" } ?? ""
            return """
                <article class="band-slide"\(runs)>
                \(figure)<div class="band-code">\(body)</div>
                </article>

                """
        }

        var slides = slide(example, showing: led + "\n" + opening, first: true)
        var labels = [lead.heading]
        for piece in media.showcase where piece.example != example {
            guard let entry = media[piece.example], entry.loopSmall != nil else { continue }
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
            let link = target.map { " <a href=\"\($0)\">Run it</a>" } ?? ""
            let name = plan.examples["Examples/\(piece.example)"]?.title
                ?? piece.example.split(separator: "/").last.map(String.init) ?? piece.example
            let told = "<h3>\(HTML.escape(name))</h3>\n" + HTML.codeBlock(code, language: "swift")
                + "\n<p class=\"band-note\">\(HTML.escape(piece.note))\(link)</p>"
            slides += slide(piece.example, showing: told, first: false)
            labels.append(name)
        }
        let all = relative(from: page.siteDirectory, to: "examples/index.html")
        let everything = "<a class=\"button quiet\" href=\"\(all)\">All \(plan.examples.count) examples</a>"
        // One sketch is not a band: the dots and the arrows would have
        // nowhere to go, so the section is the lead on its own.
        guard labels.count > 1 else {
            return "<section class=\"home-section home-band\">\n\(slides)\(everything)\n</section>\n"
        }
        let dots = labels.enumerated().map { index, label in
            """
            <button class="band-dot" type="button" aria-current="\(index == 0)" \
            aria-label="\(HTML.escape(label))"></button>
            """
        }.joined(separator: "\n")
        return """
            <section class="home-section home-band">
            <h2 id="\(HTML.slug(Self.bandHeading))">\(HTML.escape(Self.bandHeading))</h2>
            <p class="band-lede">Every one of these is the whole program.</p>
            <div class="band" data-band>
            <div class="band-track" tabindex="0" role="region" aria-label="Sketches, one at a time">
            \(slides)</div>
            <div class="band-controls">
            <div class="band-pager">
            <button class="band-arrow" type="button" data-band-step="-1" aria-label="Previous sketch">\
            \(SiteStyle.chevron)</button>
            <div class="band-dots">
            \(dots)
            </div>
            <button class="band-arrow" type="button" data-band-step="1" aria-label="Next sketch">\
            \(SiteStyle.chevron)</button>
            </div>
            \(everything)
            </div>
            </div>
            \(SiteStyle.bandScript)
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
    ///
    /// `inCheckout` writes the same map for the root of a checkout, the
    /// `llms.txt` committed there (`Scripts/llms.sh`): links are paths from
    /// the root rather than addresses on the site, and it names the commands
    /// that look a detail up from the checkout, which a site cannot run.
    func llmsIndex(plan: Plan, inCheckout: Bool = false) -> String {
        let base = siteBase ?? ""
        func address(_ page: Page) -> String {
            inCheckout ? page.repoPath : base + Self.markdownPath(for: page.sitePath)
        }
        // One sentence per page. The index's whole purpose is to be small
        // enough to hold in context while the detail waits behind the links,
        // and the reference's own summaries run to several sentences.
        func link(_ page: Page) -> String {
            var summary = page.summary
            if let stop = Self.firstSentence(of: summary) { summary = stop }
            // A summary written as one long sentence still has to fit, so it
            // is cut at a word rather than mid-word and marked as cut.
            if summary.count > 180 {
                let cut = summary.prefix(180)
                let word = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
                summary = word.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")) + "…"
            }
            // A title written with a dash between its parts reads as the
            // same title with a colon, and the index stays in plain text.
            let title = page.title.replacingOccurrences(of: " \u{2014} ", with: ": ")
            return "- [\(title)](\(address(page)))" + (summary.isEmpty ? "" : ": \(summary)")
        }
        var out = """
        # Ollin

        > \(Self.tagline) Sketches are Swift classes with a `setup()` and a `draw()` that runs every frame; the renderer sits on Metal and composites in linear light.


        """
        if inCheckout {
            out += """
            This file sits at the root of a checkout of the framework, and its links are paths from here. Read the quick reference first. Then look a detail up from this folder rather than reading pages whole:

            - `Scripts/ollin api <name>`: every declaration a public name has, as its source writes it, with the comment above it (where units and ranges are written down), the pages that document it, and examples that use it. A name it does not know is not public.
            - `Scripts/ollin docs <topic>`, or `<topic>#<heading>` for one section, and `Scripts/ollin docs --search "<text>"` for every line that says it.
            - `Scripts/ollin examples <word>`, and `--source` to print one.

            The reference is the authority on what exists and how it behaves; the guide teaches it in order; the examples are runnable sketches; `API/` lists the public surface, one line per declaration.


            """
        } else {
            out += """
            Every page on this site has a markdown twin at the same address with `.md` in place of `.html`, which is what these links point at. The reference is the authority on what exists and how it behaves; the guide teaches it in order; the examples are runnable sketches.


            """
        }
        // The two pages meant to be read first, with lines of their own: the
        // index lists neither under a group.
        var start: [String] = []
        if let page = plan.byRepoPath["Docs/QuickReference.md"] {
            start.append("- [\(page.title)](\(address(page))): the framework in one read: the lifecycle, the calls by area and their units, the command line, and the mistakes that fail with no error")
        }
        if let page = plan.byRepoPath["Docs/Swift.md"] {
            start.append("- [\(page.title)](\(address(page))): just enough of the language to write a sketch")
        }
        if !start.isEmpty { out += "## Start here\n\n" + start.joined(separator: "\n") + "\n\n" }
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
            project.append("- [Examples](\(address(examples))): \(plan.examples.count) runnable sketches by category, each with its whole source")
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

    /// `llms.txt` for the root of this checkout: the site's map with paths
    /// from the root for links, and the commands that look a detail up.
    /// `Scripts/llms.sh` writes it and checks it.
    public func checkoutIndex() -> String {
        llmsIndex(plan: plan(), inCheckout: true)
    }

    /// The page's own path from the site's root, which is empty for the front
    /// page: it is addressed as the site itself rather than as the file that
    /// serves it. The canonical link, the card a link unfurls as, and the line
    /// in the sitemap all read this, so the three cannot drift apart.
    static func pagePath(of page: Page) -> String {
        page.sitePath == "index.html" ? "" : page.sitePath
    }

    /// Every rendered page, for a search engine: `/sitemap.xml`.
    ///
    /// The other half of `llms.txt`, and the opposite of it. That one is
    /// curated and small, because an agent reads it into a context window
    /// with the work; this one is exhaustive and shaped for a machine that
    /// is only deciding what to fetch.
    ///
    /// The markdown twins are left out. They are the same words at a second
    /// address, which is the one thing a sitemap should not hand a crawler;
    /// a machine that wants them is told where they are by the page itself.
    ///
    /// There is no `lastmod`. The only date a build can read is the
    /// checkout's, and a checkout writes every file at once, so every page
    /// would claim to have changed on the morning of the build. A date that
    /// is wrong teaches a crawler to stop believing the file.
    func sitemap(plan: Plan, base: String) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">

        """
        for page in plan.pages {
            out += "  <url><loc>\(HTML.escape(base + Self.pagePath(of: page)))</loc></url>\n"
        }
        return out + "</urlset>\n"
    }

    /// What a crawler reads before anything else: `/robots.txt`.
    ///
    /// Nothing is closed, which is already what a missing file means. The
    /// line that earns the file is the last one: a sitemap sitting at a
    /// well-known address is still not looked for, and this is how a crawler
    /// is told it is there.
    func robots(base: String) -> String {
        """
        User-agent: *
        Allow: /

        Sitemap: \(base)sitemap.xml

        """
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
            log.pictureSources[sitePath] = repoPath
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

    // MARK: - What a link to a page unfurls as

    /// The picture a link to a page shows where it is shared: an absolute
    /// address, the picture's size, and what it shows in words.
    struct ShareCard: Equatable {
        var address: String
        var width: Int
        var height: Int
        var alt: String

        /// Whether the picture is wide enough to be shown large, across the
        /// card. A square one cut to that shape would lose its top and its
        /// bottom, so it is shown small and whole instead.
        var isWide: Bool { width * 2 >= height * 3 }
    }

    /// The smallest side a picture may have and still be offered as a card:
    /// under it the places that show cards fall back to no picture at all.
    static let smallestCardSide = 300

    /// A card from the first picture a rendered page shows, or nil when the
    /// page opens on no picture a card can be: one whose size the site
    /// cannot know, one too small, or a drawing in a format the places that
    /// show cards do not draw.
    func shareCard(fromTheFirstPictureIn body: String, page: Page, plan: Plan, log: LinkLog) -> ShareCard? {
        guard let base = siteBase,
              let open = body.range(of: "<img "),
              let close = Self.tagEnd(in: Substring(body), from: open.upperBound) else { return nil }
        let tag = String(body[open.lowerBound ..< close])
        let source = Self.attribute("src", in: tag).map(Self.unescaped) ?? ""
        let file = source.prefix { $0 != "?" && $0 != "#" }.lowercased()
        guard [".png", ".jpg", ".jpeg"].contains(where: { file.hasSuffix($0) }),
              let size = pictureSize(of: source, page: page, plan: plan, log: log),
              min(size.width, size.height) >= Self.smallestCardSide else { return nil }
        let address: String
        if source.contains("://") {
            address = source
        } else {
            let folder = page.siteDirectory.split(separator: "/").map(String.init)
            guard let sitePath = Self.joined(folder, String(source.prefix { $0 != "?" && $0 != "#" })) else { return nil }
            address = base + sitePath
        }
        let alt = Self.attribute("alt", in: tag).map(Self.unescaped) ?? ""
        return ShareCard(address: address, width: size.width, height: size.height,
                         alt: alt.isEmpty ? "The picture \(page.title) opens on" : alt)
    }

    // MARK: - The chrome

    /// One page in the site's chrome.
    ///
    /// `root` is for the one page that is served at addresses it was never
    /// written to, the page for a wrong address: every path it carries is
    /// then written from the site's root (`/`, or `/Name/` under a project's
    /// address), since a path relative to where the page sits would point
    /// somewhere else at every depth. Such a page has no place in a menu, no
    /// markdown behind it, and no address of its own to call canonical, and
    /// it asks not to be indexed.
    func layout(page: Page, title: String, description: String, trail: String,
                body: String, headings: [(level: Int, text: String, anchor: String)], plan: Plan,
                card: ShareCard? = nil, rootedAt root: String? = nil) -> String {
        let here = page.siteDirectory
        let asset = { (name: String) in root.map { $0 + name } ?? relative(from: here, to: name) }
        let isHome: Bool
        if case .home = page.kind { isHome = true } else { isHome = false }
        let fullTitle = isHome ? "Ollin" : "\(title) · Ollin"
        let pagePath = Self.pagePath(of: page)
        var canonical = domain.map { "<link rel=\"canonical\" href=\"https://\($0)/\(pagePath)\">" } ?? ""
        // The two relations the convention asks for, so a machine that lands
        // on the rendered page can find the markdown behind it and the index
        // that describes the site, without being told either address.
        var machine = """
        <link rel="alternate" type="text/markdown" href="\(asset(Self.markdownPath(for: page.sitePath)))">
        <link rel="describedby" type="text/markdown" href="\(asset("llms.txt"))">
        """
        // What a link to the page unfurls as, in a message or a feed: the
        // page's title and line, and a picture. A page that has a picture of
        // its own (`ShareCard`) shows that one; every other page shows the
        // mark's card. A card has to be an absolute address, so it is
        // written against the custom domain or, before there is one, the
        // address GitHub Pages serves the repository at, and left out when
        // neither is known.
        var share = ""
        if root != nil {
            canonical = ""
            machine = "<meta name=\"robots\" content=\"noindex\">"
        } else if let base = siteBase {
            share += "<meta property=\"og:url\" content=\"\(HTML.escape(base + pagePath))\">\n"
            let marks = plan.hasSocialCard
                ? ShareCard(address: base + "assets/social.png", width: 1200, height: 630, alt: "The Ollin mark") : nil
            if let shown = card ?? marks {
                share += """
                <meta property="og:image" content="\(HTML.escape(shown.address))">
                <meta property="og:image:width" content="\(shown.width)">
                <meta property="og:image:height" content="\(shown.height)">
                <meta property="og:image:alt" content="\(HTML.escape(shown.alt))">
                <meta name="twitter:card" content="\(shown.isWide ? "summary_large_image" : "summary")">

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

        let alone = isHome || root != nil
        let sidebar = alone ? "" : self.sidebar(for: page, plan: plan)
        let rail = alone ? "" : self.rail(headings, title: title)
        // On a phone the section's menu is a sheet under the bar, and what
        // opens it is the bar's own tab for the section the page is in: a
        // button beside the link, which the stylesheet shows in the link's
        // place where the screen is narrow and a script is there to answer
        // it. A project page has no tab, so its button sits beside the mark.
        let opener = { (extra: String) in
            "<button type=\"button\" class=\"menu-toggle\(extra)\" aria-expanded=\"false\" aria-controls=\"menu\""
        }
        func navItem(_ label: String, _ section: Section, _ path: String) -> String {
            guard page.section == section, !isHome else { return "<a href=\"\(asset(path))\">\(label)</a>" }
            guard !sidebar.isEmpty else { return "<a href=\"\(asset(path))\" class=\"active\" aria-current=\"true\">\(label)</a>" }
            return "<a href=\"\(asset(path))\" class=\"active has-menu\" aria-current=\"true\">\(label)</a>"
                + "\(opener(""))>\(label)\(SiteStyle.disclosure)</button>"
        }
        let markOpener = page.section == .home && !sidebar.isEmpty
            ? "\(opener(" beside-mark")) aria-label=\"Ollin pages\">\(SiteStyle.disclosure)</button>" : ""
        // The search opens from the bar and lives in a dialog at the end of
        // the page. Its button is hidden until the script that runs it has
        // loaded, so a reader with no script sees no control that does
        // nothing; the index is loaded on the first search, from the site's
        // root, which the dialog carries as the path back up to it.
        let siteRoot = String(asset("index.html").dropLast("index.html".count))
        // Ahead of the bar, so it is the first thing a Tab reaches: a reader
        // on a keyboard steps over the bar and the whole menu to the page.
        let nav = """
        <a class="skip" href="#main">Skip to content</a>
        <header class="bar">
          <div class="bar-inner">
            <a class="wordmark" href="\(asset("index.html"))" aria-label="Ollin home">\(Self.named(plan.mark))<span class="name">Ollin</span></a>\(markOpener)
            <nav class="sections" aria-label="Sections">
              \(navItem(Self.name(of: .guide), .guide, Self.index(of: .guide)))
              \(navItem(Self.name(of: .docs), .docs, Self.index(of: .docs)))
              \(navItem(Self.name(of: .examples), .examples, Self.index(of: .examples)))
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

        // Where the list beside the page is out of sight, the same list
        // folds under the page's title.
        let fold = alone ? "" : self.onPage(headings, title: title)
        let body = Self.framingCode(in: Self.linkingHeadings(in: fold.isEmpty ? body : Self.inserting(fold, afterTheFirstHeadingOf: body)))
        let menus = alone ? "" : "<script src=\"\(asset("assets/menus.js"))\" defer></script>\n"
        let trailBlock = trail.isEmpty ? "" : "<nav class=\"trail\" aria-label=\"Breadcrumb\">\(trail)</nav>\n"
        let layoutClass = isHome ? "home" : (sidebar.isEmpty ? "single" : (rail.isEmpty ? "with-sidebar" : "with-sidebar with-rail"))

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta name="theme-color" media="(prefers-color-scheme: light)" content="\(SiteStyle.ground)">
        <meta name="theme-color" media="(prefers-color-scheme: dark)" content="\(SiteStyle.groundDark)">
        <title>\(HTML.escape(fullTitle))</title>
        <meta name="description" content="\(HTML.escape(description))">
        <meta property="og:title" content="\(HTML.escape(fullTitle))">
        <meta property="og:description" content="\(HTML.escape(description))">
        <meta property="og:type" content="website">
        <meta property="og:site_name" content="Ollin">
        \(share)\(canonical)
        \(machine)
        \(icons)\(SiteStyle.scriptedMark)
        <link rel="stylesheet" href="\(asset("assets/site.css"))">
        </head>
        <body>
        \(nav)
        <div class="layout \(layoutClass)">
        \(sidebar)
        <main id="main" tabindex="-1">
        \(trailBlock)\(body)
        </main>
        \(rail)
        </div>
        \(search)
        \(menus)<script src="\(asset("assets/page.js"))" defer></script>
        \(foot(page: page, plan: plan, address: asset))
        </body>
        </html>
        """
    }

    /// A page's body with a link at the end of every heading that has an
    /// address of its own: the second level to the fourth, each carrying the
    /// anchor the renderer gave it. The link goes to the heading itself, so a
    /// reader who wants to send somebody one section of a long page has its
    /// address to copy; the stylesheet shows the link's mark while the
    /// pointer is over the heading, and the page's script copies the address
    /// when the mark is pressed. A page's title has no link (its address is
    /// the page's), and neither has a heading with no anchor.
    static func linkingHeadings(in body: String) -> String {
        var out = ""
        out.reserveCapacity(body.count + 1024)
        var rest = Substring(body)
        while let open = rest.range(of: "<h") {
            out += rest[..<open.upperBound]
            rest = rest[open.upperBound...]
            // `<h2 id="...">` and its like; anything else that opens on
            // `<h` (the page's title, a rule, a heading with no anchor) is
            // passed over.
            guard let level = rest.first, "234".contains(level), rest.dropFirst().hasPrefix(" id=\"") else { continue }
            let afterID = rest.dropFirst(6)
            guard let quote = afterID.firstIndex(of: "\""),
                  let tagEnd = Self.tagEnd(in: rest, from: rest.index(after: quote)),
                  let close = rest.range(of: "</h\(level)>", range: tagEnd ..< rest.endIndex) else { continue }
            let anchor = String(afterID[..<quote])
            let inner = rest[rest.index(after: tagEnd) ..< close.lowerBound]
            // A heading that already carries a link at itself is left alone.
            guard !anchor.isEmpty, !inner.contains("class=\"anchor\"") else { continue }
            let name = Self.plainText(of: inner).replacingOccurrences(of: "\"", with: "&quot;")
            out += rest[..<close.lowerBound]
            out += "<a class=\"anchor\" href=\"#\(anchor)\" aria-label=\"Link to this section: \(name)\">\(SiteStyle.linkIcon)\(SiteStyle.copiedIcon)</a>"
            rest = rest[close.lowerBound...]
        }
        out += rest
        return out
    }

    /// The words of a piece of rendered text, with its tags taken out and
    /// its spaces closed up. What a page escaped stays escaped, so the words
    /// can be written into an attribute as they are.
    static func plainText(of html: Substring) -> String {
        var text = ""
        var inTag = false
        for character in html {
            if character == "<" { inTag = true } else if character == ">" { inTag = false } else if !inTag { text.append(character) }
        }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// A chapter's body with the picture it opens on in the frame a
    /// chapter's opening clip stands in, so the two kinds of opening are the
    /// same size: the width of the column. The picture is the chapter's
    /// opening one when nothing stands between the title and it; a picture
    /// further down is a figure of the text and keeps the width the chapter
    /// wrote for it. A chapter whose opening is already a clip is not
    /// touched, and neither is a picture in two schemes.
    static func framingOpeningPicture(in body: String) -> String {
        guard let title = body.range(of: "</h1>") else { return body }
        var index = title.upperBound
        while index < body.endIndex, body[index].isWhitespace { index = body.index(after: index) }
        guard body[index...].hasPrefix("<img "),
              let close = Self.tagEnd(in: Substring(body), from: body.index(index, offsetBy: 5)) else { return body }
        var out = body
        out.insert(contentsOf: "\n</figure>", at: body.index(after: close))
        out.insert(contentsOf: "<figure class=\"page-hero\">\n", at: index)
        return out
    }

    /// A page's body with every block of code in a frame of its own.
    ///
    /// The block itself is what scrolls when a line is too long, so anything
    /// set on it would slide away with the line. The frame around it stays
    /// put, and it is what the button that copies the block and the fade at
    /// the block's edge are set on (`SiteStyle.pageScript`). The frame is
    /// the site's chrome, which is why it is added here and the renderer's
    /// own markup for a block of code is left as it is. Only a block the
    /// renderer wrote is framed: a `<pre` a page wrote by hand, with
    /// attributes of its own, is left as written.
    static func framingCode(in body: String) -> String {
        var out = ""
        out.reserveCapacity(body.count + 512)
        var rest = Substring(body)
        while let open = rest.range(of: "<pre>"),
              let close = rest.range(of: "</pre>", range: open.upperBound ..< rest.endIndex) {
            out += rest[..<open.lowerBound]
            out += "<div class=\"code\">"
            out += rest[open.lowerBound ..< close.upperBound]
            out += "</div>"
            rest = rest[close.upperBound...]
        }
        out += rest
        return out
    }

    /// The section's own map, beside the page: the chapters, the reference
    /// groups, the example categories, or the project pages.
    func sidebar(for page: Page, plan: Plan) -> String {
        let here = page.siteDirectory
        func item(_ target: Page, label: String? = nil, holding: Bool = false) -> String {
            // By site path, not source: the front page and the About page
            // are two pages of one file. A row that stands for a folder is
            // marked too while the page open is one of the folder's own, so
            // every page has its place in the menu.
            var current = target.sitePath == page.sitePath ? " aria-current=\"page\"" : ""
            if current.isEmpty, holding { current = " aria-current=\"true\"" }
            return "<li><a href=\"\(relative(from: here, to: target.sitePath))\"\(current)>\(HTML.escape(label ?? target.title))</a></li>"
        }
        func group(_ name: String, open: Bool, _ items: [String]) -> String {
            guard !items.isEmpty else { return "" }
            return "<details\(open ? " open" : "")><summary>\(HTML.escape(name))</summary><ul>\n\(items.joined(separator: "\n"))\n</ul></details>"
        }

        var out = "<nav class=\"sidebar\" id=\"menu\" aria-label=\"Section\" tabindex=\"-1\">\n"
        switch page.section {
        case .home:
            var items: [String] = []
            for target in plan.pages {
                switch target.kind {
                case .home: items.append(item(target, label: "Home"))
                case .about: items.append(item(target, label: Self.label(of: target)))
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
            out += "<p class=\"sidebar-title\">\(Self.name(of: .guide))</p><ul>\n\(overview.joined())\n</ul>"
            out += group("Chapters", open: true, chapters)
            out += group("Appendices", open: page.repoPath.dropFirst("Guide/".count).first?.isNumber != true, appendices)

        case .docs:
            if let index = plan.byRepoPath["Docs/README.md"] {
                // A page that sits beside the index, in no folder, is about
                // the reference as a whole (the quick reference, the Swift
                // primer), so it is listed with the overview rather than
                // under a group.
                let beside = plan.pages.filter {
                    guard case .docs = $0.kind else { return false }
                    return $0.repoPath != index.repoPath && $0.repoPath.split(separator: "/").count == 2
                }
                let rows = [item(index, label: "Overview")] + beside.map { item($0) }
                out += "<p class=\"sidebar-title\">\(Self.name(of: .docs))</p><ul>\n\(rows.joined(separator: "\n"))\n</ul>"
            }
            for group in plan.docsGroups {
                var items = group.topics.compactMap { plan.byRepoPath["Docs/\($0).md"] }.map { item($0) }
                // A group whose pages share one folder opens on that
                // folder's own index, as a category of the examples does,
                // so the index has a row to be marked on.
                let folders = Set(group.topics.compactMap { $0.split(separator: "/").first.map(String.init) })
                if folders.count == 1, let folder = folders.first, group.topics.allSatisfy({ $0.contains("/") }),
                   let listing = plan.byRepoPath["Docs/\(folder)/README.md"] {
                    items.insert(item(listing, label: "All \(group.name)"), at: 0)
                }
                // A folder's own index opens the groups its pages are in.
                // The overview is every folder's parent, and it opens none:
                // all of them open at once is a menu eight screens tall.
                let holdsPage = group.topics.contains { "Docs/\($0).md" == page.repoPath }
                    || group.topics.contains { topic in
                        page.repoPath.hasSuffix("README.md") && page.repoPath != "Docs/README.md"
                            && "Docs/\(topic)".hasPrefix(page.repoPath.replacingOccurrences(of: "README.md", with: ""))
                    }
                out += self.group(group.name, open: holdsPage, items)
            }

        case .examples:
            if let index = plan.byRepoPath["Examples/README.md"] {
                out += "<p class=\"sidebar-title\">\(Self.name(of: .examples))</p><ul>\n\(item(index, label: "Overview"))\n</ul>"
            }
            for category in plan.exampleCategories {
                let categoryPath = "Examples/\(category.path)"
                let inside = page.repoPath.hasPrefix(categoryPath + "/") || page.repoPath == categoryPath + "/README.md"
                var items: [String] = []
                if let listing = plan.byRepoPath[categoryPath + "/README.md"] {
                    items.append(item(listing, label: "All \(category.name)"))
                }
                // A folder inside the category that has a page of its own (an
                // artist, a part of the 3D set) is one row, under that page's
                // title, and its sketches are listed on that page. A sketch in
                // a folder with no page keeps a row of its own, since nothing
                // else leads to it.
                var folders: [Page] = []
                var sketches: [String] = []
                for target in plan.pages {
                    guard case .example(let entry) = target.kind, entry.path.hasPrefix(category.path + "/") else { continue }
                    let rest = entry.path.dropFirst(category.path.count + 1)
                    let subgroup = rest.split(separator: "/").dropLast().map(String.init)
                    if let first = subgroup.first, let folder = plan.byRepoPath["\(categoryPath)/\(first)/README.md"] {
                        if !folders.contains(where: { $0.sitePath == folder.sitePath }) { folders.append(folder) }
                        continue
                    }
                    sketches.append(item(target, label: subgroup.isEmpty ? entry.name : "\(subgroup.joined(separator: "/")) / \(entry.name)"))
                }
                // In the order of the names shown, which is not the folders'
                // order once a folder goes by another name than its spelling.
                folders.sort { Self.menuOrder($0.title, $0.sitePath) < Self.menuOrder($1.title, $1.sitePath) }
                for folder in folders {
                    let holds = page.sitePath != folder.sitePath && page.repoPath.hasPrefix(folder.repoPath.dropLast("README.md".count))
                    items.append(item(folder, holding: holds))
                }
                items += sketches
                out += group(category.name, open: inside, items)
            }
        }
        out += "\n</nav>\n\(SiteStyle.menuPlaceScript)"
        return out
    }

    func group(_ name: String, open: Bool, _ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        return "<details\(open ? " open" : "")><summary>\(HTML.escape(name))</summary><ul>\n\(items.joined(separator: "\n"))\n</ul></details>"
    }

    /// What a menu sorts a title by: the title without its case and its
    /// accents, so `Dóra` files under D and `Zdeněk` under Z on any machine,
    /// then the path, so two rows with one name keep one order.
    static func menuOrder(_ title: String, _ path: String) -> (String, String) {
        (title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")), path)
    }

    /// The headings a page lists as its own map: its sections and the ones
    /// under them, without the title, and none at all for a page too short
    /// to need a map.
    ///
    /// Two things a list is no good for are left out of it. A section named
    /// in brackets with a date after it, as a changelog names a release
    /// (`[0.18.0] - 2026-11-14`), is listed by the name alone. And where the
    /// headings under the sections mostly repeat one another (`Added`,
    /// `Changed`, `Fixed` under every release), they say nothing about
    /// where a reader is, so the list is the sections alone.
    static func listed(_ headings: [(level: Int, text: String, anchor: String)],
                       title: String) -> [(level: Int, text: String, anchor: String)] {
        var listed = headings.filter { $0.level == 2 || $0.level == 3 }.filter { $0.text != title }
        let under = listed.filter { $0.level == 3 }
        let repeated = under.filter { entry in under.filter { $0.text == entry.text }.count > 1 }
        if under.count >= 4, repeated.count * 2 > under.count { listed.removeAll { $0.level == 3 } }
        listed = listed.map { ($0.level, Self.listedName($0.text), $0.anchor) }
        return listed.count >= 2 ? listed : []
    }

    /// A heading's name in a list: what stands in its opening brackets when
    /// it opens on a pair, and the heading as written otherwise.
    static func listedName(_ heading: String) -> String {
        guard heading.hasPrefix("["), let close = heading.firstIndex(of: "]") else { return heading }
        let inside = heading[heading.index(after: heading.startIndex) ..< close]
        let after = heading[heading.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard !inside.isEmpty, after.isEmpty || after.hasPrefix("-") else { return heading }
        return String(inside)
    }

    static func rows(_ listed: [(level: Int, text: String, anchor: String)]) -> String {
        listed.map { "<li class=\"level-\($0.level)\"><a href=\"#\($0.anchor)\">\(HTML.escape($0.text))</a></li>\n" }.joined()
    }

    /// The page's own headings, for a long page. The script the page loads
    /// marks the one being read as the page scrolls.
    func rail(_ headings: [(level: Int, text: String, anchor: String)], title: String) -> String {
        let listed = Self.listed(headings, title: title)
        guard !listed.isEmpty else { return "" }
        return "<nav class=\"rail\" aria-label=\"On this page\"><p class=\"rail-title\">On this page</p><ul>\n\(Self.rows(listed))</ul></nav>"
    }

    /// The same list as a fold, for the widths where the list beside the
    /// page is not shown. It is the page's own markup rather than something
    /// a script builds, so it is there with scripts off and takes its room
    /// before the page is drawn.
    func onPage(_ headings: [(level: Int, text: String, anchor: String)], title: String) -> String {
        let listed = Self.listed(headings, title: title)
        guard !listed.isEmpty else { return "" }
        return "<details class=\"onpage\"><summary>On this page</summary><ul>\n\(Self.rows(listed))</ul></details>"
    }

    /// A block set right under a page's first heading, which is its title.
    /// A page with no heading keeps its body as it is.
    static func inserting(_ block: String, afterTheFirstHeadingOf body: String) -> String {
        let closes = (1 ... 6).compactMap { body.range(of: "</h\($0)>") }
        guard let first = closes.min(by: { $0.lowerBound < $1.lowerBound }) else { return body }
        var out = body
        out.insert(contentsOf: "\n" + block, at: first.upperBound)
        return out
    }

    /// A chapter's last line, set as two cards.
    ///
    /// Every chapter ends on a rule and one line of links: the contents,
    /// the chapter before, the chapter after. The words and the links are
    /// that line's own and none is added: `Previous` and `Next` become the
    /// small label on each card, the link's text its name, and a link with
    /// no label (the contents) stays a plain link under the two. A page
    /// that does not end on such a line is handed back as it came.
    static func pager(in body: String) -> String {
        guard let rule = body.range(of: "<hr>", options: .backwards) else { return body }
        let tail = body[rule.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard tail.hasPrefix("<p>"), tail.hasSuffix("</p>"), tail.components(separatedBy: "<p>").count == 2 else { return body }
        var cards: [String] = []
        var plain: [String] = []
        for part in tail.dropFirst(3).dropLast(4).components(separatedBy: " · ") {
            var link = Substring(part)
            var way: (word: String, relation: String)?
            for (word, relation) in [("Previous", "prev"), ("Next", "next")] where link.hasPrefix(word + ": ") {
                way = (word, relation)
                link = link.dropFirst(word.count + 2)
            }
            let opening = "<a href=\""
            guard link.hasPrefix(opening), link.hasSuffix("</a>"), link.components(separatedBy: "<a ").count == 2,
                  let quote = link.dropFirst(opening.count).firstIndex(of: "\""),
                  link[quote...].hasPrefix("\">") else { return body }
            let address = link[link.index(link.startIndex, offsetBy: opening.count) ..< quote]
            let name = link[link.index(quote, offsetBy: 2)...].dropLast(4)
            if let way {
                cards.append("<a class=\"pager-card pager-\(way.word.lowercased())\" rel=\"\(way.relation)\" href=\"\(address)\">"
                    + "<span class=\"pager-way\">\(way.word)</span><span class=\"pager-name\">\(name)</span></a>")
            } else {
                plain.append("<a class=\"pager-up\" href=\"\(address)\">\(name)</a>")
            }
        }
        guard !cards.isEmpty else { return body }
        let pager = "<nav class=\"pager\" aria-label=\"Previous and next\">\n\((cards + plain).joined(separator: "\n"))\n</nav>"
        return body[..<rule.lowerBound] + pager
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
