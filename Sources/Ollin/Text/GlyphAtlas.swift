import Foundation
import CoreGraphics
import CoreText
import Metal
import os

/// A single-channel signed-distance-field (SDF) texture atlas for an outline
/// font — the performance path behind `textMode(.atlas)`. Each glyph is
/// rasterized **once** into a distance field packed into a shared texture page;
/// at draw time a glyph becomes a single textured quad sampling its cell, so the
/// per-frame CPU cost of a glyph drops to a few vertex writes (no flatten +
/// triangulate). One raster serves every `textSize`, and the field keeps edges
/// crisp under magnification (the classic alpha-tested-magnification trick).
///
/// A reference type, lazily filled and shared across value copies of an
/// `OutlineFont` (like its outline/geometry caches). It's touched only from the
/// single draw thread — `slot(for:font:)` while recording a frame (no device),
/// `texture(for:)` while the renderer encodes — so it carries no locking and is
/// `@unchecked Sendable` to satisfy the `Sendable` `OutlineFont` that holds it.
///
/// The single-channel field rounds *very sharp* corners only at extreme
/// magnification (invisible for the body/volume text this path targets); a
/// corner-preserving multi-channel field (MSDF) is a future upgrade. The distance
/// transform is the exact separable Euclidean one (Felzenszwalb & Huttenlocher).
final class GlyphAtlas: @unchecked Sendable {

    /// One glyph's place in the atlas: its cell's UV rect and the covering quad in
    /// em units (font space, y-up, pen at the origin). The drawer scales the em
    /// rect by `textSize`, offsets by the pen origin, and flips y to place it.
    struct Slot {
        let u0, v0, u1, v1: Float            // atlas UVs: top-left … bottom-right
        let emLeft, emRight, emTop, emBottom: Double   // covering quad, em units, y-up
    }

    // MARK: Tunables

    /// The texture page is `pageSize`² texels, one byte each (`r8Unorm`). 1024²
    /// (1 MB) holds Latin + punctuation + common accents comfortably at the cell
    /// sizes below.
    private static let pageSize = 1024
    /// Glyphs are rasterized at this em height (points). Fixed — one raster covers
    /// every on-screen `textSize`.
    private static let atlasFontSize: CGFloat = 48
    /// SDF range / padding in texels: the field saturates to fully-in / fully-out
    /// at ±`spread` texels from the edge, and each cell carries a `spread` margin
    /// so neighbors can't bleed under linear sampling.
    private static let spread = 6
    /// A guard texel between packed cells.
    private static let gutter = 1

    // MARK: Page state

    /// The atlas page, row-major, one byte per texel: the normalized signed
    /// distance, `0.5` = edge, `> 0.5` inside.
    private var page = [UInt8](repeating: 0, count: pageSize * pageSize)
    /// Cached slots, keyed by run font (fallback puts glyphs from several faces on
    /// one line) then glyph id — mirrors `GlyphPathCache`. A cached `nil` records a
    /// glyph that draws nothing (a space), so it's not re-rasterized every frame.
    private var fonts: [(font: CTFont, slots: [CGGlyph: Slot?])] = []

    /// Shelf packer cursor: current row origin and the tallest cell on the row.
    private var penX = GlyphAtlas.gutter
    private var penY = GlyphAtlas.gutter
    private var rowHeight = 0

    /// The page changed since the last upload, so `texture(for:)` must re-blit.
    private var dirty = true
    private var cachedTexture: MTLTexture?
    private var cachedDeviceID: ObjectIdentifier?
    /// Counts the page rebuilds (`reset`). A slot handed out before a rebuild
    /// points into a page that no longer holds its glyph, so a reader carrying
    /// the page elsewhere (the web recorder) compares this against the value it
    /// saw when it first took a slot.
    private(set) var generation = 0

    /// The page's texel width (and height), for a reader that carries the page.
    static var webPageSize: Int { pageSize }

    /// Guards all the mutable page/packer/cache state above. `slot(for:)`
    /// (recording) and `texture(for:)` (encoding) both run on the main draw thread
    /// in normal use, but `OutlineFont` is a public `Sendable` reachable from the
    /// `.system` globals, so a sketch could reach the atlas off the main actor; the
    /// lock keeps the shared `page`/packer/cache from corrupting. A cache hit holds
    /// it only briefly; the one-time rasterize-and-pack runs under it during warm-up.
    private let lock = OSAllocatedUnfairLock()

    // MARK: Slots

    /// The atlas slot for `glyph` in `font`, built on first use. `nil` for a glyph
    /// with no contours (a space) or one that can't be placed (oversized, or the
    /// page is full after a rebuild) — the caller simply draws nothing for it.
    func slot(for glyph: CGGlyph, font: CTFont) -> Slot? {
        lock.lock(); defer { lock.unlock() }
        for index in fonts.indices where CFEqual(fonts[index].font, font) {
            if let hit = fonts[index].slots[glyph] { return hit }
            let made = make(glyph, font)
            fonts[index].slots[glyph] = made
            return made
        }
        let made = make(glyph, font)
        fonts.append((font: font, slots: [glyph: made]))
        return made
    }

