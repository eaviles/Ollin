import Foundation

/// The logo, as the site wears it.
///
/// The drawings live in `Logo/` at the root of the checkout: two masters,
/// the full mark and the small form, each black ink on nothing and nothing
/// else (no size, no color of its own, no id). The site reads them at build
/// time rather than carrying a copy, so the mark on the site is the mark in
/// the repository, and it sets the color itself, in one of three ways:
///
/// - `inline` puts a drawing in a page with its ink as `currentColor`, so
///   the bar's mark takes the page's own text color and one file serves the
///   light scheme and the dark one.
/// - `colored` writes a drawing in one color, for a place that cannot pass
///   one in: the README's dark twin on GitHub, where the picture is an image.
/// - `tiled` puts a drawing in one color on a square tile of another, which
///   is the favicon: a tab bar is whatever color the browser makes it, so
///   the icon carries its own ground.
///
/// The bar wears the full mark. The small form (heavier lines, four dots in
/// place of the satellites) is for the places that show the logo at icon
/// size: the favicon and Safari's pinned-tab icon, which is the one that
/// reads at 16 px. Two pictures the site cannot draw from the masters at
/// build time, since they have to be bitmaps, are written by `Scripts/logo.sh`
/// beside them and copied in: the social card a link preview shows, and the
/// touch icon a phone puts on its home screen, both the full mark in paper on
/// an ink tile.
enum SiteLogo {

    /// The full mark, ink on nothing.
    static let mark = "Logo/ollin-mark.svg"
    /// The small form, ink on nothing.
    static let small = "Logo/ollin-favicon.svg"
    /// The social card, 1200 by 630, the full mark in paper on an ink tile.
    static let socialCard = "Logo/ollin-social.png"
    /// The touch icon, 180 by 180, the same on a square tile.
    static let touchIcon = "Logo/ollin-touch.png"

    /// The site's ink and paper, which the favicon is drawn in.
    static let ink = "#0B0F14"
    static let paper = "#F4F3F0"

    /// The black a master is drawn in, when an export left it written out.
    /// Black is the default fill, so dropping it changes nothing on its own,
    /// and it lets a color set on the root reach every shape.
    private static let writtenBlacks = [" fill=\"#000000\"", " fill=\"#000\"", " fill=\"black\""]

    /// One of the drawings, read from the checkout, or nil when the file is
    /// not there (the build notes it).
    static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// One of the drawings, read from the checkout and inlined for a page,
    /// or empty when the file is not there.
    static func inline(readingAt url: URL, className: String) -> String {
        guard let svg = read(url) else { return "" }
        return inline(svg, className: className)
    }

    /// A drawing inlined for a page: its ink as `currentColor`, the root tag
    /// carrying the class, the namespace dropped (HTML knows the element),
    /// the layout closed up, and the element hidden from assistive
    /// technology, since the name beside it says what it is.
    static func inline(_ svg: String, className: String) -> String {
        rewrite(svg, compact: true, namespace: false,
                leading: " class=\"\(className)\" aria-hidden=\"true\" focusable=\"false\"",
                trailing: " fill=\"currentColor\"")
    }

    /// A drawing in one color, as a file: the master with the color set on
    /// its root, its layout kept, so the twin reads like the master beside it.
    static func colored(_ svg: String, ink: String) -> String {
        rewrite(svg, compact: false, namespace: true, trailing: " fill=\"\(ink)\"")
    }

    /// A drawing in one color on a square tile of another, as a file. The
    /// tile fills the viewport whatever the box, so it needs no numbers.
    static func tiled(_ svg: String, ink: String, tile: String) -> String {
        rewrite(svg, compact: false, namespace: true, trailing: " fill=\"\(ink)\"",
                afterRoot: "\n  <rect width=\"100%\" height=\"100%\" fill=\"\(tile)\"/>")
    }

    /// The drawing with its root tag rewritten: `leading` attributes right
    /// after `svg`, `trailing` ones at the end, the namespace kept or not,
    /// `afterRoot` placed as the first child, and any written-out black
    /// dropped from the shapes. Anything before the root tag (an XML prolog)
    /// goes. Empty when the text holds no root tag.
    private static func rewrite(_ svg: String, compact: Bool, namespace: Bool,
                                leading: String = "", trailing: String = "", afterRoot: String = "") -> String {
        let text = compact ? compacted(svg) : svg
        guard let open = text.range(of: "<svg"), let close = text[open.upperBound...].firstIndex(of: ">") else { return "" }
        var attributes = String(text[open.upperBound ..< close])
        if !namespace {
            attributes = attributes.replacingOccurrences(of: " xmlns=\"http://www.w3.org/2000/svg\"", with: "")
        }
        var body = String(text[text.index(after: close)...])
        for black in writtenBlacks {
            body = body.replacingOccurrences(of: black, with: "")
        }
        return "<svg" + leading + attributes + trailing + ">" + afterRoot + body
    }

    /// The text with its indentation and blank lines gone, for a page.
    private static func compacted(_ svg: String) -> String {
        svg.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
