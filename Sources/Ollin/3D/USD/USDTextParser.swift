import Foundation

/// A recursive-descent parser for the `.usda` text format, covering the
/// flattened single-layer envelope: prim defs with metadata, attributes
/// (defaults, `timeSamples` blocks, `.connect` targets), relationships, and
/// layer metadata. Composition arcs (references, payloads, variant sets) are
/// tolerated syntactically and skipped, never composed.
///
/// Values coerce by the declared attribute type (`point3f[]` lands as a flat
/// float tuple array), while untyped metadata values keep the literal's own
/// shape. Unknown constructs record `.unsupported` and parsing continues.
final class USDTextParser {

    private let bytes: [UInt8]
    private var i = 0

    init(text: String) {
        bytes = Array(text.utf8)
    }

    // MARK: - Entry

    func parseStage() throws -> USDStage {
        var stage = USDStage()
        try parseCookie()
        skipTrivia()
        if peek() == UInt8(ascii: "(") {
            stage.metadata = try parseMetadataBlock()
        }
        skipTrivia()
        while !atEnd {
            let word = peekIdentifier()
            switch word {
            case "def", "over", "class":
                stage.prims.append(try parsePrim())
            case "reorder":
                try skipToEndOfStatement()
            default:
                throw error("expected a prim statement, found '\(word ?? String(UnicodeScalar(peek() ?? 0)))'")
            }
            skipTrivia()
        }
        return stage
    }

    // MARK: - Header

    private func parseCookie() throws {
        guard match("#usda") else { throw error("missing '#usda' cookie") }
        // The rest of the cookie line is the version; accept any 1.x.
        while let c = peek(), c != UInt8(ascii: "\n") { i += 1 }
    }

    // MARK: - Prims

    private func parsePrim() throws -> USDPrim {
        let specifier: USDSpecifier
        if match("def") { specifier = .def }
        else if match("over") { specifier = .over }
        else if match("class") { specifier = .class }
        else { throw error("expected def/over/class") }

        skipTrivia()
        var typeName = ""
        if peek() != UInt8(ascii: "\"") && peek() != UInt8(ascii: "'") {
            typeName = try parseIdentifier()
            skipTrivia()
            // Schema type names may be dotted (`Plugin.Type`).
            while peek() == UInt8(ascii: ".") {
                i += 1
                typeName += "." + (try parseIdentifier())
                skipTrivia()
            }
        }
        let name = try parseQuotedString()
        var prim = USDPrim(name: name, specifier: specifier, typeName: typeName)

        skipTrivia()
        if peek() == UInt8(ascii: "(") {
            prim.metadata = try parseMetadataBlock()
            skipTrivia()
        }
        try expect("{")
        skipTrivia()
        while peek() != UInt8(ascii: "}") {
            guard !atEnd else { throw error("unterminated prim body for '\(name)'") }
            // A `;` is a statement separator, interchangeable with a newline.
            if peek() == UInt8(ascii: ";") {
                i += 1
            } else {
                try parsePrimBodyStatement(into: &prim)
            }
            skipTrivia()
        }
        i += 1  // consume '}'
        return prim
    }

    private func parsePrimBodyStatement(into prim: inout USDPrim) throws {
        switch peekIdentifier() {
        case "def", "over", "class":
            prim.children.append(try parsePrim())
        case "variantSet":
            try skipVariantSet()
        case "reorder":
            try skipToEndOfStatement()
        case "rel", "custom", "uniform", "varying", "add", "append", "prepend", "delete":
            try parseProperty(into: &prim)
        case .some:
            try parseProperty(into: &prim)
        case nil:
            throw error("expected a statement in prim '\(prim.name)'")
        }
    }

    // MARK: - Properties

