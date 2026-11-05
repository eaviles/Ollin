@testable import Ollin
import Foundation
import Testing

/// One ray query to a fragment. A tracing helper that makes a query of its own
/// adds one to every function it is compiled into, once for each place it is
/// called from, and a lit fragment gathers every helper: the lit mesh fragments
/// came to forty-one queries in one function, which a GPU that traces in
/// software stops on, where the passes holding one to ten traced the same
/// scene. So a helper takes its caller's query, and only a fragment makes one.
///
/// This reads the shader sources, so it runs anywhere and draws nothing.
@Suite
struct RayQueryCountTests {
    /// Where one file's ray queries are declared: the function each sits in.
    private func queryDeclarations(in name: String) throws -> [(function: String, line: Int)] {
        let url = try #require(OllinResources.bundle.url(forResource: name, withExtension: "metal"))
        let source = try String(contentsOf: url, encoding: .utf8)
        var found: [(String, Int)] = []
        var function = ""
        for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let first = line.first
            // A function's signature starts in the first column; its body is indented.
            if let first, first != " ", first != "\t", first != "/", first != "#", first != "}",
               line.contains("(") {
                function = String(line)
            }
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasSuffix(";"), !text.hasPrefix("//"), !text.hasPrefix("typedef") else { continue }
            let declares = text.hasPrefix("OllinRayQuery ")
                || (text.hasPrefix("intersection_query<") && !text.contains("("))
            if declares { found.append((function, index + 1)) }
        }
        return found
    }

    /// The files the lit fragments are compiled from. In them a query is made
    /// by a fragment, with one exception: the shadow ray with a query of its
    /// own, which the traced export's kernel calls.
    @Test(arguments: ["Shader3D", "ShaderRaymarch", "ShaderCombine"])
    func onlyAFragmentMakesARayQuery(file: String) throws {
        let declarations = try queryDeclarations(in: file)
        #expect(!declarations.isEmpty, "\(file).metal declares no ray query, so this test reads nothing")
        for declaration in declarations {
            let inFragment = declaration.function.hasPrefix("fragment ")
            let isTheShadowRayOfItsOwn = file == "Shader3D"
                && declaration.function.hasPrefix("static inline float traceShadowRay(")
            #expect(inFragment || isTheShadowRayOfItsOwn,
                    "\(file).metal:\(declaration.line) makes a ray query in a helper: take the caller's instead (\(declaration.function.prefix(70)))")
        }
    }

    /// Each fragment makes exactly one.
    @Test func aFragmentMakesOne() throws {
        for file in ["Shader3D", "ShaderRaymarch", "ShaderCombine"] {
            var perFunction: [String: Int] = [:]
            for declaration in try queryDeclarations(in: file) where declaration.function.hasPrefix("fragment ") {
                perFunction[declaration.function, default: 0] += 1
            }
            for (function, count) in perFunction {
                #expect(count == 1, "\(function.prefix(70)) makes \(count) ray queries")
            }
        }
    }
}
