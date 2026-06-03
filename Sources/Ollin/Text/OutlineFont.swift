import Foundation
import CoreGraphics
import CoreText

/// A scalable outline font — a real `.ttf`/`.otf` (TrueType or OpenType) loaded
/// from the system, a file, raw data, or a bundle. Unlike a `BitmapFont` (a fixed
/// pixel grid), an outline font stores each glyph as **vector contours**, so one
/// load draws crisply at *any* `textSize`: you never reload per size.
///
/// `drawText` renders an outline glyph as a `Shape` — the same vector fill the
/// triangulator draws — so text automatically takes the current `fill` *and*
/// `stroke`, rides the transform stack, and composites in draw order with
/// everything else. The geometry is also yours directly: `outlines(of:)` hands
/// back the glyph `Shape`s so you can warp, sample, scatter, or animate the
/// letterforms.
///
/// ```swift
/// let display = OutlineFont(name: "Futura") ?? .system
/// textFont(display)
/// textSize(160)
/// fill(.white)
/// drawText("ollin", width / 2, height / 2)
/// ```
///
/// Layout goes through Core Text (`CTLine`), so kerning, ligatures, and font
/// fallback for missing glyphs come for free.
public struct OutlineFont: @unchecked Sendable {
    /// The underlying Core Text font, created at **1 em** (point size 1) so its
    /// metrics and glyph outlines are in em units; everything scales by `textSize`
    /// at draw time. The `@unchecked Sendable` reflects that `CTFont` is
    /// thread-safe and the font is used from the single draw thread.
    let ctFont: CTFont

    /// Ascent, descent, and leading in em units (the font at size 1) — the
    /// vertical metrics layout uses to place baselines and stack lines.
    let ascent: Double
    let descent: Double
    let leading: Double

    /// A human-readable name (full name / family), for debugging and specimens.
    public let name: String

    /// Shared, lazily-filled cache of flattened glyph outlines, keyed by the run
    /// font and glyph id. A reference type so copies of the value share it.
    private let cache: GlyphPathCache

    // MARK: Construction

    /// Wrap an existing `CTFont` (assumed to be at point size 1).
    init(ctFont: CTFont) {
        self.ctFont = ctFont
        self.ascent = Double(CTFontGetAscent(ctFont))
        self.descent = Double(CTFontGetDescent(ctFont))
        self.leading = Double(CTFontGetLeading(ctFont))
        self.name = CTFontCopyFullName(ctFont) as String
        self.cache = GlyphPathCache()
    }

    /// Load an installed font by name — a family (`"Helvetica Neue"`), full name,
    /// or PostScript name. Returns `nil` if no installed font matches (so a typo
    /// fails loudly instead of silently substituting another face).
    public init?(name: String) {
        let font = CTFontCreateWithName(name as CFString, 1.0, nil)
        // CTFontCreateWithName never returns nil — an unknown name yields a
        // fallback face. Confirm the resolved font actually *is* the one asked
        // for by matching its full / family / PostScript name (loosely).
        let resolved = [
            CTFontCopyFullName(font) as String,
            (CTFontCopyName(font, kCTFontFamilyNameKey) as String?) ?? "",
            (CTFontCopyName(font, kCTFontPostScriptNameKey) as String?) ?? "",
        ]
        let wanted = OutlineFont.normalize(name)
        guard resolved.contains(where: { OutlineFont.normalize($0) == wanted }) else { return nil }
        self.init(ctFont: font)
    }

