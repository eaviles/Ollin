import Foundation

/// A small arithmetic language, read from a string and evaluated as often as
/// you like. It is what lets a number arrive as *typed text* rather than as
/// Swift source: a parameter driven by `"120 + sin(time) * 40"`, a value read from a
/// file, a control an editing surface hands to a person.
///
/// ```swift
/// let wobble = try Formula("120 + sin(time * 2) * 40")
/// let radius = wobble.value(["time": time])
/// ```
///
/// A formula is a pure function of the values you hand it: the same inputs
/// always give the same number, which is why an automation reading one renders
/// the same on every pass. The one call that reaches outside is `noise`,
/// and it reads a field you supply (a sketch hands over its own, so
/// `noiseSeed()` reproduces it).
///
/// Names are resolved while parsing, not while evaluating, so a formula
/// evaluated per frame touches no dictionary at all. ``variables`` reports the
/// names it found, in the order it met them, and ``value(_:noise:)-([Double],_)`` takes the
/// numbers in that order.
///
/// See `Docs/Helpers/Formula.md` for the whole vocabulary.
public struct Formula: Sendable, CustomStringConvertible {

    /// A signed noise field, `-1...1`, as `(x, y, z)`. A sketch hands over its
    /// own so `noiseSeed()` reaches a formula; with none, every formula reads
    /// one shared field with a fixed seed.
    public typealias NoiseField = @Sendable (Double, Double, Double) -> Double

    /// The text this formula was read from.
    public let source: String

    /// The free names in the formula, in the order parsing met them. Hand
    /// ``value(_:noise:)-([Double],_)`` the numbers in this order.
    public let variables: [String]

    let tree: Node

    /// Read a formula, letting it name its own variables. Any name that is not
    /// a constant or a function becomes a variable, so nothing is refused for
    /// being unknown: `Formula("a * b")` reports `["a", "b"]`.
    ///
    /// That also means a misspelling becomes a variable rather than an error.
    /// Where the names are known ahead of time, the other initializer refuses
    /// one that is not on the list.
    public init(_ source: String) throws {
        try self.init(source, variables: nil)
    }

    /// Read a formula against a known list of names. A name outside the list is
    /// refused, and the message says what was available, which is what a typed
    /// formula wants. The order of `variables` is kept, so the numbers handed
    /// to ``value(_:noise:)-([Double],_)`` line up with the list you gave.
    public init(_ source: String, variables: [String]) throws {
        try self.init(source, variables: Optional(variables))
    }

    private init(_ source: String, variables declared: [String]?) throws {
        var parser = FormulaParser(tokens: try formulaTokens(source), declared: declared)
        let tree = try parser.parse()
        self.source = source
        self.tree = tree
        self.variables = declared ?? parser.discovered
    }

    /// Evaluate against the numbers for ``variables``, in that order. A missing
    /// number reads as zero.
    public func value(_ values: [Double] = [], noise: NoiseField? = nil) -> Double {
        tree.value(values, noise ?? Formula.sharedNoise)
    }

    /// Evaluate against numbers looked up by name. A name the formula wants but
    /// the dictionary does not carry reads as zero.
    public func value(_ values: [String: Double], noise: NoiseField? = nil) -> Double {
        value(variables.map { values[$0] ?? 0 }, noise: noise)
    }

    /// Whether anything in here reads a noise field, so a caller can say
    /// whether it needs to supply one.
    public var usesNoise: Bool { tree.usesNoise }

    public var description: String { source }

    /// The field a formula reads when the caller supplies none. Fixed seed, so
    /// a formula with no sketch behind it is still reproducible.
    private static let sharedNoise: NoiseField = {
        let field = PerlinNoise(seed: 0)
        return { x, y, z in field.signedValue(x, y, z) }
    }()
}

extension Formula: Equatable {
    /// Two formulas are the same when they were read from the same text against
    /// the same names. The tree is a consequence of those two.
    public static func == (lhs: Formula, rhs: Formula) -> Bool {
        lhs.source == rhs.source && lhs.variables == rhs.variables
    }
}

// MARK: - Errors

/// What went wrong while reading a formula, and where. `offset` counts
/// characters from the start of the text, so a surface can point at the spot.
public struct FormulaError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public let offset: Int

    public var description: String { "\(message) (at character \(offset + 1))" }
}

