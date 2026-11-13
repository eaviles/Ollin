import CryptoKit
import Foundation

/// A dependency of the sketch's target, compiled for this process: the module
/// a compile imports and the library the sketch links.
package struct BuiltDependency: Sendable, Equatable {
    /// The module's name as sources import it.
    package let realName: String
    /// The name it was compiled under: the real one and a fingerprint of what
    /// went into it. See `SketchLoader.buildDependencies`.
    package let moduleName: String
    /// The folder holding its `.swiftmodule`.
    package let directory: String
    /// Its library, which the sketch's own names by this path.
    package let library: String
    /// The framework module files its compile read.
    package let frameworkModules: [String]
}

extension SketchLoader {
    // MARK: - Building what the target imports

    /// Build every module the target imports besides the ones the host
    /// carries, in the order they need each other, and return them in that
    /// order.
    ///
    /// Each is compiled by this process, from its Swift files, against the
    /// framework modules the sketch itself compiles against, into a library
    /// of its own that leaves the framework's symbols unresolved exactly as
    /// the sketch's library does. There is then one copy of the framework in
    /// the process however many libraries name it, which is the property the
    /// whole live route rests on; a library that linked a framework of its
    /// own would bring a second `Sketch`, and a cast across the two fails.
    ///
    /// **A library is built once and kept until what went into it changes.**
    /// Its name carries a fingerprint of its sources, its flags, the
    /// optimization level, and the libraries it needs in turn, and a
    /// fingerprint already built in this process is handed back without a
    /// compile. A save to the sketch therefore costs the sketch's compile
    /// and nothing more, and a save to a dependency costs that dependency,
    /// whatever depends on it, and the sketch. What follows from keeping it:
    /// the library's own stored globals live as long as the library does, so
    /// they keep their values across a save to the sketch and start over
    /// when the library itself is saved.
    ///
    /// **The module is compiled under a name of its own** (`Petals_3fa9…`),
    /// and whatever imports it is told the name through a module alias, so
    /// the sources keep writing `import Petals`. Two builds of one library
    /// are then two modules with no symbol or class in common, which is what
    /// lets the edited one load beside the one it replaces: an image cannot
    /// be unloaded once Swift code has run in it, and two images declaring
    /// one class name are a collision in the Objective-C runtime.
    func buildDependencies(of target: SketchTarget) -> Result<[BuiltDependency], LoadError> {
        // Nothing to walk for the common target, which depends on the
        // framework alone: no manifest is read and no folder is listed.
        let host = hostModules()
        guard target.links.contains(where: { $0.kind == .target || !host.contains($0.name) }) else {
            return .success([])
        }
        let order: [SketchTarget.Dependency]
        do {
            order = try target.dependencyOrder(
                carried: { host.contains($0) },
                workspace: PackageWorkspace(root: target.packageRoot))
        } catch {
            return .failure(.dependencyUnbuildable(error.description))
        }
        var built: [String: BuiltDependency] = [:]
        var list: [BuiltDependency] = []
        for dependency in order {
            let needs = dependency.needs.compactMap { built[$0] }
            switch build(dependency.target, needs: needs) {
            case .success(let one):
                built[one.realName] = one
                list.append(one)
            case .failure(let error):
                return .failure(error)
            }
        }
        return .success(list)
    }

    /// Compile one dependency, or hand back the build this process already
    /// has of the same sources.
    private func build(_ target: SketchTarget, needs: [BuiltDependency]) -> Result<BuiltDependency, LoadError> {
        let sources = target.swiftSources()
        let flags = target.compilerFlags(debug: optimization == .none)
        guard let fingerprint = Self.fingerprint(
            of: target, sources: sources, flags: flags, optimization: optimization, needs: needs) else {
            return .failure(.unreadable(target.directory))
        }
        let moduleName = "\(target.moduleName)_\(fingerprint)"
        let directory = (Self.dependencyRoot as NSString).appendingPathComponent(moduleName)
        let resources = (directory as NSString).appendingPathComponent("Resources")

        // One compile per fingerprint: a second evaluation asking for the same
        // build while the first is still compiling waits for it and takes it.
        let slot = Self.builds.slot(moduleName)
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if let known = slot.built {
            // A resource added since the build joins the bundle; the links
            // already there stay.
            if target.declaresBundledResources { try? target.linkResources(into: resources) }
            return .success(known)
        }

        let fm = FileManager.default
        try? fm.removeItem(atPath: directory)
        do {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.loadFailed("couldn't make a build folder for \(target.name): \(error)"))
        }
        var inputs = sources
        // A target that declares resources gets the `Bundle.module` the
        // package build would write for it, over its resources laid out as
        // the bundle lays them out.
        if target.declaresBundledResources {
            let accessor = (directory as NSString).appendingPathComponent("__OllinBundle.swift")
            do {
                try target.linkResources(into: resources)
                try """
                import Foundation
                extension Foundation.Bundle {
                    nonisolated static let module: Bundle = Bundle(path: "\(escapedForSwiftLiteral(resources))") ?? .main
                }
                """.write(toFile: accessor, atomically: true, encoding: .utf8)
            } catch {
                return .failure(.loadFailed("couldn't lay out the resources of \(target.name): \(error)"))
            }
            inputs.append(accessor)
        }

