import Foundation

/// The shader helper library as a page sees it: the sections a fragment shader
/// may ask for, trimmed and translated. The sections are the ones the framework
/// marks with `OLLIN_LIB_BEGIN` / `OLLIN_LIB_END`; the unmarked preamble (the
/// Metal includes and the shared struct header) and the unmarked tail (the
/// compute-only neighbor search and attractor macros) never reach a page,
/// because a page runs no compute kernel.
package enum WebShaderLibrary {

    /// The section names, in the order the library defines them.
    package static let sectionNames = ["base", "hash", "noise", "color", "sdf", "domain", "visual"]

    /// The sections `wanted` needs, with the library's own dependencies added:
    /// `base` always, `hash` under `noise`, and both under `visual`.
    package static func closure(of wanted: Set<String>) -> Set<String> {
        var sections = wanted
        sections.insert("base")
        if sections.contains("noise") { sections.insert("hash") }
        if sections.contains("visual") { sections.insert("hash"); sections.insert("noise") }
        return sections
    }

    /// The marked sections of the Metal library text, keeping only the ones asked
    /// for. Lines outside every section are dropped.
    package static func sections(of metalText: String, wanted: Set<String>) -> String {
        let keep = closure(of: wanted)
        var out: [Substring] = []
        var current: String? = nil
        for line in metalText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// OLLIN_LIB_BEGIN ") {
                current = String(trimmed.dropFirst("// OLLIN_LIB_BEGIN ".count)).trimmingCharacters(in: .whitespaces)
                if let c = current, keep.contains(c) { out.append(line) }
                continue
            }
            if trimmed.hasPrefix("// OLLIN_LIB_END ") {
                if let c = current, keep.contains(c) { out.append(line); out.append("") }
                current = nil
                continue
            }
            if let c = current, keep.contains(c) { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    /// The wanted sections translated to GLSL ES 3.00.
    package static func translate(_ metalText: String, wanted: Set<String>) -> WebShaderTranslation {
        WebShaderTranslator.translate(sections(of: metalText, wanted: wanted))
    }

    /// Every function the text defines, by name, definitions only (a prototype
    /// counts once, where its body is). Overloads repeat the name.
    package static func definedFunctions(in text: String) -> [String] {
        let tokens = ShaderLexer.tokenize(text)
        return ShaderScan.functions(in: tokens).filter(\.isDefinition).map(\.name)
    }
}
