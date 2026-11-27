import Foundation
import ImageIO

/// Every picture on the site says its size, and all but a page's first wait
/// until the reader is near them.
///
/// A picture with no size in its tag takes no room until its file arrives and
/// then pushes everything under it down the page, and a chapter with thirty
/// figures asks for all thirty the moment it opens. So each `<img>` a page
/// renders gains the two numbers that hold its place, and every one after the
/// first is marked to load as it comes near the screen. The first is left to
/// load at once, since it is the one most likely to be showing when the page
/// opens.
///
/// The size is the picture's own. A file in the checkout is read for it when
/// the site is built; a picture on the media host cannot be read, so its size
/// comes from the manifest's row and the name the pipeline gave it
/// (`ExampleMedia.pictureSize(at:)`). The markdown is never touched: a page
/// that writes `width="560"` keeps its width and gains the height that goes
/// with it, and a page that writes no width gets both. A picture from any
/// other host (a badge) is the one kind left as written, since nothing here
/// knows how big it is.
extension SiteBuilder {

    /// A page's body with each picture's size in its tag and all but the
    /// first marked to load late.
    func sizingPictures(in body: String, page: Page, plan: Plan, log: LinkLog) -> String {
        var out = ""
        out.reserveCapacity(body.count + 256)
        var rest = Substring(body)
        var seen = 0
        while let open = rest.range(of: "<img ") {
            guard let close = Self.tagEnd(in: rest, from: open.upperBound) else { break }
            out += rest[..<open.lowerBound]
            var tag = String(rest[open.lowerBound ..< close])
            // What is added goes inside the tag, ahead of the slash of one
            // written as closing itself.
            let closesItself = tag.hasSuffix("/")
            if closesItself { tag.removeLast() }
            while tag.hasSuffix(" ") { tag.removeLast() }
            let source = Self.attribute("src", in: tag).map(Self.unescaped) ?? ""
            if Self.attribute("height", in: tag) == nil,
               let size = pictureSize(of: source, page: page, plan: plan, log: log), size.width > 0, size.height > 0 {
                if let written = Self.attribute("width", in: tag) {
                    // The page chose a width: the height is the one that keeps
                    // the picture's own shape at it.
                    if let width = Int(written), width > 0 {
                        let height = (Double(width) * Double(size.height) / Double(size.width)).rounded()
                        tag += " height=\"\(Int(height))\""
                    }
                } else {
                    tag += " width=\"\(size.width)\" height=\"\(size.height)\""
                }
            }
            if seen > 0, Self.attribute("loading", in: tag) == nil {
                tag += " loading=\"lazy\" decoding=\"async\""
            }
            out += closesItself ? tag + " /" : tag
            seen += 1
            rest = rest[close...]
        }
        out += rest
        return out
    }

    /// How big the picture a tag names is, or nil when the site cannot know.
    func pictureSize(of source: String, page: Page, plan: Plan, log: LinkLog) -> (width: Int, height: Int)? {
        let media = plan.media
        if !media.base.isEmpty, source.hasPrefix(media.base + "/") {
            return plan.pictureSizes[ExampleMedia.unversioned(String(source.dropFirst(media.base.count + 1)))]
        }
        guard !source.isEmpty, !source.contains("://") else { return nil }
        let folder = page.siteDirectory.split(separator: "/").map(String.init)
        guard let sitePath = Self.joined(folder, String(source.prefix { $0 != "?" && $0 != "#" })),
              let repoPath = log.pictureSources[sitePath] else { return nil }
        if let known = log.pictureSizes[repoPath] { return known }
        let size = Self.pixelSize(ofPictureAt: root.appendingPathComponent(repoPath))
        log.pictureSizes[repoPath] = size ?? (0, 0)
        return size
    }

    /// A picture file's size in pixels, read from its header, or nil for a
    /// file that is not a picture the system reads.
    static func pixelSize(ofPictureAt url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// Where a tag that opens before `start` closes: the index of its `>`,
    /// stepping over any `>` written inside a quoted value.
    static func tagEnd(in text: Substring, from start: Substring.Index) -> Substring.Index? {
        var quoted = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" { quoted.toggle() }
            if character == ">", !quoted { return index }
            index = text.index(after: index)
        }
        return nil
    }

    /// One attribute's value in a tag, as written, or nil when the tag does
    /// not carry it. The name is matched whole, so `src` is not found inside
    /// `data-src`.
    static func attribute(_ name: String, in tag: String) -> String? {
        guard let found = tag.range(of: " \(name)=\"") else { return nil }
        guard let close = tag[found.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(tag[found.upperBound ..< close])
    }

    /// An attribute's value with the four characters a page escapes put back.
    static func unescaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
