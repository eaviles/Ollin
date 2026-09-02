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
        /// Nothing on the line says how big the shape is.
        case nothingToSize
        /// Nothing on the line says which way the shape faces.
        case nothingToTurn
        /// The shape is already the first or the last one drawn in its block,
        /// so there is nothing to move it past.
        case alreadyAtTheEdge
        /// A statement standing between the two shapes that is not ink, so
        /// moving past it could change more than the order. `statement` is
        /// the line as the file writes it.
        case blockedBy(statement: String)
        /// The move would need to say what ink the shape was drawn with, and
        /// nothing in the block says. `statement` is the ink line between the
        /// two shapes that the move has to get past.
        case inkUnknown(statement: String)
        /// The call shares its line with something else, so the line cannot
        /// move as the shape's own. `line` is the text.
        case notAlone(line: String)
    }

    /// One coordinate as the file writes it.
    enum Coordinate: Equatable {
        /// A number, and where it stands.
        case number(Range<Int>, Literal)
        /// A bare name (`radius`, `cx`): a parameter's name, or any other variable.
        case name(String)
        /// A calculation (`width / 2`, `p.x + 10`), with its text.
        case expression(String)

        /// What stands there, for a message that names it.
        var text: String {
            switch self {
            case .number(_, let literal): return literal.text
            case .name(let name): return name
            case .expression(let text): return text
            }
        }
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
        let bytes = Array(source.utf8)
        let places = try coordinates(bytes, at: line, column: column, move: move)
        // Every replacement is worked out against the original text first, then
        // applied back to front, so an earlier edit cannot shift a later range.
        var edits: [(Range<Int>, [UInt8])] = []
        for place in places {
            edits.append(try moved(place.x, by: delta.x))
            edits.append(try moved(place.y, by: delta.y))
        }
        return applying(edits, to: bytes)
    }

    /// The file's text with the call's size numbers multiplied by `factor`:
    /// `x` for the size across, `y` for the size down, and `x` alone for sizes
    /// that scale together.
    ///
    /// Only the size arguments change. The numbers that place the shape stay
    /// where they are, so it grows from wherever the call says it stands, and a
    /// corner radius or a count of sides is left as written.
    package static func resizing(_ source: String, line: Int, column: Int,
                                 move: SourceMove, by factor: Vector2) throws -> String {
        let bytes = Array(source.utf8)
        guard let open = openParen(in: bytes, line: line, column: column) else {
            throw Failure.callNotFound
        }
        let args = try arguments(in: bytes, openParen: open)
        func scale(_ indices: [Int], by amount: Double) throws -> [(Range<Int>, [UInt8])] {
            try indices.map { index in
                guard index < args.count else { throw Failure.missingArgument(index: index) }
                let range = args[index]
                guard let literal = literal(bytes, range) else {
                    throw Failure.computed(argument: String(decoding: bytes[range], as: UTF8.self))
                }
                return (range, Array(written(literal.value * amount, like: literal).utf8))
            }
        }
        var edits: [(Range<Int>, [UInt8])] = []
        switch move.size {
        case .none:
            throw Failure.nothingToSize
        case .uniform(let indices):
            edits += try scale(indices, by: factor.x)
        case .axes(let across, let down):
            edits += try scale(across, by: factor.x)
            edits += try scale(down, by: factor.y)
        }
        return applying(edits, to: bytes)
    }

    /// The file's text with the call turned by `angle` radians.
    ///
    /// A shape that carries its own angles (an arc's `start:` and `stop:`) has
    /// them moved by that much. A shape placed by two or more points has those
    /// points swung about their own middle, so a line turns where it lies
    /// rather than travelling. An angle is written to at least three decimals,
    /// because a whole radian is most of a quarter turn.
    package static func turning(_ source: String, line: Int, column: Int,
                                move: SourceMove, by angle: Double) throws -> String {
        let bytes = Array(source.utf8)
        guard let open = openParen(in: bytes, line: line, column: column) else {
            throw Failure.callNotFound
        }
        var edits: [(Range<Int>, [UInt8])] = []
        if !move.angles.isEmpty {
            let args = try arguments(in: bytes, openParen: open)
            for index in move.angles {
                guard index < args.count else { throw Failure.missingArgument(index: index) }
                let range = args[index]
                guard let literal = literal(bytes, range) else {
                    throw Failure.computed(argument: String(decoding: bytes[range], as: UTF8.self))
                }
                let digits = Swift.max(3, literal.fractionDigits ?? 0)
                edits.append((range, Array(written(literal.value + angle,
                                                   fractionDigits: digits).utf8)))
            }
        } else {
            guard move.pointCount >= 2 else { throw Failure.nothingToTurn }
            let places = try coordinates(bytes, at: line, column: column, move: move)
            var numbers: [(x: (Range<Int>, Literal), y: (Range<Int>, Literal))] = []
            for place in places {
                guard case .number(let xr, let xl) = place.x else {
                    throw Failure.computed(argument: place.x.text)
                }
                guard case .number(let yr, let yl) = place.y else {
                    throw Failure.computed(argument: place.y.text)
                }
                numbers.append(((xr, xl), (yr, yl)))
            }
            let count = Double(numbers.count)
            let middle = Vector2(numbers.reduce(0) { $0 + $1.x.1.value } / count,
                                 numbers.reduce(0) { $0 + $1.y.1.value } / count)
            let cosine = cos(angle), sine = sin(angle)
            for point in numbers {
                let dx = point.x.1.value - middle.x, dy = point.y.1.value - middle.y
                let turnedX = middle.x + dx * cosine - dy * sine
                let turnedY = middle.y + dx * sine + dy * cosine
                edits.append((point.x.0, Array(written(turnedX, like: point.x.1).utf8)))
                edits.append((point.y.0, Array(written(turnedY, like: point.y.1).utf8)))
            }
        }
        return applying(edits, to: bytes)
    }

    /// A move worked out coordinate by coordinate, so a host can write the
    /// numbers it can write and adjust a parameter for a coordinate that stands there
    /// as a parameter's name.
    package struct MovePlan: Equatable {
        /// The file with every coordinate that is a number already moved. The
        /// text unchanged when none of them is.
        package let text: String
        /// Coordinates written as a bare name, each with how far the drag moves
        /// it: `("cx", 13)`. Whether that name is a parameter is the host's question.
        package let names: [Named]
        /// What stands where a coordinate has to be, when it is neither a
        /// number nor a name. Nothing was written in that case.
        package let refused: String?

        package struct Named: Equatable {
            package let name: String
            package let delta: Double
            /// Whether it stands where the x coordinate goes, rather than the y.
            package let isAcross: Bool
        }
    }

    /// The same move as `moving(_:line:column:move:by:)`, reported argument by
    /// argument instead of refused whole.
    package static func planningMove(_ source: String, line: Int, column: Int,
                                     move: SourceMove, by delta: Vector2) throws -> MovePlan {
        let bytes = Array(source.utf8)
        let places = try coordinates(bytes, at: line, column: column, move: move)
        var edits: [(Range<Int>, [UInt8])] = []
        var names: [MovePlan.Named] = []
        for place in places {
            for (coordinate, step, isAcross) in [(place.x, delta.x, true), (place.y, delta.y, false)] {
                switch coordinate {
                case .number(let range, let literal):
                    edits.append((range, Array(written(literal.value + step, like: literal).utf8)))
                case .name(let name):
                    names.append(MovePlan.Named(name: name, delta: step, isAcross: isAcross))
                case .expression(let text):
                    return MovePlan(text: source, names: [], refused: text)
                }
            }
        }
        return MovePlan(text: applying(edits, to: bytes), names: names, refused: nil)
    }

    /// The text with every replacement applied back to front, so an earlier
    /// edit cannot shift a later range.
    private static func applying(_ edits: [(Range<Int>, [UInt8])], to bytes: [UInt8]) -> String {
        var bytes = bytes
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            bytes.replaceSubrange(range, with: replacement)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The coordinates that place the call at `line`/`column`, in x, y pairs
    /// and in the order the call writes them.
    private static func coordinates(_ bytes: [UInt8], at line: Int, column: Int,
                                    move: SourceMove) throws -> [(x: Coordinate, y: Coordinate)] {
        guard let open = openParen(in: bytes, line: line, column: column) else {
            throw Failure.callNotFound
        }
        let args = try arguments(in: bytes, openParen: open)
        var places: [(x: Coordinate, y: Coordinate)] = []
        switch move.position {
        case .scalars(let indices):
            for pair in stride(from: 0, to: indices.count - 1, by: 2) {
                let x = indices[pair], y = indices[pair + 1]
                guard x < args.count else { throw Failure.missingArgument(index: x) }
                guard y < args.count else { throw Failure.missingArgument(index: y) }
                places.append((coordinate(bytes, args[x]), coordinate(bytes, args[y])))
            }
        case .points(let indices):
            for index in indices {
                guard index < args.count else { throw Failure.missingArgument(index: index) }
                let range = args[index]
                let text = String(decoding: bytes[range], as: UTF8.self)
                // The value has to be a `Vector2` written out with its own two
                // arguments, since there is nowhere else to put the numbers.
                guard text.hasPrefix("Vector2"),
                      let openInner = bytes[range].firstIndex(of: UInt8(ascii: "(")),
                      let inner = try? arguments(in: bytes, openParen: openInner),
                      inner.count == 2 else {
                    throw Failure.notAPoint(argument: text)
                }
                places.append((coordinate(bytes, inner[0]), coordinate(bytes, inner[1])))
            }
        }
        return places
    }

    /// What one coordinate is: a number, a bare name, or a calculation.
    private static func coordinate(_ bytes: [UInt8], _ range: Range<Int>) -> Coordinate {
        if let literal = literal(bytes, range) { return .number(range, literal) }
        let text = String(decoding: bytes[range], as: UTF8.self)
        return isName(bytes, range) ? .name(text) : .expression(text)
    }

    /// Whether the bytes are one plain name: `radius` yes, `p.x` and `-r` no.
    private static func isName(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        guard !range.isEmpty, !isDigit(bytes[range.lowerBound]) else { return false }
        return bytes[range].allSatisfy(isNameByte)
    }

    /// One coordinate moved by `step`, or a refusal naming what stands there.
    private static func moved(_ coordinate: Coordinate,
                              by step: Double) throws -> (Range<Int>, [UInt8]) {
        guard case .number(let range, let literal) = coordinate else {
            throw Failure.computed(argument: coordinate.text)
        }
        return (range, Array(written(literal.value + step, like: literal).utf8))
    }

    // MARK: Finding the call

    /// The byte index of the call's `(`. Takes the reported column when it
    /// lands on one, and otherwise looks along the line: a formatter that
    /// reflowed the file leaves the call on its line but not at its column.
    static func openParen(in bytes: [UInt8], line: Int, column: Int) -> Int? {
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
    struct Literal: Equatable {
        let value: Double
        /// Digits after the point, or `nil` when it was written whole.
        let fractionDigits: Int?
        /// The number as the author typed it.
        let text: String
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
        return Literal(value: value, fractionDigits: fraction,
                       text: String(decoding: bytes[range], as: UTF8.self))
    }

    /// `value`, written the way the author wrote the number it replaces: whole
    /// if theirs was whole, otherwise to the same number of decimals.
    private static func written(_ value: Double, like literal: Literal) -> String {
        let digits = literal.fractionDigits ?? 0
        // A canvas is measured in points, so a coordinate never reaches the
        // range where an Int conversion would trap; take the safe road anyway.
        guard value.isFinite, abs(value) < 1e15 else { return "0" }
        let text = String(format: "%.\(digits)f", value)
        // A turn leaves a coordinate a hair under zero (the sine of a half turn
        // is not quite nothing), and rounding that writes `-0`. Nobody types
        // that, so neither does this.
        if text.hasPrefix("-"), text.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) {
            return String(text.dropFirst())
        }
        return text
    }

    /// The same rule, for a host that wants to show a number before writing it.
    package static func written(_ value: Double, fractionDigits: Int?) -> String {
        written(value, like: Literal(value: value, fractionDigits: fractionDigits, text: ""))
    }
}
