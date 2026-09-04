import Foundation
import Ollin

/// Compiles a single sketch `.swift` file into a `.dylib` and loads the `Sketch`
/// instance out of it. Each `load()` produces a fresh dylib at a unique path, so
/// `dlopen` returns a new image rather than a cached one — that fresh-image swap
/// is the mechanism behind live reload, and the way the examples gallery embeds
/// a selected sketch.
///
/// It works because the host process (OllinLive, OllinExamples, or
/// OllinLiveCoding) and the compiled dylib resolve to the *same* `Sketch`: the
/// host links Ollin and
/// exports its symbols (`-export_dynamic`), and the dylib is compiled with
/// `-undefined dynamic_lookup` so its Ollin symbols bind to the host at load.
/// The cast across the `dlopen` boundary therefore succeeds.
public struct SketchLoader: Sendable {
    public let sketchPath: String

    /// How hard `swiftc` optimizes the sketch. `.speed` (`-O`) is the default:
    /// the compiled dylib runs at release speed whatever the host was built
    /// as, so a sketch that does real CPU work every frame (points displaced
    /// by noise, a particle system stepped on the CPU, geometry rebuilt per
    /// frame) draws under the live window at the rate a release build gets,
    /// rather than the several-times-slower `-Onone` picture the compiler's
    /// default would give. Measured under a release host on 50k points moved
    /// by six octaves of noise a frame: 35 ms optimized against 80 ms plain
    /// when the noise is the framework's (the host's own code, already
    /// optimized, does most of the work), and 52 ms against 1,170 ms when the
    /// noise is written in the sketch itself. `.none` (`-Onone`) is for
    /// debugging the sketch: an `assert` fires again and a crash's backtrace
    /// names every frame. The hosts expose it as `--no-optimize`.
    public var optimization: Optimization

    public enum Optimization: Sendable {
        /// `-O`: the release speed the sketch would get from `swift run -c release`.
        case speed
        /// `-Onone`: no optimization, for debugging the sketch.
        case none

        var flag: String {
            switch self {
            case .speed: return "-O"
            case .none: return "-Onone"
            }
        }
    }

    public init(sketchPath: String, optimization: Optimization = .speed) {
        self.sketchPath = sketchPath
        self.optimization = optimization
    }

    /// What to compile: the file at `sketchPath`, or an in-memory buffer standing
    /// in for that file's content (the live-coding host's evaluate-on-command,
    /// where the editor buffer runs without being saved). A `.source` compile
    /// writes the text into the per-compile work directory under the sketch's own
    /// file name, so diagnostics carry the same file name and exact line numbers
    /// while the real file on disk stays untouched; the generated `Bundle.module`
    /// still points at `sketchPath`'s directory, so co-located assets resolve.
    public enum Input: Sendable {
        case file
        case source(String)
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

    /// Compile the sketch into a fresh `.dylib` and return its path, the slow
    /// step (it shells out to `swiftc`). Safe to run **off the main thread**: it
    /// touches no main-actor state, so the host window keeps drawing the old
    /// sketch while this runs. Pair with `instantiate(dylibPath:)`.
    public func compile() -> Result<String, LoadError> {
        compile(.file)
    }