    /// Parse one attribute or relationship declaration, including the shared
    /// qualifier prefix (`custom`, `uniform`/`varying`, list-edit keywords).
    private func parseProperty(into prim: inout USDPrim) throws {
        var isCustom = false
        var isUniform = false
        // Qualifiers, in any order; list-edit keywords apply to relationships
        // and are recorded only through the targets they introduce.
        qualifiers: while true {
            switch peekIdentifier() {
            case "custom": _ = match("custom"); isCustom = true
            case "uniform": _ = match("uniform"); isUniform = true
            case "varying": _ = match("varying")
            case "config": _ = match("config")
            case "add", "append", "prepend", "delete":
                _ = try parseIdentifier()
            default: break qualifiers
            }
            skipTrivia()
        }

        if match("rel") {
            skipTrivia()
            try parseRelationship(into: &prim)
            return
        }

        var typeName = try parseIdentifier()
        skipTrivia()
        if peek() == UInt8(ascii: "[") && peek(1) == UInt8(ascii: "]") {
            i += 2
            typeName += "[]"
            skipTrivia()
        }
        let (name, suffix) = try parsePropertyName()
        skipTrivia()

        var index = prim.attributes.firstIndex { $0.name == name }
        if index == nil {
            prim.attributes.append(USDAttribute(name: name, typeName: typeName,
                                                isUniform: isUniform, isCustom: isCustom))
            index = prim.attributes.count - 1
        }

        switch suffix {
        case "timeSamples":
            try expect("=")
            skipTrivia()
            prim.attributes[index!].timeSamples = try parseTimeSamplesBlock(declaredType: typeName)
        case "connect":
            try expect("=")
            skipTrivia()
            if !match("None") {
                prim.attributes[index!].connections += try parsePathTargets()
            }
        case "spline":
            // Spline blocks are outside the envelope; balance and skip.
            try expect("=")
            skipTrivia()
            try skipBalancedBraces()
        case nil:
            if peek() == UInt8(ascii: "=") {
                i += 1
                skipTrivia()
                prim.attributes[index!].value = try parseValue(declaredType: typeName)
                skipTrivia()
            }
            if peek() == UInt8(ascii: "(") {
                prim.attributes[index!].metadata = try parseMetadataBlock()
            }
        default:
            throw error("unsupported property suffix '.\(suffix!)' on '\(name)'")
        }
    }

    /// A property name: `:`-namespaced identifier segments, plus an optional
    /// `.connect` / `.timeSamples` suffix.
    private func parsePropertyName() throws -> (name: String, suffix: String?) {
        let name = try parseIdentifier()
        guard peek() == UInt8(ascii: ".") else { return (name, nil) }
        i += 1
        return (name, try parseIdentifier())
    }

    private func parseRelationship(into prim: inout USDPrim) throws {
        let (name, suffix) = try parsePropertyName()
        var rel = USDRelationship(name: name)
        if let suffix {
            // The one valid suffix is `.default = <path>`.
            guard suffix == "default" else {
                throw error("unsupported relationship suffix '.\(suffix)' on '\(name)'")
            }
            try expect("=")
            skipTrivia()
            rel.metadata["default"] = .path(try parsePathLiteral())
            if let existing = prim.relationships.firstIndex(where: { $0.name == name }) {
                prim.relationships[existing].metadata["default"] = rel.metadata["default"]
            } else {
                prim.relationships.append(rel)
            }
            return
        }
        skipTrivia()
        if peek() == UInt8(ascii: "=") {
            i += 1
            skipTrivia()
            if match("None") {
                // An explicitly blocked relationship keeps its empty targets.
            } else {
                rel.targets = try parsePathTargets()
            }
            skipTrivia()
        }
        if peek() == UInt8(ascii: "(") {
            rel.metadata = try parseMetadataBlock()
        }
        if let existing = prim.relationships.firstIndex(where: { $0.name == name }) {
            prim.relationships[existing].targets += rel.targets
        } else {
            prim.relationships.append(rel)
        }
    }

