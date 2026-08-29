import Foundation

/// One page of the written reference.
///
/// A page is a file under `Docs`, and the index beside it (`Docs/README.md`)
/// says which heading it is filed under and what it is for. Both halves are
/// read: the file is the content, the index is the catalog. A page the index
/// has not listed is still a page, so a new file is reachable the moment it
/// exists rather than the moment somebody remembers to list it.
public struct ReferencePage: Sendable, Hashable, Comparable {

    /// Where the page sits under `Docs`, without its extension: `Drawing/Color`.
    public let topic: String

    /// The file itself.
    public let url: URL

    /// The page's own heading, which is the name a reader knows it by.
    public let title: String

    /// The heading it is filed under in the index, or its folder if the index
    /// does not list it.
    public let group: String

    /// The one line the index says about it. Empty when the index omits it.
    public let summary: String

    public init(topic: String, url: URL, title: String, group: String, summary: String) {
        self.topic = topic
        self.url = url
        self.title = title
        self.group = group
        self.summary = summary
    }

    /// The last component of the topic: `Color` for `Drawing/Color`.
    public var name: String { String(topic.split(separator: "/").last ?? "") }

    public static func < (a: ReferencePage, b: ReferencePage) -> Bool { a.topic < b.topic }
}

/// The written reference, read out of a checkout.
public enum ReferenceLibrary {

    /// Every page under `docs`, in topic order so two runs agree.
    ///
    /// The per-folder `README.md` files are the folder indexes rather than
    /// reference pages, so they are left out: a reader asking for `Drawing`
    /// wants the pages, and the listing already shows them.
    public static func pages(inDocs docs: URL) -> [ReferencePage] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(at: docs,
                                              includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles]) else { return [] }

        // Compared as path components after resolving symlinks, for the reason
        // the example walker states: a folder handed in as /var/... walks out
        // as /private/var/..., and a string prefix test then matches nothing.
        let rootParts = docs.resolvingSymlinksInPath().standardized.pathComponents

        let catalog = index(readingIndexAt: docs.appendingPathComponent("README.md"))

        var found: [ReferencePage] = []
        for case let url as URL in walker where url.pathExtension == "md" {
            guard url.lastPathComponent != "README.md" else { continue }
            let parts = url.resolvingSymlinksInPath().standardized.pathComponents
            guard parts.count > rootParts.count,
                  Array(parts.prefix(rootParts.count)) == rootParts else { continue }
            let topic = parts.dropFirst(rootParts.count)
                .joined(separator: "/")
                .replacingOccurrences(of: ".md", with: "")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let listed = catalog[topic.lowercased()]
            let folder = topic.split(separator: "/").dropLast().joined(separator: "/")
            found.append(ReferencePage(
                topic: topic,
                url: url,
                title: title(of: text) ?? String(topic.split(separator: "/").last ?? ""),
                group: listed?.group ?? (folder.isEmpty ? "Ollin" : folder),
                summary: listed?.summary ?? ""
            ))
        }
        return found.sorted()
    }

    /// The headings the index files pages under, in the order it uses them.
    ///
    /// The order carries meaning that alphabetical order loses: the index
    /// opens on the concepts and closes on the tools, which is roughly the
    /// order somebody meets them.
    public static func groups(inDocs docs: URL) -> [String] {
        guard let text = try? String(contentsOf: docs.appendingPathComponent("README.md"),
                                     encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("### ") else { return nil }
            return Markdown.plain(String(line.dropFirst(4))).trimmingCharacters(in: .whitespaces)
        }
    }

    /// The page's own heading.
    ///
    /// Both spellings are in the tree: most pages open on a breadcrumb and a
    /// `##` title, and some open on a plain `#` one. Either is the title, and
    /// the deeper headings under them are not.
    static func title(of markdown: String) -> String? {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("#") else { continue }
            let level = line.prefix { $0 == "#" }.count
            guard level <= 2 else { continue }
            let text = Markdown.plain(String(line.dropFirst(level))).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// What the index says about each page, keyed by lowercased topic.
    ///
    /// The index lines look like ``- [`Color`](./Drawing/Color.md) - the Color
    /// type, ...`` under a `### Drawing` heading, so the heading gives the
    /// group and the text after the link gives the summary.
    static func index(readingIndexAt url: URL) -> [String: (group: String, summary: String)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return index(text)
    }

    static func index(_ text: String) -> [String: (group: String, summary: String)] {
        var catalog: [String: (group: String, summary: String)] = [:]
        var group = ""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("### ") {
                group = Markdown.plain(String(line.dropFirst(4))).trimmingCharacters(in: .whitespaces)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ["), let link = firstLink(in: trimmed) else { continue }
            guard link.target.hasSuffix(".md") else { continue }
            let topic = link.target
                .replacingOccurrences(of: "./", with: "")
                .replacingOccurrences(of: ".md", with: "")
            guard !topic.hasPrefix("..") else { continue }
            var summary = String(trimmed[link.end...])
            if let dash = summary.range(of: " - ") {
                summary = String(summary[dash.upperBound...])
            }
            catalog[topic.lowercased()] = (group, summary.trimmingCharacters(in: .whitespaces))
        }
        return catalog
    }

    /// The first markdown link in a line: its target, and where it ends.
    static func firstLink(in line: String) -> (target: String, end: String.Index)? {
        guard let open = line.range(of: "](") else { return nil }
        guard let close = line[open.upperBound...].firstIndex(of: ")") else { return nil }
        return (String(line[open.upperBound ..< close]), line.index(after: close))
    }
}
