import Foundation

/// Markdown as a web page's body.
///
/// The same pages the terminal renderer reads, written out as HTML for the
/// site. It is the same kind of renderer, for the shapes this repository's
/// pages actually take rather than a markdown implementation, and the two
/// share their line joiner, their list and link scanners, and their idea of
/// which line starts what. What differs is the output: headings carry the
/// anchors the pages already link to, lists nest, tables are tables, the raw
/// figure blocks pass through with their paths pointed at where the site put
/// the pictures, and code is colored.
///
/// Every path a page names goes through `resolve`, so this file knows nothing
/// about where the site lives. It hands over the target as the page wrote it
/// and takes back whatever the site decided: another page, a picture, a file
/// on GitHub, or the same text unchanged.
public enum HTML {

    /// One rendered page: its body, and the facts the layout wants from it.
    public struct Page: Sendable {
        /// The body, without any chrome.
        public var body: String
        /// The page's own heading, as plain text.
        public var title: String
        /// The trail the page opened with, already rendered, or empty.
        public var trail: String
        /// The headings a rail can list: level, plain text, and anchor.
        public var headings: [(level: Int, text: String, anchor: String)]
        /// The prose under each heading as plain text, one entry more than
        /// `headings`: the first is whatever came before any heading, and
        /// the rest follow the headings in order. Code, figures, and raw
        /// blocks are left out, since they are not prose. This is what the
        /// site's search reads.
        public var sections: [String]

        public init(body: String, title: String, trail: String,
                    headings: [(level: Int, text: String, anchor: String)],
                    sections: [String] = []) {
            self.body = body
            self.title = title
            self.trail = trail
            self.headings = headings
            self.sections = sections
        }
    }

    /// What a path in a page turns into on the site.
    public enum Target: Sendable, Equatable {
        /// A link's new `href`.
        case link(String)
        /// A picture's new `src`.
        case image(String)
    }

    /// Resolves a path the page wrote (`../Drawing/Color.md#ramps`,
    /// `Images/02-Color/HueWheels.jpg`) to the one the site serves. The Boolean
    /// says whether it is a picture, since the two are placed differently.
    public typealias Resolver = (_ target: String, _ image: Bool) -> String

    // MARK: - Whole pages

