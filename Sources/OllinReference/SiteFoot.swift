import Foundation

/// The foot of every page: the mark and the line that says what Ollin is, the
/// release it stands at, and the way to every part of the site that has no
/// tab in the bar.
///
/// Everything in it is read from the checkout. The sections are the bar's
/// own, the project pages are the files the plan found (`aboutPages`), each
/// under the short name its menu row goes by, and the release is the newest
/// one the changelog has a section for. So a project page added to the plan
/// has to be given a column here, and a test fails until it is; a release cut
/// tomorrow shows in the foot of the next build with nothing edited.
extension SiteBuilder {

    /// The foot's columns of project pages, by the file each row stands for.
    /// `README.md` is the About page, the README rendered whole. A file that
    /// is not in the checkout leaves its row out.
    static let footGroups: [(title: String, pages: [String])] = [
        ("Project", ["README.md", "ROADMAP.md", "CHANGELOG.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SECURITY.md"]),
        ("How it is built", ["CAPABILITIES.md", "ARCHITECTURE.md", "DESIGN-NOTES.md", "ATTRIBUTION.md", "THIRD-PARTY-NOTICES.md"]),
    ]

    /// What the first column is called: the three sections the bar names.
    static let footSectionsTitle = "Learn"

    /// The one sentence the foot closes on, with the repository linked.
    static func footNote(repository: String) -> String {
        "Ollin is MIT licensed and built in public. <a href=\"\(HTML.escape(repository))\" rel=\"noopener\">The repository</a> holds everything on this site."
    }

    /// The newest release the changelog has a section for: its number, and
    /// the anchor that section gets on the changelog's page. The changelog
    /// opens on what is not released yet, which has no number and is stepped
    /// over; a heading inside fenced code is code.
    static func latestRelease(inChangelog markdown: String) -> (version: String, anchor: String)? {
        var fence: String?
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            guard trimmed.hasPrefix("## [") else { continue }
            let heading = trimmed.dropFirst(3)
            let version = heading.dropFirst().prefix { $0 != "]" }
            guard version.first?.isNumber == true, version.allSatisfy({ $0.isNumber || $0 == "." }) else { continue }
            return (String(version), HTML.slug(Markdown.plain(String(heading))))
        }
        return nil
    }

    /// The name the bar's mark is drawn under, so the foot can show the same
    /// drawing without carrying its outline a second time on every page.
    static let markName = "bar-mark"

    /// The bar's mark, named: the drawing as the plan inlined it, with the
    /// name the foot draws it again by at the end of its opening tag.
    static func named(_ mark: String) -> String {
        guard let close = mark.firstIndex(of: ">") else { return mark }
        return mark.replacingCharacters(in: close ... close, with: " id=\"\(markName)\">")
    }

    /// The mark a second time, as a reference to the one in the bar. It is
    /// drawn in whatever ink the text around it is set in, as the first is.
    static let markAgain = """
    <svg class="mark" aria-hidden="true" focusable="false" viewBox="0 0 100 100"><use href="#\(markName)"/></svg>
    """

    /// The foot, with every path written the way the page it stands on needs
    /// it: `address` turns a site path into that page's link to it.
    func foot(page: Page, plan: Plan, address: (String) -> String) -> String {
        func row(_ label: String, _ sitePath: String) -> String {
            let here = sitePath == page.sitePath ? " aria-current=\"page\"" : ""
            return "<li><a href=\"\(address(sitePath))\"\(here)>\(HTML.escape(label))</a></li>"
        }
        func group(_ title: String, _ rows: [String]) -> String {
            guard !rows.isEmpty else { return "" }
            let id = "foot-" + HTML.slug(title)
            return """
                  <div class="foot-group">
                    <p class="foot-title" id="\(id)">\(HTML.escape(title))</p>
                    <ul aria-labelledby="\(id)">
                      \(rows.joined(separator: "\n          "))
                    </ul>
                  </div>

            """
        }

        var groups = group(Self.footSectionsTitle, [Section.guide, .docs, .examples].map { row(Self.name(of: $0), Self.index(of: $0)) })
        for (title, files) in Self.footGroups {
            var rows: [String] = []
            for file in files {
                if file == "README.md" {
                    if let about = plan.about { rows.append(row(Self.label(of: about), about.sitePath)) }
                } else if let found = plan.byRepoPath[file] {
                    rows.append(row(Self.label(of: found), found.sitePath))
                }
            }
            // The repository closes the project's own column: on a phone the
            // bar has no room for its link, and this is where it waits.
            if title == Self.footGroups.first?.title {
                rows.append("<li><a href=\"\(HTML.escape(repository))\" rel=\"noopener\">GitHub</a></li>")
            }
            groups += group(title, rows)
        }

        var release = ""
        if let changelog = plan.byRepoPath["CHANGELOG.md"], let latest = plan.release {
            release = "\n      <p class=\"foot-release\"><a href=\"\(address(changelog.sitePath))#\(latest.anchor)\">Version \(HTML.escape(latest.version))</a></p>"
        }

        return """
        <footer class="foot">
          <div class="foot-inner">
            <div class="foot-lead">
              <a class="wordmark" href="\(address("index.html"))" aria-label="Ollin home">\(Self.markAgain)<span class="name">Ollin</span></a>
              <p class="foot-line">\(HTML.escape(Self.tagline))</p>\(release)
            </div>
            <nav class="foot-nav" aria-label="Site">
        \(groups)    </nav>
            <p class="foot-note">\(Self.footNote(repository: repository))</p>
          </div>
        </footer>
        """
    }
}
