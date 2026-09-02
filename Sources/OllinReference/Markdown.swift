import Foundation

/// How the reference is dressed for the terminal it is printed into.
///
/// Color is a separate flag from width because the two are decided by
/// different things: width comes from the window, color from whether anybody
/// is looking. A page piped into a pager is still read by a person, so the
/// caller says `color` even though its own output is a pipe.
public struct TerminalStyle: Sendable, Equatable {
    public var color: Bool
    public var width: Int

    public init(color: Bool = false, width: Int = 80) {
        self.color = color
        self.width = max(24, width)
    }

    /// No escape codes at all: what a file or another program receives.
    public static let plain = TerminalStyle(color: false, width: 80)

    static let escape = "\u{1B}"

    func wrapped(_ text: String, in codes: String) -> String {
        color && !text.isEmpty ? "\(Self.escape)[\(codes)m\(text)\(Self.escape)[0m" : text
    }

    public func bold(_ text: String) -> String { wrapped(text, in: "1") }
    public func dim(_ text: String) -> String { wrapped(text, in: "2") }
    public func italic(_ text: String) -> String { wrapped(text, in: "3") }
    public func heading(_ text: String) -> String { wrapped(text, in: "1;4") }

    /// An identifier keeps its backticks when there is no color to mark it
    /// with. Plain output is read by somebody with no styling at all, and
    /// `drawCircle` without them reads as an ordinary word.
    public func code(_ text: String) -> String {
        color ? wrapped(text, in: "36") : "`\(text)`"
    }
}

/// Markdown as a terminal page.
///
/// This is a renderer for the pages this repository actually holds, not a
/// markdown implementation: headings, paragraphs, lists, fenced code, tables,
/// block quotes, and the figure blocks written as raw HTML. Anything else
/// falls through as its own text, which is the failure everybody wants, since
/// the worst case is a line that reads exactly as the file spells it.
public enum Markdown {

    // MARK: - Whole pages

    public static func render(_ markdown: String, style: TerminalStyle) -> String {
        var lines = markdown.components(separatedBy: "\n")
        dropBreadcrumb(&lines)
        lines = joined(lines)

        var out: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                appendBlank(&out)
                // Code keeps its own spelling and its own line breaks: it is
                // there to be copied, so nothing is wrapped or restyled.
                out += code.map { "    " + $0 }
                out.append("")
                continue
            }

            if trimmed.hasPrefix("|") {
                var rows: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                appendBlank(&out)
                out += table(rows, style: style)
                out.append("")
                continue
            }

            if trimmed.hasPrefix("<") {
                if let alt = altText(in: trimmed) {
                    appendBlank(&out)
                    out.append(style.dim("[figure: \(alt)]"))
                    out.append("")
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                appendBlank(&out)
                out.append(level <= 2 ? style.heading(plain(text)) : style.bold(inline(text, style: style)))
                out.append("")
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                appendBlank(&out)
                out.append(style.dim(String(repeating: "-", count: min(style.width, 60))))
                out.append("")
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                let body = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                out += wrapped(inline(body, style: style), width: style.width - 4).map { "  " + style.dim($0) }
                index += 1
                continue
            }

            if let item = listItem(line) {
                let marker = item.ordered ? item.marker + " " : "- "
                let lead = String(repeating: " ", count: item.indent)
                let body = wrapped(inline(item.text, style: style),
                                width: style.width - item.indent - marker.count)
                for (row, text) in body.enumerated() {
                    out.append(lead + (row == 0 ? marker : String(repeating: " ", count: marker.count)) + text)
                }
                index += 1
                continue
            }

            if trimmed.isEmpty {
                appendBlank(&out)
                index += 1
                continue
            }

            out += wrapped(inline(trimmed, style: style), width: style.width)
            index += 1
        }

        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    /// The navigation line most pages open with, which is a link trail for a
    /// browser and noise in a terminal.
    ///
    /// The rule under it is dropped with it, but only if it is right there.
    /// A page that carries the trail and no rule exists, and hunting for one
    /// through the whole file takes the page with it.
    static func dropBreadcrumb(_ lines: inout [String]) {
        guard lines.first?.hasPrefix("#### <sup>") == true else { return }
        var cut = 1
        while cut < lines.count, cut < 4, lines[cut].trimmingCharacters(in: .whitespaces).isEmpty { cut += 1 }
        if cut < lines.count, lines[cut].trimmingCharacters(in: .whitespaces) == "---" {
            cut += 1
        } else {
            cut = 1
        }
        lines.removeFirst(min(cut, lines.count))
    }