    public static func render(_ markdown: String, resolve: @escaping Resolver) -> Page {
        var lines = markdown.components(separatedBy: "\n")
        let trailSource = takeTrail(&lines)
        lines = Markdown.joined(lines)

        var out: [String] = []
        var headings: [(level: Int, text: String, anchor: String)] = []
        var anchors: [String: Int] = [:]
        var title: String?
        var index = 0
        var sections = [""]
        func note(_ markdown: String) {
            let text = plainText(markdown)
            guard !text.isEmpty else { return }
            sections[sections.count - 1] += sections[sections.count - 1].isEmpty ? text : " " + text
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                out.append(codeBlock(code.joined(separator: "\n"), language: language))
                continue
            }

            if trimmed.hasPrefix("|") {
                var rows: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                out.append(table(rows, resolve: resolve))
                for cell in tableCells(rows) { note(cell) }
                continue
            }

            if isRawBlock(trimmed) {
                out.append(rewritten(line, resolve: resolve))
                index += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                let plain = Markdown.plain(text)
                let anchor = uniqueAnchor(slug(plain), used: &anchors)
                if title == nil, level <= 2 { title = plain }
                headings.append((level, plain, anchor))
                sections.append("")
                out.append("<h\(level) id=\"\(anchor)\">\(inline(text, resolve: resolve))</h\(level)>")
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                out.append("<hr>")
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoted.append(String(candidate.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                out.append(blockquote(quoted, resolve: resolve))
                for line in quoted { note(line) }
                continue
            }

            if Markdown.listItem(line) != nil {
                var items: [(indent: Int, ordered: Bool, text: String)] = []
                while index < lines.count, let item = Markdown.listItem(lines[index]) {
                    items.append((item.indent, item.ordered, item.text))
                    index += 1
                }
                out.append(list(items, resolve: resolve))
                for item in items { note(item.text) }
                continue
            }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            let paragraphClass = paragraphClass(trimmed)
            out.append("<p\(paragraphClass)>\(inline(trimmed, resolve: resolve))</p>")
            if paragraphClass.isEmpty { note(trimmed) }
            index += 1
        }

        let trail = trailSource.map { inline($0, resolve: resolve) } ?? ""
        return Page(body: out.joined(separator: "\n"),
                    title: title ?? "",
                    trail: trail,
                    headings: headings,
                    sections: sections)
    }

    /// Prose as text alone: markers and links reduced to their words, pictures
    /// and tags dropped, runs of space closed up. What a section says, for an
    /// index or an excerpt.
    public static func plainText(_ markdown: String) -> String {
        var text = Markdown.plain(markdown)
        // A picture reads as its caption in the terminal; here it is not prose.
        while let open = text.range(of: "[figure:"), let close = text[open.upperBound...].firstIndex(of: "]") {
            text.removeSubrange(open.lowerBound ... close)
        }
        var kept = ""
        kept.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "<", let next = text.index(index, offsetBy: 1, limitedBy: text.endIndex), next < text.endIndex,
               text[next].isLetter || text[next] == "/",
               let close = text[next...].firstIndex(of: ">") {
                index = text.index(after: close)
                continue
            }
            kept.append(character)
            index = text.index(after: index)
        }
        return kept.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The navigation line most pages open with, taken off the top so the
    /// layout can place it, along with the rule under it when there is one.
    /// Same bound as the terminal's: the rule has to be right there.
    static func takeTrail(_ lines: inout [String]) -> String? {
        guard let first = lines.first, first.hasPrefix("#### <sup>") else { return nil }
        var cut = 1
        while cut < lines.count, cut < 4, lines[cut].trimmingCharacters(in: .whitespaces).isEmpty { cut += 1 }
        if cut < lines.count, lines[cut].trimmingCharacters(in: .whitespaces) == "---" {
            cut += 1
        } else {
            cut = 1
        }
        lines.removeFirst(min(cut, lines.count))
        var body = String(first.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("<sup>") { body.removeFirst(5) }
        if body.hasSuffix("</sup>") { body.removeLast(6) }
        return body
    }

    /// A line that is HTML already: the figure blocks, the explicit anchors
    /// the pages link to, and the tags inside a figure. They pass through,
    /// with any path in them pointed at where the site put the file.
    static func isRawBlock(_ trimmed: String) -> Bool {
        for tag in ["<picture", "</picture", "<source", "<img", "<a name=", "<a id="] where trimmed.hasPrefix(tag) {
            return true
        }
        return false
    }

    /// A raw line with every `src`, `srcset`, and `href` resolved.
    static func rewritten(_ line: String, resolve: Resolver) -> String {
        var out = line
        for attribute in ["srcset", "src", "href"] {
            var searchFrom = out.startIndex
            while let found = out.range(of: "\(attribute)=\"", range: searchFrom ..< out.endIndex) {
                guard let close = out[found.upperBound...].firstIndex(of: "\"") else { break }
                let value = String(out[found.upperBound ..< close])
                let replacement = resolve(value, attribute != "href")
                out.replaceSubrange(found.upperBound ..< close, with: replacement)
                searchFrom = out.index(found.upperBound, offsetBy: replacement.count)
            }
        }
        return out
    }

    /// The one paragraph shape the layout treats specially: a row of badges,
    /// which is pictures and nothing else, each on its own or wrapped in a
    /// link.
    static func paragraphClass(_ trimmed: String) -> String {
        guard trimmed.hasPrefix("![") || trimmed.hasPrefix("[![") else { return "" }
        var rest = Substring(trimmed)
        while let link = Markdown.link(in: rest), link.image || link.text.hasPrefix("![") {
            rest = link.rest.drop { $0 == " " }
        }
        return rest.isEmpty ? " class=\"badges\"" : ""
    }

    // MARK: - Anchors

    /// The anchor a heading gets, the way the pages already link to them:
    /// tags and punctuation dropped, lower case, spaces to dashes. It has to
    /// agree with `Scripts/check-links.sh`, which is what proves the links
    /// resolve, so both keep to the same rule.
    public static func slug(_ heading: String) -> String {
        var text = heading
        while let open = text.range(of: "<"), let close = text[open.upperBound...].firstIndex(of: ">") {
            text.removeSubrange(open.lowerBound ... close)
        }
        let lowered = text.lowercased()
        var kept = ""
        for character in lowered {
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                kept.append(character)
            } else if character.isWhitespace {
                kept.append(" ")
            }
        }
        return kept.split(separator: " ").joined(separator: "-")
    }

    static func uniqueAnchor(_ slug: String, used: inout [String: Int]) -> String {
        let count = used[slug, default: 0]
        used[slug] = count + 1
        return count == 0 ? slug : "\(slug)-\(count)"
    }

    // MARK: - Inline

    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Prose with its markers turned into tags. A `<sup>` written into the
    /// prose is kept, since two pages close on one; every other angle bracket
    /// is text.
    public static func inline(_ text: String, resolve: Resolver) -> String {
        var out = ""
        var rest = Substring(text)

        while let character = rest.first {
            switch character {
            case "`":
                if let close = rest.dropFirst().firstIndex(of: "`") {
                    let body = String(rest[rest.index(after: rest.startIndex) ..< close])
                    out += "<code>\(escape(body))</code>"
                    rest = rest[rest.index(after: close)...]
                    continue
                }
            case "!", "[":
                if let link = Markdown.link(in: rest) {
                    if link.image {
                        let source = resolve(link.target, true)
                        out += "<img src=\"\(escape(source))\" alt=\"\(escape(link.text))\">"
                    } else {
                        let target = resolve(link.target, false)
                        let external = target.hasPrefix("http")
                        let extras = external ? " rel=\"noopener\"" : ""
                        out += "<a href=\"\(escape(target))\"\(extras)>\(inline(link.text, resolve: resolve))</a>"
                    }
                    rest = link.rest
                    continue
                }
            case "*":
                if let (body, after) = Markdown.emphasis(in: rest, marker: "**") {
                    out += "<strong>\(inline(body, resolve: resolve))</strong>"
                    rest = after
                    continue
                }
                if let (body, after) = Markdown.emphasis(in: rest, marker: "*") {
                    out += "<em>\(inline(body, resolve: resolve))</em>"
                    rest = after
                    continue
                }
            case "<":
                if let tag = ["<sup>", "</sup>"].first(where: { rest.hasPrefix($0) }) {
                    out += tag
                    rest = rest.dropFirst(tag.count)
                    continue
                }
            default:
                break
            }
            out += escape(String(character))
            rest = rest.dropFirst()
        }
        return out
    }

    // MARK: - Blocks

    static func blockquote(_ lines: [String], resolve: Resolver) -> String {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        let body = paragraphs.map { "<p>\(inline($0, resolve: resolve))</p>" }.joined(separator: "\n")
        return "<blockquote>\n\(body)\n</blockquote>"
    }

    /// Items nested by their indent. An item opens a deeper list inside
    /// itself when the next one is indented past it, and a shallower item
    /// closes everything above its own level first.
    static func list(_ items: [(indent: Int, ordered: Bool, text: String)], resolve: Resolver) -> String {
        var out = ""
        var stack: [(indent: Int, tag: String)] = []
        for item in items {
            while let top = stack.last, item.indent < top.indent {
                out += "</li></\(top.tag)>"
                stack.removeLast()
            }
            if let top = stack.last, item.indent == top.indent {
                out += "</li>\n"
            } else {
                let tag = item.ordered ? "ol" : "ul"
                out += "<\(tag)>\n"
                stack.append((item.indent, tag))
            }
            out += "<li>\(inline(item.text, resolve: resolve))"
        }
        while let top = stack.popLast() {
            out += "</li></\(top.tag)>"
        }
        return out
    }

    /// The cells of a table's rows, the rule row dropped, as the table
    /// renderer reads them.
    static func tableCells(_ rows: [String]) -> [String] {
        var cells: [String] = []
        for row in rows {
            var columns = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if columns.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { columns.removeFirst() }
            if columns.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { columns.removeLast() }
            let trimmed = columns.map { $0.trimmingCharacters(in: .whitespaces) }
            let isRule = !trimmed.isEmpty && trimmed.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
            }
            if isRule { continue }
            cells.append(contentsOf: trimmed)
        }
        return cells
    }