        let library = (directory as NSString).appendingPathComponent("lib\(moduleName).dylib")
        let trace = (directory as NSString).appendingPathComponent("modules.json")
        var args = Self.dependencyCompileArguments(
            library: library, moduleName: moduleName, directory: directory, sources: inputs,
            optimization: optimization, flags: flags, needs: needs)
        args += moduleArguments()
        args += ["-emit-loaded-module-trace-path", trace]
        let result = Self.run("/usr/bin/xcrun", args)
        guard result.status == 0 else {
            try? fm.removeItem(atPath: directory)
            let log = result.stderr.isEmpty ? result.stdout : result.stderr
            return .failure(.compileFailed(
                Self.naming(needs, in: log.trimmingCharacters(in: .whitespacesAndNewlines))))
        }
        let loaded = Self.frameworkModules(inTrace: trace, under: moduleSearchPaths())
        if let rebuilt = Self.rebuiltModule(loaded, since: launchedAt) {
            try? fm.removeItem(atPath: directory)
            return .failure(rebuilt)
        }
        let built = BuiltDependency(
            realName: target.moduleName, moduleName: moduleName, directory: directory,
            library: library, frameworkModules: loaded)
        slot.built = built
        Self.builds.countCompile()
        return .success(built)
    }

    /// How many dependencies this process has compiled. A build handed back
    /// from an earlier compile does not count, which is what a test reads to
    /// learn that a save to the sketch rebuilt nothing else.
    package static var dependencyCompileCount: Int { builds.compiles }

    /// Where this process keeps the libraries it builds, one folder each.
    private static let dependencyRoot: String = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("OllinRuntime-modules-\(getpid())")

    private static let builds = DependencyBuilds()

    /// Twelve hexadecimal digits over everything that decides what a
    /// dependency's compile produces: where it is, how it is compiled, what
    /// it is compiled against, and the text of every source. `nil` when a
    /// source cannot be read.
    static func fingerprint(of target: SketchTarget, sources: [String], flags: [String],
                            optimization: Optimization, needs: [BuiltDependency]) -> String? {
        var hasher = SHA256()
        func add(_ text: String) {
            hasher.update(data: Data(text.utf8))
            hasher.update(data: Data([0]))
        }
        add(target.packageRoot)
        add(target.name)
        add(optimization.flag)
        flags.forEach(add)
        needs.forEach { add($0.moduleName) }
        for source in sources {
            guard let text = FileManager.default.contents(atPath: source) else { return nil }
            add(source)
            hasher.update(data: text)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// The `swiftc` line a dependency's compile starts from, before the
    /// framework's module search paths. Pure, so a test can read it.
    ///
    /// It emits the module beside the library, since the next compile
    /// imports it. `-parse-as-library` because a target of one file would
    /// otherwise be read as a script. The library's install name is its own
    /// path, which is the name the sketch's library records for it, so the
    /// loader finds it when the sketch is opened with nothing set up first.
    /// `-undefined dynamic_lookup` leaves the framework's symbols to the
    /// host, as the sketch's own line does.
    static func dependencyCompileArguments(library: String, moduleName: String, directory: String,
                                           sources: [String], optimization: Optimization,
                                           flags: [String], needs: [BuiltDependency]) -> [String] {
        let module = (directory as NSString).appendingPathComponent("\(moduleName).swiftmodule")
        var args = [
            "swiftc", "-emit-library", "-o", library,
            "-emit-module", "-emit-module-path", module,
            "-module-name", moduleName, "-parse-as-library",
            optimization.flag, "-wmo",
        ]
        args += flags
        args += importArguments(needs)
        args += sources
        args += [
            "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
            "-Xlinker", "-install_name", "-Xlinker", library,
        ]
        return args
    }

    /// What a compile is handed for the dependencies it imports: where each
    /// module is, the name it was built under for the name sources write,
    /// and the library to link.
    static func importArguments(_ built: [BuiltDependency]) -> [String] {
        built.flatMap {
            ["-I", $0.directory, "-module-alias", "\($0.realName)=\($0.moduleName)", $0.library]
        }
    }

    /// `log` with each dependency's build name put back to the name its
    /// sources use, so a diagnostic that qualifies a type reads
    /// `Petals.Ring` and not the fingerprinted form.
    static func naming(_ built: [BuiltDependency], in log: String) -> String {
        built.reduce(log) { $0.replacingOccurrences(of: $1.moduleName, with: $1.realName) }
    }

    /// The names of the modules the host carries: every Swift module and C
    /// module its build folder holds, which is the framework, its libraries,
    /// and the vendored code under them. A dependency by one of these names
    /// is the host's, and is never built a second time.
    func hostModules() -> Set<String> {
        var names = Set<String>()
        for map in explicitModuleMaps() {
            names.insert(((map as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        for directory in moduleSearchPaths() {
            if let declared = moduleName(declaredIn: directory) { names.insert(declared) }
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            where (entry as NSString).pathExtension == "swiftmodule" {
                names.insert((entry as NSString).deletingPathExtension)
            }
        }
        return names
    }

    // MARK: - What a host watches and compares

    /// The targets this loader's sketch depends on, when they can be read
    /// without fetching anything; none for a loose file, and none when the
    /// graph cannot be read (the compile is what reports that).
    private func readableDependencies(of target: SketchTarget) -> [SketchTarget] {
        let host = hostModules()
        let order = try? target.dependencyOrder(
            carried: { host.contains($0) },
            workspace: PackageWorkspace(root: target.packageRoot, mayResolve: false))
        return (order ?? []).map(\.target)
    }

    /// The folders in which a save changes what this loader compiles: the
    /// sketch's own, or its target's when it sits in one, and the folder of
    /// every target it depends on that somebody could be editing. A package
    /// SwiftPM fetched is left out, since nobody edits a checkout in the
    /// build folder.
    package func watchFolders() -> [String] {
        let own = SketchTarget.resolved((sketchPath as NSString).deletingLastPathComponent)
        guard scope == .target, let target = try? SketchTarget.containing(file: sketchPath) else {
            return [own]
        }
        var folders = [target.directory]
        for dependency in readableDependencies(of: target)
        where !dependency.directory.contains("/.build/") {
            folders.append(dependency.directory)
        }
        // A folder inside another one listed is already watched.
        return folders.filter { folder in
            !folders.contains { $0 != folder && SketchTarget.isInside(folder, $0) }
        }
    }

    /// Every Swift file this loader compiles beside the sketch file: the
    /// rest of its target, and the files of the targets it depends on. What
    /// a host compares to learn that something other than the sketch's own
    /// text changed.
    package func companionSources() -> [String] {
        guard scope == .target, let target = try? SketchTarget.containing(file: sketchPath) else {
            return []
        }
        let own = SketchTarget.resolved(sketchPath)
        return target.swiftSources().filter { $0 != own }
            + readableDependencies(of: target).flatMap { $0.swiftSources() }
    }
}

/// The dependency builds of this process, one slot a fingerprint. A slot's
/// lock is held across its compile, so two compiles asking for one build run
/// it once; two different builds do not wait on each other.
private final class DependencyBuilds: @unchecked Sendable {
    final class Slot: @unchecked Sendable {
        let lock = NSLock()
        var built: BuiltDependency?
    }

    private let lock = NSLock()
    private var slots: [String: Slot] = [:]
    private var compiled = 0

    var compiles: Int {
        lock.lock()
        defer { lock.unlock() }
        return compiled
    }

    func countCompile() {
        lock.lock()
        compiled += 1
        lock.unlock()
    }

    func slot(_ name: String) -> Slot {
        lock.lock()
        defer { lock.unlock() }
        if let slot = slots[name] { return slot }
        let slot = Slot()
        slots[name] = slot
        return slot
    }
}