// MARK: - Tokens

struct FormulaToken: Equatable {
    enum Kind: Equatable {
        case number(Double)
        case name(String)
        case symbol(String)
    }
    let kind: Kind
    /// Where the token starts in the source text.
    let offset: Int
}

/// Split the text into tokens. Two spellings need care. A number may carry an
/// exponent (`1e3`), and `e` is also the name of a constant, so the exponent is
/// only taken when a digit follows it. A dot inside a name (`center.x`) belongs
/// to the name, because a parameter's part is named that way.
func formulaTokens(_ source: String) throws -> [FormulaToken] {
    var tokens: [FormulaToken] = []
    let characters = Array(source)
    var i = 0

    func peek(_ offset: Int) -> Character? {
        let index = i + offset
        return index >= 0 && index < characters.count ? characters[index] : nil
    }

    while i < characters.count {
        let c = characters[i]
        let start = i

        if c.isWhitespace { i += 1; continue }

        if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
            var text = ""
            while let d = peek(0), d.isNumber || d == "." {
                text.append(d)
                i += 1
            }
            // An exponent, but only when it really is one: `2e3` is a number
            // and `2*e` is a number times a constant.
            if let d = peek(0), d == "e" || d == "E" {
                let signed = peek(1) == "+" || peek(1) == "-"
                let digit = peek(signed ? 2 : 1)
                if digit?.isNumber == true {
                    text.append("e")
                    i += 1
                    if signed { text.append(characters[i]); i += 1 }
                    while let d = peek(0), d.isNumber { text.append(d); i += 1 }
                }
            }
            guard let value = Double(text) else {
                throw FormulaError(message: "'\(text)' is not a number", offset: start)
            }
            tokens.append(FormulaToken(kind: .number(value), offset: start))
            continue
        }

        if c.isLetter || c == "_" {
            var text = ""
            while let d = peek(0) {
                if d.isLetter || d.isNumber || d == "_" {
                    text.append(d)
                    i += 1
                    continue
                }
                // A dot joins a parameter to one of its parts, so `center.x` is one
                // name and not three tokens. A dot with no name after it is
                // left where it is, and reads as an error there.
                if d == ".", let next = peek(1), next.isLetter || next == "_" {
                    text.append(d)
                    i += 1
                    continue
                }
                break
            }
            tokens.append(FormulaToken(kind: .name(text), offset: start))
            continue
        }

        // Two-character operators first, so `<=` never reads as `<` then `=`.
        let two = String([c, peek(1) ?? " "])
        switch two {
        case "<=", ">=", "==", "!=", "&&", "||":
            tokens.append(FormulaToken(kind: .symbol(two), offset: start))
            i += 2
            continue
        default: break
        }

        switch c {
        case "+", "-", "*", "/", "%", "^", "<", ">", "!", "(", ")", ",":
            tokens.append(FormulaToken(kind: .symbol(String(c)), offset: start))
        case "=":
            // A lone `=` is a comparison here; there is nothing to assign to.
            tokens.append(FormulaToken(kind: .symbol("=="), offset: start))
        case "&":
            tokens.append(FormulaToken(kind: .symbol("&&"), offset: start))
        case "|":
            tokens.append(FormulaToken(kind: .symbol("||"), offset: start))
        default:
            throw FormulaError(message: "'\(c)' has no meaning in a formula", offset: start)
        }
        i += 1
    }
    return tokens
}

// MARK: - The tree

indirect enum FormulaNode: Sendable {
    case number(Double)
    /// A variable, already resolved to its position in the values handed over.
    case variable(Int)
    case negate(FormulaNode)
    case not(FormulaNode)
    case binary(FormulaOperator, FormulaNode, FormulaNode)
    case call(FormulaFunction, [FormulaNode])
}

extension Formula { typealias Node = FormulaNode }

enum FormulaOperator: Sendable {
    case add, subtract, multiply, divide, remainder, power
    case less, lessEqual, greater, greaterEqual, equal, notEqual
    case and, or
}