    /// Rasterize `glyph` to a coverage mask, turn it into a normalized signed
    /// distance field, pack it into the page, and return its `Slot`. `nil` for an
    /// empty glyph or one that won't fit.
    private func make(_ glyph: CGGlyph, _ font: CTFont) -> Slot? {
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let bbox = path.boundingBoxOfPath
        guard bbox.width > 0, bbox.height > 0 else { return nil }   // space / blank

        let scale = GlyphAtlas.atlasFontSize
        let spread = GlyphAtlas.spread
        // Cell = the glyph's raster footprint plus a `spread` margin on every side.
        let cellW = Int(ceil(bbox.width * scale)) + 2 * spread
        let cellH = Int(ceil(bbox.height * scale)) + 2 * spread
        guard cellW <= GlyphAtlas.pageSize, cellH <= GlyphAtlas.pageSize else { return nil }

        // Cell rect in em units (y-up): the glyph bbox grown by the margin.
        let spreadEm = Double(spread) / Double(scale)
        let emLeft = Double(bbox.minX) - spreadEm
        let emBottom = Double(bbox.minY) - spreadEm
        let emRight = emLeft + Double(cellW) / Double(scale)
        let emTop = emBottom + Double(cellH) / Double(scale)

        guard let cell = rasterizeSDF(path: path, cellW: cellW, cellH: cellH,
                                      emLeft: emLeft, emBottom: emBottom) else { return nil }
        guard let (px, py) = pack(width: cellW, height: cellH) else { return nil }

        // Blit the cell (row 0 = top) into the page at (px, py).
        for r in 0..<cellH {
            let src = r * cellW
            let dst = (py + r) * GlyphAtlas.pageSize + px
            page.replaceSubrange(dst..<(dst + cellW), with: cell[src..<(src + cellW)])
        }
        dirty = true

        let p = Float(GlyphAtlas.pageSize)
        return Slot(u0: Float(px) / p, v0: Float(py) / p,
                    u1: Float(px + cellW) / p, v1: Float(py + cellH) / p,
                    emLeft: emLeft, emRight: emRight, emTop: emTop, emBottom: emBottom)
    }

    // MARK: Rasterization + distance transform

