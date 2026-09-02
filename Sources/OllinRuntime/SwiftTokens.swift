import Foundation

/// The runs a Swift source splits into, for a host that colors code.
///
/// One regex pass over the whole document is plenty at sketch scale (a few
/// hundred lines), and the same eight patterns serve every host that shows
/// Swift: the performance editor paints them as text-storage attributes, the
/// generator's stage as an attributed string. Keeping the patterns here is what
/// keeps the two from drifting apart.
///
/// The runs come back in the order they are meant to be applied, and a later
/// run wins where two overlap: a keyword inside a string reads as string, a
/// string inside a comment as comment. A consumer applies them in order and
/// nothing else.
public enum SwiftTokens {

    public enum Kind: Sendable, Equatable {
        case type, number, keyword, attribute, string, comment
    }

    public struct Run: Sendable, Equatable {
        /// A UTF-16 range into the text the run was found in, which is what an
        /// `NSAttributedString` and an `NSTextStorage` both address by.
        public let range: NSRange
        public let kind: Kind

        public init(range: NSRange, kind: Kind) {
            self.range = range
            self.kind = kind
        }
    }

    public static let keywords = [
        "as", "any", "associatedtype", "await", "break", "case", "catch", "class",
        "continue", "convenience", "default", "defer", "deinit", "do", "else",
        "enum", "extension", "fallthrough", "false", "final", "for", "func",
        "guard", "if", "import", "in", "indirect", "infix", "init", "inout",
        "internal", "is", "lazy", "let", "mutating", "nil", "nonisolated", "open",
        "operator", "override", "private", "protocol", "public", "repeat",
        "required", "return", "self", "some", "static", "struct", "subscript",
        "super", "switch", "throw", "throws", "true", "try", "typealias",
        "unowned", "var", "weak", "where", "while",
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed literals; a failure is a programmer error.
        try! NSRegularExpression(pattern: pattern)
    }

    /// In application order. Types first so a later, narrower match (a keyword,
    /// a string) paints over them; comments last so they win over everything.
    private static let patterns: [(kind: Kind, regex: NSRegularExpression)] = [
        (.type, regex(#"\b[A-Z][A-Za-z0-9_]*\b"#)),
        (.number, regex(#"\b\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?\b"#)),
        (.keyword, regex(#"\b(?:"# + keywords.joined(separator: "|") + #")\b"#)),
        (.attribute, regex(#"@\w+"#)),
        (.string, regex(#"\"\"\"[\s\S]*?\"\"\""#)),
        (.string, regex(#""(?:[^"\\\n]|\\.)*""#)),
        (.comment, regex(#"//[^\n]*"#)),
        (.comment, regex(#"/\*[\s\S]*?\*/"#)),
    ]

    /// Every run in `text`, in the order to apply them.
    public static func runs(in text: String) -> [Run] {
        let all = NSRange(location: 0, length: (text as NSString).length)
        var runs: [Run] = []
        for pattern in patterns {
            pattern.regex.enumerateMatches(in: text, range: all) { match, _, _ in
                guard let match else { return }
                runs.append(Run(range: match.range, kind: pattern.kind))
            }
        }
        return runs
    }
}
