import Foundation
import OllinProjects

/// One example sketch, as the reference talks about it.
public struct ExampleEntry: Sendable, Hashable, Comparable {

    /// Where it sits under `Examples`: `3D/Geometry/Ocean`.
    public let path: String

    /// The folder holding the sketch and everything it loads.
    public let directory: URL

    /// The line its category's own listing says about it. Empty when the
    /// listing has not caught up with the folder.
    public let summary: String

    /// The satellites it imports beyond the core.
    public let modules: [String]

    /// Files beside the sketch that it loads.
    public let resources: [String]

    /// The comment the sketch opens with, before its documentation: for a
    /// ported or homage sketch, the credit naming its source, author, and
    /// license. One line per comment line. Empty when the sketch has none.
    public let header: String

    public init(path: String, directory: URL, summary: String, modules: [String], resources: [String],
                header: String = "") {
        self.path = path
        self.directory = directory
        self.summary = summary
        self.modules = modules
        self.resources = resources
        self.header = header
    }

    /// The header's first line, when it reads as a credit (`Ported from`,
    /// `Inspired by`, `Recreation after`, `Based on`); `nil` for a sketch whose
    /// opening comment is its own note.
    public var credit: String? {
        guard let first = header.split(separator: "\n").first else { return nil }
        let line = String(first)
        let openings = ["Ported from", "Inspired by", "Recreation after", "Based on", "After "]
        return openings.contains { line.hasPrefix($0) } ? line : nil
    }

    public var name: String { String(path.split(separator: "/").last ?? "") }

    /// The folder it is filed under: `Motion`, or `3D/Geometry` where a
    /// category has grown a level deeper.
    public var group: String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// The executable it builds, named the way the examples package names it.
    public var target: String {
        "Example-" + path.split(separator: "/").joined(separator: "-")
    }

    public var sketch: URL { directory.appendingPathComponent("Sketch.swift") }

    public static func < (a: ExampleEntry, b: ExampleEntry) -> Bool { a.path < b.path }
}

/// The examples set, read out of a checkout.
///
/// The folders are the truth about which examples exist, and the per-category
/// listings are the truth about what each one shows. They are read separately
/// on purpose: a sketch added today is findable before anybody writes its row,
/// and it simply arrives with no line under it.
public enum ExampleCatalog {

    public static func entries(inExamples folder: URL) -> [ExampleEntry] {
        let found = ExampleSource.discover(in: folder)
        guard !found.isEmpty else { return [] }
        let lines = summaries(inExamples: folder)
        return found.map {
            ExampleEntry(path: $0.path,
                         directory: $0.directory,
                         summary: lines[$0.path.lowercased()] ?? "",
                         modules: $0.modules,
                         resources: $0.resources,
                         header: header(ofSketchAt: $0.directory.appendingPathComponent("Sketch.swift")))
        }.sorted()
    }

    /// The comment a sketch opens with: the `//` lines after its imports and
    /// before anything else, which is where a ported or homage sketch carries
    /// its credit. A `///` line is documentation and ends the block.
    static func header(ofSketchAt url: URL) -> String {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return header(in: source)
    }

    static func header(in source: String) -> String {
        var lines: [String] = []
        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("import ") {
                if lines.isEmpty { continue } else { break }
            }
            guard line.hasPrefix("//"), !line.hasPrefix("///") else { break }
            lines.append(line.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        return lines.joined(separator: "\n")
    }

    /// What each category's listing says about its sketches, keyed by
    /// lowercased example path.
    ///
    /// A row links either at the sketch file or at the folder, and a grouped
    /// category links one level deeper, so the link is resolved against the
    /// listing's own folder rather than read as text. A row linking the sketch
    /// file is the one that describes it, so it wins over a row linking the
    /// folder wherever a listing has both.
    static func summaries(inExamples folder: URL) -> [String: String] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(at: folder,
                                              includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles]) else { return [:] }
        let rootParts = folder.resolvingSymlinksInPath().standardized.pathComponents