    /// One `<path>` or a bracketed list of them.
    private func parsePathTargets() throws -> [String] {
        if peek() == UInt8(ascii: "<") {
            return [try parsePathLiteral()]
        }
        try expect("[")
        var targets: [String] = []
        skipTrivia()
        while peek() != UInt8(ascii: "]") {
            guard !atEnd else { throw error("unterminated path list") }
            targets.append(try parsePathLiteral())
            skipTrivia()
            if peek() == UInt8(ascii: ",") { i += 1; skipTrivia() }
        }
        i += 1
        return targets
    }

    // MARK: - Time samples

    private func parseTimeSamplesBlock(declaredType: String) throws -> [USDTimeSample] {
        try expect("{")
        var samples: [USDTimeSample] = []
        skipTrivia()
        while peek() != UInt8(ascii: "}") {
            guard !atEnd else { throw error("unterminated timeSamples block") }
            guard case .some(let time) = try parseNumber() else {
                throw error("expected a time code")
            }
            skipTrivia()
            try expect(":")
            skipTrivia()
            let value: USDValue = match("None") ? .block : try parseValue(declaredType: declaredType)
            samples.append(USDTimeSample(time: time, value: value))
            skipTrivia()
            if peek() == UInt8(ascii: ",") { i += 1; skipTrivia() }
        }
        i += 1
        return samples
    }

    // MARK: - Metadata

    /// A parenthesized metadata block on the layer, a prim, or a property.
    private func parseMetadataBlock() throws -> [String: USDValue] {
        try expect("(")
        var result: [String: USDValue] = [:]
        skipTrivia()
        while peek() != UInt8(ascii: ")") {
            guard !atEnd else { throw error("unterminated metadata block") }
            // A bare string entry is documentation.
            if peek() == UInt8(ascii: "\"") || peek() == UInt8(ascii: "'") {
                result["doc"] = .string(try parseStringLiteral())
                skipTrivia()
                continue
            }
            var key = try parseIdentifier()
            skipTrivia()
            // A list-edit qualifier prefixes the real key: `prepend apiSchemas = […]`.
            if ["add", "append", "prepend", "delete", "reorder"].contains(key) {
                key = try parseIdentifier()
                skipTrivia()
            }
            try expect("=")
            skipTrivia()
            switch key {
            case "references", "payload", "inherits", "specializes", "subLayers", "variantSets", "variants":
                // Composition arcs are outside the envelope: consume the value
                // shape without interpreting it.
                try skipCompositionValue()
                result[key] = .unsupported(key)
            case "relocates", "prefixSubstitutions", "suffixSubstitutions":
                // Path- and string-keyed colon maps; balance and skip.
                skipTrivia()
                try skipBalancedBraces()
                result[key] = .unsupported(key)
            default:
                result[key] = try parseValue(declaredType: nil)
            }
            skipTrivia()
            if peek() == UInt8(ascii: ";") { i += 1; skipTrivia() }
        }
        i += 1
        return result
    }

    /// Consume a composition-arc value: a reference (`@asset@</path>` with an
    /// optional layer-offset call), a path, a dictionary, or a list of those.
    private func skipCompositionValue() throws {
        skipTrivia()
        switch peek() {
        case UInt8(ascii: "["):
            i += 1
            skipTrivia()
            while peek() != UInt8(ascii: "]") {
                guard !atEnd else { throw error("unterminated composition list") }
                try skipCompositionValue()
                skipTrivia()
                if peek() == UInt8(ascii: ",") { i += 1; skipTrivia() }
            }
            i += 1
        case UInt8(ascii: "{"):
            _ = try parseDictionary()
        case UInt8(ascii: "@"):
            _ = try parseAssetLiteral()
            skipTrivia()
            if peek() == UInt8(ascii: "<") { _ = try parsePathLiteral() }
            skipTrivia()
            if peek() == UInt8(ascii: "(") { _ = try parseMetadataBlock() }
        case UInt8(ascii: "<"):
            _ = try parsePathLiteral()
            skipTrivia()
            if peek() == UInt8(ascii: "(") { _ = try parseMetadataBlock() }
        case UInt8(ascii: "N") where match("None"):
            break
        default:
            _ = try parseValue(declaredType: nil)
        }
    }

