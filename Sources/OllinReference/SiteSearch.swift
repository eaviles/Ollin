import Foundation

/// The site's search: what the page's own script reads.
///
/// Every section of every page is one entry: the page's title, the heading,
/// where the section is on the site, its first line, and the words it uses
/// that its title and heading do not already say. The words are what lets a
/// reader find a section by what it talks about rather than what it is
/// called, the same want the terminal's `--search` answers, and they are kept
/// small: a stop word goes, so does a word shorter than three letters, and so
/// does any word common to more than a tenth of the sections, since a word
/// that common finds everything and so finds nothing. The entries are written
/// beside the pages as a script that sets one global rather than as a file
/// the page fetches, so the search works from a folder opened off the disk as
/// well as from a server. The matching itself is a library's, loaded when the
/// search opens (`SiteStyle.searchScript`).
enum SiteSearch {

    /// One section, as the search lists it.
    struct Entry: Equatable {
        /// Which part of the site: `guide`, `docs`, `examples`, or `home`.
        var kind: String
        /// The page's title.
        var title: String
        /// The heading the section sits under, or empty for the page's own
        /// opening.
        var heading: String
        /// The site path, with the heading's anchor: `docs/drawing/color.html#ramps`.
        var url: String
        /// The first line under the heading, as plain text.
        var excerpt: String
        /// The words the section uses, beyond its title and heading.
        var words: [String]
    }

    /// How long an excerpt may run before it is cut at a word.
    static let excerptLength = 160

    /// The share of the entries a word may appear in before it is dropped
    /// from every one of them.
    static let commonShare = 0.1

    // MARK: - Reading a page

    /// The sections of a rendered page. The heading that names the page gives
    /// the page's own entry, with its opening prose under it and no anchor;
    /// every other heading gives one of its own, but for a page's table of
    /// contents, which only repeats the headings that follow it.
    ///
    /// The project pages beside the front page (the capabilities inventory,
    /// the architecture notes, the changelog, the credits) are written for
    /// the people building Ollin, and their sections run to thousands of
    /// words each: they are listed by heading and first line alone, since
    /// their words would double the index for a reader who came for the
    /// Guide, the reference, and the examples.
    static func entries(for page: SiteBuilder.Page, rendered: HTML.Page) -> [Entry] {
        let kind = page.section.rawValue
        let listsWords: Bool
        if case .about = page.kind { listsWords = false } else { listsWords = true }
        let titleWords = Set(tokens(page.title))
        let sections = rendered.sections.isEmpty ? [""] : rendered.sections
        var opening = sections[0]
        var found: [Entry] = []
        var titled = false
        for (index, heading) in rendered.headings.enumerated() {
            let text = index + 1 < sections.count ? sections[index + 1] : ""
            if !titled, heading.text == rendered.title {
                titled = true
                opening = [opening, text].filter { !$0.isEmpty }.joined(separator: " ")
                continue
            }
            if heading.text == "Contents" { continue }
            let headingWords = Set(tokens(heading.text))
            found.append(Entry(kind: kind,
                               title: page.title,
                               heading: heading.text,
                               url: page.sitePath + "#" + heading.anchor,
                               excerpt: excerpt(text),
                               words: listsWords ? tokens(text).filter { !titleWords.contains($0) && !headingWords.contains($0) } : []))
        }
        let first = Entry(kind: kind,
                          title: page.title,
                          heading: "",
                          url: page.sitePath,
                          excerpt: excerpt(opening.isEmpty ? page.summary : opening),
                          words: listsWords ? tokens(opening + " " + page.summary).filter { !titleWords.contains($0) } : [])
        return [first] + found
    }

    /// An example's entry: its name, the category it is filed under, the line
    /// its listing says about it, and the words of that line, its imports, and
    /// the comment the sketch opens with, which is where a sketch says what it
    /// is and who it is after.
    static func entry(for example: ExampleEntry, page: SiteBuilder.Page, source: String) -> Entry {
        let heading = example.group.split(separator: "/").joined(separator: " / ")
        let comment = leadingComment(of: source)
        let titleWords = Set(tokens(example.name))
        let headingWords = Set(tokens(heading))
        let about = [example.summary, example.modules.joined(separator: " "), comment].joined(separator: " ")
        return Entry(kind: "examples",
                     title: example.name,
                     heading: heading,
                     url: page.sitePath,
                     excerpt: excerpt(example.summary.isEmpty ? comment : example.summary),
                     words: tokens(about).filter { !titleWords.contains($0) && !headingWords.contains($0) })
    }

