import Foundation

// Reading a rule and reading a word are the same problem twice: find where each
// module's letter ends and its parameter list begins. The one subtlety is that
// several characters mean one thing at module level and another inside a
// parameter list. `+` is a turn where a module may start and addition inside
// parentheses; `-` is a turn, part of the arrow, and subtraction; `,` separates
// parameters inside a list and is a module of its own outside one. So the reader
// is always in one of the two contexts and never tries to lex both at once.

extension ParametricLSystem {

    /// Read a run of modules: the axiom, or the successor of a rule. `parameters`
    /// are the names the enclosing rule's predecessor bound, and are empty for an
    /// axiom, whose numbers can only be constants.
    static func parseModules(_ source: Substring, parameters: [String],
                             constants: [String: Double]) throws -> [SuccessorModule] {
        var modules: [SuccessorModule] = []
        var i = source.startIndex

        while i < source.endIndex {
            if source[i].isWhitespace { i = source.index(after: i); continue }

            let character = source[i]
            guard character != "(" else {
                throw LSystemParseError(message: "a '(' where a module should start")
            }
            guard character != ")" else {
                throw LSystemParseError(message: "a ')' with no '(' to close")
            }
            let letter = try asciiLetter(character)
            i = source.index(after: i)

            // The published grammars space a turn from its angle, as in
            // "- (120) F(1)", so the parameter list may sit off from its letter.
            var afterLetter = i
            while afterLetter < source.endIndex, source[afterLetter].isWhitespace {
                afterLetter = source.index(after: afterLetter)
            }

            guard afterLetter < source.endIndex, source[afterLetter] == "(" else {
                modules.append(SuccessorModule(letter: letter, parameters: []))
                continue
            }

            let open = source.index(after: afterLetter)
            guard let close = matchingParenthesis(in: source, after: afterLetter) else {
                throw LSystemParseError(message: "a '(' is never closed")
            }
            let list = try LSystemExpressionParser.parseList(source[open ..< close],
                                                             parameters: parameters,
                                                             constants: constants)
            modules.append(SuccessorModule(letter: letter, parameters: list))
            i = source.index(after: close)
        }
        return modules
    }

    /// The index of the `)` that closes the `(` at `open`.
    static func matchingParenthesis(in source: Substring, after open: Substring.Index) -> Substring.Index? {
        var depth = 0
        var i = open
        while i < source.endIndex {
            switch source[i] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return i }
            default: break
            }
            i = source.index(after: i)
        }
        return nil
    }

    /// Every module letter is one ASCII character. The published alphabets are
    /// all ASCII, and holding a word of millions of modules a byte apiece is what
    /// keeps a deep expansion affordable.
    static func asciiLetter(_ character: Character) throws -> UInt8 {
        guard let ascii = character.asciiValue else {
            throw LSystemParseError(message: "'\(character)' is not an ASCII letter, so it cannot be a module")
        }
        return ascii
    }

    /// The first `index` where `character` sits outside every parameter list.
    static func indexOutsideParentheses(of character: Character, in source: Substring) -> Substring.Index? {
        var depth = 0
        var i = source.startIndex
        while i < source.endIndex {
            switch source[i] {
            case "(": depth += 1
            case ")": depth -= 1
            case character where depth == 0: return i
            default: break
            }
            i = source.index(after: i)
        }
        return nil
    }
}

extension ParametricProduction {

