import Foundation

/// Turns a pasted web fragment shader into one Ollin can run.
///
/// The shape it reads is the common one: a `mainImage(fragColor, fragCoord)`
/// entry point over a set of `i`-prefixed values the site supplies each frame.
/// Ollin's own contract is `shade(uv, info)`, so the work is a rename, a flip of
/// the vertical axis, and a mapping of each supplied value onto `ShaderInfo`.
///
/// Whatever cannot be carried over is written into the emitted file as a comment,
/// never dropped in silence.
public enum ShaderImport {

    /// Which Ollin effect the shader becomes, decided by how many inputs it reads.
    /// This is the same rule the user-shader path already uses.
    public enum Routing: Sendable, Equatable {
        case generator
        case filter
        case combine
    }

    public struct Result: Sendable {
        /// The `.metal` file body: the helpers, then the translated shader, then
        /// the `shade` entry point.
        public var metalSource: String
        public var routing: Routing
        public var diagnostics: [GLSLDiagnostic]

        /// Whether anything needs a person before the shader will compile.
        public var needsAttention: Bool {
            diagnostics.contains { $0.severity == .unsupported }
        }
    }

    /// Where the shader came from, recorded in the emitted file. A pasted shader
    /// carries its author's terms, and the header is where those stay attached.
    public struct Provenance: Sendable {
        public var title: String?
        public var author: String?
        public var url: String?

        public init(title: String? = nil, author: String? = nil, url: String? = nil) {
            self.title = title
            self.author = author
            self.url = url
        }
    }

    static let channelNames = ["iChannel0", "iChannel1", "iChannel2", "iChannel3"]

    // MARK: - Entry point

    public static func translate(glsl: String, provenance: Provenance = Provenance()) -> Result {
        let translation = GLSLTranslator.translate(glsl)
        var diagnostics = translation.diagnostics
        var tokens = translation.tokens

        let entry = findEntryPoint(in: tokens, diagnostics: &diagnostics)
        if case .plainMain(let mainIndex) = entry {
            reshapePlainMain(&tokens, mainIndex: mainIndex, diagnostics: &diagnostics)
        }

        let channels = channelsUsed(in: tokens)
        let routing = routingFor(channels: channels, diagnostics: &diagnostics)

        rewriteChannelSampling(&tokens, channels: channels, diagnostics: &diagnostics)
        rewriteSuppliedValues(&tokens, diagnostics: &diagnostics)
        reportLeftoverInputs(in: tokens, diagnostics: &diagnostics)

        let functions = GLSLScan.functions(in: tokens)
        let needsInfo = functionsNeedingInfo(in: tokens, functions: functions)
        threadInfo(&tokens, functions: functions, needing: needsInfo)

        if entry == .none {
            diagnostics.append(.init(
                severity: .unsupported,
                message: "No entry point found. The shader needs a 'mainImage(out vec4, in vec2)' "
                    + "or a 'main()'. Paste only the image pass, not a whole page.",
                line: 0))
        }

        let source = assemble(
            body: GLSLLexer.join(tokens),
            helpers: translation.helpers,
            routing: routing,
            entryNeedsInfo: needsInfo.contains("mainImage"),
            usesMouse: mentions("iMouse", in: glsl),
            diagnostics: diagnostics,
            provenance: provenance)

        return Result(metalSource: source, routing: routing, diagnostics: diagnostics)
    }

    // MARK: - Entry point

    enum EntryPoint: Equatable {
        case mainImage
        case plainMain(Int)
        case none
    }

    static func findEntryPoint(in tokens: [GLSLToken], diagnostics: inout [GLSLDiagnostic]) -> EntryPoint {
        let functions = GLSLScan.functions(in: tokens)
        if functions.contains(where: { $0.name == "mainImage" && $0.isDefinition }) { return .mainImage }
        if let main = functions.first(where: { $0.name == "main" && $0.isDefinition }) {
            diagnostics.append(.init(
                severity: .note,
                message: "The shader uses 'main' rather than 'mainImage', so it was reshaped into the "
                    + "same form: the pixel position is 'fragCoord' and the result is 'fragColor'.",
                line: tokens[main.nameIndex].line))
            return .plainMain(functions.firstIndex { $0.name == "main" && $0.isDefinition }!)
        }
        return .none
    }

