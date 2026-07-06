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
///   swap, so a knob never visibly snaps back.
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
    public private(set) var phase: Phase = .idle
    /// Runner-reload count: bumped on every successful swap after the first
    /// mount. `reloadCount == 0` inside `onSuccess` identifies the first mount.
    public private(set) var reloadCount = 0
    /// Wall-clock seconds of the last successful hot reload (compile + load).
    /// `nil` until the first reload (the initial mount doesn't count).
    public private(set) var lastBuildSeconds: Double?
    /// The running sketch's `@Param` knobs, for the host's inspector surface.
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

    /// The in-flight compile, kept so a newer evaluation can cancel it. (The
    /// detached `swiftc` still runs to completion; its result is refused.)
    @ObservationIgnored private var compileTask: Task<Void, Never>?
    /// User-tuned parameter values, keyed by name, re-applied to each freshly
    /// loaded sketch so a knob doesn't snap back. Only values the user actually
    /// changed are stored, so editing a default in code still takes effect.
    @ObservationIgnored private var paramValues: [String: ParamStored] = [:]

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

    /// Record a knob the user changed, so it survives the next evaluation.
    public func recordParam(_ name: String, _ value: ParamStored) {
        paramValues[name] = value
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
                    self.syncParams(newSketch)   // re-apply tuned knobs before it draws
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
        let handles = sketch.parameters()
        for handle in handles {
            guard let stored = paramValues[handle.name] else { continue }
            // Restore instantly (a smoothed knob shouldn't glide in from its
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
