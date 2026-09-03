import Foundation

/// Something the translation could not do, or did in a way worth knowing about.
/// Nothing is dropped in silence: every one of these reaches the reader, and an
/// `unsupported` one means the page will not compile until it is dealt with.
package struct WebShaderDiagnostic: Sendable, Equatable {
    package enum Severity: Sendable, Equatable {
        /// Translated, but the reader should know what happened.
        case note
        /// Left alone because no honest translation exists.
        case unsupported
    }

    package var severity: Severity
    package var message: String
    /// 1-based line in the source that was handed in, or 0 when the message is
    /// about the file as a whole.
    package var line: Int

    package init(severity: Severity, message: String, line: Int = 0) {
        self.severity = severity
        self.message = message
        self.line = line
    }
}

/// The result of translating one Metal source to GLSL ES 3.00.
package struct WebShaderTranslation {
    /// The rewritten body, still holding the original function names and layout.
    package var body: String
    package var diagnostics: [WebShaderDiagnostic]
    /// The GLSL helpers the body calls.
    package var helpers: Set<WebShaderCompat.Helper>
    /// The named constants the body reads, each of which becomes a `#define`.
    package var constants: Set<String>
    /// The token stream after rewriting, for a caller that keeps working on it.
    package var tokens: [ShaderToken]

    /// Whether every construct crossed. A clean translation compiles on its own;
    /// one that is not carries at least one `unsupported` diagnostic saying why.
    package var isClean: Bool { !diagnostics.contains { $0.severity == .unsupported } }
    package var unsupported: [WebShaderDiagnostic] { diagnostics.filter { $0.severity == .unsupported } }

    /// The support text the body needs ahead of it: constants and helpers.
    package var support: String { WebShaderCompat.source(for: helpers, constants: constants) }
}

