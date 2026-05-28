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
        let examples = ExampleCatalog.discover()
        // `--list` prints the catalog and exits (no window) — a quick check.
        if CommandLine.arguments.dropFirst().contains("--list") {
            ExampleCatalog.printCatalog(examples)
            exit(0)
        }
        self.examples = examples
    }

    var body: some Scene {
        WindowGroup("Ollin Examples") {
            GalleryView(examples: examples)
        }
        // Sidebar + a fixed square sketch; the window hugs that content (no free
        // resize), and collapsing the sidebar narrows the window to the square.
        .defaultSize(width: OllinApp.defaultWindowSize.width + GalleryView.sidebarWidth,
                     height: OllinApp.defaultWindowSize.height)
        .windowResizability(.contentSize)
    }
}
