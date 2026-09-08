import AppKit
import Observation
import UniformTypeIdentifiers
import Ollin
import OllinRuntime

/// The performance host's state: the shared `SketchSession` hot-swap engine
/// plus the document side (the file, the buffer's dirty state, autosave and
/// crash recovery) and the evaluate loop. Evaluation compiles the *editor
/// buffer* (never an implicit save; the `.swift` file on disk stays the
/// artifact, written only by ⌘S), with `keepClock` on by default so motion
/// phase carries across a swap mid-set.
@MainActor
@Observable
final class PerformanceSession {
    /// The shared hot-swap engine (compile scheduling, param carry across
    /// swaps, the two error channels).
    @ObservationIgnored let core = SketchSession(keepClock: true)
    @ObservationIgnored let editor = EditorController()
    /// The host's own performance surface on MIDI and OSC: evaluate, hide the
    /// code, the backdrop and size, record. A host preference, never the
    /// sketch's; see `PerformanceControls`.
    @ObservationIgnored private(set) lazy var controls = PerformanceControls(handlers: controlHandlers)

    /// The open document; `nil` is an untitled buffer.
    private(set) var fileURL: URL?
    private(set) var isDirty = false
    /// Structured compiler errors for the strip + editor line tints, from the
    /// last failed evaluation. Empty while the buffer last compiled clean.
    private(set) var diagnostics: [CompileDiagnostic] = []
    /// Bumped per successful evaluation; drives the editor flash + toast.
    private(set) var evaluateCount = 0
    /// Stage geometry, updated per successful evaluation: the canvas aspect the
    /// letterbox preserves, or fill-the-window for `.resizable` sketches.
    private(set) var stageAspect: Double = 1
    private(set) var stageFillsWindow = false
    /// The canvas the stage shows, in the sketch's own points, which is what
    /// a shape's outline over the stage is measured in.
    private(set) var stageCanvas = CGSize(width: 1080, height: 1080)
    private(set) var title = "OllinLiveCoding"
    /// Recovered buffer text offered after a crash (`nil` when none pending).
    private(set) var recoveryAvailable: String?
    /// Whether the stage is being recorded; the chip and the menu read this.
    private(set) var isRecording = false
    /// The just-finished recording's file name, briefly shown as a toast.
    private(set) var recordingSaved: String?

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var autosaveTimer: Timer?
    /// The text the sketch on stage was built from. A shape's site names a
    /// line of that text, so it is the only text a drag may edit.
    @ObservationIgnored private var sourceOnStage: String?
    /// Where the crash net lives; the real support folder unless a headless
    /// test hands over a scratch one.
    @ObservationIgnored private let supportDirectory: URL

    var displayName: String { fileURL?.lastPathComponent ?? "Untitled" }

    /// The folder line for the monitor card: the document's home, or a hint
    /// that the buffer hasn't been saved yet.
    var folderDisplay: String {
        guard let fileURL else { return "unsaved buffer" }
        return (fileURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    /// The engine state mapped onto the shared status chip.
    var chipStatus: InspectorStatus {
        switch core.phase {
        case .compiling: return .compiling
        case .idle: return core.shaderError == nil ? .watching : .error
        case .failed: return .error
        }
    }

    /// The path the loader compiles *as*: the document's, or a stand-in under
    /// the support folder for an untitled buffer (the loader needs a path for
    /// the class regex, the asset `Bundle`, and the diagnostic file name).
    private var effectivePath: String {
        fileURL?.path ?? supportDirectory.appendingPathComponent("Untitled.swift").path
    }

    /// How the buffer compiles; see `SketchLoader.Optimization`.
    @ObservationIgnored private let optimization: SketchLoader.Optimization

    init(fileURL: URL?, optimization: SketchLoader.Optimization = .speed,
         supportDirectory: URL = PerformanceSession.defaultSupportDirectory) {
        self.fileURL = fileURL
        self.optimization = optimization
        self.supportDirectory = supportDirectory
    }

    /// Called once from the root view's `.task`: load the document (or the
    /// starter template), offer crash recovery if a newer autosave exists, and
    /// evaluate so the window opens with motion.
    func start() {
        guard !didStart else { return }
        didStart = true

        var text = SketchTemplate.source
        if let fileURL, let fromDisk = try? String(contentsOf: fileURL, encoding: .utf8) {
            text = fromDisk
        }
        editor.setText(text)
        editor.onTextChange = { [weak self] in self?.markDirty() }
        refreshTitle()

        // Offer recovery only for *this* document: an untitled buffer's crash
        // net must not overwrite a file the next launch opened (a real early
        // miss: restoring replaced an opened sketch with old untitled work).
        if let recovered = try? String(contentsOf: recoveryFile, encoding: .utf8),
           recovered != text,
           recoveryOrigin() == fileURL?.path {
            recoveryAvailable = recovered
        }

        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isDirty else { return }
                self.autosave()
            }
        }

        evaluate()
        controls.start()
    }

