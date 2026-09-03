import AppKit
import CryptoKit
import Foundation
import ImageIO
import Ollin
import OllinRuntime

/// `swift run OllinGuideFigures [options]` renders every figure sketch, the
/// chapters' (`Guide/Figures/**/*.swift`, to `Guide/Images/<chapter>/`) and
/// the reference pages' own (`Docs/Figures/*.swift`, to `Docs/Images/`,
/// keyed with a `Docs/` prefix), and exits nonzero
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
/// - **A probe sample.** Most framework edits move no pixels at all, so a
///   framework change renders the figures marked `// figure: probe` first (a
///   sample chosen to witness every drawing path) and compares each, pixel for
///   pixel, to the image committed beside it. All identical means the change
///   was render-neutral, and the rest keep their cache entries.
///
/// One rule spans both: **"changed" means the pixels, never the bytes, and a
/// move the framework made on its own has to be visible.** The JPEG and PNG
/// encoders here are not byte-deterministic, so a fresh render of an unchanged
/// figure can encode to different bytes with identical pixels. A render
/// therefore lands in a dot-temp beside the committed image and replaces it
/// only when the decoded pixels moved (`promote`), and a move the framework
/// caused counts only past the visible threshold in `Movement`; a figure whose
/// own source changed is recorded exactly, since its author meant the new
/// picture. Without the first half, every full pass leaves a few byte-churned
/// images dirty in the working tree; without the second, a sub-perceptual
/// framework change rewrites megabytes of identical-looking JPEGs into git
/// history, which is most of what that history weighs.
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
        /// `probe` puts a figure in the sample rendered first when the
        /// framework changes, to find out whether the change moved any pixels
        /// at all. Mark a figure that is the cheapest honest witness for one
        /// drawing path, and never an `unstable` one, whose render cannot be
        /// compared to anything.
        var probe = false
        /// `themed` renders the figure twice: once as committed (`<Name>.jpg`)
        /// and once with its `darkTheme` parameter flipped on (`<Name>-dark.jpg`),
        /// so a page can serve the dark variant through a `<picture>` tag.
        /// The figure declares `@Param var darkTheme = false` and keys its
        /// palette on it; the runner sets the parameter between the two renders of
        /// the same instance, so a themed figure must draw the same under a
        /// second `setup()` pass (assign state, never append). Stills only.
        var themed = false

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
                case ("probe", _): probe = true
                case ("themed", _): themed = true
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
            /// A `themed` figure's dark sibling (`<Name>-dark.jpg`): its file
            /// name and hash, checked for staleness beside the light image.
            var darkOutput: String?
            var darkPath: String?
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
        var darkOutput: String?
        var darkPath: String?
        /// A recording render that moved below the visible threshold and so
        /// kept the committed image, described for the end-of-run report.
        var note = ""
        /// How far a probe's render sits from the image committed beside it
        /// (the larger move of the two, for a themed figure).
        var movement: Movement?
    }

    /// One figure to render, plus what may happen to its committed image.
    /// `verifyOnly` is set for an `unstable` figure that is being redone only
    /// because the framework moved: the render still has to succeed, but its
    /// image is arbitrary, so overwriting it would report a change that means
    /// nothing and leave a diff to throw away. `probeOnly` also leaves the
    /// committed image alone, but it *measures* the fresh render against it
    /// instead of discarding it, which is how the probe phase learns whether
    /// the pixels moved. `exact` replaces the committed image on any pixel
    /// move rather than only a visible one: set when the figure's own source
    /// changed (its author meant the new picture) and under `--exact`.
    struct Work {
        var figure: String
        var verifyOnly: Bool
        var probeOnly = false
        var exact = false

        init(figure: String, verifyOnly: Bool, probeOnly: Bool = false, exact: Bool = false) {
            self.figure = figure
            self.verifyOnly = verifyOnly
            self.probeOnly = probeOnly
            self.exact = exact
        }

        init(line: String) {
            let parts = line.split(separator: "\t").map(String.init)
            figure = parts[0]
            let flags = parts.dropFirst()
            verifyOnly = flags.contains("verify")
            probeOnly = flags.contains("probe")
            exact = flags.contains("exact")
        }

        var line: String {
            var flags: [String] = []
            if probeOnly {
                flags.append("probe")
            } else if verifyOnly {
                flags.append("verify")
            }
            if exact { flags.append("exact") }
            return ([figure] + flags).joined(separator: "\t")
        }
    }

    // MARK: - Entry point

    @MainActor
    static func main() {
        // Line buffering, so the progress line (written straight to the file
        // handle) stays in order with the ordinary prints when output is piped.
        setvbuf(stdout, nil, _IOLBF, 0)

        var only: String?
        var force = false
        var exact = false
        var verbose = false
        var jobs = defaultJobs
        var listPath: String?
        var resultsPath: String?
        var progressPath: String?
        var compare: (String, String)?

        var probing = true
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
            case "--exact": exact = true
            case "--no-probe": probing = false
            case "--verbose": verbose = true
            case "--jobs": jobs = max(1, Int(value("--jobs")) ?? 1)
            case "--list": listPath = value("--list")
            case "--results": resultsPath = value("--results")
            case "--progress": progressPath = value("--progress")
            case "--compare":
                let first = value("--compare")
                compare = (first, value("--compare"))
            case "--help", "-h": usage()
            default:
                die("unknown argument '\(argument)'; try --help")
            }
        }

        // A measurement on its own: how far one image sits from another, and
        // which side of the visible threshold that lands on.
        if let (first, second) = compare {
            let movement = Movement.between(first, and: second)
            let verdict = movement.identical ? "identical"
                : movement.isVisible ? "a visible change" : "below the visible threshold"
            print("\(movement.summary): \(verdict)")
            exit(0)
        }

        let root = FileManager.default.currentDirectoryPath

        // Shard mode: render exactly the listed figures, report back as JSON,
        // touch no cache. The parent owns all cache and reporting decisions.
        if let listPath, let resultsPath {
            let list = ((try? String(contentsOfFile: listPath, encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                .map(Work.init(line:))
            let results = render(list, root: root,
                                 progressPath: progressPath, echo: true)
            if let data = try? JSONEncoder().encode(results) {
                try? data.write(to: URL(fileURLWithPath: resultsPath))
            }
            exit(results.contains { !$0.ok } ? 1 : 0)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root + "/Guide/Figures",
                                             isDirectory: &isDirectory),
              isDirectory.boolValue else {
            die("Guide/Figures not found under \(root); run from the repository root")
        }

        // Deterministic order so runs (and their logs) are comparable. The
        // Docs pages' own figures live in their own tree but key with a
        // `Docs/` prefix, so both trees share one work list and one cache.
        var figures: [String] = []
        for (tree, prefix) in [("/Guide/Figures", ""), ("/Docs/Figures", "Docs/")] {
            let enumerator = FileManager.default.enumerator(atPath: root + tree)
            while let relative = enumerator?.nextObject() as? String {
                if relative.hasSuffix(".swift") { figures.append(prefix + relative) }
            }
        }
        figures.sort()
        if let only {
            figures = figures.filter { $0.range(of: only, options: .caseInsensitive) != nil }
            if figures.isEmpty { die("no figure matches --only \(only)") }
        }
        guard !figures.isEmpty else {
            print("guide-figures: no figure sketches found, nothing to render")
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
                // Most framework edits move no pixels at all: a new function, a
                // comment, a type nothing draws through. Rendering the whole
                // suite to learn that costs ten minutes, so render the probe
                // sample first and ask. A probe is only trusted when it is
                // *identical*, and any probe that moved or failed hands the run
                // back to the full re-render below.
                if only == nil, !force, cache.version == Cache.currentVersion,
                   !cache.figures.isEmpty, probing,
                   case let sample = probeFigures(figures, root: root),
                   !sample.isEmpty {
                    let moved = runProbe(sample, root: root, jobs: jobs, verbose: verbose)
                    if moved.isEmpty {
                        cache.framework = digest
                        saveCache(cache, to: cachePath)
                        print("guide-figures: the framework changed, but all"
                              + " \(sample.count) probe figure\(plural(sample.count)) drew the"
                              + " same pixels, so the rest are left alone."
                              + " Run with --no-probe to re-render everything anyway.")
                        exit(0)
                    }
                    // Any move at all hands the run to the full render, since
                    // a change too small to see on the sample can still be
                    // visible on a figure it never looked at; the full render
                    // then rewrites only the images that moved visibly.
                    print("guide-figures: the probe found \(moved.count)"
                          + " figure\(plural(moved.count)) whose pixels moved, so every"
                          + " figure is re-rendered; only a visible move rewrites"
                          + " a committed image")
                    for (figure, movement) in moved {
                        print("  \(figure): \(movement?.summary ?? "failed to render")")
                    }
                    cache = Cache(version: Cache.currentVersion, framework: digest, figures: [:])
                } else if !cache.figures.isEmpty {
                    print("guide-figures: the framework changed, so every figure is re-rendered")
                    cache = Cache(version: Cache.currentVersion, framework: digest, figures: [:])
                } else {
                    cache = Cache(version: Cache.currentVersion, framework: digest, figures: [:])
                }
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
            isStale($0, cache: cache, root: root)
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
        // A figure whose own source changed is recorded exactly: its author
        // meant the new picture, however small the move. Only a render the
        // framework moved on its own is held to the visible threshold (see
        // `Movement`), and with no cache entry to say which it was, the
        // threshold applies, so a fresh clone does not rewrite every drifted
        // figure the first time it renders.
        let stale = staleFigures.map { figure -> Work in
            let verifyOnly: Bool
            var sourceChanged = false
            if let entry = previous.figures[figure] {
                let same = unchanged(figure, cache: previous, root: root)
                verifyOnly = entry.unstable && same
                sourceChanged = !same
            } else {
                verifyOnly = directiveIsUnstable(figure, root: root)
            }
            return Work(figure: figure, verifyOnly: verifyOnly, exact: exact || sourceChanged)
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
            results = render(stale, root: root, progressPath: nil, echo: true)
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
                unstable: result.unstable, darkOutput: result.darkOutput,
                darkPath: result.darkPath)
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
        let held = results.filter { $0.ok && !$0.note.isEmpty }
        if !held.isEmpty {
            print("guide-figures: \(held.count) figure\(plural(held.count)) moved below the"
                  + " visible threshold and kept \(held.count == 1 ? "its" : "their")"
                  + " committed image (--exact rewrites them anyway):")
            for result in held { print("  \(result.figure): \(result.note)") }
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

    // MARK: - The probe

    /// The figures marked `// figure: probe`, minus any that cannot be
    /// compared. An `unstable` figure renders differently every time, so a
    /// probe made of one would report a change on every run and the sample
    /// would never pass.
    private static func probeFigures(_ figures: [String], root: String) -> [String] {
        figures.filter { figure in
            guard let data = FileManager.default.contents(atPath: sourceFile(figure, root: root)),
                  let source = String(data: data, encoding: .utf8) else { return false }
            let directive = Directive(source: source)
            if directive.probe, directive.unstable {
                warn("\(figure) is marked both probe and unstable; ignoring the probe mark")
                return false
            }
            return directive.probe
        }
    }

    /// Render the sample and report which of them no longer match the image
    /// committed beside them, each with how far it moved. A figure that fails
    /// to render counts as changed, with no measurement: the point of the
    /// probe is to hand any doubt to the full run.
    @MainActor
    private static func runProbe(_ sample: [String], root: String, jobs: Int,
                                 verbose: Bool) -> [(figure: String, movement: Movement?)] {
        print("guide-figures: the framework changed; probing \(sample.count)"
              + " figure\(plural(sample.count)) to see whether it moved any pixels")
        let work = sample.map { Work(figure: $0, verifyOnly: false, probeOnly: true) }
        let workers = min(jobs, work.count)
        let results = workers <= 1
            ? render(work, root: root, progressPath: nil, echo: verbose)
            : renderSharded(work, workers: workers, verbose: verbose)
        return results.compactMap { result -> (figure: String, movement: Movement?)? in
            guard result.ok, let movement = result.movement else { return (result.figure, nil) }
            return movement.identical ? nil : (result.figure, movement)
        }.sorted { $0.figure < $1.figure }
    }

    // MARK: - Rendering

    /// Compile and render each listed figure in this process, in order. The
    /// serial heart of the runner: everything else decides *which* figures get
    /// here and how many processes are doing it at once.
    @MainActor
    private static func render(_ list: [Work], root: String,
                               progressPath: String?, echo: Bool) -> [Rendered] {
        var results: [Rendered] = []
        for work in list {
            let relative = work.figure
            let sourcePath = sourceFile(relative, root: root)
            let started = Date()
            var log = ""
            var outPath = ""
            var sourceHash = ""
            var ok = false
            var unstable = false
            var held = ""
            var movement: Movement?
            var darkOutPath: String?

            if let data = FileManager.default.contents(atPath: sourcePath),
               let source = String(data: data, encoding: .utf8) {
                sourceHash = hex(SHA256.hash(data: data))
                let directive = Directive(source: source)
                unstable = directive.unstable
                let stem = (relative as NSString).deletingPathExtension
                let name = (stem as NSString).lastPathComponent
                    + (directive.gif ? ".gif" : directive.stillExtension)
                let directory = imageFolder(relative, root: root)
                outPath = directory + "/" + name
                try? FileManager.default.createDirectory(
                    atPath: directory, withIntermediateDirectories: true)

                // Verifying rather than recording: render beside the committed
                // image and throw the result away. Probing is the same detour
                // with the result measured against the committed image first,
                // so the caller learns how far it moved without that image ever
                // being overwritten. And a recording render goes to a dot-temp
                // too, promoted over the committed image only when the picture
                // actually changed (see the type comment on byte-nondeterministic
                // encoders and the visible threshold).
                let verifying = work.verifyOnly
                    && FileManager.default.fileExists(atPath: outPath)
                let probing = work.probeOnly
                let writePath = verifying || probing
                    ? directory + "/." + (probing ? "probe-" : "verify-") + name
                    : directory + "/.new-" + name

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
                    // The dark pass: flip the figure's own parameter and render the
                    // same instance again, beside the light image.
                    if ok, directive.themed {
                        if directive.gif {
                            warn("\(relative): themed is still-only; ignoring it for a GIF")
                        } else if let parameter = sketch.parameters()
                            .first(where: { $0.name == "darkTheme" }) {
                            let darkName = ((stem as NSString).lastPathComponent)
                                + "-dark" + directive.stillExtension
                            let darkWrite = verifying || probing
                                ? directory + "/." + (probing ? "probe-" : "verify-") + darkName
                                : directory + "/.new-" + darkName
                            parameter.param.restore(.boolean(true))
                            if directive.png {
                                OllinApp.export(sketch, to: darkWrite, frame: directive.frame)
                            } else {
                                exportJPEG(sketch, to: darkWrite, frame: directive.frame)
                            }
                            if FileManager.default.fileExists(atPath: darkWrite) {
                                darkOutPath = directory + "/" + darkName
                                if probing {
                                    movement = Movement.between(darkWrite,
                                                                and: directory + "/" + darkName)
                                }
                            } else {
                                ok = false
                                log = "no dark output written"
                            }
                            if verifying || probing {
                                try? FileManager.default.removeItem(atPath: darkWrite)
                            } else if ok, let kept = promote(darkWrite, over: directory + "/" + darkName,
                                                             exact: work.exact) {
                                held = "dark: " + kept
                            }
                        } else {
                            ok = false
                            log = "themed, but the figure declares no"
                                + " `@Param var darkTheme = false` parameter to flip"
                        }
                    }
                    if probing {
                        let light = Movement.between(writePath, and: outPath)
                        movement = movement.map { Movement.larger($0, light) } ?? light
                    }
                    if verifying || probing {
                        try? FileManager.default.removeItem(atPath: writePath)
                    } else if ok, let kept = promote(writePath, over: outPath, exact: work.exact) {
                        held = held.isEmpty ? kept : kept + "; " + held
                    }
                case .failure(let error):
                    log = "\(error)"
                }
            } else {
                log = "unreadable"
            }

            // A probe reports how far it moved; everything else reports the
            // hash of the image now on disk.
            let outputHash = ok && !unstable && !work.probeOnly ? fileHash(outPath) : ""
            var darkHash: String?
            if let darkOutPath, ok, !unstable, !work.probeOnly {
                darkHash = fileHash(darkOutPath)
            }
            results.append(Rendered(
                figure: relative, ok: ok, seconds: Date().timeIntervalSince(started),
                source: sourceHash, output: outputHash,
                outputPath: (outPath as NSString).lastPathComponent, log: log,
                unstable: unstable, darkOutput: darkHash,
                darkPath: darkOutPath.map { ($0 as NSString).lastPathComponent },
                note: held, movement: work.probeOnly ? movement : nil))
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

    // MARK: - The two figure trees

    /// Where a figure key lives. A chapter figure keys as
    /// `<chapter>/<Name>.swift` under `Guide/Figures`, rendering to
    /// `Guide/Images/<chapter>/`; a `Docs/` prefix routes the key to the
    /// reference pages' own `Docs/Figures`, rendering to `Docs/Images`. The
    /// prefix is part of the key, not a folder under the Guide: cache
    /// entries, shard lists, and `--only` matches all name figures by key,
    /// so both trees share one namespace here.
    private static func trees(_ figure: String) -> (figures: String, images: String, path: String) {
        if figure.hasPrefix("Docs/") {
            return ("/Docs/Figures", "/Docs/Images", String(figure.dropFirst("Docs/".count)))
        }
        return ("/Guide/Figures", "/Guide/Images", figure)
    }

    /// The figure key's source file on disk.
    private static func sourceFile(_ figure: String, root: String) -> String {
        let tree = trees(figure)
        return root + tree.figures + "/" + tree.path
    }

    /// The folder the figure's rendered images belong in, light and dark.
    private static func imageFolder(_ figure: String, root: String) -> String {
        let tree = trees(figure)
        let parent = (tree.path as NSString).deletingLastPathComponent
        return root + tree.images + (parent.isEmpty ? "" : "/" + parent)
    }

    // MARK: - Staleness

    /// Whether a figure's own source carries the `unstable` directive, read
    /// directly when the cache has no entry to say so.
    private static func directiveIsUnstable(_ relative: String,
                                            root: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: sourceFile(relative, root: root)),
              let source = String(data: data, encoding: .utf8) else { return false }
        return Directive(source: source).unstable
    }

    /// Whether a figure's own source still matches what the cache recorded,
    /// regardless of the framework digest that may have invalidated the entry.
    private static func unchanged(_ relative: String, cache: Cache,
                                  root: String) -> Bool {
        guard let entry = cache.figures[relative],
              let source = FileManager.default.contents(atPath: sourceFile(relative, root: root))
        else { return false }
        return hex(SHA256.hash(data: source)) == entry.source
    }

    private static func isStale(_ relative: String, cache: Cache,
                                root: String) -> Bool {
        guard let entry = cache.figures[relative] else { return true }
        guard let source = FileManager.default.contents(atPath: sourceFile(relative, root: root)),
              hex(SHA256.hash(data: source)) == entry.source else { return true }
        let image = imageFolder(relative, root: root) + "/" + entry.outputPath
        guard FileManager.default.fileExists(atPath: image) else { return true }
        // A themed figure's dark sibling is part of its output: missing or
        // hand-edited means the figure needs redoing, same as the light one.
        if let darkPath = entry.darkPath {
            let dark = imageFolder(relative, root: root) + "/" + darkPath
            guard FileManager.default.fileExists(atPath: dark) else { return true }
            if !entry.unstable, fileHash(dark) != (entry.darkOutput ?? "") { return true }
        }
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
        print("guide-figures: \(figures.count) figures, about \(format(total)) of"
              + " summed render time (wall clock divides by the workers);"
              + " the slowest are")
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

    /// One frame of an image file, decoded to tightly packed RGBA8.
    struct Frame {
        var width: Int
        var height: Int
        var pixels: Data
    }

    /// Every frame of an image file decoded to pixels (a still has one, a GIF
    /// its whole loop), or nil when the file does not decode.
    private static func decodedFrames(_ path: String) -> [Frame]? {
        guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        var frames: [Frame] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let context = CGContext(
                    data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0,
                                           width: image.width, height: image.height))
            guard let data = context.data else { return nil }
            frames.append(Frame(width: image.width, height: image.height,
                                pixels: Data(bytes: data,
                                             count: image.width * image.height * 4)))
        }
        return frames
    }

    /// A hash of what an image *shows* rather than the bytes that encode it:
    /// every frame decoded to tightly packed RGBA8 and hashed. The JPEG and PNG
    /// encoders here are not byte-deterministic, so a byte comparison reports
    /// change where a reader could never see one; this comparison means "the
    /// pixels moved". Falls back to the byte hash when the file does not decode.
    private static func pixelHash(_ path: String) -> String {
        guard let frames = decodedFrames(path) else { return fileHash(path) }
        var hasher = SHA256()
        for frame in frames { hasher.update(data: frame.pixels) }
        return hex(hasher.finalize())
    }

    /// How far one image moved from another, over every frame, in the terms
    /// that decide whether a reader could see it. A framework change that
    /// shifts a stroke's anti-aliasing by a level or two moves pixels in most
    /// figures and is invisible in all of them, and rewriting the JPEGs for
    /// that is what filled the repository's history with figures nobody can
    /// tell apart. So a render the framework moved on its own replaces the
    /// committed image only when the move is visible by one of two measures,
    /// calibrated against every figure rewrite in the history: a patch of
    /// pixels moved hard (more than `strongLevel` levels in some channel, over
    /// at least `strongFraction` of the image), which is a label, a shape, or
    /// a highlight that changed; or the whole picture drifted (a mean
    /// difference of `meanThreshold` levels or more per channel, twice what
    /// the snapshot suite tolerates), which is a tone or palette shift. Under
    /// both, the committed image stays. The measured classes sit apart: the
    /// largest invisible moves in the history reach 0.12% of pixels past 32
    /// levels, or a mean of 2.1 with almost none past it, while the smallest
    /// visible one, a marker that moved to the other corner, is 0.32%.
    struct Movement: Codable {
        static let strongLevel = 32
        static let strongFraction = 0.002
        static let meanThreshold = 4.0

        /// Mean absolute difference per channel, in 8-bit levels.
        var mean: Double
        /// The fraction of pixels where some channel moved past `strongLevel`.
        var strong: Double
        /// The two could not be compared (a different size or frame count, or
        /// a file that does not decode); counts as visible.
        var incomparable = false

        var identical: Bool { !incomparable && mean == 0 && strong == 0 }
        var isVisible: Bool {
            incomparable || mean >= Self.meanThreshold || strong >= Self.strongFraction
        }

        var summary: String {
            if incomparable { return "a different size or frame count" }
            return String(format: "mean %.2f levels, %.2f%% of pixels moved more than %d levels",
                          mean, strong * 100, Self.strongLevel)
        }

        /// The larger of two moves, measure by measure, for a themed figure's
        /// pair of renders.
        static func larger(_ a: Movement, _ b: Movement) -> Movement {
            if a.incomparable { return a }
            if b.incomparable { return b }
            return Movement(mean: max(a.mean, b.mean), strong: max(a.strong, b.strong))
        }

        static func between(_ fresh: String, and committed: String) -> Movement {
            let incomparable = Movement(mean: 0, strong: 0, incomparable: true)
            guard let a = decodedFrames(fresh), let b = decodedFrames(committed),
                  a.count == b.count, !a.isEmpty else { return incomparable }
            var sum = 0
            var strong = 0
            var pixels = 0
            for (fa, fb) in zip(a, b) {
                guard fa.width == fb.width, fa.height == fb.height else { return incomparable }
                pixels += fa.width * fa.height
                fa.pixels.withUnsafeBytes { pa in
                    fb.pixels.withUnsafeBytes { pb in
                        for i in stride(from: 0, to: pa.count, by: 4) {
                            var worst = 0
                            for c in 0..<3 {
                                let d = abs(Int(pa[i + c]) - Int(pb[i + c]))
                                sum += d
                                if d > worst { worst = d }
                            }
                            if worst > strongLevel { strong += 1 }
                        }
                    }
                }
            }
            return Movement(mean: Double(sum) / Double(pixels * 3),
                            strong: Double(strong) / Double(pixels))
        }
    }

    /// Put a fresh render into place. The committed file stays when the new
    /// pixels are identical, so a nondeterministic encoder cannot churn the
    /// working tree, and, unless `exact`, when they moved below the visible
    /// threshold (see `Movement`); it is replaced when the picture changed.
    /// Returns the description of a move that was held back, for the report.
    private static func promote(_ fresh: String, over committed: String,
                                exact: Bool) -> String? {
        let manager = FileManager.default
        if manager.fileExists(atPath: committed) {
            let movement = Movement.between(fresh, and: committed)
            if movement.identical || (!exact && !movement.isVisible) {
                try? manager.removeItem(atPath: fresh)
                return movement.identical ? nil : movement.summary
            }
        }
        try? manager.removeItem(atPath: committed)
        try? manager.moveItem(atPath: fresh, toPath: committed)
        return nil
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
        OllinGuideFigures: render the Guide's and Docs' figure sketches to
        their Images trees.

          --only <substring>   only figures whose path contains this
          --force              re-render even figures the cache calls unchanged
          --exact              rewrite a committed image on any pixel move,
                               not only a visible one
          --no-probe           skip the probe sample; re-render everything
          --jobs <n>           worker processes (default \(defaultJobs))
          --verbose            print each shard's full log
          --compare <a> <b>    measure how far one image moved from another,
                               and say which side of the threshold it lands on
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

        A figure carrying `// figure: themed` renders twice, flipping its own
        `@Param var darkTheme = false` parameter for a `<Name>-dark` sibling image,
        which pages serve to dark-mode readers through a <picture> tag.

        Most framework edits move no pixels: a new function, a comment, a type
        nothing draws through. So a framework change first renders the figures
        marked `// figure: probe`, a sample covering every drawing path, and
        compares each, pixel for pixel, to the image committed beside it. All
        identical means the change was render-neutral and the rest are left
        alone, which turns a ten minute gate into about fifteen seconds. Any
        probe that moved or failed hands the run back to the full re-render.
        --no-probe skips the sample and re-renders everything.

        Every comparison here is of decoded pixels, never encoded bytes: the
        JPEG/PNG encoders are not byte-deterministic, so a fresh render replaces
        a committed image only when the picture actually changed. And a move
        the framework made on its own has to be visible to count: at least
        \(String(format: "%.1f", Movement.strongFraction * 100))% of the pixels moved by
        more than \(Movement.strongLevel) levels, or a mean difference of
        \(String(format: "%.0f", Movement.meanThreshold)) levels or more per channel.
        Below that the committed image stays, and the run lists what it held.
        A figure whose own source changed is recorded on any move, since its
        author meant the new picture; --exact treats every figure that way.
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
