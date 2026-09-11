import Foundation

/// The front page's share of the README.
///
/// The front page shows a subset of the README rather than the whole file:
/// the opening (the paragraphs before its first section, less the badge row
/// and the navigation row, which the bar and the cards stand in for), then
/// the sections named in `rows`, by their own headings, laid out for the
/// width of a page rather than the column of a file. The README stays the
/// source: nothing here rewrites a line of it. The rest of the README is the
/// About page, rendered whole, and the front page ends with a link to every
/// section it left there, so nothing the README says is further than one
/// click from the front. A heading named here that the README no longer
/// carries is reported by the build rather than dropped in silence.
enum SiteHome {

    /// One row of the front page, below the hero and the cards.
    enum Row: Equatable {
        /// One section across the page.
        case section(String)
        /// Two sections side by side.
        case pair(String, String)
        /// One section leading a band of sketches you page through, its own
        /// program the first of them, playing as the example named here.
        case carousel(String, running: String)

        var headings: [String] {
            switch self {
            case .section(let heading), .carousel(let heading, _): return [heading]
            case .pair(let left, let right): return [left, right]
            }
        }
    }

    /// The README sections the front page shows, in the README's order, by
    /// their `## ` headings.
    static let rows: [Row] = [
        .carousel("Hello, circle", running: "Basic/HelloCircle"),
        .pair("Run it", "Install"),
        .section("What's in it"),
    ]

    /// Every heading `rows` names, in order.
    static var shown: [String] { rows.flatMap(\.headings) }

    /// One `## ` section of the README: its heading as plain text, and its
    /// markdown from the heading line to the line before the next section.
    struct Section: Equatable {
        var heading: String
        var markdown: String
        /// The anchor the heading gets on a page.
        var anchor: String { HTML.slug(heading) }
    }

    /// The README split at its `## ` headings: whatever comes before the
    /// first one, then each section with its heading line. A `##` inside a
    /// fenced code block is code, not a heading.
    static func split(_ markdown: String) -> (opening: String, sections: [Section]) {
        var opening: [String] = []
        var sections: [Section] = []
        var current: (heading: String, lines: [String])?
        var fence: String?
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
            } else if trimmed.hasPrefix("## "), !trimmed.hasPrefix("### ") {
                if let done = current {
                    sections.append(Section(heading: done.heading, markdown: done.lines.joined(separator: "\n")))
                }
                current = (Markdown.plain(String(trimmed.dropFirst(3))).trimmingCharacters(in: .whitespaces), [])
            }
            if current != nil {
                current!.lines.append(line)
            } else {
                opening.append(line)
            }
        }
        if let done = current {
            sections.append(Section(heading: done.heading, markdown: done.lines.joined(separator: "\n")))
        }
        return (opening.joined(separator: "\n"), sections)
    }

    /// The headings inside a piece of markdown, as the anchors they get,
    /// with a `#` inside fenced code left alone. Used to tell a link at a
    /// section the front page shows from one at a section it left on the
    /// About page.
    static func anchors(in markdown: String) -> Set<String> {
        var found: Set<String> = []
        var fence: String?
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
            } else if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                found.insert(HTML.slug(Markdown.plain(text)))
            } else if trimmed.hasPrefix("<a name=\"") || trimmed.hasPrefix("<a id=\"") {
                let start = trimmed.index(trimmed.firstIndex(of: "\"")!, offsetBy: 1)
                found.insert(String(trimmed[start...].prefix { $0 != "\"" }))
            }
        }
        return found
    }

    /// The opening without the rows the site's own chrome stands in for: a
    /// paragraph of badges (pictures and nothing else), and a navigation row
    /// (links joined by middle dots and nothing else). Everything else stays
    /// as the README spells it.
    static func trimmedOpening(_ opening: String) -> String {
        opening.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !HTML.paragraphClass(trimmed).contains("badges") && !isNavigationRow(trimmed)
        }.joined(separator: "\n")
    }

    /// A line that is links joined by middle dots and nothing else.
    static func isNavigationRow(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("["), trimmed.contains("·") else { return false }
        var rest = Substring(trimmed)
        var links = 0
        while let link = Markdown.link(in: rest), !link.image {
            links += 1
            rest = link.rest.drop { $0 == " " || $0 == "·" }
        }
        return links >= 2 && rest.isEmpty
    }
}
