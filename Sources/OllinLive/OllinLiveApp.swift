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
// status (live FPS + parameter knobs land next).
@main
struct OllinLiveApp: App {
    @NSApplicationDelegateAdaptor(LiveAppDelegate.self) private var delegate
    @State private var session: LiveSession

    init() {
        setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: reload messages show immediately

        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--selftest") { SelfTest.run() }      // headless; exits
        if arguments.contains("--watchtest") { WatchTest.run() }    // headless; exits
        if arguments.contains("--paramtest") { ParamTest.run() }    // headless; exits

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

        // Keep `init()` fast so the window appears (and activates) immediately;
        // the initial compile runs async inside `LiveSession`. A blocking compile
        // here left the window behind the terminal until a Dock click.
        let keepClock = arguments.contains("--keep-clock")
        _session = State(initialValue: LiveSession(
            loader: SketchLoader(sketchPath: sketchPath), sketchPath: sketchPath,
            displayName: pathArg, keepClock: keepClock))
    }

    var body: some Scene {
        WindowGroup {
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
        // No "Show FPS" command here: the inspector panel is the live host's
        // stats display, so the floating overlay would only duplicate it.
    }
}