    /// Gives a plain `main` the entry-point shape the rest of this expects, and
    /// points the built-in pixel position and output color at the new parameters.
    static func reshapePlainMain(_ tokens: inout [GLSLToken], mainIndex: Int,
                                 diagnostics: inout [GLSLDiagnostic]) {
        let functions = GLSLScan.functions(in: tokens)
        guard mainIndex < functions.count else { return }
        let main = functions[mainIndex]

        tokens[main.nameIndex].text = "mainImage"
        // `main()` takes nothing, or `void`; either way the parameters are replaced.
        // They go on the opening bracket rather than the closing one, because the
        // closing one is where a later pass adds the frame's values.
        for i in (main.openParen + 1)..<main.closeParen { tokens[i].text = "" }
        tokens[main.openParen].text = "(thread float4 &fragColor, float2 fragCoord"

        // A modern shader declares its own output; an older one writes to the
        // built-in. Both become the new parameter.
        var declaredOutput: String? = nil
        for (i, t) in tokens.enumerated() where t.kind == .identifier && t.text == "out" {
            guard let typeIndex = tokens.nextSignificant(from: i + 1),
                  tokens[typeIndex].text == "float4",
                  let nameIndex = tokens.nextSignificant(from: typeIndex + 1),
                  tokens[nameIndex].kind == .identifier,
                  let semi = tokens.nextSignificant(from: nameIndex + 1), tokens[semi].text == ";"
            else { continue }
            declaredOutput = tokens[nameIndex].text
            for j in i...semi { tokens[j].text = "" }
            // The declaration drew an unsupported note on the way in; it is
            // handled now, so that note comes back out.
            diagnostics.removeAll { $0.line == t.line && $0.severity == .unsupported }
            break
        }

        for i in tokens.indices where tokens[i].kind == .identifier {
            switch tokens[i].text {
            case "gl_FragColor": tokens[i].text = "fragColor"
            case "gl_FragCoord": tokens[i].text = "float4(fragCoord, 0.0, 1.0)"
            case declaredOutput: tokens[i].text = "fragColor"
            default: break
            }
        }
    }

    // MARK: - Inputs

    static func channelsUsed(in tokens: [GLSLToken]) -> [String] {
        var used: [String] = []
        for t in tokens where t.kind == .identifier && channelNames.contains(t.text) {
            if !used.contains(t.text) { used.append(t.text) }
        }
        return used.sorted { (channelNames.firstIndex(of: $0) ?? 0) < (channelNames.firstIndex(of: $1) ?? 0) }
    }

    static func routingFor(channels: [String], diagnostics: inout [GLSLDiagnostic]) -> Routing {
        switch channels.count {
        case 0: return .generator
        case 1: return .filter
        case 2: return .combine
        default:
            diagnostics.append(.init(
                severity: .unsupported,
                message: "The shader reads \(channels.count) inputs, and a shader here takes at most two. "
                    + "Combine them into two layers, or drop the ones it can do without.",
                line: 0))
            return .combine
        }
    }