    /// Load a font from raw `.ttf`/`.otf` data — e.g. bytes you fetched or
    /// embedded. Returns `nil` if the data isn't a usable font.
    public init?(data: Data) {
        guard let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider) else { return nil }
        let font = CTFontCreateWithGraphicsFont(cgFont, 1.0, nil, nil)
        self.init(ctFont: font)
    }

    /// Load a font from a file path (a `.ttf`/`.otf` on disk).
    public init?(path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        self.init(data: data)
    }

    /// Load a font from a **file** URL. (A remote `https://` URL would need an
    /// asynchronous download and can't block the draw thread — load those in
    /// `setup()` and pass the bytes to `init(data:)`.)
    public init?(url: URL) {
        guard url.isFileURL, let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    /// Load a font bundled as a resource. Mirrors `BitmapFont(resource:in:)` —
    /// the bundle can't default to `.module` (that would resolve to Ollin's own
    /// bundle, not the caller's), so pass `in: .module` from your target.
    public init?(resource: String, in bundle: Bundle) {
        let name = (resource as NSString).deletingPathExtension
        let ext = (resource as NSString).pathExtension
        guard let url = bundle.url(forResource: name, withExtension: ext.isEmpty ? nil : ext) else { return nil }
        self.init(url: url)
    }

    /// The system UI font (San Francisco on macOS), at any size.
    public static var system: OutlineFont {
        OutlineFont(ctFont: CTFontCreateUIFontForLanguage(.system, 1.0, nil)!)
    }

    /// The bold system UI font.
    public static var systemBold: OutlineFont {
        OutlineFont(ctFont: CTFontCreateUIFontForLanguage(.emphasizedSystem, 1.0, nil)!)
    }

    /// The system monospaced font (Menlo / SF Mono lineage).
    public static var systemMono: OutlineFont {
        OutlineFont(ctFont: CTFontCreateUIFontForLanguage(.userFixedPitch, 1.0, nil)!)
    }

    /// Strip case and spaces so `"Helvetica Neue"` matches `"HelveticaNeue"`.
    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: Metrics

    /// The em-units-to-points scale for a given on-screen text size.
    func scale(for size: Double) -> Double { size }

    /// The advance width of `string`'s widest line, in points, at `size`.
    func width(of string: String, size: Double) -> Double {
        guard size > 0 else { return 0 }
        var widest = 0.0
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            widest = Swift.max(widest, layoutLine(String(line)).width)
        }
        return widest * size
    }

    // MARK: Glyph geometry

    /// The glyphs of `string`, each as a `Shape` of vector contours, positioned in
    /// Ollin canvas space (y-down) as if drawn at `origin` with `size`, `alignH`,
    /// and `alignV`. One `Shape` per glyph (a letter with a counter — `o`, `e`,
    /// `a` — keeps its hole via even-odd winding). The geometry behind `drawText`
    /// and the public `outlines(of:)`.
    func glyphShapes(for string: String, size: Double,
                     alignH: TextAlignH, alignV: TextAlignV,
                     at origin: Vector2) -> [Shape] {
        guard size > 0, !string.isEmpty else { return [] }
        let ascentP = ascent * size
        let descentP = descent * size
        let lineHeightP = (ascent + descent + leading) * size

        let rawLines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let laidOut = rawLines.map { layoutLine(String($0)) }
        let blockHeight = Double(rawLines.count - 1) * lineHeightP + ascentP + descentP

        // Top edge of the first line, from the vertical anchor.
        let topY0: Double
        switch alignV {
        case .top:      topY0 = origin.y
        case .baseline: topY0 = origin.y - ascentP
        case .middle:   topY0 = origin.y - blockHeight / 2
        case .bottom:   topY0 = origin.y - blockHeight
        }

        var shapes: [Shape] = []
        for (index, line) in laidOut.enumerated() {
            let baselineY = topY0 + Double(index) * lineHeightP + ascentP
            let lineWidth = line.width * size
            let startX: Double
            switch alignH {
            case .left:   startX = origin.x
            case .center: startX = origin.x - lineWidth / 2
            case .right:  startX = origin.x - lineWidth
            }
            for placed in line.glyphs {
                guard let path = cache.path(for: placed.glyph, font: placed.font) else { continue }
                let glyphOriginX = startX + placed.x * size
                let glyphOriginY = baselineY - placed.y * size
                let contours = OutlineFont.flatten(path, scale: size,
                                                   originX: glyphOriginX, originY: glyphOriginY)
                if !contours.isEmpty { shapes.append(Shape(contours: contours)) }
            }
        }
        return shapes
    }

    // MARK: Core Text layout

    /// One glyph placed on a line: its source font (after fallback), glyph id, pen
    /// position in em units (y-up, baseline at 0, x increasing from the line's
    /// start), and the source character's UTF-16 offset in the string.
    private struct PlacedGlyph {
        let font: CTFont; let glyph: CGGlyph; let x: Double; let y: Double; let stringIndex: Int
    }

    /// A single-line run of glyphs for per-glyph drawing and text-on-a-path: each
    /// glyph's character, pen metrics in canvas units (at `size`), and geometry in
    /// a local frame (pen origin at the origin, baseline at `y = 0`). Newlines are
    /// treated as spaces — these effects are single-line by nature.
    func glyphRun(for string: String, size: Double) -> [GlyphRunItem] {
        guard size > 0, !string.isEmpty else { return [] }
        let line = string.replacingOccurrences(of: "\n", with: " ")
        let (placed, width) = layoutLine(line)
        guard !placed.isEmpty else { return [] }

        var items: [GlyphRunItem] = []
        items.reserveCapacity(placed.count)
        for (i, g) in placed.enumerated() {
            let penX = g.x * size
            let nextX = (i + 1 < placed.count) ? placed[i + 1].x * size : width * size
            let advance = Swift.max(0, nextX - penX)
            var shapes: [Shape] = []
            if let path = cache.path(for: g.glyph, font: g.font) {
                let contours = OutlineFont.flatten(path, scale: size, originX: 0, originY: 0)
                if !contours.isEmpty { shapes = [Shape(contours: contours)] }
            }
            items.append(GlyphRunItem(character: OutlineFont.character(in: line, atUTF16: g.stringIndex),
                                      penX: penX, advance: advance, localShapes: shapes))
        }
        return items
    }

    /// The `Character` at a UTF-16 offset in `string` (a space if out of range) —
    /// maps a Core Text glyph's string index back to a Swift character.
    private static func character(in string: String, atUTF16 offset: Int) -> Character {
        let u = string.utf16
        guard offset >= 0,
              let idx = u.index(u.startIndex, offsetBy: offset, limitedBy: u.endIndex),
              idx < u.endIndex, let s = idx.samePosition(in: string) else { return " " }
        return string[s]
    }

    /// One laid-out line: its glyphs (em units) and typographic advance width (em).
    private func layoutLine(_ string: String) -> (glyphs: [PlacedGlyph], width: Double) {
        guard !string.isEmpty else { return ([], 0) }
        let attributes = [kCTFontAttributeName: ctFont] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes) else {
            return ([], 0)
        }
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)

        var glyphs: [PlacedGlyph] = []
        let runs = CTLineGetGlyphRuns(ctLine)
        for runIndex in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }

            // The run's own font (Core Text substitutes a fallback face for glyphs
            // the base font lacks — e.g. emoji in a Latin font).
            let attrs = CTRunGetAttributes(run)
            let fontPtr = CFDictionaryGetValue(attrs, Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
            let runFont = fontPtr.map { unsafeBitCast($0, to: CTFont.self) } ?? ctFont

            var gids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &gids)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for k in 0..<count {
                glyphs.append(PlacedGlyph(font: runFont, glyph: gids[k],
                                          x: Double(positions[k].x), y: Double(positions[k].y),
                                          stringIndex: indices[k]))
            }
        }
        return (glyphs, width)
    }

    /// Flatten a glyph's `CGPath` (em units, y-up, origin at the glyph's pen) into
    /// Ollin `Contour`s in canvas space: every point maps through
    /// `(gx, gy) → (originX + gx·scale, originY − gy·scale)` (the y flip turns the
    /// font's y-up into Ollin's y-down). Curves flatten through the shared
    /// `CurveSampling`, so segment density tracks the on-screen size.
    private static func flatten(_ path: CGPath, scale: Double,
                                originX: Double, originY: Double) -> [Contour] {
        func map(_ p: CGPoint) -> Vector2 {
            Vector2(originX + Double(p.x) * scale, originY - Double(p.y) * scale)
        }
        var contours: [Contour] = []
        var current: [Vector2] = []
        path.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                if current.count >= 2 { contours.append(Contour(current, closed: true)) }
                current = [map(element.points[0])]
            case .addLineToPoint:
                current.append(map(element.points[0]))
            case .addQuadCurveToPoint:
                let from = current.last ?? map(element.points[1])
                current.append(contentsOf: CurveSampling.quadratic(
                    from: from, control: map(element.points[0]), end: map(element.points[1])))
            case .addCurveToPoint:
                let from = current.last ?? map(element.points[2])
                current.append(contentsOf: CurveSampling.cubic(
                    from: from, control1: map(element.points[0]),
                    control2: map(element.points[1]), end: map(element.points[2])))
            case .closeSubpath:
                if current.count >= 2 { contours.append(Contour(current, closed: true)) }
                current = []
            @unknown default:
                break
            }
        }
        if current.count >= 2 { contours.append(Contour(current, closed: true)) }
        return contours
    }
}

