import Foundation

/// A Swift package the new sketch could join, rather than one it brings with it.
///
/// A folder of sketches is usually one package with a target per sketch, not a
/// package per sketch: that way the framework builds once and each sketch is a
/// one-file compile. So when the chosen folder already sits inside a package,
/// making another self-contained one is nearly always the wrong answer, and the
/// generator should offer to add the sketch to the package that is already
/// there.
///
/// Read, never guessed: the manifest is parsed only as far as needed to answer
/// three questions (what is it called, does it already reach Ollin, and where
/// does the target list end), and anything it cannot answer confidently means
/// the manifest is left alone.
public struct PackageHost: Sendable, Hashable {
    /// The `Package.swift` itself.
    public let manifest: URL
    /// The package's own name, as declared.
    public let name: String
    /// Whether it already depends on Ollin. Without that, a target added here
    /// could not import the framework, so there is nothing useful to add.
    public let linksOllin: Bool

    public var root: URL { manifest.deletingLastPathComponent() }

    public init(manifest: URL, name: String, linksOllin: Bool) {
        self.manifest = manifest
        self.name = name
        self.linksOllin = linksOllin
    }

    /// The nearest package at or above `folder`, which is the one a sketch put
    /// there would belong to.
    public static func nearest(from folder: URL, limit: Int = 12) -> PackageHost? {
        var directory = folder.standardized
        for _ in 0 ..< limit {
            let manifest = directory.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8) {
                return PackageHost(manifest: manifest,
                                   name: packageName(in: text) ?? directory.lastPathComponent,
                                   linksOllin: dependsOnOllin(in: text))
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    /// Where `folder` sits relative to the package root, e.g. `2026/08`, which
    /// is what a target's `path:` has to say.
    public func relativePath(of folder: URL) -> String {
        // Tried twice on purpose. Symlink resolution only applies to parts of a
        // path that exist, so a folder about to be created can keep a `/private`
        // prefix that its own parent has already lost, and comparing one
        // resolved path against one unresolved one matches nothing.
        if let relative = Self.relative(of: folder.resolvingSymlinksInPath().standardized,
                                        to: root.resolvingSymlinksInPath().standardized) {
            return relative
        }
        return Self.relative(of: folder.standardized, to: root.standardized) ?? ""
    }

    private static func relative(of folder: URL, to root: URL) -> String? {
        let rootParts = root.pathComponents
        let parts = folder.pathComponents
        guard parts.count >= rootParts.count,
              Array(parts.prefix(rootParts.count)) == rootParts else { return nil }
        return parts.dropFirst(rootParts.count).joined(separator: "/")
    }

    // MARK: - Reading the manifest

    static func packageName(in text: String) -> String? {
        guard let range = text.range(of: "Package(") else { return nil }
        let rest = text[range.upperBound...]
        guard let nameRange = rest.range(of: "name:") else { return nil }
        let afterName = rest[nameRange.upperBound...]
        guard let open = afterName.firstIndex(of: "\""),
              let close = afterName[afterName.index(after: open)...].firstIndex(of: "\"") else { return nil }
        return String(afterName[afterName.index(after: open) ..< close])
    }

    /// Any dependency naming Ollin: a path to the folder, or its git URL.
    static func dependsOnOllin(in text: String) -> Bool {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(".package(") else { continue }
            if trimmed.contains("Ollin") { return true }
        }
        return false
    }

    /// Insert `stanza` at the end of the manifest's `targets:` array.
    ///
    /// Returns nil when the array cannot be found unambiguously, which is the
    /// signal to leave the file alone and hand the stanza over to be pasted:
    /// a manifest is someone's own code, and a half-understood edit to it is
    /// worse than no edit.
    public static func inserting(_ stanza: String, intoTargetsOf text: String) -> String? {
        guard let targets = text.range(of: "targets:") else { return nil }
        guard let open = text[targets.upperBound...].firstIndex(of: "[") else { return nil }

        // Walk the array to its own closing bracket, so a nested one (a target's
        // `dependencies:` list, say) cannot be mistaken for the end.
        var depth = 0
        var index = open
        var close: String.Index?
        while index < text.endIndex {
            let character = text[index]
            if character == "[" { depth += 1 }
            if character == "]" {
                depth -= 1
                if depth == 0 { close = index; break }
            }
            index = text.index(after: index)
        }
        guard let close else { return nil }

        // Insert after the last entry rather than immediately before the closing
        // bracket, so the file's own indentation of that closing line survives.
        let body = text[text.index(after: open) ..< close]
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text.replacingCharacters(in: close ..< close, with: "\n" + stanza + "\n")
        }
        var end = close
        while end > open, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }
        return text.replacingCharacters(in: end ..< end, with: "\n" + stanza)
    }
}