    /// Turns a channel read into a layer read. The vertical axis turns over,
    /// because the pasted shader measures a texture from the bottom and Ollin
    /// measures a layer from the top.
    static func rewriteChannelSampling(_ tokens: inout [GLSLToken], channels: [String],
                                       diagnostics: inout [GLSLDiagnostic]) {
        let samplers: Set<String> = ["texture", "texture2D", "textureLod", "texture2DLod"]

        for i in tokens.indices where tokens[i].kind == .identifier {
            if tokens[i].text == "texelFetch" {
                diagnostics.append(.init(
                    severity: .unsupported,
                    message: "'texelFetch' reads one texel by whole-number position, which a layer read "
                        + "cannot do. Divide the position by the resolution and sample instead.",
                    line: tokens[i].line))
                continue
            }
            guard samplers.contains(tokens[i].text),
                  let paren = tokens.nextSignificant(from: i + 1), tokens[paren].bracket == "(",
                  let close = tokens.matchingBracket(from: paren),
                  let first = tokens.nextSignificant(from: paren + 1),
                  channelNames.contains(tokens[first].text),
                  let slot = channels.firstIndex(of: tokens[first].text)
            else { continue }

            let commas = GLSLTranslator.topLevelCommas(in: tokens, from: paren, to: close)
            guard let firstComma = commas.first else { continue }

            tokens[i].text = slot == 0 ? "sample" : "sampleAux"
            tokens[first].text = "info"
            // Wrap the coordinate so the read lands the same way up as the original.
            tokens[firstComma].text = ", ollin_channel_uv("
            // The space that followed the comma now sits inside the wrap, where it
            // would read as a gap before the coordinate.
            if firstComma + 1 < tokens.count, tokens[firstComma + 1].kind == .whitespace,
               !tokens[firstComma + 1].text.contains("\n") {
                tokens[firstComma + 1].text = ""
            }
            tokens[close].text = ")" + tokens[close].text

            if commas.count > 1 {
                // A level-of-detail argument has nowhere to go on a layer read.
                for j in commas[1]..<close { tokens[j].text = "" }
                diagnostics.append(.init(
                    severity: .note,
                    message: "A texture level was asked for and dropped; a layer has one level.",
                    line: tokens[i].line))
            }
        }

    }

    /// Reports an input the rewrite could not reach, which happens when a channel
    /// is handed to a function rather than read on the spot.
    static func reportLeftoverInputs(in tokens: [GLSLToken], diagnostics: inout [GLSLDiagnostic]) {
        var reported: Set<String> = []
        for t in tokens where t.kind == .identifier && channelNames.contains(t.text) {
            guard reported.insert(t.text).inserted else { continue }
            diagnostics.append(.init(
                severity: .unsupported,
                message: "'\(t.text)' is used somewhere other than a texture read, so it has no layer to "
                    + "stand for it. Read the layer where it is used, or pass the color along instead.",
                line: t.line))
        }
    }

    /// Points each supplied value at the matching field of `ShaderInfo`.
    static func rewriteSuppliedValues(_ tokens: inout [GLSLToken], diagnostics: inout [GLSLDiagnostic]) {
        var notedDate = false
        var notedSampleRate = false
        var notedMouse = false

        for i in tokens.indices where tokens[i].kind == .identifier {
            switch tokens[i].text {
            case "iTime":
                tokens[i].text = "info.time"
            case "iTimeDelta":
                tokens[i].text = "info.deltaTime"
            case "iFrame":
                tokens[i].text = "int(info.frame)"
            case "iFrameRate":
                tokens[i].text = "(1.0 / max(info.deltaTime, 1e-5))"
            case "iResolution":
                // The third component is the pixel aspect, and it is 1 here. Every
                // read that stays within the first two takes the pair straight,
                // which is nearly all of them and keeps the line readable.
                let flat: Set<String> = ["x", "y", "xy", "yx", "xx", "yy"]
                if let dot = tokens.nextSignificant(from: i + 1), tokens[dot].text == ".",
                   let field = tokens.nextSignificant(from: dot + 1), flat.contains(tokens[field].text) {
                    tokens[i].text = "info.resolution"
                } else {
                    tokens[i].text = "float3(info.resolution, 1.0)"
                }
            case "iMouse":
                tokens[i].text = "ollin_mouse(info)"
                if !notedMouse {
                    notedMouse = true
                    diagnostics.append(.init(
                        severity: .note,
                        message: "The mouse reports its position in both halves, because Ollin does not "
                            + "keep the place of the last click. Read 'mouseIsPressed' in the sketch "
                            + "and pass it in as a param if the shader needs the button.",
                        line: tokens[i].line))
                }
            case "iDate":
                tokens[i].text = "float4(0.0, 0.0, 0.0, info.time)"
                if !notedDate {
                    notedDate = true
                    diagnostics.append(.init(
                        severity: .note,
                        message: "The calendar date is not supplied; only the seconds field carries a value.",
                        line: tokens[i].line))
                }
            case "iSampleRate":
                tokens[i].text = "44100.0"
                if !notedSampleRate {
                    notedSampleRate = true
                    diagnostics.append(.init(
                        severity: .note,
                        message: "The sample rate is a fixed 44100; this pass draws and does not make sound.",
                        line: tokens[i].line))
                }
            case "iChannelTime":
                replaceIndexed(&tokens, at: i, with: "info.time")
            case "iChannelResolution":
                replaceIndexed(&tokens, at: i, with: "float3(info.resolution, 1.0)")
            default:
                break
            }
        }
    }

