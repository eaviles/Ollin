import SwiftUI
import Ollin

// OllinExamples — the examples gallery.
//
//   swift run OllinExamples
//
// Lists every Examples/ sketch in a sidebar; click one and it compiles and runs
// in the detail pane. Run from the repo root (it scans the Examples/ source tree
// and compiles via the toolchain, like OllinLive).
//
// A SwiftUI `App`/`WindowGroup` owns the window and menu; an
// `NSApplicationDelegateAdaptor` nudges activation so the window reliably comes
// forward when launched from a bundleless `swift run` executable.
@main
struct OllinExamplesApp: App {
    @NSApplicationDelegateAdaptor(ExamplesAppDelegate.self) private var delegate
    private let examples: [Example]

    init() {
        // Stop AppKit from reading any stray command-line argument as a
        // file-open request, which suppresses the scene's automatic initial
        // window on a bundleless launch (the same misread the live host hits
        // with its sketch-path argument; see `OllinLiveApp.init`). The gallery
        // takes no positional argument today — this keeps it robust if one
        // ever appears.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])

        // Surface in-process sketch faults (a native signal or an uncaught ObjC
        // exception) with the example named and a backtrace, instead of the window
        // just vanishing. Installed first, before anything can fault.
        CrashReporter.install()
        let examples = ExampleCatalog.discover()
        // `--list` prints the catalog and exits (no window) — a quick check.
        if CommandLine.arguments.dropFirst().contains("--list") {
            ExampleCatalog.printCatalog(examples)
            exit(0)
        }
        self.examples = examples
    }

    var body: some Scene {
        // A `Window` (not `WindowGroup`): the gallery is one window by design.
        // The title-bar accessories assume one window to bind to, and a second
        // gallery compiling the same sketches buys nothing.
        Window("Ollin Examples", id: "main") {
            GalleryView(examples: examples)
        }
        // Example list + a fixed square stage + inspector; the window hugs that
        // content (no free resize), and collapsing either sidebar narrows it.
        .defaultSize(width: OllinApp.defaultWindowSize.width
                        + GalleryView.examplesSidebarWidth + OllinInspector.sidebarWidth,
                     height: OllinApp.defaultWindowSize.height)
        .windowResizability(.contentSize)
        // The tall gradient title bar (see `GalleryView.toolbar`): a unified
        // toolbar so macOS centers the traffic lights and `.contentSize`
        // accounts for the height.
        .windowToolbarStyle(.unified(showsTitle: false))
        // No `OllinHUDCommands` here: the inspector is the gallery's right
        // sidebar, so the detached "Show Inspector" panel would just duplicate
        // it; ⌘/ toggles the sidebar instead, matching the live host.
        .commands {
            GalleryCommands()
            OllinCameraCommands()
        }
    }
}

/// View ▸ Show Examples (⌥⌘S) and Show Inspector (⌘/), bound to the same
/// `@AppStorage` keys as the title-bar toggles, so the menus, the buttons, and
/// the persisted choices are one state.
private struct GalleryCommands: Commands {
    @AppStorage(GalleryView.examplesShownKey) private var examplesShown = true
    @AppStorage(GalleryView.inspectorShownKey) private var inspectorShown = true

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Show Examples", isOn: $examplesShown)
                .keyboardShortcut("s", modifiers: [.command, .option])
            Toggle("Show Inspector", isOn: $inspectorShown)
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}