    /// Draw `path` (em units, y-up) into a `cellW`×`cellH` grayscale coverage mask
    /// (row 0 = top), then convert it to a normalized signed distance field
    /// (`0.5` = edge, `> 0.5` inside). Returns the cell bytes, or `nil` if the
    /// bitmap context can't be made.
    private func rasterizeSDF(path: CGPath, cellW: Int, cellH: Int,
                              emLeft: Double, emBottom: Double) -> [UInt8]? {
        let scale = GlyphAtlas.atlasFontSize
        var coverage = [UInt8](repeating: 0, count: cellW * cellH)
        let made: Bool = coverage.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: cellW, height: cellH,
                                      bitsPerComponent: 8, bytesPerRow: cellW,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // Map em point (gx, gy) → ctx point scale·(g − (emLeft, emBottom)); with
            // CG's y-up bitmap, memory row 0 is the highest y, so row 0 = the cell's
            // top (emTop) — matching v0 at the top of the cell.
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -emLeft, y: -emBottom)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(path)
            ctx.fillPath()
            return true
        }
        guard made else { return nil }
        return GlyphAtlas.signedDistanceField(coverage: coverage, width: cellW, height: cellH,
                                              spread: GlyphAtlas.spread)
    }

    /// A normalized signed distance field from a binary coverage mask: positive
    /// (`> 0.5`) inside, `0.5` on the edge, saturating to 0 / 1 at ±`spread`
    /// texels. Uses the exact separable Euclidean distance transform (Felzenszwalb
    /// & Huttenlocher) on the inside and the outside, combined to a signed value.
    /// Pure CPU and deterministic, so it's unit-tested without a GPU.
    static func signedDistanceField(coverage: [UInt8], width: Int, height: Int,
                                    spread: Int) -> [UInt8] {
        let n = width * height
        let inf = 1e20
        var inside = [Double](repeating: 0, count: n)   // 0 at inside, inf elsewhere
        var outside = [Double](repeating: 0, count: n)  // 0 at outside, inf elsewhere
        for i in 0..<n {
            let isInside = coverage[i] >= 128
            inside[i] = isInside ? 0 : inf
            outside[i] = isInside ? inf : 0
        }
        let distToInside = distanceTransform(inside, width: width, height: height)   // for outside texels
        let distToOutside = distanceTransform(outside, width: width, height: height) // for inside texels

        var out = [UInt8](repeating: 0, count: n)
        let range = Double(2 * spread)
        for i in 0..<n {
            let isInside = coverage[i] >= 128
            let signed = isInside ? distToOutside[i].squareRoot() : -distToInside[i].squareRoot()
            let norm = 0.5 + signed / range
            out[i] = UInt8(max(0, min(255, (norm * 255).rounded())))
        }
        return out
    }

    /// 2D squared Euclidean distance transform (separable: columns then rows).
    private static func distanceTransform(_ f: [Double], width: Int, height: Int) -> [Double] {
        var grid = f
        // Columns.
        var col = [Double](repeating: 0, count: height)
        for x in 0..<width {
            for y in 0..<height { col[y] = grid[y * width + x] }
            let d = dt1d(col)
            for y in 0..<height { grid[y * width + x] = d[y] }
        }
        // Rows.
        var row = [Double](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width { row[x] = grid[y * width + x] }
            let d = dt1d(row)
            for x in 0..<width { grid[y * width + x] = d[x] }
        }
        return grid
    }

    /// 1D squared distance transform of a sampled function (the lower envelope of
    /// parabolas), per Felzenszwalb & Huttenlocher.
    private static func dt1d(_ f: [Double]) -> [Double] {
        let n = f.count
        guard n > 0 else { return f }
        var d = [Double](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)        // parabola locations in the envelope
        var z = [Double](repeating: 0, count: n + 1) // envelope boundaries
        let inf = 1e20
        var k = 0
        v[0] = 0; z[0] = -inf; z[1] = inf
        for q in 1..<n {
            var s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
            while s <= z[k] {
                k -= 1
                s = ((f[q] + Double(q * q)) - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
            }
            k += 1
            v[k] = q; z[k] = s; z[k + 1] = inf
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Double(q) { k += 1 }
            let diff = Double(q - v[k])
            d[q] = diff * diff + f[v[k]]
        }
        return d
    }

    // MARK: Packing

    /// Reserve a `width`×`height` cell with a shelf packer, returning its top-left
    /// origin. Rebuilds the page (clearing every cached slot) if it overflows — a
    /// blunt bound, like the geometry cache's, fine because a font's glyph set is
    /// small and stable after warm-up. `nil` only if the cell can't fit a fresh
    /// page (caught earlier by the oversize guard).
    private func pack(width: Int, height: Int) -> (Int, Int)? {
        let size = GlyphAtlas.pageSize
        let gutter = GlyphAtlas.gutter
        if penX + width + gutter > size {            // wrap to the next shelf
            penX = gutter
            penY += rowHeight + gutter
            rowHeight = 0
        }
        if penY + height + gutter > size {           // page full → rebuild
            reset()
        }
        guard penX + width <= size, penY + height <= size else { return nil }
        let origin = (penX, penY)
        penX += width + gutter
        rowHeight = max(rowHeight, height)
        return origin
    }

    /// Clear the page and every cached slot (a packer overflow). Glyphs re-cache on
    /// next use.
    private func reset() {
        for i in page.indices { page[i] = 0 }
        fonts.removeAll(keepingCapacity: true)
        penX = GlyphAtlas.gutter
        penY = GlyphAtlas.gutter
        rowHeight = 0
        dirty = true
        cachedTexture = nil
        cachedDeviceID = nil
        generation += 1
    }

    /// The page's bytes down to the last packed shelf: the rows a reader must
    /// carry to reproduce every slot handed out so far (the rest of the page is
    /// zero), one byte per texel, row 0 at the top, `webPageSize` wide. What the
    /// web recorder writes into the page as the atlas asset.
    func webPage() -> (bytes: [UInt8], rows: Int) {
        lock.lock(); defer { lock.unlock() }
        let rows = min(GlyphAtlas.pageSize, max(1, penY + rowHeight + GlyphAtlas.gutter))
        return (Array(page[0 ..< rows * GlyphAtlas.pageSize]), rows)
    }

    // MARK: GPU texture

    /// The atlas page as a Metal texture on `device`, (re)uploaded when the page
    /// changed. `r8Unorm` and **not** sRGB: it stores distance, not color, so the
    /// sample must stay raw (the fragment linearizes the fill color separately).
    /// Built and updated on the main thread during encoding, mirroring
    /// `Image.texture(for:)`.
    func texture(for device: MTLDevice) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        let id = ObjectIdentifier(device)
        if let cachedTexture, cachedDeviceID == id, !dirty { return cachedTexture }

        let texture: MTLTexture
        if let cachedTexture, cachedDeviceID == id {
            texture = cachedTexture          // same device, just re-upload the page
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm, width: GlyphAtlas.pageSize, height: GlyphAtlas.pageSize,
                mipmapped: false)
            desc.usage = .shaderRead
            desc.storageMode = ollinUploadStorageMode
            guard let made = device.makeTexture(descriptor: desc) else { return nil }
            texture = made
        }

        let region = MTLRegionMake2D(0, 0, GlyphAtlas.pageSize, GlyphAtlas.pageSize)
        page.withUnsafeBytes { raw in
            texture.replace(region: region, mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: GlyphAtlas.pageSize)
        }
        cachedTexture = texture
        cachedDeviceID = id
        dirty = false
        return texture
    }
}
