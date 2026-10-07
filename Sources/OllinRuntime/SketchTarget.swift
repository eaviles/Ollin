import Foundation

/// The SwiftPM target a sketch file sits in, read from the manifest of the
/// package around it.
///
/// A sketch that outgrows one file keeps its helpers beside it in the target's
/// folder, and the package build compiles them together. A live compile of the
/// one file named would not find them (`cannot find 'breath' in scope`), so a
/// host that runs what a person names compiles the whole target instead: every
/// `.swift` file the package build compiles, under the target's Swift settings,
/// with its declared resources where `Bundle.module` looks. A file in no
/// package, or in none of a package's target folders, is a loose file and
/// compiles alone, which is what keeps a folder of independent sketches (each
/// with its own `@main`) working.
///
/// The manifest is read through `swift package dump-package`, which evaluates
/// `Package.swift` and nothing else: no dependency is fetched or resolved. It
/// runs with a scratch folder of its own, because SwiftPM locks a package's
/// `.build` for as long as a build runs there, and a read sharing that folder
/// waited the whole build out (32 s behind a `swift build`, measured; 0.25 s
/// with its own folder). A package's read is kept until its `Package.swift`
/// changes, so a compile after the first costs a `stat`.
package struct SketchTarget: Sendable, Equatable {
    /// The folder holding `Package.swift`.
    package let packageRoot: String
    package let name: String
    /// The target's own folder.
    package let directory: String
    /// What the manifest leaves out of the target (`exclude:`).
    package let excluded: [String]
    /// The files and folders the manifest names as the sources (`sources:`),
    /// or `nil` when it names none and the whole folder is compiled.
    package let declaredSources: [String]?
    package let resources: [Resource]
    package let settings: [Setting]
    /// The language mode the package asks for (its `swiftLanguageModes`, or
    /// what its tools version implies); a target's own setting overrides it.
    package let packageLanguageMode: String
    /// Everything the target depends on by name: the framework's products,
    /// other targets, other packages' products.
    package let dependencies: [String]

    /// A resource rule from the manifest.
    package struct Resource: Sendable, Equatable {
        package enum Rule: String, Sendable {
            /// Flattened into the bundle: a folder's files land at its top.
            case process
            /// Copied as it is: a folder keeps its name and its insides.
            case copy
            /// Compiled into the code as bytes; nothing reaches the bundle.
            case embedInCode
        }
        package let rule: Rule
        package let path: String
    }

    /// A Swift setting from the manifest, with the condition it applies under.
    package struct Setting: Sendable, Equatable {
        /// The setting's name as the manifest spells it (`define`,
        /// `swiftLanguageMode`, `enableUpcomingFeature`, …).
        package let kind: String
        package let values: [String]
        /// `debug` or `release` when the setting applies to one of them.
        package let configuration: String?
        /// The platforms it applies on; empty applies on every platform.
        package let platforms: [String]
    }

    // MARK: - Finding the target

    /// The target whose folder holds `file`, or `nil` when the file is in no
    /// package or in none of its targets' folders. Throws when there is a
    /// package and its manifest cannot be read: a broken `Package.swift`
    /// would break the package build too, and compiling the one file instead
    /// would trade that message for a wrong one.
    package static func containing(file: String) throws(ManifestError) -> SketchTarget? {
        let path = resolved(file)
        guard let root = packageRoot(above: (path as NSString).deletingLastPathComponent) else {
            return nil
        }
        let targets = try Manifest.read(root: root).targets
        return targets
            .filter { $0.holds(path) }
            .max { $0.directory.count < $1.directory.count }
    }

    /// Whether `path` is one of this target's files: inside its folder, not
    /// under anything the manifest excludes, and inside what it names as its
    /// sources when it names any.
    package func holds(_ path: String) -> Bool {
        guard Self.isInside(path, directory) else { return false }
        if excluded.contains(where: { Self.isInside(path, $0) }) { return false }
        if let declaredSources {
            return declaredSources.contains { Self.isInside(path, $0) }
        }
        return true
    }

    /// The nearest folder at or above `folder` holding a `Package.swift`.
    package static func packageRoot(above folder: String) -> String? {
        var dir = folder
        while true {
            let manifest = (dir as NSString).appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest) { return dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return nil }
            dir = parent
        }
    }

    // MARK: - What it compiles

    /// Every `.swift` file the package build compiles for this target, sorted,
    /// walked fresh on each call so a file added since the last compile joins
    /// the next one. Hidden files and folders are skipped as SwiftPM skips
    /// them, and so is anything excluded or declared a resource.
    ///
    /// A `main.swift` is left out. It is the package build's entry point, and
    /// a live compile is a library whose entry point is the host's own: its
    /// top-level code does not compile there, and what it starts, the host
    /// starts instead.
    package func swiftSources() -> [String] {
        let roots = declaredSources ?? [directory]
        let skipped = excluded + resources.map(\.path)
        var found = Set<String>()
        let fm = FileManager.default
        for root in roots where !skipped.contains(where: { Self.isInside(root, $0) }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                if Self.isSwiftSource(root) { found.insert(root) }
                continue
            }
            guard let walk = fm.enumerator(
                at: URL(fileURLWithPath: root, isDirectory: true),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walk {
                // Built from the resolved folder, so already in its spelling.
                let path = url.path
                if skipped.contains(where: { Self.isInside(path, $0) }) {
                    walk.skipDescendants()
                    continue
                }
                if Self.isSwiftSource(path) { found.insert(path) }
            }
        }
        return found.sorted()
    }

    private static func isSwiftSource(_ path: String) -> Bool {
        (path as NSString).pathExtension == "swift"
            && (path as NSString).lastPathComponent != "main.swift"
    }

    /// The compiler flags the target's settings ask for, the way the package
    /// build passes them: its language mode, its defines, its upcoming and
    /// experimental features, its default isolation, strict memory safety, and
    /// its own unsafe flags. A setting conditioned on another platform is left
    /// out, and one conditioned on a configuration applies to the matching
    /// compile: `debug` to the plain one, `release` to the optimized one. C
    /// and linker settings are not the sketch compile's to carry.
    package func compilerFlags(debug: Bool) -> [String] {
        let applying = settings.filter { setting in
            if let configuration = setting.configuration,
               configuration != (debug ? "debug" : "release") { return false }
            return setting.platforms.isEmpty || setting.platforms.contains("macos")
        }
        let mode = applying.last { $0.kind == "swiftLanguageMode" }?.values.first
            ?? packageLanguageMode
        var flags = ["-swift-version", mode]
        for setting in applying {
            switch setting.kind {
            case "define":
                flags += setting.values.prefix(1).map { "-D\($0)" }
            case "enableUpcomingFeature":
                flags += setting.values.prefix(1).flatMap { ["-enable-upcoming-feature", $0] }
            case "enableExperimentalFeature":
                flags += setting.values.prefix(1).flatMap { ["-enable-experimental-feature", $0] }
            case "defaultIsolation":
                // The manifest spells nonisolated as no actor at all.
                let actor = setting.values.first ?? ""
                flags += ["-default-isolation", actor.isEmpty ? "nonisolated" : actor]
            case "strictMemorySafety":
                flags.append("-strict-memory-safety")
            case "unsafeFlags":
                flags += setting.values
            default:
                break
            }
        }
        return flags
    }

    /// Whether the manifest declares anything for the bundle. A target that
    /// declares nothing keeps the loose file's lenient bundle, the sketch's
    /// own folder, so a picture sitting beside the sketch loads as it always
    /// has.
    package var declaresBundledResources: Bool {
        resources.contains { $0.rule != .embedInCode }
    }

    /// Lay the declared resources out in `folder` as the package build lays
    /// them out in the bundle, as links back to the files: a processed folder
    /// flattened to its files (a `.lproj` folder kept whole, since the bundle
    /// reads it that way), a processed file at the top, a copied folder or
    /// file kept whole under its own name. A name taken twice keeps the
    /// first, where the package build refuses to build. Links rather than
    /// copies, so a picture edited in place reaches the running sketch the
    /// next time `setup()` loads it.
    package func linkResources(into folder: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        func link(_ source: String) throws {
            let destination = (folder as NSString)
                .appendingPathComponent((source as NSString).lastPathComponent)
            guard !fm.fileExists(atPath: destination) else { return }
            try fm.createSymbolicLink(atPath: destination, withDestinationPath: source)
        }
        for resource in resources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resource.path, isDirectory: &isDir) else { continue }
            switch resource.rule {
            case .embedInCode:
                continue
            case .copy:
                try link(resource.path)
            case .process where !isDir.boolValue:
                try link(resource.path)
            case .process:
                guard let walk = fm.enumerator(
                    at: URL(fileURLWithPath: resource.path, isDirectory: true),
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]) else { continue }
                for case let url as URL in walk {
                    let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                        .isDirectory ?? false
                    if isFolder {
                        if url.pathExtension == "lproj" {
                            try link(url.path)
                            walk.skipDescendants()
                        }
                        continue
                    }
                    try link(url.path)
                }
            }
        }
    }

    // MARK: - Paths

    /// `path`, absolute, with `..` and symbolic links resolved, so two
    /// spellings of one file compare equal (`/tmp` is `/private/tmp`).
    /// `realpath` rather than Foundation's resolver, which strips a leading
    /// `/private` where the folder walk keeps it, so the same file would come
    /// back spelled two ways and compile twice. A path that does not exist (an
    /// excluded folder nobody made) keeps its missing tail on the resolved
    /// form of the part that does.
    package static func resolved(_ path: String) -> String {
        let absolute = (path as NSString).isAbsolutePath
            ? path
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
        var head = (absolute as NSString).standardizingPath
        var tail: [String] = []
        while true {
            if let real = realpath(head, nil) {
                defer { free(real) }
                return tail.reversed().reduce(String(cString: real)) {
                    ($0 as NSString).appendingPathComponent($1)
                }
            }
            let parent = (head as NSString).deletingLastPathComponent
            if parent == head || parent.isEmpty { return (absolute as NSString).standardizingPath }
            tail.append((head as NSString).lastPathComponent)
            head = parent
        }
    }

    /// Whether `path` is `folder` or inside it, by whole path components.
    package static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}

