// Moving a shape by editing the file it was written in.
//
// A draw call remembers where it was written (`SourceSite`, captured through
// `#line`/`#column` default arguments). This is the other half: given that
// place and how far the shape moved on screen, find the numbers in the file
// and write the new ones.
//
// It is a scanner over the file's bytes, not a parser: the only thing it has
// to understand is where one call's arguments start and end, and whether an
// argument is a plain number. Every edit replaces the text of a number that is
// already there, so the author's spacing, comments, and line breaks all
// survive, and the file stays the file they wrote.
//
// Columns are UTF-8 byte offsets, which is what Swift reports, so the whole
// scan works in bytes and the text is rebuilt once at the end. A file with an
// accented comment above the call still edits at the right place.

import Foundation
import Ollin

/// Rewriting one draw call's coordinates in the source it was written in.
package enum SourceEdit {

    /// Why a shape could not be moved by editing the file.
    package enum Failure: Error, Equatable {
        /// Nothing that looks like a call is where the site says it is. The
        /// file has been edited since the frame was drawn.
        case callNotFound
        /// The call has fewer arguments than its shape needs.
        case missingArgument(index: Int)
        /// A coordinate is written as something other than a plain number, so
        /// there is no number to change. `argument` is what stands there
        /// (`width / 2`, `cx`, `p.x + 10`).
        case computed(argument: String)
        /// A point argument is not written as a plain `Vector2(x, y)`.
        case notAPoint(argument: String)
    }

    /// The file's text with the call at `line`/`column` moved by `delta`.
    ///
    /// `line` is 1-based and `column` is the call's opening parenthesis, in
    /// UTF-8 bytes from the start of that line: exactly what `#line` and
    /// `#column` report at the call site.
    ///
    /// A number written without a fraction stays without one (a shape placed
    /// at whole points keeps whole points, so a drag lands on the grid); one
    /// written with a fraction keeps as many digits as the author wrote.
    package static func moving(_ source: String, line: Int, column: Int,
                               move: SourceMove, by delta: Vector2) throws -> String {
        var bytes = Array(source.utf8)
        guard let open = openParen(in: bytes, line: line, column: column) else {
            throw Failure.callNotFound
        }
        let args = try arguments(in: bytes, openParen: open)
        // Every replacement is worked out against the original text first, then
        // applied back to front, so an earlier edit cannot shift a later range.
        var edits: [(Range<Int>, [UInt8])] = []
        switch move {
        case .scalars(let indices):
            for (n, index) in indices.enumerated() {
                guard index < args.count else { throw Failure.missingArgument(index: index) }
                let step = n.isMultiple(of: 2) ? delta.x : delta.y
                edits.append(try moved(bytes, args[index], by: step))
            }
        case .points(let indices):
            for index in indices {
                guard index < args.count else { throw Failure.missingArgument(index: index) }
                edits.append(contentsOf: try movedPoint(bytes, args[index], by: delta))
            }
        }
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            bytes.replaceSubrange(range, with: replacement)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Finding the call

    /// The byte index of the call's `(`. Takes the reported column when it
    /// lands on one, and otherwise looks along the line: a formatter that
    /// reflowed the file leaves the call on its line but not at its column.
    private static func openParen(in bytes: [UInt8], line: Int, column: Int) -> Int? {
        guard line >= 1, column >= 1 else { return nil }
        var index = 0, current = 1
        while current < line, index < bytes.count {
            if bytes[index] == UInt8(ascii: "\n") { current += 1 }
            index += 1
        }
        guard current == line else { return nil }
        let lineStart = index
        var lineEnd = index
        while lineEnd < bytes.count, bytes[lineEnd] != UInt8(ascii: "\n") { lineEnd += 1 }
        let at = lineStart + column - 1
        if at < lineEnd, bytes[at] == UInt8(ascii: "(") { return at }
        var scan = lineStart
        while scan < lineEnd {
            if bytes[scan] == UInt8(ascii: "(") { return scan }
            scan += 1
        }
        return nil
    }

    /// The byte ranges of each argument's *value*, in order, for the call whose
    /// `(` is at `openParen`. A label (`center:`) is not part of the value.
    private static func arguments(in bytes: [UInt8], openParen: Int) throws -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var depth = 0
        var start = openParen + 1
        var index = openParen
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index = endOfString(bytes, from: index)
                continue
            case UInt8(ascii: "/") where index + 1 < bytes.count:
                if bytes[index + 1] == UInt8(ascii: "/") || bytes[index + 1] == UInt8(ascii: "*") {
                    index = endOfComment(bytes, from: index)
                    continue
                }
            case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
            case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
                if depth == 0 {
                    if start < index { ranges.append(value(in: bytes, start ..< index)) }
                    return ranges
                }
            case UInt8(ascii: ",") where depth == 1:
                ranges.append(value(in: bytes, start ..< index))
                start = index + 1
            default:
                break
            }
            index += 1
        }
        throw Failure.callNotFound
    }

    /// One argument's range narrowed to its value: no surrounding whitespace,
    /// and no `label:` in front of it.
    private static func value(in bytes: [UInt8], _ range: Range<Int>) -> Range<Int> {
        var trimmed = trim(bytes, range)
        // A label is a name followed by a colon, before anything else. A
        // ternary's colon is never first, so it cannot be mistaken for one.
        var scan = trimmed.lowerBound
        while scan < trimmed.upperBound, isNameByte(bytes[scan]) { scan += 1 }
        if scan > trimmed.lowerBound {
            var colon = scan
            while colon < trimmed.upperBound, isSpace(bytes[colon]) { colon += 1 }
            if colon < trimmed.upperBound, bytes[colon] == UInt8(ascii: ":") {
                trimmed = trim(bytes, (colon + 1) ..< trimmed.upperBound)
            }
        }
        return trimmed
    }

    private static func trim(_ bytes: [UInt8], _ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound, upper = range.upperBound
        while lower < upper, isSpace(bytes[lower]) { lower += 1 }
        while upper > lower, isSpace(bytes[upper - 1]) { upper -= 1 }
        return lower ..< upper
    }

    static func isSpace(_ b: UInt8) -> Bool {
        b == UInt8(ascii: " ") || b == UInt8(ascii: "\n") || b == UInt8(ascii: "\t")
            || b == UInt8(ascii: "\r")
    }

    static func isDigit(_ b: UInt8) -> Bool {
        b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9")
    }

    static func isNameByte(_ b: UInt8) -> Bool {
        isDigit(b) || (b | 0x20) >= UInt8(ascii: "a") && (b | 0x20) <= UInt8(ascii: "z")
            || b == UInt8(ascii: "_") || b >= 0x80
    }

    /// The index just past a string literal starting at `index` (a `"`),
    /// including the `"""` and raw `#"` forms, so a comma inside a string is
    /// never read as an argument separator.
    static func endOfString(_ bytes: [UInt8], from index: Int) -> Int {
        let quote = UInt8(ascii: "\"")
        // A multi-line literal ends at its own three quotes.
        if index + 2 < bytes.count, bytes[index + 1] == quote, bytes[index + 2] == quote {
            var scan = index + 3
            while scan + 2 < bytes.count {
                if bytes[scan] == quote, bytes[scan + 1] == quote, bytes[scan + 2] == quote {
                    return scan + 3
                }
                scan += 1
            }
            return bytes.count
        }
        var scan = index + 1
        while scan < bytes.count {
            if bytes[scan] == UInt8(ascii: "\\") { scan += 2; continue }
            if bytes[scan] == quote { return scan + 1 }
            if bytes[scan] == UInt8(ascii: "\n") { return scan }   // unterminated
            scan += 1
        }
        return bytes.count
    }

    /// The index just past a comment starting at `index`. Block comments nest
    /// in Swift, so the depth is counted rather than the first `*/` taken.
    static func endOfComment(_ bytes: [UInt8], from index: Int) -> Int {
        if bytes[index + 1] == UInt8(ascii: "/") {
            var scan = index + 2
            while scan < bytes.count, bytes[scan] != UInt8(ascii: "\n") { scan += 1 }
            return scan
        }
        var scan = index + 2, depth = 1
        while scan + 1 < bytes.count {
            if bytes[scan] == UInt8(ascii: "/"), bytes[scan + 1] == UInt8(ascii: "*") {
                depth += 1; scan += 2; continue
            }
            if bytes[scan] == UInt8(ascii: "*"), bytes[scan + 1] == UInt8(ascii: "/") {
                depth -= 1; scan += 2
                if depth == 0 { return scan }
                continue
            }
            scan += 1
        }
        return bytes.count
    }

    // MARK: Reading and writing one number

    /// A number written in the source: its value, and how the author wrote it.
    private struct Literal {
        let value: Double
        /// Digits after the point, or `nil` when it was written whole.
        let fractionDigits: Int?
    }

    private static func literal(_ bytes: [UInt8], _ range: Range<Int>) -> Literal? {
        guard !range.isEmpty else { return nil }
        var scan = range.lowerBound
        if bytes[scan] == UInt8(ascii: "-") || bytes[scan] == UInt8(ascii: "+") { scan += 1 }
        var sawDigit = false, fraction: Int? = nil
        var counting = false, digitsAfterPoint = 0
        while scan < range.upperBound {
            let b = bytes[scan]
            if isDigit(b) {
                sawDigit = true
                if counting { digitsAfterPoint += 1 }
            } else if b == UInt8(ascii: ".") {
                guard !counting else { return nil }          // a second point
                counting = true
            } else if b == UInt8(ascii: "_") {
                // A grouped literal (`1_000`) reads fine; it just loses its
                // grouping when rewritten.
            } else {
                return nil                                   // an exponent, a name, an operator
            }
            scan += 1
        }
        guard sawDigit else { return nil }
        if counting { fraction = digitsAfterPoint }
        let text = String(decoding: bytes[range], as: UTF8.self).replacingOccurrences(of: "_", with: "")
        guard let value = Double(text) else { return nil }
        return Literal(value: value, fractionDigits: fraction)
    }

    /// The replacement for one scalar argument moved by `step`.
    private static func moved(_ bytes: [UInt8], _ range: Range<Int>,
                              by step: Double) throws -> (Range<Int>, [UInt8]) {
        guard let literal = literal(bytes, range) else {
            throw Failure.computed(argument: String(decoding: bytes[range], as: UTF8.self))
        }
        return (range, Array(written(literal.value + step, like: literal).utf8))
    }

    /// The replacements for one `Vector2(x, y)` argument moved by `delta`.
    private static func movedPoint(_ bytes: [UInt8], _ range: Range<Int>,
                                   by delta: Vector2) throws -> [(Range<Int>, [UInt8])] {
        let text = String(decoding: bytes[range], as: UTF8.self)
        // The value has to be a `Vector2` written out with its numbers, since
        // there is nowhere else to put them.
        guard text.hasPrefix("Vector2"), let open = bytes[range].firstIndex(of: UInt8(ascii: "(")),
              let inner = try? arguments(in: bytes, openParen: open), inner.count == 2 else {
            throw Failure.notAPoint(argument: text)
        }
        return [try moved(bytes, inner[0], by: delta.x), try moved(bytes, inner[1], by: delta.y)]
    }

    /// `value`, written the way the author wrote the number it replaces: whole
    /// if theirs was whole, otherwise to the same number of decimals.
    private static func written(_ value: Double, like literal: Literal) -> String {
        let digits = literal.fractionDigits ?? 0
        // A canvas is measured in points, so a coordinate never reaches the
        // range where an Int conversion would trap; take the safe road anyway.
        guard value.isFinite, abs(value) < 1e15 else { return "0" }
        return String(format: "%.\(digits)f", value)
    }

    /// The same rule, for a host that wants to show a number before writing it.
    package static func written(_ value: Double, fractionDigits: Int?) -> String {
        written(value, like: Literal(value: value, fractionDigits: fractionDigits))
    }
}
