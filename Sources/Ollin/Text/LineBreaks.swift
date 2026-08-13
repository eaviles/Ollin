// Where a line of text is allowed to break, from the system's own line-break
// rules rather than from the spaces in the string.

import Foundation

/// Line-break opportunities in a string.
///
/// Wrapping text into a box means choosing where a line may end. Splitting on
/// spaces answers that for English and gets it wrong for most of the world:
/// Japanese and Chinese write without spaces and may break between almost any
/// two characters, and Thai writes without spaces but breaks only between
/// *words*, which takes a dictionary to find. The system knows all of this, so
/// ask it instead of guessing.
enum LineBreaks {
    /// The UTF-16 offsets a line may start at, always beginning with 0. Offset
    /// `n` (the end of the string) is never included, so consecutive entries
    /// bound one breakable piece and the last piece runs to the end.
    ///
    /// The tokenizer is created with **no locale**, which is load-bearing: a
    /// locale would make wrapping depend on the machine's own settings and an
    /// export would stop reproducing. Measured across English, Japanese and Thai,
    /// a nil locale and an explicit `en_US`, `th_TH`, or the current locale all
    /// return the same offsets, so nothing is lost by leaving it out.
    static func opportunities(in string: String) -> [Int] {
        let text = string as CFString
        let length = CFStringGetLength(text)
        guard length > 0 else { return [] }
        guard let tokenizer = CFStringTokenizerCreate(
            nil, text, CFRangeMake(0, length), kCFStringTokenizerUnitLineBreak, nil) else {
            return [0]
        }
        var offsets: [Int] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let start = CFStringTokenizerGetCurrentTokenRange(tokenizer).location
            if offsets.last != start { offsets.append(start) }
        }
        if offsets.first != 0 { offsets.insert(0, at: 0) }
        return offsets
    }

    /// `string` cut into the pieces a line may be built from, in order, so that
    /// joining them reproduces the string exactly. A piece carries its own
    /// trailing space, so a caller measuring a candidate line should trim.
    static func pieces(of string: String) -> [String] {
        let offsets = opportunities(in: string)
        guard offsets.count > 1 else { return string.isEmpty ? [] : [string] }
        let utf16 = Array(string.utf16)
        var out: [String] = []
        out.reserveCapacity(offsets.count)
        for (index, start) in offsets.enumerated() {
            let end = index + 1 < offsets.count ? offsets[index + 1] : utf16.count
            guard start < end, end <= utf16.count else { continue }
            out.append(String(utf16CodeUnits: Array(utf16[start..<end]), count: end - start))
        }
        return out
    }
}
