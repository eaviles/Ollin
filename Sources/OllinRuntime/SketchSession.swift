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
@MainActor
@Observable
public final class SketchSession {
    /// The evaluation lifecycle. `.idle` means nothing is in flight (a sketch
    /// may well be running); `.failed` carries the raw compiler log.
    public enum Phase: Equatable, Sendable {
        case idle
        case compiling
        case failed(String)
    }

    /// The sketch to host. `nil` until the first compile lands; set once (the
    /// host's view then builds the runner with it). Later evaluations swap
    /// inside the runner, not through this.
    public private(set) var sketch: Sketch?
    /// The instance actually drawing right now: the runner's, once one exists,
    /// because later evaluations swap inside the runner while `sketch` stays
    /// the first mount. Anything addressed to "the sketch on stage" (the live
    /// recorder, a host control) goes through this.
    public var currentSketch: Sketch? { runner?.sketch ?? sketch }
    public private(set) var phase: Phase = .idle
    /// Runner-reload count: bumped on every successful swap after the first
    /// mount. `reloadCount == 0` inside `onSuccess` identifies the first mount.
    public private(set) var reloadCount = 0
    /// Wall-clock seconds of the last successful hot reload (compile + load).
    /// `nil` until the first reload (the initial mount doesn't count).
    public private(set) var lastBuildSeconds: Double?
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

    public init(keepClock: Bool = false) {
        self.keepClock = keepClock
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
    public func evaluate(_ loader: SketchLoader,
                         input: SketchLoader.Input = .file,
                         keepClock: Bool? = nil,
                         onSuccess: (@MainActor (Sketch) -> Void)? = nil,
                         onFailure: (@MainActor (SketchLoader.LoadError) -> Void)? = nil) {
        phase = .compiling
        let carryClock = keepClock ?? self.keepClock
        // Supersede any in-flight compile so a newer evaluation always wins:
        // two evaluations within one swiftc run otherwise race, and a slower
        // older compile could land last and swap in stale code.
        compileTask?.cancel()
        compileTask = Task {
            let started = Date()
            let compiled = await Task.detached(priority: .userInitiated) {
                loader.compile(input)
            }.value
            if Task.isCancelled { return }   // a newer evaluation superseded this one
            switch compiled {
            case .success(let dylibPath):
                switch loader.instantiate(dylibPath: dylibPath) {
                case .success(let newSketch):
                    self.syncParams(newSketch)   // re-apply tuned parameters before it draws
                    if let runner = self.runner {
                        self.lastBuildSeconds = Date().timeIntervalSince(started)
                        runner.reload(to: newSketch, keepClock: carryClock)
                        self.reloadCount += 1
                    } else {
                        self.sketch = newSketch   // first success: the view mounts the runner
                    }
                    self.phase = .idle
                    onSuccess?(newSketch)
                case .failure(let error):
                    self.fail(error, onFailure)
                }
            case .failure(let error):
                self.fail(error, onFailure)
            }
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
