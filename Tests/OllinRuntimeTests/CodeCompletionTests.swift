import Foundation
import Testing
@testable import OllinRuntime

/// The text side of completion: where a word starts, what counts as a member
/// dot, how a placeholder is spelled, and where the next one is. Pure text,
/// no service; the service itself is proven by `OllinLiveCoding --selftest`,
/// which asks it for `drawCircle` against the real framework.
@Suite
struct CodeCompletionTests {
    private let line = "        fill(.black)\n        drawCi"

    @Test func aWordStartsWhereItsLettersDo() {
        let caret = (line as NSString).length
        #expect(CompletionText.wordStart(in: line, caret: caret) == caret - 6)
        #expect(CompletionText.prefix(in: line, caret: caret) == "drawCi")
        // Inside the word the same start is found, with less of it typed.
        #expect(CompletionText.wordStart(in: line, caret: caret - 2) == caret - 6)
        #expect(CompletionText.prefix(in: line, caret: caret - 2) == "draw")
    }

    @Test func noWordAfterASpaceABracketOrADot() {
        for text in ["drawCircle(", "let x = ", "Color.", ""] {
            let caret = (text as NSString).length
            #expect(CompletionText.wordStart(in: text, caret: caret) == caret, "\(text)")
            #expect(CompletionText.prefix(in: text, caret: caret).isEmpty)
        }
    }

    @Test func aNumberIsNotAWord() {
        let text = "let r = 120"
        let caret = (text as NSString).length
        #expect(CompletionText.wordStart(in: text, caret: caret) == caret)
        // A digit inside a name is fine; only a leading one makes a number.
        let named = "let p = point2"
        let end = (named as NSString).length
        #expect(CompletionText.wordStart(in: named, caret: end) == end - 6)
        let underscored = "_hidden"
        #expect(CompletionText.wordStart(in: underscored, caret: 7) == 0)
    }

    @Test func aMemberDotIsOneAfterANameOrABracket() {
        for text in ["Color.", "background(.", "points[0].", "self.", "a?."] {
            #expect(CompletionText.isMemberAccess(in: text, caret: (text as NSString).length), "\(text)")
        }
        for text in ["0.", "0..", "a..", "", "Color", "x = ."] {
            let caret = (text as NSString).length
            let isMember = CompletionText.isMemberAccess(in: text, caret: caret)
            #expect(isMember == (text == "x = ."), "\(text)")
        }
    }

    @Test func aPlaceholderKeepsItsDisplayAndDropsItsType() {
        let full = "drawCircle(<#T##x: Double##Double#>, <#T##y: Double##Double#>, <#T##radius: Double##Double#>)"
        #expect(CompletionText.reducingPlaceholders(full)
                == "drawCircle(<#x: Double#>, <#y: Double#>, <#radius: Double#>)")
        // A placeholder with no separate display keeps its type as the display.
        #expect(CompletionText.reducingPlaceholders("count: <#T##Int?#>") == "count: <#Int?#>")
        // A closure type carries an arrow inside; it survives whole.
        #expect(CompletionText.reducingPlaceholders("run(<#T##body: () -> Void##() -> Void#>)")
                == "run(<#body: () -> Void#>)")
        // Text with no placeholder, and an unterminated one, come back as they were.
        #expect(CompletionText.reducingPlaceholders("red") == "red")
        #expect(CompletionText.reducingPlaceholders("a <#b") == "a <#b")
    }

    @Test func tabFindsTheNextPlaceholderAndWraps() {
        let text = "drawCircle(<#x: Double#>, <#y: Double#>)\nfill(.black)"
        let first = NSRange(location: 11, length: 13)
        let second = NSRange(location: 26, length: 13)
        #expect(CompletionText.placeholder(in: text, after: 0) == first)
        #expect(CompletionText.placeholder(in: text, after: 11) == first)
        #expect(CompletionText.placeholder(in: text, after: 12) == second)
        #expect(CompletionText.placeholder(in: text, after: first.location + first.length) == second)
        // Past the last one the search wraps to the first.
        #expect(CompletionText.placeholder(in: text, after: (text as NSString).length) == first)
        #expect(CompletionText.placeholder(in: "fill(.black)", after: 0) == nil)
    }

    @Test func offsetsCountBytesForTheServiceAndUnitsForTheEditor() {
        // A comment with an accent and an emoji before the code: UTF-16 and
        // UTF-8 disagree on both, and the editor and the service each want
        // their own count.
        let text = "// café 🎨\nbackground(.white)\ndraw"
        let caret = (text as NSString).length
        let start = CompletionText.wordStart(in: text, caret: caret)
        #expect(String(text.utf16.prefix(start))! == "// café 🎨\nbackground(.white)\n")
        let bytes = CompletionText.utf8Offset(of: start, in: text)
        #expect(bytes == "// café 🎨\nbackground(.white)\n".utf8.count)
        #expect(CompletionText.utf16Offset(ofUTF8: bytes, in: text) == start)
        // Out-of-range offsets clamp rather than trap.
        #expect(CompletionText.utf8Offset(of: caret + 50, in: text) == text.utf8.count)
        #expect(CompletionText.utf16Offset(ofUTF8: -3, in: text) == 0)
    }

    @Test func theServicesKindNamesMapOntoTheListsGlyphs() {
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.function.method.instance") == .function)
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.function.free") == .function)
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.function.constructor") == .initializer)
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.var.instance") == .property)
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.var.class") == .property)
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.enumelement") == .enumCase)
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.struct") == .type)
        #expect(CodeCompleter.kind(of: "source.lang.swift.decl.typealias") == .type)
        #expect(CodeCompleter.kind(of: "source.lang.swift.keyword") == .keyword)
        #expect(CodeCompleter.kind(of: "source.lang.swift.literal.color") == .other)
        #expect(CodeCompleter.kind(of: "") == .other)
    }

    @Test func theCompletionArgumentsNameTheSDKTheModuleAndTheFile() {
        let loader = SketchLoader(sketchPath: "/tmp/somewhere/Sketch.swift")
        let args = loader.completionArguments(sourceFile: "/tmp/somewhere/Sketch.swift")
        #expect(args.first == "-sdk")
        #expect(args.count > 1 && args[1].hasSuffix(".sdk"))
        #expect(args.contains("-parse-as-library"))
        // Never the file's own name: a module called `Sketch` would shadow the
        // class every sketch extends.
        if let name = args.firstIndex(of: "-module-name") {
            #expect(args[name + 1] == "OllinRuntimeCompletion")
        } else {
            Issue.record("no -module-name in \(args)")
        }
        #expect(args.last == "/tmp/somewhere/Sketch.swift")
        // A completion request compiles nothing and links nothing.
        #expect(!args.contains("-emit-library"))
        #expect(!args.contains("-o"))
    }

    @Test func theFrameworksAreLookedForBesideTheCompiler() {
        let paths = CodeCompleter.frameworkPaths
        // On a machine with a toolchain the two frameworks are named in order,
        // the out-of-process one first; without one the list is empty.
        if !paths.isEmpty {
            #expect(paths.count == 2)
            #expect(paths[0].hasSuffix("sourcekitd.framework/sourcekitd"))
            #expect(paths[1].hasSuffix("sourcekitdInProc.framework/sourcekitdInProc"))
        }
    }
}
