import Foundation
import OllinRuntime

// MARK: - The compiler alone
//
// A block's typecheck through the sketch loader is four processes: the tool
// finder, the compiler's driver, a compiler the driver starts to ask about
// the target, and the compiler that reads the block. Only the last does the
// work, and with three thousand blocks the other three are a large share of a
// run in which every block compiles.
//
// The driver's whole contribution is the command line it hands that last
// process, and it will print it instead of running it. So the driver is asked
// once, for a probe file compiled exactly as the loader compiles a block, and
// every block then runs that same command with its own file and module name
// in the probe's places. Nothing about the compile is restated here: the
// flags, the SDK, the plugin paths are the driver's, read back.
//
// Two things keep it honest. A command whose shape is not understood (the
// probe's file or module name not found where expected, or found inside some
// other argument) is not used at all, and the loader compiles as before. And
// every run compiles a sample of its blocks both ways and compares the
// answers; one disagreement throws the direct answers away and the loader
// compiles everything (`--compare-routes` checks every block that way).

/// One typecheck as the compiler process alone, with the command line the
/// driver would have given it.
struct DirectCompile: Sendable {
    private let executable: String
    private let arguments: [String]
    private let fileSlots: [Int]
    private let moduleSlots: [Int]
    private let environment: [String: String]

    /// Ask the driver for the job behind a typecheck, or `nil` when its answer
    /// is not one compiler command of the expected shape.
    ///
    /// The driver's arguments here are the ones `SketchLoader.typecheck` passes,
    /// in its order; `moduleArguments` are the loader's own search paths and
    /// module maps.
    init?(moduleArguments: [String]) {
        let work = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinSnippets-probe-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: work) }
        let probeFile = (work as NSString).appendingPathComponent("OllinSnippetProbe.swift")
        let probeModule = "OllinRuntimeCheck_0123456789ABCDEF0123456789ABCDEF"
        guard (try? "import Foundation\n".write(toFile: probeFile, atomically: true, encoding: .utf8)) != nil
        else { return nil }

        let driver = ["swiftc", "-typecheck", "-parse-as-library", "-module-name", probeModule, probeFile]
            + moduleArguments + ["-driver-print-jobs"]
        let printed = Self.run("/usr/bin/xcrun", driver, environment: nil)
        guard printed.status == 0 else { return nil }
        let jobs = printed.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard jobs.count == 1, let words = Self.shellWords(jobs[0]), words.count > 3,
              words.contains("-frontend"), words.contains("-typecheck") else { return nil }

        var files: [Int] = []
        var modules: [Int] = []
        for (index, word) in words.enumerated().dropFirst() {
            if word == probeFile {
                files.append(index)
            } else if word == probeModule {
                modules.append(index)
            } else if word.contains(work) || word.contains(probeModule) {
                // The probe's names inside another argument (an output path
                // derived from them) is a shape this does not know how to fill.
                return nil
            }
        }
        guard !files.isEmpty, modules.count == 1, modules[0] > 0, words[modules[0] - 1] == "-module-name",
              FileManager.default.isExecutableFile(atPath: words[0]) else { return nil }

        // The tool finder gives the compiler the SDK in its environment as
        // well as on its command line; kept the same here.
        var environment = ProcessInfo.processInfo.environment
        if environment["SDKROOT"] == nil {
            let sdk = Self.run("/usr/bin/xcrun", ["--show-sdk-path"], environment: nil).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sdk.isEmpty { environment["SDKROOT"] = sdk }
        }
        executable = words[0]
        arguments = Array(words.dropFirst())
        fileSlots = files.map { $0 - 1 }
        moduleSlots = modules.map { $0 - 1 }
        self.environment = environment
    }

    /// Typecheck `source` as the loader would, and answer as it does: success,
    /// or the failure the loader would have returned, word for word.
    func typecheck(_ source: String, fileName: String) -> Result<Void, SketchLoader.LoadError> {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let work = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinRuntime-check-\(token)")
        try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: work) }
        let sourceFile = (work as NSString).appendingPathComponent(fileName)
        do {
            try source.write(toFile: sourceFile, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.loadFailed("couldn't write source buffer: \(error)"))
        }
        var filled = arguments
        for slot in fileSlots { filled[slot] = sourceFile }
        for slot in moduleSlots { filled[slot] = "OllinRuntimeCheck_\(token)" }
        let result = Self.run(executable, filled, environment: environment)
        guard result.status == 0 else {
            let log = result.stderr.isEmpty ? result.stdout : result.stderr
            return .failure(.compileFailed(log.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(())
    }

    // MARK: Helpers

    /// A printed command line as its arguments: words split on spaces, with
    /// single quotes, double quotes, and backslashes read as a shell reads
    /// them. `nil` for a line that ends inside a quote.
    static func shellWords(_ line: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var characters = line.makeIterator()
        while let character = characters.next() {
            if let open = quote {
                if character == open {
                    quote = nil
                } else if character == "\\", open == "\"", let next = characters.next() {
                    current.append(next)
                } else {
                    current.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
                inWord = true
            } else if character == "\\" {
                if let next = characters.next() { current.append(next) }
                inWord = true
            } else if character == " " || character == "\t" {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        guard quote == nil else { return nil }
        if inWord { words.append(current) }
        return words
    }

    private static func run(_ launchPath: String, _ arguments: [String], environment: [String: String]?)
        -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        guard (try? process.run()) != nil else { return (-1, "", "couldn't launch \(launchPath)") }
        // Standard output is drained on its own queue while this thread reads
        // the errors, so a compiler that fills one pipe cannot wait forever on
        // the other.
        let drained = Shelf<Data>()
        let done = DispatchGroup()
        DispatchQueue.global().async(group: done) {
            drained.put(outPipe.fileHandleForReading.readDataToEndOfFile(), at: 0)
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        done.wait()
        // Closed by hand rather than left to whenever the pipes are let go:
        // three thousand compiles a run, four handles each.
        for pipe in [outPipe, errPipe] {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        return (process.terminationStatus,
                String(data: drained[0] ?? Data(), encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }
}
