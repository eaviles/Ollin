import CryptoKit
import Foundation
import OllinRuntime

// MARK: - Results kept from one run to the next
//
// Every block is its own compile, and about three thousand of them take
// minutes however they are run (CompilePass.swift). A block's answer is a
// function of what the compiler reads for it: its text, the compiler, the
// flags, and the module files its imports load. So the answer is kept under a
// digest of exactly those, and a block is compiled again only when one of
// them moved.
//
// The rule that keeps this the same gate: nothing here guesses. Which module
// files a set of imports loads is asked of the compiler itself, the files are
// compared by their bytes, and a block whose inputs cannot be listed in full
// (an import that does not resolve, a `canImport` test, a module file that
// cannot be read) is never remembered and compiles every time. A rename in
// the framework changes its module file, the digest of every block importing
// it changes with it, and those blocks compile again; that was checked by
// planting one (2026-11-10).

/// The answers of earlier runs: a digest of everything a block's compile
/// reads, to the first error it gave, or to the empty string when it compiled.
struct Remembered {
    private(set) var results: [String: String] = [:]
    let path: String

    private struct Stored: Codable {
        var version: Int
        var results: [String: String]
    }

    /// Bumped when what is stored changes its meaning, so an older file is
    /// dropped rather than misread.
    private static let version = 1

    init(path: String, reading: Bool) {
        self.path = path
        guard reading, let data = FileManager.default.contents(atPath: path),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == Self.version else { return }
        results = stored.results
    }

    /// Write this run's answers. A run over every page replaces the file, so
    /// it never grows past the blocks there are; a run over some pages adds to
    /// what was there, since it saw only those.
    func save(_ fresh: [String: String], whole: Bool) {
        var merged = whole ? [:] : results
        merged.merge(fresh) { _, new in new }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Stored(version: Self.version, results: merged)) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// Values put down from many threads at once, each under the index of the
/// work that made it.
final class Shelf<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int: Value] = [:]

    func put(_ value: Value, at index: Int) {
        lock.lock()
        values[index] = value
        lock.unlock()
    }

    subscript(index: Int) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return values[index]
    }

    var all: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return Array(values.values)
    }
}

/// Everything a block's compile reads besides the block's own text, as a
/// digest per set of imports.
final class CompileInputs: @unchecked Sendable {
    /// The search paths and module maps a compile is given, as the loader lists them.
    let moduleArguments: [String]
    private let work: String
    /// The compiler, the SDK, the flags, the C headers the module maps name,
    /// and the checker's own sources: what every answer rests on whatever the
    /// block imports. `nil` when one of the checker's sources cannot be read,
    /// and then nothing is kept.
    private let base: String?
    /// The C headers folded into `base`, kept to be listed by `--inputs`.
    let headerFiles: [String]
    private let lock = NSLock()
    private var fileDigests: [String: String] = [:]

    /// `checker` is the source of everything that turns a block into an
    /// answer: how it is wrapped, which flags it compiles under, how its first
    /// error is read. An answer kept by an older checker is not this one's.
    init(loader: SketchLoader, checker: [String]) {
        // The module arguments a compile gets, read off the one public list
        // that carries them: the search paths and the C module maps.
        let all = loader.completionArguments(sourceFile: "Snippet.swift")
        var arguments: [String] = []
        var index = 0
        while index + 1 < all.count {
            if all[index] == "-I" || all[index] == "-Xcc" {
                arguments += [all[index], all[index + 1]]
                index += 2
            } else {
                index += 1
            }
        }
        moduleArguments = arguments
        work = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinSnippets-inputs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)