/// The active text font — a bitmap (pixel-grid) or an outline (vector) face.
/// `drawText` and the text metrics dispatch on this; `textFont(_:)` sets it from
/// either a `BitmapFont` or an `OutlineFont`.
enum ActiveFont {
    case bitmap(BitmapFont)
    case outline(OutlineFont)
}

/// Per-font cache of glyph outlines. Glyph paths are created once by Core Text
/// and reused across frames. Keyed by the run font *and* glyph id, because font
/// fallback can place glyphs from several faces on one line.
private final class GlyphPathCache: @unchecked Sendable {
    private var fonts: [(font: CTFont, paths: [CGGlyph: CGPath])] = []

    /// The outline for `glyph` in `font` (em units, y-up), or `nil` for a glyph
    /// with no contours (a space). Created on first use, then cached.
    func path(for glyph: CGGlyph, font: CTFont) -> CGPath? {
        for index in fonts.indices where CFEqual(fonts[index].font, font) {
            if let cached = fonts[index].paths[glyph] { return cached }
            let created = CTFontCreatePathForGlyph(font, glyph, nil)
            if let created { fonts[index].paths[glyph] = created }
            return created
        }
        let created = CTFontCreatePathForGlyph(font, glyph, nil)
        var entry = (font: font, paths: [CGGlyph: CGPath]())
        if let created { entry.paths[glyph] = created }
        fonts.append(entry)
        return created
    }
}
