import Foundation

/// One place a word appears in the reference.
public struct SearchHit: Sendable, Equatable {
    public let page: ReferencePage
    /// Line number in the file, so the hit can be looked at in an editor.
    public let line: Int
    /// The heading the line sits under, which is what makes a hit readable.
    public let section: String
    public let text: String

    public init(page: ReferencePage, line: Int, section: String, text: String) {
        self.page = page
        self.line = line
        self.section = section
        self.text = text
    }
}

/// Reading the whole reference for a word.
///
/// This is what answers the question a page lookup cannot: the reader knows
/// what they want to do and not what it is called. It runs over the files in
/// the checkout, so it needs no index and cannot go stale.
public enum ReferenceSearch {

    public static func hits(for query: String,
                            in pages: [ReferencePage],
                            perPage: Int = 3,
                            limit: Int = 40) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }

        // A page whose own name carries the word is the likeliest answer, so
        // it is read first and its hits come out on top.
        let ordered = pages.sorted { a, b in
            let left = a.name.lowercased().contains(needle) || a.title.lowercased().contains(needle)
            let right = b.name.lowercased().contains(needle) || b.title.lowercased().contains(needle)
            if left != right { return left }
            return a.topic < b.topic
        }

        var found: [SearchHit] = []
        for page in ordered {
            guard found.count < limit else { break }
            guard let text = try? String(contentsOf: page.url, encoding: .utf8) else { continue }
            var section = ""
            var taken = 0
            for (number, rawLine) in text.components(separatedBy: "\n").enumerated() {
                if rawLine.hasPrefix("#") {
                    let level = rawLine.prefix { $0 == "#" }.count
                    if level >= 2 {
                        section = Markdown.plain(String(rawLine.dropFirst(level)))
                            .trimmingCharacters(in: .whitespaces)
                    }
                    continue
                }
                guard taken < perPage, found.count < limit else { continue }
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, line.lowercased().contains(needle) else { continue }
                found.append(SearchHit(page: page, line: number + 1, section: section, text: line))
                taken += 1
            }
        }
        return found
    }
}
