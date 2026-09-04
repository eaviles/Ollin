import SwiftUI
import Ollin
import OllinRuntime

// OllinLive — the live-reload host.
//
//   swift run OllinLive <path/to/Sketch.swift>
//
// Opens a window for the sketch, watches the file, and hot-swaps the running
// sketch on save without closing the window. A SwiftUI `App` owns the window;
// the sketch renders in the detail pane and a sidebar inspector shows reload
// status (live FPS + parameters land next).
@main
struct OllinLiveApp: App {
    @NSApplicationDelegateAdaptor(LiveAppDelegate.self) private var delegate
    @State private var session: LiveSession

    init() {
        // Stop AppKit from reading the sketch-path argument as a file-open
        // request — that misread is what suppresses the scene's automatic
        // initial window when a bundleless host launches with an argument
        // (the Sequoia regression; a `Window` scene has no New Window menu
        // item, so the old fire-⌘N recovery can't help it). Registered here in
        // `init` so it lands before AppKit parses the arguments at launch.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])

        setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: reload messages show immediately

        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--selftest") { SelfTest.run() }      // headless; exits
        if arguments.contains("--watchtest") { WatchTest.run() }    // headless; exits
        if arguments.contains("--paramtest") { ParamTest.run() }    // headless; exits
        if arguments.contains("--dragtest") { DragTest.run() }      // headless; exits
        if arguments.contains("--savetest") { SaveTest.run() }      // headless; exits

        guard let pathArg = arguments.first(where: { !$0.hasPrefix("-") }) else {
            FileHandle.standardError.write(
                Data("usage: swift run OllinLive <path/to/Sketch.swift>\n".utf8))
            exit(2)
        }
        let sketchPath = (pathArg as NSString).isAbsolutePath
            ? pathArg
            : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(pathArg)
        guard FileManager.default.fileExists(atPath: sketchPath) else {
            FileHandle.standardError.write(Data("OllinLive: file not found — \(sketchPath)\n".utf8))
            exit(2)
        }

        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }

        // The timeline's file: `--automation <file>`, or the sketch's own
        // sibling (`Sketch.automation.json` beside `Sketch.swift`). One that
        // exists installs its tracks on the windowed run and on this host's
        // export path alike; one that does not yet is simply where the
        // panel's edits will land. A file that exists but cannot be read
        // fails here, before anything runs, like a bad take.
        let automationURL = value(after: "--automation").map(URL.init(fileURLWithPath:))
            ?? URL(fileURLWithPath: sketchPath).deletingPathExtension()
                .appendingPathExtension("automation.json")
        var automation: Automation?
        if FileManager.default.fileExists(atPath: automationURL.path) {
            do {
                automation = try Automation.load(from: automationURL)
                let tracks = automation?.tracks.count ?? 0
                print("OllinLive: automation from \(automationURL.lastPathComponent)"
                      + " (\(tracks) track\(tracks == 1 ? "" : "s"))")
            } catch {
                FileHandle.standardError.write(
                    Data("OllinLive: could not read the automation: \(error)\n".utf8))
                exit(1)
            }
        }

        // `swift run OllinLive Sketch.swift --export-gif loop.gif --seconds 4`
        // runs the same headless export surface a standalone `@main` sketch
        // gets, on a loose watched file: the shared handler recognizes the
        // flag and only then pays for the compile. Exits without a window.
        // The sibling automation rides along, so an export renders the piece
        // as the timeline panel played it; the `--automation` flag still wins
        // (the shared handler applies it after this).
        // The sketch compiles optimized unless `--no-optimize` asks for the
        // plain compile (a debugging aid: asserts fire, backtraces keep every
        // frame); see `SketchLoader.Optimization`.
        let optimization: SketchLoader.Optimization =
            arguments.contains("--no-optimize") ? .none : .speed
        let handled = OllinApp.handleCommandLine(arguments, makeSketch: {
            switch SketchLoader(sketchPath: sketchPath, optimization: optimization).load() {
            case .success(let sketch):
                if let automation { sketch.automation = automation }
                return sketch
            case .failure(let error):
                FileHandle.standardError.write(Data("OllinLive: \(error)\n".utf8))
                exit(1)
            }
        })
        if handled { exit(0) }

        // An installation is read by a sketch that opens its own window, and
        // this host opens its own instead. Said out loud rather than dropped
        // (a flag that quietly does nothing reads as a broken feature), and it
        // names the host that does give the sketch a window, so the answer
        // arrives with the problem. `ollin <file> --installation` picks that
        // host on its own.
        if arguments.contains("--installation") {
            let message = "OllinLive: --installation applies to a sketch that opens its own window; "
                + "this host owns the window, so the flag is ignored here. "
                + "Put the piece up with `swift run OllinRun \(pathArg) --installation` "
                + "(or `ollin \(pathArg) --installation`); see Docs/Output/Installation.md\n"
            FileHandle.standardError.write(Data(message.utf8))
        }

