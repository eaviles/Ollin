import Foundation

/// Starting from an example rather than a template.
///
/// The examples are the largest, best-maintained body of Ollin code there is,
/// and every one of them is a working sketch. Copying one into a new project
/// gives a starting point nobody had to write twice, and the copy is yours to
/// cut apart, which is the difference between this and reading one in place.
///
/// What comes across is the whole file: its header comment (which for a ported
/// or homage sketch carries the credit, and must stay with it), its parameters,
/// and its own structure. What changes is the type name and, if you asked for
/// more, the imports.
public enum ExampleSource {

    /// One example that can be started from.
    public struct Example: Sendable, Hashable, Identifiable, Comparable {
        /// Path inside the examples folder, e.g. `Motion/Breathing`.
        public var id: String { path }
        public let path: String
        /// The folder the sketch and its material live in.
        public let directory: URL
        /// The modules it imports beyond the core.
        public let modules: [String]
        /// Files beside the sketch that it loads.
        public let resources: [String]

        /// The last path component, e.g. `Breathing`.
        public var name: String { String(path.split(separator: "/").last ?? "") }
        /// Everything before that, e.g. `Motion`.
        public var group: String {
            path.split(separator: "/").dropLast().joined(separator: "/")
        }

        public static func < (a: Example, b: Example) -> Bool { a.path < b.path }
    }

    /// Every example under `folder` (the repository's `Examples` directory),
    /// in path order so two runs agree.
    public static func discover(in folder: URL) -> [Example] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(at: folder,
                                              includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles]) else { return [] }

        // Compared as path components after resolving symlinks: a folder handed
        // in as /var/... walks out as /private/var/..., and a string prefix test
        // then matches nothing at all.
        let rootParts = folder.resolvingSymlinksInPath().standardized.pathComponents

        var found: [Example] = []
        for case let url as URL in walker where url.lastPathComponent == "Sketch.swift" {
            let directory = url.deletingLastPathComponent()
            let parts = directory.resolvingSymlinksInPath().standardized.pathComponents
            guard parts.count > rootParts.count,
                  Array(parts.prefix(rootParts.count)) == rootParts else { continue }
            let path = parts.dropFirst(rootParts.count).joined(separator: "/")
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let siblings = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
            found.append(Example(
                path: path,
                directory: directory,
                modules: modules(in: source),
                resources: siblings.filter { $0 != "Sketch.swift" && !$0.hasPrefix(".") }.sorted()
            ))
        }
        return found.sorted()
    }

    public static func named(_ path: String, in folder: URL) -> Example? {
        discover(in: folder).first { $0.path.lowercased() == path.lowercased() }
    }

    /// Every satellite module a sketch imports: the ones the catalog knows in
    /// its own order, then anything else alphabetically, so a manifest reads the
    /// same way every time.
    ///
    /// Deliberately **not** filtered to the capability catalog. A sketch's
    /// `import` lines are copied verbatim, so a module dropped here would be
    /// imported by the copy and missing from its manifest, and the new project
    /// would not compile. That is exactly what would happen the first time a
    /// satellite ships without a `Capability` entry, so the catalog is treated
    /// as an ordering, never as a filter.
    static func modules(in source: String) -> [String] {
        let imported = Set(source.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { return nil }
            let module = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
            return module.hasPrefix("Ollin") && module != "Ollin" ? module : nil
        })
        let known = Capability.satellites.compactMap(\.module).filter { imported.contains($0) }
        let unknown = imported.subtracting(known).sorted()
        return known + unknown
    }

    /// The example's source with its type renamed after the new project.
    ///
    /// The name is replaced everywhere it appears as a whole word, not just at
    /// the declaration, because a sketch may well name its own type inside
    /// itself, and a half-renamed file does not compile.
    public static func renamed(_ source: String, to typeName: String) -> String {
        guard let old = className(in: source), old != typeName else { return source }
        return replacingWholeWord(old, with: typeName, in: source)
    }

    /// The sketch's own type name, read off its declaration.
    static func className(in source: String) -> String? {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("class"), trimmed.contains(": Sketch") else { continue }
            guard let afterClass = trimmed.range(of: "class ") else { continue }
            let rest = trimmed[afterClass.upperBound...]
            let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { return String(name) }
        }
        return nil
    }

    static func replacingWholeWord(_ word: String, with replacement: String, in text: String) -> String {
        func isIdentifier(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }
        var out = ""
        var rest = Substring(text)
        while let found = rest.range(of: word) {
            let before = found.lowerBound > rest.startIndex
                ? rest[rest.index(before: found.lowerBound)] : nil
            let after = found.upperBound < rest.endIndex ? rest[found.upperBound] : nil
            out += rest[rest.startIndex ..< found.lowerBound]
            let bounded = !(before.map(isIdentifier) ?? false) && !(after.map(isIdentifier) ?? false)
            out += bounded ? replacement : word
            rest = rest[found.upperBound...]
        }
        return out + rest
    }
}
