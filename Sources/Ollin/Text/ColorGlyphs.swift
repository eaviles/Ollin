// Color glyphs: the ones a font stores as pictures rather than outlines.

import Foundation
import CoreGraphics
import CoreText
import os

/// A glyph a font draws as a picture instead of an outline, rasterized once and
/// kept.
///
/// Most glyphs are contours, which is why text in Ollin is geometry you can fill,
/// stroke, warp and sample. Emoji are not: the color emoji font stores each one
/// as a stack of bitmaps, so `CTFontCreatePathForGlyph` hands back nothing at all
/// and a glyph asked for its outline draws as empty space. Drawing it means
/// rasterizing the picture and placing it as an image.
struct ColorGlyph {
    /// The rasterized picture, ready for the textured-quad path.
    let image: Image
    /// Where the picture sits relative to the pen, in em units with the canvas's
    /// own orientation: `y` runs down from the baseline, so a glyph standing above
    /// the baseline has a negative `y`.
    let emRect: Rectangle

    /// The canvas rect this picture covers for a glyph whose pen sits at `origin`,
    /// drawn at `size` points.
    func rect(at origin: Vector2, size: Double) -> Rectangle {
        Rectangle(x: origin.x + emRect.x * size, y: origin.y + emRect.y * size,
                  width: emRect.width * size, height: emRect.height * size)
    }
}

/// Per-font cache of rasterized color glyphs, keyed by the run font and glyph id
/// like the outline caches beside it. A reference type, so copies of an
/// `OutlineFont` value share one cache.
final class ColorGlyphCache: @unchecked Sendable {
    /// The pixel size each color glyph is rasterized at.
    ///
    /// **The number comes from the font, not from taste.** Apple Color Emoji is an
    /// `sbix` font: it carries a fixed ladder of bitmap strikes, and reading its
    /// table shows the ladder ends at 160 pixels per em. Rasterizing larger only
    /// upsamples that same top strike, so 160 is where the detail runs out. An
    /// emoji drawn much larger than this softens, which is the format's limit
    /// rather than ours.
    static let rasterPixels = 160

    private var fonts: [(font: CTFont, glyphs: [CGGlyph: ColorGlyph?])] = []
    /// Guards `fonts`, matching the outline caches: the expensive raster runs
    /// outside the lock, so two threads racing a cold miss just draw the same
    /// glyph twice.
    private let lock = OSAllocatedUnfairLock()

    /// The picture for `glyph` in `font`, or `nil` when the glyph is an ordinary
    /// outline (or has no ink at all, like a space). Rasterized on first use.
    func glyph(_ glyph: CGGlyph, font: CTFont) -> ColorGlyph? {
        lock.lock()
        let cached = fonts.first(where: { CFEqual($0.font, font) })?.glyphs[glyph]
        lock.unlock()
        if let cached { return cached }

        let made = ColorGlyphCache.rasterize(glyph, font: font)
        lock.lock(); defer { lock.unlock() }
        if let index = fonts.firstIndex(where: { CFEqual($0.font, font) }) {
            fonts[index].glyphs[glyph] = made
        } else {
            fonts.append((font: font, glyphs: [glyph: made]))
        }
        return made
    }

    /// Draw one color glyph into a bitmap. Returns `nil` for a glyph that has an
    /// outline (the ordinary case, handled by the vector path) or no ink.
    private static func rasterize(_ glyph: CGGlyph, font: CTFont) -> ColorGlyph? {
        // An outline glyph is somebody else's job. Asking the path first is also
        // what tells a color glyph apart from an ordinary one: there is no flag
        // for it, only the absence of contours.
        guard CTFontCreatePathForGlyph(font, glyph, nil) == nil else { return nil }

        var ids = [glyph]
        // Metrics come from the font at 1 em, so the rect is in em units and one
        // raster serves every `textSize`.
        let unitFont = CTFontCreateCopyWithAttributes(font, 1.0, nil, nil)
        let box = CTFontGetBoundingRectsForGlyphs(unitFont, .default, &ids, nil, 1)
        guard box.width > 0, box.height > 0, box.width.isFinite, box.height.isFinite else { return nil }

        // One pixel of margin all round, so the edge of the picture keeps its own
        // anti-aliasing instead of being cut off by the bitmap's edge.
        let scale = Double(rasterPixels)
        let margin = 1
        let width = Int((Double(box.width) * scale).rounded(.up)) + margin * 2
        let height = Int((Double(box.height) * scale).rounded(.up)) + margin * 2
        guard width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)

        // Place the pen so the glyph's own bounding box lands inside the margin.
        // The context is y-up like the font, so no flip is needed here; the flip
        // into canvas orientation happens in `emRect`.
        var pen = CGPoint(x: CGFloat(margin) - box.minX * scale,
                          y: CGFloat(margin) - box.minY * scale)
        let drawFont = CTFontCreateCopyWithAttributes(font, CGFloat(scale), nil, nil)
        CTFontDrawGlyphs(drawFont, &ids, &pen, 1, context)

        guard let cgImage = context.makeImage() else { return nil }
        // The margin is real ink space, so it belongs in the rect too: the picture
        // covers the glyph's box grown by one pixel of the raster on every side.
        let pad = Double(margin) / scale
        let rect = Rectangle(x: Double(box.minX) - pad,
                             y: -(Double(box.maxY) + pad),
                             width: Double(box.width) + pad * 2,
                             height: Double(box.height) + pad * 2)
        return ColorGlyph(image: Image(cgImage: cgImage), emRect: rect)
    }
}