    private func skipVariantSet() throws {
        // variantSet "name" = { "variant" ( meta ) { body } … } is outside the
        // envelope (variants come pre-applied in flattened files), so balance
        // the braces string-aware and move on.
        _ = try parseIdentifier()
        skipTrivia()
        _ = try parseQuotedString()
        skipTrivia()
        try expect("=")
        skipTrivia()
        try skipBalancedBraces()
    }

    /// Consume a `{ … }` block, balancing nested braces while staying aware
    /// of strings, asset literals, and comments.
    private func skipBalancedBraces() throws {
        try expect("{")
        var depth = 1
        while depth > 0 {
            guard let c = peek() else { throw error("unterminated block") }
            switch c {
            case UInt8(ascii: "{"): depth += 1; i += 1
            case UInt8(ascii: "}"): depth -= 1; i += 1
            case UInt8(ascii: "\""), UInt8(ascii: "'"): _ = try parseStringLiteral()
            case UInt8(ascii: "@"): _ = try parseAssetLiteral()
            case UInt8(ascii: "#"):
                while let d = peek(), d != UInt8(ascii: "\n") { i += 1 }
            case UInt8(ascii: "/") where peek(1) == UInt8(ascii: "/") || peek(1) == UInt8(ascii: "*"):
                skipTrivia()
            default: i += 1
            }
        }
    }

    private func skipToEndOfStatement() throws {
        while let c = peek(), c != UInt8(ascii: "\n") {
            if c == UInt8(ascii: "[") {
                // A bracketed list may wrap lines; balance it.
                var depth = 0
                repeat {
                    guard let d = peek() else { return }
                    if d == UInt8(ascii: "[") { depth += 1 }
                    if d == UInt8(ascii: "]") { depth -= 1 }
                    i += 1
                } while depth > 0
            } else {
                i += 1
            }
        }
    }

    // MARK: - Values

    /// Parse one value literal, coercing by `declaredType` when given (an
    /// attribute's declared type) or keeping the literal's neutral shape when
    /// nil (metadata values).
    private func parseValue(declaredType: String?) throws -> USDValue {
        skipTrivia()
        guard let c = peek() else { throw error("expected a value") }
        switch c {
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            let s = try parseStringLiteral()
            switch declaredType.map(Self.baseType) {
            case "token": return .token(s)
            default: return .string(s)
            }
        case UInt8(ascii: "@"):
            return .asset(try parseAssetLiteral())
        case UInt8(ascii: "<"):
            return .path(try parsePathLiteral())
        case UInt8(ascii: "("):
            let components = try parseTupleComponents()
            return .tuple(components)
        case UInt8(ascii: "["):
            return try parseArray(declaredType: declaredType)
        case UInt8(ascii: "{"):
            return .dictionary(try parseDictionary())
        default:
            if match("true") { return .bool(true) }
            if match("false") { return .bool(false) }
            if match("None") { return .block }
            if match("AnimationBlock") { return .unsupported("AnimationBlock") }
            if peekIdentifier() == "edit" {
                // An array-edit value: skip the balanced instruction list.
                _ = try parseIdentifier()
                skipTrivia()
                try skipBalancedBrackets()
                return .unsupported("arrayEdit")
            }
            if let n = try parseNumber() {
                return Self.coerceScalar(n, declaredType: declaredType)
            }
            // A bare identifier arrives as a token (`permission = public`).
            if Self.isIdentifierByte(c) {
                return .token(try parseIdentifier())
            }
            throw error("unrecognized value")
        }
    }

    /// Consume a `[ … ]` block, balancing nested brackets string-aware.
    private func skipBalancedBrackets() throws {
        try expect("[")
        var depth = 1
        while depth > 0 {
            guard let c = peek() else { throw error("unterminated bracket block") }
            switch c {
            case UInt8(ascii: "["): depth += 1; i += 1
            case UInt8(ascii: "]"): depth -= 1; i += 1
            case UInt8(ascii: "\""), UInt8(ascii: "'"): _ = try parseStringLiteral()
            case UInt8(ascii: "@"): _ = try parseAssetLiteral()
            default: i += 1
            }
        }
    }

