import Foundation
import Observation
import Ollin

/// Host-agnostic hot-swap orchestration shared by the live hosts: schedules
/// compiles off the main actor with supersede-cancel semantics, re-applies
/// user-tuned parameter values before each swap, and carries the two-channel
/// error model (sketch compile vs user shader). A host supplies the *trigger*
/// (a file watcher, an editor's evaluate command) and the presentation (status
/// chips, overlays, prints); this owns the invariants that must not drift
/// between hosts:
///
/// - A newer evaluation always supersedes an in-flight one, so a slower older
///   compile can never land last and swap in stale code.
/// - Tuned parameter values are re-applied to the fresh sketch *before* the
///   swap, so a parameter never visibly snaps back.
/// - A failed compile leaves the running sketch untouched.
/// - The sketch-compile error and the user-shader error are independent
///   channels: fixing one never clears the other.
/// - Under two-speed evaluation (`landsPlainBuildFirst`) the plain build is
///   the one the host hears about, and the optimized build behind it swaps
///   in silently with the clock carried, so a set never sees it land.
@MainActor
@Observable
public final class SketchSession {
    /// The evaluation lifecycle. `.idle` means nothing is in flight that the
    /// host waits on (a sketch may well be running, and an optimized build may
    /// still be on its way; see `isOptimizing`); `.failed` carries the raw
    /// compiler log.
    public enum Phase: Equatable, Sendable {
        case idle
        case compiling
        case failed(String)
    }

    /// The sketch to host. `nil` until the first compile lands; set by the
    /// first build that lands (the host's view then builds the runner with
    /// it), and again by an optimized build that lands behind a plain one
    /// before any runner exists. Later evaluations swap inside the runner,
    /// not through this.
    public private(set) var sketch: Sketch?
    /// The instance actually drawing right now: the runner's, once one exists,
    /// because later evaluations swap inside the runner while `sketch` stays
    /// the first mount. Anything addressed to "the sketch on stage" (the live
    /// recorder, a host control) goes through this.
    public var currentSketch: Sketch? { runner?.sketch ?? sketch }
    public private(set) var phase: Phase = .idle
    /// Runner-reload count: bumped once per evaluation that lands after the
    /// first mount (the optimized swap behind a plain build is the same
    /// evaluation, so it does not count again). `reloadCount == 0` inside
    /// `onSuccess` identifies the first mount.
    public private(set) var reloadCount = 0
    /// Wall-clock seconds from the evaluation to its first swap (compile +
    /// load), the wait the performer saw. `nil` until the first reload (the
    /// initial mount doesn't count).
    public private(set) var lastBuildSeconds: Double?
    /// Whether an evaluation lands a plain build first. On, the buffer
    /// compiles twice at once, plain (`-Onone`) and optimized (`-O`): the
    /// plain build swaps in the moment it compiles and the optimized build
    /// replaces it when it is ready, the clock carried across that second
    /// swap whatever the first one did, so the edit is on stage before the
    /// optimized compile alone would have put it there. Off, the one
    /// optimized build swaps in when it is ready. Moot under a loader that
    /// compiles plain (`--no-optimize`), where there is only the one build.
    ///
    /// What it buys is the gap between the two compiles, which is the
    /// optimizer's own share of the time: about a third on a sketch of a few
    /// hundred lines, and nothing on a small one, whose compile is all module
    /// loading and linking. What it costs is a second fresh instance: the
    /// second swap runs `setup()` again and fires `reloaded()` again, so a
    /// sketch that accumulates state starts over twice, a fraction of a
    /// second apart, unless the evaluation carried the run (`keepRun`), which
    /// the second swap carries too. The host's flag that turns it off is for
    /// the sketch that cannot.
    public var landsPlainBuildFirst: Bool
    /// Whether the optimized build of the sketch on stage is still compiling:
    /// a plain build has swapped in and the optimized one has not yet replaced
    /// it. False the moment it does, or when it fails (the plain build then
    /// stays).
    public private(set) var isOptimizing = false
    /// The running sketch's `@Param` parameters, for the host's inspector surface.
    public private(set) var params: [ParamHandle] = []
    /// A user shader's compile error, reported by the runner after a frame
    /// (`nil` when every shader compiles). Distinct from `phase`, which tracks
    /// the Swift compile, so the two error kinds don't clear each other.
    public private(set) var shaderError: String?
    public private(set) var runner: SketchRunner?
    /// Live performance numbers of the running sketch, shared with the runner
    /// (pass it to `SketchView(stats:)`) so every surface reads one source.
    @ObservationIgnored public let stats = FrameStats()
    /// Whether evaluations carry `time`/`frameCount` across the swap by
    /// default; `evaluate`'s `keepClock` argument overrides per call.
    public var keepClock: Bool
    /// The automation the host carries: the launch file's tracks, then
    /// whatever the timeline panel authored. Re-installed on each freshly
    /// loaded sketch before its `setup()` runs, so the tracks survive a swap;
    /// `setup()`'s own `automate(...)` calls then win per parameter, the same
    /// precedence a file has everywhere else.
    public var automation: Automation?