        // Keep `init()` fast so the window appears (and activates) immediately;
        // the initial compile runs async inside `LiveSession`. A blocking compile
        // here left the window behind the terminal until a Dock click.
        let keepClock = arguments.contains("--keep-clock")
        let record = arguments.contains("--record")
        // The take flags (`--record-take <file>` writes the run's inputs and
        // parameters down; `--replay <file>` plays a recorded run back). A bad take
        // file fails here, before a window opens.
        let replayTake: Take? = value(after: "--replay").map { path in
            do {
                return try Take.load(from: URL(fileURLWithPath: path))
            } catch {
                FileHandle.standardError.write(Data("OllinLive: could not read the take: \(error)\n".utf8))
                exit(1)
            }
        }
        var takeRecordURL = value(after: "--record-take").map(URL.init(fileURLWithPath:))
        if replayTake != nil, takeRecordURL != nil {
            FileHandle.standardError.write(Data("OllinLive: --record-take is ignored during a replay\n".utf8))
            takeRecordURL = nil
        }
        let session = LiveSession(
            loader: SketchLoader(sketchPath: sketchPath, optimization: optimization),
            sketchPath: sketchPath,
            displayName: pathArg, keepClock: keepClock, recordOnLaunch: record,
            takeRecordOnLaunch: takeRecordURL, replayOnLaunch: replayTake,
            automation: automation, automationURL: automationURL)
        _session = State(initialValue: session)
        ActiveLiveSession.session = session
    }

    var body: some SwiftUI.Scene {
        // A `Window` (not `WindowGroup`): the live host is one window by design.
        // A second window would share the single `LiveSession` — its runner
        // would clobber the first's on attach — and the title-bar accessories
        // assume one window to bind to, so don't offer File ▸ New Window at all.
        Window("OllinLive", id: "main") {
            LiveRootView(session: session)
        }
        // The root is a fixed-size `HStack` (sidebar + sketch), so `.contentSize`
        // sizes the window exactly to it, disables user resize, and shrinks it to
        // just the sketch when the sidebar is collapsed.
        .defaultSize(width: OllinApp.defaultWindowSize.width + LiveRootView.sidebarWidth,
                     height: OllinApp.defaultWindowSize.height)
        .windowResizability(.contentSize)
        // A unified (taller) title bar for the redesign's gradient bar: macOS
        // centers the traffic lights and `.contentSize` accounts for the height, so
        // there's no reserved dead space (hiding the native bar leaves it behind).
        .windowToolbarStyle(.unified(showsTitle: false))
        // The sidebar toggle as a menu command (⌘/, matching the standalone
        // hosts' Show Inspector). No "Show FPS"/detached-panel command here:
        // the sidebar is the live host's stats display.
        .commands {
            LiveSidebarCommands()
            LiveTimelineCommands()
            LiveRecordCommands()
            OllinCameraCommands()
        }
    }
}

/// The one running session, reachable from menu `Commands` structs (which
/// can't be handed instance state). Weak: the `App`'s `@State` owns it.
@MainActor
enum ActiveLiveSession {
    static weak var session: LiveSession?
}

/// Sketch ▸ Record (⌘⇧R): record the live run to a movie, sound included,
/// the same control the performance host has.
private struct LiveRecordCommands: Commands {
    var body: some Commands {
        CommandMenu("Sketch") {
            Button(ActiveLiveSession.session?.core.currentSketch?.isRecording == true
                   ? "Stop Recording" : "Start Recording") {
                ActiveLiveSession.session?.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

/// View ▸ Show Inspector (⌘/) for the live host — bound to the same
/// `@AppStorage` key as the title-bar toggle, so the menu, the button, and the
/// persisted choice are one state.
private struct LiveSidebarCommands: Commands {
    @AppStorage(LiveRootView.sidebarShownKey) private var sidebarShown = true

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Show Inspector", isOn: $sidebarShown)
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}

/// View ▸ Show Timeline (⌘T): the parameter-timeline panel, bound to the same
/// `@AppStorage` key as the title-bar chip, so the menu, the chip, and the
/// persisted choice are one state.
private struct LiveTimelineCommands: Commands {
    @AppStorage(OllinHUD.showTimelineKey) private var showTimeline = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Show Timeline", isOn: $showTimeline)
                .keyboardShortcut("t", modifiers: .command)
        }
    }
}