// MARK: - The manifest

/// Why a package's `Package.swift` could not be read, with SwiftPM's own
/// words when it had any.
package struct ManifestError: Error, CustomStringConvertible, Sendable {
    package let packageRoot: String
    package let message: String

    package var description: String {
        let manifest = (packageRoot as NSString).appendingPathComponent("Package.swift")
        return "\(manifest) could not be read:\n\(message)"
    }
}

extension SketchTarget {
    /// The targets of one package, from its manifest.
    package struct Manifest: Sendable {
        package let root: String
        /// The package's source-bearing targets (regular and executable);
        /// tests, plugins, macros, and binaries are not anything a sketch
        /// host runs.
        package let targets: [SketchTarget]

        /// The package at `root`, read once and kept until its `Package.swift`
        /// changes.
        package static func read(root: String) throws(ManifestError) -> Manifest {
            let manifestPath = (root as NSString).appendingPathComponent("Package.swift")
            let stamp = (try? FileManager.default.attributesOfItem(atPath: manifestPath))?[.modificationDate] as? Date
            return try cache.manifest(root: root, stamp: stamp) { () throws(ManifestError) in
                let scratch = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("OllinRuntime-manifest")
                let result = SketchLoader.run("/usr/bin/xcrun", [
                    "swift", "package", "--package-path", root,
                    "--scratch-path", scratch, "dump-package",
                ])
                guard result.status == 0 else {
                    let log = result.stderr.isEmpty ? result.stdout : result.stderr
                    throw ManifestError(packageRoot: root,
                                        message: log.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return try parse(Data(result.stdout.utf8), root: root)
            }
        }

        private static let cache = ManifestCache()

        /// The manifest from `dump-package`'s JSON. Read loosely, key by key,
        /// so a field a later SwiftPM adds or reshapes costs that field and
        /// never the read.
        package static func parse(_ data: Data, root: String) throws(ManifestError) -> Manifest {
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let json = object as? [String: Any] else {
                throw ManifestError(packageRoot: root, message: "SwiftPM's description of it was not JSON")
            }
            let mode = languageMode(
                listed: json["swiftLanguageVersions"] as? [String],
                toolsVersion: (json["toolsVersion"] as? [String: Any])?["_version"] as? String)
            let targets = (json["targets"] as? [[String: Any]] ?? []).compactMap {
                target(from: $0, root: root, languageMode: mode)
            }
            return Manifest(root: root, targets: targets)
        }

        /// The language mode the package build would use: the newest one the
        /// package lists that this compiler has, else the one its tools
        /// version implies (6 from tools 6.0 on, 5 before).
        static func languageMode(listed: [String]?, toolsVersion: String?) -> String {
            let known = ["4", "4.2", "5", "6"]
            if let listed, let newest = listed.filter(known.contains)
                .max(by: { (Double($0) ?? 0) < (Double($1) ?? 0) }) {
                return newest
            }
            let major = toolsVersion.flatMap { Int($0.split(separator: ".").first ?? "") } ?? 5
            return major >= 6 ? "6" : "5"
        }

        private static func target(from json: [String: Any], root: String,
                                   languageMode: String) -> SketchTarget? {
            guard let name = json["name"] as? String,
                  let type = json["type"] as? String,
                  type == "regular" || type == "executable" else { return nil }
            let path = json["path"] as? String ?? defaultPath(for: name, root: root)
            let directory = SketchTarget.resolved((path as NSString).isAbsolutePath
                ? path : (root as NSString).appendingPathComponent(path))
            func inside(_ relative: String) -> String {
                SketchTarget.resolved((directory as NSString).appendingPathComponent(relative))
            }
            let resources: [Resource] = (json["resources"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let path = entry["path"] as? String,
                      let rule = (entry["rule"] as? [String: Any])?.keys.first,
                      let kind = Resource.Rule(rawValue: rule) else { return nil }
                return Resource(rule: kind, path: inside(path))
            }
            let settings: [Setting] = (json["settings"] as? [[String: Any]] ?? []).compactMap { entry in
                guard entry["tool"] as? String == "swift",
                      let kind = (entry["kind"] as? [String: Any])?.first else { return nil }
                // A value sits under `_0`: a string, a list of strings, or
                // nothing at all for a setting that is only switched on.
                let payload = (kind.value as? [String: Any])?["_0"]
                let values = payload as? [String] ?? (payload as? String).map { [$0] } ?? []
                let condition = entry["condition"] as? [String: Any]
                return Setting(kind: kind.key, values: values,
                               configuration: condition?["config"] as? String,
                               platforms: condition?["platformNames"] as? [String] ?? [])
            }
            // Each dependency is one key (`byName`, `target`, `product`)
            // over a list whose first entry is the name.
            let dependencies = (json["dependencies"] as? [[String: Any]] ?? []).compactMap {
                ($0.values.first as? [Any])?.first as? String
            }
            return SketchTarget(
                packageRoot: root, name: name, directory: directory,
                excluded: (json["exclude"] as? [String] ?? []).map(inside),
                declaredSources: (json["sources"] as? [String])?.map(inside),
                resources: resources, settings: settings,
                packageLanguageMode: languageMode, dependencies: dependencies)
        }

        /// Where SwiftPM looks for a target that names no path: its name under
        /// the first of the conventional source folders that exists.
        private static func defaultPath(for name: String, root: String) -> String {
            for folder in ["Sources", "Source", "src", "srcs"] {
                let candidate = (folder as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                let absolute = (root as NSString).appendingPathComponent(candidate)
                if FileManager.default.fileExists(atPath: absolute, isDirectory: &isDir), isDir.boolValue {
                    return candidate
                }
            }
            return ("Sources" as NSString).appendingPathComponent(name)
        }
    }
}

/// The manifests read so far, each with the modification date of the
/// `Package.swift` it came from. A lock rather than an actor because the
/// reader is the compile, which runs synchronously off the main thread; it is
/// held across the read so two compiles asking at once read the package once.
private final class ManifestCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (stamp: Date?, manifest: SketchTarget.Manifest)] = [:]

    func manifest(root: String, stamp: Date?,
                  read: () throws(ManifestError) -> SketchTarget.Manifest) throws(ManifestError)
        -> SketchTarget.Manifest {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[root], entry.stamp == stamp { return entry.manifest }
        let manifest = try read()
        entries[root] = (stamp, manifest)
        return manifest
    }
}

// MARK: - What a person named

/// The sketch file a host runs for what it was handed on its command line.
package struct SketchChoice: Sendable, Equatable {
    package let sketchPath: String
    /// A line for the person when the file run is not the one they named.
    package let note: String?

    /// The path a host's command line names and the target `--target` picks,
    /// read the same way in every host: the path is the first argument that is
    /// neither a flag nor `--target`'s own value, and none means the host runs
    /// whatever its own default is.
    package static func arguments(_ arguments: [String]) -> (path: String?, target: String?) {
        var target: String?
        var path: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--target" {
                if index + 1 < arguments.count { target = arguments[index + 1] }
                index += 2
                continue
            }
            if path == nil, !argument.hasPrefix("-") { path = argument }
            index += 1
        }
        return (path, target)
    }

