@testable import OllinRuntime
import Foundation
import Testing

/// The token runs both code stages color from. Every check is on text alone.
@Suite
struct SwiftTokensTests {

    private func kinds(of text: String, at needle: String) -> [SwiftTokens.Kind] {
        let range = (text as NSString).range(of: needle)
        return SwiftTokens.runs(in: text)
            .filter { NSIntersectionRange($0.range, range).length == range.length }
            .map(\.kind)
    }

    @Test func eachKindIsFound() {
        let text = "@main final class Dots: Sketch { let n = 12 } // twelve"
        #expect(kinds(of: text, at: "@main") == [.attribute])
        #expect(kinds(of: text, at: "class") == [.keyword])
        #expect(kinds(of: text, at: "Sketch") == [.type])
        #expect(kinds(of: text, at: "12") == [.number])
        #expect(kinds(of: text, at: "// twelve") == [.comment])
    }

    /// A later run paints over an earlier one, so what a consumer that applies
    /// them in order ends up showing is decided here, not there.
    @Test func aLaterRunCoversAnEarlierOne() {
        let text = #"let title = "class Dots" // let"#
        let runs = SwiftTokens.runs(in: text)
        let string = (text as NSString).range(of: #""class Dots""#)
        let comment = (text as NSString).range(of: "// let")

        let stringIndex = runs.firstIndex { $0.range == string && $0.kind == .string }
        let keywordInString = runs.firstIndex { $0.kind == .keyword && NSIntersectionRange($0.range, string).length > 0 }
        let keywordInComment = runs.firstIndex { $0.kind == .keyword && NSIntersectionRange($0.range, comment).length > 0 }
        let commentIndex = runs.firstIndex { $0.range == comment && $0.kind == .comment }

        #expect(stringIndex != nil && keywordInString != nil && stringIndex! > keywordInString!)
        #expect(commentIndex != nil && keywordInComment != nil && commentIndex! > keywordInComment!)
    }

    /// The single-line pattern also bites on the empty pairs inside the
    /// triple quotes, which is harmless because every run it makes is string
    /// too; what matters is that one run spans the whole literal.
    @Test func aMultilineStringIsCoveredWhole() {
        let text = "let s = \"\"\"\nline one\nline two\n\"\"\"\n"
        let whole = (text as NSString).range(of: "\"\"\"\nline one\nline two\n\"\"\"")
        let strings = SwiftTokens.runs(in: text).filter { $0.kind == .string }
        #expect(strings.contains { $0.range == whole })
        #expect(strings.allSatisfy { NSIntersectionRange($0.range, whole).length == $0.range.length })
    }

    @Test func rangesAreUTF16SoAnEmojiCountsAsTwo() {
        // An attributed string addresses by UTF-16, and so must every run.
        let text = "// 🙂\nlet x = 1"
        let numbers = SwiftTokens.runs(in: text).filter { $0.kind == .number }
        #expect(numbers.first?.range == NSRange(location: 14, length: 1))
    }

    @Test func nothingIsFoundInNothing() {
        #expect(SwiftTokens.runs(in: "").isEmpty)
    }
}
