import Foundation

/// One function found in a shader source: where its name, its parameter list,
/// and its body sit in the token stream. A forward declaration has no body.
package struct ShaderFunction {
    package var name: String
    package var nameIndex: Int
    package var openParen: Int
    package var closeParen: Int
    package var openBrace: Int?
    package var closeBrace: Int?

    package var isDefinition: Bool { openBrace != nil }
}

package enum ShaderScan {

    /// Finds every function declared at file scope.
    ///
    /// A definition reads as `type name ( … ) {` and a declaration ends in `;`
    /// instead. Only file scope is searched, because a name in a parameter list or
    /// inside a body is not a function being declared, and both sit at a depth
    /// this walk keeps count of. Qualifier words ahead of the type (`static`,
    /// `inline`) do not matter: the walk tries every identifier as the type.
    package static func functions(in tokens: [ShaderToken]) -> [ShaderFunction] {
        var found: [ShaderFunction] = []
        var braceDepth = 0
        var parenDepth = 0
        var i = 0

        while i < tokens.count {
            let t = tokens[i]
            if let b = t.bracket {
                switch b {
                case "{": braceDepth += 1
                case "}": braceDepth = max(0, braceDepth - 1)
                case "(": parenDepth += 1
                case ")": parenDepth = max(0, parenDepth - 1)
                default: break
                }
            }

            guard braceDepth == 0, parenDepth == 0, t.kind == .identifier else { i += 1; continue }

            // `type name (` with both names at file scope.
            guard let nameIndex = tokens.nextSignificant(from: i + 1),
                  tokens[nameIndex].kind == .identifier,
                  let parenIndex = tokens.nextSignificant(from: nameIndex + 1),
                  tokens[parenIndex].bracket == "(",
                  let closeParen = tokens.matchingBracket(from: parenIndex)
            else { i += 1; continue }

            var fn = ShaderFunction(name: tokens[nameIndex].text, nameIndex: nameIndex,
                                    openParen: parenIndex, closeParen: closeParen)
            if let after = tokens.nextSignificant(from: closeParen + 1), tokens[after].bracket == "{",
               let closeBrace = tokens.matchingBracket(from: after) {
                fn.openBrace = after
                fn.closeBrace = closeBrace
                found.append(fn)
                i = closeBrace + 1
                continue
            }
            if let after = tokens.nextSignificant(from: closeParen + 1), tokens[after].text == ";" {
                found.append(fn)
                i = after + 1
                continue
            }
            i += 1
        }
        return found
    }

    /// Every struct declared in the source. Knowing these names is what lets a
    /// construction call be told apart from an ordinary function call, which the
    /// two languages spell differently.
    package static func structNames(in tokens: [ShaderToken]) -> Set<String> {
        var names: Set<String> = []
        for (i, t) in tokens.enumerated() where t.kind == .identifier && t.text == "struct" {
            if let n = tokens.nextSignificant(from: i + 1), tokens[n].kind == .identifier {
                names.insert(tokens[n].text)
            }
        }
        return names
    }

    /// The names called from inside a token range. A name counts as called when an
    /// opening parenthesis follows it, which is what a call looks like once types
    /// and constructions are known separately.
    package static func callsMade(in tokens: [ShaderToken], range: Range<Int>) -> Set<String> {
        var called: Set<String> = []
        for i in range where tokens[i].kind == .identifier {
            if let next = tokens.nextSignificant(from: i + 1), tokens[next].bracket == "(" {
                called.insert(tokens[i].text)
            }
        }
        return called
    }
}
