import Foundation
import OllinShaderText

/// Something the translation could not do, or did in a way worth knowing about.
/// Every one of these reaches the reader as a comment in the emitted file, so a
/// shader never comes out quietly different from the one that went in.
public struct GLSLDiagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        /// Translated, but the reader should know what happened.
        case note
        /// Left alone because no honest translation exists. The file will not
        /// compile until the reader deals with it.
        case unsupported
    }

    public var severity: Severity
    public var message: String
    /// 1-based line in the source that was handed in, or 0 when the message is
    /// about the file as a whole.
    public var line: Int

    public init(severity: Severity, message: String, line: Int = 0) {
        self.severity = severity
        self.message = message
        self.line = line
    }
}

/// The result of translating one GLSL source.
struct GLSLTranslation {
    /// The rewritten body, still holding the original function names and layout.
    var body: String
    var diagnostics: [GLSLDiagnostic]
    var helpers: Set<GLSLCompat.Helper>
    /// The token stream after rewriting, for a caller that needs to keep working
    /// on it (the entry-point mapping does).
    var tokens: [ShaderToken]
}

/// Rewrites GLSL into Metal at the level of names and small local shapes.
///
/// Every edit replaces the text of a token that is already there, and never adds
/// or removes one. That keeps every index a pass has worked out still valid for
/// the pass after it, and it is why the output keeps the spacing, the blank
/// lines, and the comments of the source it came from.
enum GLSLTranslator {

    static func translate(_ source: String) -> GLSLTranslation {
        var tokens = ShaderLexer.tokenize(source)
        var diagnostics: [GLSLDiagnostic] = []
        var helpers: Set<GLSLCompat.Helper> = []

        let structNames = ShaderScan.structNames(in: tokens)
        let functions = ShaderScan.functions(in: tokens)
        let functionNames = Set(functions.map(\.name))

        stripPrecision(&tokens)
        rewriteParameterQualifiers(&tokens, functions: functions)
        rewriteFileScopeDeclarations(&tokens, functions: functions, diagnostics: &diagnostics)
        rewriteTypes(&tokens)
        rewriteBuiltins(&tokens, functionNames: functionNames, structNames: structNames,
                        helpers: &helpers, diagnostics: &diagnostics)
        rewriteConstructions(&tokens, structNames: structNames)
        rewriteArrayConstructors(&tokens)

        return GLSLTranslation(body: ShaderLexer.join(tokens), diagnostics: diagnostics,
                               helpers: helpers, tokens: tokens)
    }

    // MARK: - Passes

    /// Removes the precision machinery, which Metal states per type instead.
    private static func stripPrecision(_ tokens: inout [ShaderToken]) {
        let qualifiers: Set<String> = ["lowp", "mediump", "highp"]
        var i = 0
        while i < tokens.count {
            guard tokens[i].kind == .identifier else { i += 1; continue }

            // A whole `precision highp float;` statement.
            if tokens[i].text == "precision" {
                var j = i
                while j < tokens.count, tokens[j].text != ";" { tokens[j].text = ""; j += 1 }
                if j < tokens.count { tokens[j].text = "" }
                i = j + 1
                continue
            }
            if qualifiers.contains(tokens[i].text) {
                tokens[i].text = ""
                // Take the space that followed it with it, so nothing is left doubled.
                if i + 1 < tokens.count, tokens[i + 1].kind == .whitespace,
                   !tokens[i + 1].text.contains("\n") {
                    tokens[i + 1].text = ""
                }
            }
            i += 1
        }
    }

    /// Turns a parameter GLSL marks as written-to into the Metal reference that
    /// says the same thing, and drops the plain input marker, which Metal implies.
    private static func rewriteParameterQualifiers(_ tokens: inout [ShaderToken], functions: [ShaderFunction]) {
        for fn in functions {
            var i = fn.openParen + 1
            var expectingParameter = true
            var depth = 0
            while i < fn.closeParen {
                let t = tokens[i]
                if let b = t.bracket {
                    if b == "(" || b == "[" || b == "{" { depth += 1 }
                    else { depth -= 1 }
                } else if t.kind == .punctuation, t.text == ",", depth == 0 {
                    expectingParameter = true; i += 1; continue
                }
                guard t.kind == .identifier, depth == 0 else {
                    if t.isSignificant, t.kind != .identifier { expectingParameter = false }
                    i += 1
                    continue
                }

                if expectingParameter, t.text == "out" || t.text == "inout" || t.text == "in" {
                    let isReference = t.text != "in"
                    tokens[i].text = isReference ? "thread" : ""
                    if !isReference, i + 1 < tokens.count, tokens[i + 1].kind == .whitespace,
                       !tokens[i + 1].text.contains("\n") {
                        tokens[i + 1].text = ""
                    }
                    if isReference,
                       let typeIndex = tokens.nextSignificant(from: i + 1),
                       let nameIndex = tokens.nextSignificant(from: typeIndex + 1),
                       tokens[nameIndex].kind == .identifier {
                        // `&` goes on the name, so the type token stays a bare name
                        // for the pass that renames types.
                        tokens[nameIndex].text = "&" + tokens[nameIndex].text
                    }
                }
                expectingParameter = false
                i += 1
            }
        }
    }

