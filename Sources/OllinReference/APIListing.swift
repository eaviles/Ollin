import Foundation

/// One public declaration, as the listings under `API/` write it.
///
/// Those listings are one line per declaration, written by
/// `Scripts/api-surface.sh` from what the compiler says each library exports,
/// and nested two spaces a level under the type they belong to. That makes
/// them the one place that settles "is this public, and what are its labels"
/// without reading the source, which is where `ollin api` starts.
public struct APIDeclaration: Sendable, Equatable {

    public enum Kind: String, Sendable {
        case type, function, initializer, property, enumCase, subscriptMember, typeAlias, other
    }

    /// The library it belongs to: `Ollin`, `OllinAudio`, and so on.
    public let module: String
    /// The types it is nested in, outermost first. Empty at the top level.
    public let owner: [String]
    public let name: String
    public let kind: Kind
    /// The line as the listing writes it, without its indentation.
    public let text: String
    /// Where the listing writes it, counting from 1.
    public let line: Int

    public init(module: String, owner: [String], name: String, kind: Kind, text: String, line: Int) {
        self.module = module
        self.owner = owner
        self.name = name
        self.kind = kind
        self.text = text
        self.line = line
    }

    /// `Sketch.drawCircle`, `Light.Kind.point`, or just the name at the top
    /// level.
    public var qualifiedName: String { (owner + [name]).joined(separator: ".") }

    /// An `extension Double` line opens members, and declares nothing itself.
    public var isExtension: Bool {
        kind == .type && text.range(of: #"(^|\s)extension\s"#, options: .regularExpression) != nil
    }

    /// The argument labels in order, `_` for an unlabeled one, or nil for a
    /// declaration called without an argument list.
    public var labels: [String]? {
        switch kind {
        case .function, .initializer, .subscriptMember: APIListing.labels(of: text)
        default: nil
        }
    }
}

/// Reading the listings under `API/` and answering a name with what they say.
public enum APIListing {

    /// Every declaration in every listing in a folder.
    public static func declarations(inAPI folder: URL) -> [APIDeclaration] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { file -> [APIDeclaration] in
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
                return declarations(in: text, module: file.deletingPathExtension().lastPathComponent)
            }
    }

    /// The declarations in one listing. A type's members sit one level deeper
    /// than the type, so the level a line is indented to says which open type
    /// it belongs to.
    public static func declarations(in listing: String, module: String) -> [APIDeclaration] {
        var found: [APIDeclaration] = []
        var open: [String] = []
        for (index, raw) in listing.components(separatedBy: "\n").enumerated() {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("//") else { continue }
            let level = raw.prefix { $0 == " " }.count / 2
            if open.count > level { open.removeLast(open.count - level) }
            let (kind, name) = declaration(in: text) ?? (.other, text)
            found.append(APIDeclaration(module: module, owner: open, name: name, kind: kind,
                                        text: text, line: index + 1))
            if kind == .type, open.count == level { open.append(name) }
        }
        return found
    }

    // MARK: - Asking by name

    /// What a name asks for: every declaration it names, and when it names
    /// nothing exactly, the public names spelled most like it.
    public struct Answer: Sendable, Equatable {
        public var declarations: [APIDeclaration]
        public var nearby: [String]
    }

    /// Answers `drawCircle`, `Mesh.tube`, `Light.Kind`, or `Material`.
    ///
    /// The part after the last dot is the name and anything before it is the
    /// type it sits on, matched from the inside out, so `Kind.point` finds
    /// `Light.Kind.point`. An exact spelling wins; failing that, the same name
    /// in any case; failing both, nothing is claimed and the names that look
    /// like it come back instead, which is how "what is it called" gets an
    /// answer.
    public static func answer(_ query: String, in all: [APIDeclaration]) -> Answer {
        var parts = query.split(separator: ".").map(String.init)
        guard let name = parts.popLast() else { return Answer(declarations: [], nearby: []) }
        let owner = parts

        func sits(_ declaration: APIDeclaration, caseless: Bool) -> Bool {
            guard owner.count <= declaration.owner.count else { return false }
            let tail = Array(declaration.owner.suffix(owner.count))
            return caseless ? tail.map { $0.lowercased() } == owner.map { $0.lowercased() } : tail == owner
        }

        var exact = all.filter { $0.name == name && !$0.isExtension && sits($0, caseless: false) }
        if exact.isEmpty {
            let lower = name.lowercased()
            exact = all.filter { $0.name.lowercased() == lower && !$0.isExtension && sits($0, caseless: true) }
        }
        return Answer(declarations: exact,
                      nearby: nearby(name, in: all, excluding: Set(exact.map(\.qualifiedName)), fuzzy: exact.isEmpty))
    }