    /// Replaces `name[k]` with one value, taking the subscript with it.
    private static func replaceIndexed(_ tokens: inout [GLSLToken], at i: Int, with replacement: String) {
        tokens[i].text = replacement
        if let bracket = tokens.nextSignificant(from: i + 1), tokens[bracket].text == "[",
           let close = tokens.matchingBracket(from: bracket) {
            for j in bracket...close { tokens[j].text = "" }
        }
    }

    // MARK: - Carrying info through

    /// Works out which functions have to be handed `info`.
    ///
    /// A supplied value is a global in the language this came from, so any
    /// function may read one. Metal has no such global, so `info` travels as a
    /// parameter, and it is added only to the functions that need it: the ones
    /// that read a value themselves, and the ones that call those.
    static func functionsNeedingInfo(in tokens: [GLSLToken], functions: [GLSLFunction]) -> Set<String> {
        let definitions = functions.filter { $0.isDefinition }
        var needs: Set<String> = []
        var callsOf: [String: Set<String>] = [:]

        for fn in definitions {
            guard let open = fn.openBrace, let close = fn.closeBrace else { continue }
            let body = open..<close
            // The mapping has already run, so a supplied value now reads as a
            // field of `info` sitting inside a token's text rather than as a
            // token of its own. Look for the name inside the text.
            if body.contains(where: { readsInfo(tokens[$0].text) }) { needs.insert(fn.name) }
            callsOf[fn.name] = GLSLScan.callsMade(in: tokens, range: body)
        }

        // A caller of a needing function needs it too, until nothing more changes.
        var changed = true
        while changed {
            changed = false
            for fn in definitions where !needs.contains(fn.name) {
                if let calls = callsOf[fn.name], !calls.isDisjoint(with: needs) {
                    needs.insert(fn.name)
                    changed = true
                }
            }
        }
        return needs
    }

