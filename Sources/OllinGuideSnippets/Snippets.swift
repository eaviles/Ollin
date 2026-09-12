// The Guide's code gate: every Swift block a reader could type is compiled, and
// every name the prose points at is resolved.
//
// The three navigation gates (check-links, guide-coverage, prose-lint) verify
// that a page can be reached and reads well. None of them opens a code block.
// Chapter 1 shipped past all of them carrying a radius wrong by a factor of a
// thousand, a command that prints usage instead of a GIF, and a docs anchor
// that does not resolve; chapter 2 named an example folder that does not exist
// and sent the reader to a file the guide never has them write. This is the
// gate for that class.
//
// See Guide/AUTHORING.md, "The code in the prose".
import Foundation
import OllinRuntime

// MARK: - Markdown

/// One fenced block, with where it came from so a failure names a line.
struct Block {
    var page: String
    var line: Int          // 1-based line of the opening fence
    var language: String
    var body: String
    var skip: String?      // the reason from a `<!-- snippet: skip ... -->` marker
}

/// Fenced blocks, in order, carrying any skip marker that sits above the fence.
func blocks(in page: String, text: String) -> [Block] {
    var out: [Block] = []
    let lines = text.components(separatedBy: "\n")
    var pendingSkip: String?
    var open: (line: Int, language: String, body: [String])?
    for (index, line) in lines.enumerated() {
        if let marker = line.range(of: #"<!--\s*snippet:\s*skip(.*?)-->"#, options: .regularExpression) {
            pendingSkip = String(line[marker])
                .replacingOccurrences(of: #"<!--\s*snippet:\s*skip\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*-->"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if pendingSkip?.isEmpty == true { pendingSkip = "marked" }
            continue
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            if var current = open {
                current.body.append("")
                out.append(Block(page: page, line: current.line, language: current.language,
                                 body: current.body.dropLast().joined(separator: "\n"),
                                 skip: pendingSkip))
                pendingSkip = nil
                open = nil
            } else {
                open = (index + 1, String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
            }
        } else if open != nil {
            open!.body.append(line)
        } else if !trimmed.isEmpty {
            pendingSkip = nil   // a marker only reaches the block right under it
        }
    }
    return out
}

// MARK: - Wrapping a fragment into something compilable

/// What a block is, which decides what has to be built around it.
enum Shape {
    case wholeFile          // has its own `import`, compiles as written
    case declaration        // a type or an extension: needs the import only
    case body               // members, statements, or both: needs a sketch around it
}

/// A block's own `import` lines, lifted off the front, and what is left. A
/// chapter often opens a fragment with the satellite it needs, so an import at
/// the top does not mean the block is a whole file.
func liftImports(_ body: String) -> (imports: [String], rest: String) {
    var imports: [String] = []
    var lines = body.components(separatedBy: "\n")
    while let first = lines.first {
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("import ") { imports.append(trimmed); lines.removeFirst(); continue }
        if trimmed.isEmpty && !imports.isEmpty { lines.removeFirst(); continue }
        break
    }
    return (imports, lines.joined(separator: "\n"))
}

/// Pseudo-code: a bare `...` stands for the part the prose is not showing, and
/// Swift reads it as an operator. Those blocks are illustration, not something
/// to type, so they are passed over rather than reported.
func isElided(_ body: String) -> Bool {
    body.components(separatedBy: "\n").contains {
        let t = $0.trimmingCharacters(in: .whitespaces)
        return t == "..." || t == "// ..." || t == "…" || t.hasSuffix("// ...")
    }
}

func shape(of body: String) -> Shape {
    let source = liftImports(body).rest.trimmingCharacters(in: .whitespacesAndNewlines)
    let head = source.components(separatedBy: "\n")
        .first(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("//") && !t.isEmpty
        })?.trimmingCharacters(in: .whitespaces) ?? ""
    for keyword in ["final class ", "class ", "struct ", "enum ", "extension ", "protocol ", "actor "]
    where head.hasPrefix(keyword) { return .declaration }
    return .body
}

/// A block's lines split into what belongs at type scope and what belongs in
/// `draw()`. The Guide mixes the two on purpose, showing a parameter's
/// declaration next to the line that reads it, so partitioning is the general
/// case rather than an exception.
///
/// Only depth-zero lines are examined, so a `for` loop's body travels with the
/// loop and a computed property's braces travel with the property.
func partition(_ body: String) -> (members: [String], statements: [String]) {
    var members: [String] = []
    var statements: [String] = []
    var depth = 0
    // A bare `let`/`var` is ambiguous: a `draw()` body is full of them, and so
    // is a class body. When the block also declares an `override`, there is no
    // room for a loose statement at type scope, so the declarations must be
    // properties. Reading them as statements put `var light: Accumulator!`
    // inside a method while `setup()` assigned it, and the name then resolved
    // to `Sketch.light(_:)` instead: a failure the chapter did not have.
    let declaresOverride = body.components(separatedBy: "\n").contains {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix("override ")
    }
    var carry: [String]?        // the member currently being consumed, brace by brace
    // Depth counts every bracket, not just braces: a property whose value is a
    // call spread over several lines is one declaration, and counting `{` alone
    // let each continuation line be read as its own statement, which is a parse
    // error rather than anything the chapter did.
    for line in body.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let opens = line.filter { "{([".contains($0) }.count
        let closes = line.filter { "})]".contains($0) }.count
        if carry != nil {
            carry!.append(line)
            depth += opens - closes
            if depth <= 0 { members.append(contentsOf: carry!); carry = nil; depth = 0 }
            continue
        }
        if depth == 0 && (isMemberHead(trimmed)
                          || (declaresOverride && isPropertyHead(trimmed))) {
            if opens > closes {
                carry = [line]
                depth = opens - closes
            } else {
                members.append(line)
            }
            continue
        }
        statements.append(line)
        depth = max(0, depth + opens - closes)
    }
    if var unfinished = carry { members.append(contentsOf: unfinished); unfinished = [] }
    return (members, statements)
}