    /// The members a type's listing writes under it, across every library
    /// that extends it.
    public static func members(of type: APIDeclaration, in all: [APIDeclaration]) -> [APIDeclaration] {
        let path = type.owner + [type.name]
        return all.filter { $0.owner == path }
    }

    /// Public names containing the one asked for, the closest first, and
    /// when `fuzzy`, the names a letter off it too (two, for a long one): a
    /// misspelling wants those, and a name that was found does not.
    static func nearby(_ name: String, in all: [APIDeclaration], excluding taken: Set<String>,
                       fuzzy: Bool, limit: Int = 16) -> [String] {
        let wanted = name.lowercased()
        guard wanted.count >= 3 else { return [] }
        var scored: [String: Int] = [:]
        for declaration in all where !declaration.isExtension && declaration.kind != .initializer {
            let qualified = declaration.qualifiedName
            guard !taken.contains(qualified), scored[qualified] == nil else { continue }
            let candidate = declaration.name.lowercased()
            var score: Int?
            if candidate.hasPrefix(wanted) { score = 0 }
            else if candidate.contains(wanted) { score = 1 }
            else if fuzzy, wanted.count >= 4 {
                let allowed = wanted.count >= 8 ? 2 : 1
                if abs(candidate.count - wanted.count) <= allowed, distance(candidate, wanted) <= allowed { score = 2 }
            }
            if let score { scored[qualified] = score * 1000 + candidate.count }
        }
        return scored.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            .prefix(limit).map(\.key)
    }

    /// Edit distance, for the names a letter or two off.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0 ... b.count)
        for i in 1 ... a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1 ... b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Reading a declaration

    /// The spelling a person reads: the source-location parameters the
    /// shape-dragging calls take are dropped (the compiler fills them and
    /// nobody passes one), and so are the module names in front of system
    /// types.
    public static func tidy(_ text: String) -> String {
        var out = text.replacingOccurrences(
            of: ", file: StaticString = default, line: Int = default, column: Int = default", with: "")
        out = out.replacingOccurrences(
            of: #"\b(?:Swift|Foundation|CoreFoundation|CoreGraphics|ObjectiveC|Metal|MetalKit|AppKit|SwiftUI|SwiftUICore|simd|Dispatch|QuartzCore|CoreImage|CoreVideo|CoreMedia|AVFoundation|ScreenSaver|_Concurrency|Ollin)\."#,
            with: "", options: .regularExpression)
        return out
    }

    /// The kind of declaration a line opens and the name it declares, or nil
    /// when the line opens none. Reads a listing's line and a source line
    /// alike: attributes and modifiers first, then the keyword that decides.
    static func declaration(in line: String) -> (APIDeclaration.Kind, String)? {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        skipAttributes(&rest)
        while let word = leadingWord(rest) {
            let bare = word.split(separator: "(").first.map(String.init) ?? word
            guard modifiers.contains(bare) else { break }
            // `class` is a modifier only in front of a member: `class func`.
            if bare == "class" {
                let after = rest.dropFirst(word.count).drop { $0 == " " }
                guard let next = leadingWord(after), memberKeywords.contains(next) || next == "class" else { break }
            }
            rest = rest.dropFirst(word.count).drop { $0 == " " }
            skipAttributes(&rest)
        }
        guard let keyword = identifier(at: rest) else { return nil }
        let after = rest.dropFirst(keyword.count)
        switch keyword {
        case "func":
            let name = after.drop { $0 == " " }.prefix { $0 != "(" && $0 != "<" && $0 != " " }
            return name.isEmpty ? nil : (.function, String(name))
        case "init":
            return (.initializer, "init")
        case "subscript":
            return (.subscriptMember, "subscript")
        case "var", "let":
            return identifier(at: after.drop { $0 == " " }).map { (.property, $0) }
        case "case":
            return identifier(at: after.drop { $0 == " " }).map { (.enumCase, $0) }
        case "typealias", "associatedtype":
            return identifier(at: after.drop { $0 == " " }).map { (.typeAlias, $0) }
        case "class", "struct", "enum", "protocol", "actor", "extension":
            // `extension [TuringScale]` adds to the array type.
            if keyword == "extension", after.drop(while: { $0 == " " }).first == "[" { return (.type, "Array") }
            let spelled = after.drop { $0 == " " }.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            guard let last = spelled.split(separator: ".").last else { return nil }
            return (.type, String(last))
        default:
            return nil
        }
    }

