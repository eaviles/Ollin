import Foundation

/// A GLSL token, carrying its exact text so the whole stream concatenates back
/// into the source it came from. Whitespace and comments are tokens too, which is
/// what lets a translation keep the author's own layout: a rule rewrites the few
/// tokens it cares about and every other byte survives untouched.
struct GLSLToken: Equatable {
    enum Kind: Equatable {
        case whitespace
        case comment
        /// A whole `#…` line, taken verbatim. The preprocessor is close enough in
        /// both languages that these usually pass straight through.
        case directive
        case identifier
        case number
        case punctuation
    }

    var kind: Kind
    var text: String
    /// 1-based line the token starts on, for a diagnostic that names a place.
    var line: Int
    /// Which bracket this token was when it was read, kept apart from the text so
    /// that rewriting the text can never make the source unreadable to the passes
    /// that walk it. A rule may turn a `(` into a `{` or hang a whole argument off
    /// a `)`, and every later pass still sees the shape the author wrote.
    var bracket: Character?

    /// Whether the token carries meaning rather than layout.
    var isSignificant: Bool { kind != .whitespace && kind != .comment }

    /// Whether the token still carries meaning. A rule removes a token by emptying
    /// its text, and an emptied token must stop counting.
    var hasText: Bool { isSignificant && !text.isEmpty }
}

/// Splits GLSL into tokens. It is a lexer only: it never builds a tree, because
/// the translation works on names and on a handful of local shapes (a parameter
/// list, a call, a struct body), and a full parser would be far more to keep
/// right than those rules need.
enum GLSLLexer {

    static func tokenize(_ source: String) -> [GLSLToken] {
        var tokens: [GLSLToken] = []
        let chars = Array(source)
        var i = 0
        var line = 1
        /// True until the current line has a non-blank character, so a `#` is read
        /// as a directive only where one can legally start.
        var atLineStart = true

        func take(_ kind: GLSLToken.Kind, from start: Int, to end: Int) {
            let text = String(chars[start..<end])
            let bracket: Character? = (kind == .punctuation && text.count == 1
                                       && "()[]{}".contains(text)) ? Character(text) : nil
            tokens.append(GLSLToken(kind: kind, text: text, line: line, bracket: bracket))
            line += text.filter { $0 == "\n" }.count
        }

        while i < chars.count {
            let c = chars[i]

            if c == "\n" || c == " " || c == "\t" || c == "\r" {
                let start = i
                while i < chars.count, chars[i] == "\n" || chars[i] == " " || chars[i] == "\t" || chars[i] == "\r" {
                    if chars[i] == "\n" { atLineStart = true }
                    i += 1
                }
                take(.whitespace, from: start, to: i)
                continue
            }

            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                let start = i
                while i < chars.count, chars[i] != "\n" { i += 1 }
                take(.comment, from: start, to: i)
                atLineStart = false
                continue
            }

            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(i + 2, chars.count)
                take(.comment, from: start, to: i)
                atLineStart = false
                continue
            }

            // A directive runs to the end of the line, and keeps going while the
            // line ends in a backslash.
            if c == "#", atLineStart {
                let start = i
                while i < chars.count {
                    if chars[i] == "\n" {
                        // A continued directive swallows the newline and carries on.
                        var back = i - 1
                        while back >= start, chars[back] == " " || chars[back] == "\t" || chars[back] == "\r" { back -= 1 }
                        if back >= start, chars[back] == "\\" { i += 1; continue }
                        break
                    }
                    i += 1
                }
                take(.directive, from: start, to: i)
                continue
            }

            atLineStart = false

            if c.isLetter || c == "_" {
                let start = i
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { i += 1 }
                take(.identifier, from: start, to: i)
                continue
            }

            // A number, including the `.5` form. A lone `.` before a non-digit is
            // the member operator and falls through to punctuation.
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                let start = i
                if c == "0", i + 1 < chars.count, chars[i + 1] == "x" || chars[i + 1] == "X" {
                    i += 2
                    while i < chars.count, chars[i].isHexDigit { i += 1 }
                } else {
                    while i < chars.count, chars[i].isNumber { i += 1 }
                    if i < chars.count, chars[i] == "." {
                        i += 1
                        while i < chars.count, chars[i].isNumber { i += 1 }
                    }
                    if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                        var j = i + 1
                        if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                        if j < chars.count, chars[j].isNumber {
                            i = j
                            while i < chars.count, chars[i].isNumber { i += 1 }
                        }
                    }
                }
                // Width and sign suffixes.
                while i < chars.count, "uUfFlL".contains(chars[i]) { i += 1 }
                take(.number, from: start, to: i)
                continue
            }

            // Punctuation, longest match first so `<<=` never reads as `<` `<=`.
            let three = ["<<=", ">>="]
            let two = ["<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "^^",
                       "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "++", "--"]
            var matched = false
            for op in three where i + 3 <= chars.count && String(chars[i..<(i + 3)]) == op {
                take(.punctuation, from: i, to: i + 3); i += 3; matched = true; break
            }
            if matched { continue }
            for op in two where i + 2 <= chars.count && String(chars[i..<(i + 2)]) == op {
                take(.punctuation, from: i, to: i + 2); i += 2; matched = true; break
            }
            if matched { continue }
            take(.punctuation, from: i, to: i + 1)
            i += 1
        }
        return tokens
    }

    /// Puts a token stream back together. Concatenation is the whole of it, which
    /// is the property that keeps a translated shader looking like what was pasted.
    static func join(_ tokens: [GLSLToken]) -> String {
        tokens.map(\.text).joined()
    }
}

extension Array where Element == GLSLToken {
    /// The index of the next token that still carries meaning, at or after `i`.
    /// A token a rule has emptied is skipped, because it is no longer there.
    func nextSignificant(from i: Int) -> Int? {
        var j = i
        while j < count {
            if self[j].hasText { return j }
            j += 1
        }
        return nil
    }

    /// The index of the previous token that still carries meaning, at or before `i`.
    func previousSignificant(from i: Int) -> Int? {
        var j = i
        while j >= 0 {
            if j < count, self[j].hasText { return j }
            j -= 1
        }
        return nil
    }

    /// Given the index of an opening bracket, the index of the one that closes it.
    /// Returns nil when the source is unbalanced, so a caller leaves it alone
    /// rather than rewriting past the end.
    ///
    /// The match runs on what each token *was*, not on what a rule has since
    /// written into it.
    func matchingBracket(from open: Int) -> Int? {
        let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
        guard let opener = self[open].bracket, let closer = pairs[opener] else { return nil }
        var depth = 0
        var i = open
        while i < count {
            if let b = self[i].bracket {
                if b == opener { depth += 1 }
                else if b == closer {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i += 1
        }
        return nil
    }
}
