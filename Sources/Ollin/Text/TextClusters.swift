// Grouping shaped glyphs back into the characters a reader sees.

import Foundation
import CoreGraphics
import CoreText

/// One glyph the layout engine produced, in em units (the font at size 1) with
/// the pen at the line's left edge and the baseline at `y = 0`.
struct ShapedGlyph {
    /// The face this glyph came from. Font fallback can put several faces on one
    /// line, so a glyph id only means something beside its own font.
    let font: CTFont
    let glyph: CGGlyph
    /// Pen position: `x` grows rightward from the line's left edge, `y` grows
    /// upward from the baseline (the font's own orientation).
    let x: Double
    let y: Double
    /// How far this glyph moves the pen. A mark that sits on another letter
    /// advances nothing.
    let advance: Double
    /// The UTF-16 offset of the first source character this glyph came from.
    let stringIndex: Int
}

/// The glyphs that together stand for one thing a reader would call a character.
///
/// One glyph per character is the Latin case and almost nothing else. A Devanagari
/// syllable is several glyphs, one of which is drawn to the *left* of the letter it
/// follows. An Arabic letter carrying a vowel mark is two glyphs stacked at nearly
/// the same place. A ligature is the opposite: one glyph standing for two
/// characters. Anything that works per character has to work on this unit, not on
/// a glyph.
struct ShapedCluster {
    /// The source characters this cluster stands for.
    let text: String
    /// Its glyphs, in the order the layout engine gave them.
    let glyphs: [ShapedGlyph]
    /// The leftmost pen position in the cluster, em units.
    let originX: Double
    /// The pen advance of the whole cluster, em units.
    let advance: Double
}

enum TextClusters {
    /// Group `glyphs` into clusters against the string they came from, then order
    /// them **left to right on the canvas**.
    ///
    /// Visual order is the deliberate choice. A per-glyph effect wants to sweep
    /// across the drawing, and text on a path has to lay its clusters along the
    /// curve in the order they appear. For a right-to-left line that is the
    /// reverse of reading order, which is correct: the word still reads properly,
    /// because each cluster keeps its own place.
    static func group(_ glyphs: [ShapedGlyph], in string: String) -> [ShapedCluster] {
        // Where each user-perceived character starts, in UTF-16 offsets.
        var starts: [Int] = []
        var offset = 0
        for character in string {
            starts.append(offset)
            offset += character.utf16.count
        }
        let total = offset
        guard !starts.isEmpty else { return [] }

        // Which character each offset belongs to, so a glyph landing in the middle
        // of one (the vowel sign of a Devanagari syllable does) still finds it.
        var owner = [Int](repeating: 0, count: max(total, 1))
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : total
            for position in start..<end { owner[position] = index }
        }

        var buckets = [[ShapedGlyph]](repeating: [], count: starts.count)
        for glyph in glyphs {
            let position = min(max(glyph.stringIndex, 0), total - 1)
            buckets[owner[position]].append(glyph)
        }

        // Walk the characters in order. A character with no glyph of its own was
        // swallowed by a ligature, so it joins the cluster before it (the layout
        // engine reports a ligature at the *first* character it covers, in either
        // direction). One at the very start has nothing before it, so it waits for
        // the first cluster instead.
        var clusters: [ShapedCluster] = []
        var waiting: [Int] = []
        var currentCharacters: [Int] = []
        var currentGlyphs: [ShapedGlyph] = []
        var open = false

        func closeCurrent() {
            guard open else { return }
            clusters.append(make(characters: currentCharacters, glyphs: currentGlyphs,
                                starts: starts, total: total, string: string))
            open = false
        }

        for index in 0..<starts.count {
            if buckets[index].isEmpty {
                if open { currentCharacters.append(index) } else { waiting.append(index) }
                continue
            }
            closeCurrent()
            currentCharacters = waiting + [index]
            currentGlyphs = buckets[index]
            waiting = []
            open = true
        }
        closeCurrent()

        // Order by where each cluster sits, tie-broken by build order so a run
        // reproduces exactly.
        return clusters.enumerated()
            .sorted { ($0.element.originX, $0.offset) < ($1.element.originX, $1.offset) }
            .map(\.element)
    }

    private static func make(characters: [Int], glyphs: [ShapedGlyph],
                             starts: [Int], total: Int, string: String) -> ShapedCluster {
        let from = starts[characters.first ?? 0]
        let last = characters.last ?? 0
        let to = last + 1 < starts.count ? starts[last + 1] : total
        let utf16 = Array(string.utf16)
        let text = from < to && to <= utf16.count
            ? String(utf16CodeUnits: Array(utf16[from..<to]), count: to - from)
            : ""
        let originX = glyphs.map(\.x).min() ?? 0
        let advance = glyphs.reduce(0) { $0 + $1.advance }
        return ShapedCluster(text: text, glyphs: glyphs, originX: originX, advance: advance)
    }
}
