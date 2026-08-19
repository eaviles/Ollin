import AppKit
import CryptoKit
import Foundation
import Ollin
import OllinRuntime

/// `swift run OllinGuideFigures [options]` renders every Guide figure sketch
/// (`Guide/Figures/**/*.swift`) to its committed image
/// (`Guide/Images/<chapter>/<name>.jpg`, `.png`, or `.gif`), and exits nonzero
/// if any figure fails to compile or render. This is the Guide's verification
/// gate: a listing that no longer builds fails here before it can mislead a
/// reader.
///
/// Stills default to JPEG (quality 0.85): the renderer's anti-banding dither
/// is per-pixel noise, so a PNG of even a flat diagram weighs hundreds of
/// kilobytes while the JPEG is a fraction of it and looks identical at the
/// Guide's display widths. `format=png` opts a figure back into lossless.
///
/// Each figure is an ordinary sketch file, compiled through `SketchLoader`
/// (the live host's loader) and rendered through the same off-screen path as
/// `--export`, so the committed image is exactly what a reader's own run of
/// the listing produces. Figure conventions and the directive format live in
/// `Guide/AUTHORING.md`.
///
/// Two mechanisms keep a full run affordable, because a gate nobody can afford
/// to run is a gate nobody runs (see `Guide/AUTHORING.md`):
///
/// - **A content-hash cache.** A figure is re-rendered only when its own source
///   changed, its image is missing, or its image was edited by hand. Any change
///   to the framework itself (`Sources/`, `External/`, `Package.swift`, or the
///   Swift toolchain) invalidates every entry, since that can change what any
///   figure renders.
/// - **Sharded worker processes.** The work left after the cache is split
///   across child copies of this executable. Sharding rather than in-process
///   concurrency is deliberate: the expensive figures spend their time in
///   `setup()` on the main actor (erosion, stippling, flame accumulation), so
///   only separate processes actually run them in parallel.
@main
enum GuideFigures {

    // MARK: - Directives

    /// Render configuration parsed from a figure's `// figure:` comment,
    /// scanned in the file's first lines. `frame=N` picks the still's frame
    /// and `format=png` makes it lossless; `gif` (plus optional `duration=`,
    /// `fps=`, `width=`) renders an animated loop instead.
    struct Directive {
        var frame = 0
        var gif = false
        var png = false
        var duration = 3.0
        var fps = 25.0
        var width: Int?
        /// `unstable` marks a figure whose render is genuinely not reproducible
        /// (a GPU sim whose scatter order is atomic-race-ordered). The cache
        /// then keys it on its source alone, ignoring the committed image, so a
        /// suite run stops reporting it as changed every time.
        var unstable = false

