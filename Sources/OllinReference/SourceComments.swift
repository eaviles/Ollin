import Foundation

/// Where a public declaration is written, and what its doc comment says.
public struct SourcePlace: Sendable, Equatable {
    public let file: URL
    /// The declaration's own line, counting from 1.
    public let line: Int
    /// The `///` lines above it, markers taken off, in order. Empty when it
    /// has none.
    public let comment: [String]
    /// What the listing leaves out about where it sits: `where Value:
    /// ParamOption` for an extension with a `where` clause, `requirement` for
    /// a protocol's own member. Two declarations the listing writes alike (an
    /// initializer for a menu and one for a named set; a requirement and its
    /// default) differ only here.
    public var constraint: String? = nil
}

/// Finding a listed declaration in `Sources/` to read its doc comment.
///
/// The listing says what is public and how it is spelled. What a value means
/// (its unit, its range, which way it turns) is written in the comment above
/// the declaration, and that was the part people went to the source for.
/// This is a reader for the one shape the tree is written in, not a Swift
/// parser: it follows the types a line sits in by counting braces outside
/// strings and comments, and pairs a declaration by its name, the type it
/// sits in, and its argument labels.
public enum SourceComments {

    /// The places of the declarations asked about, keyed by their index in
    /// `declarations`. One that cannot be found is simply absent.
    public static func places(of declarations: [APIDeclaration], inSources sources: URL) -> [Int: SourcePlace] {
        var found: [Int: SourcePlace] = [:]
        let byModule = Dictionary(grouping: declarations.indices.filter { !declarations[$0].isExtension },
                                  by: { declarations[$0].module })
        // A match on labels alone is held until the end, in case the same
        // labels turn up later with the same parameter types too.
        var loose: [Int: SourcePlace] = [:]
        for (module, indices) in byModule {
            var waiting = Dictionary(grouping: indices, by: { declarations[$0].name })
            for file in swiftFiles(in: sources.appendingPathComponent(module)) {
                guard !waiting.isEmpty,
                      let text = try? String(contentsOf: file, encoding: .utf8),
                      waiting.keys.contains(where: { text.contains($0) }) else { continue }
                for written in self.declarations(in: text) {
                    for name in Set(written.names + [written.name]) {
                        guard let candidates = waiting[name] else { continue }
                        // One listing line to one source declaration: two lines
                        // the listing writes alike (the same initializer under
                        // two constraints) take the two declarations in turn,
                        // rather than both taking the first.
                        let place = SourcePlace(file: file, line: written.line, comment: written.comment,
                                                constraint: written.constraint)
                        for index in candidates where found[index] == nil && pairs(declarations[index], with: written) {
                            if sameTypes(declarations[index], written) {
                                found[index] = place
                                break
                            } else if loose[index] == nil {
                                loose[index] = place
                            }
                        }
                        let left = candidates.filter { found[$0] == nil }
                        waiting[name] = left.isEmpty ? nil : left
                    }
                }
            }
        }
        return found.merging(loose) { exact, _ in exact }
    }

    /// A declaration as the source writes it.
    struct Written: Equatable {
        var owner: [String]
        var name: String
        var kind: APIDeclaration.Kind
        /// Every name a `case a, b, c` line declares.
        var names: [String]
        var labels: [String]?
        var line: Int
        var comment: [String]
        var isExtension = false
        /// The parameter types, for telling apart overloads with the same labels.
        var types: [String]?
        /// The `where` clause of the type or extension it sits in.
        var constraint: String?
    }

    static func pairs(_ listed: APIDeclaration, with written: Written) -> Bool {
        guard written.names.contains(listed.name) || written.name == listed.name else { return false }
        // `extension Sketch` adds to a type and is not where it is declared.
        guard !written.isExtension else { return false }
        guard ownerMatches(listed.owner, written.owner) else { return false }
        switch listed.kind {
        case .function, .initializer, .subscriptMember:
            return written.kind == listed.kind && written.labels == listed.labels
        case .property:
            return written.kind == .property
        default:
            return written.kind == listed.kind
        }
    }