    /// The argument labels of a declaration's first argument list, `_` for
    /// an unlabeled one. The listing and the source both put the external
    /// label first, so one reading serves both: a source's `_ x: Double` and
    /// the listing's `_: Double` are both `_`.
    static func labels(of text: String) -> [String]? {
        // An attribute's own parentheses (`@available(...)`) come first on
        // the line and are not the argument list.
        var declaration = Substring(text.trimmingCharacters(in: .whitespaces))
        skipAttributes(&declaration)
        guard let list = argumentList(in: String(declaration)) else { return nil }
        return split(list).compactMap { parameter in
            let head = parameter.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
            var words = Substring(head)
            skipAttributes(&words)
            return words.split(separator: " ").first.map(String.init)
        }
    }

    /// The text between the first argument list's parentheses, skipping a
    /// generic clause in front of it.
    static func argumentList(in text: String) -> String? {
        let characters = Array(text)
        var index = 0
        // Up to the name: past `func name`, `init?`, `subscript`.
        var angle = 0
        while index < characters.count {
            let character = characters[index]
            if character == "<" { angle += 1 }
            else if character == ">", index > 0, characters[index - 1] != "-" { angle -= 1 }
            else if character == "(", angle == 0 { break }
            index += 1
        }
        guard index < characters.count else { return nil }
        var depth = 0
        let start = index + 1
        while index < characters.count {
            switch characters[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return String(characters[start ..< index]) }
            default: break
            }
            index += 1
        }
        return nil
    }

    /// An argument list cut at its top-level commas.
    static func split(_ list: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var previous: Character = " "
        for character in list {
            switch character {
            case "(", "[", "<", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case ">" where previous != "-": depth -= 1
            case "," where depth == 0:
                parts.append(current)
                current = ""
                previous = character
                continue
            default: break
            }
            current.append(character)
            previous = character
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(current) }
        return parts
    }

    static let modifiers: Set<String> = [
        "open", "public", "package", "internal", "private", "fileprivate",
        "final", "static", "class", "mutating", "nonmutating", "override", "required",
        "convenience", "optional", "nonisolated", "dynamic", "lazy", "weak", "unowned",
        "indirect", "prefix", "postfix", "infix", "isolated", "consuming", "borrowing",
    ]

    static let memberKeywords: Set<String> = ["func", "var", "let", "subscript", "init", "deinit", "static"]

    static func skipAttributes(_ text: inout Substring) {
        while text.first == "@" {
            text = text.dropFirst().drop { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            if text.first == "(" {
                var depth = 0
                var end = text.startIndex
                for index in text.indices {
                    if text[index] == "(" { depth += 1 }
                    if text[index] == ")" { depth -= 1 }
                    if depth == 0 { end = text.index(after: index); break }
                }
                text = text[end...]
            }
            text = text.drop { $0 == " " }
        }
    }

    /// The word up to the next space, parentheses and all: `private(set)`.
    static func leadingWord(_ text: Substring) -> String? {
        let word = text.prefix { $0 != " " }
        return word.isEmpty ? nil : String(word)
    }

    /// A name at the start of the text; a backticked one (`` `return` ``)
    /// without its backticks.
    static func identifier(at text: Substring) -> String? {
        if text.first == "`" {
            let word = text.dropFirst().prefix { $0 != "`" }
            return word.isEmpty ? nil : String(word)
        }
        let word = text.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return word.isEmpty ? nil : String(word)
    }
}