extension FormulaNode {
    var usesNoise: Bool {
        switch self {
        case .number, .variable: return false
        case .negate(let e), .not(let e): return e.usesNoise
        case .binary(_, let l, let r): return l.usesNoise || r.usesNoise
        case .call(let f, let a): return f.readsNoise || a.contains(where: \.usesNoise)
        }
    }

    func value(_ values: [Double], _ noise: Formula.NoiseField) -> Double {
        switch self {
        case .number(let v):
            return v
        case .variable(let index):
            return index < values.count ? values[index] : 0
        case .negate(let e):
            return -e.value(values, noise)
        case .not(let e):
            return FormulaNode.isTrue(e.value(values, noise)) ? 0 : 1
        case .call(let function, let arguments):
            // `if` picks a branch, so only the branch it picks is evaluated.
            if function == .if, arguments.count == 3 {
                let condition = FormulaNode.isTrue(arguments[0].value(values, noise))
                return arguments[condition ? 1 : 2].value(values, noise)
            }
            return function.apply(arguments.map { $0.value(values, noise) }, noise)
        case .binary(let op, let l, let r):
            let a = l.value(values, noise)
            switch op {
            // Short-circuit, so `x != 0 && 1 / x > 2` behaves the way it reads.
            case .and:
                guard FormulaNode.isTrue(a) else { return 0 }
                return FormulaNode.isTrue(r.value(values, noise)) ? 1 : 0
            case .or:
                if FormulaNode.isTrue(a) { return 1 }
                return FormulaNode.isTrue(r.value(values, noise)) ? 1 : 0
            default: break
            }
            let b = r.value(values, noise)
            switch op {
            case .add: return a + b
            case .subtract: return a - b
            case .multiply: return a * b
            case .divide: return a / b
            case .remainder: return FormulaFunction.floorMod(a, b)
            case .power: return Foundation.pow(a, b)
            case .less: return a < b ? 1 : 0
            case .lessEqual: return a <= b ? 1 : 0
            case .greater: return a > b ? 1 : 0
            case .greaterEqual: return a >= b ? 1 : 0
            case .equal: return a == b ? 1 : 0
            case .notEqual: return a != b ? 1 : 0
            case .and, .or: return 0   // handled above
            }
        }
    }

    /// A condition holds when it is neither zero nor undefined. The
    /// not-a-number guard matters: `NaN != 0` is true in floating point, so a
    /// condition that divided by zero somewhere would otherwise read as *met*.
    static func isTrue(_ value: Double) -> Bool {
        !value.isNaN && value != 0
    }
}

// MARK: - Functions and constants

enum FormulaFunction: String, Sendable, CaseIterable {
    case sin, cos, tan, asin, acos, atan, sinh, cosh, tanh
    case atan2
    case abs, sign, floor, ceil, round, trunc, fract
    case sqrt, exp, log, log2, log10, pow, hypot
    case radians, degrees, saturate
    case min, max
    case mod, step
    case clamp, lerp, mix, smoothstep
    case map
    case `if`
    case noise, signedNoise

    /// How many arguments the function takes. `nil` above means "no ceiling",
    /// which only `min` and `max` use.
    var arity: (least: Int, most: Int?) {
        switch self {
        case .atan2, .pow, .hypot, .mod, .step: return (2, 2)
        case .clamp, .lerp, .mix, .smoothstep, .if: return (3, 3)
        case .map: return (5, 5)
        case .min, .max: return (2, nil)
        case .noise, .signedNoise: return (1, 3)
        default: return (1, 1)
        }
    }

    var readsNoise: Bool { self == .noise || self == .signedNoise }

    /// The floored remainder, the one that wraps a phase the way a picture
    /// wants: `mod(-1, 3)` is `2`, not `-1`. It matches `fract` and the shader
    /// vocabulary, and it is deliberately *not* Swift's `%`.
    static func floorMod(_ a: Double, _ b: Double) -> Double {
        guard b != 0 else { return .nan }
        return a - b * (a / b).rounded(.down)
    }

