import Foundation

/// One example sketch discovered under `Examples/`.
struct Example: Identifiable, Hashable {
    let id: String          // the Sketch.swift path (unique)
    let name: String        // leaf folder, e.g. "HelloCircle"
    let category: String    // top-level folder, e.g. "Motion", "3D"
    let subgroup: String?   // one level deeper, e.g. "Raymarching" under 3D
    let sketchPath: String
    /// Whether the sketch reads the keyboard (detected from its source), so the
    /// gallery can offer the click-to-focus hint only where keys actually matter.
    let usesKeyboard: Bool

    /// Flat label: prefixes the group for nested entries (used by `--list`).
    var displayName: String { subgroup.map { "\($0) · \(name)" } ?? name }
}

enum ExampleCatalog {
    /// Scan the `Examples/` tree (relative to the working directory; run from the
    /// repo root, like OllinLive) for every `…/Sketch.swift`. Reads source, not
    /// `.build`, so renamed/removed examples never linger.
    ///
    /// Layout: `Examples/<Category>/<Name>/Sketch.swift`, with large categories
    /// grouped one deeper: `Examples/<Category>/<Group>/<Name>/Sketch.swift`
    /// (`3D/` by topic, `Recreations/` by artist).
    static func discover(root: String = "Examples") -> [Example] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        guard let walker = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var examples: [Example] = []
        for case let url as URL in walker {
            // `Examples/` is its own package, so its build tree sits inside the
            // directory being walked. Descending into it is slow and can surface
            // a `Sketch.swift` belonging to a checkout rather than to an example.
            if url.lastPathComponent == ".build" {
                walker.skipDescendants()
                continue
            }
            guard url.lastPathComponent == "Sketch.swift" else { continue }
            let parts = url.pathComponents
            guard let examplesIndex = parts.lastIndex(of: root) else { continue }
            let relative = Array(parts[(examplesIndex + 1)...])   // [Category, (Group,) Name, "Sketch.swift"]
            guard relative.count >= 3 else { continue }           // need at least Category/Name/Sketch.swift
            examples.append(Example(
                id: url.path,
                name: relative[relative.count - 2],
                category: relative[0],
                subgroup: relative.count >= 4 ? relative[relative.count - 3] : nil,
                sketchPath: url.path,
                usesKeyboard: sourceReadsKeyboard(at: url.path)))
        }
        return examples.sorted { ($0.category, $0.displayName) < ($1.category, $1.displayName) }
    }

    /// Whether the sketch's source touches the keyboard surface (the press
    /// hooks, the held-key polls, or the key identity reads). The gallery keeps
    /// keyboard focus on the example list by default, so this decides which
    /// sketches show the "click to use the keyboard" hint.
    private static func sourceReadsKeyboard(at path: String) -> Bool {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return source.range(
            of: #"\b(keyPressed|keyReleased|keyIsPressed|isKeyDown|keyCode)\b"#,
            options: .regularExpression) != nil
    }

    // MARK: Sidebar tree

    /// A top-level category with its direct examples and nested groups, in the
    /// order the sidebar shows them: groups after direct entries, both sorted.
    struct Category: Identifiable, Hashable {
        struct Group: Identifiable, Hashable {
            let name: String
            let examples: [Example]
            var id: String { name }
        }

        let name: String
        let direct: [Example]     // examples right under the category
        let groups: [Group]       // one-deeper groups (3D topics, Recreations artists)
        var id: String { name }
        var count: Int { direct.count + groups.reduce(0) { $0 + $1.examples.count } }
    }

    /// The category → group → example tree the sidebar renders. Input order is
    /// preserved (the catalog is already sorted by category, then group · name).
    static func tree(of examples: [Example]) -> [Category] {
        categories(of: examples).map { name in
            let inCategory = examples.filter { $0.category == name }
            var groupNames: [String] = []
            var seen = Set<String>()
            for example in inCategory {
                if let group = example.subgroup, seen.insert(group).inserted {
                    groupNames.append(group)
                }
            }
            return Category(
                name: name,
                direct: inCategory.filter { $0.subgroup == nil },
                groups: groupNames.map { group in
                    Category.Group(name: group,
                                   examples: inCategory.filter { $0.subgroup == group })
                })
        }
    }

    /// Categories in first-seen order (catalog is already sorted by category).
    static func categories(of examples: [Example]) -> [String] {
        var seen = Set<String>()
        return examples.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    /// Print the catalog grouped by category and group; backs `--list`.
    static func printCatalog(_ examples: [Example]) {
        for category in tree(of: examples) {
            print(category.name)
            for example in category.direct {
                print("  \(example.name)")
            }
            for group in category.groups {
                print("  \(group.name)")
                for example in group.examples {
                    print("    \(example.name)")
                }
            }
        }
    }
}