    static func table(_ rows: [String], resolve: Resolver) -> String {
        var cells: [[String]] = []
        for row in rows {
            var columns = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if columns.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { columns.removeFirst() }
            if columns.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { columns.removeLast() }
            let trimmed = columns.map { $0.trimmingCharacters(in: .whitespaces) }
            let isRule = !trimmed.isEmpty && trimmed.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
            }
            if isRule { continue }
            cells.append(trimmed)
        }
        guard let header = cells.first else { return "" }

        var out = "<div class=\"table\"><table>\n<thead><tr>"
        for cell in header { out += "<th>\(inline(cell, resolve: resolve))</th>" }
        out += "</tr></thead>\n<tbody>\n"
        for row in cells.dropFirst() {
            out += "<tr>"
            for column in 0 ..< header.count {
                let cell = column < row.count ? row[column] : ""
                out += "<td>\(inline(cell, resolve: resolve))</td>"
            }
            out += "</tr>\n"
        }
        out += "</tbody>\n</table></div>"
        return out
    }

    // MARK: - Code

    public static func codeBlock(_ code: String, language: String) -> String {
        let tag = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
        return "<pre><code\(tag)>\(highlighted(code, language: language))</code></pre>"
    }

    /// Code with its comments, strings, numbers, keywords, attributes, and
    /// type names wrapped for coloring. A tokenizer for reading rather than
    /// for compiling: it knows what a comment and a string look like and
    /// leaves everything it does not recognize as plain text.
    public static func highlighted(_ code: String, language: String) -> String {
        let keywords: Set<String>
        let lineComment: String
        var blockComments = true
        var hashComments = false
        switch language {
        case "swift":
            keywords = swiftKeywords
            lineComment = "//"
        case "metal", "c", "cpp", "glsl":
            keywords = metalKeywords
            lineComment = "//"
        case "sh", "bash", "zsh", "shell":
            keywords = []
            lineComment = "#"
            blockComments = false
            hashComments = true
        case "js", "javascript", "json":
            keywords = ["const", "let", "var", "function", "return", "import", "export", "true", "false", "null"]
            lineComment = "//"
        default:
            return escape(code)
        }

        var out = ""
        let characters = Array(code)
        var index = 0

        func span(_ kind: String, _ text: String) {
            out += "<span class=\"tk-\(kind)\">\(escape(text))</span>"
        }

        while index < characters.count {
            let character = characters[index]

            // Comments.
            if !hashComments, starts(characters, at: index, with: lineComment) {
                var end = index
                while end < characters.count, characters[end] != "\n" { end += 1 }
                span("comment", String(characters[index ..< end]))
                index = end
                continue
            }
            if hashComments, character == "#", index == 0 || characters[index - 1] == "\n" || characters[index - 1] == " " {
                var end = index
                while end < characters.count, characters[end] != "\n" { end += 1 }
                span("comment", String(characters[index ..< end]))
                index = end
                continue
            }
            if blockComments, starts(characters, at: index, with: "/*") {
                var end = index + 2
                var depth = 1
                while end < characters.count, depth > 0 {
                    if starts(characters, at: end, with: "/*") { depth += 1; end += 2; continue }
                    if starts(characters, at: end, with: "*/") { depth -= 1; end += 2; continue }
                    end += 1
                }
                span("comment", String(characters[index ..< end]))
                index = end
                continue
            }

            // Strings: plain, multi-line, and raw.
            if character == "\"" || (character == "#" && starts(characters, at: index, with: "#\"")) {
                var end = index
                var hashes = 0
                while end < characters.count, characters[end] == "#" { hashes += 1; end += 1 }
                let multiline = starts(characters, at: end, with: "\"\"\"")
                end += multiline ? 3 : 1
                let closing = (multiline ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
                while end < characters.count {
                    if characters[end] == "\\", hashes == 0 { end += 2; continue }
                    if starts(characters, at: end, with: closing) { end += closing.count; break }
                    if !multiline, characters[end] == "\n" { break }
                    end += 1
                }
                span("string", String(characters[index ..< min(end, characters.count)]))
                index = min(end, characters.count)
                continue
            }

            // Numbers.
            if character.isNumber, index == 0 || !(characters[index - 1].isLetter || characters[index - 1] == "_") {
                var end = index
                while end < characters.count,
                      characters[end].isNumber || characters[end] == "." || characters[end] == "_"
                        || characters[end] == "x" || characters[end] == "e"
                        || (characters[end].isHexDigit && starts(characters, at: index, with: "0x")) {
                    end += 1
                }
                span("number", String(characters[index ..< end]))
                index = end
                continue
            }

            // Words: attributes, keywords, and type names.
            if character.isLetter || character == "_" || character == "@" {
                var end = index + 1
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                    end += 1
                }
                let word = String(characters[index ..< end])
                if word.hasPrefix("@") {
                    span("attribute", word)
                } else if keywords.contains(word) {
                    span("keyword", word)
                } else if let first = word.first, first.isUppercase, !keywords.isEmpty {
                    span("type", word)
                } else {
                    out += escape(word)
                }
                index = end
                continue
            }

            out += escape(String(character))
            index += 1
        }
        return out
    }

    static func starts(_ characters: [Character], at index: Int, with text: String) -> Bool {
        let needle = Array(text)
        guard index + needle.count <= characters.count else { return false }
        for offset in 0 ..< needle.count where characters[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    static let swiftKeywords: Set<String> = [
        "let", "var", "func", "class", "struct", "enum", "protocol", "extension", "import", "return",
        "if", "else", "for", "in", "while", "repeat", "switch", "case", "default", "break", "continue",
        "guard", "defer", "do", "try", "catch", "throw", "throws", "rethrows", "async", "await", "actor",
        "init", "deinit", "self", "Self", "super", "static", "final", "override", "private", "fileprivate",
        "internal", "public", "open", "package", "where", "is", "as", "nil", "true", "false", "some", "any",
        "inout", "mutating", "nonmutating", "lazy", "weak", "unowned", "typealias", "associatedtype",
        "subscript", "operator", "indirect", "convenience", "required", "dynamic", "optional", "get", "set",
        "willSet", "didSet", "fallthrough", "consuming", "borrowing", "nonisolated", "isolated", "macro",
    ]

    static let metalKeywords: Set<String> = [
        "kernel", "vertex", "fragment", "constant", "device", "thread", "threadgroup", "using", "namespace",
        "struct", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue",
        "float", "float2", "float3", "float4", "half", "half2", "half3", "half4", "int", "int2", "int3",
        "int4", "uint", "uint2", "uint3", "uint4", "bool", "void", "inline", "static", "const", "template",
        "typename", "true", "false", "texture2d", "sampler", "float2x2", "float3x3", "float4x4", "ushort",
        "in", "out", "inout", "uniform", "varying", "attribute", "vec2", "vec3", "vec4", "mat2", "mat3",
        "mat4", "define", "include", "pragma", "auto", "sizeof", "unsigned", "char", "double", "long",
    ]
}
