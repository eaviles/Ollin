import Foundation
import Ollin

/// Compiles a single sketch `.swift` file into a `.dylib` and loads the `Sketch`
/// instance out of it. Each `load()` produces a fresh dylib at a unique path, so
/// `dlopen` returns a new image rather than a cached one — that fresh-image swap
/// is the mechanism behind live reload.
///
/// It works because the host (OllinLive) and the compiled dylib both link the
/// *same* dynamic `libOllin.dylib`: the loaded object's `Sketch` is the host's
/// `Sketch`, so the cast across the `dlopen` boundary succeeds.
struct SketchLoader {
    let sketchPath: String

    enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case noSketchClass(String)
        case compileFailed(String)
        case loadFailed(String)

        var description: String {
            switch self {
            case .unreadable(let p): return "couldn't read sketch file: \(p)"
            case .noSketchClass(let p):
                return "no `class …: Sketch` declaration found in \(p)"
            case .compileFailed(let log): return "compile failed —\n\(log)"
            case .loadFailed(let msg): return "load failed — \(msg)"
            }
        }
    }

    /// The directory holding this executable — `.build/<triple>/debug` — which is
    /// also where `Modules/Ollin.swiftmodule` lives, so it's the search path the
    /// sketch dylib needs to `import Ollin` (for type-checking only; the Ollin
    /// *symbols* resolve against this host process at load time).
    private var buildDir: String {
        (Bundle.main.executablePath! as NSString).deletingLastPathComponent
    }

    func load() -> Result<Sketch, LoadError> {
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
            .appendingPathComponent("OllinLive-\(token)")
        try? FileManager.default.createDirectory(
            atPath: work, withIntermediateDirectories: true)

        // A generated sibling file gives the dylib a stable C-ABI entry point that
        // builds the sketch — without touching (or even parsing beyond the class
        // name) the user's file. `@main` in the user file is harmless here.
        let factoryPath = (work as NSString).appendingPathComponent("__OllinFactory.swift")
        let factory = """
        import Ollin
        @_cdecl("ollin_make_sketch")
        public func ollin_make_sketch() -> UnsafeMutableRawPointer {
            Unmanaged.passRetained(\(className)()).toOpaque()
        }
        """
        do {
            try factory.write(toFile: factoryPath, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.loadFailed("couldn't write factory shim: \(error)"))
        }

        let dylibPath = (work as NSString).appendingPathComponent("sketch.dylib")
        let bin = buildDir
        // `-I .../Modules` lets the sketch type-check against `import Ollin`.
        // `-undefined dynamic_lookup` (and *no* `-lOllin`) leaves Ollin symbols
        // unresolved at link time so they bind to the host process at `dlopen`,
        // keeping one shared copy of `Sketch` across the boundary.
        let result = run("/usr/bin/xcrun", [
            "swiftc", "-emit-library", "-o", dylibPath,
            "-module-name", "OllinLiveSketch_\(token)",
            sketchPath, factoryPath,
            "-I", (bin as NSString).appendingPathComponent("Modules"),
            "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
        ])
        guard result.status == 0 else {
            let log = result.stderr.isEmpty ? result.stdout : result.stderr
            return .failure(.compileFailed(log.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

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
        var outData = Data()
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
