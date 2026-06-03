import Foundation
import CoreGraphics
import ImageIO

/// Loading a `BitmapFont` from a **Playdate `.fnt`** file — the line-oriented text
/// format Panic's Playdate uses, and the format a large pool of free community
/// pixel fonts ship in. A `.fnt` is a plaintext index (per-glyph advance widths,
/// `tracking`, and kerning pairs) paired with a 1-bit glyph strike, either an
/// external `<name>-table-<W>-<H>.png` beside it or embedded as base64 inside the
/// file. The strike decodes through ImageIO; each fixed cell becomes a
/// `BitmapGlyph`, so the result draws through the same `drawText` path as any
/// other bitmap font — no rasterization, no new pipeline.
///
/// ```swift
/// // Bundled beside a sketch (the usual case — an embedded-strike .fnt is one file):
/// let font = BitmapFont(resource: "MyFont.fnt", in: .module) ?? .builtin
/// textFont(font)
/// drawText("hello", x, y)
///
/// // Or load it from anywhere — a string is all the embedded form needs:
/// let text = try String(contentsOf: someURL, encoding: .utf8)
/// let font = BitmapFont(fnt: text)!
/// ```
public extension BitmapFont {
    /// Parse a Playdate font from its `.fnt` text. Works for the **embedded** form
    /// (the strike base64'd into the file); a font that references an *external*
    /// `-table-W-H.png` has no sibling to find from a bare string, so load those
    /// with `init?(fntContentsOf:)` instead. Returns `nil` if the text has no
    /// usable glyphs or its strike can't be decoded.
    init?(fnt text: String) {
        self.init(fnt: text, externalStrike: { nil })
    }

    /// Parse a Playdate font from raw `.fnt` bytes (UTF-8). Embedded-strike form
    /// only — see `init?(fnt:)`.
    init?(fntData data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        self.init(fnt: text)
    }

    /// Load a Playdate font from a `.fnt` file URL. Handles both forms: an embedded
    /// strike, or an external `<name>-table-<W>-<H>.png` discovered in the same
    /// directory.
    init?(fntContentsOf url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        self.init(fnt: text, externalStrike: {
            BitmapFont.findExternalStrike(base: base, in: directory)
        })
    }
}

private extension BitmapFont {
    /// One decoded glyph strike: its pixel size and a top-down lit/unlit grid.
    typealias Strike = (width: Int, height: Int, lit: [Bool])

    /// The shared parser. `externalStrike` supplies `(pngData, cellW, cellH)` for
    /// the external form when the embedded form is absent (it returns `nil` when
    /// there's no file context).
    init?(fnt text: String, externalStrike: () -> (data: Data, cellW: Int, cellH: Int)?) {
        var tracking = 1
        var embeddedWidth = 0, embeddedHeight = 0
        var embeddedData: Data? = nil
        // Glyphs in sprite-sheet order (row-major); kerning is order-independent.
        var order: [(character: Character, width: Int)] = []
        var kerning: [GlyphPair: Int] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("--") { continue }
            if line.hasPrefix("tracking=") {
                tracking = Int(line.dropFirst("tracking=".count)) ?? tracking
            } else if line.hasPrefix("width=") {
                embeddedWidth = Int(line.dropFirst("width=".count)) ?? 0
            } else if line.hasPrefix("height=") {
                embeddedHeight = Int(line.dropFirst("height=".count)) ?? 0
            } else if line.hasPrefix("data=") {
                embeddedData = Data(base64Encoded: String(line.dropFirst("data=".count)))
            } else if line.hasPrefix("datalen=") {
                continue   // base64 length, not needed for decoding
            } else {
                // A glyph line (`<char> <width>`), a kerning line (`<char><char>
                // <offset>`), or the space keyword (`space <width>`). The key is
                // everything up to the first run of whitespace; the value is the
                // trailing integer.
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 2, let value = Int(fields[fields.count - 1]) else { continue }
                let key = fields[0]
                if key == "space" {
                    order.append((" ", value))
                } else if let char = key.first, key.count == 1 {
                    order.append((char, value))
                } else if key.count == 2 {
                    let pair = Array(key)
                    kerning[GlyphPair(pair[0], pair[1])] = value
                }
            }
        }

