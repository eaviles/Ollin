import Foundation

/// One example sketch discovered under `Examples/`.
struct Example: Identifiable, Hashable {
    let id: String          // the Sketch.swift path (unique)
    let name: String        // leaf folder, e.g. "HelloCircle"
    let category: String    // top-level folder, e.g. "Motion", "Recreations"
    let subgroup: String?   // one level deeper, e.g. "VeraMolnar" under Recreations
    let sketchPath: String

    /// Sidebar label — prefixes the artist for nested (Recreations) entries.
    var displayName: String { subgroup.map { "\($0) · \(name)" } ?? name }
}

enum ExampleCatalog {
    /// Scan the `Examples/` tree (relative to the working directory; run from the
    /// repo root, like OllinLive) for every `…/Sketch.swift`. Reads source, not
    /// `.build`, so renamed/removed examples never linger.
    ///
    /// Layout: `Examples/<Category>/<Name>/Sketch.swift`, with `Recreations/`
    /// nested one deeper: `Examples/Recreations/<Artist>/<Name>/Sketch.swift`.
    static func discover(root: String = "Examples") -> [Example] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        guard let walker = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var examples: [Example] = []
        for case let url as URL in walker where url.lastPathComponent == "Sketch.swift" {
            let parts = url.pathComponents
            guard let examplesIndex = parts.lastIndex(of: root) else { continue }
            let relative = Array(parts[(examplesIndex + 1)...])   // [Category, (Artist,) Name, "Sketch.swift"]
            guard relative.count >= 3 else { continue }           // need at least Category/Name/Sketch.swift
            examples.append(Example(
                id: url.path,
                name: relative[relative.count - 2],
                category: relative[0],
                subgroup: relative.count >= 4 ? relative[relative.count - 3] : nil,
                sketchPath: url.path))
        }
        return examples.sorted { ($0.category, $0.displayName) < ($1.category, $1.displayName) }
    }

    /// Categories in first-seen order (catalog is already sorted by category).
    static func categories(of examples: [Example]) -> [String] {
        var seen = Set<String>()
        return examples.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
