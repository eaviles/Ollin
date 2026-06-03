import Foundation

/// Loading a `BitmapFont` from a **BDF** file (Glyph Bitmap Distribution Format,
/// the standard text format for bitmap fonts — what the X11 catalog, u8g2, and
/// Cozette ship). This is how the bundled default font is loaded, and how a user
/// can drop in their own pixel font.
public extension BitmapFont {
    /// Parse a BDF font from its raw file bytes. Returns `nil` if the data isn't
    /// valid UTF-8 or has no usable glyphs.
    init?(bdfData data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        self.init(bdf: text)
    }

    /// Load and parse a BDF font from a file URL.
    init?(bdfContentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(bdfData: data)
    }

    /// Parse a BDF font from its text. Reads the font metrics (`FONT_ASCENT`,
    /// `FONT_DESCENT`, `CAP_HEIGHT`, `PIXEL_SIZE`) and each `STARTCHAR…ENDCHAR`
    /// glyph (`ENCODING`, `DWIDTH`, `BBX`, and the hex `BITMAP` rows), mapping
    /// BDF's baseline-relative bounding box onto `BitmapGlyph`'s top-down cell.
    init?(bdf text: String) {
        var fontAscent = 0, fontDescent = 0, capHeight = 0, pixelSize = 0
        var glyphs: [Character: BitmapGlyph] = [:]

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var i = 0
        let n = lines.count

        func fields(_ line: Substring) -> [Substring] {
            line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        }

        while i < n {
            let parts = fields(lines[i])
            guard let key = parts.first else { i += 1; continue }
            switch key {
            case "FONT_ASCENT":  fontAscent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            case "FONT_DESCENT": fontDescent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            case "CAP_HEIGHT":   capHeight = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            case "PIXEL_SIZE":   pixelSize = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            case "STARTCHAR":
                var encoding = -1, advance = 0
                var bbw = 0, bbh = 0, bbxoff = 0, bbyoff = 0
                var rows: [UInt32] = []
                i += 1
                inner: while i < n {
                    let f = fields(lines[i])
                    guard let k = f.first else { i += 1; continue }
                    switch k {
                    case "ENCODING": if f.count > 1 { encoding = Int(f[1]) ?? -1 }
                    case "DWIDTH":   if f.count > 1 { advance = Int(f[1]) ?? 0 }
                    case "BBX":
                        if f.count > 4 {
                            bbw = Int(f[1]) ?? 0; bbh = Int(f[2]) ?? 0
                            bbxoff = Int(f[3]) ?? 0; bbyoff = Int(f[4]) ?? 0
                        }
                    case "BITMAP":
                        rows.reserveCapacity(bbh)
                        let mask: UInt32 = bbw >= 32 ? .max : (bbw <= 0 ? 0 : (UInt32(1) << bbw) - 1)
                        var r = 0
                        while r < bbh, i + 1 < n {
                            i += 1
                            let hex = lines[i].trimmingCharacters(in: .whitespaces)
                            let paddedBits = hex.count * 4
                            let value = UInt64(hex, radix: 16) ?? 0
                            let shift = paddedBits - bbw
                            let packed = shift > 0 ? UInt32(truncatingIfNeeded: value >> shift)
                                                   : UInt32(truncatingIfNeeded: value)
                            rows.append(packed & mask)
                            r += 1
                        }
                    case "ENDCHAR":
                        break inner
                    default:
                        break
                    }
                    i += 1
                }
                if encoding >= 0, let scalar = Unicode.Scalar(encoding) {
                    // BDF places the bbox by its lower-left, `bbyoff` above the
                    // baseline; convert to a top-down cell offset from the line top.
                    let yOffset = fontAscent - bbyoff - bbh
                    glyphs[Character(scalar)] = BitmapGlyph(
                        width: bbw, height: bbh, rows: rows, advance: advance,
                        xOffset: bbxoff, yOffset: yOffset)
                }
            default:
                break
            }
            i += 1
        }

        guard !glyphs.isEmpty else { return nil }
        // `textSize` reads as the capital height, so use CAP_HEIGHT as the divisor
        // (falling back to the ascent); the baseline and line pitch come from the
        // font's own ascent/descent.
        let cap = capHeight > 0 ? capHeight : (fontAscent > 0 ? fontAscent : 1)
        let pitch = pixelSize > 0 ? pixelSize : (fontAscent + fontDescent)
        self.init(glyphs: glyphs, pixelHeight: cap,
                  baseline: fontAscent > 0 ? fontAscent : cap,
                  lineHeight: pitch > 0 ? pitch : cap + 1)
    }
}