    func apply(_ a: [Double], _ noise: Formula.NoiseField) -> Double {
        func at(_ i: Int) -> Double { i < a.count ? a[i] : 0 }
        let x = at(0)
        switch self {
        case .sin: return Foundation.sin(x)
        case .cos: return Foundation.cos(x)
        case .tan: return Foundation.tan(x)
        case .asin: return Foundation.asin(x)
        case .acos: return Foundation.acos(x)
        case .atan: return Foundation.atan(x)
        case .sinh: return Foundation.sinh(x)
        case .cosh: return Foundation.cosh(x)
        case .tanh: return Foundation.tanh(x)
        case .atan2: return Foundation.atan2(x, at(1))
        case .abs: return Swift.abs(x)
        case .sign: return x > 0 ? 1 : (x < 0 ? -1 : 0)
        case .floor: return x.rounded(.down)
        case .ceil: return x.rounded(.up)
        case .round: return x.rounded()
        case .trunc: return x.rounded(.towardZero)
        case .fract: return x - x.rounded(.down)
        case .sqrt: return Foundation.sqrt(x)
        case .exp: return Foundation.exp(x)
        case .log: return Foundation.log(x)
        case .log2: return Foundation.log2(x)
        case .log10: return Foundation.log10(x)
        case .pow: return Foundation.pow(x, at(1))
        case .hypot: return Foundation.hypot(x, at(1))
        case .radians: return x * .pi / 180
        case .degrees: return x * 180 / .pi
        case .saturate: return Swift.min(Swift.max(x, 0), 1)
        case .min: return a.min() ?? 0
        case .max: return a.max() ?? 0
        case .mod: return FormulaFunction.floorMod(x, at(1))
        case .step: return at(1) < x ? 0 : 1
        case .clamp: return Swift.min(Swift.max(x, at(1)), at(2))
        case .lerp, .mix: return x + (at(1) - x) * at(2)
        case .smoothstep: return Ollin.smoothstep(x, at(1), at(2))
        case .map: return Ollin.map(x, at(1), at(2), at(3), at(4))
        case .if: return FormulaNode.isTrue(x) ? at(1) : at(2)   // handled in the tree
        case .noise: return (noise(x, at(1), at(2)) + 1) / 2
        case .signedNoise: return noise(x, at(1), at(2))
        }
    }
}

/// The names that are always a number, never a variable.
let formulaConstants: [String: Double] = [
    "pi": .pi,
    "tau": .pi * 2,
    "e": Foundation.exp(1.0),
]

// MARK: - Parser

/// Recursive descent over the ordinary arithmetic precedence table, loosest
/// rule first.
///
/// The one place the table earns a note: exponentiation binds *tighter* than
/// unary minus, so `-2^2` is `-4` and not `4`, and it associates to the right,
/// so `2^3^2` is `2^9`. That is what a calculator does and what a person
/// writing a formula expects. (Ollin's other small language, the one a
/// parametric L-system's productions are written in, binds unary tighter,
/// because the published formalism there says so. The two do not have to
/// agree, and they do not.)
struct FormulaParser {
    private let tokens: [FormulaToken]
    private var index = 0
    /// The names allowed, or `nil` to let any name become a variable.
    private let declared: [String]?
    /// The variables met, in order, when the names are not declared ahead.
    private(set) var discovered: [String] = []

    init(tokens: [FormulaToken], declared: [String]?) {
        self.tokens = tokens
        self.declared = declared
    }

    /// Parse one whole formula and insist that nothing is left over.
    mutating func parse() throws -> FormulaNode {
        guard !tokens.isEmpty else {
            throw FormulaError(message: "a formula cannot be empty", offset: 0)
        }
        let node = try expression()
        if index < tokens.count {
            throw FormulaError(message: "there is more here than one formula",
                               offset: tokens[index].offset)
        }
        return node
    }

    // MARK: Grammar

    private mutating func expression() throws -> FormulaNode { try or() }

    private mutating func or() throws -> FormulaNode {
        var left = try and()
        while match("||") { left = .binary(.or, left, try and()) }
        return left
    }

    private mutating func and() throws -> FormulaNode {
        var left = try equality()
        while match("&&") { left = .binary(.and, left, try equality()) }
        return left
    }

    private mutating func equality() throws -> FormulaNode {
        var left = try relational()
        while true {
            if match("==") { left = .binary(.equal, left, try relational()) }
            else if match("!=") { left = .binary(.notEqual, left, try relational()) }
            else { return left }
        }
    }