    /// `compile()`, but with the source selected by `input`: the file on disk, or
    /// an in-memory buffer compiled *as* that file (see `Input`).
    public func compile(_ input: Input) -> Result<String, LoadError> {
        var source: String
        switch input {
        case .file:
            guard let text = try? String(contentsOfFile: sketchPath, encoding: .utf8) else {
                return .failure(.unreadable(sketchPath))
            }
            source = text
        case .source(let text):
            source = text
        }
        // A `#!/usr/bin/env ollin` hashbang line makes a sketch file directly
        // executable from the shell, but swiftc allows a hashbang only in a
        // main file and this compile is a library. Swapping the two marker
        // characters for `//` turns the line into a comment of identical
        // length, so every diagnostic keeps its exact line and column; the
        // modified text then compiles from the work dir like a buffer (see
        // below), leaving the file on disk untouched.
        let hasShebang = source.hasPrefix("#!")
        if hasShebang { source = "//" + source.dropFirst(2) }
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

        // A `.file` compile hands swiftc the real file, so diagnostics name the
        // path the user knows. A `.source` compile (and a hashbang file, whose
        // first line was neutralized above) writes the text into the work dir
        // under the same file name: line numbers match the original exactly
        // (identical line count), and the file *name* in a diagnostic still
        // matches the sketch, which is what an editor keys on to map errors.
        let sourceFile: String
        switch input {
        case .file where !hasShebang:
            sourceFile = sketchPath
        default:
            sourceFile = (work as NSString)
                .appendingPathComponent((sketchPath as NSString).lastPathComponent)
            do {
                try source.write(toFile: sourceFile, atomically: true, encoding: .utf8)
            } catch {
                return .failure(.loadFailed("couldn't write source buffer: \(error)"))
            }
        }

        let dylibPath = (work as NSString).appendingPathComponent("sketch.dylib")
        var args = Self.compileArguments(
            dylibPath: dylibPath, moduleName: "OllinRuntimeSketch_\(token)",
            sources: [sourceFile, factoryPath], optimization: optimization)
        args += moduleArguments()
        let result = run("/usr/bin/xcrun", args)
        guard result.status == 0 else {
            let log = result.stderr.isEmpty ? result.stdout : result.stderr
            return .failure(.compileFailed(log.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(dylibPath)
    }

    /// The `swiftc` line a sketch compile starts from, before the module search
    /// paths: the dylib to emit, the per-load module name, the sources, the
    /// optimization level, and the linker flags. Pure, so a test can read it.
    ///
    /// `-undefined dynamic_lookup` (and *no* `-lOllin`) leaves Ollin symbols
    /// unresolved at link time so they bind to the host process at `dlopen`,
    /// keeping one shared copy of `Sketch` across the boundary. The
    /// optimization flag is always spelled out: `swiftc`'s own default is
    /// `-Onone`, and a sketch compiled that way ran its CPU work several
    /// times slower under the live window than under a release build.
    static func compileArguments(dylibPath: String, moduleName: String,
                                 sources: [String],
                                 optimization: Optimization) -> [String] {
        var args = [
            "swiftc", "-emit-library", "-o", dylibPath,
            "-module-name", moduleName,
            optimization.flag,
        ]
        args += sources
        args += ["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"]
        return args
    }

    /// Type-check a source that is not a sketch, against the same modules a
    /// sketch compile sees. For a library file (an extension's starter, say),
    /// which has no `Sketch` subclass to build and nothing to run, this is the
    /// whole honest check: does it still compile against the framework on this
    /// machine. No dylib is produced and nothing is linked, so it is a fraction
    /// of a compile. Safe to run off the main thread.
    ///
    /// The text is written into a work directory under `fileName`, so a
    /// diagnostic names the file the caller knows and keeps its exact line.
    public func typecheck(_ source: String, fileName: String) -> Result<Void, LoadError> {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let work = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinRuntime-check-\(token)")
        try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        let sourceFile = (work as NSString).appendingPathComponent(fileName)
        do {
            try source.write(toFile: sourceFile, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.loadFailed("couldn't write source buffer: \(error)"))
        }
        defer { try? FileManager.default.removeItem(atPath: work) }

        var args = [
            "swiftc", "-typecheck", "-parse-as-library",
            "-module-name", "OllinRuntimeCheck_\(token)",
            sourceFile,
        ]
        args += moduleArguments()
        let result = run("/usr/bin/xcrun", args)
        guard result.status == 0 else {
            let log = result.stderr.isEmpty ? result.stdout : result.stderr
            return .failure(.compileFailed(log.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(())
    }

    /// The module arguments every compile against the framework needs.
    ///
    /// `-I` the dirs holding `Ollin.swiftmodule` (so `import Ollin` type-checks)
    /// and the C targets' clang module maps that `import Ollin` pulls in
    /// (`CLibtess2` / `CClipper2` / `COllinShaders`). Discovered across both
    /// build layouts; see `moduleSearchPaths()`. Without them the compile fails
    /// with "no such module 'Ollin'" or "missing required modules".
    /// One build layout does not put its C module maps anywhere `-I` can find
    /// them, so they are named outright; see `explicitModuleMaps()`.
    private func moduleArguments() -> [String] {
        var args: [String] = []
        let named = explicitModuleMaps()
        // A module named outright must not also be reachable through a search path,
        // or clang sees it declared twice and refuses the whole compile with
        // "umbrella for module ... already covers this directory". Only some C
        // targets get collected into the generated directory, so the ones that do
        // are skipped by name and the rest still travel as search paths.
        let alreadyNamed = Set(named.map {
            ((($0 as NSString).lastPathComponent) as NSString).deletingPathExtension
        })
        for path in moduleSearchPaths() where !alreadyNamed.contains(moduleName(declaredIn: path) ?? "") {
            args.append(contentsOf: ["-I", path])
        }
        for path in named {
            args.append(contentsOf: ["-Xcc", "-fmodule-map-file=\(path)"])
        }
        return args
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
    ///
    /// One more source sits outside the build tree entirely: a vendored C target
    /// with a *checked-in* module map (`External/<Target>/include/module.modulemap`)
    /// is compiled straight from the source tree, so no generated map ever lands
    /// under a `*.build` dir. A sketch importing a satellite whose swiftmodule
    /// depends on one (the physics library's rigid side, say) needs that map on
    /// the search path, so those `include/` dirs are collected from the package
    /// root, the `.build` directory's parent.
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
            let external = ((buildRoot as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent("External")
            for name in (try? fm.contentsOfDirectory(atPath: external)) ?? [] {
                let include = ((external as NSString).appendingPathComponent(name) as NSString)
                    .appendingPathComponent("include")
                if fm.fileExists(atPath: (include as NSString).appendingPathComponent("module.modulemap")) {
                    add(include)
                }
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
    /// C module maps that have to be named one by one rather than searched for.
    ///
    /// `-I` finds a clang module only when the directory holds a file called exactly
    /// `module.modulemap`, which is how the classic build layout writes them. The
    /// Xcode build system instead collects every target's map into one
    /// `GeneratedModuleMaps` directory and names each after its target
    /// (`CClipper2.modulemap`, `COllinShaders.modulemap`, …), where no amount of
    /// `-I` will ever find them: the compile fails with "missing required modules"
    /// even though the maps are right there. That layout is what a plain `swift
    /// build` produces on this toolchain, which is why every host that compiles a
    /// sketch (the Guide figures, `OllinLive`, the gallery, `ollin`) could stop
    /// working after a clean with nothing obviously wrong. Naming them outright is
    /// what the real build does too.
    private func explicitModuleMaps() -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        // The products dir is `<root>/Products/<config>`, so the intermediates sit
        // two levels up. Derived from where this executable actually is rather than
        // from an assumed `.build`, which is what makes it work from a checkout laid
        // out any other way.
        var roots: [String] = []
        let productsParent = ((buildDir as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent
        roots.append((productsParent as NSString).appendingPathComponent("Intermediates.noindex"))
        if let dotBuild = dotBuildDirectory() {
            roots.append(((dotBuild as NSString).appendingPathComponent("out") as NSString)
                .appendingPathComponent("Intermediates.noindex"))
        }
        for root in roots {
            let dir = (root as NSString).appendingPathComponent("GeneratedModuleMaps")
            for name in (try? fm.contentsOfDirectory(atPath: dir))?.sorted() ?? []
            where name.hasSuffix(".modulemap") {
                let path = (dir as NSString).appendingPathComponent(name)
                if !out.contains(path) { out.append(path) }
            }
        }
        return out
    }

    /// The module a search directory would contribute, read from the
    /// `module.modulemap` it holds, or `nil` if it holds none (a Swift module
    /// directory, which never collides).
    private func moduleName(declaredIn dir: String) -> String? {
        let map = (dir as NSString).appendingPathComponent("module.modulemap")
        guard let text = try? String(contentsOfFile: map, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "module" { return String(parts[1]) }
        }
        return nil
    }

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
    package static func sketchClassName(in source: String) -> String? {
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