        var hasher = SHA256()
        func add(_ text: String) { hasher.update(data: Data((text + "\u{1}").utf8)) }
        add(Self.run(["swiftc", "--version"]).output)
        add(Self.run(["--show-sdk-path"]).output)
        add(Self.run(["--show-sdk-build-version"]).output)
        for name in ["SDKROOT", "TOOLCHAINS", "DEVELOPER_DIR"] {
            add(name + "=" + (ProcessInfo.processInfo.environment[name] ?? ""))
        }
        add(arguments.joined(separator: "\u{2}"))
        headerFiles = Self.headers(namedBy: arguments)
        for file in headerFiles {
            add(file)
            hasher.update(data: FileManager.default.contents(atPath: file) ?? Data())
        }
        var readable = !checker.isEmpty
        for file in checker.sorted() {
            guard let data = FileManager.default.contents(atPath: file) else { readable = false; break }
            add((file as NSString).lastPathComponent)
            hasher.update(data: data)
        }
        base = readable ? Self.hex(hasher.finalize()) : nil
    }

    deinit { try? FileManager.default.removeItem(atPath: work) }

    /// The import lines of a source, as written, in a fixed order.
    static func imports(in source: String) -> [String] {
        var found: Set<String> = []
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") || (trimmed.hasPrefix("@") && trimmed.contains(" import ")) {
                found.insert(trimmed)
            }
        }
        return found.sorted()
    }

    /// Whether a source can ask about a module without importing it, which no
    /// list of the files its imports load would cover.
    static func asksAboutModules(_ source: String) -> Bool { source.contains("canImport") }

    /// The digest of what a file with these imports reads, or `nil` when that
    /// cannot be listed: the imports do not all resolve (so what the block
    /// reads depends on a module that is not there yet), or a file the
    /// compiler loaded cannot be read back.
    ///
    /// The compiler is asked which module files it loaded for a file holding
    /// only the imports. Every one is hashed by its bytes, the SDK's with the
    /// framework's, so nothing rests on telling the two apart by path.
    func digest(imports: [String], index: Int) -> String? {
        guard let base, let modules = modules(imports: imports, index: index) else { return nil }
        var hasher = SHA256()
        hasher.update(data: Data(base.utf8))
        for module in modules {
            guard let digest = fileDigest(module) else { return nil }
            // The last two components name the module and its architecture
            // file; the folders above them are the machine's business.
            let name = (module as NSString).pathComponents.suffix(2).joined(separator: "/")
            hasher.update(data: Data((name + "\u{1}" + digest + "\u{1}").utf8))
        }
        return Self.hex(hasher.finalize())
    }

    /// The module files the compiler loads for a file holding only these
    /// imports, sorted, or `nil` when the imports do not all resolve.
    func modules(imports: [String], index: Int) -> [String]? {
        let directory = (work as NSString).appendingPathComponent("\(index)")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let source = (directory as NSString).appendingPathComponent("Imports.swift")
        let trace = (directory as NSString).appendingPathComponent("trace.json")
        guard (try? (imports.joined(separator: "\n") + "\n")
            .write(toFile: source, atomically: true, encoding: .utf8)) != nil else { return nil }
        let arguments = ["swiftc", "-typecheck", "-parse-as-library",
                         "-module-name", "OllinSnippetInputs_\(index)", source]
            + moduleArguments
            + ["-emit-loaded-module-trace", "-emit-loaded-module-trace-path", trace]
        guard Self.run(arguments).status == 0,
              let text = try? String(contentsOfFile: trace, encoding: .utf8),
              let last = text.components(separatedBy: "\n").last(where: { !$0.isEmpty }),
              let object = try? JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any],
              let modules = object["swiftmodules"] as? [String], !modules.isEmpty
        else { return nil }
        return modules.sorted()
    }

    /// The key a block's answer is kept under.
    static func key(digest: String, source: String) -> String {
        hex(SHA256.hash(data: Data((digest + "\u{1}" + source).utf8)))
    }

    private func fileDigest(_ path: String) -> String? {
        lock.lock()
        let known = fileDigests[path]
        lock.unlock()
        if let known { return known }
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let digest = Self.hex(SHA256.hash(data: data))
        lock.lock()
        fileDigests[path] = digest
        lock.unlock()
        return digest
    }

    // MARK: The C side

    /// Every header a module map among the arguments names, with the headers
    /// those include by a quoted path, sorted. A module file does not carry a C
    /// header's text, so a field renamed in one would otherwise change what a
    /// block compiles to with no module file moving.
    private static func headers(namedBy arguments: [String]) -> [String] {
        let manager = FileManager.default
        var maps: [String] = []
        var index = 0
        while index + 1 < arguments.count {
            let value = arguments[index + 1]
            if arguments[index] == "-I" {
                maps.append((value as NSString).appendingPathComponent("module.modulemap"))
            } else if value.hasPrefix("-fmodule-map-file=") {
                maps.append(String(value.dropFirst("-fmodule-map-file=".count)))
            }
            index += 2
        }

        var found: Set<String> = []
        var pending: [String] = []
        func take(_ path: String) {
            let standard = (path as NSString).standardizingPath
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: standard, isDirectory: &isDirectory) else { return }
            if isDirectory.boolValue {
                let enumerator = manager.enumerator(atPath: standard)
                while let relative = enumerator?.nextObject() as? String {
                    if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
                    take((standard as NSString).appendingPathComponent(relative))
                }
            } else if found.insert(standard).inserted {
                pending.append(standard)
            }
        }

        let entry = try? NSRegularExpression(pattern: #"(umbrella\s+header|umbrella|header)\s+"([^"]+)""#)
        let include = try? NSRegularExpression(pattern: ##"#\s*(?:include|import)\s+"([^"]+)""##)
        for map in maps {
            guard let text = try? String(contentsOfFile: map, encoding: .utf8) else { continue }
            take(map)
            let folder = (map as NSString).deletingLastPathComponent
            let range = NSRange(text.startIndex..., in: text)
            for match in entry?.matches(in: text, range: range) ?? [] {
                guard let kind = Range(match.range(at: 1), in: text),
                      let name = Range(match.range(at: 2), in: text) else { continue }
                var path = String(text[name])
                if !path.hasPrefix("/") { path = (folder as NSString).appendingPathComponent(path) }
                // An umbrella header stands for the folder it sits in.
                if text[kind].hasPrefix("umbrella"), text[kind].contains("header") {
                    take((path as NSString).deletingLastPathComponent)
                } else {
                    take(path)
                }
            }
        }
        // The headers those include, kept on a list rather than the stack: how
        // deep one header reaches into the next is the headers' own business.
        while let file = pending.popLast() {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let folder = (file as NSString).deletingLastPathComponent
            let range = NSRange(text.startIndex..., in: text)
            for match in include?.matches(in: text, range: range) ?? [] {
                guard let name = Range(match.range(at: 1), in: text) else { continue }
                take((folder as NSString).appendingPathComponent(String(text[name])))
            }
        }
        return found.sorted()
    }

    // MARK: Helpers

    private static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return (-1, "") }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
