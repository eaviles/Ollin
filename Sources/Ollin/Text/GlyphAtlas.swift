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
/// `OutlineFont` (like its outline/geometry caches). The glyphs live on a
/// `Page`, and a slot names the page it was placed on. When the page fills,
/// the atlas starts a fresh one and leaves the full page as it was: a glyph
/// placed earlier in the same frame, or baked into a retained batch, keeps
/// sampling the page that holds it, and a batch holds its page alive for as
/// long as it draws. The atlas is `@unchecked Sendable` to satisfy the
/// `Sendable` `OutlineFont` that holds it; its lock and each page's own guard
/// the mutable state.
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
        let page: Page                       // the page the glyph was placed on
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

    // MARK: Atlas state

    /// The page new glyphs are placed on. A full page is never cleared: the
    /// atlas moves on to a fresh one, so every slot handed out stays true.
    private var page = Page()
    /// Cached slots, keyed by run font (fallback puts glyphs from several faces on
    /// one line) then glyph id — mirrors `GlyphPathCache`. A cached `nil` records a
    /// glyph that draws nothing (a space), so it's not re-rasterized every frame.
    /// Emptied when the atlas moves to a fresh page, so a glyph asked for again
    /// is placed on the page that is current then.
    private var fonts: [(font: CTFont, slots: [CGGlyph: Slot?])] = []

    /// Counts the fresh pages started because the current one filled. A reader
    /// that wants to know whether a long run of text moved on (`SoakTests`)
    /// compares it against an earlier value.
    private(set) var generation = 0

    /// The page's texel width (and height), for a reader that carries the page.
    static var webPageSize: Int { pageSize }

    /// Guards the current page and the slot cache. `slot(for:)` runs on the main
    /// draw thread in normal use, but `OutlineFont` is a public `Sendable`
    /// reachable from the `.system` globals, so a sketch could reach the atlas
    /// off the main actor; the lock keeps the cache from corrupting. A cache hit
    /// holds it only briefly; the one-time rasterize-and-pack runs under it
    /// during warm-up.
    private let lock = OSAllocatedUnfairLock()

    /// How many glyphs the current page holds a slot for, across every face on
    /// it. A full page is left behind, so this is bounded by what one page fits
    /// however much text a long run feeds it (`SoakTests`).
    var glyphCount: Int {
        lock.lock(); defer { lock.unlock() }
        return fonts.reduce(0) { $0 + $1.slots.count }
    }

    /// The page new glyphs go on, for a test that reads which page a slot
    /// landed on.
    var currentPage: Page {
        lock.lock(); defer { lock.unlock() }
        return page
    }

    // MARK: Slots

    /// The atlas slot for `glyph` in `font`, built on first use. `nil` for a glyph
    /// with no contours (a space) or one that can't be placed (larger than a
    /// page); the caller draws nothing for it.
    func slot(for glyph: CGGlyph, font: CTFont) -> Slot? {
        lock.lock(); defer { lock.unlock() }
        if let index = fonts.firstIndex(where: { CFEqual($0.font, font) }),
           let hit = fonts[index].slots[glyph] {
            return hit
        }
        // Making a slot can fill the page and move on to a fresh one, which
        // forgets every face, so the face is found again afterwards: an index
        // taken before would point past the end of the emptied list.
        let made = make(glyph, font)
        if let index = fonts.firstIndex(where: { CFEqual($0.font, font) }) {
            fonts[index].slots[glyph] = made
        } else {
            fonts.append((font: font, slots: [glyph: made]))
        }
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
        // A full page is left as it is and the glyph goes on a fresh one, so
        // every slot handed out before still names bytes that hold its glyph.
        var placed = page.place(cell, width: cellW, height: cellH)
        if placed == nil {
            page = Page()
            fonts.removeAll(keepingCapacity: true)
            generation += 1
            placed = page.place(cell, width: cellW, height: cellH)
        }
        guard let (px, py) = placed else { return nil }

        let p = Float(GlyphAtlas.pageSize)
        return Slot(page: page, u0: Float(px) / p, v0: Float(py) / p,
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

    // MARK: Pages

    /// One `pageSize`² page of distance fields, filled by a shelf packer and
    /// never cleared: a page only gains cells, so the bytes under a slot never
    /// change once it is handed out. A draw batch holds the page its glyphs
    /// sample, which keeps a full page alive for as long as something draws
    /// through it.
    final class Page: @unchecked Sendable {

        /// Row-major, one byte per texel: the normalized signed distance,
        /// `0.5` = edge, `> 0.5` inside.
        private var bytes = [UInt8](repeating: 0, count: GlyphAtlas.pageSize * GlyphAtlas.pageSize)

        /// Shelf packer cursor: current row origin and the tallest cell on the row.
        private var penX = GlyphAtlas.gutter
        private var penY = GlyphAtlas.gutter
        private var rowHeight = 0

        /// The bytes changed since the last upload.
        private var dirty = true
        private var cachedTexture: MTLTexture?
        private var cachedDeviceID: ObjectIdentifier?

        /// Guards the bytes, the packer, and the texture: the atlas places cells
        /// while a frame records, and the renderer uploads while it encodes.
        private let lock = OSAllocatedUnfairLock()

        /// Reserve a `width`×`height` cell with a shelf packer and copy `cell`
        /// (row 0 = top) into it, returning its top-left origin, or `nil` when
        /// the page has no room left for it.
        func place(_ cell: [UInt8], width: Int, height: Int) -> (Int, Int)? {
            lock.lock(); defer { lock.unlock() }
            let size = GlyphAtlas.pageSize
            let gutter = GlyphAtlas.gutter
            var x = penX, y = penY, row = rowHeight
            if x + width + gutter > size {           // wrap to the next shelf
                x = gutter
                y += row + gutter
                row = 0
            }
            guard x + width <= size, y + height + gutter <= size else { return nil }
            for r in 0..<height {
                let src = r * width
                let dst = (y + r) * size + x
                bytes.replaceSubrange(dst..<(dst + width), with: cell[src..<(src + width)])
            }
            penX = x + width + gutter
            penY = y
            rowHeight = max(row, height)
            dirty = true
            return (x, y)
        }

        /// The page's bytes down to the last packed shelf: the rows a reader must
        /// carry to reproduce every slot on it (the rest of the page is zero), one
        /// byte per texel, row 0 at the top, `webPageSize` wide. What the web
        /// recorder writes into the page as an atlas asset.
        func webPage() -> (bytes: [UInt8], rows: Int) {
            lock.lock(); defer { lock.unlock() }
            let rows = min(GlyphAtlas.pageSize, max(1, penY + rowHeight + GlyphAtlas.gutter))
            return (Array(bytes[0 ..< rows * GlyphAtlas.pageSize]), rows)
        }

        /// The page as a Metal texture on `device`. `r8Unorm` and **not** sRGB: it
        /// stores distance, not color, so the sample must stay raw (the fragment
        /// linearizes the fill color separately). A page that gained cells since
        /// the last upload gets a fresh texture rather than an upload into the
        /// old one, which a frame still in flight may be reading. Built on the
        /// main thread during encoding, mirroring `Image.texture(for:)`.
        func texture(for device: MTLDevice) -> MTLTexture? {
            lock.lock(); defer { lock.unlock() }
            let id = ObjectIdentifier(device)
            if let cachedTexture, cachedDeviceID == id, !dirty { return cachedTexture }

            let size = GlyphAtlas.pageSize
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm, width: size, height: size, mipmapped: false)
            desc.usage = .shaderRead
            desc.storageMode = ollinUploadStorageMode
            guard let texture = device.makeTexture(descriptor: desc) else { return nil }
            let region = MTLRegionMake2D(0, 0, size, size)
            bytes.withUnsafeBytes { raw in
                texture.replace(region: region, mipmapLevel: 0,
                                withBytes: raw.baseAddress!, bytesPerRow: size)
            }
            cachedTexture = texture
            cachedDeviceID = id
            dirty = false
            return texture
        }
    }
}
