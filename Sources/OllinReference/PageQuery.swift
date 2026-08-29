import Foundation

/// Turning what somebody typed into a page.
///
/// A reader types the shortest thing that could work (`color`, `Drawing/Color`,
/// `spectral`), so the match runs from exact to loose and stops at the first
/// rank that finds anything. Stopping there is what keeps `color` from
/// returning the nine pages that merely mention color: an exact name beats a
/// substring, and only a tie inside one rank is ambiguous.
public enum PageQuery {

    /// What a query found.
    public enum Result: Sendable, Equatable {
        /// One page, so print it.
        case one(ReferencePage)
        /// Several equally good pages, so ask which.
        case several([ReferencePage])
        /// Nothing by name, so the caller falls back to searching the text.
        case none
    }

    /// The ranks, best first. Each is tried against every page before the next.
    static let ranks: [@Sendable (String, ReferencePage) -> Bool] = [
        { query, page in page.topic.lowercased() == query },
        { query, page in page.name.lowercased() == query },
        { query, page in page.title.lowercased() == query },
        { query, page in page.name.lowercased().hasPrefix(query) },
        { query, page in page.title.lowercased().hasPrefix(query) },
        { query, page in page.topic.lowercased().contains(query) },
        { query, page in page.title.lowercased().contains(query) },
        { query, page in page.summary.lowercased().contains(query) },
    ]

    public static func resolve(_ query: String, in pages: [ReferencePage]) -> Result {
        let needle = query
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".md", with: "")
            .lowercased()
        guard !needle.isEmpty else { return .none }
        for rank in ranks {
            let hits = pages.filter { rank(needle, $0) }
            if hits.count == 1 { return .one(hits[0]) }
            if hits.count > 1 { return .several(hits) }
        }
        return .none
    }
}
