import Foundation

/// The logo, as the site wears it.
///
/// The drawings live in `Logo/` at the root of the checkout, ink on nothing,
/// and the site reads them at build time rather than carrying a copy, so the
/// mark on the site is the mark in the repository. The favicon is
/// `ollin-favicon.svg` as it is: the small form on its tile. The mark in the
/// bar and the one on the front page are the same drawings inlined with
/// their ink turned into `currentColor`, so one file serves the light scheme
/// and the dark one and the mark takes the page's own text color wherever
/// it sits. The bar wears the small form (the favicon's glyph without its
/// tile: heavier strokes and no satellites), which is the one that reads at
/// 16 px; the front page wears the full mark.
enum SiteLogo {

    /// The full mark, ink on nothing.
    static let mark = "Logo/ollin-mark.svg"
    /// The small form on its dark tile, which is the favicon.
    static let favicon = "Logo/ollin-favicon.svg"

    /// The colors the files are drawn in, which the inline forms replace.
    static let ink = "#0B0F14"
    static let paper = "#F4F3F0"

    /// One of the drawings, read from the checkout and inlined for a page,
    /// or empty when the file is not there (the build notes it).
    static func inline(readingAt url: URL, id: String, className: String) -> String {
        guard let svg = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return inline(svg, id: id, className: className)
    }

    /// A drawing inlined for a page: its tile dropped, its ink and paper as
    /// `currentColor`, its mask named after `id` so two marks on one page
    /// keep their own, and the element hidden from assistive technology,
    /// since the name beside it says what it is.
    static func inline(_ svg: String, id: String, className: String) -> String {
        var lines: [String] = []
        for line in svg.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // The tile is the one full-size rectangle outside the mask.
            if trimmed.hasPrefix("<rect width=\"100\" height=\"100\" fill=\"#") { continue }
            if trimmed.isEmpty { continue }
            lines.append(trimmed)
        }
        var out = lines.joined(separator: "\n")
        out = out.replacingOccurrences(of: ink, with: "currentColor")
        out = out.replacingOccurrences(of: paper, with: "currentColor")
        out = out.replacingOccurrences(of: "id=\"eye\"", with: "id=\"\(id)\"")
        out = out.replacingOccurrences(of: "url(#eye)", with: "url(#\(id))")
        out = out.replacingOccurrences(of: "<svg xmlns=\"http://www.w3.org/2000/svg\"",
                                       with: "<svg class=\"\(className)\" aria-hidden=\"true\" focusable=\"false\"")
        return out
    }
}