    /// The cues the running sketch carries, for the inspector's card. Kept
    /// across swaps like the automation: the sheet is re-installed on each
    /// freshly loaded sketch before its `setup()` runs.
    public private(set) var cues: [Cue] = []
    /// The file the cue sheet round-trips through (`Sketch.cues.json` beside
    /// the sketch), written after every save and delete; nil keeps the cues
    /// in memory for the session.
    public var cueFile: String?
    @ObservationIgnored private var cueSheet: CueSheet?

    /// The in-flight compile, kept so a newer evaluation can cancel it. (The
    /// detached `swiftc` still runs to completion; its result is refused.)
    @ObservationIgnored private var compileTask: Task<Void, Never>?
    /// User-tuned parameter values, keyed by name, re-applied to each freshly
    /// loaded sketch so a parameter doesn't snap back. Only values the user actually
    /// changed are stored, so editing a default in code still takes effect.
    @ObservationIgnored private var paramValues: [String: ParamStored] = [:]
    /// A variation seed the user navigated to, re-applied to each freshly
    /// loaded sketch (before its `setup()`) so the composition doesn't shuffle
    /// under an edit. Only set once the user actually touches the seed card,
    /// so an untouched session keeps rolling fresh variations per reload.
    @ObservationIgnored private var navigatedSeed: Int?

    public init(keepClock: Bool = false, landsPlainBuildFirst: Bool = false) {
        self.keepClock = keepClock
        self.landsPlainBuildFirst = landsPlainBuildFirst
    }

