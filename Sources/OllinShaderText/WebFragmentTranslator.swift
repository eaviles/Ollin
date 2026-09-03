import Foundation

/// A Metal fragment entry point carried to the page as a whole GLSL ES 3.00
/// fragment shader: the entry with every helper, struct, constant, and macro it
/// reaches, over the page's own bindings.
package struct WebFragmentTranslation {
    /// The complete fragment shader, ready to compile.
    package var glsl: String
    /// The texture uniforms, in the order the entry bound them (`[[texture(n)]]`).
    package var textures: [String]
    /// The name of the params array the entry reads, `nil` when it reads none.
    package var paramsName: String?
    package var diagnostics: [WebShaderDiagnostic]

    package var isClean: Bool { !diagnostics.contains { $0.severity == .unsupported } }
    package var unsupported: [WebShaderDiagnostic] { diagnostics.filter { $0.severity == .unsupported } }
}

/// Rewrites one `fragment` entry point of the framework's shader text into a
/// page shader. The Metal side of an effect pass has one shape, a fullscreen
/// triangle's `uv` in, one or more `texture2d<float>` inputs, a `sampler`, and a
/// `constant float4 *params` array; the page binds the same things its own way,
/// as an `in vec2 uv`, `sampler2D` uniforms, and a `vec4` uniform array. The
/// entry keeps its name and becomes an ordinary function a generated `main`
/// calls, so its body crosses through the same token rewriter every helper
/// does; a texture read becomes a call to a helper that turns the coordinate
/// over, since the page keeps its layers bottom-up where Metal keeps them
/// top-down, and a read at a pixel position turns the same way.
package enum WebFragmentTranslator {

    /// The row count the params array is declared with, as a macro the page can
    /// size per fragment.
    package static let paramRowsMacro = "OLLIN_PARAM_ROWS"

    /// The names of every `fragment` entry point the text defines.
    package static func entryPoints(in metalText: String) -> [String] {
        let tokens = ShaderLexer.tokenize(metalText)
        let functions = ShaderScan.functions(in: tokens)
        return functions.filter { fn in
            fn.isDefinition && isFragment(tokens, fn)
        }.map(\.name)
    }

    /// Translate the entry point `name` out of `metalText`, the framework's
    /// segments concatenated. `paramRows` is how many `float4` rows the page will
    /// bind; the array is declared that long.
    package static func translate(entry name: String, in metalText: String,
                                  paramRows: Int) -> WebFragmentTranslation {
        var tokens = ShaderLexer.tokenize(metalText)
        var diagnostics: [WebShaderDiagnostic] = []
        let functions = ShaderScan.functions(in: tokens)
        guard let entry = functions.first(where: { $0.name == name && $0.isDefinition }) else {
            diagnostics.append(.init(severity: .unsupported, message: "no fragment named '\(name)' is defined."))
            return WebFragmentTranslation(glsl: "", textures: [], paramsName: nil, diagnostics: diagnostics)
        }

        // The entry's bindings, read off its parameter list.
        let bindings = parseEntryParameters(tokens, entry, diagnostics: &diagnostics)

        // Everything the entry reaches, by name, over the file-scope declarations.
        let declarations = topLevelDeclarations(tokens, functions: functions)
        let reachable = reach(from: entry, in: declarations, tokens: tokens,
                              excludingStruct: bindings.stageInStruct)
        if let stageIn = bindings.stageInStruct,
           reachable.contains(where: { decl in
               if case .function(let fn) = decl.kind, fn.nameIndex != entry.nameIndex {
                   return mentions(tokens, decl.range, stageIn)
               }
               return false
           }) {
            diagnostics.append(.init(severity: .unsupported,
                                     message: "a helper takes the stage-in struct '\(stageIn)'; the page has no such value to pass.",
                                     line: tokens[entry.nameIndex].line))
        }

        // The rewrites that know what a texture, a sampler, and a params array are.
        rewriteEntry(&tokens, entry, bindings, diagnostics: &diagnostics)
        var samplerNames = bindings.samplers
        var pointerNames: Set<String> = []
        rewriteHelperParameters(&tokens, functions: functions, reachable: reachable,
                                samplerNames: &samplerNames, pointerNames: &pointerNames)
        rewriteTextureReads(&tokens, reachable: reachable, diagnostics: &diagnostics)
        rewriteSamplerUses(&tokens, functions: functions, reachable: reachable, names: samplerNames)
        if let params = bindings.params {
            rewriteParamsPointers(&tokens, reachable: reachable, params: params, pointerNames: pointerNames)
        }

        // The reachable declarations, in the order the framework wrote them, through
        // the general rewriter.
        var pieces: [String] = []
        for decl in reachable {
            pieces.append(ShaderLexer.join(Array(tokens[decl.range])))
        }
        let translation = WebShaderTranslator.translate(pieces.joined(separator: "\n\n"))
        diagnostics.append(contentsOf: translation.diagnostics)

        var out = WebShaderCompat.preamble
        let support = translation.support
        if !support.isEmpty { out += support + "\n\n" }
        out += "#define \(paramRowsMacro) \(max(1, paramRows))\n"
        out += "in vec2 uv;\n"
        out += "uniform vec2 ollin_viewport;\n"
        for texture in bindings.textures { out += "uniform sampler2D \(texture);\n" }
        if let params = bindings.params { out += "uniform vec4 \(params)[\(paramRowsMacro)];\n" }
        out += readHelpers + "\n"
        out += translation.body + "\n\n"
        out += "out vec4 fragColor;\nvoid main() { fragColor = \(name)(); }\n"
        return WebFragmentTranslation(glsl: out, textures: bindings.textures,
                                      paramsName: bindings.params, diagnostics: diagnostics)
    }

    /// The page's readers: a layer read at a Metal coordinate, which turns over
    /// because the page keeps a layer bottom-up, and the fragment's own position
    /// in Metal's pixel space.
    package static let readHelpers = """
    vec4 ollin_tex(sampler2D t, vec2 q) { return texture(t, vec2(q.x, 1.0 - q.y)); }
    vec4 ollin_texLod(sampler2D t, vec2 q, float l) { return textureLod(t, vec2(q.x, 1.0 - q.y), l); }
    vec4 ollin_texLod(sampler2D t, vec2 q, int l) { return textureLod(t, vec2(q.x, 1.0 - q.y), float(l)); }
    vec4 ollin_fetch(sampler2D t, ivec2 c) { ivec2 s = textureSize(t, 0); return texelFetch(t, ivec2(c.x, s.y - 1 - c.y), 0); }
    vec4 ollin_fetch(sampler2D t, uvec2 c) { return ollin_fetch(t, ivec2(c)); }
    uint ollin_width(sampler2D t) { return uint(textureSize(t, 0).x); }
    uint ollin_height(sampler2D t) { return uint(textureSize(t, 0).y); }
    #define ollin_position vec4(gl_FragCoord.x, ollin_viewport.y - gl_FragCoord.y, gl_FragCoord.z, gl_FragCoord.w)
    """

    // MARK: - The entry's parameters

    struct EntryBindings {
        var stageInName: String?
        var stageInStruct: String?
        var textures: [String] = []
        var samplers: Set<String> = []
        var params: String?
    }

    private static func isFragment(_ tokens: [ShaderToken], _ fn: ShaderFunction) -> Bool {
        guard let type = tokens.previousSignificant(from: fn.nameIndex - 1),
              let word = tokens.previousSignificant(from: type - 1) else { return false }
        return tokens[word].kind == .identifier && tokens[word].text == "fragment"
    }

    private static func parseEntryParameters(_ tokens: [ShaderToken], _ fn: ShaderFunction,
                                             diagnostics: inout [WebShaderDiagnostic]) -> EntryBindings {
        var bindings = EntryBindings()
        var textures: [(Int, String)] = []
        for range in tokens.argumentRanges(from: fn.openParen, to: fn.closeParen) {
            let significant = range.filter { tokens[$0].hasText }
            guard !significant.isEmpty else { continue }
            let line = tokens[significant[0]].line
            // The attribute: `[[ word ( n ) ]]`, the name just ahead of it.
            guard let attrOpen = significant.firstIndex(where: { tokens[$0].bracket == "[" }),
                  attrOpen + 2 < significant.count,
                  tokens[significant[attrOpen + 1]].bracket == "[",
                  tokens[significant[attrOpen + 2]].kind == .identifier else {
                diagnostics.append(.init(severity: .unsupported,
                                         message: "a parameter of '\(fn.name)' carries no binding attribute; the page binds by attribute.",
                                         line: line))
                continue
            }
            let attribute = tokens[significant[attrOpen + 2]].text
            var slot = 0
            if attrOpen + 4 < significant.count, tokens[significant[attrOpen + 3]].bracket == "(",
               tokens[significant[attrOpen + 4]].kind == .number {
                slot = Int(tokens[significant[attrOpen + 4]].text) ?? 0
            }
            let nameIndex = significant[attrOpen - 1]
            let name = tokens[nameIndex].text
            let words = significant[..<(attrOpen - 1)].map { tokens[$0].text }
            switch attribute {
            case "stage_in":
                bindings.stageInName = name
                bindings.stageInStruct = words.first
            case "texture":
                if words.first == "texture2d" {
                    textures.append((slot, name))
                } else {
                    diagnostics.append(.init(severity: .unsupported,
                                             message: "'\(fn.name)' reads a '\(words.first ?? "?")'; the page binds flat layers only.",
                                             line: line))
                }
            case "sampler":
                bindings.samplers.insert(name)
            case "buffer":
                if words.contains("float4"), words.contains("*") {
                    bindings.params = name
                } else {
                    diagnostics.append(.init(severity: .unsupported,
                                             message: "'\(fn.name)' binds a '\(words.joined(separator: " "))' at buffer \(slot); the page binds a float4 array only.",
                                             line: line))
                }
            default:
                diagnostics.append(.init(severity: .unsupported,
                                         message: "'[[\(attribute)]]' on a parameter of '\(fn.name)' has no page binding.",
                                         line: line))
            }
        }
        textures.sort { $0.0 < $1.0 }
        for (i, t) in textures.enumerated() where t.0 != i {
            diagnostics.append(.init(severity: .unsupported,
                                     message: "'\(fn.name)' binds texture \(t.0) with a gap before it; the page binds textures in order.",
                                     line: tokens[fn.nameIndex].line))
        }
        bindings.textures = textures.map(\.1)
        return bindings
    }

    // MARK: - The declarations and what reaches what

    struct Declaration {
        enum Kind {
            case function(ShaderFunction)
            case structure(String)
            case macro(String)
            case global(String)
            case other
        }
        var kind: Kind
        var range: Range<Int>
        var names: Set<String>

        var name: String? {
            switch kind {
            case .function(let fn): return fn.name
            case .structure(let n), .macro(let n), .global(let n): return n
            case .other: return nil
            }
        }
    }

    /// The file-scope declarations, each with the token range it spans (leading
    /// layout and comments included) and the names it mentions.
    private static func topLevelDeclarations(_ tokens: [ShaderToken],
                                             functions: [ShaderFunction]) -> [Declaration] {
        var declarations: [Declaration] = []
        var byNameIndex: [Int: ShaderFunction] = [:]
        for fn in functions { byNameIndex[fn.nameIndex] = fn }

        var start = 0
        var i = 0
        func close(_ end: Int) {
            let range = start..<(end + 1)
            declarations.append(classify(tokens, range: range, functions: byNameIndex))
            start = end + 1
        }
        while i < tokens.count {
            let t = tokens[i]
            if t.kind == .directive {
                close(i)
                i += 1
                continue
            }
            if t.bracket == "{" {
                guard let closeBrace = tokens.matchingBracket(from: i) else { break }
                if let after = tokens.nextSignificant(from: closeBrace + 1), tokens[after].text == ";" {
                    close(after)
                    i = after + 1
                } else {
                    close(closeBrace)
                    i = closeBrace + 1
                }
                continue
            }
            if t.kind == .punctuation, t.text == ";" {
                close(i)
                i += 1
                continue
            }
            i += 1
        }
        return declarations
    }

    private static func classify(_ tokens: [ShaderToken], range: Range<Int>,
                                 functions: [Int: ShaderFunction]) -> Declaration {
        var mentioned: Set<String> = []
        var kind: Declaration.Kind = .other
        for i in range {
            let t = tokens[i]
            if t.kind == .directive {
                let body = String(t.text.dropFirst())
                let sub = ShaderLexer.tokenize(body)
                var isDefine = false
                for (j, s) in sub.enumerated() where s.kind == .identifier {
                    if j == 0 || (isDefine == false && s.text == "define" && mentioned.isEmpty) {
                        if s.text == "define" { isDefine = true; continue }
                    }
                    if isDefine, case .other = kind {
                        kind = .macro(s.text)
                        continue
                    }
                    mentioned.insert(s.text)
                }
                continue
            }
            if t.kind == .identifier { mentioned.insert(t.text) }
            if let fn = functions[i], case .other = kind { kind = .function(fn) }
        }
        if case .other = kind {
            let significant = range.filter { tokens[$0].hasText }
            if let s = significant.first, tokens[s].text == "struct",
               significant.count > 1, tokens[significant[1]].kind == .identifier {
                kind = .structure(tokens[significant[1]].text)
            } else if let s = significant.first, tokens[s].text != "using" {
                // A global: its name sits just ahead of the first `=`, `[`, `(`, or `;`.
                var name: String? = nil
                var previous: Int? = nil
                for i in significant {
                    let text = tokens[i].text
                    if text == "=" || text == ";" || tokens[i].bracket == "[" || tokens[i].bracket == "(" {
                        if let p = previous, tokens[p].kind == .identifier { name = tokens[p].text }
                        break
                    }
                    previous = i
                }
                if let name { kind = .global(name) }
            }
        }
        if let own = Declaration(kind: kind, range: range, names: []).name { mentioned.remove(own) }
        return Declaration(kind: kind, range: range, names: mentioned)
    }

    /// The declarations the entry reaches, in file order: the entry itself, every
    /// function it calls (all overloads of a name), and every struct, constant, and
    /// macro any of them names. The entry's own parameter list is not read, since
    /// the page rewrites it whole.
    private static func reach(from entry: ShaderFunction, in declarations: [Declaration],
                              tokens: [ShaderToken], excludingStruct: String?) -> [Declaration] {
        var byName: [String: [Int]] = [:]
        for (i, d) in declarations.enumerated() {
            if let n = d.name { byName[n, default: []].append(i) }
        }
        var included = Set<Int>()
        var queue: [Int] = []
        guard let entryIndex = declarations.firstIndex(where: {
            if case .function(let fn) = $0.kind { return fn.nameIndex == entry.nameIndex }
            return false
        }) else { return [] }
        included.insert(entryIndex)
        // The entry mentions: its return type, and its body.
        var entryNames: Set<String> = []
        if let body = entry.openBrace, let close = entry.closeBrace {
            for i in body...close where tokens[i].kind == .identifier { entryNames.insert(tokens[i].text) }
        }
        if let type = tokens.previousSignificant(from: entry.nameIndex - 1) { entryNames.insert(tokens[type].text) }
        for n in entryNames { for j in byName[n] ?? [] where !included.contains(j) { included.insert(j); queue.append(j) } }
        while let next = queue.popLast() {
            for n in declarations[next].names {
                for j in byName[n] ?? [] where !included.contains(j) {
                    included.insert(j)
                    queue.append(j)
                }
            }
        }
        if let excluded = excludingStruct {
            for j in byName[excluded] ?? [] {
                if case .structure = declarations[j].kind { included.remove(j) }
            }
        }
        return included.sorted().map { declarations[$0] }
    }

    private static func mentions(_ tokens: [ShaderToken], _ range: Range<Int>, _ name: String) -> Bool {
        range.contains { tokens[$0].kind == .identifier && tokens[$0].text == name }
    }

    // MARK: - The rewrites

    /// The entry loses its `fragment` word and its whole parameter list, and its
    /// stage-in reads become the page's varying and position.
    private static func rewriteEntry(_ tokens: inout [ShaderToken], _ fn: ShaderFunction,
                                     _ bindings: EntryBindings,
                                     diagnostics: inout [WebShaderDiagnostic]) {
        if let type = tokens.previousSignificant(from: fn.nameIndex - 1),
           let word = tokens.previousSignificant(from: type - 1),
           tokens[word].text == "fragment" {
            tokens[word].text = ""
            if word + 1 < tokens.count, tokens[word + 1].kind == .whitespace, !tokens[word + 1].text.contains("\n") {
                tokens[word + 1].text = ""
            }
        }
        for i in (fn.openParen + 1)..<fn.closeParen { tokens[i].text = "" }
        guard let stageIn = bindings.stageInName, let open = fn.openBrace, let close = fn.closeBrace else { return }
        for i in open...close where tokens[i].kind == .identifier && tokens[i].text == stageIn && tokens[i].hasText {
            guard let dot = tokens.nextSignificant(from: i + 1), tokens[dot].text == ".",
                  let member = tokens.nextSignificant(from: dot + 1), tokens[member].kind == .identifier else { continue }
            switch tokens[member].text {
            case "uv":
                tokens[i].text = ""
                tokens[dot].text = ""
            case "position":
                tokens[i].text = ""
                tokens[dot].text = ""
                tokens[member].text = "ollin_position"
            default:
                diagnostics.append(.init(severity: .unsupported,
                                         message: "the fragment reads '\(stageIn).\(tokens[member].text)', which the page's vertex stage does not carry.",
                                         line: tokens[i].line))
            }
        }
    }

    /// A helper's texture parameter becomes a `sampler2D`, its sampler parameter
    /// a placeholder int (the page's textures carry their own sampling), and a
    /// params pointer the array the page declares.
    private static func rewriteHelperParameters(_ tokens: inout [ShaderToken], functions: [ShaderFunction],
                                                reachable: [Declaration], samplerNames: inout Set<String>,
                                                pointerNames: inout Set<String>) {
        let reachableNames = Set(reachable.compactMap { decl -> Int? in
            if case .function(let fn) = decl.kind { return fn.nameIndex }
            return nil
        })
        for fn in functions where reachableNames.contains(fn.nameIndex) {
            for range in tokens.argumentRanges(from: fn.openParen, to: fn.closeParen) {
                let significant = range.filter { tokens[$0].hasText }
                guard let first = significant.first else { continue }
                var words = significant.map { tokens[$0].text }
                // `texture2d < float > name`
                if let t = significant.firstIndex(where: { tokens[$0].text == "texture2d" }),
                   t + 3 < significant.count, tokens[significant[t + 1]].text == "<",
                   tokens[significant[t + 3]].text == ">" {
                    tokens[significant[t]].text = "sampler2D"
                    tokens[significant[t + 1]].text = ""
                    tokens[significant[t + 2]].text = ""
                    tokens[significant[t + 3]].text = ""
                    continue
                }
                // `sampler name`
                if tokens[first].text == "sampler", significant.count >= 2,
                   tokens[significant[1]].kind == .identifier {
                    tokens[first].text = "int"
                    samplerNames.insert(tokens[significant[1]].text)
                    continue
                }
                // `constant float4 *name`: a walk into the params array, carried
                // as an offset into the page's uniform array.
                if let c = words.firstIndex(of: "constant"), let f = words.firstIndex(of: "float4"),
                   let star = words.firstIndex(of: "*"), star + 1 < significant.count,
                   tokens[significant[star + 1]].kind == .identifier {
                    tokens[significant[c]].text = ""
                    tokens[significant[f]].text = "int"
                    tokens[significant[star]].text = ""
                    pointerNames.insert(tokens[significant[star + 1]].text)
                    words = []
                    continue
                }
            }
        }
    }

    /// `t.sample(s, q)` becomes `ollin_tex(t, q)`, a `level(n)` read the LOD form,
    /// `t.read(c)` a fetch, and the size queries their helpers, inside every
    /// reachable declaration and inside the macros they use.
    private static func rewriteTextureReads(_ tokens: inout [ShaderToken], reachable: [Declaration],
                                            diagnostics: inout [WebShaderDiagnostic]) {
        for decl in reachable {
            for i in decl.range where tokens[i].kind == .directive {
                let text = tokens[i].text
                guard text.hasPrefix("#") else { continue }
                var sub = ShaderLexer.tokenize(String(text.dropFirst()))
                rewriteTextureReads(in: &sub, range: 0..<sub.count, diagnostics: &diagnostics)
                tokens[i].text = "#" + ShaderLexer.join(sub)
            }
            rewriteTextureReads(in: &tokens, range: decl.range, diagnostics: &diagnostics)
        }
    }

    private static let textureMembers: Set<String> = ["sample", "read", "get_width", "get_height"]

    private static func rewriteTextureReads(in tokens: inout [ShaderToken], range: Range<Int>,
                                            diagnostics: inout [WebShaderDiagnostic]) {
        for i in range where tokens[i].kind == .identifier && tokens[i].hasText {
            guard let dot = tokens.nextSignificant(from: i + 1), dot < range.upperBound, tokens[dot].text == ".",
                  let member = tokens.nextSignificant(from: dot + 1), member < range.upperBound,
                  tokens[member].kind == .identifier, textureMembers.contains(tokens[member].text),
                  let paren = tokens.nextSignificant(from: member + 1), tokens[paren].bracket == "(",
                  let close = tokens.matchingBracket(from: paren) else { continue }
            let receiver = tokens[i].text
            let line = tokens[i].line
            let arguments = tokens.argumentRanges(from: paren, to: close)
            func drop(_ argument: Range<Int>, comma: Bool) {
                for k in argument { tokens[k].text = "" }
                if comma, let next = tokens.nextSignificant(from: argument.upperBound), tokens[next].text == "," {
                    tokens[next].text = ""
                }
            }
            switch tokens[member].text {
            case "sample":
                guard arguments.count == 2 || arguments.count == 3 else {
                    diagnostics.append(.init(severity: .unsupported,
                                             message: "'\(receiver).sample' takes \(arguments.count) arguments; the page reads a layer at a coordinate, with or without a level.",
                                             line: line))
                    continue
                }
                if arguments.count == 3 {
                    guard let word = tokens.nextSignificant(from: arguments[2].lowerBound),
                          tokens[word].text == "level" else {
                        diagnostics.append(.init(severity: .unsupported,
                                                 message: "'\(receiver).sample' takes a gradient or bias; the page reads a layer at a level only.",
                                                 line: line))
                        continue
                    }
                    tokens[word].text = ""
                    tokens[i].text = "ollin_texLod"
                } else {
                    tokens[i].text = "ollin_tex"
                }
                tokens[dot].text = ""
                tokens[member].text = ""
                tokens[paren].text = "(" + receiver + ", "
                drop(arguments[0], comma: true)
            case "read":
                guard arguments.count == 1 || arguments.count == 2 else { continue }
                tokens[i].text = "ollin_fetch"
                tokens[dot].text = ""
                tokens[member].text = ""
                tokens[paren].text = "(" + receiver + ", "
                if arguments.count == 2 {
                    if let comma = tokens.previousSignificant(from: arguments[1].lowerBound - 1), tokens[comma].text == "," {
                        tokens[comma].text = ""
                    }
                    for k in arguments[1] { tokens[k].text = "" }
                }
            case "get_width", "get_height":
                tokens[i].text = tokens[member].text == "get_width" ? "ollin_width" : "ollin_height"
                tokens[dot].text = ""
                tokens[member].text = ""
                tokens[paren].text = "(" + receiver
            default:
                continue
            }
        }
    }

    /// Metal walks the params array through pointers (`constant float4 *basis =
    /// params + 3;` then `basis[i]`, or a helper taking `constant float4 *rows`);
    /// GLSL has no pointers, so each becomes an offset: the local an `int`, the
    /// bare array name in arithmetic `0`, and a subscript on an offset a read of
    /// the uniform array at the offset plus the index.
    private static func rewriteParamsPointers(_ tokens: inout [ShaderToken], reachable: [Declaration],
                                              params: String, pointerNames: Set<String>) {
        var names = pointerNames
        // Locals declared as pointers, found first so their uses can be rewritten.
        for decl in reachable {
            for i in decl.range where tokens[i].kind == .identifier && tokens[i].text == "constant" {
                guard let type = tokens.nextSignificant(from: i + 1), type < decl.range.upperBound,
                      tokens[type].text == "float4",
                      let star = tokens.nextSignificant(from: type + 1), tokens[star].text == "*",
                      let name = tokens.nextSignificant(from: star + 1), tokens[name].kind == .identifier,
                      let after = tokens.nextSignificant(from: name + 1), tokens[after].text == "=" else { continue }
                tokens[i].text = ""
                if i + 1 < tokens.count, tokens[i + 1].kind == .whitespace, !tokens[i + 1].text.contains("\n") { tokens[i + 1].text = "" }
                tokens[type].text = "int"
                tokens[star].text = ""
                names.insert(tokens[name].text)
            }
        }
        guard !names.isEmpty else { return }
        for decl in reachable {
            for i in decl.range where tokens[i].kind == .identifier && tokens[i].hasText {
                if let prev = tokens.previousSignificant(from: i - 1), tokens[prev].text == "." { continue }
                let name = tokens[i].text
                let next = tokens.nextSignificant(from: i + 1)
                let indexed = next.map { tokens[$0].bracket == "[" } ?? false
                if names.contains(name) {
                    // A declaration keeps its name; a read through it becomes a
                    // read of the array at the offset.
                    if let p = tokens.previousSignificant(from: i - 1), tokens[p].text == "int" { continue }
                    if indexed, let open = next {
                        tokens[i].text = params
                        tokens[open].text = "[" + name + " + "
                    }
                } else if name == params, !indexed {
                    // The array itself in arithmetic, or handed to a helper: offset 0.
                    if let p = tokens.previousSignificant(from: i - 1), tokens[p].text == "vec4" || tokens[p].text == "float4" { continue }
                    tokens[i].text = "0"
                }
            }
        }
    }

    /// A sampler passed along to a helper becomes the placeholder `0`, since the
    /// helper's parameter became an int.
    private static func rewriteSamplerUses(_ tokens: inout [ShaderToken], functions: [ShaderFunction],
                                           reachable: [Declaration], names: Set<String>) {
        guard !names.isEmpty else { return }
        var parameterRanges: [Range<Int>] = []
        for fn in functions { parameterRanges.append(fn.openParen..<(fn.closeParen + 1)) }
        for decl in reachable {
            for i in decl.range where tokens[i].kind == .identifier && tokens[i].hasText && names.contains(tokens[i].text) {
                if parameterRanges.contains(where: { $0.contains(i) }) { continue }
                // A member access on it, or a declaration of it, is not a use.
                if let prev = tokens.previousSignificant(from: i - 1), tokens[prev].text == "." { continue }
                tokens[i].text = "0"
            }
            for i in decl.range where tokens[i].kind == .directive {
                var sub = ShaderLexer.tokenize(String(tokens[i].text.dropFirst()))
                for k in sub.indices where sub[k].kind == .identifier && names.contains(sub[k].text) {
                    if let prev = sub.previousSignificant(from: k - 1), sub[prev].text == "." { continue }
                    sub[k].text = "0"
                }
                tokens[i].text = "#" + ShaderLexer.join(sub)
            }
        }
    }
}
