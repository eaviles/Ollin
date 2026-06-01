import Foundation
import Observation
import Ollin
import OllinRuntime

/// Host-owned state for the live session: it owns the watcher, reacts to file
/// changes, and drives hot-swaps.
///
/// The initial content is intentionally lightweight — the detail pane shows a
/// "Compiling…" placeholder, *not* a Metal view, until the first sketch
/// compiles. Mounting an `MTKView` at launch kept the window from coming to the
/// front (a plain SwiftUI launch, like the examples gallery, foregrounds fine).
/// The first compile (kicked off here, off the main actor) sets `sketch`, which
/// mounts the `SketchView`; later edits swap inside the existing runner via
/// `reload`. A compile error is surfaced (in the inspector, and the detail pane
/// before the first success) and the running sketch is left untouched — a typo
/// never closes the window.
@MainActor
@Observable
final class LiveSession {
    /// Reload lifecycle, surfaced in the inspector.
    enum Status: Equatable {
        case compiling
        case watching
        case error(String)

        var label: String {
            switch self {
            case .compiling: return "Compiling…"
            case .watching: return "Watching"
            case .error: return "Compile error"
            }
        }
    }

    /// The path argument as the user typed it — shown in the inspector.
    let displayName: String

    /// The sketch to host. `nil` until the first compile lands; set once (the
    /// detail view then builds the runner with it). Later reloads swap inside the
    /// runner, not through this.
    private(set) var sketch: Sketch?
    private(set) var title = "Ollin Live"
    private(set) var status: Status = .compiling
    private(set) var reloadCount = 0
    /// Live performance numbers of the running sketch, refreshed a few times a
    /// second by the runner. Shared with the on-canvas overlay (one source of
    /// truth), so the inspector and overlay never disagree. The reference is
    /// constant; its `@Observable` fields drive the inspector's updates.
    @ObservationIgnored let stats = FrameStats()
    /// The running sketch's `@Param` knobs, surfaced as sliders in the inspector.
    private(set) var params: [ParamHandle] = []

    /// The last compile error, when `status` is `.error`.
    var errorMessage: String? {
        if case .error(let message) = status { return message }
        return nil
    }

    @ObservationIgnored private let loader: SketchLoader
    @ObservationIgnored private let sketchPath: String
    @ObservationIgnored private let keepClock: Bool
    /// The framework's shader source, watched for live shader reload — set only
    /// when running from the Ollin repo (where `Sources/Ollin/Renderer` exists).
    @ObservationIgnored private let shaderPath: String?
    @ObservationIgnored private var runner: SketchRunner?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var didStart = false
    /// User-tuned parameter values, keyed by name, re-applied to each freshly
    /// reloaded sketch so a knob doesn't snap back. Only values the user actually
    /// changed are stored — so editing a default in code still takes effect.
    @ObservationIgnored private var paramValues: [String: Double] = [:]

    /// Asset extensions whose change re-runs `setup()` (where assets load).
    private static let assetExtensions = ["png", "jpg", "jpeg", "gif", "heic", "bmp", "tiff"]

    init(loader: SketchLoader, sketchPath: String, displayName: String, keepClock: Bool) {
        self.loader = loader
        self.sketchPath = sketchPath
        self.displayName = displayName
        self.keepClock = keepClock

        let shader = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("Sources/Ollin/Renderer/Shaders.metal")
        self.shaderPath = FileManager.default.fileExists(atPath: shader) ? shader : nil
    }

    /// Called once from the root view's `.task`, after the window has appeared —
    /// starting the watcher and kicking off the initial compile here (rather than
    /// in `init`) keeps launch minimal so the window comes to the front cleanly.
    func start() {
        guard !didStart else { return }
        didStart = true
        startWatching()
        print("OllinLive: compiling \(displayName) …")
        compileAndApply()
    }

    /// Called by the detail view once the renderer's `SketchRunner` exists (after
    /// the first successful compile makes `sketch` non-nil and the view mounts).
    func attach(_ runner: SketchRunner) {
        self.runner = runner
        // `stats` is wired into the runner by the `SketchView` (it's passed in as
        // the shared instance), so there's nothing to hook up here.
    }

    private func startWatching() {
        var dirs = [(sketchPath as NSString).deletingLastPathComponent]
        if let shaderPath {                   // also watch the shader's folder
            dirs.append((shaderPath as NSString).deletingLastPathComponent)
        }
        watcher = FileWatcher(paths: dirs) { [weak self] changed in
            // Called on the watcher's background queue; hop to the main actor.
            Task { @MainActor in self?.handle(changed) }
        }
        watcher?.start()
        print("OllinLive: watching \(displayName) — edit and save to hot-reload.")
        if shaderPath != nil { print("OllinLive: also live-reloading Shaders.metal.") }
    }

    /// Dispatch a coalesced batch of changed paths by file type.
    private func handle(_ paths: [String]) {
        if paths.contains(where: { $0.hasSuffix(".swift") }) {
            compileAndApply()
        } else if shaderPath != nil, paths.contains(where: { $0.hasSuffix(".metal") }) {
            reloadShaders()
        } else if paths.contains(where: { Self.assetExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            runner?.rerunSetup()
            print("OllinLive: asset changed — re-running setup() ✓")
        }
    }

    /// Compile (slow `swiftc`) off the main actor; apply on the main actor. The
    /// first success sets `sketch` (mounting the view, which builds the runner);
    /// later successes swap into the existing runner.
    private func compileAndApply() {
        status = .compiling
        let loader = self.loader
        let keepClock = self.keepClock
        Task {
            let compiled = await Task.detached(priority: .userInitiated) {
                loader.compile()
            }.value
            switch compiled {
            case .success(let dylibPath):
                switch loader.instantiate(dylibPath: dylibPath) {
                case .success(let newSketch):
                    self.syncParams(newSketch)   // re-apply tuned knobs before it draws
                    if let runner = self.runner {
                        runner.reload(to: newSketch, keepClock: keepClock)
                        self.reloadCount += 1
                        print("OllinLive: reloaded \(type(of: newSketch)) ✓")
                    } else {
                        self.sketch = newSketch   // first success: the view mounts the runner
                        print("OllinLive: running \(type(of: newSketch)).")
                    }
                    self.title = newSketch.title
                    self.status = .watching
                case .failure(let error):
                    self.fail(error)
                }
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    /// Apply previously-tuned values to a freshly loaded sketch's params, and
    /// publish the handles for the inspector. Only re-applies values the user
    /// changed; untouched params keep the sketch's (possibly edited) defaults.
    private func syncParams(_ sketch: Sketch) {
        let handles = sketch.parameters()
        for handle in handles where paramValues[handle.name] != nil {
            handle.param.wrappedValue = paramValues[handle.name]!
        }
        params = handles
    }

    /// Record a knob the user dragged, so it survives the next reload.
    func recordParam(_ name: String, _ value: Double) {
        paramValues[name] = value
    }

    private func fail(_ error: SketchLoader.LoadError) {
        status = .error("\(error)")
        FileHandle.standardError.write(
            Data("OllinLive: reload skipped (kept running) — \(error)\n".utf8))
    }

    private func reloadShaders() {
        guard let shaderPath,
              let source = try? String(contentsOfFile: shaderPath, encoding: .utf8) else { return }
        do {
            try runner?.reloadShaderLibrary(source: source)
            print("OllinLive: reloaded Shaders.metal ✓")
        } catch {
            FileHandle.standardError.write(
                Data("OllinLive: shader reload skipped (kept running) — \(error)\n".utf8))
        }
    }
}