/// Rewrites Metal shading language into GLSL ES 3.00 at the level of names and
/// small local shapes: the GLSL import's rewriter run the other way, over the
/// same lexer.
///
/// Every edit replaces the text of a token that is already there, and never adds
/// or removes one. That keeps every index a pass has worked out still valid for
/// the pass after it, and it is why the output keeps the spacing, the blank
/// lines, and the comments of the source it came from. The rules are the ones
/// the two languages actually disagree on: the storage words Metal has and GLSL
/// lacks, the type spellings, a reference parameter against `inout`, `select`
/// and the vector comparisons, the sign of `fmod`, a brace initializer against a
/// constructor, and the names GLSL keeps for itself. Anything with no honest
/// form (a pointer into a buffer, a texture read, an entry point) is reported,
/// never guessed.
package enum WebShaderTranslator {

    package static func translate(_ source: String) -> WebShaderTranslation {
        var tokens = ShaderLexer.tokenize(source)
        var diagnostics: [WebShaderDiagnostic] = []
        var helpers: Set<WebShaderCompat.Helper> = []
        var constants: Set<String> = []

        renameReservedWords(&tokens, diagnostics: &diagnostics)
        rewriteDirectives(&tokens, constants: &constants)
        dropUsingAndNamespaces(&tokens, diagnostics: &diagnostics)
        dropStorageWords(&tokens)

        let structNames = ShaderScan.structNames(in: tokens)
        let functions = ShaderScan.functions(in: tokens)
        let functionNames = Set(functions.map(\.name))

        rewriteParameters(&tokens, functions: functions, diagnostics: &diagnostics)
        rewriteAddressSpaces(&tokens, functions: functions, diagnostics: &diagnostics)
        rewriteTypes(&tokens, diagnostics: &diagnostics)
        rewriteScalarInitializers(&tokens)
        rewriteNumbers(&tokens)
        rewriteBuiltins(&tokens, functions: functions, functionNames: functionNames, structNames: structNames,
                        helpers: &helpers, constants: &constants, diagnostics: &diagnostics)
        rewriteAggregates(&tokens, functions: functions, structNames: structNames, diagnostics: &diagnostics)
        reportAttributes(&tokens, diagnostics: &diagnostics)

        return WebShaderTranslation(body: ShaderLexer.join(tokens), diagnostics: diagnostics,
                                    helpers: helpers, constants: constants, tokens: tokens)
    }

    // MARK: - Passes

    /// A name GLSL keeps for itself gets a trailing underscore, and the two
    /// spellings GLSL reserves outright (`gl_` and a double underscore) are
    /// rewritten. A struct member is renamed where it is declared and where it is
    /// read, since GLSL reserves the word there too. This runs first, on the
    /// source as written, so a word a later rule writes (`inout`, `const`) is
    /// never mistaken for one the author used.
    private static func renameReservedWords(_ tokens: inout [ShaderToken], diagnostics: inout [WebShaderDiagnostic]) {
        var reported: Set<String> = []
        for i in tokens.indices where tokens[i].kind == .identifier {
            // A member read is renamed with its declaration; a member call is a
            // texture read, left for the pass that reports it.
            if isMemberAccess(tokens, i), let next = tokens.nextSignificant(from: i + 1), tokens[next].bracket == "(" {
                continue
            }
            let name = tokens[i].text
            var renamed: String? = nil
            if WebShaderCompat.reservedWords.contains(name) {
                renamed = name + "_"
            } else if name.hasPrefix("gl_") {
                renamed = "ollin_" + name.dropFirst(3)
            } else if name.contains("__") {
                var collapsed = name
                while collapsed.contains("__") { collapsed = collapsed.replacingOccurrences(of: "__", with: "_") }
                renamed = collapsed
            }
            guard let new = renamed else { continue }
            tokens[i].text = new
            if reported.insert(name).inserted {
                diagnostics.append(.init(severity: .note,
                                         message: "'\(name)' is a word GLSL reserves; it is spelled '\(new)' on the page.",
                                         line: tokens[i].line))
            }
        }
    }

    /// The includes and pragmas belong to the Metal toolchain and go away; a
    /// conditional or a macro carries on, with its Metal type names rewritten.
    private static func rewriteDirectives(_ tokens: inout [ShaderToken], constants: inout Set<String>) {
        for i in tokens.indices where tokens[i].kind == .directive {
            let text = tokens[i].text
            let afterHash = text.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
            let head = String(afterHash.prefix(while: { $0.isLetter }))
            switch head {
            case "include", "import", "pragma", "line":
                tokens[i].text = ""
            case "define", "if", "elif", "ifdef", "ifndef", "else", "endif", "undef", "error":
                tokens[i].text = rewriteWords(in: text, constants: &constants)
            default:
                break
            }
        }
    }

    /// Word-level rewriting inside a directive's text: the type names and the
    /// plain renames, with a constant recorded when one is read.
    private static func rewriteWords(in text: String, constants: inout Set<String>) -> String {
        var out = ""
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            if let mapped = WebShaderCompat.typeNames[word] { out += mapped }
            else if let mapped = WebShaderCompat.renamedFunctions[word] { out += mapped }
            else {
                if WebShaderCompat.constantValues[word] != nil { constants.insert(word) }
                out += word
            }
            word = ""
        }
        for c in text {
            if c.isLetter || c.isNumber || c == "_" {
                if word.isEmpty, c.isNumber { out.append(c) } else { word.append(c) }
            } else {
                flush()
                out.append(c)
            }
        }
        flush()
        return out
    }

    /// `using namespace metal;` goes away; a namespace of the shader's own has
    /// no GLSL form and is reported.
    private static func dropUsingAndNamespaces(_ tokens: inout [ShaderToken], diagnostics: inout [WebShaderDiagnostic]) {
        var depth = 0
        var i = 0
        while i < tokens.count {
            if let b = tokens[i].bracket {
                if b == "{" { depth += 1 } else if b == "}" { depth = max(0, depth - 1) }
            }
            guard tokens[i].kind == .identifier else { i += 1; continue }
            if tokens[i].text == "using" {
                var j = i
                while j < tokens.count, tokens[j].text != ";" { tokens[j].text = ""; j += 1 }
                if j < tokens.count { tokens[j].text = "" }
                i = j + 1
                continue
            }
            if tokens[i].text == "namespace", depth == 0 {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "GLSL has no namespaces; move the functions to file scope.",
                                         line: tokens[i].line))
            }
            i += 1
        }
    }

    /// Storage and linkage words GLSL does not have, and the namespace prefixes
    /// Metal's own library uses.
    private static func dropStorageWords(_ tokens: inout [ShaderToken]) {
        let dropped: Set<String> = ["static", "inline", "constexpr", "noinline", "extern"]
        let namespaces: Set<String> = ["metal", "precise", "fast", "simd", "std"]
        for i in tokens.indices where tokens[i].kind == .identifier {
            let text = tokens[i].text
            if dropped.contains(text) {
                emptyWithTrailingSpace(&tokens, i)
            } else if namespaces.contains(text),
                      let c1 = tokens.nextSignificant(from: i + 1), tokens[c1].text == ":",
                      let c2 = tokens.nextSignificant(from: c1 + 1), tokens[c2].text == ":" {
                tokens[i].text = ""
                tokens[c1].text = ""
                tokens[c2].text = ""
            }
        }
    }

    /// A reference parameter becomes `inout`; a pointer or a buffer reference has
    /// no place on a page and is reported.
    private static func rewriteParameters(_ tokens: inout [ShaderToken], functions: [ShaderFunction],
                                          diagnostics: inout [WebShaderDiagnostic]) {
        for fn in functions {
            for range in tokens.argumentRanges(from: fn.openParen, to: fn.closeParen) {
                var depth = 0
                var threadIndex: Int? = nil
                var ampersand: Int? = nil
                var star: Int? = nil
                var bufferWord: Int? = nil
                var constantWord: Int? = nil
                var constWord: Int? = nil
                var typeIndex: Int? = nil
                for i in range {
                    if let b = tokens[i].bracket {
                        depth += (b == "(" || b == "[" || b == "{") ? 1 : -1
                        continue
                    }
                    guard depth == 0, tokens[i].hasText else { continue }
                    let t = tokens[i]
                    if t.kind == .identifier {
                        switch t.text {
                        case "thread": threadIndex = i
                        case "constant": constantWord = i
                        case "const": constWord = i
                        case _ where WebShaderCompat.bufferAddressSpaces.contains(t.text): bufferWord = i
                        default: if typeIndex == nil { typeIndex = i }
                        }
                    } else if t.kind == .punctuation {
                        if t.text == "&", ampersand == nil { ampersand = i }
                        if t.text == "*", star == nil { star = i }
                    }
                }
                let line = tokens[range.lowerBound].line
                if star != nil {
                    diagnostics.append(.init(severity: .unsupported,
                                             message: "'\(fn.name)' takes a pointer; GLSL passes values, so pass the element or an array.",
                                             line: line))
                    continue
                }
                if let w = bufferWord {
                    diagnostics.append(.init(severity: .unsupported,
                                             message: "'\(fn.name)' takes a '\(tokens[w].text)' reference; a page has no buffers to point into.",
                                             line: line))
                    continue
                }
                if let w = threadIndex {
                    tokens[w].text = "inout"
                    if let a = ampersand { tokens[a].text = "" }
                    continue
                }
                if let w = constantWord {
                    // A constant reference reads as a value on the page.
                    emptyWithTrailingSpace(&tokens, w)
                    if let a = ampersand { tokens[a].text = "" }
                    continue
                }
                if let a = ampersand {
                    tokens[a].text = ""
                    if let c = constWord {
                        emptyWithTrailingSpace(&tokens, c)
                    } else if let t = typeIndex {
                        tokens[t].text = "inout " + tokens[t].text
                    }
                }
            }
        }
    }

    /// Outside a parameter list: a file-scope `constant` is a `const`, a local
    /// `thread` value is a plain local, and a pointer or a buffer reference is
    /// reported.
    private static func rewriteAddressSpaces(_ tokens: inout [ShaderToken], functions: [ShaderFunction],
                                             diagnostics: inout [WebShaderDiagnostic]) {
        let parameterRanges = functions.map { $0.openParen...$0.closeParen }
        func inParameters(_ i: Int) -> Bool { parameterRanges.contains { $0.contains(i) } }

        for i in tokens.indices where tokens[i].kind == .identifier && !inParameters(i) {
            let text = tokens[i].text
            if text == "constant" {
                tokens[i].text = "const"
            } else if text == "thread" {
                emptyWithTrailingSpace(&tokens, i)
                if let type = tokens.nextSignificant(from: i + 1),
                   let after = tokens.nextSignificant(from: type + 1) {
                    if tokens[after].text == "*" {
                        diagnostics.append(.init(severity: .unsupported,
                                                 message: "a pointer local has no GLSL form; index the array directly.",
                                                 line: tokens[i].line))
                    } else if tokens[after].text == "&" {
                        diagnostics.append(.init(severity: .unsupported,
                                                 message: "a reference local has no GLSL form; copy the value.",
                                                 line: tokens[i].line))
                    }
                }
            } else if WebShaderCompat.bufferAddressSpaces.contains(text) {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "'\(text)' names a buffer another stage wrote; a page has none.",
                                         line: tokens[i].line))
            }
        }
    }

    /// Renames the vector and matrix types, and reports a texture or sampler.
    private static func rewriteTypes(_ tokens: inout [ShaderToken], diagnostics: inout [WebShaderDiagnostic]) {
        var reported: Set<String> = []
        for i in tokens.indices where tokens[i].kind == .identifier && !isMemberAccess(tokens, i) {
            let text = tokens[i].text
            if let mapped = WebShaderCompat.typeNames[text] {
                tokens[i].text = mapped
            } else if WebShaderCompat.textureTypes.contains(text), reported.insert(text).inserted {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "'\(text)' is a Metal texture type; the page reads a layer through its own seam.",
                                         line: tokens[i].line))
            }
        }
    }

    /// Metal spreads a scalar over a vector it initializes (`float2 p = 0.0;`);
    /// GLSL wants the constructor, so a bare number (or its negative) that
    /// initializes a declared vector is wrapped in one, through the whole
    /// declarator list.
    private static func rewriteScalarInitializers(_ tokens: inout [ShaderToken]) {
        let vectors: Set<String> = ["vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4"]
        var i = 0
        while i < tokens.count {
            guard tokens[i].kind == .identifier, vectors.contains(tokens[i].text),
                  let name = tokens.nextSignificant(from: i + 1), tokens[name].kind == .identifier,
                  let equals = tokens.nextSignificant(from: name + 1), tokens[equals].text == "=" else { i += 1; continue }
            let type = tokens[i].text
            var cursor = equals
            while true {
                guard let value = tokens.nextSignificant(from: cursor + 1) else { break }
                var end = value
                var number = value
                var negative = false
                if tokens[value].kind == .punctuation, tokens[value].text == "-",
                   let n = tokens.nextSignificant(from: value + 1) { number = n; negative = true }
                if tokens[number].kind == .number, let after = tokens.nextSignificant(from: number + 1),
                   tokens[after].text == "," || tokens[after].text == ";" {
                    if negative {
                        tokens[value].text = type + "(-"
                        tokens[number].text += ")"
                    } else {
                        tokens[number].text = type + "(" + tokens[number].text + ")"
                    }
                    end = after
                } else {
                    // Not a bare number: skip to the end of this declarator.
                    var depth = 0
                    var j = value
                    while j < tokens.count {
                        if let b = tokens[j].bracket { depth += (b == "(" || b == "[" || b == "{") ? 1 : -1 }
                        else if depth == 0, tokens[j].kind == .punctuation, tokens[j].text == "," || tokens[j].text == ";" { break }
                        j += 1
                    }
                    end = j
                }
                if end >= tokens.count || tokens[end].text == ";" { break }
                guard let next = tokens.nextSignificant(from: end + 1), tokens[next].kind == .identifier,
                      let eq2 = tokens.nextSignificant(from: next + 1), tokens[eq2].text == "=" else { break }
                cursor = eq2
            }
            i = name + 1
        }
    }

    /// A half literal's suffix goes, and so does a long one.
    private static func rewriteNumbers(_ tokens: inout [ShaderToken]) {
        for i in tokens.indices where tokens[i].kind == .number {
            var text = tokens[i].text
            if text.hasPrefix("0x") || text.hasPrefix("0X") { continue }
            while let last = text.last, "hHlL".contains(last) { text.removeLast() }
            tokens[i].text = text
        }
    }

    /// Renames or reshapes the built-in calls, and records the constants read.
    private static func rewriteBuiltins(_ tokens: inout [ShaderToken], functions: [ShaderFunction],
                                        functionNames: Set<String>, structNames: Set<String>,
                                        helpers: inout Set<WebShaderCompat.Helper>,
                                        constants: inout Set<String>,
                                        diagnostics: inout [WebShaderDiagnostic]) {
        var reportedTextureReads: Set<String> = []
        var depth = 0
        for i in tokens.indices {
            if let b = tokens[i].bracket {
                if b == "{" { depth += 1 } else if b == "}" { depth = max(0, depth - 1) }
                continue
            }
            guard tokens[i].kind == .identifier, tokens[i].hasText else { continue }
            let name = tokens[i].text
            let line = tokens[i].line

            if isMemberAccess(tokens, i) {
                if WebShaderCompat.textureMembers.contains(name),
                   let paren = tokens.nextSignificant(from: i + 1), tokens[paren].bracket == "(",
                   reportedTextureReads.insert(name).inserted {
                    diagnostics.append(.init(severity: .unsupported,
                                             message: "'.\(name)(' reads a Metal texture; the page reads a layer through its own seam.",
                                             line: line))
                }
                continue
            }

            if WebShaderCompat.constantValues[name] != nil {
                constants.insert(name)
                continue
            }

            if name == "discard_fragment" {
                tokens[i].text = "discard"
                if let open = tokens.nextSignificant(from: i + 1), tokens[open].bracket == "(",
                   let close = tokens.matchingBracket(from: open) {
                    tokens[open].text = ""
                    tokens[close].text = ""
                }
                continue
            }

            if name == "as_type" {
                rewriteBitCast(&tokens, at: i, helpers: &helpers, diagnostics: &diagnostics)
                continue
            }

            if depth == 0, WebShaderCompat.entryPointWords.contains(name),
               let next = tokens.nextSignificant(from: i + 1), tokens[next].kind == .identifier {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "'\(name)' marks an entry point; the page's wrapper owns those, so hand it the body as a function.",
                                         line: line))
                continue
            }

            if name == "template" || name == "typename" {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "GLSL has no templates; write the function for each type it takes.",
                                         line: line))
                continue
            }
            if name == "enum_" || name == "enum" {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "GLSL has no enums; write the values as const ints.",
                                         line: line))
                continue
            }

            // A name the shader declares itself always wins over a built-in.
            guard !functionNames.contains(name), !structNames.contains(name) else { continue }
            guard let paren = tokens.nextSignificant(from: i + 1), tokens[paren].bracket == "(",
                  let close = tokens.matchingBracket(from: paren) else { continue }

            if let mapped = WebShaderCompat.renamedFunctions[name] {
                tokens[i].text = mapped
                if let helper = WebShaderCompat.Helper(rawValue: mapped) { helpers.insert(helper) }
                continue
            }

            if let reason = WebShaderCompat.unsupportedFunctions[name] {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "'\(name)' has no direct GLSL form. \(reason)",
                                         line: line))
                continue
            }

            switch name {
            case "fmod":
                tokens[i].text = WebShaderCompat.Helper.fmod.rawValue
                helpers.insert(.fmod)
            case "saturate":
                tokens[i].text = WebShaderCompat.Helper.saturate.rawValue
                helpers.insert(.saturate)
            case "fma":
                tokens[i].text = WebShaderCompat.Helper.fma.rawValue
                helpers.insert(.fma)
            case "select":
                tokens[i].text = WebShaderCompat.Helper.select.rawValue
                helpers.insert(.select)
                let arguments = tokens.argumentRanges(from: paren, to: close)
                if arguments.count == 3 {
                    rewriteRelational(&tokens, in: arguments[2], helpers: &helpers)
                }
            case "any", "all":
                let arguments = tokens.argumentRanges(from: paren, to: close)
                if arguments.count == 1 {
                    rewriteRelational(&tokens, in: arguments[0], helpers: &helpers)
                }
            default:
                break
            }
        }
    }

    /// `as_type<T>(x)` becomes the bit cast GLSL names by its target width.
    private static func rewriteBitCast(_ tokens: inout [ShaderToken], at i: Int,
                                       helpers: inout Set<WebShaderCompat.Helper>,
                                       diagnostics: inout [WebShaderDiagnostic]) {
        guard let open = tokens.nextSignificant(from: i + 1), tokens[open].text == "<",
              let type = tokens.nextSignificant(from: open + 1), tokens[type].kind == .identifier,
              let close = tokens.nextSignificant(from: type + 1), tokens[close].text == ">" else {
            diagnostics.append(.init(severity: .unsupported,
                                     message: "'as_type' without a readable target type.",
                                     line: tokens[i].line))
            return
        }
        let target = tokens[type].text
        let mapped: String
        if target.hasPrefix("u") { mapped = "floatBitsToUint" }
        else if target.hasPrefix("i") { mapped = "floatBitsToInt" }
        else if target == "float" || target.hasPrefix("vec") {
            mapped = WebShaderCompat.Helper.bitsToFloat.rawValue
            helpers.insert(.bitsToFloat)
        } else {
            diagnostics.append(.init(severity: .unsupported,
                                     message: "'as_type<\(target)>' has no GLSL bit cast.",
                                     line: tokens[i].line))
            return
        }
        tokens[i].text = mapped
        tokens[open].text = ""
        tokens[type].text = ""
        tokens[close].text = ""
    }

    /// A comparison that yields a vector of booleans is a call in GLSL. Inside a
    /// `select` condition or an `any`/`all` argument the operands may well be
    /// vectors, so the operator becomes the helper that takes either.
    private static func rewriteRelational(_ tokens: inout [ShaderToken], in range: Range<Int>,
                                          helpers: inout Set<WebShaderCompat.Helper>) {
        guard let first = tokens.nextSignificant(from: range.lowerBound), first < range.upperBound,
              let last = tokens.previousSignificant(from: range.upperBound - 1), last >= first else { return }

        // A parenthesized condition is the same condition.
        if tokens[first].bracket == "(", tokens.matchingBracket(from: first) == last {
            rewriteRelational(&tokens, in: (first + 1)..<last, helpers: &helpers)
            return
        }

        var depth = 0
        var opIndex: Int? = nil
        var count = 0
        for i in range {
            if let b = tokens[i].bracket {
                depth += (b == "(" || b == "[" || b == "{") ? 1 : -1
                continue
            }
            guard depth == 0, tokens[i].kind == .punctuation, tokens[i].hasText else { continue }
            let t = tokens[i].text
            if t == "&&" || t == "||" || t == "?" || t == ":" || t == "!" { return }
            if WebShaderCompat.relationalHelper(for: t) != nil { count += 1; opIndex = i }
        }
        guard count == 1, let op = opIndex, first < op, op < last,
              let helper = WebShaderCompat.relationalHelper(for: tokens[op].text) else { return }

        tokens[first].text = helper.rawValue + "(" + tokens[first].text
        tokens[op].text = ","
        if op > 0, tokens[op - 1].kind == .whitespace, !tokens[op - 1].text.contains("\n") {
            tokens[op - 1].text = ""
        }
        tokens[last].text += ")"
        helpers.insert(helper)
    }

    /// A brace initializer becomes the constructor GLSL spells it as: an array
    /// with its type and size, a struct or vector with its name.
    private static func rewriteAggregates(_ tokens: inout [ShaderToken], functions: [ShaderFunction],
                                          structNames: Set<String>, diagnostics: inout [WebShaderDiagnostic]) {
        for i in tokens.indices where tokens[i].bracket == "{" {
            guard let close = tokens.matchingBracket(from: i),
                  let prevIndex = tokens.previousSignificant(from: i - 1) else { continue }
            let prev = tokens[prevIndex]

            if prev.kind == .punctuation, prev.text == "=" {
                guard let beforeEquals = tokens.previousSignificant(from: prevIndex - 1) else { continue }
                var nameIndex = beforeEquals
                var arraySize: String? = nil
                if tokens[beforeEquals].bracket == "]", let open = openingBracket(tokens, closing: beforeEquals) {
                    arraySize = ShaderLexer.join(Array(tokens[(open + 1)..<beforeEquals])).trimmingCharacters(in: .whitespaces)
                    guard let n = tokens.previousSignificant(from: open - 1) else { continue }
                    nameIndex = n
                }
                guard tokens[nameIndex].kind == .identifier,
                      let typeIndex = tokens.previousSignificant(from: nameIndex - 1),
                      tokens[typeIndex].kind == .identifier else {
                    diagnostics.append(.init(severity: .note,
                                             message: "an initializer list whose type could not be read was left as written.",
                                             line: tokens[i].line))
                    continue
                }
                let type = tokens[typeIndex].text
                if let size = arraySize {
                    tokens[i].text = "\(type)[\(size)]("
                    tokens[close].text = ")"
                    rewriteNestedBraces(&tokens, from: i, to: close, element: type)
                } else if structNames.contains(type) || isConstructibleType(type) {
                    tokens[i].text = "\(type)("
                    tokens[close].text = ")"
                    rewriteNestedBraces(&tokens, from: i, to: close, element: nil)
                } else {
                    diagnostics.append(.init(severity: .note,
                                             message: "an initializer list for '\(type)' was left as written; GLSL wants a constructor.",
                                             line: tokens[i].line))
                    continue
                }
                dropTrailingComma(&tokens, before: close)
                continue
            }

            if prev.kind == .identifier, structNames.contains(prev.text) || isConstructibleType(prev.text),
               !isStructDeclaration(tokens, nameIndex: prevIndex) {
                tokens[i].text = "("
                tokens[close].text = ")"
                rewriteNestedBraces(&tokens, from: i, to: close, element: nil)
                dropTrailingComma(&tokens, before: close)
                continue
            }

            if prev.kind == .identifier, prev.text == "return",
               let fn = functions.first(where: { ($0.openBrace ?? -1) < i && i < ($0.closeBrace ?? -1) }),
               let typeIndex = tokens.previousSignificant(from: fn.nameIndex - 1) {
                tokens[i].text = "\(tokens[typeIndex].text)("
                tokens[close].text = ")"
                rewriteNestedBraces(&tokens, from: i, to: close, element: nil)
                dropTrailingComma(&tokens, before: close)
            }
        }
    }

    /// Braces nested one level inside an initializer: an array's elements, or a
    /// struct's members that are themselves aggregates.
    private static func rewriteNestedBraces(_ tokens: inout [ShaderToken], from open: Int, to close: Int, element: String?) {
        var depth = 0
        var i = open + 1
        while i < close {
            if let b = tokens[i].bracket {
                if b == "{" {
                    if depth == 0, let inner = tokens.matchingBracket(from: i) {
                        tokens[i].text = (element ?? "") + "("
                        tokens[inner].text = ")"
                        dropTrailingComma(&tokens, before: inner)
                    }
                    depth += 1
                } else if b == "}" {
                    depth -= 1
                }
            }
            i += 1
        }
    }

    private static func dropTrailingComma(_ tokens: inout [ShaderToken], before close: Int) {
        if let last = tokens.previousSignificant(from: close - 1), tokens[last].kind == .punctuation, tokens[last].text == "," {
            tokens[last].text = ""
        }
    }

    /// An attribute in double brackets belongs to an entry point or a binding,
    /// which the page's wrapper owns.
    private static func reportAttributes(_ tokens: inout [ShaderToken], diagnostics: inout [WebShaderDiagnostic]) {
        for i in tokens.indices where tokens[i].bracket == "[" {
            guard i + 1 < tokens.count, tokens[i + 1].bracket == "[" else { continue }
            guard let name = tokens.nextSignificant(from: i + 2), tokens[name].kind == .identifier else { continue }
            diagnostics.append(.init(severity: .unsupported,
                                     message: "'[[\(tokens[name].text)]]' is an attribute for the Metal pipeline; the page's wrapper binds what the body needs.",
                                     line: tokens[i].line))
        }
    }

    // MARK: - Helpers

    private static func isMemberAccess(_ tokens: [ShaderToken], _ i: Int) -> Bool {
        guard i > 0, let p = tokens.previousSignificant(from: i - 1) else { return false }
        return tokens[p].kind == .punctuation && tokens[p].text == "."
    }

    private static func emptyWithTrailingSpace(_ tokens: inout [ShaderToken], _ i: Int) {
        tokens[i].text = ""
        if i + 1 < tokens.count, tokens[i + 1].kind == .whitespace, !tokens[i + 1].text.contains("\n") {
            tokens[i + 1].text = ""
        }
    }

    /// The `[` that a `]` closes, walking back.
    private static func openingBracket(_ tokens: [ShaderToken], closing: Int) -> Int? {
        var depth = 0
        var i = closing
        while i >= 0 {
            if let b = tokens[i].bracket {
                if b == "]" { depth += 1 }
                else if b == "[" {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i -= 1
        }
        return nil
    }

    /// Whether the identifier at `nameIndex` is the name in `struct Name {`, whose
    /// braces are a body and not a construction.
    private static func isStructDeclaration(_ tokens: [ShaderToken], nameIndex: Int) -> Bool {
        guard let before = tokens.previousSignificant(from: nameIndex - 1) else { return false }
        return tokens[before].kind == .identifier && tokens[before].text == "struct"
    }

    /// A GLSL type a brace initializer can be spelled as a constructor of.
    private static func isConstructibleType(_ name: String) -> Bool {
        if ["float", "int", "uint", "bool"].contains(name) { return true }
        for prefix in ["vec", "ivec", "uvec", "bvec", "mat"] where name.hasPrefix(prefix) { return true }
        return false
    }
}
