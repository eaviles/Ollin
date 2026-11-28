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
        /// One section across the page, its text running in two columns
        /// under its heading where the page is wide enough for two. The
        /// browser decides where the first column ends, so the two stay even
        /// however the README's paragraphs change.
        case flowing(String)
        /// One section across the page, the parts its `###` headings open
        /// standing side by side: two ways to do one thing, each read down
        /// its own column.
        case split(String)
        /// One section leading a band of sketches you page through, its own
        /// program the first of them, playing as the example named here.
        case carousel(String, running: String)

        var headings: [String] {
            switch self {
            case .section(let heading), .flowing(let heading), .split(let heading), .carousel(let heading, _):
                return [heading]
            }
        }

        /// The class the row's section wears beside its own name, which is
        /// what the stylesheet lays it out by.
        var layoutClass: String {
            switch self {
            case .section, .carousel: return ""
            case .flowing: return " home-flow"
            case .split: return " home-split"
            }
        }
    }

    /// The README sections the front page shows, in the README's order, by
    /// their `## ` headings.
    static let rows: [Row] = [
        .carousel("Hello, circle", running: "Basic/HelloCircle"),
        .flowing("Run it"),
        .split("Install"),
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

    // MARK: - Laying a section out

    /// A rendered section with each part a `###` heading opens in a box of
    /// its own, so the stylesheet can stand the parts side by side. What
    /// comes before the first such heading (the section's own heading, a line
    /// of introduction) stays outside the boxes and runs across them. A
    /// section with fewer than two parts is handed back as it came: one box
    /// beside nothing is not a layout.
    static func parted(_ html: String) -> String {
        let pieces = html.components(separatedBy: "<h3")
        guard pieces.count > 2 else { return html }
        // Each piece opens inside its heading's own tag, so only what
        // trails it is trimmed: the space ahead of the tag's first attribute
        // is part of the tag.
        let parts = pieces.dropFirst().map { piece -> String in
            var body = Substring(piece)
            while let last = body.last, last.isWhitespace { body.removeLast() }
            return "<div class=\"home-part\">\n<h3\(body)\n</div>\n"
        }
        return pieces[0] + parts.joined()
    }

    /// The rendered opening in two boxes: the paragraphs it starts with, and
    /// the facts that follow them, from its first list to its end (the list
    /// of what Ollin runs on and is made with, and the note on where it
    /// stands). On a wide page the stylesheet sets the second beside the
    /// first as a sheet of facts; on a narrow one they stack in the README's
    /// own order, which the markup keeps. An opening with no list is handed
    /// back as it came.
    static func openingColumns(_ html: String) -> String {
        guard let list = html.range(of: "<ul") else { return html }
        let lede = html[..<list.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let facts = html[list.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lede.isEmpty else { return html }
        return "<div class=\"home-lede\">\n\(lede)\n</div>\n<div class=\"home-facts\">\n\(facts)\n</div>"
    }
}
