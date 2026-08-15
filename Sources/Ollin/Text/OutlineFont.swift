import Foundation
import CoreGraphics
import CoreText
import os

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

    /// Shared, lazily-filled cache of flattened + triangulated glyph geometry at a
    /// given size (the per-frame cost of redrawing static text). Also a reference
    /// type so copies of the value share it.
    private let geometryCache: GlyphGeometryCache

    /// Shared, lazily-filled SDF atlas for the `textMode(.atlas)` volume path —
    /// each glyph rasterized once into a distance field and drawn as a textured
    /// quad. A reference type so value copies share it (like the caches above).
    let atlas: GlyphAtlas

    /// Shared, lazily-filled cache of the glyphs a font draws as pictures rather
    /// than outlines (emoji). Another reference type shared by value copies.
    let colorGlyphs: ColorGlyphCache

    // MARK: Construction

    /// Wrap an existing `CTFont` (assumed to be at point size 1).
    init(ctFont: CTFont) {
        self.ctFont = ctFont
        self.ascent = Double(CTFontGetAscent(ctFont))
        self.descent = Double(CTFontGetDescent(ctFont))
        self.leading = Double(CTFontGetLeading(ctFont))
        self.name = CTFontCopyFullName(ctFont) as String
        self.cache = GlyphPathCache()
        self.geometryCache = GlyphGeometryCache()
        self.atlas = GlyphAtlas()
        self.colorGlyphs = ColorGlyphCache()
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

    // The system faces are `static let` so every user of one shares a single
    // instance — and with it the glyph/geometry caches (reference types the
    // copies share), which matters for anything drawing text every frame.

    /// The system UI font (San Francisco on macOS), at any size.
    public static let system = OutlineFont(ctFont: CTFontCreateUIFontForLanguage(.system, 1.0, nil)!)

    /// The medium-weight system UI font — the default text font (`drawText`
    /// with no `textFont` set), a touch sturdier than the regular weight so
    /// text holds up over busy canvases.
    public static let systemMedium: OutlineFont = {
        let base = CTFontCreateUIFontForLanguage(.system, 1.0, nil)!
        let traits = [kCTFontWeightTrait as String: 0.23] as CFDictionary   // medium
        let attributes = [kCTFontTraitsAttribute as String: traits] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
        return OutlineFont(ctFont: CTFontCreateCopyWithAttributes(base, 1.0, nil, descriptor))
    }()

    /// The bold system UI font.
    public static let systemBold = OutlineFont(ctFont: CTFontCreateUIFontForLanguage(.emphasizedSystem, 1.0, nil)!)

    /// The system monospaced font (Menlo / SF Mono lineage).
    public static let systemMono = OutlineFont(ctFont: CTFontCreateUIFontForLanguage(.userFixedPitch, 1.0, nil)!)

    /// Strip case and spaces so `"Helvetica Neue"` matches `"HelveticaNeue"`.
    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: Variable fonts

    /// A copy of this font with **variation axes** set — for a variable font, the
    /// continuous design axes (weight, width, optical size, slant, …). Keys are the
    /// 4-character axis tags; values are in the font's own axis units (a variable
    /// font's ranges are font-specific, so query the font's specimen or use
    /// `variationAxes`). Non-variable fonts ignore it.
    ///
    /// ```swift
    /// let skia = OutlineFont(name: "Skia")!
    /// textFont(skia.variation(["wght": 2.6, "wdth": 1.2]))   // heavy, a touch wide
    /// ```
    public func variation(_ axes: [String: Double]) -> OutlineFont {
        guard !axes.isEmpty else { return self }
        var settings: [NSNumber: NSNumber] = [:]
        for (tag, value) in axes {
            settings[NSNumber(value: OutlineFont.fourCharCode(tag))] = NSNumber(value: value)
        }
        let attributes = [kCTFontVariationAttribute as String: settings] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
        return OutlineFont(ctFont: CTFontCreateCopyWithAttributes(ctFont, 1.0, nil, descriptor))
    }

    /// A copy with the weight axis (`wght`) set. Convenience for one axis; combine
    /// several in one call with `variation(_:)` so they don't reset each other.
    public func weight(_ value: Double) -> OutlineFont { variation(["wght": value]) }
    /// A copy with the width axis (`wdth`) set.
    public func width(_ value: Double) -> OutlineFont { variation(["wdth": value]) }
    /// A copy with the optical-size axis (`opsz`) set.
    public func opticalSize(_ value: Double) -> OutlineFont { variation(["opsz": value]) }
    /// A copy with the slant axis (`slnt`) set.
    public func slant(_ value: Double) -> OutlineFont { variation(["slnt": value]) }

    /// The font's variation axes — `(tag, name, min, max, default)` per axis, empty
    /// for a non-variable font. Use it to discover what a font exposes and its
    /// ranges.
    public var variationAxes: [(tag: String, name: String, min: Double, max: Double, default: Double)] {
        guard let raw = CTFontCopyVariationAxes(ctFont) as? [[String: Any]] else { return [] }
        return raw.map { axis in
            let id = (axis[kCTFontVariationAxisIdentifierKey as String] as? Int) ?? 0
            var tag = ""
            for shift in [24, 16, 8, 0] { tag.append(Character(UnicodeScalar(UInt8((id >> shift) & 0xFF)))) }
            return (tag: tag,
                    name: (axis[kCTFontVariationAxisNameKey as String] as? String) ?? "",
                    min: (axis[kCTFontVariationAxisMinimumValueKey as String] as? Double) ?? 0,
                    max: (axis[kCTFontVariationAxisMaximumValueKey as String] as? Double) ?? 0,
                    default: (axis[kCTFontVariationAxisDefaultValueKey as String] as? Double) ?? 0)
        }
    }

    /// Pack a 4-character axis tag (`"wght"`) into the integer id Core Text uses.
    private static func fourCharCode(_ tag: String) -> Int {
        var code = 0
        for byte in tag.utf8.prefix(4) { code = (code << 8) | Int(byte) }
        return code
    }

    // MARK: Metrics

    /// The em-units-to-points scale for a given on-screen text size.
    func scale(for size: Double) -> Double { size }

    /// The advance width of `string`'s widest line, in points, at `size`.
    func width(of string: String, size: Double, direction: TextDirection) -> Double {
        guard size > 0 else { return 0 }
        var widest = 0.0
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            widest = Swift.max(widest, layoutLine(String(line), direction: direction).width)
        }
        return widest * size
    }

    // MARK: What the font could and did draw

    /// The names of the faces that actually drew `string`.
    ///
    /// Asking a Latin font for Japanese does not fail: the system quietly borrows a
    /// face that has the letters, which is why text in any script draws at all.
    /// This is how to see that happening, and which faces a line really used.
    ///
    /// ```swift
    /// print(font.fontsUsed(for: "Ollin 日本語 👋"))
    /// // ["System Font Regular", ".PingFang UI Text SC Regular Text", ".Apple Color Emoji UI"]
    /// ```
    public func fontsUsed(for string: String) -> [String] {
        var names: [String] = []
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            for glyph in layoutLine(String(line), direction: .automatic).glyphs {
                let name = CTFontCopyFullName(glyph.font) as String
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// The characters in `string` that no font on this machine can draw, in the
    /// order they appear.
    ///
    /// A character nobody can draw is not dropped. It lands on the system's last
    /// resort face, which draws a box, so it is visible rather than silently
    /// missing. Ask this when you want to know before drawing.
    public func missingCharacters(in string: String) -> [Character] {
        var missing: [Character] = []
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            let glyphs = layoutLine(text, direction: .automatic).glyphs
            for cluster in TextClusters.group(glyphs, in: text) {
                guard cluster.glyphs.contains(where: OutlineFont.isUndrawable) else { continue }
                missing.append(contentsOf: cluster.text)
            }
        }
        return missing
    }

    /// Whether a shaped glyph stands for a character nothing could draw: either the
    /// font's own "no such glyph" id, or a glyph from the last resort face, which
    /// exists only to draw a box where a character should have been.
    private static func isUndrawable(_ glyph: ShapedGlyph) -> Bool {
        if glyph.glyph == 0 { return true }
        let name = (CTFontCopyPostScriptName(glyph.font) as String)
        return name.hasSuffix("LastResort")
    }

    // MARK: Glyph geometry

    /// One glyph placed for drawing: where its pen origin lands in canvas space,
    /// plus its cached *local* geometry — flattened contours and triangulated fill
    /// with the pen at the origin. The caller translates by `origin` to place it.
    /// Flattening and triangulating are the per-frame cost of outline text, so
    /// caching them (keyed by font/glyph/size) turns a redrawn label into a
    /// translate of cached vertices.
    struct PlacedGlyphGeometry {
        let origin: Vector2
        let localContours: [Contour]
        let localFill: [Vector2]
        /// Set for a glyph the font stores as a picture rather than an outline (an
        /// emoji): the rasterized image and the canvas rect it covers. The contours
        /// and fill are empty in that case.
        let picture: Image?
        let pictureRect: Rectangle
    }

    /// The glyphs of `string`, each placed (origin + cached local geometry) as if
    /// drawn at `origin` with `size`, `alignH`, and `alignV`. The shared layout
    /// behind `drawText`'s fast fill path and `glyphShapes`. Glyphs with neither
    /// contours nor a picture (spaces) are skipped.
    func placedGlyphs(for string: String, size: Double,
                      alignH: TextAlignH, alignV: TextAlignV,
                      direction: TextDirection,
                      justify: TextJustification? = nil,
                      hangs: Bool = false,
                      at origin: Vector2) -> [PlacedGlyphGeometry] {
        guard size > 0, !string.isEmpty else { return [] }
        let laidOut = layoutBlock(string, size: size, direction: direction,
                                  justify: justify, hangs: hangs)
        let starts = lineStarts(extents: laidOut.map { ($0.width - $0.hang) * size }, size: size,
                                alignH: alignH, alignV: alignV,
                                direction: direction, at: origin)
        let turned = direction.turnsGlyphs

        var placedGlyphs: [PlacedGlyphGeometry] = []
        for (index, line) in laidOut.enumerated() {
            let start = starts[index]
            for placed in line.glyphs {
                let pen = OutlineFont.penOrigin(placed, start: start, size: size, turned: turned)
                let glyphOriginX = pen.x
                let glyphOriginY = pen.y
                let local = geometry(for: placed.glyph, font: placed.font, size: size, turned: turned)
                if local.contours.isEmpty {
                    // No outline: either a glyph the font draws as a picture, or
                    // something with no ink at all (a space).
                    guard let color = colorGlyphs.glyph(placed.glyph, font: placed.font) else { continue }
                    let box = OutlineFont.pictureRect(color.emRect, size: size, turned: turned)
                    placedGlyphs.append(PlacedGlyphGeometry(
                        origin: Vector2(glyphOriginX, glyphOriginY),
                        localContours: [], localFill: [],
                        picture: color.image,
                        pictureRect: Rectangle(x: glyphOriginX + box.x, y: glyphOriginY + box.y,
                                               width: box.width, height: box.height)))
                    continue
                }
                placedGlyphs.append(PlacedGlyphGeometry(
                    origin: Vector2(glyphOriginX, glyphOriginY),
                    localContours: local.contours, localFill: local.fill,
                    picture: nil, pictureRect: Rectangle(x: 0, y: 0, width: 0, height: 0)))
            }
        }
        return placedGlyphs
    }

    /// One glyph placed for the SDF-atlas path: its pen origin in canvas space and
    /// the source glyph id + run font (after fallback) the atlas keys its slot on.
    /// Lighter than `PlacedGlyphGeometry` — no flatten or triangulation, since the
    /// atlas path draws a textured quad rather than a vector fill.
    struct PlacedAtlasGlyph {
        let origin: Vector2
        let glyph: CGGlyph
        let font: CTFont
        /// Set where the column turns its glyphs: the quad the drawer builds from
        /// the atlas slot takes the same quarter turn clockwise about this origin.
        let turned: Bool
    }

    /// The glyphs of `string`, each placed (pen origin + glyph id/font) as if drawn
    /// at `origin` with `size`, `alignH`, and `alignV` — the layout behind the
    /// `textMode(.atlas)` fast path. Same line/alignment math as `placedGlyphs`,
    /// without building any geometry; the drawer turns each into a quad sampling
    /// the atlas. Spaces are kept (the atlas returns no slot for them).
    func placedAtlasGlyphs(for string: String, size: Double,
                           alignH: TextAlignH, alignV: TextAlignV,
                           direction: TextDirection,
                           justify: TextJustification? = nil,
                           hangs: Bool = false,
                           at origin: Vector2) -> [PlacedAtlasGlyph] {
        guard size > 0, !string.isEmpty else { return [] }
        let laidOut = layoutBlock(string, size: size, direction: direction,
                                  justify: justify, hangs: hangs)
        let starts = lineStarts(extents: laidOut.map { ($0.width - $0.hang) * size }, size: size,
                                alignH: alignH, alignV: alignV,
                                direction: direction, at: origin)
        let turned = direction.turnsGlyphs

        var result: [PlacedAtlasGlyph] = []
        for (index, line) in laidOut.enumerated() {
            let start = starts[index]
            for placed in line.glyphs {
                result.append(PlacedAtlasGlyph(
                    origin: OutlineFont.penOrigin(placed, start: start, size: size, turned: turned),
                    glyph: placed.glyph, font: placed.font, turned: turned))
            }
        }
        return result
    }

    /// Every line of a block, laid out. Split on the newlines, and where the block is
    /// justified each line but the last of its paragraph is stretched to the box.
    private func layoutBlock(_ string: String, size: Double, direction: TextDirection,
                             justify: TextJustification?,
                             hangs: Bool) -> [(glyphs: [ShapedGlyph], width: Double, hang: Double)] {
        string.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                let text = String(line)
                // What the last character adds, where it is one allowed to hang past
                // the end. The line still holds it and still draws it; it is only
                // left out of how far the line counts as running.
                var hang = 0.0
                if hangs, HangingPunctuation.endsWithHangable(text) {
                    let full = layoutLine(text, direction: direction).width
                    let rest = layoutLine(String(text.dropLast()), direction: direction).width
                    hang = max(0, full - rest)
                }
                var target: Double? = nil
                if let justify, !justify.naturalLines.contains(index) {
                    // The stretch has to carry the hung character past the edge, so
                    // the part that counts is the part that reaches it.
                    target = justify.extent / size + hang   // the layout works in em
                }
                let laid = layoutLine(text, direction: direction, justifyTo: target)
                return (laid.glyphs, laid.width, hang)
            }
    }

    /// The point each line of a block measures its glyph positions from, in canvas
    /// points, one per line. A glyph then lands at `start + (x, -y) * size`.
    ///
    /// The two writing axes need one formula between them, so the returned point
    /// means whatever that axis needs it to mean: across a line it is the line's
    /// left edge on its baseline; down a column it is the column's centre axis at
    /// the column's top edge. Both cases put the glyph in the right place with the
    /// same addition, which is what lets one placement loop serve both, and it is
    /// why this is the only place either layout decides anything.
    ///
    /// `extents` is how far each line runs along its own writing axis, in points.
    /// Every line is anchored by its own extent, so a short column centres on its
    /// own length exactly as a short line does.
    private func lineStarts(extents: [Double], size: Double,
                            alignH: TextAlignH, alignV: TextAlignV,
                            direction: TextDirection, at origin: Vector2) -> [Vector2] {
        let ascentP = ascent * size
        let descentP = descent * size
        // Baseline to baseline across a line, and column axis to column axis down
        // one. The same number: a column is set as tightly as a line is.
        let pitch = (ascent + descent + leading) * size
        let count = Double(extents.count - 1)

        guard direction.isVertical else {
            let blockHeight = count * pitch + ascentP + descentP
            let topY: Double
            switch alignV {
            case .top:      topY = origin.y
            case .baseline: topY = origin.y - ascentP
            case .middle:   topY = origin.y - blockHeight / 2
            case .bottom:   topY = origin.y - blockHeight
            }
            return extents.enumerated().map { index, width in
                let startX: Double
                switch alignH {
                case .left:   startX = origin.x
                case .center: startX = origin.x - width / 2
                case .right:  startX = origin.x - width
                }
                return Vector2(startX, topY + Double(index) * pitch + ascentP)
            }
        }

        // How wide one column is, and where its own axis sits inside it. Set on the
        // em square, a column is one em across whatever the glyphs in it, which is
        // what the writing system sets to and what keeps the block a fixed width
        // however the text changes. Turned, a column is instead as wide as the line
        // it was before the turn, so it takes the ascent and the descent. The turn
        // puts what stood above the baseline to the right of the axis, so the
        // descent is the side that reaches back to the column's left edge.
        let turned = direction.turnsGlyphs
        let columnWidth = turned ? ascentP + descentP : size
        let axisFromLeft = turned ? descentP : size / 2
        let blockWidth = count * pitch + columnWidth
        let left: Double
        switch alignH {
        case .left:   left = origin.x
        case .center: left = origin.x - blockWidth / 2
        case .right:  left = origin.x - blockWidth
        }
        // Which end the first column stands at is the other half of the difference:
        // one order fills right to left, the other left to right.
        let firstAxis = turned ? left + axisFromLeft : left + blockWidth - axisFromLeft
        let step = turned ? pitch : -pitch
        return extents.enumerated().map { index, length in
            let topY: Double
            switch alignV {
            case .top, .baseline: topY = origin.y
            case .middle:         topY = origin.y - length / 2
            case .bottom:         topY = origin.y - length
            }
            return Vector2(firstAxis + Double(index) * step, topY)
        }
    }

    /// Where one shaped glyph's pen lands in canvas space, measured from its line's
    /// start point.
    ///
    /// A turned column swaps the two axes. What the pen advanced across the line now
    /// runs down the column, and what stood above the baseline now stands to the
    /// right of the column's axis, so both offsets are added rather than one being
    /// subtracted for the font's y-up.
    static func penOrigin(_ placed: ShapedGlyph, start: Vector2,
                          size: Double, turned: Bool) -> Vector2 {
        turned ? Vector2(start.x + placed.y * size, start.y + placed.x * size)
               : Vector2(start.x + placed.x * size, start.y - placed.y * size)
    }

    /// One point of a glyph's local geometry, turned a quarter turn clockwise. The
    /// glyph's own advance direction becomes the way down the column.
    static func turnedPoint(_ p: Vector2) -> Vector2 { Vector2(-p.y, p.x) }

    /// A picture glyph's box in the glyph's local frame, turned with the glyph where
    /// the column turns. A quarter turn takes a box to a box, so the picture stays
    /// square to the page.
    static func pictureRect(_ emRect: Rectangle, size: Double, turned: Bool) -> Rectangle {
        let x = emRect.x * size, y = emRect.y * size
        let w = emRect.width * size, h = emRect.height * size
        guard turned else { return Rectangle(x: x, y: y, width: w, height: h) }
        return Rectangle(x: -(y + h), y: x, width: h, height: w)
    }

    /// The glyphs of `string`, each as a positioned `Shape` of vector contours, as
    /// if drawn at `origin` with `size`, `alignH`, and `alignV`. One `Shape` per
    /// glyph (a letter with a counter — `o`, `e`, `a` — keeps its hole via nonzero
    /// winding). The geometry behind the public `outlines(of:)` and `textToShapes`;
    /// `drawText` itself takes the lighter `placedGlyphs` path. Built by
    /// translating each glyph's cached local contours, so it shares the cache.
    func glyphShapes(for string: String, size: Double,
                     alignH: TextAlignH, alignV: TextAlignV,
                     direction: TextDirection,
                     justify: TextJustification? = nil,
                     hangs: Bool = false,
                     at origin: Vector2) -> [Shape] {
        OutlineFont.shapes(of: placedGlyphs(for: string, size: size, alignH: alignH,
                                            alignV: alignV, direction: direction,
                                            justify: justify, hangs: hangs, at: origin))
    }

    /// The canvas-space `Shape` of each placed glyph that has one. A glyph the font
    /// stores as a picture has no geometry, so it is left out.
    static func shapes(of placed: [PlacedGlyphGeometry]) -> [Shape] {
        placed.compactMap { glyph in
            guard !glyph.localContours.isEmpty else { return nil }
            // Glyph outlines are authored for nonzero winding.
            return Shape(contours: glyph.localContours.map {
                Contour($0.points.map { $0 + glyph.origin }, closed: $0.isClosed)
            }, winding: .nonZero)
        }
    }

    /// Cached local geometry (flattened contours + triangulated fill, pen at the
    /// origin) for one glyph at `size`. Built on first use through the per-font
    /// `geometryCache`.
    private func geometry(for glyph: CGGlyph, font: CTFont,
                          size: Double, turned: Bool = false) -> GlyphGeometryCache.Local {
        geometryCache.geometry(for: glyph, font: font, size: size, turned: turned) {
            // A turned glyph is the upright one under a quarter turn, so it asks for
            // that one first and turns the result. The flatten, the clean and the
            // triangulation therefore happen once for the pair, and a turned column
            // stays what an upright line already is: a translate of cached vertices.
            if turned {
                let upright = geometry(for: glyph, font: font, size: size)
                return GlyphGeometryCache.Local(
                    contours: upright.contours.map {
                        Contour($0.points.map(OutlineFont.turnedPoint), closed: $0.isClosed)
                    },
                    fill: upright.fill.map(OutlineFont.turnedPoint))
            }
            guard let path = cache.path(for: glyph, font: font) else {
                return GlyphGeometryCache.Local(contours: [], fill: [])
            }
            // Some system faces (San Francisco) build a glyph from *overlapping*
            // sub-contours. Used as-is they hurt both ways the geometry is drawn:
            // the triangulated *fill* shows a faint hairline seam where overlaps
            // meet (the counters of a/e/g), and the *outline* carries doubled edges
            // where sub-contours cross — so a stroke, or dots sampled along the
            // outline, double up there. Resolving the self-overlap into clean,
            // non-overlapping boundaries first — a union of the glyph with nothing,
            // which normalizes it under its nonzero winding — fixes both. The union
            // only merges cleanly when the curves are finely flattened, and flatten
            // density tracks the render size, so at small sizes the overlap stays
            // coarse and the seam survives. So flatten + clean at a large reference
            // scale, then scale the clean result down to the render size. Both the
            // returned contours (outline/stroke/points) and the fill come from it.
            // Cached per (glyph, size).
            //
            // Flattening at the reference scale leaves the result far denser than the
            // render size needs (~40× the points at 26pt), which the per-frame stroke
            // tessellation and fill bake then pay for every frame. So simplify the
            // scaled contours back to a sub-pixel tolerance — the clean topology
            // survives, but the point count drops to render-appropriate.
            let referenceContours = OutlineFont.flatten(path, scale: 1024, originX: 0, originY: 0)
            guard !referenceContours.isEmpty else {
                return GlyphGeometryCache.Local(contours: [], fill: [])
            }
            let cleaned = Shape(contours: referenceContours, winding: .nonZero)
                .union(Shape(contours: [], winding: .nonZero))
            let k = size / 1024
            let contours = cleaned.contours.compactMap { contour -> Contour? in
                let scaled = contour.points.map { Vector2($0.x * k, $0.y * k) }
                let simplified = OutlineFont.simplifyClosed(scaled, tolerance: 0.3)
                return simplified.count >= 3 ? Contour(simplified, closed: contour.isClosed) : nil
            }
            let fill = Shape(contours: contours, winding: cleaned.winding).triangulatedFill()
            return GlyphGeometryCache.Local(contours: contours, fill: fill)
        }
    }

    // MARK: Core Text layout

    /// A single-line run of **clusters** for per-glyph drawing and text-on-a-path:
    /// each cluster's source characters, pen metrics in canvas units (at `size`),
    /// and geometry in a local frame (pen origin at the origin, baseline at
    /// `y = 0`). Newlines are treated as spaces, since these effects are
    /// single-line by nature.
    ///
    /// The unit is a cluster rather than a glyph because a glyph is the wrong unit
    /// for anything a person would call a letter: see `ShapedCluster`.
    func glyphRun(for string: String, size: Double, direction: TextDirection) -> [GlyphRunItem] {
        guard size > 0, !string.isEmpty else { return [] }
        let line = string.replacingOccurrences(of: "\n", with: " ")
        let (placed, _) = layoutLine(line, direction: direction)
        guard !placed.isEmpty else { return [] }

        // A turned column was shaped as an ordinary line, so it measures its pen the
        // way a line does. Only a column set on em squares stacks its pieces.
        let turned = direction.turnsGlyphs
        let stacked = direction.isVertical && !turned
        let clusters = TextClusters.group(placed, in: line, vertical: stacked)
        // Down a stacked column the run starts at the top edge of the first piece's
        // square, which is a whole ascent above the first glyph's own baseline, so
        // the distance is accumulated from the advances rather than read off a
        // glyph. Across a line the shaped pen position already is that distance, and
        // it carries the kerning, so it is kept.
        var reached = 0.0

        var items: [GlyphRunItem] = []
        for cluster in clusters {
            let pen = (stacked ? reached : cluster.anchor) * size
            // The top edge of this piece's square, in the layout's own frame.
            let cellTop = -reached
            defer { reached += cluster.advance }
            var shapes: [Shape] = []
            var picture: Image? = nil
            var pictureRect = Rectangle(x: 0, y: 0, width: 0, height: 0)
            for glyph in cluster.glyphs {
                // Each glyph keeps its own place inside the cluster: a mark sits
                // over its letter and a reordered vowel sign sits before it. Only
                // the axis the run travels along is made relative; the other one
                // keeps the offset the layout gave it.
                // A turned piece keeps the same two numbers with their axes swapped:
                // the pen distance runs down the piece, the height across it.
                let along = (stacked ? glyph.x : glyph.x - cluster.anchor) * size
                let across = -(stacked ? glyph.y - cellTop : glyph.y) * size
                let localX = turned ? -across : along
                let localY = turned ? along : across
                if let path = cache.path(for: glyph.glyph, font: glyph.font) {
                    let contours = OutlineFont.flatten(path, scale: size,
                                                       originX: localX, originY: localY,
                                                       turned: turned)
                    if !contours.isEmpty { shapes.append(Shape(contours: contours, winding: .nonZero)) }
                } else if let color = colorGlyphs.glyph(glyph.glyph, font: glyph.font) {
                    picture = color.image
                    let box = OutlineFont.pictureRect(color.emRect, size: size, turned: turned)
                    pictureRect = Rectangle(x: localX + box.x, y: localY + box.y,
                                            width: box.width, height: box.height)
                }
            }
            items.append(GlyphRunItem(text: cluster.text, pen: pen,
                                      advance: cluster.advance * size,
                                      localShapes: shapes,
                                      picture: picture, localPictureRect: pictureRect))
        }
        return items
    }

    /// One laid-out line: its glyphs (em units) and typographic advance width (em).
    ///
    /// `justifyTo` stretches the line to that extent, in em, which is what justified
    /// text asks for. The stretching is the layout engine's own: it knows where a
    /// script allows the extra room to go, which is between the words in English and
    /// between the characters in Japanese. A line already at or past the target is
    /// left alone, so justification never squeezes.
    private func layoutLine(_ string: String, direction: TextDirection,
                            justifyTo: Double? = nil) -> (glyphs: [ShapedGlyph], width: Double) {
        guard !string.isEmpty else { return ([], 0) }
        var attributes: [CFString: Any] = [kCTFontAttributeName: ctFont]
        if direction.isVertical && !direction.turnsGlyphs {
            // Asking for the vertical forms does two things at once: the layout
            // engine picks each character's sideways glyph where the font has one,
            // and it places the glyphs down the column instead of across a line.
            // The positions come back with the font's own vertical offset already
            // applied, so a glyph needs no further translation and no rotation.
            attributes[kCTVerticalFormsAttributeName] = true
        } else if let style = OutlineFont.paragraphStyle(direction) {
            attributes[kCTParagraphStyleAttributeName] = style
        }
        guard let attributed = CFAttributedStringCreate(nil, string as CFString,
                                                        attributes as CFDictionary) else {
            return ([], 0)
        }
        var ctLine = CTLineCreateWithAttributedString(attributed)
        var width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        if let target = justifyTo, width > 0, target > width,
           let stretched = CTLineCreateJustifiedLine(ctLine, 1.0, target) {
            ctLine = stretched
            width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        }

        var glyphs: [ShapedGlyph] = []
        let runs = CTLineGetGlyphRuns(ctLine)
        for runIndex in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, runIndex), to: CTRun.self)
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }

            // The run's own font. The system substitutes a fallback face for glyphs
            // the base font lacks, which is how one line can carry Latin, Japanese
            // and an emoji at once.
            let attrs = CTRunGetAttributes(run)
            let fontPtr = CFDictionaryGetValue(attrs, Unmanaged.passUnretained(kCTFontAttributeName).toOpaque())
            let runFont = fontPtr.map { unsafeBitCast($0, to: CTFont.self) } ?? ctFont

            var gids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &gids)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            for k in 0..<count {
                glyphs.append(ShapedGlyph(font: runFont, glyph: gids[k],
                                          x: Double(positions[k].x), y: Double(positions[k].y),
                                          advance: Double(advances[k].width),
                                          stringIndex: indices[k]))
            }
        }
        return (glyphs, width)
    }

    /// The paragraph style that forces a base direction, or `nil` for `.automatic`
    /// (no style at all, so the layout engine reads the direction off the text).
    /// Built once per direction: the two styles are immutable and shared.
    private static func paragraphStyle(_ direction: TextDirection) -> CTParagraphStyle? {
        switch direction {
        // Vertical text asks for the vertical forms instead, and a column has no
        // base direction to force: it always runs top to bottom. A turned column
        // is shaped as an ordinary line, but the scripts set that way run one way
        // only, so reading the direction off the text is already right.
        case .automatic, .topToBottom, .topToBottomLeftToRight: return nil
        case .leftToRight:  return forcedLeftToRight
        case .rightToLeft:  return forcedRightToLeft
        }
    }

    // Immutable once created, and Core Text reads them from any thread.
    private nonisolated(unsafe) static let forcedLeftToRight = makeDirectionStyle(.leftToRight)
    private nonisolated(unsafe) static let forcedRightToLeft = makeDirectionStyle(.rightToLeft)

    /// A paragraph style carrying one base writing direction. The setting holds a
    /// *pointer* to the value, so both must stay alive until `CTParagraphStyleCreate`
    /// has copied them; nesting the two `withUnsafePointer` calls is what guarantees
    /// that (letting the pointer escape its closure reads freed stack memory and the
    /// direction silently does nothing).
    private static func makeDirectionStyle(_ value: CTWritingDirection) -> CTParagraphStyle {
        var direction = value
        return withUnsafePointer(to: &direction) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .baseWritingDirection,
                valueSize: MemoryLayout<CTWritingDirection>.size,
                value: UnsafeRawPointer(pointer))
            return withUnsafePointer(to: &setting) { CTParagraphStyleCreate($0, 1) }
        }
    }

    /// Flatten a glyph's `CGPath` (em units, y-up, origin at the glyph's pen) into
    /// Ollin `Contour`s in canvas space: every point maps through
    /// `(gx, gy) → (originX + gx·scale, originY − gy·scale)` (the y flip turns the
    /// font's y-up into Ollin's y-down). Curves flatten through the shared
    /// `CurveSampling`, so segment density tracks the on-screen size.
    /// Reduce a closed polyline to the points needed to stay within `tolerance`
    /// (Ramer–Douglas–Peucker), keeping the shape's topology. Used to bring a
    /// reference-scale-cleaned glyph contour back to render-appropriate density.
    static func simplifyClosed(_ points: [Vector2], tolerance: Double) -> [Vector2] {
        guard points.count > 4 else { return points }
        // Anchor on the two farthest-apart points so a closed loop keeps its extent,
        // then simplify the two halves between them as open chains.
        var iA = 0, iB = 0, best = -1.0
        for i in 1..<points.count {
            let d = points[i].distanceSquared(to: points[0])
            if d > best { best = d; iB = i }
        }
        best = -1
        for i in 0..<points.count {
            let d = points[i].distanceSquared(to: points[iB])
            if d > best { best = d; iA = i }
        }
        if iA > iB { swap(&iA, &iB) }
        let first = Array(points[iA...iB])
        let second = Array(points[iB...] + points[...iA])
        var out = douglasPeucker(first, tolerance: tolerance)
        let tail = douglasPeucker(second, tolerance: tolerance)
        if tail.count > 2 { out.append(contentsOf: tail[1..<(tail.count - 1)]) }
        return out
    }

    private static func douglasPeucker(_ pts: [Vector2], tolerance: Double) -> [Vector2] {
        guard pts.count > 2 else { return pts }
        let a = pts.first!, b = pts.last!
        var maxDist = -1.0, idx = 0
        for i in 1..<(pts.count - 1) {
            let d = perpendicularDistance(pts[i], a, b)
            if d > maxDist { maxDist = d; idx = i }
        }
        if maxDist <= tolerance { return [a, b] }
        let left = douglasPeucker(Array(pts[0...idx]), tolerance: tolerance)
        let right = douglasPeucker(Array(pts[idx...]), tolerance: tolerance)
        return left.dropLast() + right
    }

    private static func perpendicularDistance(_ p: Vector2, _ a: Vector2, _ b: Vector2) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-12 { return p.distance(to: a) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }

    private static func flatten(_ path: CGPath, scale: Double,
                                originX: Double, originY: Double,
                                turned: Bool = false) -> [Contour] {
        func map(_ p: CGPoint) -> Vector2 {
            // Turned, the same quarter turn clockwise every other piece of a turned
            // column takes: the glyph's advance runs down, its height runs right.
            turned ? Vector2(originX + Double(p.y) * scale, originY + Double(p.x) * scale)
                   : Vector2(originX + Double(p.x) * scale, originY - Double(p.y) * scale)
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

/// The active text font — a bitmap (pixel-grid), an outline (vector) face, or a
/// stroke (single-line / plotter) face. `drawText` and the text metrics dispatch
/// on this; `textFont(_:)` sets it from a `BitmapFont`, `OutlineFont`, or
/// `StrokeFont`.
enum ActiveFont {
    case bitmap(BitmapFont)
    case outline(OutlineFont)
    case stroke(StrokeFont)

    /// Whether the active font draws as stroked pen paths (so `drawText` strokes
    /// open polylines rather than filling glyph shapes).
    var isStroke: Bool {
        if case .stroke = self { return true }
        return false
    }
}

/// Per-font cache of glyph outlines. Glyph paths are created once by Core Text
/// and reused across frames. Keyed by the run font *and* glyph id, because font
/// fallback can place glyphs from several faces on one line.
private final class GlyphPathCache: @unchecked Sendable {
    private var fonts: [(font: CTFont, paths: [CGGlyph: CGPath])] = []
    /// Guards `fonts`. The framework only touches the cache from the main draw
    /// thread, but `OutlineFont` is a public `Sendable` value reachable from the
    /// `.system` globals, so a sketch could read a glyph off the main actor; the
    /// lock keeps that from corrupting the array. Uncontended with one thread, and
    /// a cache hit holds it only for a dictionary lookup.
    private let lock = OSAllocatedUnfairLock()

    /// The outline for `glyph` in `font` (em units, y-up), or `nil` for a glyph
    /// with no contours (a space). Created on first use, then cached.
    func path(for glyph: CGGlyph, font: CTFont) -> CGPath? {
        lock.lock(); defer { lock.unlock() }
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

/// Per-font cache of a glyph's *flattened and triangulated* geometry at a given
/// on-screen size, in a local frame (pen at the origin). Flattening the outline
/// and triangulating the fill (libtess2) are the per-frame cost of drawing
/// outline text; caching them lets a redrawn label become a translate of cached
/// vertices. Keyed by the run font, glyph id, and `size` — the geometry depends
/// on size (both the flatten density and the scale track it). The size key is the
/// exact `Double` bit pattern, so a sketch redrawing text at a constant size hits
/// every frame; text whose size animates continuously won't hit (and pays the
/// usual cost), with the total bounded by clearing past a cap.
private final class GlyphGeometryCache: @unchecked Sendable {
    struct Local { let contours: [Contour]; let fill: [Vector2] }
    private struct Key: Hashable { let glyph: CGGlyph; let sizeBits: UInt64; let turned: Bool }
    private var fonts: [(font: CTFont, glyphs: [Key: Local])] = []
    private var count = 0
    /// Bound memory for text whose size animates (each size is a distinct key).
    private static let cap = 8192
    /// Guards `fonts`/`count` (see `GlyphPathCache.lock`). The expensive build runs
    /// *outside* the lock, so the lock is held only for a lookup or an insert, never
    /// the flatten + triangulate; two threads racing a cold miss just build the same
    /// glyph twice (harmless, the inserts are idempotent).
    private let lock = OSAllocatedUnfairLock()

    /// Cached local geometry for `glyph` at `size`, built via `make` on first use.
    func geometry(for glyph: CGGlyph, font: CTFont, size: Double, turned: Bool = false,
                  make: () -> Local) -> Local {
        let key = Key(glyph: glyph, sizeBits: size.bitPattern, turned: turned)
        lock.lock()
        let cached = lookup(key, font)
        lock.unlock()
        if let cached { return cached }
        let made = make()                       // flatten + triangulate, off the lock
        lock.lock(); defer { lock.unlock() }
        insert(key, font, made)
        return made
    }

    /// Locked lookup helper: the caller holds `lock`.
    private func lookup(_ key: Key, _ font: CTFont) -> Local? {
        for index in fonts.indices where CFEqual(fonts[index].font, font) {
            return fonts[index].glyphs[key]
        }
        return nil
    }

    /// Locked insert helper: the caller holds `lock`. Also bounds the cache, clearing
    /// everything past the cap (a blunt bound, fine since size-animating text is the
    /// only way to reach it).
    private func insert(_ key: Key, _ font: CTFont, _ made: Local) {
        if let index = fonts.firstIndex(where: { CFEqual($0.font, font) }) {
            fonts[index].glyphs[key] = made
        } else {
            fonts.append((font: font, glyphs: [key: made]))
        }
        count += 1
        if count > Self.cap { fonts.removeAll(); count = 0 }
    }
}