    /// Read one rule: `predecessor : condition -> successor : weight`, with the
    /// condition and the weight both optional.
    init(_ rule: String, constants: [String: Double]) throws {
        let (head, tail) = try ParametricProduction.splitOnArrow(Substring(rule))

        // The predecessor, and the condition that may follow it.
        var predecessorText = head
        var conditionText: Substring?
        if let colon = ParametricLSystem.indexOutsideParentheses(of: ":", in: head) {
            predecessorText = head[head.startIndex ..< colon]
            conditionText = head[head.index(after: colon)...]
        }

        let (letter, names) = try ParametricProduction.parsePredecessor(predecessorText)
        self.letter = letter
        self.arity = names.count

        // A condition written "*", or left out, always holds.
        if let conditionText {
            let trimmed = conditionText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "*" {
                self.condition = nil
            } else {
                self.condition = try LSystemExpressionParser.parse(conditionText,
                                                                   parameters: names,
                                                                   constants: constants)
            }
        } else {
            self.condition = nil
        }

        // The successor, and the weight that may follow it.
        var successorText = tail
        var weightText: Substring?
        if let colon = ParametricLSystem.indexOutsideParentheses(of: ":", in: tail) {
            successorText = tail[tail.startIndex ..< colon]
            weightText = tail[tail.index(after: colon)...]
        }

        self.successor = try ParametricLSystem.parseModules(successorText,
                                                            parameters: names,
                                                            constants: constants)
        if let weightText {
            let trimmed = weightText.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                throw LSystemParseError(message: "a ':' after the successor with no weight following it")
            }
            self.weight = try LSystemExpressionParser.parse(weightText,
                                                            parameters: names,
                                                            constants: constants)
        } else {
            self.weight = nil
        }
    }

    /// Split a rule at its arrow, which is written `->`, `-->`, or the book's
    /// own `→`. The arrow always sits outside any parameter list, and no valid
    /// condition puts a `-` immediately before a `>`, so the first one found
    /// outside parentheses is the right one.
    static func splitOnArrow(_ rule: Substring) throws -> (Substring, Substring) {
        var depth = 0
        var i = rule.startIndex
        while i < rule.endIndex {
            let character = rule[i]
            if character == "(" { depth += 1 }
            else if character == ")" { depth -= 1 }
            else if depth == 0 {
                if character == "\u{2192}" {
                    return (rule[rule.startIndex ..< i], rule[rule.index(after: i)...])
                }
                if character == "-" {
                    var j = rule.index(after: i)
                    if j < rule.endIndex, rule[j] == "-" { j = rule.index(after: j) }
                    if j < rule.endIndex, rule[j] == ">" {
                        return (rule[rule.startIndex ..< i], rule[rule.index(after: j)...])
                    }
                }
            }
            i = rule.index(after: i)
        }
        throw LSystemParseError(message: "there is no '->' in it")
    }

    /// Read `A`, `A(x)`, or `A(l, w)` into a letter and the names it binds.
    static func parsePredecessor(_ source: Substring) throws -> (UInt8, [String]) {
        var i = source.startIndex
        while i < source.endIndex, source[i].isWhitespace { i = source.index(after: i) }
        guard i < source.endIndex else {
            throw LSystemParseError(message: "there is nothing before the '->'")
        }
        let letter = try ParametricLSystem.asciiLetter(source[i])
        i = source.index(after: i)
        while i < source.endIndex, source[i].isWhitespace { i = source.index(after: i) }

        guard i < source.endIndex else { return (letter, []) }
        guard source[i] == "(" else {
            throw LSystemParseError(message: "'\(source[i])' follows the predecessor's letter; a rule rewrites one module")
        }
        guard let close = ParametricLSystem.matchingParenthesis(in: source, after: i) else {
            throw LSystemParseError(message: "the predecessor's '(' is never closed")
        }
        let inside = source[source.index(after: i) ..< close]
        var after = source.index(after: close)
        while after < source.endIndex, source[after].isWhitespace { after = source.index(after: after) }
        guard after == source.endIndex else {
            throw LSystemParseError(message: "'\(source[after...])' follows the predecessor; a rule rewrites one module")
        }

        let names = inside.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if names.count == 1 && names[0].isEmpty { return (letter, []) }

        for name in names {
            guard let first = name.first, first.isLetter || first == "_",
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                throw LSystemParseError(message: "'\(name)' is not a name a parameter can have")
            }
        }
        // The formalism forbids a name appearing twice in one predecessor, which
        // is exactly what lets a module bind to it by position with no checking.
        for (i, name) in names.enumerated() where names[..<i].contains(name) {
            throw LSystemParseError(message: "'\(name)' is named twice in the predecessor")
        }
        return (letter, names)
    }
}
