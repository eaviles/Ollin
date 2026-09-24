import Foundation

/// One place a public name is written: a section of a reference page, or a
/// line of an example.
public struct APIMention: Sendable, Equatable {
    /// A page's topic (`Drawing/Color`) or an example's sketch, relative to
    /// the checkout.
    public let place: String
    /// The heading it sits under on a page; empty for an example.
    public let heading: String
    public let line: Int
    public let text: String

    /// What `ollin docs` takes to open the section, `Drawing/Color#ramps`,
    /// with the heading as a slug so it needs no quoting; an example's
    /// `path:line`.
    public var address: String {
        if place.hasSuffix(".swift") { return "\(place):\(line)" }
        guard !heading.isEmpty else { return place }
        return place + "#" + Markdown.anchor(heading).replacingOccurrences(of: " ", with: "-")
    }
}

/// How a name is written where it is used.
public enum APIReach: Sendable {
    /// A type: the word on its own.
    case type
    /// Something on a type other than `Sketch`: reached with a dot,
    /// `.tube(` or `Mesh.tube(`.
    case member
    /// Called bare, the way a sketch calls its own members and the top-level
    /// functions: the word on its own, but never as an argument label.
    case bare
}

/// The reference pages and the example sketches, read once so a lookup that
/// asks about several types reads each file one time.
public struct UsageCorpus: Sendable {
    public let root: URL
    public let pages: [(page: ReferencePage, text: String)]
    public let examples: [(entry: ExampleEntry, text: String)]

    public init(root: URL) {
        self.root = root
        pages = ReferenceLibrary.pages(inDocs: root.appendingPathComponent("Docs")).compactMap { page in
            (try? String(contentsOf: page.url, encoding: .utf8)).map { (page, $0) }
        }
        examples = ExampleCatalog.entries(inExamples: root.appendingPathComponent("Examples")).compactMap { entry in
            (try? String(contentsOf: entry.sketch, encoding: .utf8)).map { (entry, $0) }
        }
    }
}

/// Where a public name is documented, and which examples use it.
///
/// Both read the checkout as it stands, the way the rest of the reference
/// does, so there is no index to fall out of date. A name counts only where
/// it is written as code (a fence, a code span, a heading), because that is
/// where a page spells a name rather than using the word.
public enum APIUsage {

    /// The pages that document a name, the likeliest first.
    ///
    /// A page with the name in a heading is taken to be about it. After that
    /// the page naming the type it sits on as well, then the page that writes
    /// it most. `owners` are the types the name was found on, and a member of
    /// `Sketch` is called bare, so `Sketch` is left out of them.
    public static func pages(naming name: String,
                             reach: APIReach,
                             owners: [String],
                             in corpus: UsageCorpus,
                             limit: Int = 3) -> [APIMention] {
        var scored: [(score: Int, mention: APIMention)] = []
        let owners = owners.filter { $0 != "Sketch" && $0 != name }
        for (page, text) in corpus.pages where text.contains(name) {
            var heading = ""
            var fenced = false
            // A fence of shell commands or printed output shows a call being
            // looked up, not used: only code counts.
            var fenceIsCode = false
            var first: APIMention?
            var titled: APIMention?
            var count = 0
            var namesOwner = owners.isEmpty
            for (number, line) in text.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    fenced.toggle()
                    let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    fenceIsCode = ["", "swift", "metal"].contains(language)
                    continue
                }
                var code: String
                if fenced {
                    guard fenceIsCode else { continue }
                    code = line
                } else if trimmed.hasPrefix("#") {
                    // The breadcrumb over every page is a heading in form only.
                    if trimmed.contains("<sup>") { continue }
                    let level = trimmed.prefix { $0 == "#" }.count
                    let words = String(trimmed.dropFirst(level))
                    if level >= 2 { heading = Markdown.plain(words).trimmingCharacters(in: .whitespaces) }
                    // A heading names a thing in its code, or by being
                    // nothing but the name: "A blown tube" is about sound.
                    code = spans(in: words)
                    if code.isEmpty, !heading.contains(" ") { code = heading }
                    if level >= 2, titled == nil, mentions(name, in: code, reach: reach) {
                        titled = APIMention(place: page.topic, heading: heading, line: number + 1, text: heading)
                    }
                } else {
                    code = spans(in: line)
                }
                if !namesOwner, owners.contains(where: { mentions($0, in: code, reach: .type) }) { namesOwner = true }
                guard mentions(name, in: code, reach: reach) else { continue }
                count += 1
                // A page's contents list names everything once; the section
                // the list points at is the one to open.
                if first == nil, heading != "Contents" {
                    first = APIMention(place: page.topic, heading: heading, line: number + 1,
                                       text: trimmed)
                }
            }
            guard let best = titled ?? first else { continue }
            let named = page.name == name || owners.contains(page.name)
            let score = (titled != nil ? 10000 : 0) + (named ? 5000 : 0) + (namesOwner ? 1000 : 0) + min(count, 999)
            scored.append((score, best))
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.mention.place < $1.mention.place }
            .prefix(limit).map(\.mention)
    }

    /// Examples that use a name, the shortest sketch first, since the
    /// shortest is the one that shows it with the least around it.
    public static func examples(using name: String,
                                reach: APIReach,
                                in corpus: UsageCorpus,
                                limit: Int = 3) -> [APIMention] {
        var found: [(length: Int, mention: APIMention)] = []
        let root = corpus.root
        for (entry, text) in corpus.examples where text.contains(name) {
            let lines = text.components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                var inString = false
                let code = SourceComments.codePart(of: line, inString: &inString)
                guard mentions(name, in: code, reach: reach) else { continue }
                found.append((lines.count, APIMention(place: relative(entry.sketch, to: root), heading: "",
                                                      line: number + 1, text: trimmed)))
                break
            }
        }
        return found
            .sorted { $0.length != $1.length ? $0.length < $1.length : $0.mention.place < $1.mention.place }
            .prefix(limit).map(\.mention)
    }

    /// The code spans of a line of prose, joined.
    static func spans(in line: String) -> String {
        let parts = line.components(separatedBy: "`")
        guard parts.count > 2 else { return "" }
        return stride(from: 1, to: parts.count - 1, by: 2).map { parts[$0] }.joined(separator: " ")
    }

    /// Whether code writes the name the way it is reached: a word of its own
    /// rather than inside a longer one, and then as `reach` says. Being code
    /// already rules out the name used as an ordinary word.
    static func mentions(_ name: String, in code: String, reach: APIReach) -> Bool {
        var searched = code[...]
        while let range = searched.range(of: name) {
            let before = range.lowerBound > code.startIndex ? code[code.index(before: range.lowerBound)] : " "
            let after = range.upperBound < code.endIndex ? code[range.upperBound] : " "
            if !isWordCharacter(before), !isWordCharacter(after) {
                switch reach {
                case .type: return true
                // `self.rotate(` is the sketch's own call, not a member of
                // another type reached with a dot.
                case .member:
                    if before == ".", !code[..<range.lowerBound].hasSuffix("self.") { return true }
                case .bare: if after != ":" { return true }
                }
            }
            searched = code[range.upperBound...]
        }
        return false
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    static func relative(_ url: URL, to root: URL) -> String {
        let parts = url.standardized.resolvingSymlinksInPath().pathComponents
        let rootParts = root.standardized.resolvingSymlinksInPath().pathComponents
        guard parts.count > rootParts.count,
              Array(parts.prefix(rootParts.count)) == rootParts else { return url.path }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }
}