    /// A tuple literal `(a, b, …)`; nested tuples (matrix rows) flatten.
    private func parseTupleComponents() throws -> [Double] {
        try expect("(")
        var components: [Double] = []
        skipTrivia()
        while peek() != UInt8(ascii: ")") {
            guard !atEnd else { throw error("unterminated tuple") }
            if peek() == UInt8(ascii: "(") {
                components += try parseTupleComponents()
            } else if let n = try parseNumber() {
                components.append(n)
            } else {
                throw error("expected a number in tuple")
            }
            skipTrivia()
            if peek() == UInt8(ascii: ",") { i += 1; skipTrivia() }
        }
        i += 1
        return components
    }

    private func parseArray(declaredType: String?) throws -> USDValue {
        try expect("[")
        skipTrivia()

        var numbers: [Double] = []
        var strings: [String] = []
        var paths: [String] = []
        var tupleArity = 0
        var tupleComponents: [Double] = []
        var sawFraction = false
        var kind: ArrayKind = .empty

        while peek() != UInt8(ascii: "]") {
            guard !atEnd else { throw error("unterminated array") }
            switch peek() {
            case UInt8(ascii: "\""), UInt8(ascii: "'"):
                strings.append(try parseStringLiteral())
                if kind == .empty { kind = .string }
            case UInt8(ascii: "@"):
                strings.append(try parseAssetLiteral())
                kind = .asset
            case UInt8(ascii: "<"):
                paths.append(try parsePathLiteral())
                kind = .path
            case UInt8(ascii: "("):
                let t = try parseTupleComponents()
                if tupleArity == 0 { tupleArity = t.count }
                tupleComponents += t
                kind = .tuple
            default:
                if match("true") { numbers.append(1); kind = .bool }
                else if match("false") { numbers.append(0); kind = .bool }
                else if let n = try parseNumber() {
                    if n != n.rounded(.towardZero) || abs(n) >= 9.007199254740992e15 { sawFraction = true }
                    numbers.append(n)
                    if kind == .empty { kind = .number }
                } else {
                    throw error("unrecognized array element")
                }
            }
            skipTrivia()
            if peek() == UInt8(ascii: ",") { i += 1; skipTrivia() }
        }
        i += 1

        let base = declaredType.map(Self.baseType)
        switch kind {
        case .empty:
            return Self.emptyArray(for: base)
        case .bool:
            return .boolArray(numbers.map { $0 != 0 })
        case .string:
            switch base {
            case "token": return .tokenArray(strings)
            case "asset": return .assetArray(strings)
            default: return .stringArray(strings)
            }
        case .asset: return .assetArray(strings)
        case .path: return .pathArray(paths)
        case .tuple:
            switch Self.flavor(of: base) {
            case .float: return .floatTupleArray(tupleArity, tupleComponents.map(Float.init))
            default: return .doubleTupleArray(tupleArity, tupleComponents)
            }
        case .number:
            switch Self.flavor(of: base) {
            case .float: return .floatArray(numbers.map(Float.init))
            case .double: return .doubleArray(numbers)
            case .int: return .intArray(numbers.map { Int64($0) })
            case .stringLike, .other:
                // Untyped: integral values stay ints, anything else doubles.
                return sawFraction ? .doubleArray(numbers) : .intArray(numbers.map { Int64($0) })
            }
        }
    }

    private enum ArrayKind { case empty, bool, number, string, asset, path, tuple }

    /// The right empty-array value for a declared element type.
    private static func emptyArray(for base: String?) -> USDValue {
        guard let base else { return .doubleArray([]) }
        let arity = tupleArity(base)
        switch flavor(of: base) {
        case .float: return arity > 1 ? .floatTupleArray(arity, []) : .floatArray([])
        case .double: return arity > 1 ? .doubleTupleArray(arity, []) : .doubleArray([])
        case .int: return .intArray([])
        case .stringLike:
            switch base {
            case "token": return .tokenArray([])
            case "asset": return .assetArray([])
            default: return .stringArray([])
            }
        case .other: return .doubleArray([])
        }
    }

