import Foundation

/// What a sketch's source is made of, for a host that evaluates it: the
/// declarations the file holds, which one the caret stands in, and what an
/// edit changed against the text the stage was built from.
///
/// A compiled language cannot swap one method on a live object, so "evaluate
/// this block" cannot mean what it means in a language that interprets. What
/// it can honestly mean is this: the whole buffer still compiles and the whole
/// instance is still replaced, but the *run underneath* carries on when the
/// edit could not have changed what the run is made of. Reading the source is
/// how that is decided, and the block under the caret is what the editor
/// flashes so the performer sees which one they just sent.
///
/// It reads lines with the brackets counted, the way the reorder does: an item
/// is a run of lines whose bracket depth comes back to zero, a nested block is
/// opaque, and a comment or a bare attribute line joins the declaration under
/// it rather than standing alone. That is enough for declarations, which is
/// all this decides, and it keeps the host free of a parser to maintain.
///
/// Offsets are UTF-16, which is what an `NSTextView` addresses by, so a region
/// can be handed straight to the editor.
package enum SourceRegions {

    /// What a declaration is, at the granularity the decision needs.
    package enum Kind: Equatable, Sendable {
        /// A class, struct, enum, extension, actor, or protocol: it holds
        /// members, so the scan goes inside it.
        case type
        /// A `func`, `init`, `deinit`, or `subscript`: a body that runs when
        /// something calls it.
        case method
        /// A `var` or `let` with a block of its own (a computed property, or
        /// one with accessors).
        case computed
        /// A `var` or `let` with no block: the state an instance holds.
        case stored
        /// An import, a typealias, an operator, anything else the file says.
        case other
    }

    /// One declaration in the file.
    package struct Region: Equatable, Sendable {
        /// How the file names it, near enough to say which block ran:
        /// `draw()`, `speed`, `Live`.
        package let name: String
        /// The declarations around it, outermost first.
        package let path: [String]
        package let kind: Kind
        /// Header and body together, plus any comment or attribute line above
        /// it, as a UTF-16 range: what the editor flashes.
        package let range: NSRange
        /// The part that makes it the declaration it is (everything before the
        /// opening brace), with whitespace collapsed and comments dropped, so
        /// a rewrapped signature is the same declaration and a reworded note
        /// above it is too.
        package let header: String
        /// The text between its braces, exactly as written; `nil` when it has
        /// none.
        package let body: String?
        /// 1-based, for a host that talks in lines.
        package let firstLine: Int
        package let lastLine: Int

        /// The name with the declarations around it, which is what makes two
        /// `draw()`s in two types different declarations.
        package var qualifiedName: String { (path + [name]).joined(separator: ".") }
    }

    /// What an edit did to a sketch's source, and whether the run underneath
    /// can carry on through the swap it causes.
    package enum SourceChange: Equatable, Sendable {
        /// The same text again. The run carries on.
        case nothing
        /// Only these bodies moved, and nothing `setup()` runs is among them.
        /// The run carries on.
        case bodies([String])
        /// The swap starts a fresh run, for the reason named (a sentence, for
        /// a host that wants to say why).
        case restarts(String)

        /// Whether the swap this edit causes can carry the run underneath it.
        package var keepsTheRun: Bool {
            if case .restarts = self { return false }
            return true
        }

        /// A word or two for a status line: which block ran, or that the run
        /// started over.
        package var shortDescription: String {
            switch self {
            case .nothing: return "no change"
            case .bodies(let names):
                if names.count == 1 { return names[0] }
                return "\(names.count) blocks"
            case .restarts: return "restarted"
            }
        }
    }

    // MARK: - Reading the file

    /// Every declaration in `text`, outermost first, each type followed by the
    /// declarations inside it.
    package static func regions(in text: String) -> [Region] {
        let units = Array(text.utf16)
        let lines = lineStarts(units)
        var regions: [Region] = []
        scan(units, 0, units.count, path: [], lines: lines, into: &regions)
        return regions
    }

    /// The innermost declaration the caret stands in, or `nil` when it stands
    /// between declarations (the editor then has nothing narrower than the
    /// whole buffer to flash).
    package static func region(in text: String, containingOffset offset: Int) -> Region? {
        // The scan emits a type before the declarations inside it, so the last
        // region that contains the caret is the innermost one.
        regions(in: text).last { NSLocationInRange(offset, $0.range) || offset == $0.range.upperBound }
    }

    // MARK: - What an edit did

    /// What changed between the text the stage was built from and the text
    /// about to be evaluated.
    ///
    /// The run carries on only when every declaration is still the declaration
    /// it was, nothing `setup()` runs was touched, and `setup()` builds nothing
    /// a swap cannot carry. Anything else restarts, which is what a swap has
    /// always done.
    package static func change(from old: String, to new: String) -> SourceChange {
        let before = regions(in: old)
        let after = regions(in: new)

        guard before.count == after.count else {
            return .restarts("a declaration was added or removed")
        }
        for (a, b) in zip(before, after) {
            guard a.path == b.path, a.kind == b.kind, a.header == b.header else {
                return .restarts("the declaration of `\(b.name)` changed")
            }
        }

        // What `setup()` reaches, in the text about to run. Skipping it is the
        // whole point of carrying the run, so anything it builds that a swap
        // cannot bring across would be gone rather than rebuilt.
        let reach = setupReach(after)
        if let fragile = reach.fragileNamed {
            return .restarts("`setup()` builds `\(fragile)`, which a swap cannot carry across")
        }

        var changed: [String] = []
        for (a, b) in zip(before, after) where a.body != b.body {
            guard b.kind == .method || b.kind == .computed else { continue }
            if reach.names.contains(b.qualifiedName) {
                return .restarts("`\(b.name)` is code `setup()` runs")
            }
            changed.append(b.name)
        }
        return changed.isEmpty ? .nothing : .bodies(changed)
    }

    /// What `setup()` reaches in each type that declares one: the names of the
    /// declarations its body runs (itself included), and the first stored
    /// property it builds that a swap could not carry across.
    ///
    /// The walk is by name and takes a fixed point, so a `setup()` that calls a
    /// helper that fills an array is caught as surely as one that fills it
    /// itself. A property is carried across a swap only when it is `@Saved`
    /// (the same set a checkpoint carries), so every other one it names is a
    /// reason to start the run over.
    private static func setupReach(_ regions: [Region]) -> (names: Set<String>, fragileNamed: String?) {
        var names: Set<String> = []
        var fragile: String?
        for type in regions where type.kind == .type {
            let inside = regions.filter { $0.path == type.path + [type.name] }
            guard let setup = inside.first(where: { $0.name == "setup()" && $0.kind == .method }) else {
                continue
            }
            // The fixed point: start at setup(), and pull in any declaration of
            // this type whose name its text mentions.
            var reached: Set<String> = [setup.name]
            var text = setup.body ?? ""
            var grew = true
            while grew {
                grew = false
                let words = identifiers(in: text)
                for member in inside where !reached.contains(member.name) {
                    let bare = member.name.hasSuffix("()")
                        ? String(member.name.dropLast(2)) : member.name
                    guard words.contains(bare), let body = member.body else { continue }
                    reached.insert(member.name)
                    text += "\n" + body
                    grew = true
                }
            }
            for name in reached { names.insert((type.path + [type.name, name]).joined(separator: ".")) }

            if fragile == nil {
                let words = identifiers(in: text)
                for member in inside where member.kind == .stored {
                    guard words.contains(member.name), !member.header.contains("@Saved") else { continue }
                    fragile = member.name
                    break
                }
            }
        }
        return (names, fragile)
    }

    /// Every identifier in a piece of code, as a set. Coarse on purpose: a
    /// property this text so much as names is a property the walk treats as
    /// built here, because the cost of being wrong that way is one restart and
    /// the cost of being wrong the other way is a sketch drawing nothing.
    private static func identifiers(in text: String) -> Set<String> {
        var words: Set<String> = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else if !current.isEmpty {
                words.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { words.insert(current) }
        return words
    }

    // MARK: - The scan

    private static let declarationKeywords: Set<String> = [
        "func", "var", "let", "class", "struct", "enum", "extension", "actor",
        "protocol", "init", "deinit", "subscript", "typealias", "import",
        "operator", "case", "associatedtype",
    ]

    private static let typeKeywords: Set<String> = [
        "class", "struct", "enum", "extension", "actor", "protocol",
    ]

    /// Read the declarations between `start` and `end`, appending each and then
    /// the declarations inside it.
    private static func scan(_ u: [UInt16], _ start: Int, _ end: Int,
                             path: [String], lines: [Int], into regions: inout [Region]) {
        var i = start
        while i < end {
            // Skip the blank space between declarations; the item begins at the
            // first thing that is not space, which may be the comment above it.
            while i < end, isSpace(u[i]) { i += 1 }
            guard i < end else { return }
            let itemStart = i
            var depth = 0
            var firstBrace: Int?
            var itemEnd = end

            scanning: while i < end {
                if let past = pastStringOrComment(u, i, end) {
                    i = past
                    continue
                }
                let c = u[i]
                switch c {
                case 0x7B, 0x28, 0x5B:   // { ( [
                    if c == 0x7B, depth == 0, firstBrace == nil { firstBrace = i }
                    depth += 1
                    i += 1
                case 0x7D, 0x29, 0x5D:   // } ) ]
                    depth -= 1
                    i += 1
                    if depth <= 0, c == 0x7D, firstBrace != nil {
                        itemEnd = i
                        break scanning
                    }
                    if depth < 0 {       // the enclosing block closed under us
                        itemEnd = i - 1
                        break scanning
                    }
                case 0x0A:               // a newline ends an item that is one
                    if depth == 0, carriesADeclaration(u, itemStart, i) {
                        itemEnd = i
                        break scanning
                    }
                    i += 1
                default:
                    i += 1
                }
            }
            if i >= end, itemEnd > end { itemEnd = end }
            if itemEnd <= itemStart { return }

            let headerEnd = firstBrace ?? itemEnd
            let header = collapsed(u, itemStart, headerEnd)
            if !header.isEmpty {
                let keyword = declarationKeyword(in: header)
                let kind: Kind
                if let keyword, typeKeywords.contains(keyword) {
                    kind = .type
                } else if keyword == "func" || keyword == "init"
                            || keyword == "deinit" || keyword == "subscript" {
                    kind = .method
                } else if keyword == "var" || keyword == "let" {
                    kind = firstBrace == nil ? .stored : .computed
                } else {
                    kind = .other
                }
                let name = declarationName(in: header, keyword: keyword, kind: kind)
                let body = firstBrace.map { text(u, $0 + 1, max($0 + 1, itemEnd - 1)) }
                regions.append(Region(
                    name: name, path: path, kind: kind,
                    range: NSRange(location: itemStart, length: itemEnd - itemStart),
                    header: header, body: body,
                    firstLine: line(of: itemStart, lines),
                    lastLine: line(of: max(itemStart, itemEnd - 1), lines)))
                if kind == .type, let open = firstBrace {
                    scan(u, open + 1, max(open + 1, itemEnd - 1),
                         path: path + [name], lines: lines, into: &regions)
                }
            }
            i = max(itemEnd, itemStart + 1)
        }
    }

    /// Whether what has been read so far declares something, which is what
    /// ends an item at a newline. A comment, a bare attribute (`@Param(0...2)`
    /// on its own line), and a modifier left hanging (`override` with `func`
    /// on the next) all wait for the line that declares something and join it.
    private static func carriesADeclaration(_ u: [UInt16], _ start: Int, _ end: Int) -> Bool {
        let header = collapsed(u, start, end)
        guard !header.isEmpty else { return false }
        return declarationKeyword(in: header) != nil
    }

    /// The first declaration keyword in a header, past the attributes and the
    /// modifiers.
    private static func declarationKeyword(in header: String) -> String? {
        for word in header.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }) {
            let text = String(word)
            if declarationKeywords.contains(text) { return text }
        }
        return nil
    }

    /// How the file names this declaration: the identifier after its keyword,
    /// with `()` on the things that are called.
    private static func declarationName(in header: String, keyword: String?, kind: Kind) -> String {
        guard let keyword else { return header }
        if keyword == "init" { return "init()" }
        if keyword == "deinit" { return "deinit" }
        if keyword == "subscript" { return "subscript()" }
        // The word after the keyword, stopping at whatever ends a name.
        guard let range = header.range(of: "\\b\(keyword)\\b", options: .regularExpression) else {
            return header
        }
        let rest = header[range.upperBound...].drop { $0 == " " }
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !name.isEmpty else { return header }
        return kind == .method ? "\(name)()" : String(name)
    }

    // MARK: - Reading bytes

    private static func isSpace(_ c: UInt16) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }

    /// The index past the string literal or comment starting at `i`, or `nil`
    /// when none does. Raw literals are counted by their pounds, since an
    /// imported shader rides in one.
    private static func pastStringOrComment(_ u: [UInt16], _ i: Int, _ end: Int) -> Int? {
        if u[i] == 0x2F, i + 1 < end {           // /
            if u[i + 1] == 0x2F {                // //
                var j = i + 2
                while j < end, u[j] != 0x0A { j += 1 }
                return j
            }
            if u[i + 1] == 0x2A {                // /*
                var j = i + 2
                var nesting = 1
                while j + 1 < end, nesting > 0 {
                    if u[j] == 0x2F, u[j + 1] == 0x2A { nesting += 1; j += 2; continue }
                    if u[j] == 0x2A, u[j + 1] == 0x2F { nesting -= 1; j += 2; continue }
                    j += 1
                }
                return min(j, end)
            }
            return nil
        }
        var pounds = 0
        var j = i
        while j < end, u[j] == 0x23 { pounds += 1; j += 1 }   // #
        guard j < end, u[j] == 0x22 else { return nil }       // "
        var quotes = 0
        while j < end, u[j] == 0x22, quotes < 3 { quotes += 1; j += 1 }
        let closing = quotes == 3 ? 3 : 1
        if quotes == 2, pounds == 0 { return j }              // the empty string
        while j < end {
            if u[j] == 0x5C, pounds == 0 { j += 2; continue } // an escape
            if u[j] == 0x22 {
                var run = 0
                while j + run < end, u[j + run] == 0x22, run < closing { run += 1 }
                if run == closing {
                    var k = j + run
                    var closed = 0
                    while k < end, u[k] == 0x23, closed < pounds { closed += 1; k += 1 }
                    if closed == pounds { return k }
                }
                j += max(run, 1)
                continue
            }
            j += 1
        }
        return end
    }

    private static func text(_ u: [UInt16], _ start: Int, _ end: Int) -> String {
        guard start < end, start >= 0, end <= u.count else { return "" }
        return String(decoding: u[start..<end], as: UTF16.self)
    }

    /// The header as it reads once whitespace is collapsed and comments are
    /// dropped: what makes two spellings of one declaration the same one.
    private static func collapsed(_ u: [UInt16], _ start: Int, _ end: Int) -> String {
        var out: [UInt16] = []
        var i = start
        var spaced = true
        while i < end {
            if u[i] == 0x2F, i + 1 < end, u[i + 1] == 0x2F || u[i + 1] == 0x2A {
                i = pastStringOrComment(u, i, end) ?? end
                continue
            }
            if let past = pastStringOrComment(u, i, end) {
                out.append(contentsOf: u[i..<min(past, end)])
                spaced = false
                i = past
                continue
            }
            if isSpace(u[i]) {
                if !spaced { out.append(0x20); spaced = true }
                i += 1
                continue
            }
            out.append(u[i])
            spaced = false
            i += 1
        }
        return String(decoding: out, as: UTF16.self).trimmingCharacters(in: .whitespaces)
    }

    private static func lineStarts(_ u: [UInt16]) -> [Int] {
        var starts = [0]
        for (i, c) in u.enumerated() where c == 0x0A { starts.append(i + 1) }
        return starts
    }

    private static func line(of offset: Int, _ starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }
}