    /// The error a host's overlay should show: the Swift compile error first
    /// (the sketch isn't even running), otherwise a user-shader compile error.
    public var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return shaderError
    }

    /// Called by the host once the renderer's `SketchRunner` exists (from
    /// `SketchView(onRunner:)`). Wires the user-shader error channel.
    public func attach(_ runner: SketchRunner) {
        self.runner = runner
        runner.onUserShaderError = { [weak self] error in
            self?.shaderError = error?.message
        }
    }

    /// Record a parameter the user changed, so it survives the next evaluation.
    public func recordParam(_ name: String, _ value: ParamStored) {
        paramValues[name] = value
    }

    /// The parameters the user has turned, in declaration order, each carrying what
    /// it holds right now. This is the set an inspector writes back into the
    /// sketch: a parameter nobody touched is left as the file declares it, and the
    /// value written is the one on screen (a parameter turned by hand and then moved
    /// by a fader saves where the fader left it).
    public var tunedParams: [(name: String, stored: ParamStored)] {
        params.filter { paramValues[$0.name] != nil }.map { ($0.name, $0.param.stored) }
    }

    /// Forget tuned values that now stand in the sketch's own text, so the next
    /// reload reads them from the file. Without this the tuned value keeps
    /// winning, and editing that default by hand would look ignored.
    public func forgetTunedParams(_ names: [String]) {
        for name in names { paramValues.removeValue(forKey: name) }
    }

    // MARK: - Cues

    /// Take the cue sheet at `path` as this session's, and keep writing it
    /// there. A path with no file yet is simply where the first save lands; a
    /// file that cannot be read throws, before anything runs.
    public func adoptCueFile(_ path: String) throws {
        cueFile = path
        if FileManager.default.fileExists(atPath: path) {
            let sheet = try CueSheet.load(from: path)
            cueSheet = sheet
            cues = sheet.cues
            if let sketch { sketch.cueSheet = sheet }
        } else if let cueSheet, !cueSheet.cues.isEmpty {
            // Cues saved before the sketch had a file (an untitled buffer)
            // land in the new file now rather than at the next change.
            try cueSheet.write(to: path)
        }
    }

    /// Save the running sketch's parameters as they stand under `name`.
    public func saveCue(_ name: String) {
        sketch?.saveCue(name)
    }

    public func deleteCue(_ name: String) {
        sketch?.deleteCue(name)
    }

    /// Call a cue on the running sketch, over `seconds`.
    public func callCue(_ request: CueRequest, over seconds: Double) {
        sketch?.cue(request, over: seconds)
    }

    /// The cue the running sketch called last.
    public var currentCue: String? { sketch?.currentCue }

    /// The sketch saved or deleted a cue: carry the sheet, show it, file it.
    private func cueSheetDidChange() {
        guard let sketch else { return }
        cueSheet = sketch.cueSheet
        cues = sketch.cueSheet.cues
        if let cueFile {
            do {
                try sketch.cueSheet.write(to: cueFile)
            } catch {
                print("Ollin: could not write the cues to \(cueFile): \(error)")
            }
        }
    }

    /// Record a variation seed the user navigated to, so it survives the next
    /// evaluation the way tuned parameters do.
    public func recordSeed(_ seed: Int) {
        navigatedSeed = seed
    }

    /// Set or clear the shader-error channel from a host's own shader path
    /// (a framework-library reload, a user-shader cache drop).
    public func reportShaderError(_ message: String?) {
        shaderError = message
    }

    /// Compile `input` through `loader` off the main actor, superseding any
    /// in-flight compile, then instantiate and swap on the main actor. The
    /// first success sets `sketch` (the host's view mounts the runner); later
    /// successes swap into the existing runner. `keepClock` overrides the
    /// session default for this one evaluation. `onSuccess` runs after the
    /// swap (so a host can re-assert canvas size, retitle, print); `onFailure`
    /// runs with the running sketch left untouched.
    ///
    /// `keepRun` asks for the run underneath to carry on rather than start
    /// over (`SketchRunner.reload(to:keepClock:keepRun:)`): `setup()` does not
    /// run again, the canvas keeps its pile, and the drawing state, the random
    /// streams and the `@Saved` properties come across. It is the host's call,
    /// not this one's, because only the host has the text the edit was made
    /// against; `SourceRegions.change(from:to:)` is what decides it. It applies
    /// to both swaps of a two-speed evaluation, since they run the same code.
    ///
    /// With `landsPlainBuildFirst` on and a loader that optimizes, the two
    /// compiles start side by side (the optimized one takes a few percent
    /// longer with the plain one beside it than alone, measured). The plain
    /// build is the evaluation the host hears about: it swaps in with the
    /// clock as asked and `onSuccess` runs once, then. The optimized build
    /// replaces it silently when it lands, the clock always carried, the
    /// tuned parameters re-applied as at any swap. A plain build that fails
    /// to compile fails the evaluation at once; the optimized compile of the
    /// same text fails the same way, and its result is refused. An optimized
    /// build that fails on its own (a compiler fault at `-O`, which the plain
    /// compile cannot see) leaves the plain build on stage and says so.
    public func evaluate(_ loader: SketchLoader,
                         input: SketchLoader.Input = .file,
                         keepClock: Bool? = nil,
                         keepRun: Bool = false,
                         onSuccess: (@MainActor (Sketch) -> Void)? = nil,
                         onFailure: (@MainActor (SketchLoader.LoadError) -> Void)? = nil) {
        phase = .compiling
        isOptimizing = false
        let carryClock = keepClock ?? self.keepClock
        let twoSpeed = landsPlainBuildFirst && loader.optimization == .speed
        // Supersede any in-flight compile so a newer evaluation always wins:
        // two evaluations within one swiftc run otherwise race, and a slower
        // older compile could land last and swap in stale code. Cancelling
        // the task refuses both of its builds; the detached compiles run to
        // completion and nobody reads them.
        compileTask?.cancel()
        compileTask = Task {
            let started = Date()
            let optimizedCompile = Task.detached(priority: .userInitiated) {
                loader.compile(input)
            }
            var plainLanded = false
            if twoSpeed {
                var plainLoader = loader
                plainLoader.optimization = .none
                let plain = await Task.detached(priority: .userInitiated) {
                    plainLoader.compile(input)
                }.value
                if Task.isCancelled { return }   // a newer evaluation superseded this one
                switch plain {
                case .success(let dylibPath):
                    switch self.land(dylibPath, with: loader, keepClock: carryClock,
                                     keepRun: keepRun, started: started, counts: true) {
                    case .success(let newSketch):
                        plainLanded = true
                        self.isOptimizing = true
                        self.phase = .idle
                        onSuccess?(newSketch)
                    case .failure(let error):
                        self.fail(error, onFailure)
                        return
                    }
                case .failure(let error):
                    self.fail(error, onFailure)
                    return
                }
            }
            let optimized = await optimizedCompile.value
            if Task.isCancelled { return }
            switch optimized {
            case .success(let dylibPath):
                if plainLanded {
                    // The silent second swap: the clock carries whatever the
                    // first did, and the host is not told again.
                    if case .failure(let error) = self.land(dylibPath, with: loader, keepClock: true,
                                                            keepRun: keepRun, started: started,
                                                            counts: false) {
                        print("Ollin: the optimized build did not load, so the plain build stays: \(error)")
                    }
                    self.isOptimizing = false
                } else {
                    switch self.land(dylibPath, with: loader, keepClock: carryClock,
                                     keepRun: keepRun, started: started, counts: true) {
                    case .success(let newSketch):
                        self.phase = .idle
                        onSuccess?(newSketch)
                    case .failure(let error):
                        self.fail(error, onFailure)
                    }
                }
            case .failure(let error):
                if plainLanded {
                    self.isOptimizing = false
                    print("Ollin: the optimized build failed, so the plain build stays: \(error)")
                } else {
                    self.fail(error, onFailure)
                }
            }
        }
    }

    /// Load a compiled build and put it on stage: swapped into the runner
    /// when one exists, else set as the sketch the host's view mounts. The
    /// tuned parameters are re-applied before it draws. `counts` is whether
    /// this swap is the evaluation's first, the one the reload count and the
    /// build time record; the optimized swap behind a plain build is not.
    /// Hands back the instance on stage, or the error when the dylib does
    /// not load, with nothing changed.
    private func land(_ dylibPath: String, with loader: SketchLoader, keepClock: Bool,
                      keepRun: Bool, started: Date,
                      counts: Bool) -> Result<Sketch, SketchLoader.LoadError> {
        switch loader.instantiate(dylibPath: dylibPath) {
        case .success(let newSketch):
            syncParams(newSketch)   // re-apply tuned parameters before it draws
            if let runner {
                if counts { lastBuildSeconds = Date().timeIntervalSince(started) }
                runner.reload(to: newSketch, keepClock: keepClock, keepRun: keepRun)
                if counts { reloadCount += 1 }
            } else {
                sketch = newSketch   // no runner yet: the view mounts this one
            }
            return .success(newSketch)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Apply previously-tuned values to a freshly loaded sketch's params, and
    /// publish the handles for the host's inspector. Only re-applies values the
    /// user changed; untouched params keep the sketch's (possibly edited)
    /// defaults.
    private func syncParams(_ sketch: Sketch) {
        // Carry a navigated variation across the swap. Before setup(), so a
        // sketch that pins its own seed there still wins, same as anywhere.
        if let navigatedSeed { sketch.seed(navigatedSeed) }
        // Carry the timeline's tracks the same way: installed before setup()
        // runs, so a track the sketch writes there still wins its own parameter.
        if let automation { sketch.automation = automation }
        // The cue sheet the same way, then the hook that files every change.
        if let cueSheet { sketch.cueSheet = cueSheet }
        sketch.cuesChanged = { [weak self] in self?.cueSheetDidChange() }
        cues = sketch.cueSheet.cues
        let handles = sketch.parameters()
        for handle in handles {
            guard let stored = paramValues[handle.name] else { continue }
            // Restore instantly (a smoothed parameter shouldn't glide in from its
            // default on every reload; it's resuming where it was, not
            // retargeting). A payload whose kind no longer matches the param
            // (the property changed type in the edit) is ignored, so the
            // freshly written default wins.
            handle.param.restore(stored)
        }
        params = handles
    }

    private func fail(_ error: SketchLoader.LoadError,
                      _ onFailure: (@MainActor (SketchLoader.LoadError) -> Void)?) {
        phase = .failed("\(error)")
        onFailure?(error)
    }
}