    /// A function's, initializer's or subscript's declaration as its source
    /// writes it, one line: the parameter names and the default values the
    /// listing leaves out, without the access level, the compiler-filled
    /// source-location parameters, or the body. Nil for anything else, whose
    /// listing line already says all of it.
    public static func signature(of declaration: APIDeclaration, at place: SourcePlace) -> String? {
        guard [.function, .initializer, .subscriptMember].contains(declaration.kind),
              let text = try? String(contentsOf: place.file, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard place.line >= 1, place.line <= lines.count else { return nil }
        var inString = false
        let code = lines[(place.line - 1) ..< min(lines.count, place.line + 39)].map { line -> String in
            codePart(of: line, inString: &inString).trimmingCharacters(in: .whitespaces)
        }
        var joined = ""
        var depth = 0
        var opened = false
        scan: for line in code {
            for character in line {
                if character == "(" { depth += 1; opened = true }
                if character == ")" { depth -= 1 }
                // The body starts at the first brace outside the arguments.
                if character == "{", depth == 0, opened { break scan }
                joined.append(character)
            }
            joined.append(" ")
        }
        var out = joined.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "( ", with: "(").replacingOccurrences(of: " )", with: ")")
            .trimmingCharacters(in: .whitespaces)
        out = out.replacingOccurrences(
            of: #",\s*file: StaticString = #\w+,\s*line: (Int|UInt) = #line,\s*column: (Int|UInt) = #column"#,
            with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"^(?:(?:public|open|package|nonisolated|final)\s+)+"#,
                                       with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"(^|\s)(?:(?:public|open)\s+)"#, with: "$1", options: .regularExpression)
        return out.isEmpty ? nil : out
    }

    /// Whether a paired declaration's parameters are the same types. Only
    /// something with an argument list can differ here.
    static func sameTypes(_ listed: APIDeclaration, _ written: Written) -> Bool {
        guard let types = written.types else { return true }
        return APIListing.parameterTypes(of: listed.text) == types
    }

    /// The listing writes a type's full nesting; the source may reach it
    /// through `extension Light.Kind` or by nesting it, which both flatten to
    /// the same names.
    static func ownerMatches(_ listed: [String], _ written: [String]) -> Bool {
        guard !listed.isEmpty else { return written.isEmpty }
        return written.count >= listed.count && Array(written.suffix(listed.count)) == listed
    }

    /// Every declaration in one file that sits at a type's member level or
    /// at the top level, with the types it sits in.
    ///
    /// Every brace is followed, not only a type's: a method body, a computed
    /// property, and a closure open scopes too, and a `let` inside one of
    /// them is a local rather than a member, so nothing inside one is taken.
    static func declarations(in text: String) -> [Written] {
        let lines = text.components(separatedBy: "\n")
        var found: [Written] = []
        // One entry per open brace: the type names it opens, or nil for a
        // body that is not a type's.
        var open: [[String]?] = []
        // The `where` clause of each open type, beside it.
        var constraints: [String?] = []
        // A type declared on a line whose brace has not come yet, and its
        // `where` clause.
        var pending: [String]?
        var pendingConstraint: String?
        var inString = false

        for (index, raw) in lines.enumerated() {
            let code = codePart(of: raw, inString: &inString)
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            let atMemberLevel = open.isEmpty || open.last! != nil

            if atMemberLevel, !trimmed.isEmpty, let (kind, name) = APIListing.declaration(in: trimmed) {
                var names = [name]
                var labels: [String]?
                var types: [String]?
                switch kind {
                case .enumCase:
                    names = caseNames(continued(from: index, in: lines))
                case .function, .initializer, .subscriptMember:
                    let signature = signature(from: index, in: lines)
                    labels = sourceLabels(signature, kind: kind, name: name)
                    types = APIListing.parameterTypes(of: signature)
                case .type:
                    pending = typeName(trimmed)
                    if isExtension(trimmed) {
                        pendingConstraint = whereClause(trimmed).map { "where " + $0 }
                    } else if trimmed.range(of: #"(^|\s)protocol\s"#, options: .regularExpression) != nil {
                        pendingConstraint = "requirement"
                    } else {
                        pendingConstraint = nil
                    }
                default: break
                }
                let owner = open.compactMap { $0 }.flatMap { $0 }
                let above = comment(above: index, in: lines)
                let constraint = Array(zip(open, constraints)).last { $0.0 != nil }.flatMap { $0.1 }
                found.append(Written(owner: owner, name: name, kind: kind,
                                     names: names, labels: labels, line: index + 1,
                                     comment: above, isExtension: kind == .type && isExtension(trimmed),
                                     types: types, constraint: constraint))
                // `enum Kind { case left, right }` declares its cases on the
                // line that opens it, and they read as the type's.
                if kind == .type, let body = trimmed.firstIndex(of: "{") {
                    let inside = trimmed[trimmed.index(after: body)...].prefix { $0 != "}" }
                        .trimmingCharacters(in: .whitespaces)
                    if inside.hasPrefix("case ") {
                        let cases = caseNames(inside)
                        found.append(Written(owner: owner + (pending ?? []), name: cases.first ?? "",
                                             kind: .enumCase, names: cases, labels: nil,
                                             line: index + 1, comment: above))
                    }
                }
            }

            for character in code {
                if character == "{" {
                    open.append(pending)
                    constraints.append(pending == nil ? nil : pendingConstraint)
                    pending = nil
                    pendingConstraint = nil
                } else if character == "}", !open.isEmpty {
                    open.removeLast()
                    constraints.removeLast()
                }
            }
        }
        return found
    }

    /// The code on a line with its comment and the insides of its strings
    /// taken out, carrying a multi-line string across lines. Braces inside a
    /// string (a shader held as Swift text) are not the file's.
    static func codePart(of line: String, inString: inout Bool) -> String {
        var out = ""
        let characters = Array(line)
        var index = 0
        var inQuote = false
        while index < characters.count {
            let triple = index + 2 < characters.count
                && characters[index] == "\"" && characters[index + 1] == "\"" && characters[index + 2] == "\""
            if inString {
                if triple { inString = false; index += 3 } else { index += 1 }
                continue
            }
            if triple { inString = true; index += 3; continue }
            let character = characters[index]
            if inQuote {
                if character == "\\" { index += 2; continue }
                if character == "\"" { inQuote = false; out.append("\"") }
                index += 1
                continue
            }
            if character == "\"" { inQuote = true; out.append("\""); index += 1; continue }
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" { break }
            out.append(character)
            index += 1
        }
        return out
    }

    /// The labels a call writes. The source names a parameter once or twice,
    /// and once means the name is the label, except on a subscript or an
    /// operator, where a parameter has no label unless it is given two names
    /// (an operator never has one).
    static func sourceLabels(_ signature: String, kind: APIDeclaration.Kind, name: String) -> [String]? {
        guard let labels = APIListing.labels(of: signature) else { return nil }
        if kind == .function, let first = name.first, !(first.isLetter || first == "_") {
            return labels.map { _ in "_" }
        }
        guard kind == .subscriptMember, let list = APIListing.argumentList(in: signature) else { return labels }
        return APIListing.split(list).map { parameter in
            let words = parameter.prefix { $0 != ":" }.split(separator: " ")
            return words.count >= 2 ? String(words[0]) : "_"
        }
    }

    /// The declaration's text from its line until its first argument list
    /// closes, which a long signature spreads over several lines.
    static func signature(from index: Int, in lines: [String]) -> String {
        var text = ""
        var depth = 0
        var opened = false
        for line in lines[index ..< min(lines.count, index + 40)] {
            text += " " + line.trimmingCharacters(in: .whitespaces)
            for character in line {
                if character == "(" { depth += 1; opened = true }
                if character == ")" { depth -= 1 }
            }
            if opened && depth <= 0 { break }
        }
        return text
    }

    /// The `///` lines right above a declaration, stepping over its
    /// attributes.
    static func comment(above index: Int, in lines: [String]) -> [String] {
        var collected: [String] = []
        var line = index - 1
        while line >= 0 {
            let trimmed = lines[line].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                var text = trimmed.dropFirst(3)
                if text.first == " " { text = text.dropFirst() }
                collected.append(String(text))
            } else if trimmed.hasPrefix("@"), collected.isEmpty {
                // An attribute on a line of its own, between comment and declaration.
            } else {
                break
            }
            line -= 1
        }
        return collected.reversed()
    }