        // Read in path order, not in whatever order the walker hands them
        // over: the first line found wins, so an unsorted walk could describe
        // a sketch differently on two runs.
        let listings = walker.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "README.md" }
            .sorted { $0.path < $1.path }

        var lines: [String: String] = [:]
        var fromSketch: Set<String> = []
        for url in listings {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let directory = url.deletingLastPathComponent()
            for (target, summary) in rows(text) {
                let resolved = directory.appendingPathComponent(target)
                    .standardized
                    .resolvingSymlinksInPath()
                var parts = resolved.pathComponents
                let linksSketch = parts.last == "Sketch.swift"
                if linksSketch { parts.removeLast() }
                guard parts.count > rootParts.count,
                      Array(parts.prefix(rootParts.count)) == rootParts else { continue }
                let path = parts.dropFirst(rootParts.count).joined(separator: "/").lowercased()
                if lines[path] == nil || (linksSketch && !fromSketch.contains(path)) {
                    lines[path] = summary
                    if linksSketch { fromSketch.insert(path) }
                }
            }
        }
        return lines
    }

    /// The rows of a listing, in either shape the listings use.
    ///
    /// A category lists its sketches as a table, `| [Name](where) | what it
    /// shows |`. The recreations list theirs as prose under the artist,
    /// `- [**Name**](where), what it shows`, because the artist is the subject
    /// there and a table would flatten that. Both are read, so neither has to
    /// change to be found. The picture grid a listing opens with names its
    /// sketches on a row of links with no words of their own (`| [A](A/) |
    /// [B](B/) |`); such a row describes nothing and is passed over, or the
    /// first sketch on it would be described by its neighbors' names.
    static func rows(_ text: String) -> [(target: String, summary: String)] {
        var found: [(String, String)] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let table = line.hasPrefix("| [")
            let list = line.hasPrefix("- [") || line.hasPrefix("* [")
            guard table || list, let link = ReferenceLibrary.firstLink(in: line) else { continue }
            guard !link.target.contains("://") else { continue }

            var summary = String(line[link.end...])
            if table {
                guard let bar = summary.firstIndex(of: "|") else { continue }
                summary = String(summary[summary.index(after: bar)...])
                if summary.hasSuffix("|") { summary.removeLast() }
                guard !isOnlyLinks(summary) else { continue }
            } else {
                // A prose row runs straight on from the link, so the joining
                // punctuation is dropped and the sentence starts where it
                // really starts.
                summary = summary.trimmingCharacters(in: .whitespaces)
                while let first = summary.first, first == "," || first == "." || first == ":" || first == "-" {
                    summary.removeFirst()
                    summary = summary.trimmingCharacters(in: .whitespaces)
                }
            }
            found.append((link.target, Markdown.plain(summary).trimmingCharacters(in: .whitespaces)))
        }
        return found
    }

    /// Whether a table's cells hold nothing but links: the grid's name row.
    static func isOnlyLinks(_ cells: String) -> Bool {
        var rest = cells
        while let link = ReferenceLibrary.firstLink(in: rest),
              let open = rest[..<link.end].lastIndex(of: "[") {
            rest.removeSubrange(open ..< link.end)
        }
        return rest.allSatisfy { $0 == "|" || $0 == " " || $0 == "\t" }
    }

    /// The examples somebody asking for `filter` meant.
    ///
    /// An exact name or path answers alone, so `Ocean` is the ocean rather
    /// than the nine sketches that mention water. Anything looser lists every
    /// sketch it fits, the ones named for the word first, then the ones whose
    /// folder, description, header credit, or imports say it, so `complex`
    /// lists the sketch called ComplexPlane and the ones described as complex
    /// arithmetic together, and an author named in a sketch's credit finds it.
    public static func matches(_ filter: String, in entries: [ExampleEntry]) -> [ExampleEntry] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        let dashed = needle.replacingOccurrences(of: "example-", with: "")
            .replacingOccurrences(of: "-", with: "/")

        let exact: [(ExampleEntry) -> Bool] = [
            { $0.path.lowercased() == needle || $0.path.lowercased() == dashed },
            { $0.name.lowercased() == needle },
        ]
        for rank in exact {
            let hits = entries.filter(rank)
            if !hits.isEmpty { return hits }
        }

        let loose: [(ExampleEntry) -> Bool] = [
            { $0.name.lowercased().hasPrefix(needle) },
            { $0.path.lowercased().contains(needle) || $0.path.lowercased().contains(dashed) },
            { $0.summary.lowercased().contains(needle) },
            { $0.header.lowercased().contains(needle) },
            { $0.modules.contains { $0.lowercased().contains(needle) } },
        ]
        var found: [ExampleEntry] = []
        var seen: Set<String> = []
        for rank in loose {
            for entry in entries where rank(entry) && !seen.contains(entry.path) {
                found.append(entry)
                seen.insert(entry.path)
            }
        }
        return found
    }
}
