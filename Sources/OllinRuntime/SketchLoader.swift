import Foundation
import Ollin

/// Compiles a single sketch `.swift` file into a `.dylib` and loads the `Sketch`
/// instance out of it. Each `load()` produces a fresh dylib at a unique path, so
/// `dlopen` returns a new image rather than a cached one — that fresh-image swap
/// is the mechanism behind live reload, and the way the examples gallery embeds
/// a selected sketch.
///
/// It works because the host process (OllinLive or OllinExamples) and the
/// compiled dylib resolve to the *same* `Sketch`: the host links Ollin and
/// exports its symbols (`-export_dynamic`), and the dylib is compiled with
/// `-undefined dynamic_lookup` so its Ollin symbols bind to the host at load.
/// The cast across the `dlopen` boundary therefore succeeds.
public struct SketchLoader: Sendable {
    public let sketchPath: String

    public init(sketchPath: String) {
        self.sketchPath = sketchPath
    }

    public enum LoadError: Error, CustomStringConvertible, Sendable {
        case unreadable(String)
        case noSketchClass(String)
        case compileFailed(String)
        case loadFailed(String)

        public var description: String {
            switch self {
            case .unreadable(let p): return "couldn't read sketch file: \(p)"
            case .noSketchClass(let p):
                return "no `class …: Sketch` declaration found in \(p)"
            case .compileFailed(let log): return "compile failed —\n\(log)"
            case .loadFailed(let msg): return "load failed — \(msg)"
            }
        }
    }

    /// The directory holding this executable (`.build/debug` and friends). The
    /// sketch dylib is compiled against the Ollin module found from here (for
    /// type-checking only; the Ollin *symbols* resolve against this host process at
    /// load time). Where exactly the module and the C module maps sit relative to
    /// this depends on the build system; see `moduleSearchPaths()`.
    private var buildDir: String {
        (Bundle.main.executablePath! as NSString).deletingLastPathComponent
    }

    /// Compile + instantiate in one step, on the main actor. Convenience for
    /// callers already on the main thread (the initial load, the self-test); to
    /// keep the slow `swiftc` off the main thread, call `compile()` off-main and
    /// then `instantiate(dylibPath:)` on the main actor instead.
    @MainActor
    public func load() -> Result<Sketch, LoadError> {
        switch compile() {
        case .success(let dylibPath): return instantiate(dylibPath: dylibPath)
        case .failure(let error): return .failure(error)
        }
    }