    private func parseDictionary() throws -> [String: USDValue] {
        try expect("{")
        var result: [String: USDValue] = [:]
        skipTrivia()
        while peek() != UInt8(ascii: "}") {
            guard !atEnd else { throw error("unterminated dictionary") }
            // Entries are `[type] key = value`; the key may be quoted, and
            // `dictionary` types nest.
            var declaredType: String?
            var key: String
            if peek() == UInt8(ascii: "\"") || peek() == UInt8(ascii: "'") {
                key = try parseQuotedString()
            } else {
                let first = try parseIdentifier()
                skipTrivia()
                if peek() == UInt8(ascii: "[") && peek(1) == UInt8(ascii: "]") {
                    i += 2
                    declaredType = first + "[]"
                    skipTrivia()
                    key = peek() == UInt8(ascii: "\"") || peek() == UInt8(ascii: "'")
                        ? try parseQuotedString() : try parseIdentifier()
                } else if peek() == UInt8(ascii: "=") {
                    key = first
                } else {
                    declaredType = first
                    key = peek() == UInt8(ascii: "\"") || peek() == UInt8(ascii: "'")
                        ? try parseQuotedString() : try parseIdentifier()
                }
            }
            skipTrivia()
            try expect("=")
            skipTrivia()
            if declaredType == "dictionary" {
                result[key] = .dictionary(try parseDictionary())
            } else {
                result[key] = try parseValue(declaredType: declaredType)
            }
            skipTrivia()
            if peek() == UInt8(ascii: ";") { i += 1; skipTrivia() }
        }
        i += 1
        return result
    }

    // MARK: - Type coercion

    private static func coerceScalar(_ n: Double, declaredType: String?) -> USDValue {
        switch flavor(of: declaredType.map(baseType)) {
        case .float, .double: return .double(n)
        case .int:
            if declaredType == "bool" { return .bool(n != 0) }
            if declaredType == "uint" || declaredType == "uint64" {
                return .uint(UInt64(bitPattern: Int64(n)))
            }
            return .int(Int64(n))
        case .stringLike, .other:
            let isIntegral = n == n.rounded(.towardZero) && abs(n) < 9.007199254740992e15
            return isIntegral ? .int(Int64(n)) : .double(n)
        }
    }

    /// The element type of an array type: `point3f[]` → `point3f`.
    private static func baseType(_ type: String) -> String {
        type.hasSuffix("[]") ? String(type.dropLast(2)) : type
    }

    private enum Flavor { case float, double, int, stringLike, other }

    private static func flavor(of base: String?) -> Flavor {
        guard let base else { return .other }
        switch base {
        case "half", "float", "quath", "quatf":
            return .float
        case "double", "quatd", "frame4d", "matrix2d", "matrix3d", "matrix4d", "timecode":
            return .double
        case "int", "uint", "int64", "uint64", "uchar", "bool":
            return .int
        case "string", "token", "asset", "path":
            return .stringLike
        default:
            // Compound names: float2/3/4, double2/3/4, half2, color3f, point3f,
            // normal3f, vector3f, texCoord2f/h/d, int2/3/4 …
            if base.hasPrefix("int") { return .int }
            if base.hasPrefix("double") { return .double }
            if base.hasSuffix("d") { return .double }
            if base.hasPrefix("float") || base.hasPrefix("half") { return .float }
            if base.hasSuffix("f") || base.hasSuffix("h") { return .float }
            return .other
        }
    }