    /// The file to run for `path`, as typed. A file is run as it is. A folder
    /// is a package's folder, or one inside a package, and runs the one
    /// target there whose files declare a `Sketch` subclass; with several,
    /// `target` names which. A file that declares no sketch but sits in a
    /// target that has one runs that target's sketch, so naming any file of a
    /// project runs the project.
    package static func resolve(_ path: String, target: String?) throws(LaunchError) -> SketchChoice {
        let absolute = (path as NSString).isAbsolutePath
            ? path
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absolute, isDirectory: &isDir) else {
            throw .notFound(absolute)
        }
        guard isDir.boolValue else {
            guard target == nil else { throw .targetBesideAFile }
            let text = (try? String(contentsOfFile: absolute, encoding: .utf8)) ?? ""
            if SketchLoader.sketchClassName(in: text) != nil {
                return SketchChoice(sketchPath: absolute, note: nil)
            }
            // A helper of a project: the project's sketch is what runs. A
            // manifest that cannot be read is the loader's to report.
            if let owner = try? SketchTarget.containing(file: absolute),
               let found = owner.sketch() {
                let named = (absolute as NSString).lastPathComponent
                let file = (found.file as NSString).lastPathComponent
                return SketchChoice(
                    sketchPath: found.file,
                    note: "\(named) declares no sketch, so this runs \(found.className) from \(file), "
                        + "the sketch of the target \(owner.name)")
            }
            return SketchChoice(sketchPath: absolute, note: nil)
        }