    /// Handles what sits at file scope outside a function: a constant becomes a
    /// Metal constant, and anything a shader means to write to is reported,
    /// because Metal has nowhere to put it.
    private static func rewriteFileScopeDeclarations(_ tokens: inout [ShaderToken],
                                                     functions: [ShaderFunction],
                                                     diagnostics: inout [GLSLDiagnostic]) {
        // Ranges a function already owns, so a body is never mistaken for a
        // file-scope statement.
        var owned: [Range<Int>] = []
        for fn in functions {
            let end = (fn.closeBrace ?? fn.closeParen) + 1
            owned.append(fn.nameIndex..<end)
        }
        func isOwned(_ i: Int) -> Bool { owned.contains { $0.contains(i) } }

        let droppedQualifiers: Set<String> = ["uniform", "varying", "attribute", "flat", "smooth", "noperspective"]
        let samplerTypes: Set<String> = ["sampler2D", "sampler3D", "samplerCube", "sampler2DArray",
                                         "sampler2DShadow", "isampler2D", "usampler2D"]

        var i = 0
        var depth = 0
        var statementStart: Int? = nil
        var statementIsStruct = false

        while i < tokens.count {
            let t = tokens[i]
            if let b = t.bracket {
                if b == "{" { depth += 1 }
                else if b == "}" { depth = max(0, depth - 1) }
            }
            guard depth == 0, !isOwned(i) else { i += 1; continue }

            if t.hasText, statementStart == nil, t.text != ";" {
                statementStart = i
                statementIsStruct = (t.kind == .identifier && t.text == "struct")
            }

            if t.hasText, t.kind == .punctuation, t.text == ";", let start = statementStart {
                if !statementIsStruct {
                    classifyFileScopeStatement(&tokens, from: start, to: i,
                                               droppedQualifiers: droppedQualifiers,
                                               samplerTypes: samplerTypes,
                                               diagnostics: &diagnostics)
                }
                statementStart = nil
                statementIsStruct = false
            }
            i += 1
        }
    }

    private static func classifyFileScopeStatement(_ tokens: inout [ShaderToken],
                                                   from start: Int, to end: Int,
                                                   droppedQualifiers: Set<String>,
                                                   samplerTypes: Set<String>,
                                                   diagnostics: inout [GLSLDiagnostic]) {
        var sawConst = false
        var sawDropped = false
        var sawSampler = false
        var sawInterfaceDirection = false
        var name = ""

        for i in start...end where tokens[i].kind == .identifier {
            let text = tokens[i].text
            if text == "const" { sawConst = true }
            else if droppedQualifiers.contains(text) { sawDropped = true }
            else if samplerTypes.contains(text) { sawSampler = true }
            else if text == "in" || text == "out" { sawInterfaceDirection = true }
            else if name.isEmpty, GLSLCompat.typeNames[text] == nil,
                    !["float", "int", "uint", "bool", "void", "struct", "layout",
                      "lowp", "mediump", "highp"].contains(text) {
                name = text
            }
        }

        let line = tokens[start].line

        if sawSampler {
            diagnostics.append(.init(
                severity: .unsupported,
                message: "\(name.isEmpty ? "a texture" : "'\(name)'") is a texture the shader declares itself. "
                    + "Ollin binds a layer instead: draw into a render target and pass it in.",
                line: line))
            return
        }

        if sawDropped || sawInterfaceDirection {
            diagnostics.append(.init(
                severity: .unsupported,
                message: "\(name.isEmpty ? "a value" : "'\(name)'") is declared as a pipeline input or output. "
                    + "Read it from 'info', or add it to the shader's params.",
                line: line))
            return
        }

        if sawConst {
            for i in start...end where tokens[i].kind == .identifier && tokens[i].text == "const" {
                tokens[i].text = "constant"
            }
            return
        }

        // A plain shader-wide variable. Metal has no address space that allows one
        // to be written, so the reader has to move it or pass it along.
        diagnostics.append(.init(
            severity: .unsupported,
            message: "\(name.isEmpty ? "a variable" : "'\(name)'") is a shader-wide variable the code can write to. "
                + "Metal has no such thing: make it 'constant' if it never changes, "
                + "or make it a local and pass it to the functions that use it.",
            line: line))
    }