    /// The tuple arity of a base type name (`point3f` → 3, `matrix4d` → 16,
    /// scalar types → 1).
    private static func tupleArity(_ base: String) -> Int {
        if base.hasPrefix("matrix"), let n = base.dropFirst(6).first?.wholeNumberValue {
            return n * n
        }
        if base.hasPrefix("quat") { return 4 }
        if let idx = base.lastIndex(where: \.isNumber) {
            let after = base.index(after: idx)
            if after == base.endIndex || "fdh".contains(base[after]) {
                return base[idx].wholeNumberValue ?? 1
            }
        }
        return 1
    }

    // MARK: - Literals

    /// A quoted string: single or double quotes, or their triple-quoted
    /// multiline forms, with C-style escapes.
    private func parseStringLiteral() throws -> String {
        guard let quote = peek(), quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") else {
            throw error("expected a string")
        }
        let triple = peek(1) == quote && peek(2) == quote
        i += triple ? 3 : 1
        var out: [UInt8] = []
        while true {
            guard let c = peek() else { throw error("unterminated string") }
            if c == quote {
                if triple {
                    if peek(1) == quote && peek(2) == quote { i += 3; break }
                    out.append(c)
                    i += 1
                } else {
                    i += 1
                    break
                }
            } else if c == UInt8(ascii: "\\") {
                i += 1
                guard let e = peek() else { throw error("unterminated escape") }
                switch e {
                case UInt8(ascii: "a"): out.append(0x07); i += 1
                case UInt8(ascii: "b"): out.append(0x08); i += 1
                case UInt8(ascii: "f"): out.append(0x0C); i += 1
                case UInt8(ascii: "n"): out.append(0x0A); i += 1
                case UInt8(ascii: "r"): out.append(0x0D); i += 1
                case UInt8(ascii: "t"): out.append(0x09); i += 1
                case UInt8(ascii: "v"): out.append(0x0B); i += 1
                case UInt8(ascii: "x"):
                    // 1-2 hex digits; bare `\x` is a zero byte.
                    i += 1
                    var value = 0
                    var digits = 0
                    while digits < 2, let d = peek(), let hex = Self.hexDigit(d) {
                        value = value * 16 + hex
                        digits += 1
                        i += 1
                    }
                    out.append(UInt8(value))
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    // 1-3 octal digits, accumulated mod 256.
                    var value = 0
                    var digits = 0
                    while digits < 3, let d = peek(),
                          d >= UInt8(ascii: "0"), d <= UInt8(ascii: "7") {
                        value = (value * 8 + Int(d - UInt8(ascii: "0"))) % 256
                        digits += 1
                        i += 1
                    }
                    out.append(UInt8(value))
                default:
                    // Any other escaped character stands for itself.
                    out.append(e)
                    i += 1
                }
            } else {
                if !triple && c == UInt8(ascii: "\n") { throw error("newline in string") }
                out.append(c)
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private func parseQuotedString() throws -> String {
        try parseStringLiteral()
    }

    /// An asset path literal: `@…@`, or `@@@…@@@` when the path contains `@`.
    private func parseAssetLiteral() throws -> String {
        guard peek() == UInt8(ascii: "@") else { throw error("expected an asset path") }
        let triple = peek(1) == UInt8(ascii: "@") && peek(2) == UInt8(ascii: "@")
        i += triple ? 3 : 1
        var out: [UInt8] = []
        while true {
            guard let c = peek() else { throw error("unterminated asset path") }
            if c == UInt8(ascii: "@") {
                if triple {
                    if peek(1) == UInt8(ascii: "@") && peek(2) == UInt8(ascii: "@") { i += 3; break }
                    out.append(c)
                    i += 1
                } else {
                    i += 1
                    break
                }
            } else {
                out.append(c)
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// A path literal: `<…>` captured verbatim.
    private func parsePathLiteral() throws -> String {
        try expect("<")
        var out: [UInt8] = []
        while true {
            guard let c = peek() else { throw error("unterminated path") }
            if c == UInt8(ascii: ">") { i += 1; break }
            out.append(c)
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// A number literal, or nil if the cursor isn't at one. Accepts ints,
    /// decimals, scientific notation, `inf`/`-inf`/`nan`.
    private func parseNumber() throws -> Double? {
        skipTrivia()
        let start = i
        if match("inf") { return .infinity }
        if match("-inf") { return -.infinity }
        if match("nan") { return .nan }
        var sawDigit = false
        if peek() == UInt8(ascii: "-") || peek() == UInt8(ascii: "+") { i += 1 }
        while let c = peek() {
            if c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") { sawDigit = true; i += 1 }
            else if c == UInt8(ascii: ".") { i += 1 }
            else if c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
                i += 1
                if peek() == UInt8(ascii: "-") || peek() == UInt8(ascii: "+") { i += 1 }
            } else { break }
        }
        guard sawDigit else { i = start; return nil }
        let text = String(decoding: bytes[start..<i], as: UTF8.self)
        guard let value = Double(text) else { throw error("bad number '\(text)'") }
        return value
    }

    /// An identifier: letters, digits, underscores, joined by `:` namespaces.
    private func parseIdentifier() throws -> String {
        skipTrivia()
        let start = i
        while let c = peek(), Self.isIdentifierByte(c) { i += 1 }
        guard i > start else { throw error("expected an identifier") }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    /// The identifier at the cursor without consuming it, or nil.
    private func peekIdentifier() -> String? {
        var j = i
        while j < bytes.count, Self.isIdentifierByte(bytes[j]) { j += 1 }
        return j > i ? String(decoding: bytes[i..<j], as: UTF8.self) : nil
    }

    private static func hexDigit(_ c: UInt8) -> Int? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): Int(c - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): Int(c - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): Int(c - UInt8(ascii: "A")) + 10
        default: nil
        }
    }

    private static func isIdentifierByte(_ c: UInt8) -> Bool {
        (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
            || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
            || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
            || c == UInt8(ascii: "_") || c == UInt8(ascii: ":")
    }

    // MARK: - Scanner

    private var atEnd: Bool { i >= bytes.count }

    private func peek(_ ahead: Int = 0) -> UInt8? {
        i + ahead < bytes.count ? bytes[i + ahead] : nil
    }

    /// Consume `text` if the cursor is at it and, for identifier-like text,
    /// the following byte doesn't extend the identifier.
    private func match(_ text: String) -> Bool {
        let t = Array(text.utf8)
        guard i + t.count <= bytes.count else { return false }
        for (k, c) in t.enumerated() where bytes[i + k] != c { return false }
        // Word-boundary guard so `match("def")` won't eat "default".
        if Self.isIdentifierByte(t[t.count - 1]),
           i + t.count < bytes.count, Self.isIdentifierByte(bytes[i + t.count]) {
            return false
        }
        i += t.count
        return true
    }

    private func expect(_ text: String) throws {
        skipTrivia()
        guard match(text) else {
            let found = peek().map { String(UnicodeScalar($0)) } ?? "end of file"
            throw error("expected '\(text)', found '\(found)'")
        }
    }

    /// Skip whitespace, newlines, and all three comment forms (`#`, `//`,
    /// `/* … */`).
    private func skipTrivia() {
        while let c = peek() {
            switch c {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), UInt8(ascii: "\n"):
                i += 1
            case UInt8(ascii: "#"):
                while let d = peek(), d != UInt8(ascii: "\n") { i += 1 }
            case UInt8(ascii: "/") where peek(1) == UInt8(ascii: "/"):
                while let d = peek(), d != UInt8(ascii: "\n") { i += 1 }
            case UInt8(ascii: "/") where peek(1) == UInt8(ascii: "*"):
                i += 2
                while i < bytes.count,
                      !(bytes[i] == UInt8(ascii: "*") && peek(1) == UInt8(ascii: "/")) {
                    i += 1
                }
                i = min(i + 2, bytes.count)
            default:
                return
            }
        }
    }

    private func error(_ message: String) -> USDError {
        var line = 1
        for k in 0..<min(i, bytes.count) where bytes[k] == UInt8(ascii: "\n") { line += 1 }
        return .malformed("usda line \(line): \(message)")
    }
}
