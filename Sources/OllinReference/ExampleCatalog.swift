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

    public init(path: String, directory: URL, summary: String, modules: [String], resources: [String]) {
        self.path = path
        self.directory = directory
        self.summary = summary
        self.modules = modules
        self.resources = resources
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
                         resources: $0.resources)
        }.sorted()
    }

    /// What each category's listing says about its sketches, keyed by
    /// lowercased example path.
    ///
    /// A row links either at the sketch file or at the folder, and a grouped
    /// category links one level deeper, so the link is resolved against the
    /// listing's own folder rather than read as text.
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
        for url in listings {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let directory = url.deletingLastPathComponent()
            for (target, summary) in rows(text) {
                let resolved = directory.appendingPathComponent(target)
                    .standardized
                    .resolvingSymlinksInPath()
                var parts = resolved.pathComponents
                if parts.last == "Sketch.swift" { parts.removeLast() }
                guard parts.count > rootParts.count,
                      Array(parts.prefix(rootParts.count)) == rootParts else { continue }
                let path = parts.dropFirst(rootParts.count).joined(separator: "/")
                if lines[path.lowercased()] == nil { lines[path.lowercased()] = summary }
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
    /// change to be found.
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

    /// The examples somebody asking for `filter` meant.
    ///
    /// Same shape as a page lookup: exact first, then loose, so `Ocean` is the
    /// ocean rather than the nine sketches that mention water.
    public static func matches(_ filter: String, in entries: [ExampleEntry]) -> [ExampleEntry] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        let dashed = needle.replacingOccurrences(of: "example-", with: "")
            .replacingOccurrences(of: "-", with: "/")

        let ranks: [(ExampleEntry) -> Bool] = [
            { $0.path.lowercased() == needle || $0.path.lowercased() == dashed },
            { $0.name.lowercased() == needle },
            { $0.name.lowercased().hasPrefix(needle) },
            { $0.path.lowercased().contains(needle) || $0.path.lowercased().contains(dashed) },
            { $0.summary.lowercased().contains(needle) },
            { $0.modules.contains { $0.lowercased().contains(needle) } },
        ]
        for rank in ranks {
            let hits = entries.filter(rank)
            if !hits.isEmpty { return hits }
        }
        return []
    }
}