    static func appendBlank(_ out: inout [String]) {
        if let last = out.last, !last.isEmpty { out.append("") }
    }

    /// A paragraph carried over several lines, put back on one.
    ///
    /// Most pages here write a paragraph as one long line, but not all of
    /// them, and the difference matters more than it looks: a link split
    /// across two lines is two halves of nothing until they are joined, and
    /// one such paragraph would otherwise print `family](#combining)` at the
    /// reader. Fenced code is passed through untouched, and so is anything
    /// indented four spaces, since that is code as well.
    static func joined(_ lines: [String]) -> [String] {
        var out: [String] = []
        var inFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                out.append(line)
                continue
            }
            let indented = line.hasPrefix("    ")
            if !inFence, !indented, !trimmed.isEmpty, !opensBlock(trimmed),
               let last = out.last, continuable(last) {
                out[out.count - 1] = last + " " + trimmed
                continue
            }
            out.append(line)
        }
        return out
    }

    /// Whether a line starts something of its own rather than carrying on the
    /// line above it.
    static func opensBlock(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("|") || trimmed.hasPrefix("<")
            || trimmed.hasPrefix(">") || trimmed.hasPrefix("```") { return true }
        if trimmed == "---" || trimmed == "***" || trimmed == "___" { return true }
        return listItem(trimmed) != nil
    }

    /// Whether the line above can take more text: prose and list items can,
    /// and everything with a shape of its own cannot.
    static func continuable(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || line.hasPrefix("    ") { return false }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("|") || trimmed.hasPrefix("<")
            || trimmed.hasPrefix("```") { return false }
        if trimmed == "---" || trimmed == "***" || trimmed == "___" { return false }
        return true
    }

    // MARK: - One section

    /// One section of a page, from its heading to the next heading at the same
    /// level or above.
    ///
    /// The name is matched the way somebody would type it, so the heading's
    /// backticks and punctuation are dropped and a web anchor's dashes count
    /// as spaces.
    public static func section(_ name: String, in markdown: String) -> String? {
        let wanted = anchor(name)
        guard !wanted.isEmpty else { return nil }
        let lines = markdown.components(separatedBy: "\n")

        var exact: Int?
        var loose: Int?
        for (number, line) in lines.enumerated() {
            guard line.hasPrefix("#") else { continue }
            let level = line.prefix { $0 == "#" }.count
            guard level >= 2 else { continue }
            let heading = anchor(String(line.dropFirst(level)))
            if heading == wanted { exact = number; break }
            if loose == nil, heading.contains(wanted) { loose = number }
        }
        guard let start = exact ?? loose else { return nil }

        let level = lines[start].prefix { $0 == "#" }.count
        var end = start + 1
        while end < lines.count {
            let line = lines[end]
            if line.hasPrefix("#") {
                let next = line.prefix { $0 == "#" }.count
                if next <= level { break }
            }
            end += 1
        }
        return lines[start ..< end].joined(separator: "\n")
    }

    /// Every heading of a page, as a reader would type them.
    public static func headings(in markdown: String) -> [String] {
        markdown.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("##") else { return nil }
            let level = line.prefix { $0 == "#" }.count
            return plain(String(line.dropFirst(level))).trimmingCharacters(in: .whitespaces)
        }
    }

    static func anchor(_ text: String) -> String {
        let stripped = plain(text).lowercased()
        let spaced = stripped.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    // MARK: - Inline

    /// Markdown with its markers taken off and nothing put back: what a title,
    /// a table measurement, or a search hit needs.
    public static func plain(_ text: String) -> String {
        inline(text, style: TerminalStyle(color: false, width: 1_000_000), quoting: false)
    }

    static func inline(_ text: String, style: TerminalStyle) -> String {
        inline(text, style: style, quoting: true)
    }

    static func inline(_ text: String, style: TerminalStyle, quoting: Bool) -> String {
        var out = ""
        var rest = Substring(text)

        while let character = rest.first {
            switch character {
            case "`":
                if let close = rest.dropFirst().firstIndex(of: "`") {
                    let body = String(rest[rest.index(after: rest.startIndex) ..< close])
                    out += quoting ? style.code(body) : body
                    rest = rest[rest.index(after: close)...]
                    continue
                }
            case "!", "[":
                if let link = self.link(in: rest) {
                    if link.image {
                        out += style.dim("[figure: \(inline(link.text, style: style, quoting: false))]")
                    } else {
                        out += inline(link.text, style: style, quoting: quoting)
                        // A relative link points at another page, and the topic
                        // is already in the text. A web address cannot be
                        // followed from here, so it is spelled out instead.
                        if quoting, link.target.hasPrefix("http") {
                            out += style.dim(" <\(link.target)>")
                        }
                    }
                    rest = link.rest
                    continue
                }
            case "*":
                if let (body, after) = emphasis(in: rest, marker: "**") {
                    out += style.bold(inline(body, style: style, quoting: quoting))
                    rest = after
                    continue
                }
                if let (body, after) = emphasis(in: rest, marker: "*") {
                    out += style.italic(inline(body, style: style, quoting: quoting))
                    rest = after
                    continue
                }
            default:
                break
            }
            out.append(character)
            rest = rest.dropFirst()
        }
        return out
    }

    /// An emphasized run opened by `marker` at the start of the text: its
    /// body and what follows it.
    ///
    /// A marker followed by a space opens nothing, and one preceded by a
    /// space closes nothing, which is the rule that keeps `1 + F0 * (1/E - 1)`
    /// a multiplication rather than the start of an italic that swallows the
    /// rest of the line. A marker with no close is text.
    static func emphasis(in text: Substring, marker: String) -> (body: String, rest: Substring)? {
        guard text.hasPrefix(marker) else { return nil }
        let opened = text.dropFirst(marker.count)
        guard let first = opened.first, !first.isWhitespace else { return nil }
        var search = opened.startIndex
        while let close = opened[search...].range(of: marker) {
            let before = close.lowerBound > opened.startIndex ? opened[opened.index(before: close.lowerBound)] : " "
            if !before.isWhitespace {
                return (String(opened[opened.startIndex ..< close.lowerBound]), opened[close.upperBound...])
            }
            search = close.upperBound
        }
        return nil
    }

    /// A markdown link, or an image when it carries the leading mark.
    static func link(in text: Substring) -> (text: String, target: String, image: Bool, rest: Substring)? {
        var body = text
        var image = false
        if body.hasPrefix("!") {
            image = true
            body = body.dropFirst()
        }
        guard body.hasPrefix("[") else { return nil }

        // Counted rather than searched for, so a link whose text holds its own
        // brackets still ends where it really ends.
        var depth = 0
        var closing: Substring.Index?
        var index = body.startIndex
        while index < body.endIndex {
            if body[index] == "[" { depth += 1 }
            if body[index] == "]" {
                depth -= 1
                if depth == 0 { closing = index; break }
            }
            index = body.index(after: index)
        }
        guard let close = closing, body.index(after: close) < body.endIndex,
              body[body.index(after: close)] == "(",
              let end = body[body.index(close, offsetBy: 2)...].firstIndex(of: ")") else { return nil }

        let label = String(body[body.index(after: body.startIndex) ..< close])
        let target = String(body[body.index(close, offsetBy: 2) ..< end])
        return (label, target, image, body[body.index(after: end)...])
    }

    /// The description a figure carries, whether it is written as markdown or
    /// as the raw `img` tag the pages use for sized figures. It is the only
    /// part of a picture a terminal can show.
    static func altText(in line: String) -> String? {
        guard let start = line.range(of: "alt=\"") else { return nil }
        guard let end = line[start.upperBound...].firstIndex(of: "\"") else { return nil }
        let alt = String(line[start.upperBound ..< end]).trimmingCharacters(in: .whitespaces)
        return alt.isEmpty ? nil : alt
    }

    // MARK: - Lists

    static func listItem(_ line: String) -> (indent: Int, marker: String, ordered: Bool, text: String)? {
        let indent = line.prefix { $0 == " " }.count
        let body = line.dropFirst(indent)
        for marker in ["- ", "* ", "+ "] where body.hasPrefix(marker) {
            return (indent, "-", false, String(body.dropFirst(2)))
        }
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". ") {
            return (indent, digits + ".", true, String(body.dropFirst(digits.count + 2)))
        }
        return nil
    }

    // MARK: - Tables

    static func table(_ rows: [String], style: TerminalStyle) -> [String] {
        var cells: [[String]] = []
        for row in rows {
            var columns = row.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if columns.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { columns.removeFirst() }
            if columns.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { columns.removeLast() }
            let trimmed = columns.map { $0.trimmingCharacters(in: .whitespaces) }
            // The rule row under the header carries no content.
            let isRule = !trimmed.isEmpty && trimmed.allSatisfy { cell in
                !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
            }
            if isRule { continue }
            cells.append(trimmed)
        }
        guard !cells.isEmpty else { return [] }

        let count = cells.map(\.count).max() ?? 0
        let rendered = cells.map { row in
            (0 ..< count).map { column in
                column < row.count ? inline(row[column], style: style) : ""
            }
        }

        var widths = (0 ..< count).map { column in
            rendered.map { visibleLength($0[column]) }.max() ?? 0
        }
        widths = fitted(widths, into: style.width)

        var out: [String] = []
        for (number, row) in rendered.enumerated() {
            let stacks = (0 ..< count).map { wrapped(row[$0], width: widths[$0]) }
            let height = stacks.map(\.count).max() ?? 1
            for line in 0 ..< max(height, 1) {
                var text = ""
                for column in 0 ..< count {
                    let piece = line < stacks[column].count ? stacks[column][line] : ""
                    let padded = piece + String(repeating: " ",
                                                count: max(0, widths[column] - visibleLength(piece)))
                    text += column == count - 1 ? piece : padded + "  "
                }
                out.append(number == 0 ? style.bold(text) : text)
            }
            if number == 0 {
                out.append(style.dim(String(repeating: "-",
                                            count: min(style.width, widths.reduce(0, +) + 2 * (count - 1)))))
            }
        }
        return out
    }

    /// Column widths that fit the window, taking the space off the widest
    /// columns first so a narrow one is never squeezed to nothing.
    static func fitted(_ widths: [Int], into width: Int) -> [Int] {
        let gutters = 2 * max(0, widths.count - 1)
        var result = widths
        var total = result.reduce(0, +) + gutters
        var steps = 0
        while total > width, steps < 10_000 {
            guard let widest = result.indices.max(by: { result[$0] < result[$1] }) else { break }
            if result[widest] <= 12 { break }
            result[widest] -= 1
            total -= 1
            steps += 1
        }
        return result
    }

    // MARK: - Wrapping

    /// The width a line takes on screen, which is not its length: the escape
    /// codes that color it occupy no columns.
    public static func visibleLength(_ text: String) -> Int {
        var count = 0
        var inEscape = false
        for character in text {
            if inEscape {
                if character.isLetter { inEscape = false }
                continue
            }
            if character == "\u{1B}" { inEscape = true; continue }
            count += 1
        }
        return count
    }

    /// A line broken to fit a window, at spaces, counting only the columns it
    /// really takes.
    public static func wrapped(_ text: String, width: Int) -> [String] {
        guard width > 4 else { return [text] }
        var lines: [String] = []
        var current = ""
        var length = 0
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let piece = String(word)
            let size = visibleLength(piece)
            if length > 0, length + 1 + size > width {
                lines.append(current)
                current = piece
                length = size
                continue
            }
            if length == 0 {
                current = piece
                length = size
            } else {
                current += " " + piece
                length += 1 + size
            }
        }
        if !current.isEmpty || lines.isEmpty { lines.append(current) }
        return lines
    }
}