    /// Compile the sketch into a fresh `.dylib` and return its path — the slow
    /// step (it shells out to `swiftc`). Safe to run **off the main thread**: it
    /// touches no main-actor state, so the host window keeps drawing the old
    /// sketch while this runs. Pair with `instantiate(dylibPath:)`.
    public func compile() -> Result<String, LoadError> {
        guard let source = try? String(contentsOfFile: sketchPath, encoding: .utf8) else {
            return .failure(.unreadable(sketchPath))
        }
        guard let className = Self.sketchClassName(in: source) else {
            return .failure(.noSketchClass(sketchPath))
        }

        // A unique token per load gives a fresh dylib *path* (so dlopen sees a
        // new image — it caches by path) and a fresh *module name* (so each
        // loaded version is a distinct mangled type; without it, every reload of
        // `HelloCircle` collides in the objc runtime and risks bad casts).
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let work = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinRuntime-\(token)")
        try? FileManager.default.createDirectory(
            atPath: work, withIntermediateDirectories: true)

        // A generated sibling file gives the dylib a stable C-ABI entry point that
        // builds the sketch — without touching (or even parsing beyond the class
        // name) the user's file. `@main` in the user file is harmless here.
        // `Sketch.init` is main-actor isolated, so the factory asserts main-actor
        // isolation (the host calls the C entry point from `instantiate`, which is
        // `@MainActor`) to construct it synchronously across the C boundary.
        let factoryPath = (work as NSString).appendingPathComponent("__OllinFactory.swift")
        // A `Bundle.module` resolving to the sketch's own folder, so a loaded
        // sketch reaches assets sitting beside it through `resource:in:.module`
        // (the per-example asset convention). A loose compile has no
        // SwiftPM-synthesized accessor, so without this `.module` doesn't even
        // compile — it binds to Ollin's *internal* one — and a font/image sketch
        // that bundles a resource can't load it. Pointed at the source directory,
        // a flat-directory `Bundle` finds the file by name.
        let sketchDir = escapedForSwiftLiteral(
            (sketchPath as NSString).deletingLastPathComponent)
        let factory = """
        import Foundation
        import Ollin
        extension Bundle {
            static let module: Bundle = Bundle(path: "\(sketchDir)") ?? .main
        }
        @_cdecl("ollin_make_sketch")
        public func ollin_make_sketch() -> UnsafeMutableRawPointer {
            MainActor.assumeIsolated {
                Unmanaged.passRetained(\(className)()).toOpaque()
            }
        }
        """
        do {
            try factory.write(toFile: factoryPath, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.loadFailed("couldn't write factory shim: \(error)"))
        }

        let dylibPath = (work as NSString).appendingPathComponent("sketch.dylib")
        // `-undefined dynamic_lookup` (and *no* `-lOllin`) leaves Ollin symbols
        // unresolved at link time so they bind to the host process at `dlopen`,
        // keeping one shared copy of `Sketch` across the boundary.
        var args = [
            "swiftc", "-emit-library", "-o", dylibPath,
            "-module-name", "OllinRuntimeSketch_\(token)",
            sketchPath, factoryPath,
            "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
        ]
        // `-I` the dirs holding `Ollin.swiftmodule` (so `import Ollin` type-checks)
        // and the C targets' clang module maps that `import Ollin` pulls in
        // (`CLibtess2` / `CClipper2` / `COllinShaders`). Discovered across both
        // build layouts; see `moduleSearchPaths()`. Without them the compile fails
        // with "no such module 'Ollin'" or "missing required modules".
        for path in moduleSearchPaths() {
            args.append(contentsOf: ["-I", path])
        }
        let result = run("/usr/bin/xcrun", args)
        guard result.status == 0 else {
            let log = result.stderr.isEmpty ? result.stdout : result.stderr
            return .failure(.compileFailed(log.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(dylibPath)
    }

    /// `dlopen` the compiled dylib and build the `Sketch` from its factory entry
    /// point. **Runs on the main actor**: `Sketch.init` is main-actor isolated, so
    /// the factory's `MainActor.assumeIsolated` requires this to be called on the
    /// main thread. `dlopen`/`dlsym` are cheap, so confining this step costs
    /// nothing while `compile()` stays off-main.
    @MainActor
    public func instantiate(dylibPath: String) -> Result<Sketch, LoadError> {
        guard let handle = dlopen(dylibPath, RTLD_NOW) else {
            return .failure(.loadFailed(String(cString: dlerror())))
        }
        guard let sym = dlsym(handle, "ollin_make_sketch") else {
            return .failure(.loadFailed("factory symbol `ollin_make_sketch` not found"))
        }
        typealias Factory = @convention(c) () -> UnsafeMutableRawPointer
        let make = unsafeBitCast(sym, to: Factory.self)
        let object = Unmanaged<AnyObject>.fromOpaque(make()).takeRetainedValue()
        guard let sketch = object as? Sketch else {
            return .failure(.loadFailed("loaded object is not an Ollin.Sketch"))
        }
        return .success(sketch)
    }

    /// The `-I` directories the sketch compile needs: the one holding
    /// `Ollin.swiftmodule` (so `import Ollin` type-checks) and the C targets'
    /// `module.modulemap` dirs that `import Ollin` pulls in. Discovered, not
    /// assumed, because the build layout differs by build system:
    ///
    /// - **Classic SwiftPM build:** everything sits next to the executable, at
    ///   `<bin>/Modules/Ollin.swiftmodule` and `<bin>/<C>.build/module.modulemap`.
    /// - **Xcode/Swift build system:** `Ollin.swiftmodule` is directly in `<bin>`
    ///   (`.build/out/Products/Debug`), while the C module maps live under the
    ///   index-store build at `.build/index-build/<triple>/debug/<C>.build/`, so
    ///   the classic `<bin>`-only scan finds neither and the compile fails with
    ///   "no such module 'Ollin'".
    ///
    /// Each *layout root* follows the same classic shape (an optional `Modules/`
    /// for the Swift modules, plus `<C>.build/module.modulemap` children for the C
    /// targets, with `Ollin.swiftmodule` possibly sitting in the root itself). We
    /// collect from `<bin>` and from each `index-build/<triple>/debug`, taking
    /// whichever exist; a classic build (no index-build) just uses `<bin>`.
    private func moduleSearchPaths() -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []
        func add(_ dir: String) {
            var isDir: ObjCBool = false
            if !dirs.contains(dir), fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                dirs.append(dir)
            }
        }

        var roots = [buildDir]
        if let buildRoot = dotBuildDirectory() {
            let indexBuild = (buildRoot as NSString).appendingPathComponent("index-build")
            for triple in (try? fm.contentsOfDirectory(atPath: indexBuild)) ?? [] {
                roots.append(((indexBuild as NSString).appendingPathComponent(triple) as NSString)
                    .appendingPathComponent("debug"))
            }
        }

        for root in roots {
            // The Swift module: in a `Modules/` subdir (classic / index-build) or
            // directly in the root (the Xcode build system's product dir).
            let modules = (root as NSString).appendingPathComponent("Modules")
            if fm.fileExists(atPath: (modules as NSString).appendingPathComponent("Ollin.swiftmodule")) { add(modules) }
            if fm.fileExists(atPath: (root as NSString).appendingPathComponent("Ollin.swiftmodule")) { add(root) }
            // C module maps: a `module.modulemap` that's a *direct* child of a
            // `*.build` dir is a C target's (the Swift targets keep theirs a level
            // deeper under `include/`), so matching direct children selects exactly
            // the C targets, and a new C target needs no change here.
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".build") {
                let dir = (root as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("module.modulemap")) { add(dir) }
            }
        }
        return dirs
    }