        let folder = SketchTarget.resolved(absolute)
        guard let root = SketchTarget.packageRoot(above: folder) else {
            throw .noPackage(absolute)
        }
        let manifest: SketchTarget.Manifest
        do {
            manifest = try SketchTarget.Manifest.read(root: root)
        } catch {
            throw .manifest(error)
        }
        let sketches = manifest.targets
            .filter { SketchTarget.isInside($0.directory, folder) || SketchTarget.isInside(folder, $0.directory) }
            .compactMap { owner in owner.sketch().map { (target: owner, found: $0) } }
            .sorted { $0.target.name < $1.target.name }
        let names = sketches.map(\.target.name)
        if let target {
            guard let chosen = sketches.first(where: { $0.target.name == target }) else {
                throw .unknownTarget(target, among: names)
            }
            return SketchChoice(sketchPath: chosen.found.file, note: nil)
        }
        switch sketches.count {
        case 0: throw .noSketch(absolute, packageRoot: root)
        case 1: return SketchChoice(sketchPath: sketches[0].found.file, note: nil)
        default: throw .several(absolute, names: names)
        }
    }
}

/// Why a host could not find a sketch to run in what it was handed, in words
/// for the terminal.
package enum LaunchError: Error, CustomStringConvertible, Sendable, Equatable {
    case notFound(String)
    case noPackage(String)
    case manifest(ManifestError)
    case noSketch(String, packageRoot: String)
    case several(String, names: [String])
    case unknownTarget(String, among: [String])
    case targetBesideAFile

    package var description: String {
        switch self {
        case .notFound(let path):
            return "nothing at \(path)"
        case .noPackage(let folder):
            return "\(folder) is a folder with no Package.swift in it or above it; "
                + "name a sketch file, or the folder of a package"
        case .manifest(let error):
            return error.description
        case .noSketch(let folder, let root):
            let manifest = (root as NSString).appendingPathComponent("Package.swift")
            let place = SketchTarget.resolved(folder) == SketchTarget.resolved(root) ? "" : " under \(folder)"
            return "no target of \(manifest)\(place) is a sketch's: none declares a "
                + "`class …: Sketch` as what it runs"
        case .several(let folder, let names):
            return "\(folder) holds \(names.count) sketch targets; pick one with --target <name>:\n"
                + names.map { "  \($0)" }.joined(separator: "\n")
        case .unknownTarget(let name, let names):
            guard !names.isEmpty else { return "no sketch target named \(name), and none here at all" }
            return "no sketch target named \(name); the sketch targets here are:\n"
                + names.map { "  \($0)" }.joined(separator: "\n")
        case .targetBesideAFile:
            return "--target picks one of a package's sketch targets, and a file already names "
                + "its own sketch; name the package's folder with --target, or the file alone"
        }
    }
}