    /// What a control does when it reaches the host. The view settings live
    /// in the defaults the views already read, so a fader moving the backdrop
    /// moves the menu's picker with it.
    private var controlHandlers: PerformanceControls.Handlers {
        let defaults = UserDefaults.standard
        return PerformanceControls.Handlers(
            evaluate: { [weak self] fresh in self?.evaluate(fresh: fresh) },
            setCodeHidden: { wanted in
                let key = LiveCodingRootView.codeHiddenKey
                defaults.set(wanted ?? !defaults.bool(forKey: key), forKey: key)
            },
            setBackdrop: { defaults.set($0, forKey: LiveCodingRootView.backdropKey) },
            setCodeSize: { defaults.set($0.rounded(), forKey: LiveCodingRootView.fontSizeKey) },
            setRecording: { [weak self] wanted in
                guard let self else { return }
                if let wanted, wanted == self.isRecording { return }
                self.toggleRecording()
            },
            cue: { [weak self] request in
                self?.core.callCue(request, over: CuesCardView.fade())
            },
            cueOver: { [weak self] request, fade in
                self?.core.callCue(request, over: fade)
            }
        )
    }

    // MARK: - Evaluate

    /// Compile the buffer and hot-swap. `fresh` restarts the clock (⌘⇧↩);
    /// the default carries `time`/`frameCount` so motion doesn't jump.
    func evaluate(fresh: Bool = false) {
        let text = editor.text()
        autosave(text)
        let loader = SketchLoader(sketchPath: effectivePath, optimization: optimization)
        core.evaluate(loader, input: .source(text), keepClock: fresh ? false : nil) { [weak self] sketch in
            guard let self else { return }
            self.sourceOnStage = text
            self.diagnostics = []
            self.editor.setDiagnostics([])
            self.evaluateCount += 1
            self.editor.flashEvaluate()
            // A `.metal` beside the sketch may have changed since the last
            // evaluation; there is no file watcher here, so refresh on ⌘↩.
            self.core.runner?.invalidateUserShaders()
            self.updateStage(for: sketch)
        } onFailure: { [weak self] error in
            guard let self else { return }
            if case .compileFailed(let log) = error {
                let file = (self.effectivePath as NSString).lastPathComponent
                self.diagnostics = CompileDiagnostic.parse(log).filter { $0.fileName == file }
            } else {
                self.diagnostics = []
            }
            self.editor.setDiagnostics(self.diagnostics.filter { $0.severity == .error })
        }
    }

    // MARK: - Recording