        guard !order.isEmpty else { return nil }

        // Resolve the strike: embedded base64 first, else the external sibling.
        let cellW: Int, cellH: Int, strikeData: Data
        if let data = embeddedData, embeddedWidth > 0, embeddedHeight > 0 {
            strikeData = data; cellW = embeddedWidth; cellH = embeddedHeight
        } else if let ext = externalStrike() {
            strikeData = ext.data; cellW = ext.cellW; cellH = ext.cellH
        } else {
            return nil
        }
        guard cellW > 0, cellH > 0,
              let strike = BitmapFont.decodeStrike(strikeData),
              strike.width >= cellW, strike.height >= cellH else { return nil }

        let columns = strike.width / cellW
        guard columns > 0 else { return nil }

        var glyphs: [Character: BitmapGlyph] = [:]
        glyphs.reserveCapacity(order.count)
        for (index, entry) in order.enumerated() {
            let cellRow = index / columns
            let cellCol = index % columns
            let x0 = cellCol * cellW
            let y0 = cellRow * cellH
            guard y0 + cellH <= strike.height, x0 + cellW <= strike.width else { continue }
            // Pack the full fixed cell (ink is left-justified, the rest blank); the
            // glyph's own `width` is the advance, not the read width.
            var rows: [UInt32] = []
            rows.reserveCapacity(cellH)
            for r in 0..<cellH {
                var mask: UInt32 = 0
                for c in 0..<cellW where strike.lit[(y0 + r) * strike.width + (x0 + c)] {
                    mask |= 1 << (cellW - 1 - c)
                }
                rows.append(mask)
            }
            glyphs[entry.character] = BitmapGlyph(
                width: cellW, height: cellH, rows: rows,
                advance: entry.width + tracking)
        }

        guard !glyphs.isEmpty else { return nil }
        let spaceAdvance = glyphs[" "]?.advance ?? (cellW + tracking)
        self.init(glyphs: glyphs, pixelHeight: cellH,
                  baseline: cellH, lineHeight: cellH + 1,
                  spaceAdvance: spaceAdvance, kerning: kerning)
    }

    /// Find a `<base>-table-<W>-<H>.png` strike beside the `.fnt`, reading the cell
    /// dimensions from its filename.
    static func findExternalStrike(base: String, in directory: URL) -> (data: Data, cellW: Int, cellH: Int)? {
        let prefix = base + "-table-"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return nil }
        for name in entries where name.hasPrefix(prefix) && name.hasSuffix(".png") {
            let dims = name.dropFirst(prefix.count).dropLast(".png".count).split(separator: "-")
            guard dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]),
                  let data = try? Data(contentsOf: directory.appendingPathComponent(name))
            else { continue }
            return (data, w, h)
        }
        return nil
    }

    /// Decode a PNG strike to a top-down lit grid. A pixel is lit when it's opaque
    /// and dark — covering both the embedded RGBA form (black ink on transparent)
    /// and the spec's 1-bit black-on-white external PNGs.
    static func decodeStrike(_ data: Data) -> Strike? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }

        let bytesPerRow = w * 4
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: h * bytesPerRow, alignment: 1)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: h * bytesPerRow)

        guard let ctx = CGContext(
            data: buffer, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // No y-flip: drawing the source image into this bitmap context already
        // lands row 0 at the top, which is the order the cells are indexed in
        // (row-major, top-down). Adding the usual translate/scale flip here would
        // turn the strike upside down — verified against the reference fonts.
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let pixels = buffer.bindMemory(to: UInt8.self, capacity: h * bytesPerRow)
        var lit = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1])
            let b = Int(pixels[i * 4 + 2]), a = Int(pixels[i * 4 + 3])
            let luminance = (r * 299 + g * 587 + b * 114) / 1000
            lit[i] = a > 127 && luminance < 128
        }
        return (w, h, lit)
    }
}