        init(source: String) {
            let head = source.split(separator: "\n", omittingEmptySubsequences: false).prefix(8)
            guard let line = head.first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("// figure:")
            }) else { return }
            let body = line.trimmingCharacters(in: .whitespaces).dropFirst("// figure:".count)
            for token in body.split(separator: " ") {
                let pair = token.split(separator: "=", maxSplits: 1)
                let key = String(pair[0])
                let value = pair.count > 1 ? String(pair[1]) : nil
                switch (key, value) {
                case ("gif", _): gif = true
                case ("unstable", _): unstable = true
                case ("format", "png"): png = true
                case ("format", "jpg"), ("format", "jpeg"): png = false
                case ("frame", let v?): frame = Int(v) ?? frame
                case ("duration", let v?): duration = Double(v) ?? duration
                case ("fps", let v?): fps = Double(v) ?? fps
                case ("width", let v?): width = Int(v)
                default:
                    warn("ignoring unknown directive token '\(token)'")
                }
            }
        }

        var stillExtension: String { png ? ".png" : ".jpg" }
    }

    // MARK: - Cache

    /// The render cache, stored at `Guide/.figure-cache.json` (gitignored). A
    /// figure is up to date when its source hash, its image's hash, and the
    /// framework digest all still match.
    struct Cache: Codable {
        static let currentVersion = 1

        var version = Cache.currentVersion
        var framework = ""
        var figures: [String: Entry] = [:]

        struct Entry: Codable {
            var source: String
            var output: String
            var outputPath: String
            var seconds: Double
            var unstable = false
        }
    }

    /// One figure's outcome, as a shard reports it back to the parent process.
    struct Rendered: Codable {
        var figure: String
        var ok: Bool
        var seconds: Double
        var source: String
        var output: String
        var outputPath: String
        var log: String
        var unstable = false
    }

    /// One figure to render, plus whether its committed image is allowed to
    /// change. `verifyOnly` is set for an `unstable` figure that is being redone
    /// only because the framework moved: the render still has to succeed, but
    /// its image is arbitrary, so overwriting it would report a change that
    /// means nothing and leave a diff to throw away.
    struct Work {
        var figure: String
        var verifyOnly: Bool

        init(figure: String, verifyOnly: Bool) {
            self.figure = figure
            self.verifyOnly = verifyOnly
        }

        init(line: String) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            figure = String(parts[0])
            verifyOnly = parts.count > 1 && parts[1] == "verify"
        }

        var line: String { verifyOnly ? "\(figure)\tverify" : figure }
    }

    // MARK: - Entry point

    @MainActor
    static func main() {
        // Line buffering, so the progress line (written straight to the file
        // handle) stays in order with the ordinary prints when output is piped.
        setvbuf(stdout, nil, _IOLBF, 0)

        var only: String?
        var force = false
        var verbose = false
        var jobs = defaultJobs
        var listPath: String?
        var resultsPath: String?
        var progressPath: String?

        var arguments = Array(CommandLine.arguments.dropFirst())
        while let argument = arguments.first {
            arguments.removeFirst()
            func value(_ flag: String) -> String {
                guard let v = arguments.first else { die("\(flag) needs a value") }
                arguments.removeFirst()
                return v
            }
            switch argument {
            case "--only": only = value("--only")
            case "--force": force = true
            case "--verbose": verbose = true
            case "--jobs": jobs = max(1, Int(value("--jobs")) ?? 1)
            case "--list": listPath = value("--list")
            case "--results": resultsPath = value("--results")
            case "--progress": progressPath = value("--progress")
            case "--help", "-h": usage()
            default:
                die("unknown argument '\(argument)'; try --help")
            }
        }

        let root = FileManager.default.currentDirectoryPath
        let figuresDir = root + "/Guide/Figures"
        let imagesDir = root + "/Guide/Images"

        // Shard mode: render exactly the listed figures, report back as JSON,
        // touch no cache. The parent owns all cache and reporting decisions.
        if let listPath, let resultsPath {
            let list = ((try? String(contentsOfFile: listPath, encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                .map(Work.init(line:))
            let results = render(list, figuresDir: figuresDir, imagesDir: imagesDir,
                                 progressPath: progressPath, echo: true)
            if let data = try? JSONEncoder().encode(results) {
                try? data.write(to: URL(fileURLWithPath: resultsPath))
            }
            exit(results.contains { !$0.ok } ? 1 : 0)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: figuresDir, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            die("Guide/Figures not found under \(root); run from the repository root")
        }

        // Deterministic order so runs (and their logs) are comparable.
        var figures: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: figuresDir)
        while let relative = enumerator?.nextObject() as? String {
            if relative.hasSuffix(".swift") { figures.append(relative) }
        }
        figures.sort()
        if let only {
            figures = figures.filter { $0.range(of: only, options: .caseInsensitive) != nil }
            if figures.isEmpty { die("no figure matches --only \(only)") }
        }
        guard !figures.isEmpty else {
            print("guide-figures: no figures under Guide/Figures yet, nothing to render")
            exit(0)
        }

        // What the cache is keyed on, beyond each figure's own source.
        let cachePath = root + "/Guide/.figure-cache.json"
        let digest = frameworkDigest(root: root)
        let previous = loadCache(cachePath)
        var cache = previous
        let frameworkChanged = cache.framework != digest
        var renderAll = force
        if frameworkChanged || cache.version != Cache.currentVersion {
            if only == nil || cache.version != Cache.currentVersion {
                if !cache.figures.isEmpty {
                    print("guide-figures: the framework changed, so every figure is re-rendered")
                }
                cache = Cache(version: Cache.currentVersion, framework: digest, figures: [:])
            } else {
                // A filtered run keeps the cache exactly as it was: adopting
                // the new digest while recording only the matches would leave
                // the next full run with no `previous` entries, so the
                // unstable figures' committed images would be rewritten, the
                // very thing `verifyOnly` exists to prevent. The old digest
                // stays, so that full run still re-renders the world.
                print("guide-figures: the framework changed; a filtered run"
                      + " renders its matches but leaves the cache alone, so"
                      + " the next full run still re-renders everything")
                renderAll = true
            }
        }

        let staleFigures = renderAll ? figures : figures.filter {
            isStale($0, cache: cache, figuresDir: figuresDir, imagesDir: imagesDir)
        }
        // An `unstable` figure whose own source is unchanged is only being
        // redone because the framework moved, so verify it without touching its
        // committed image (see `Work`). This reads the pre-reset cache, since a
        // framework change is exactly the case it is here to handle. With no
        // entry at all (the cache is gitignored, so a fresh clone or a cleared
        // cache), the figure's own directive is the fallback: `render` only
        // verifies when the committed image exists, so a brand-new unstable
        // figure still gets its image written, and re-recording an edited one
        // with no cache entry means deleting its image first.
        let stale = staleFigures.map { figure -> Work in
            let verifyOnly: Bool
            if let entry = previous.figures[figure] {
                verifyOnly = entry.unstable
                    && unchanged(figure, cache: previous, figuresDir: figuresDir)
            } else {
                verifyOnly = directiveIsUnstable(figure, figuresDir: figuresDir)
            }
            return Work(figure: figure, verifyOnly: verifyOnly)
        }
        let skipped = figures.count - stale.count
        guard !stale.isEmpty else {
            print("guide-figures: \(figures.count) figure\(plural(figures.count)) already up to date")
            reportSlowest(cache: cache, among: figures)
            exit(0)
        }
        if skipped > 0 {
            print("guide-figures: \(skipped) unchanged figure\(plural(skipped)) skipped")
        }

        let workers = min(jobs, stale.count)
        let started = Date()
        var results: [Rendered]
        if workers <= 1 {
            print("guide-figures: rendering \(stale.count) figure\(plural(stale.count))")
            results = render(stale, figuresDir: figuresDir, imagesDir: imagesDir,
                             progressPath: nil, echo: true)
        } else {
            print("guide-figures: rendering \(stale.count) figure\(plural(stale.count))"
                  + " across \(workers) job\(plural(workers))")
            results = renderSharded(stale, workers: workers, verbose: verbose)
        }
        results.sort { $0.figure < $1.figure }

        for result in results where result.ok {
            cache.figures[result.figure] = Cache.Entry(
                source: result.source, output: result.output,
                outputPath: result.outputPath, seconds: result.seconds,
                unstable: result.unstable)
        }
        for result in results where !result.ok {
            cache.figures.removeValue(forKey: result.figure)
        }
        saveCache(cache, to: cachePath)

        let elapsed = Date().timeIntervalSince(started)
        let failures = results.filter { !$0.ok }
        for failure in failures where !failure.log.isEmpty {
            warn("FAILED \(failure.figure)\n\(failure.log)")
        }
        reportSlowest(cache: cache, among: figures)
        if failures.isEmpty {
            print("guide-figures: \(results.count) figure\(plural(results.count)) rendered"
                  + " in \(format(elapsed))")
            exit(0)
        }
        warn("\(failures.count) of \(results.count) figures failed: "
             + failures.map(\.figure).joined(separator: ", "))
        exit(1)
    }

    // MARK: - Rendering

    /// Compile and render each listed figure in this process, in order. The
    /// serial heart of the runner: everything else decides *which* figures get
    /// here and how many processes are doing it at once.
    @MainActor
    private static func render(_ list: [Work], figuresDir: String, imagesDir: String,
                               progressPath: String?, echo: Bool) -> [Rendered] {
        var results: [Rendered] = []
        for work in list {
            let relative = work.figure
            let sourcePath = figuresDir + "/" + relative
            let started = Date()
            var log = ""
            var outPath = ""
            var sourceHash = ""
            var ok = false
            var unstable = false

            if let data = FileManager.default.contents(atPath: sourcePath),
               let source = String(data: data, encoding: .utf8) {
                sourceHash = hex(SHA256.hash(data: data))
                let directive = Directive(source: source)
                unstable = directive.unstable
                let stem = (relative as NSString).deletingPathExtension
                let name = (stem as NSString).lastPathComponent
                    + (directive.gif ? ".gif" : directive.stillExtension)
                let directory = imagesDir + "/" + (stem as NSString).deletingLastPathComponent
                outPath = directory + "/" + name
                try? FileManager.default.createDirectory(
                    atPath: directory, withIntermediateDirectories: true)

                // Verifying rather than recording: render beside the committed
                // image and throw the result away.
                let verifying = work.verifyOnly
                    && FileManager.default.fileExists(atPath: outPath)
                let writePath = verifying ? directory + "/.verify-" + name : outPath

                if echo { print("guide-figures: \(relative)") }
                switch SketchLoader(sketchPath: sourcePath).load() {
                case .success(let sketch):
                    if directive.gif {
                        let frames = max(1, Int((directive.duration * directive.fps).rounded()))
                        OllinApp.exportGIF(sketch, to: writePath, frames: frames,
                                           fps: directive.fps, width: directive.width)
                    } else if directive.png {
                        OllinApp.export(sketch, to: writePath, frame: directive.frame)
                    } else {
                        exportJPEG(sketch, to: writePath, frame: directive.frame)
                    }
                    if FileManager.default.fileExists(atPath: writePath) {
                        ok = true
                    } else {
                        log = "no output written"
                    }
                    if verifying { try? FileManager.default.removeItem(atPath: writePath) }
                case .failure(let error):
                    log = "\(error)"
                }
            } else {
                log = "unreadable"
            }

            let outputHash = ok && !unstable ? fileHash(outPath) : ""
            results.append(Rendered(
                figure: relative, ok: ok, seconds: Date().timeIntervalSince(started),
                source: sourceHash, output: outputHash,
                outputPath: (outPath as NSString).lastPathComponent, log: log,
                unstable: unstable))
            if !ok { warn("FAILED \(relative)\(log.isEmpty ? "" : "\n" + log)") }
            note(progressPath, ok ? "." : "x")
        }
        return results
    }

    /// Split the work across child copies of this executable and merge what
    /// they report. Figures are dealt round-robin rather than in contiguous
    /// blocks, so the handful of slow figures spread across shards instead of
    /// landing in one and stranding the others (chapter neighbors tend to cost
    /// about the same, and they sort together).
    @MainActor
    private static func renderSharded(_ stale: [Work], workers: Int,
                                      verbose: Bool) -> [Rendered] {
        guard let executable = Bundle.main.executablePath else {
            die("cannot find this executable to shard")
        }
        let scratch = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("OllinGuideFigures-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: scratch,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: scratch) }

        var shards: [[Work]] = Array(repeating: [], count: workers)
        for (index, work) in stale.enumerated() { shards[index % workers].append(work) }

        var processes: [Process] = []
        var resultPaths: [String] = []
        var logPaths: [String] = []
        var progressPaths: [String] = []
        var shardWork: [[Work]] = []
        for (index, shard) in shards.enumerated() where !shard.isEmpty {
            let listPath = "\(scratch)/list-\(index).txt"
            let resultPath = "\(scratch)/results-\(index).json"
            let logPath = "\(scratch)/log-\(index).txt"
            let progressPath = "\(scratch)/progress-\(index)"
            try? shard.map(\.line).joined(separator: "\n").write(toFile: listPath,
                                                                 atomically: true, encoding: .utf8)
            FileManager.default.createFile(atPath: logPath, contents: nil)
            FileManager.default.createFile(atPath: progressPath, contents: nil)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["--list", listPath, "--results", resultPath,
                                 "--progress", progressPath]
            process.currentDirectoryURL = URL(fileURLWithPath:
                FileManager.default.currentDirectoryPath)
            if let handle = FileHandle(forWritingAtPath: logPath) {
                process.standardOutput = handle
                process.standardError = handle
            }
            do {
                try process.run()
            } catch {
                die("could not start a shard: \(error)")
            }
            processes.append(process)
            resultPaths.append(resultPath)
            logPaths.append(logPath)
            progressPaths.append(progressPath)
            shardWork.append(shard)
        }

        // Each shard appends one character per finished figure, so counting
        // bytes is the whole progress protocol.
        while processes.contains(where: \.isRunning) {
            report(progress: progressPaths, total: stale.count)
            Thread.sleep(forTimeInterval: 1)
        }
        for process in processes { process.waitUntilExit() }
        report(progress: progressPaths, total: stale.count)
        FileHandle.standardOutput.write(Data("\n".utf8))

        var results: [Rendered] = []
        for (index, path) in resultPaths.enumerated() {
            if let data = FileManager.default.contents(atPath: path),
               let decoded = try? JSONDecoder().decode([Rendered].self, from: data) {
                results.append(contentsOf: decoded)
            } else {
                // A shard that died before writing results (a crashing figure
                // takes the process with it) still has to name its figures, or
                // they would silently look untouched.
                let tail = String(((try? String(contentsOfFile: logPaths[index],
                                                encoding: .utf8)) ?? "")
                    .split(separator: "\n").suffix(20).joined(separator: "\n"))
                for work in shardWork[index] {
                    results.append(Rendered(figure: work.figure, ok: false, seconds: 0,
                                            source: "", output: "", outputPath: "",
                                            log: "shard exited without reporting\n\(tail)"))
                }
            }
            if verbose, let log = try? String(contentsOfFile: logPaths[index], encoding: .utf8) {
                print(log, terminator: "")
            }
        }
        return results
    }

    private static func report(progress paths: [String], total: Int) {
        var done = 0
        var failed = 0
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            done += data.count
            failed += data.filter { $0 == UInt8(ascii: "x") }.count
        }
        let percent = total == 0 ? 100 : Int((Double(done) / Double(total) * 100).rounded())
        let suffix = failed > 0 ? " · \(failed) failed" : ""
        FileHandle.standardOutput.write(Data(
            "\r  rendering \(done)/\(total) (\(percent)%)\(suffix)      ".utf8))
    }

    private static func note(_ path: String?, _ mark: String) {
        guard let path, let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(mark.utf8))
        try? handle.close()
    }

    /// The still-figure writer: the same headless render `--export` uses,
    /// encoded as JPEG at quality 0.85 (see the type comment for why).
    @MainActor
    private static func exportJPEG(_ sketch: Sketch, to path: String, frame: Int) {
        guard let cgImage = OllinApp.image(of: sketch, frame: frame) else {
            warn("render produced no image (no Metal device?)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg,
                                            properties: [.compressionFactor: 0.85]) else {
            warn("JPEG encode failed for \(path)")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Ollin: exported frame \(frame) → \(path) (\(cgImage.width)×\(cgImage.height))")
        } catch {
            warn("failed to write \(path): \(error)")
        }
    }

    // MARK: - Staleness

    /// Whether a figure's own source carries the `unstable` directive, read
    /// directly when the cache has no entry to say so.
    private static func directiveIsUnstable(_ relative: String,
                                            figuresDir: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: figuresDir + "/" + relative),
              let source = String(data: data, encoding: .utf8) else { return false }
        return Directive(source: source).unstable
    }

    /// Whether a figure's own source still matches what the cache recorded,
    /// regardless of the framework digest that may have invalidated the entry.
    private static func unchanged(_ relative: String, cache: Cache,
                                  figuresDir: String) -> Bool {
        guard let entry = cache.figures[relative],
              let source = FileManager.default.contents(atPath: figuresDir + "/" + relative)
        else { return false }
        return hex(SHA256.hash(data: source)) == entry.source
    }

    private static func isStale(_ relative: String, cache: Cache,
                                figuresDir: String, imagesDir: String) -> Bool {
        guard let entry = cache.figures[relative] else { return true }
        guard let source = FileManager.default.contents(atPath: figuresDir + "/" + relative),
              hex(SHA256.hash(data: source)) == entry.source else { return true }
        let stem = (relative as NSString).deletingPathExtension
        let image = imagesDir + "/" + (stem as NSString).deletingLastPathComponent
            + "/" + entry.outputPath
        guard FileManager.default.fileExists(atPath: image) else { return true }
        // A figure marked `unstable` renders differently every time, so its
        // committed image says nothing about whether it needs redoing.
        if entry.unstable { return false }
        return fileHash(image) != entry.output
    }

    /// Everything outside a figure's own file that changes what it renders: the
    /// framework sources (Swift, and the `.metal` and asset resources beside
    /// them), the vendored C, the manifest, and the compiler.
    private static func frameworkDigest(root: String) -> String {
        var hasher = SHA256()
        let manager = FileManager.default
        for directory in ["Sources", "External"] {
            let base = root + "/" + directory
            var paths: [String] = []
            let enumerator = manager.enumerator(atPath: base)
            while let relative = enumerator?.nextObject() as? String {
                // Skip dotfiles: a stray .DS_Store must not invalidate the world.
                if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                    continue
                }
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: base + "/" + relative,
                                         isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }
                paths.append(relative)
            }
            paths.sort()
            for relative in paths {
                hasher.update(data: Data("\(directory)/\(relative)".utf8))
                if let data = manager.contents(atPath: base + "/" + relative) {
                    hasher.update(data: data)
                }
            }
        }
        for file in ["Package.swift", "Package.resolved"] {
            guard let data = manager.contents(atPath: root + "/" + file) else { continue }
            hasher.update(data: Data(file.utf8))
            hasher.update(data: data)
        }
        hasher.update(data: Data(toolchainVersion().utf8))
        return hex(hasher.finalize())
    }

    /// The compiler's own version string. A toolchain upgrade can change what a
    /// figure renders, and it leaves no trace in the sources.
    private static func toolchainVersion() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "unknown" }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? "unknown"
    }

    // MARK: - Cache storage

    private static func loadCache(_ path: String) -> Cache {
        guard let data = FileManager.default.contents(atPath: path),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return Cache(version: Cache.currentVersion, framework: "", figures: [:])
        }
        return cache
    }

    private static func saveCache(_ cache: Cache, to path: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// The slowest figures, so a session can see where a full run's time goes
    /// (and so the next person to wonder does not have to measure it again).
    private static func reportSlowest(cache: Cache, among figures: [String]) {
        let timed = figures.compactMap { figure -> (String, Double)? in
            guard let seconds = cache.figures[figure]?.seconds, seconds >= 5 else { return nil }
            return (figure, seconds)
        }.sorted { $0.1 > $1.1 }.prefix(6)
        guard !timed.isEmpty else { return }
        let total = figures.compactMap { cache.figures[$0]?.seconds }.reduce(0, +)
        print("guide-figures: a full run costs about \(format(total)); the slowest figures are")
        for (figure, seconds) in timed {
            print("  \(format(seconds).padding(toLength: 8, withPad: " ", startingAt: 0)) \(figure)")
        }
    }

    // MARK: - Helpers

    private static var defaultJobs: Int {
        // Four is a deliberate ceiling rather than the core count: each shard is
        // a full Metal process, and they share one GPU and this machine's memory.
        min(4, max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    private static func fileHash(_ path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path) else { return "" }
        return hex(SHA256.hash(data: data))
    }

    private static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func format(_ seconds: Double) -> String {
        seconds < 60 ? String(format: "%.1fs", seconds)
            : String(format: "%dm %02ds", Int(seconds) / 60, Int(seconds) % 60)
    }

    private static func plural(_ count: Int) -> String { count == 1 ? "" : "s" }

    private static func usage() -> Never {
        print("""
        OllinGuideFigures: render the Guide's figure sketches to Guide/Images.

          --only <substring>   only figures whose path contains this
          --force              re-render even figures the cache calls unchanged
          --jobs <n>           worker processes (default \(defaultJobs))
          --verbose            print each shard's full log
          --help               this message

        Unchanged figures are skipped using Guide/.figure-cache.json, which is
        keyed on each figure's source, its rendered image, and a digest of the
        framework. Editing anything under Sources/ or External/ re-renders
        everything, since that can change what any figure draws. A --only run
        after such an edit renders just its matches and leaves the cache
        untouched, so the next full run still re-renders everything.

        A figure whose first line carries `// figure: unstable` is cached on its
        source alone: its render is genuinely not reproducible, so its committed
        image cannot say whether it needs redoing.
        """)
        exit(0)
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("guide-figures: \(message)\n".utf8))
    }

    private static func die(_ message: String) -> Never {
        warn(message)
        exit(2)
    }
}