    /// The comment a sketch opens with, as one line.
    static func leadingComment(of source: String) -> String {
        var lines: [String] = []
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") {
                let text = line.drop { $0 == "/" }.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { lines.append(text) }
            } else if line.isEmpty, lines.isEmpty {
                continue
            } else {
                break
            }
        }
        return lines.joined(separator: " ")
    }

    // MARK: - Words

    /// The words of a text, lower-cased, each once, in the order they appear.
    /// A run of letters and digits is a word; a word shorter than three
    /// characters is kept only when it carries a digit (`3d`), a word with no
    /// letter in it is not a word, and a stop word is dropped.
    static func tokens(_ text: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        var current = ""
        func flush() {
            let word = current.lowercased()
            current = ""
            guard keeps(word), !seen.contains(word) else { return }
            seen.insert(word)
            found.append(word)
        }
        for character in text {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return found
    }

    static func keeps(_ word: String) -> Bool {
        guard word.contains(where: { $0.isLetter }) else { return false }
        if word.count < 3 { return word.count == 2 && word.contains(where: { $0.isNumber }) }
        return !stopWords.contains(word)
    }

    /// Words that say nothing about what a section is about.
    static let stopWords: Set<String> = Set("""
    the and for with that this from are was were been being have has had not but you your its our their they them then than when what which where who whom how why all any each every some more most other such only own same over under out into onto upon off just also both nor yet very much many few will would should could may might must does did done doing get got gets make makes made take takes took gives give given goes going come comes came way ways thing things something anything nothing everything itself himself herself themselves well like there here about after before because between through while again still too can one two three first second per via etc let use used uses using set sets put puts say says said see sees seen since until unless whether either neither rather instead once already always never often sometimes usually another others those these such
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init))

    /// The entries with the words common to more than `share` of them
    /// dropped: a word that common finds everything, and so finds nothing.
    static func pruned(_ entries: [Entry], commonAbove share: Double = commonShare) -> [Entry] {
        var frequency: [String: Int] = [:]
        for entry in entries {
            for word in entry.words { frequency[word, default: 0] += 1 }
        }
        let limit = max(1, Int((Double(entries.count) * share).rounded(.down)))
        return entries.map { entry in
            var kept = entry
            kept.words = entry.words.filter { frequency[$0, default: 0] <= limit }
            return kept
        }
    }

    // MARK: - Excerpts

    /// The first line of a text: its first sentence when that ends soon
    /// enough, otherwise the text cut at a word before the limit.
    static func excerpt(_ text: String, limit: Int = excerptLength) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !flat.isEmpty else { return "" }
        if let end = sentenceEnd(in: flat), flat.distance(from: flat.startIndex, to: end) <= limit {
            return String(flat[..<end])
        }
        if flat.count <= limit { return flat }
        let cut = flat.index(flat.startIndex, offsetBy: limit)
        let space = flat[..<cut].lastIndex(of: " ") ?? cut
        return String(flat[..<space]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")) + "…"
    }

    /// Just past the first sentence's end: a period, question mark, or
    /// exclamation mark at the end of the text, or followed by a space and
    /// then a capital, a digit, or an opening quote or bracket. A period that
    /// closes an abbreviation (`e.g.`) or a name with a dot in it (`Package.swift`)
    /// ends nothing, while a range (`0...1.`) does; a decimal (`0.5`) is
    /// followed by a digit, not a space, so it never asks.
    static func sentenceEnd(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "." || character == "!" || character == "?" {
                if next == text.endIndex { return next }
                let after = text.index(after: next)
                if text[next] == " ", after < text.endIndex, opensSentence(text[after]) {
                    let word = String(text[..<index].reversed().prefix { $0 != " " }.reversed())
                    let abbreviation = word.count <= 1 || (word.contains(".") && word.contains(where: { $0.isLetter }))
                    if character != "." || !abbreviation { return next }
                }
            }
            index = next
        }
        return nil
    }

    static func opensSentence(_ character: Character) -> Bool {
        character.isUppercase || character.isNumber || "\"“'‘([`".contains(character)
    }

    // MARK: - Writing

    /// The entries as the script the page loads: one global, so the file
    /// loads from a folder as well as from a server. A `<` is written as its
    /// escape, so no excerpt can close the script that carries it.
    static func script(_ entries: [Entry]) throws -> String {
        let objects: [[String: String]] = entries.map {
            ["k": $0.kind, "t": $0.title, "h": $0.heading, "u": $0.url, "x": $0.excerpt, "w": $0.words.joined(separator: " ")]
        }
        let data = try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys, .withoutEscapingSlashes])
        let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        return "window.ollinSearchIndex = \(json);\n"
    }
}
