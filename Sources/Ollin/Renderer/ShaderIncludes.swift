import Foundation

/// Resolves `#include "…"` directives in Metal source by hand.
///
/// Metal's runtime compiler (`makeLibrary(source:)`) has no include search path, so a
/// quoted `#include` in shader source is an error rather than a file. Every shader
/// Ollin compiles at runtime goes through this first: the directive is read, the named
/// file is read in its place, and a `#line` directive on each side keeps the compiler
/// reporting a mistake at the file and line the author wrote it in.
///
/// It serves three callers. The built-in shader segments use it to say what they need
/// (`#include "ShaderCore.metal"` at the top of a segment), so the concatenation order
/// falls out of the declarations rather than out of a hand-kept list. A shader a sketch
/// writes for itself, and a compute kernel, use it to pull in another file, so one helper
/// is written once and read by both.
///
/// The rules:
///
/// - A file is spliced **once** per compile, however many times it is named, so a
///   diamond (two files that both include a third) does not define anything twice.
/// - A cycle is reported rather than followed, as is a chain deeper than `depthLimit`.
/// - `#include <angle>` is left exactly as it is: those are the compiler's own headers
///   (`<metal_stdlib>`, `<metal_mesh>`), and it resolves them itself.
/// - A directive that is only a comment (`// #include "x"`) is left alone.
enum ShaderIncludes {

    /// A file the resolver was able to find.
    struct Source {
        /// Identity, so the same file named two ways is still spliced once. An absolute
        /// path where there is one; the resource name where the file lives in a bundle.
        let key: String
        /// The name a diagnostic should carry. An absolute path where there is one, so
        /// the reported `file:line` is clickable.
        let name: String
        let text: String

        init(key: String, name: String, text: String) {
            self.key = key
            self.name = name
            self.text = text
        }
    }

    /// What a resolve produced.
    struct Result {
        /// The source with every quoted include replaced by the file it named.
        var source: String
        /// The files pulled in, by name, in the order they were spliced.
        var included: [String]
        /// One line per directive that could not be honored, each already carrying the
        /// including file's own `name:line:` so it reads like any other diagnostic.
        var problems: [String]
        var ok: Bool { problems.isEmpty }
    }

    /// How deep a chain of includes may go before the resolver calls it a runaway. A
    /// cycle is caught on its own, so this only bounds a pathological but acyclic nest.
    static let depthLimit = 32

    /// Resolve every quoted `#include` in `source`.
    ///
    /// - Parameters:
    ///   - source: the text to resolve.
    ///   - name: the name `source` itself should be reported under.
    ///   - startLine: the file line `source`'s first line sits on (an inline shader
    ///     starts partway down its `.swift`).
    ///   - leadingLineDirective: emit `#line startLine "name"` ahead of the result. Off
    ///     where the caller writes that directive itself (the user-shader compose does).
    ///   - rootKey: `source`'s own identity in `load`'s terms, so a file that names the
    ///     root back is caught as the cycle it is rather than read a second time.
    ///   - load: find a file by the spelling inside the quotes, given the name of the
    ///     file that asked for it. Return `nil` when there is no such file.
    static func resolve(_ source: String, name: String, startLine: Int = 1,
                        leadingLineDirective: Bool = false, rootKey: String? = nil,
                        load: (_ spelling: String, _ askedBy: String) -> Source?) -> Result {
        let head = leadingLineDirective ? lineDirective(startLine, name) + "\n" : ""
        // The common shader has no include at all, and this runs once per compiled
        // shader per frame, so leave it untouched rather than walk it line by line.
        guard source.contains("#include") else {
            return Result(source: head + source, included: [], problems: [])
        }
        var seen = Set<String>()
        var stack: [String] = []
        if let rootKey {
            seen.insert(rootKey)
            stack.append(rootKey)
        }
        var included: [String] = []
        var problems: [String] = []
        let body = expand(source, name: name, startLine: startLine, depth: 0,
                          seen: &seen, stack: &stack, included: &included,
                          problems: &problems, load: load)
        return Result(source: head + body, included: included, problems: problems)
    }

    /// Resolve several files into one compile unit, sharing what has already been
    /// spliced across all of them. A root already pulled in as somebody else's
    /// dependency is skipped, so the result holds every file exactly once and each one
    /// lands after everything it needs. That is what lets the built-in segment list
    /// carry no order: the declarations put the segments in the right sequence.
    static func resolveAll(_ roots: [Source],
                           load: (_ spelling: String, _ askedBy: String) -> Source?) -> Result {
        var seen = Set<String>()
        var stack: [String] = []
        var included: [String] = []
        var problems: [String] = []
        var parts: [String] = []
        for root in roots where !seen.contains(root.key) {
            seen.insert(root.key)
            included.append(root.name)
            stack.append(root.key)
            let body = expand(root.text, name: root.name, startLine: 1, depth: 0,
                              seen: &seen, stack: &stack, included: &included,
                              problems: &problems, load: load)
            stack.removeLast()
            parts.append(lineDirective(1, root.name))
            parts.append(body)
        }
        return Result(source: parts.joined(separator: "\n"), included: included, problems: problems)
    }

