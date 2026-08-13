import Foundation

// The small arithmetic language a parametric L-system's productions are written
// in: the parameters of a module combined with numbers, operators, and a handful
// of functions, evaluated once per module per rewriting pass.
//
// Two pieces of the published formalism are easy to get wrong and are pinned
// here. Exponentiation binds *tighter* than multiplication and associates to the
// right, so `2^3^2` is `2^9`; and unary minus binds tighter still, so `-2^2` is
// `(-2)^2 = 4`. Neither matches C, and reaching for C's table out of habit is
// silently wrong rather than a parse error.
//
// Names are resolved while parsing, not while evaluating: a formal parameter
// becomes its position in the predecessor's list and a constant becomes its
// value, so evaluating a production touches no dictionary at all.

// MARK: - Errors

/// What went wrong while reading a production. Carried on the system as text
/// rather than thrown, so a bad rule costs that rule and not the sketch.
struct LSystemParseError: Error {
    let message: String
}

// MARK: - Tokens

enum LSystemToken: Equatable {
    case number(Double)
    case name(String)
    case symbol(String)     // an operator or a bracket, in its canonical spelling
}

/// Split an expression into tokens. Only ever called on the text *inside* a
/// module's parentheses, so `+` here is always addition and never a turn.
func lSystemTokens(_ source: Substring) throws -> [LSystemToken] {
    var tokens: [LSystemToken] = []
    let characters = Array(source)
    var i = 0

    func peek(_ offset: Int) -> Character? {
        let index = i + offset
        return index < characters.count ? characters[index] : nil
    }

    while i < characters.count {
        let c = characters[i]

        if c.isWhitespace { i += 1; continue }

        // A number, which may open with a decimal point: the published grammars
        // write `F(s+.1, ...)` as well as `0.25`.
        if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
            var text = ""
            while let d = peek(0), d.isNumber || d == "." {
                text.append(d)
                i += 1
            }
            guard let value = Double(text) else {
                throw LSystemParseError(message: "'\(text)' is not a number")
            }
            tokens.append(.number(value))
            continue
        }

        if c.isLetter || c == "_" {
            var text = ""
            while let d = peek(0), d.isLetter || d.isNumber || d == "_" {
                text.append(d)
                i += 1
            }
            tokens.append(.name(text))
            continue
        }

        // Two-character operators first, so `<=` never reads as `<` then `=`.
        // The book spells and/or/equality `&`, `|`, `=` and the reference
        // implementation spells them `&&`, `||`, `==`; both are accepted, since
        // this language has no assignment for a bare `=` to be confused with.
        let two = String([c, peek(1) ?? " "])
        switch two {
        case "<=", ">=", "==", "!=", "&&", "||":
            tokens.append(.symbol(two)); i += 2; continue
        case "<>":
            tokens.append(.symbol("!=")); i += 2; continue
        default: break
        }

        switch c {
        case "+", "-", "*", "/", "%", "^", "<", ">", "!", "(", ")", ",":
            tokens.append(.symbol(String(c)))
        case "=":
            tokens.append(.symbol("=="))
        case "&":
            tokens.append(.symbol("&&"))
        case "|":
            tokens.append(.symbol("||"))
        default:
            throw LSystemParseError(message: "'\(c)' has no meaning in an expression")
        }
        i += 1
    }
    return tokens
}

// MARK: - The tree

indirect enum LSystemExpression: Sendable {
    case number(Double)
    /// A formal parameter, already resolved to its position in the predecessor.
    case parameter(Int)
    case negate(LSystemExpression)
    case not(LSystemExpression)
    case binary(LSystemBinaryOperator, LSystemExpression, LSystemExpression)
    case call(LSystemFunction, LSystemExpression)
}

enum LSystemBinaryOperator: Sendable {
    case add, subtract, multiply, divide, remainder, power
    case less, lessEqual, greater, greaterEqual, equal, notEqual
    case and, or
}

enum LSystemFunction: String, Sendable, CaseIterable {
    case sin, cos, tan, asin, acos, atan
    case floor, ceil, trunc, abs, exp, log, sqrt, sign
    /// Uniform in `[0, x)`, the one function that reads the random source.
    case ran
}