    private mutating func relational() throws -> FormulaNode {
        var left = try additive()
        while true {
            if match("<=") { left = .binary(.lessEqual, left, try additive()) }
            else if match(">=") { left = .binary(.greaterEqual, left, try additive()) }
            else if match("<") { left = .binary(.less, left, try additive()) }
            else if match(">") { left = .binary(.greater, left, try additive()) }
            else { return left }
        }
    }

    private mutating func additive() throws -> FormulaNode {
        var left = try multiplicative()
        while true {
            if match("+") { left = .binary(.add, left, try multiplicative()) }
            else if match("-") { left = .binary(.subtract, left, try multiplicative()) }
            else { return left }
        }
    }

    private mutating func multiplicative() throws -> FormulaNode {
        var left = try unary()
        while true {
            if match("*") { left = .binary(.multiply, left, try unary()) }
            else if match("/") { left = .binary(.divide, left, try unary()) }
            else if match("%") { left = .binary(.remainder, left, try unary()) }
            else { return left }
        }
    }

    /// Unary minus sits *above* exponentiation, so `-2^2` reads as `-(2^2)`.
    private mutating func unary() throws -> FormulaNode {
        if match("-") { return .negate(try unary()) }
        if match("+") { return try unary() }
        if match("!") { return .not(try unary()) }
        return try power()
    }

    /// Right-associative, and its right operand may itself be unary, so `2^-1`
    /// reads and `2^3^2` is `2^(3^2)`.
    private mutating func power() throws -> FormulaNode {
        let left = try primary()
        guard match("^") else { return left }
        return .binary(.power, left, try unary())
    }

    private mutating func primary() throws -> FormulaNode {
        guard index < tokens.count else {
            throw FormulaError(message: "a formula stops early",
                               offset: tokens.last.map { $0.offset + 1 } ?? 0)
        }
        let token = tokens[index]
        index += 1

        switch token.kind {
        case .number(let value):
            return .number(value)

        case .name(let name):
            if case .symbol("(")? = peek()?.kind {
                guard let function = FormulaFunction(rawValue: name) else {
                    throw FormulaError(message: "'\(name)' is not a function", offset: token.offset)
                }
                index += 1
                var arguments: [FormulaNode] = []
                if case .symbol(")")? = peek()?.kind {
                    index += 1
                } else {
                    repeat { arguments.append(try expression()) } while match(",")
                    guard match(")") else {
                        throw FormulaError(message: "'\(name)(' is never closed", offset: token.offset)
                    }
                }
                let arity = function.arity
                guard arguments.count >= arity.least,
                      arity.most.map({ arguments.count <= $0 }) ?? true else {
                    throw FormulaError(message: "\(name) takes \(FormulaParser.say(arity)), "
                                       + "not \(arguments.count)", offset: token.offset)
                }
                return .call(function, arguments)
            }
            if let value = formulaConstants[name] { return .number(value) }
            if let declared {
                guard let position = declared.firstIndex(of: name) else {
                    let available = declared.isEmpty
                        ? "this formula reads no values"
                        : "the values here are \(declared.joined(separator: ", "))"
                    throw FormulaError(message: "'\(name)' is not a value or a function; \(available)",
                                       offset: token.offset)
                }
                return .variable(position)
            }
            if let position = discovered.firstIndex(of: name) { return .variable(position) }
            discovered.append(name)
            return .variable(discovered.count - 1)

        case .symbol("("):
            let inner = try expression()
            guard match(")") else {
                throw FormulaError(message: "a '(' is never closed", offset: token.offset)
            }
            return inner

        case .symbol(let s):
            throw FormulaError(message: "'\(s)' cannot start a formula", offset: token.offset)
        }
    }

    private static func say(_ arity: (least: Int, most: Int?)) -> String {
        guard let most = arity.most else { return "\(arity.least) arguments or more" }
        if most == arity.least { return "\(most) argument\(most == 1 ? "" : "s")" }
        return "\(arity.least) to \(most) arguments"
    }

    // MARK: Cursor

    private func peek() -> FormulaToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func match(_ symbol: String) -> Bool {
        guard case .symbol(let s)? = peek()?.kind, s == symbol else { return false }
        index += 1
        return true
    }
}