    /// Walk up from the executable's directory to the enclosing `.build` directory
    /// (the SwiftPM build root), or `nil` if it isn't under one.
    private func dotBuildDirectory() -> String? {
        var dir = buildDir
        while !dir.isEmpty, dir != "/" {
            if (dir as NSString).lastPathComponent == ".build" { return dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return nil
    }

    /// Escape a string so it's safe to splice into a Swift `"…"` literal in the
    /// generated factory (backslashes and quotes). Filesystem paths can in
    /// principle contain either.
    private func escapedForSwiftLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The name of the first `class …: Sketch` in the source (allowing a leading
    /// `final` and trailing protocol conformances after `Sketch`).
    static func sketchClassName(in source: String) -> String? {
        let pattern = #"class\s+(\w+)\s*:\s*[^{]*\bSketch\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              let nameRange = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[nameRange])
    }

    /// Run a process to completion, draining stdout and stderr concurrently so a
    /// verbose compiler error can't fill a pipe buffer and deadlock us.
    private func run(_ launchPath: String, _ args: [String])
        -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return (-1, "", "couldn't launch \(launchPath): \(error)")
        }
        // Drained on `drain` while we block reading stderr below; `drain.sync {}`
        // establishes the happens-before before we read it, so the concurrent
        // write is safe — which is what `nonisolated(unsafe)` vouches for.
        nonisolated(unsafe) var outData = Data()
        let drain = DispatchQueue(label: "ollin.subprocess.stdout")
        drain.async { outData = outPipe.fileHandleForReading.readDataToEndOfFile() }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        drain.sync {}   // ensure stdout finished reading
        return (process.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }
}
