// Putting the knobs you turned back where they were declared.
//
// A tuned value lives in the running process, and quitting drops it, so a good
// set is typed back into the sketch by hand. This writes it instead: for each
// knob the user moved, find its `@Param` declaration and replace the value
// standing after the `=`.
//
// It is the scanner `SourceEdit` uses, pointed at a property's default rather
// than a call's arguments. Every edit replaces text that is already there, so
// the attribute, the range, the label, the spacing, and a trailing comment all
// survive, and the file stays the file its author wrote. The destination is the
// source, never a preset file beside it: the sketch is the artifact.
//
// Two rules are load-bearing, because breaking either writes a file that no
// longer compiles. A `Double` knob whose default is written whole may be a
// `Double` only by the range beside it, so a fractional value keeps its point
// (`86.0`, never `86`). A `ClosedRange` default writes both ends with a point
// for the same reason: `40...50` reads as a range of `Int`.
//
// Offsets are UTF-8 bytes, which is what Swift reports, so an accented comment
// above a declaration cannot move the edit.

import Foundation
import Ollin

/// Writing tuned `@Param` values into the declarations they came from.
package enum ParamWrite {

    /// Why one knob's value could not be written down.
    package enum Reason: Error, Equatable {
        /// No `@Param` property of that name stands in this file. The knob is
        /// declared somewhere else, in a base class or another file.
        case notDeclared
        /// Two `@Param` properties in this file carry the name, so there is no
        /// way to tell which one the knob belongs to.
        case ambiguous
        /// The declaration carries no plain value to replace.
        case noDefault
        /// The default is worked out rather than written down, so there is no
        /// literal to change. `text` is what stands there (`width / 3`).
        case computed(String)
        /// The value has no name in code, so it cannot be written as one. Only
        /// a menu choice can reach this (a curve built from a closure carries a
        /// serial of its own rather than a member name).
        case unnamed(String)
    }

    /// One knob that could not be written, and why.
    package struct Refusal: Equatable {
        package let name: String
        package let reason: Reason
    }

    /// What one pass over the file did: the new text, the knobs written into
    /// it, and the ones refused with their reason.
    package struct Result {
        package let text: String
        package let written: [String]
        package let refused: [Refusal]
    }

    /// `source` with each named knob's declared default replaced by `stored`.
    ///
    /// A knob that cannot be written leaves the text alone and comes back in
    /// `refused`, so a set that is half writable still lands, and nothing is
    /// dropped in silence.
    package static func writing(_ source: String,
                                values: [(name: String, stored: ParamStored)]) -> Result {
        var bytes = Array(source.utf8)
        // Every replacement is worked out against the original text, then
        // applied back to front, so an earlier edit cannot shift a later range.
        var edits: [(Range<Int>, [UInt8])] = []
        var written: [String] = []
        var refused: [Refusal] = []
        let declarations = paramDeclarations(in: bytes)
        for value in values {
            let sites = declarations.filter { $0.name == value.name }
            guard let site = sites.first else {
                refused.append(Refusal(name: value.name, reason: .notDeclared))
                continue
            }
            guard sites.count == 1 else {
                refused.append(Refusal(name: value.name, reason: .ambiguous))
                continue
            }
            guard let range = site.defaultValue else {
                refused.append(Refusal(name: value.name, reason: .noDefault))
                continue
            }
            let existing = String(decoding: bytes[range], as: UTF8.self)
            guard isWrittenDown(bytes, range) else {
                refused.append(Refusal(name: value.name, reason: .computed(existing)))
                continue
            }
            switch replacement(for: value.stored, existing: existing) {
            case .success(let text):
                edits.append((range, Array(text.utf8)))
                written.append(value.name)
            case .failure(let reason):
                refused.append(Refusal(name: value.name, reason: reason))
            }
        }
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            bytes.replaceSubrange(range, with: replacement)
        }
        return Result(text: String(decoding: bytes, as: UTF8.self),
                      written: written, refused: refused)
    }

    // MARK: What to say about it

    /// Why one knob stayed where it was, in one sentence. Each one names the
    /// thing standing where a value would have to go, because that is the only
    /// way to see what to do about it.
    package static func sentence(for refusal: Refusal, in file: String) -> String {
        switch refusal.reason {
        case .notDeclared:
            return "\(file) does not declare \(refusal.name)."
        case .ambiguous:
            return "Two knobs are named \(refusal.name) in \(file), so this cannot tell them apart."
        case .noDefault:
            return "\(refusal.name) has no value written after its ="
        case .computed(let text):
            return "\(refusal.name) is set to \(text), so there is no value to replace."
        case .unnamed(let text):
            return "\(refusal.name) is set to \(text), which has no name to write down."
        }
    }

    /// The one line a host shows after a save: what landed, and the first thing
    /// that did not.
    package static func summary(of result: Result, in file: String) -> String {
        var sentence: String
        switch result.written.count {
        case 0: sentence = "Nothing was written into \(file)."
        case 1: sentence = "Saved 1 value into \(file)."
        default: sentence = "Saved \(result.written.count) values into \(file)."
        }
        if let first = result.refused.first {
            sentence += " " + Self.sentence(for: first, in: file)
            if result.refused.count > 1 {
                sentence += " (\(result.refused.count - 1) more were left as they are.)"
            }
        }
        return sentence
    }

    // MARK: Finding a declaration

    /// One `@Param` property found in the file: its name, and the byte range of
    /// the value written after its `=`.
    private struct Declaration {
        let name: String
        let defaultValue: Range<Int>?
    }

    /// Every `@Param` property the file declares, in the order they stand.
    ///
    /// The walk runs forward from each `@Param` attribute rather than back from
    /// each `var`, because forward is where the scanner can skip a string or a
    /// comment safely. Between the attribute and the name there may be its own
    /// parentheses (`@Param(0...200, group: "Shape")`) and any number of
    /// modifiers (`private var`), so both are stepped over.
    private static func paramDeclarations(in bytes: [UInt8]) -> [Declaration] {
        var found: [Declaration] = []
        for token in nameTokens(in: bytes) {
            guard text(bytes, token) == "Param" else { continue }
            var back = token.lowerBound - 1
            while back >= 0, SourceEdit.isSpace(bytes[back]) { back -= 1 }
            guard back >= 0, bytes[back] == UInt8(ascii: "@") else { continue }

            var index = skip(bytes, from: token.upperBound)
            if index < bytes.count, bytes[index] == UInt8(ascii: "(") {
                index = endOfGroup(bytes, from: index)
                index = skip(bytes, from: index)
            }
            // The modifiers a property may wear before `var`. `@Param` itself
            // rules out the ones that could not carry a value (`let`, `func`).
            let modifiers: Set<String> = ["private", "fileprivate", "internal", "package",
                                          "public", "open", "final", "static", "class",
                                          "lazy", "weak", "unowned", "nonisolated"]
            var keyword = nameToken(bytes, at: index)
            while let word = keyword, modifiers.contains(text(bytes, word)) {
                index = skip(bytes, from: word.upperBound)
                keyword = nameToken(bytes, at: index)
            }
            guard let word = keyword, text(bytes, word) == "var" else { continue }
            index = skip(bytes, from: word.upperBound)
            guard let name = nameToken(bytes, at: index) else { continue }
            found.append(Declaration(name: text(bytes, name),
                                     defaultValue: defaultValue(bytes, after: name.upperBound)))
        }
        return found
    }

    /// The byte range of the value written after the declaration's `=`, or
    /// `nil` when the line carries none.
    ///
    /// The search for the `=` stops at the end of the line on purpose: a
    /// property with no default would otherwise reach forward and take the next
    /// statement's value as its own.
    private static func defaultValue(_ bytes: [UInt8], after nameEnd: Int) -> Range<Int>? {
        var index = nameEnd
        var depth = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") { index = SourceEdit.endOfString(bytes, from: index); continue }
            if byte == UInt8(ascii: "/"), index + 1 < bytes.count,
               bytes[index + 1] == UInt8(ascii: "/") || bytes[index + 1] == UInt8(ascii: "*") {
                index = SourceEdit.endOfComment(bytes, from: index)
                continue
            }
            switch byte {
            case UInt8(ascii: "("), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: ")"), UInt8(ascii: "]"):
                depth -= 1
            case UInt8(ascii: "{") where depth == 0:
                return nil                                   // a computed property
            case UInt8(ascii: "\n") where depth == 0:
                return nil                                   // no default on this line
            case UInt8(ascii: "="):
                // `==` and the operators ending in `=` are not an assignment.
                let next = index + 1 < bytes.count ? bytes[index + 1] : 0
                let previous = bytes[index - 1]
                if depth == 0, next != UInt8(ascii: "="), previous != UInt8(ascii: "="),
                   previous != UInt8(ascii: "!"), previous != UInt8(ascii: "<"),
                   previous != UInt8(ascii: ">") {
                    return expression(bytes, from: index + 1)
                }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    /// The range of the value that starts after an `=`: everything up to the
    /// end of the line, a `;`, or a trailing comment, with anything still open
    /// (a call, an array) carried across the line breaks inside it.
    private static func expression(_ bytes: [UInt8], from start: Int) -> Range<Int>? {
        var index = start
        while index < bytes.count, bytes[index] == UInt8(ascii: " ") || bytes[index] == UInt8(ascii: "\t") {
            index += 1
        }
        let begin = index
        guard begin < bytes.count, bytes[begin] != UInt8(ascii: "\n") else { return nil }
        var depth = 0
        scan: while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") { index = SourceEdit.endOfString(bytes, from: index); continue }
            if byte == UInt8(ascii: "/"), index + 1 < bytes.count,
               bytes[index + 1] == UInt8(ascii: "/") || bytes[index + 1] == UInt8(ascii: "*") {
                if depth == 0 { break scan }                  // a comment after the value
                index = SourceEdit.endOfComment(bytes, from: index)
                continue
            }
            switch byte {
            case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
            case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"):
                if depth == 0 { break scan }                  // a bracket this never opened
                depth -= 1
            case UInt8(ascii: "\n"), UInt8(ascii: ";"):
                if depth == 0 { break scan }
            default:
                break
            }
            index += 1
        }
        var end = min(index, bytes.count)
        while end > begin, SourceEdit.isSpace(bytes[end - 1]) { end -= 1 }
        return begin < end ? begin ..< end : nil
    }

    // MARK: Is it written down, or worked out?

    /// Whether the value in `range` is written down rather than worked out.
    ///
    /// Two rules, and both are about not throwing away what the author wrote.
    /// A name belongs to a written value when it follows a dot (`.purple`),
    /// labels an argument (`red:`), or is a type reaching for one of its own
    /// (`Vector2(`, `Insets.all`); any other name is one the sketch works out
    /// as it runs. And a sum standing on its own (`600.0 / 2`, `margin * 2`) is
    /// arithmetic the author meant, not a value, even when every part of it is
    /// a number.
    private static func isWrittenDown(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        guard !carriesArithmetic(bytes, range) else { return false }
        for token in nameTokens(in: bytes, within: range) {
            let word = text(bytes, token)
            if word == "true" || word == "false" || word == "nil" { continue }
            var before = token.lowerBound - 1
            while before >= range.lowerBound, SourceEdit.isSpace(bytes[before]) { before -= 1 }
            if before >= range.lowerBound, bytes[before] == UInt8(ascii: ".") { continue }
            var after = token.upperBound
            while after < range.upperBound, SourceEdit.isSpace(bytes[after]) { after += 1 }
            let next = after < range.upperBound ? bytes[after] : 0
            if next == UInt8(ascii: ":") { continue }         // an argument label
            let isType = word.first.map { $0.isUppercase } ?? false
            if isType, next == UInt8(ascii: "(") || next == UInt8(ascii: ".") { continue }
            return false
        }
        return true
    }

    /// Whether an arithmetic operator stands between two values in `range`,
    /// outside any brackets. A leading minus is part of the number after it, so
    /// it does not count, and a `/` opening a comment is never reached (the
    /// value ends before one).
    private static func carriesArithmetic(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var index = range.lowerBound
        var depth = 0
        while index < range.upperBound {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index = SourceEdit.endOfString(bytes, from: index)
                continue
            }
            switch byte {
            case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
            case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
            case UInt8(ascii: "+"), UInt8(ascii: "*"), UInt8(ascii: "/"), UInt8(ascii: "%"):
                if depth == 0 { return true }
            case UInt8(ascii: "-"):
                if depth == 0, index > range.lowerBound { return true }
            default:
                break
            }
            index += 1
        }
        return false
    }

    // MARK: Writing one value down

    /// The text to stand in for `existing`, or why the value cannot be written.
    private static func replacement(for stored: ParamStored,
                                    existing: String) -> Swift.Result<String, Reason> {
        switch stored {
        case .number(let value):
            // A default written whole stays whole while the value is whole, so
            // a knob that was tuned to a round number reads as it did before.
            // A fraction always keeps its point: without one the literal reads
            // as an `Int` and the declaration can stop compiling.
            let whole = !existing.contains(".") && value == value.rounded()
            return .success(whole ? String(Int(value.rounded())) : number(value))
        case .boolean(let value):
            return .success(value ? "true" : "false")
        case .option(let name):
            guard isIdentifier(name) else { return .failure(.unnamed(name)) }
            guard let prefix = memberPrefix(of: existing) else { return .failure(.computed(existing)) }
            return .success(prefix + name)
        case .color(let red, let green, let blue, let alpha):
            return .success(color(red, green, blue, alpha))
        case .vector(let x, let y):
            return .success("Vector2(\(argument(x)), \(argument(y)))")
        case .vector3(let x, let y, let z):
            return .success("Vector3(\(argument(x)), \(argument(y)), \(argument(z)))")
        case .rect(let x, let y, let width, let height):
            return .success("Rectangle(x: \(argument(x)), y: \(argument(y)), "
                            + "width: \(argument(width)), height: \(argument(height)))")
        case .insets(let top, let right, let bottom, let left):
            return .success("Insets(top: \(argument(top)), right: \(argument(right)), "
                            + "bottom: \(argument(bottom)), left: \(argument(left)))")
        case .range(let lower, let upper):
            // Both ends keep a point, or the pair reads as a range of `Int`.
            return .success("\(number(lower))...\(number(upper))")
        case .text(let value):
            return .success(quoted(value))
        case .colors(let stops, let space):
            guard let space else {
                return .success("Palette([" + stops.map { color($0) }.joined(separator: ", ") + "])")
            }
            let written = stops.map { "(position: \(argument($0.position)), color: \(color($0)))" }
            return .success("Ramp(stops: [" + written.joined(separator: ", ") + "], in: .\(space))")
        }
    }

    /// How a member is reached in the text standing there, so a case keeps the
    /// spelling its author chose: `.dots` stays leading-dot, `Style.dots` keeps
    /// its type. `nil` when what stands there is not a member at all.
    private static func memberPrefix(of existing: String) -> String? {
        if existing.hasPrefix(".") { return "." }
        guard let dot = existing.firstIndex(of: "."), dot != existing.startIndex else { return nil }
        let head = existing[existing.startIndex ..< dot]
        guard isIdentifier(String(head)) else { return nil }
        return head + "."
    }

    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// A `Double` written so it stays a `Double`: always a decimal point, and
    /// no more digits than the value needs.
    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        for digits in 1...6 {
            let text = String(format: "%.\(digits)f", value)
            if let read = Double(text), abs(read - value) <= max(1e-12, abs(value) * 1e-12) {
                return text
            }
        }
        // Swift's own shortest form always carries a point or an exponent.
        return String(value)
    }

    /// A number inside a call, where the type is already fixed by what it is
    /// passed to, so a whole number needs no point of its own.
    private static func argument(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value.rounded()))
            : number(value)
    }

    /// A color written out. Four decimals is finer than a display can show (a
    /// channel step is 1/255), and it keeps the line readable.
    private static func color(_ red: Double, _ green: Double, _ blue: Double,
                              _ alpha: Double) -> String {
        var text = "Color(red: \(channel(red)), green: \(channel(green)), blue: \(channel(blue))"
        if alpha < 1 { text += ", alpha: \(channel(alpha))" }
        return text + ")"
    }

    private static func color(_ stop: ParamColorStop) -> String {
        color(stop.red, stop.green, stop.blue, stop.alpha)
    }

    private static func channel(_ value: Double) -> String {
        argument((value * 10_000).rounded() / 10_000)
    }

    /// A string written as a Swift literal, with what would end it escaped.
    private static func quoted(_ value: String) -> String {
        var text = "\""
        for character in value {
            switch character {
            case "\\": text += "\\\\"
            case "\"": text += "\\\""
            case "\n": text += "\\n"
            case "\t": text += "\\t"
            case "\r": text += "\\r"
            default: text.append(character)
            }
        }
        return text + "\""
    }

    // MARK: Reading the file as tokens

    /// The byte ranges of the name tokens in `bytes`, in order, with the ones
    /// inside a string or a comment left out.
    private static func nameTokens(in bytes: [UInt8]) -> [Range<Int>] {
        nameTokens(in: bytes, within: 0 ..< bytes.count)
    }

    private static func nameTokens(in bytes: [UInt8], within range: Range<Int>) -> [Range<Int>] {
        var tokens: [Range<Int>] = []
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index = SourceEdit.endOfString(bytes, from: index)
                continue
            }
            if byte == UInt8(ascii: "/"), index + 1 < range.upperBound,
               bytes[index + 1] == UInt8(ascii: "/") || bytes[index + 1] == UInt8(ascii: "*") {
                index = SourceEdit.endOfComment(bytes, from: index)
                continue
            }
            // A name never starts with a digit, so `1_000` stays a number.
            if SourceEdit.isNameByte(byte), !SourceEdit.isDigit(byte),
               index == range.lowerBound || !SourceEdit.isNameByte(bytes[index - 1]) {
                var end = index
                while end < range.upperBound, SourceEdit.isNameByte(bytes[end]) { end += 1 }
                tokens.append(index ..< end)
                index = end
                continue
            }
            index += 1
        }
        return tokens
    }

    /// The name token standing at `index`, or `nil` when something else does.
    private static func nameToken(_ bytes: [UInt8], at index: Int) -> Range<Int>? {
        guard index < bytes.count, SourceEdit.isNameByte(bytes[index]),
              !SourceEdit.isDigit(bytes[index]) else { return nil }
        var end = index
        while end < bytes.count, SourceEdit.isNameByte(bytes[end]) { end += 1 }
        return index ..< end
    }

    /// The first byte at or after `index` that is neither whitespace nor a
    /// comment, since a declaration may carry either between its parts.
    private static func skip(_ bytes: [UInt8], from index: Int) -> Int {
        var scan = index
        while scan < bytes.count {
            if SourceEdit.isSpace(bytes[scan]) { scan += 1; continue }
            if bytes[scan] == UInt8(ascii: "/"), scan + 1 < bytes.count,
               bytes[scan + 1] == UInt8(ascii: "/") || bytes[scan + 1] == UInt8(ascii: "*") {
                scan = SourceEdit.endOfComment(bytes, from: scan)
                continue
            }
            break
        }
        return scan
    }

    /// The index just past the group that opens at `index`, counting the
    /// brackets inside it and stepping over strings and comments.
    private static func endOfGroup(_ bytes: [UInt8], from index: Int) -> Int {
        var scan = index
        var depth = 0
        while scan < bytes.count {
            let byte = bytes[scan]
            if byte == UInt8(ascii: "\"") { scan = SourceEdit.endOfString(bytes, from: scan); continue }
            if byte == UInt8(ascii: "/"), scan + 1 < bytes.count,
               bytes[scan + 1] == UInt8(ascii: "/") || bytes[scan + 1] == UInt8(ascii: "*") {
                scan = SourceEdit.endOfComment(bytes, from: scan)
                continue
            }
            if byte == UInt8(ascii: "(") || byte == UInt8(ascii: "[") || byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: ")") || byte == UInt8(ascii: "]") || byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { return scan + 1 }
            }
            scan += 1
        }
        return bytes.count
    }

    private static func text(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }
}