    /// Renames the vector and matrix types.
    private static func rewriteTypes(_ tokens: inout [ShaderToken]) {
        for i in tokens.indices where tokens[i].kind == .identifier {
            if let mapped = GLSLCompat.typeNames[tokens[i].text] {
                tokens[i].text = mapped
            }
        }
    }

    /// Renames or reshapes the built-in calls.
    private static func rewriteBuiltins(_ tokens: inout [ShaderToken],
                                        functionNames: Set<String>,
                                        structNames: Set<String>,
                                        helpers: inout Set<GLSLCompat.Helper>,
                                        diagnostics: inout [GLSLDiagnostic]) {
        for i in tokens.indices where tokens[i].kind == .identifier {
            let name = tokens[i].text

            if name == "discard" {
                tokens[i].text = "discard_fragment()"
                continue
            }
            // A name the shader declares itself always wins over a built-in.
            guard !functionNames.contains(name), !structNames.contains(name) else { continue }
            guard let paren = tokens.nextSignificant(from: i + 1), tokens[paren].bracket == "(",
                  let close = tokens.matchingBracket(from: paren) else { continue }

            if let mapped = GLSLCompat.renamedFunctions[name] {
                tokens[i].text = mapped
                continue
            }

            if let reason = GLSLCompat.unsupportedFunctions[name] {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "'\(name)' has no direct Metal form. \(reason)",
                                         line: tokens[i].line))
                continue
            }

            if let op = GLSLCompat.relationalOperators[name] {
                let commas = topLevelCommas(in: tokens, from: paren, to: close)
                if commas.count == 1 {
                    tokens[i].text = ""
                    tokens[commas[0]].text = " " + op
                }
                continue
            }

            switch name {
            case "not":
                tokens[i].text = "!"
            case "atan":
                // One argument is the plain arc tangent; two is the quadrant-aware
                // one, which Metal gives a different name.
                if topLevelCommas(in: tokens, from: paren, to: close).count == 1 {
                    tokens[i].text = "atan2"
                }
            case "mod":
                tokens[i].text = GLSLCompat.Helper.mod.rawValue
                helpers.insert(.mod)
            case "inverse":
                tokens[i].text = GLSLCompat.Helper.inverse.rawValue
                helpers.insert(.inverse)
                diagnostics.append(.init(
                    severity: .note,
                    message: "'inverse' is supplied for 2x2 and 3x3 matrices only; a 4x4 needs writing by hand.",
                    line: tokens[i].line))
            case "matrixCompMult":
                tokens[i].text = GLSLCompat.Helper.matrixCompMult.rawValue
                helpers.insert(.matrixCompMult)
            default:
                break
            }
        }
    }

    /// Turns a struct construction into the Metal spelling. GLSL builds one with
    /// parentheses; Metal fills the members in braces.
    private static func rewriteConstructions(_ tokens: inout [ShaderToken], structNames: Set<String>) {
        guard !structNames.isEmpty else { return }
        for i in tokens.indices where tokens[i].kind == .identifier && structNames.contains(tokens[i].text) {
            // Skip the declaration itself.
            if let before = tokens.previousSignificant(from: i - 1), tokens[before].text == "struct" { continue }
            guard let paren = tokens.nextSignificant(from: i + 1), tokens[paren].bracket == "(",
                  let close = tokens.matchingBracket(from: paren) else { continue }
            tokens[paren].text = "{"
            tokens[close].text = "}"
        }
    }

    /// Turns an array construction into the Metal spelling: the type and its size
    /// go away and the values stay in braces.
    private static func rewriteArrayConstructors(_ tokens: inout [ShaderToken]) {
        var i = 0
        while i < tokens.count {
            guard tokens[i].kind == .identifier,
                  let bracket = tokens.nextSignificant(from: i + 1), tokens[bracket].bracket == "[",
                  let closeBracket = tokens.matchingBracket(from: bracket),
                  let paren = tokens.nextSignificant(from: closeBracket + 1), tokens[paren].bracket == "(",
                  let close = tokens.matchingBracket(from: paren)
            else { i += 1; continue }

            // `name[i](…)` is a call on an element, not a construction. A
            // construction names a type, and a type is followed by nothing else.
            let isType = GLSLCompat.typeNames.values.contains(tokens[i].text)
                || ["float", "int", "uint", "bool"].contains(tokens[i].text)
            guard isType else { i += 1; continue }

            for j in i...closeBracket { tokens[j].text = "" }
            tokens[paren].text = "{"
            tokens[close].text = "}"
            i = close + 1
        }
    }

    // MARK: - Helpers

    /// The commas that separate one argument list, ignoring any nested inside it.
    static func topLevelCommas(in tokens: [ShaderToken], from open: Int, to close: Int) -> [Int] {
        tokens.topLevelCommas(from: open, to: close)
    }
}