/// A stored-property declaration, read as a member only when the block's own
/// `override` proves it is a type body rather than a function body.
func isPropertyHead(_ trimmed: String) -> Bool {
    trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ")
}

/// A line that can only live in a type body. `let`/`var` are deliberately absent:
/// a `draw()` body is full of them, and a property that matters to a snippet is
/// nearly always written with `@Param` or beside an `override`.
func isMemberHead(_ trimmed: String) -> Bool {
    if trimmed.hasPrefix("@") { return true }
    for keyword in ["override ", "func ", "init(", "deinit", "subscript", "typealias ", "static "]
    where trimmed.hasPrefix(keyword) { return true }
    return false
}

/// The compilable file for one block: the chapter's preamble, then the block
/// put wherever its parts belong.
func wrapped(_ block: Block, preamble: String) -> String {
    let (own, body) = liftImports(block.body)
    let imports = (["import Ollin"] + own).joined(separator: "\n")
    switch shape(of: block.body) {
    case .wholeFile:
        return preamble.isEmpty ? block.body : block.body + "\n\n" + preamble
    case .declaration:
        return imports + "\n" + preamble + "\n" + body
    case .body:
        let (members, statements) = partition(body)
        let drawBody = statements.joined(separator: "\n")
        // Loose statements go in `draw()` so they run where a reader would put
        // them. When the block declares its own overrides they go in a plain
        // method instead, or the synthesized one collides with the block's.
        let declaresOverride = members.contains { $0.contains("override func ") }
        var parts = [imports, preamble, "final class SnippetProbe: Sketch {"]
        parts.append(indent(members.joined(separator: "\n")))
        if !drawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(declaresOverride ? "    func snippetBody() {" : "    override func draw() {")
            parts.append(indent(drawBody, by: 8))
            parts.append("    }")
        }
        parts.append("}")
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

func indent(_ text: String, by spaces: Int = 4) -> String {
    let pad = String(repeating: " ", count: spaces)
    return text.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? $0 : pad + $0 }
        .joined(separator: "\n")
}
