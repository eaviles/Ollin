import Foundation

public extension StrokeFont {
    /// Parse a Hershey vector font from `.jhf` text.
    ///
    /// The `.jhf` format stores one glyph per record: a 5-character glyph number,
    /// a 3-character vertex count, then two characters per vertex. Each coordinate
    /// is the character's value relative to `'R'` (so `'R'` is 0, `'P'` is −2). The
    /// first vertex pair is the glyph's left/right pen bounds; a `" R"` pair (a
    /// space) lifts the pen, starting a new stroke. Per-face `.jhf` files list one
    /// glyph per printable ASCII character in order, so the Nth record maps to
    /// character `32 + N` (record 0 is the space).
    ///
    /// Returns `nil` if no glyphs parse.
    init?(jhf contents: String) {
        var glyphs: [Character: StrokeGlyph] = [:]
        let baseline = 9.0   // Hershey's shared coordinate system: baseline at +9.
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        var lineIndex = 0
        var recordIndex = 0

        func coord(_ c: Character) -> Double { Double(Int(c.asciiValue ?? 82) - 82) }

        while lineIndex < lines.count {
            var chars = Array(lines[lineIndex]); lineIndex += 1
            // A glyph record needs the number (5) + vertex count (3) + at least the
            // left/right pair (2). Anything else (a blank line) is skipped without
            // consuming a character slot.
            guard chars.count >= 10,
                  let count = Int(String(chars[5..<8]).trimmingCharacters(in: .whitespaces)),
                  count >= 1 else { continue }
            let needed = 8 + count * 2
            // Long glyphs can wrap onto following (header-less) lines — pull more
            // until the record is complete.
            while chars.count < needed && lineIndex < lines.count {
                chars += Array(lines[lineIndex]); lineIndex += 1
            }
            guard chars.count >= needed else { continue }

            let left = coord(chars[8])

            var polylines: [[Vector2]] = []
            var current: [Vector2] = []
            var p = 10
            while p + 1 < needed {
                let cx = chars[p], cy = chars[p + 1]
                p += 2
                if cx == " " {                       // pen up: end this stroke
                    if current.count >= 2 { polylines.append(current) }
                    current = []
                    continue
                }
                // Pen origin to x = 0, baseline to y = 0.
                current.append(Vector2(coord(cx) - left, coord(cy) - baseline))
            }
            if current.count >= 2 { polylines.append(current) }

            guard 32 + recordIndex < 256 else { break }
            let character = Character(UnicodeScalar(UInt8(32 + recordIndex)))
            recordIndex += 1
            glyphs[character] = StrokeGlyph(advance: coord(chars[9]) - left, polylines: polylines)
        }

        guard !glyphs.isEmpty else { return nil }
        // Hershey caps span y −12…+9 (cap height 21) with descenders to ~+16
        // (descent 7); those are the layout metrics. Glyphs that ink beyond still
        // draw — the em is only the scale reference.
        self.init(glyphs: glyphs, unitsPerEm: 28, ascentUnits: 21, descentUnits: 7,
                  lineGapUnits: 8, spaceAdvanceUnits: glyphs[" "]?.advance)
    }

    /// Parse a Hershey `.jhf` font from a file URL. Returns `nil` if the file
    /// can't be read or parsed.
    init?(jhfContentsOf url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(jhf: contents)
    }
}
