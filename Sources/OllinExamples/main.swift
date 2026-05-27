import AppKit
import SwiftUI

// OllinExamples — the examples gallery.
//
//   swift run OllinExamples
//
// Lists every Examples/ sketch in a sidebar; click one and it compiles and runs
// in the detail pane. Run from the repo root (it scans the Examples/ source tree
// and compiles via the toolchain, like OllinLive).
//
// Boots through AppKit (mirroring OllinApp.run) rather than a SwiftUI `App` so
// the window reliably shows and activates when launched from `swift run`; the
// SwiftUI UI is hosted via NSHostingView.

let examples = ExampleCatalog.discover()

// `--list` prints the catalog and exits (no window) — handy for a quick check.
if CommandLine.arguments.dropFirst().contains("--list") {
    for category in ExampleCatalog.categories(of: examples) {
        print(category)
        for example in examples where example.category == category {
            print("  \(example.displayName)")
        }
    }
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: CGRect(x: 0, y: 0, width: 1000, height: 680),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false)
window.title = "Ollin Examples"
window.contentView = NSHostingView(rootView: GalleryView(examples: examples))
window.setFrameAutosaveName("OllinExamples")
window.center()
window.makeKeyAndOrderFront(nil)

application.mainMenu = makeMenu()
let delegate = ExamplesAppDelegate()
application.delegate = delegate

application.activate(ignoringOtherApps: true)
application.run()

// MARK: - Menu & lifecycle

func makeMenu() -> NSMenu {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Ollin Examples",
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    return mainMenu
}

final class ExamplesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