    /// A convenience over `resolve` for files on disk: a quoted spelling resolves
    /// against the folder of the file that asked for it, then against `searchPaths`.
    /// This is what a sketch's own shader gets, so `#include "noise.metal"` finds the
    /// file sitting beside it.
    static func resolveFromFilesystem(_ source: String, name: String, startLine: Int = 1,
                                      searchPaths: [String] = [],
                                      leadingLineDirective: Bool = false) -> Result {
        let rootKey = URL(fileURLWithPath: name).resolvingSymlinksInPath().path
        return resolve(source, name: name, startLine: startLine,
                leadingLineDirective: leadingLineDirective,
                rootKey: rootKey) { spelling, askedBy in
            for path in candidatePaths(for: spelling, askedBy: askedBy, searchPaths: searchPaths) {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                // Standardize the path so the same file reached two ways (a `../` detour,
                // a symlinked folder) is still spliced once.
                let key = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                    .standardizedFileURL.path
                return Source(key: key, name: key, text: text)
            }
            return nil
        }
    }

    /// Where a quoted spelling might be on disk, in the order to try.
    ///
    /// A spelling that names a place of its own (an absolute path, or one starting at
    /// the home folder) is taken as it is, which is how a shader reaches a library
    /// cloned somewhere else on the machine. Everything else is relative to the file
    /// that asked for it, then to each search path in turn. Relative is the form a
    /// library's own files use between themselves, so a chain that starts with one
    /// absolute path carries on resolving from wherever that file sits.
    private static func candidatePaths(for spelling: String, askedBy: String,
                                       searchPaths: [String]) -> [String] {
        if spelling.hasPrefix("/") { return [spelling] }
        if spelling.hasPrefix("~") { return [(spelling as NSString).expandingTildeInPath] }
        var folders = [(askedBy as NSString).deletingLastPathComponent]
        folders.append(contentsOf: searchPaths)
        return folders.filter { !$0.isEmpty }
            .map { ($0 as NSString).appendingPathComponent(spelling) }
    }

    // MARK: - The walk

    private static func expand(_ text: String, name: String, startLine: Int, depth: Int,
                               seen: inout Set<String>, stack: inout [String],
                               included: inout [String], problems: inout [String],
                               load: (String, String) -> Source?) -> String {
        var out: [String] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            guard let spelling = quotedIncludeSpelling(line) else {
                out.append(String(line))
                continue
            }
            let fileLine = startLine + index
            // Every branch below writes exactly one line in the directive's place, so a
            // file that is skipped (already in, or missing) leaves its own numbering alone.
            guard depth < depthLimit else {
                problems.append("\(name):\(fileLine): \"\(spelling)\" is nested deeper than "
                                + "\(depthLimit) includes, so it was not read.")
                out.append("")
                continue
            }
            guard let found = load(spelling, name) else {
                problems.append("\(name):\(fileLine): cannot find \"\(spelling)\".")
                out.append("")
                continue
            }
            if stack.contains(found.key) {
                problems.append("\(name):\(fileLine): \"\(spelling)\" is already open "
                                + "further up the chain, so reading it again would not end.")
                out.append("")
                continue
            }
            if seen.contains(found.key) {
                out.append("")   // already spliced: the second mention is a no-op
                continue
            }
            seen.insert(found.key)
            included.append(found.name)
            stack.append(found.key)
            let inner = expand(found.text, name: found.name, startLine: 1, depth: depth + 1,
                               seen: &seen, stack: &stack, included: &included,
                               problems: &problems, load: load)
            stack.removeLast()
            out.append(lineDirective(1, found.name))
            out.append(inner)
            out.append(lineDirective(fileLine + 1, name))
        }
        return out.joined(separator: "\n")
    }

    /// The spelling inside the quotes of a `#include "…"` line, or `nil` for any other
    /// line. An angle include and a commented-out one both read as any other line.
    private static func quotedIncludeSpelling(_ line: Substring) -> String? {
        var rest = Substring(line)
        rest = rest.drop(while: { $0 == " " || $0 == "\t" })
        guard rest.hasPrefix("#") else { return nil }
        rest = rest.dropFirst()
        rest = rest.drop(while: { $0 == " " || $0 == "\t" })
        guard rest.hasPrefix("include") else { return nil }
        rest = rest.dropFirst("include".count)
        // `#includes` is an identifier, not the directive.
        guard let next = rest.first, next == " " || next == "\t" || next == "\"" else { return nil }
        rest = rest.drop(while: { $0 == " " || $0 == "\t" })
        guard rest.hasPrefix("\"") else { return nil }
        rest = rest.dropFirst()
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let spelling = String(rest[rest.startIndex..<end])
        return spelling.isEmpty ? nil : spelling
    }

    /// A `#line` directive naming a file, with the two characters a Metal string cannot
    /// carry bare escaped (the path of a sketch can hold either).
    private static func lineDirective(_ line: Int, _ name: String) -> String {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "#line \(max(1, line)) \"\(escaped)\""
    }
}