    /// A line and the ones after it while it ends in a comma: a `case`
    /// list running onto the next line.
    static func continued(from index: Int, in lines: [String]) -> String {
        var text = ""
        for line in lines[index ..< min(lines.count, index + 40)] {
            var ignored = false
            let code = codePart(of: line, inString: &ignored).trimmingCharacters(in: .whitespaces)
            text += " " + code
            if !code.hasSuffix(",") { break }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func caseNames(_ line: String) -> [String] {
        guard let range = line.range(of: "case ") else { return [] }
        return APIListing.split(String(line[range.upperBound...])).compactMap {
            APIListing.identifier(at: Substring($0.trimmingCharacters(in: .whitespaces)))
        }
    }

    /// The `where` clause on a type or extension's opening line, without the
    /// brace: `Value: ParamOption` from `extension Param where Value: ParamOption {`.
    static func whereClause(_ line: String) -> String? {
        guard let range = line.range(of: " where ") else { return nil }
        let clause = line[range.upperBound...].prefix { $0 != "{" }.trimmingCharacters(in: .whitespaces)
        return clause.isEmpty ? nil : clause
    }

    static func isExtension(_ line: String) -> Bool {
        line.range(of: #"(^|\s)extension\s"#, options: .regularExpression) != nil
    }

    /// `extension Light.Kind where …` opens both names.
    static func typeName(_ line: String) -> [String] {
        // `extension [TuringScale]` adds to the array type.
        if line.range(of: #"\bextension\s+\["#, options: .regularExpression) != nil { return ["Array"] }
        let pattern = #"\b(?:extension|struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_.]*)"#
        guard let match = line.range(of: pattern, options: .regularExpression) else { return [] }
        let spelled = line[match].split(separator: " ", omittingEmptySubsequences: true).last ?? ""
        return spelled.split(separator: ".").map(String.init)
    }

    static func swiftFiles(in folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }
}