    /// Start or stop recording the performance (⌘⇧R). The recording rides the
    /// runner across evaluations, so a swap mid-take never cuts the film; the
    /// file lands in `~/Movies/Ollin/` and its name is shown when it is done.
    func toggleRecording() {
        guard let sketch = core.currentSketch else { return }
        if sketch.isRecording {
            sketch.stopRecording { [weak self] url in
                guard let self, let url else { return }
                self.recordingSaved = url.lastPathComponent
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    self.recordingSaved = nil
                }
            }
            isRecording = false
        } else {
            sketch.startRecording()
            isRecording = sketch.isRecording
        }
    }

    private func updateStage(for sketch: Sketch) {
        stageCanvas = sketch.canvasSize.cgSize
        if case .resizable = sketch.windowMode {
            stageFillsWindow = true
            stageAspect = 1
        } else {
            stageFillsWindow = false
            let size = sketch.canvasSize
            stageAspect = size.height > 0 ? Double(size.width) / Double(size.height) : 1
        }
    }

    // MARK: - Document

    func newBuffer() {
        confirmDiscardIfNeeded {
            self.fileURL = nil
            self.editor.setText(SketchTemplate.source)
            self.clearDirty()
            self.refreshTitle()
            self.evaluate(fresh: true)
        }
    }

    func openDocument() {
        confirmDiscardIfNeeded {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.swiftSource]
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            self.open(url)
        }
    }

    func open(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            presentError("Couldn't read \(url.lastPathComponent).")
            return
        }
        fileURL = url
        adoptCueFile(beside: url)
        editor.setText(text)
        clearDirty()
        refreshTitle()
        evaluate(fresh: true)
    }

    /// The cues live in `Sketch.cues.json` beside the open document, so a set
    /// rehearsed in the live host is on the stage too. An untitled buffer
    /// keeps its cues for the session only, until it is saved somewhere.
    private func adoptCueFile(beside url: URL) {
        let path = url.deletingPathExtension().appendingPathExtension("cues.json").path
        do {
            try core.adoptCueFile(path)
        } catch {
            presentError("Couldn't read the cues beside \(url.lastPathComponent): \(error)")
        }
    }

    func saveDocument() {
        guard let fileURL else {
            saveDocumentAs()
            return
        }
        write(to: fileURL)
    }

    // MARK: - Parameters back into the code

    /// The inspector's save action. Here it writes the *buffer*, not the file:
    /// the buffer is what the audience is reading and what ⌘↩ evaluates, and ⌘S
    /// stays the only thing that touches the disk.
    var saveAction: ParamSaveAction {
        ParamSaveAction(title: "Save parameters to the code") { [weak self] in
            self?.saveParamsIntoBuffer()
        }
    }

    /// Put the parameters the performer turned into the `@Param` lines on screen, so
    /// the code the audience reads is the code that draws what they see. The
    /// running sketch is left alone: the values are already in it, and rewriting
    /// the text is not an evaluation.
    private func saveParamsIntoBuffer() -> String {
        let values = core.tunedParams
        guard !values.isEmpty else {
            return "No parameter has changed yet, so the code already says what the sketch draws."
        }
        let text = editor.text()
        let result = ParamWrite.writing(text, values: values)
        if result.text != text {
            editor.replaceBuffer(with: result.text)
        }
        // The code carries them now, so the tuned set steps aside and the next
        // evaluation reads them from the buffer.
        core.forgetTunedParams(result.written)
        var summary = ParamWrite.summary(of: result, in: "the code")
        if !result.written.isEmpty, fileURL != nil {
            summary += " Press Command-S to keep them."
        }
        return summary
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.swiftSource]
        panel.nameFieldStringValue = displayName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        write(to: url)
        refreshTitle()
    }

    private func write(to url: URL) {
        if fileURL == nil || core.cueFile == nil { adoptCueFile(beside: url) }
        do {
            try editor.text().write(to: url, atomically: true, encoding: .utf8)
            clearDirty()
            clearRecovery()
        } catch {
            presentError("Couldn't save: \(error.localizedDescription)")
        }
    }

    /// Ask before discarding unsaved changes (new/open over a dirty buffer).
    private func confirmDiscardIfNeeded(_ proceed: @escaping @MainActor () -> Void) {
        guard isDirty else {
            proceed()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "\(displayName) has changes that haven't been saved."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { proceed() }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    private func markDirty() {
        isDirty = true
        window?.isDocumentEdited = true
    }

    private func clearDirty() {
        isDirty = false
        window?.isDocumentEdited = false
    }

    private func refreshTitle() {
        title = "OllinLiveCoding - \(displayName)"
        window?.representedURL = fileURL
    }

    // MARK: - Autosave & recovery

    /// The crash net: the live buffer, written on every evaluation and every
    /// 15 s while dirty, removed by a clean save. Restore is offered on the
    /// next launch when its content differs from what the launch loaded.
    private func autosave(_ text: String? = nil) {
        let content = text ?? editor.text()
        try? FileManager.default.createDirectory(
            at: supportDirectory, withIntermediateDirectories: true)
        try? content.write(to: recoveryFile, atomically: true, encoding: .utf8)
        // Which document the net belongs to ("" = untitled), so the next
        // launch offers it only to the same one.
        try? (fileURL?.path ?? "").write(to: recoveryOriginFile, atomically: true, encoding: .utf8)
    }

    /// The document the recovery buffer belonged to (`nil` path spelled "").
    private func recoveryOrigin() -> String? {
        guard let origin = try? String(contentsOf: recoveryOriginFile, encoding: .utf8) else {
            return nil
        }
        return origin.isEmpty ? nil : origin
    }

    func restoreRecovery() {
        guard let recovered = recoveryAvailable else { return }
        editor.setText(recovered)
        markDirty()
        recoveryAvailable = nil
        evaluate()
    }

    func discardRecovery() {
        recoveryAvailable = nil
        clearRecovery()
    }

    private func clearRecovery() {
        try? FileManager.default.removeItem(at: recoveryFile)
        try? FileManager.default.removeItem(at: recoveryOriginFile)
    }

    static var defaultSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OllinLiveCoding")
    }

    private var recoveryFile: URL {
        supportDirectory.appendingPathComponent("recovery.swift")
    }

    private var recoveryOriginFile: URL {
        supportDirectory.appendingPathComponent("recovery-origin.txt")
    }
}

// MARK: - Dragging a shape on the stage

/// The buffer is the source: a Command-drag on the stage rewrites the code
/// the room is reading and evaluates it, the way ⌘↩ would. ⌘S is still the
/// only thing that writes the file, and the editor's own undo takes a drag
/// back.
extension PerformanceSession: ShapeDragHost {
    var currentSketch: Sketch? { core.currentSketch }

    var sourceName: String { (effectivePath as NSString).lastPathComponent }

    /// The buffer, when it is the text the stage was built from. A shape's
    /// site names a line of that text, so an edit is only honest against it:
    /// typing above the line would have moved the site, and a drag while the
    /// last one is still compiling would add to numbers the stage has not
    /// shown yet.
    func readSource() throws -> String {
        let text = editor.text()
        guard text == sourceOnStage else {
            if core.phase == .compiling {
                throw ShapeDragRefusal(
                    "The stage is still being built from the last change. Drag again when it lands.")
            }
            throw ShapeDragRefusal(
                "The code has changed since the stage was built from it. "
                + "Evaluate it (Command-Return), then drag.")
        }
        return text
    }

    /// The edit goes into the buffer as an ordinary edit, so it marks the
    /// document and one undo step takes it back, and then the buffer is
    /// evaluated, which is what puts the shape where the drag left it.
    func writeSource(_ text: String) throws {
        editor.replaceBuffer(with: text)
        evaluate()
    }

    func recordParam(_ name: String, _ value: ParamStored) {
        core.recordParam(name, value)
    }
}