extension ManifestError: Equatable {}

extension SketchTarget {
    /// The file in this target that declares its sketch and the class it
    /// declares, or `nil` when the target is not a sketch's.
    ///
    /// A `Sketch` subclass marked `@main` is the sketch, so a variation kept
    /// beside it never runs in its place. With none marked, the first subclass
    /// is the sketch only when nothing else in the target is marked either (a
    /// library target the app beside it runs, or one a `main.swift` starts).
    /// A target whose `@main` is something else (an app with a sketch inside
    /// it, a host with sketches for its own tests) is that thing's, and naming
    /// one of its files is how to run its sketch live.
    package func sketch() -> (file: String, className: String)? {
        var first: (file: String, className: String)?
        var otherEntryPoints = 0
        for file in swiftSources() {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let declared = SketchDeclarations(text)
            if let marked = declared.classes.first(where: \.isMain) {
                return (file, marked.name)
            }
            otherEntryPoints += declared.mainCount
            if first == nil, let name = declared.classes.first?.name { first = (file, name) }
        }
        return otherEntryPoints == 0 ? first : nil
    }
}

/// What a file's code declares that decides what runs: its `Sketch`
/// subclasses, which of them `@main` marks, and how many `@main`s the file
/// holds in all. Read with comments and strings blanked
/// (`SourceRegions.code(in:)`), so a class a doc comment or a template string
/// names is not one the file declares.
package struct SketchDeclarations {
    package struct Declared: Sendable, Equatable {
        package let name: String
        package let isMain: Bool
    }

    package let classes: [Declared]
    package let mainCount: Int

    package init(_ source: String) {
        let code = SourceRegions.code(in: source)
        let range = NSRange(code.startIndex..., in: code)
        classes = Self.sketchClass.matches(in: code, range: range).compactMap { match in
            guard let name = Range(match.range(at: 2), in: code),
                  let prefix = Range(match.range(at: 1), in: code) else { return nil }
            let isMain = code[prefix].range(of: #"@main\b"#, options: .regularExpression) != nil
            return Declared(name: String(code[name]), isMain: isMain)
        }
        mainCount = Self.main.numberOfMatches(in: code, range: range)
    }

    /// A class whose inheritance clause names `Sketch`, with the attributes
    /// and modifiers in front of it captured so `@main` can be looked for
    /// among them.
    private static let sketchClass = try! NSRegularExpression(
        pattern: #"((?:@\w+(?:\([^)]*\))?\s+|\b(?:final|public|open|internal|package|private|fileprivate)\s+)*)\bclass\s+(\w+)\s*:\s*[^{]*\bSketch\b"#)

    private static let main = try! NSRegularExpression(pattern: #"@main\b"#)
}
