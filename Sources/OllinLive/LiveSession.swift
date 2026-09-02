import Foundation
import Observation
import Ollin
import OllinRuntime

/// Host-owned state for the live session: it owns the watcher, reacts to file
/// changes, and drives hot-swaps through the shared `SketchSession` engine
/// (which carries the compile scheduling, param persistence, and error-channel
/// invariants for every live host).
///
/// The initial content is intentionally lightweight: the detail pane shows a
/// "Compiling…" placeholder, *not* a Metal view, until the first sketch
/// compiles. Mounting an `MTKView` at launch kept the window from coming to the
/// front (a plain SwiftUI launch, like the examples gallery, foregrounds fine).
/// The first compile (kicked off here, off the main actor) sets `sketch`, which
/// mounts the `SketchView`; later edits swap inside the existing runner via
/// `reload`. A compile error is surfaced (in the inspector, and the detail pane
/// before the first success) and the running sketch is left untouched; a typo
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

    /// The path argument as the user typed it, shown in the inspector.
    let displayName: String

    /// The shared hot-swap engine: compile scheduling, param carry across
    /// reloads, and the two error channels. This session adds the file-watch
    /// trigger and the OllinLive presentation on top.
    @ObservationIgnored let core: SketchSession

    /// The parameter timeline behind the Timeline panel and the knob rows'
    /// diamonds. Its edits land on the running sketch and are held by the
    /// engine, so the tracks survive every reload swap.
    @ObservationIgnored let timeline = TimelineModel()

    private(set) var title = "OllinLive"

    /// The sketch to host, from the engine. `nil` until the first compile
    /// lands; later reloads swap inside the runner, not through this.
    var sketch: Sketch? { core.sketch }
    var status: Status {
        switch core.phase {
        case .compiling: return .compiling
        case .idle: return .watching
        case .failed(let message): return .error(message)
        }
    }
    var reloadCount: Int { core.reloadCount }
    /// Wall-clock seconds of the last successful hot reload (compile + load),
    /// shown in the "Reloaded" toast. `nil` until the first reload.
    var lastBuildSeconds: Double? { core.lastBuildSeconds }
    /// Live performance numbers of the running sketch, refreshed a few times a
    /// second by the runner. Shared with the on-canvas overlay (one source of
    /// truth), so the inspector and overlay never disagree.
    var stats: FrameStats { core.stats }
    /// The running sketch's `@Param` knobs, surfaced as sliders in the inspector.
    var params: [ParamHandle] { core.params }
    /// A user shader's compile error (`nil` when every shader compiles).
    /// Distinct from `status`, which tracks the Swift hot-reload, so a shader
    /// error and a sketch-compile error don't clear each other.
    var shaderError: String? { core.shaderError }

    /// The error shown in the overlay: the Swift compile error first (the sketch
    /// isn't even running), otherwise a user-shader compile error.
    var errorMessage: String? { core.errorMessage }

    /// The watcher state mapped onto the shared inspector chip. A user-shader error
    /// turns the chip red too, even while the Swift side is happily watching.
    var inspectorStatus: InspectorStatus {
        switch status {
        case .compiling: return .compiling
        case .watching: return shaderError == nil ? .watching : .error
        case .error: return .error
        }
    }

    /// The source file's name (`Sketch.swift`) for the monitor card header.
    var fileName: String { (sketchPath as NSString).lastPathComponent }

    /// The watched file itself, which is also the file a dragged shape is
    /// written back into (see `ShapeDragController`).
    var sourcePath: String { sketchPath }

    /// The sketch running right now. Unlike `sketch`, which mounts the view,
    /// this follows every hot swap, so a host surface that acts on the live
    /// instance reads it fresh each time.
    var currentSketch: Sketch? { core.currentSketch }

    /// The source file's folder, home-abbreviated (`~/Live/Parameters`).
    var folder: String {
        ((sketchPath as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
    }

    @ObservationIgnored private let loader: SketchLoader
    @ObservationIgnored private let sketchPath: String
    /// The framework's shader source directory, watched for live shader reload,
    /// set only when running from the Ollin repo (where `Sources/Ollin/Renderer`
    /// exists). Its `Shader*.metal` segments are concatenated on each reload.
    @ObservationIgnored private let shaderDir: String?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var didStart = false
    /// Whether this session has already said that a declared installation does
    /// not apply here; it is said once, on the first compile that carries one.
    @ObservationIgnored private var saidInstallationIsIgnored = false

    /// Asset extensions whose change re-runs `setup()` (where assets load).
    private static let assetExtensions = ["png", "jpg", "jpeg", "gif", "heic", "bmp", "tiff"]

    /// Whether `--record` asked for the run to be recorded from the first
    /// frame; consumed when the runner attaches.
    @ObservationIgnored private var recordOnLaunch: Bool

    /// Where `--record-take` asked the run's input-and-knob take to be
    /// written, and the take `--replay` asked to play back. Both consumed when
    /// the runner attaches; a later reload ends either (an edited sketch is a
    /// different run, so the take is written out and the replay stops).
    @ObservationIgnored private var takeRecordOnLaunch: URL?
    @ObservationIgnored private var replayOnLaunch: Take?

    init(loader: SketchLoader, sketchPath: String, displayName: String, keepClock: Bool,
         recordOnLaunch: Bool = false, takeRecordOnLaunch: URL? = nil,
         replayOnLaunch: Take? = nil,
         automation: Automation? = nil, automationURL: URL? = nil) {
        self.loader = loader
        self.sketchPath = sketchPath
        self.displayName = displayName
        self.recordOnLaunch = recordOnLaunch
        self.takeRecordOnLaunch = takeRecordOnLaunch
        self.replayOnLaunch = replayOnLaunch
        self.core = SketchSession(keepClock: keepClock)

        let dir = (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent("Sources/Ollin/Renderer")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
        self.shaderDir = exists ? dir : nil

        // The launch automation (the flag's file, or the sketch's own sibling
        // `.automation.json`) rides the engine so every swap re-installs it;
        // the panel's edits replace it through the same seam and write back
        // to the same file.
        core.automation = automation
        timeline.setFile(automationURL)
        timeline.automationChanged = { [weak self] automation in
            self?.core.automation = automation
        }
    }

    /// Called once from the root view's `.task`, after the window has appeared;
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
    /// `stats` is wired into the runner by the `SketchView` (it's passed in as
    /// the shared instance); the engine wires the user-shader error channel.
    func attach(_ runner: SketchRunner) {
        core.attach(runner)
        timeline.runner = runner
        // `--record` starts the take the moment the run is on screen. The
        // recording then rides the runner across reloads, so saves mid-take
        // keep filming; closing the window finishes the file.
        if recordOnLaunch {
            recordOnLaunch = false
            core.currentSketch?.startRecording()
        }
        // The take flags apply once the first compile is on screen: replay
        // hands the run to the recording, and a take recording restarts the
        // run so its frame 0 is the take's frame 0.
        if let take = replayOnLaunch {
            replayOnLaunch = nil
            print("OllinLive: replaying \(take.frameCount) frames (space pauses, arrows step, Home/End jump)")
            runner.replay(take)
        } else if let url = takeRecordOnLaunch {
            takeRecordOnLaunch = nil
            runner.beginTake(writingTo: url)
        }
    }

    /// Start or stop recording the run (the Sketch ▸ Record menu, ⌘⇧R).
    func toggleRecording() {
        guard let sketch = core.currentSketch else { return }
        if sketch.isRecording {
            sketch.stopRecording()
        } else {
            sketch.startRecording()
        }
    }

    /// Record a knob the user changed, so it survives the next reload.
    func recordParam(_ name: String, _ value: ParamStored) {
        core.recordParam(name, value)
    }

    /// Record a variation seed the user navigated to, so it survives the next
    /// reload the way tuned knobs do.
    func recordSeed(_ seed: Int) {
        core.recordSeed(seed)
    }

    /// The inspector's save action: put the knobs the user turned into the
    /// watched file. Built fresh on each read so the button always names the
    /// file this session watches.
    var saveAction: ParamSaveAction {
        ParamSaveAction(title: "Save parameters to \(fileName)") { [weak self] in
            self?.saveParams()
        }
    }

    /// Write the tuned knob values into the `@Param` lines they came from, and
    /// say in one line what happened. Nothing here reaches into the running
    /// sketch: the file is the only thing that changes, the watcher sees the
    /// save, and the reload brings the values back from the text. That is why
    /// the picture does not move when a save lands.
    private func saveParams() -> String {
        let values = core.tunedParams
        guard !values.isEmpty else {
            return "No parameter has changed yet, so \(fileName) already says what the sketch draws."
        }
        guard let text = try? String(contentsOfFile: sketchPath, encoding: .utf8) else {
            return "Could not read \(fileName)."
        }
        let result = ParamWrite.writing(text, values: values)
        if result.text != text {
            do {
                try result.text.write(toFile: sketchPath, atomically: true, encoding: .utf8)
            } catch {
                return "Could not write \(fileName): \(error.localizedDescription)"
            }
        }
        // The values stand in the file now, so the tuned set steps aside. Kept,
        // it would keep winning, and a later hand edit of one of those defaults
        // would look ignored.
        core.forgetTunedParams(result.written)
        let summary = ParamWrite.summary(of: result, in: fileName)
        print("OllinLive: \(summary)")
        return summary
    }

    private func startWatching() {
        var dirs = [(sketchPath as NSString).deletingLastPathComponent]
        if let shaderDir {                    // also watch the shader folder
            dirs.append(shaderDir)
        }
        watcher = FileWatcher(paths: dirs) { [weak self] changed in
            // Called on the watcher's background queue; hop to the main actor.
            Task { @MainActor in self?.handle(changed) }
        }
        watcher?.start()
        print("OllinLive: watching \(displayName); edit and save to hot-reload.")
        if shaderDir != nil { print("OllinLive: also live-reloading the framework shaders.") }
    }

    /// Dispatch a coalesced batch of changed paths by file type.
    private func handle(_ paths: [String]) {
        if paths.contains(where: { $0.hasSuffix(".swift") }) {
            compileAndApply()
            return
        }
        let metal = paths.filter { $0.hasSuffix(".metal") }
        if !metal.isEmpty {
            // A framework segment (under the repo's shader dir) reloads the built-in
            // library; a `.metal` beside the sketch is a user shader, recompiled by
            // dropping its cache so the renderer re-reads the file.
            if let shaderDir, metal.contains(where: { $0.hasPrefix(shaderDir) }) {
                reloadShaders()
            }
            if metal.contains(where: { path in
                guard let shaderDir else { return true }   // no framework dir: it's a user shader
                return !path.hasPrefix(shaderDir)
            }) {
                reloadUserShaders()
            }
            return
        }
        if paths.contains(where: { Self.assetExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            core.runner?.rerunSetup()
            print("OllinLive: asset changed, re-running setup() ✓")
        }
    }

    /// A user's own `.metal` shader file changed: drop the compiled-shader cache so the
    /// renderer re-reads and recompiles it on the next frame, and clear any stale error.
    private func reloadUserShaders() {
        core.runner?.invalidateUserShaders()
        core.reportShaderError(nil)
        print("OllinLive: reloaded user shader ✓")
    }

    /// Evaluate the watched file through the shared engine; the OllinLive
    /// presentation (prints, the window title) rides the callbacks.
    private func compileAndApply() {
        core.evaluate(loader) { [weak self] newSketch in
            guard let self else { return }
            if self.core.reloadCount > 0 {
                print("OllinLive: reloaded \(type(of: newSketch)) ✓")
            } else {
                print("OllinLive: running \(type(of: newSketch)).")
            }
            self.noteDeclaredInstallation(newSketch)
            // The live host names its window "OllinLive - <Sketch>" (the
            // sketch's own `title` is "Ollin - <Sketch>", which the
            // standalone/gallery windows keep).
            let sketchTitle = newSketch.title
            self.title = sketchTitle.hasPrefix("Ollin")
                ? "OllinLive" + sketchTitle.dropFirst("Ollin".count)
                : sketchTitle
        } onFailure: { error in
            FileHandle.standardError.write(
                Data("OllinLive: reload skipped (kept running): \(error)\n".utf8))
        }
    }

    /// Say, once a session, that a sketch which declares an installation is not
    /// getting one here. The declaration is read where the sketch owns its
    /// window, and this host owns it instead, so the piece runs in an ordinary
    /// live window and the reason is invisible. Said on the first successful
    /// compile rather than on every save, because a reload a second is not a
    /// place to put an explanation.
    private func noteDeclaredInstallation(_ sketch: Sketch) {
        guard !saidInstallationIsIgnored, sketch.installation.runsUnattended else { return }
        saidInstallationIsIgnored = true
        FileHandle.standardError.write(Data("""
            OllinLive: this sketch declares an installation, which is read where the sketch owns \
            its own window; this host owns the window, so the piece runs here as an ordinary live \
            sketch. Put it up with `ollin \(displayName) --installation` (see \
            Docs/Output/Installation.md).

            """.utf8))
    }

    private func reloadShaders() {
        guard let shaderDir else { return }
        do {
            try core.runner?.reloadShaderLibrary(fromDirectory: shaderDir)
            core.reportShaderError(nil)
            print("OllinLive: reloaded framework shaders ✓")
        } catch {
            // Surface the Metal compiler's diagnostics in the same overlay user
            // shaders use, instead of only the terminal.
            core.reportShaderError("\(error)")
            FileHandle.standardError.write(
                Data("OllinLive: shader reload skipped (kept running)\n\(error)\n".utf8))
        }
    }
}