extension LSystemExpression {
    /// Whether anything in here draws on the random source, so a system can say
    /// whether it needs one.
    var usesRandom: Bool {
        switch self {
        case .number, .parameter: return false
        case .negate(let e), .not(let e): return e.usesRandom
        case .binary(_, let l, let r): return l.usesRandom || r.usesRandom
        case .call(let f, let e): return f == .ran || e.usesRandom
        }
    }

    /// Evaluate against the actual parameters bound to the module being
    /// rewritten. Relational and logical results are 0 or 1, as the formalism
    /// specifies.
    func value<R: RandomNumberGenerator>(_ arguments: [Double], using rng: inout R) -> Double {
        switch self {
        case .number(let v):
            return v
        case .parameter(let index):
            return index < arguments.count ? arguments[index] : 0
        case .negate(let e):
            return -e.value(arguments, using: &rng)
        case .not(let e):
            return LSystemExpression.isTrue(e.value(arguments, using: &rng)) ? 0 : 1
        case .call(let function, let e):
            return function.apply(e.value(arguments, using: &rng), using: &rng)
        case .binary(let op, let l, let r):
            let a = l.value(arguments, using: &rng)
            switch op {
            // Short-circuit, so `x != 0 && 1/x > 2` behaves the way it reads.
            case .and:
                guard LSystemExpression.isTrue(a) else { return 0 }
                return LSystemExpression.isTrue(r.value(arguments, using: &rng)) ? 1 : 0
            case .or:
                if LSystemExpression.isTrue(a) { return 1 }
                return LSystemExpression.isTrue(r.value(arguments, using: &rng)) ? 1 : 0
            default: break
            }
            let b = r.value(arguments, using: &rng)
            switch op {
            case .add: return a + b
            case .subtract: return a - b
            case .multiply: return a * b
            case .divide: return a / b
            case .remainder: return a.truncatingRemainder(dividingBy: b)
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

    /// A condition holds when its value is neither zero nor undefined. The
    /// not-a-number guard matters: `NaN != 0` is true in floating point, so a
    /// condition that divided by zero somewhere would otherwise read as *met*.
    static func isTrue(_ value: Double) -> Bool {
        !value.isNaN && value != 0
    }
}

extension LSystemFunction {
    func apply<R: RandomNumberGenerator>(_ x: Double, using rng: inout R) -> Double {
        switch self {
        case .sin: return Foundation.sin(x)
        case .cos: return Foundation.cos(x)
        case .tan: return Foundation.tan(x)
        case .asin: return Foundation.asin(x)
        case .acos: return Foundation.acos(x)
        case .atan: return Foundation.atan(x)
        case .floor: return x.rounded(.down)
        case .ceil: return x.rounded(.up)
        case .trunc: return x.rounded(.towardZero)
        case .abs: return Swift.abs(x)
        case .exp: return Foundation.exp(x)
        case .log: return Foundation.log(x)
        case .sqrt: return Foundation.sqrt(x)
        case .sign: return x > 0 ? 1 : (x < 0 ? -1 : 0)
        case .ran: return Double.random(in: 0 ..< 1, using: &rng) * x
        }
    }
}

// MARK: - Parser

/// Recursive descent over the published precedence table, loosest rule first.
struct LSystemExpressionParser {
    private let tokens: [LSystemToken]
    private var index = 0
    /// The predecessor's formal parameters, in order; a name found here becomes
    /// its position.
    private let parameters: [String]
    private let constants: [String: Double]

    init(tokens: [LSystemToken], parameters: [String], constants: [String: Double]) {
        self.tokens = tokens
        self.parameters = parameters
        self.constants = constants
    }

    /// Parse one whole expression and insist that nothing is left over.
    static func parse(_ source: Substring, parameters: [String],
                      constants: [String: Double]) throws -> LSystemExpression {
        var parser = LSystemExpressionParser(tokens: try lSystemTokens(source),
                                             parameters: parameters, constants: constants)
        let expression = try parser.expression()
        guard parser.index == parser.tokens.count else {
            throw LSystemParseError(message: "'\(source)' has more in it than one expression")
        }
        return expression
    }

    /// Split `source` on top-level commas and parse each piece, which is how a
    /// module's parameter list is read.
    static func parseList(_ source: Substring, parameters: [String],
                          constants: [String: Double]) throws -> [LSystemExpression] {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [] }
        var pieces: [Substring] = []
        var depth = 0
        var start = source.startIndex
        var i = source.startIndex
        while i < source.endIndex {
            switch source[i] {
            case "(": depth += 1
            case ")": depth -= 1
            case "," where depth == 0:
                pieces.append(source[start ..< i])
                start = source.index(after: i)
            default: break
            }
            i = source.index(after: i)
        }
        pieces.append(source[start ..< source.endIndex])
        return try pieces.map { try parse($0, parameters: parameters, constants: constants) }
    }

    // MARK: Grammar

    private mutating func expression() throws -> LSystemExpression { try or() }

    private mutating func or() throws -> LSystemExpression {
        var left = try and()
        while match("||") { left = .binary(.or, left, try and()) }
        return left
    }

    private mutating func and() throws -> LSystemExpression {
        var left = try equality()
        while match("&&") { left = .binary(.and, left, try equality()) }
        return left
    }

    private mutating func equality() throws -> LSystemExpression {
        var left = try relational()
        while true {
            if match("==") { left = .binary(.equal, left, try relational()) }
            else if match("!=") { left = .binary(.notEqual, left, try relational()) }
            else { return left }
        }
    }

    private mutating func relational() throws -> LSystemExpression {
        var left = try additive()
        while true {
            if match("<=") { left = .binary(.lessEqual, left, try additive()) }
            else if match(">=") { left = .binary(.greaterEqual, left, try additive()) }
            else if match("<") { left = .binary(.less, left, try additive()) }
            else if match(">") { left = .binary(.greater, left, try additive()) }
            else { return left }
        }
    }

    private mutating func additive() throws -> LSystemExpression {
        var left = try multiplicative()
        while true {
            if match("+") { left = .binary(.add, left, try multiplicative()) }
            else if match("-") { left = .binary(.subtract, left, try multiplicative()) }
            else { return left }
        }
    }

    private mutating func multiplicative() throws -> LSystemExpression {
        var left = try power()
        while true {
            if match("*") { left = .binary(.multiply, left, try power()) }
            else if match("/") { left = .binary(.divide, left, try power()) }
            else if match("%") { left = .binary(.remainder, left, try power()) }
            else { return left }
        }
    }

    /// Exponentiation sits above multiplication and associates to the right, so
    /// the right operand is another power and `2^3^2` reads as `2^(3^2)`.
    private mutating func power() throws -> LSystemExpression {
        let left = try unary()
        guard match("^") else { return left }
        return .binary(.power, left, try power())
    }

    /// Unary minus and negation bind tighter than exponentiation, so `-2^2` is
    /// `(-2)^2`. That is the table's own ordering, not C's.
    private mutating func unary() throws -> LSystemExpression {
        if match("-") { return .negate(try unary()) }
        if match("!") { return .not(try unary()) }
        return try primary()
    }

    private mutating func primary() throws -> LSystemExpression {
        guard index < tokens.count else {
            throw LSystemParseError(message: "an expression stops early")
        }
        let token = tokens[index]
        index += 1

        switch token {
        case .number(let value):
            return .number(value)

        case .name(let name):
            // A function is a name followed by an open parenthesis; a formal
            // parameter shadows a constant of the same spelling.
            if case .symbol("(")? = peek(), let function = LSystemFunction(rawValue: name) {
                index += 1
                let argument = try expression()
                guard match(")") else {
                    throw LSystemParseError(message: "'\(name)(' is never closed")
                }
                return .call(function, argument)
            }
            if let position = parameters.firstIndex(of: name) { return .parameter(position) }
            if let value = constants[name] { return .number(value) }
            throw LSystemParseError(message: "'\(name)' is not a parameter of this rule, a constant, or a function")

        case .symbol("("):
            let inner = try expression()
            guard match(")") else {
                throw LSystemParseError(message: "a '(' is never closed")
            }
            return inner

        case .symbol(let s):
            throw LSystemParseError(message: "'\(s)' cannot start an expression")
        }
    }

    // MARK: Cursor

    private func peek() -> LSystemToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func match(_ symbol: String) -> Bool {
        guard case .symbol(let s)? = peek(), s == symbol else { return false }
        index += 1
        return true
    }
}