    /// Whether a token's text reads `info` as a whole word. A name that merely
    /// holds those four letters, such as a shader's own `infold`, does not count.
    static func readsInfo(_ text: String) -> Bool {
        guard text.contains("info") else { return false }
        let chars = Array(text)
        let needle = Array("info")
        var i = 0
        while i + needle.count <= chars.count {
            if Array(chars[i..<(i + needle.count)]) == needle {
                let beforeOK = i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber || chars[i - 1] == "_")
                let after = i + needle.count
                let afterOK = after == chars.count
                    || !(chars[after].isLetter || chars[after].isNumber || chars[after] == "_")
                if beforeOK && afterOK { return true }
            }
            i += 1
        }
        return false
    }

    /// Adds the parameter to every function that needs it, and the argument to
    /// every call of one.
    static func threadInfo(_ tokens: inout [GLSLToken], functions: [GLSLFunction], needing: Set<String>) {
        guard !needing.isEmpty else { return }

        var declarationParens: Set<Int> = []
        for fn in functions where needing.contains(fn.name) {
            declarationParens.insert(fn.openParen)
            addArgument(&tokens, openParen: fn.openParen, closeParen: fn.closeParen, text: "ShaderInfo info")
        }

        for i in tokens.indices where tokens[i].kind == .identifier && needing.contains(tokens[i].text) {
            guard let paren = tokens.nextSignificant(from: i + 1), tokens[paren].bracket == "(",
                  !declarationParens.contains(paren),
                  let close = tokens.matchingBracket(from: paren) else { continue }
            addArgument(&tokens, openParen: paren, closeParen: close, text: "info")
        }
    }

    /// Puts one more entry at the end of a parenthesised list, whether or not the
    /// list already holds anything.
    private static func addArgument(_ tokens: inout [GLSLToken], openParen: Int, closeParen: Int, text: String) {
        // A list already carrying something needs a separator. What it carries may
        // sit in the tokens between the brackets, or, for a list an earlier rule
        // rewrote whole, on the opening bracket itself.
        var isEmpty = tokens[openParen].text == "("
        for i in (openParen + 1)..<closeParen where tokens[i].hasText {
            if tokens[i].text == "void" { tokens[i].text = ""; continue }
            isEmpty = false
        }
        tokens[closeParen].text = (isEmpty ? text : ", " + text) + tokens[closeParen].text
    }

    // MARK: - Assembly

    static func mentions(_ name: String, in source: String) -> Bool {
        source.contains(name)
    }

    static func assemble(body: String, helpers: Set<GLSLCompat.Helper>, routing: Routing,
                         entryNeedsInfo: Bool, usesMouse: Bool,
                         diagnostics: [GLSLDiagnostic], provenance: Provenance) -> String {
        var parts: [String] = []

        parts.append(header(provenance: provenance, routing: routing))

        if !diagnostics.isEmpty {
            var notes = ["// Things worth a look, from the translation:"]
            for d in diagnostics.sorted(by: { $0.line < $1.line }) {
                let mark = d.severity == .unsupported ? "TODO" : "NOTE"
                let place = d.line > 0 ? " (line \(d.line) of the original)" : ""
                notes.append("// \(mark)(ollin):\(place) \(d.message)")
            }
            parts.append(notes.joined(separator: "\n"))
        }

        var support: [String] = []
        let helperSource = GLSLCompat.source(for: helpers)
        if !helperSource.isEmpty { support.append(helperSource) }

        if routing != .generator {
            support.append("""
            // A layer is measured from its top edge and a texture from its bottom, so
            // a coordinate turns over on its way to a layer read.
            inline float2 ollin_channel_uv(float2 uv) { return float2(uv.x, 1.0 - uv.y); }
            """)
        }
        if usesMouse {
            support.append("""
            inline float4 ollin_mouse(ShaderInfo info) {
                float2 p = float2(info.mouse.x, info.resolution.y - info.mouse.y);
                return float4(p, p);
            }
            """)
        }
        if !support.isEmpty { parts.append(support.joined(separator: "\n\n")) }

        parts.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        parts.append(entryPointSource(needsInfo: entryNeedsInfo))

        return parts.joined(separator: "\n\n") + "\n"
    }

    static func header(provenance: Provenance, routing: Routing) -> String {
        var lines: [String] = []
        lines.append("// A fragment shader brought over from GLSL.")
        if let title = provenance.title, !title.isEmpty { lines.append("// Shader: \(title)") }
        if let author = provenance.author, !author.isEmpty { lines.append("// Author: \(author)") }
        if let url = provenance.url, !url.isEmpty { lines.append("// Source: \(url)") }
        lines.append("//")
        lines.append("// The shader stays under the terms its author gave it. Check those terms")
        lines.append("// before you publish anything made from it, and keep this header with it.")
        switch routing {
        case .generator:
            lines.append("// It reads no input, so the sketch runs it with generate(...).")
        case .filter:
            lines.append("// It reads one input, so the sketch runs it with layer.filtered(...).")
        case .combine:
            lines.append("// It reads two inputs, so the sketch runs it with a.combined(with: b, ...).")
        }
        return lines.joined(separator: "\n")
    }

    static func entryPointSource(needsInfo: Bool) -> String {
        let call = needsInfo ? "mainImage(fragColor, fragCoord, info);" : "mainImage(fragColor, fragCoord);"
        return """
        // Ollin's own entry point. It hands the shader the pixel position it expects,
        // measured in pixels from the bottom-left corner, and takes back the color.
        float4 shade(float2 uv, ShaderInfo info) {
            float2 fragCoord = float2(uv.x, 1.0 - uv.y) * info.resolution;
            float4 fragColor = float4(0.0, 0.0, 0.0, 1.0);
            \(call)
            // The site this came from shows every pixel opaque and pays no attention
            // to the fourth channel, so holding it at 1 is what reproduces the look.
            return float4(fragColor.rgb, 1.0);
        }
        """
    }
}
