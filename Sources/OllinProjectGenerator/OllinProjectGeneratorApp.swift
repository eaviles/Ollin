import SwiftUI
import Ollin

// OllinProjectGenerator: the project generator with a window.
//
//   swift run OllinProjectGenerator
//
// Pick what to make, pick a starting point and watch it actually run, tick what
// it should be wired for, and create it. The same `OllinProjects` library the
// `ollin new` command uses decides every file, so the two faces can never
// disagree about what a project is.
@main
struct OllinProjectGeneratorApp: App {
    @NSApplicationDelegateAdaptor(GeneratorAppDelegate.self) private var delegate

    init() {
        // Stop AppKit reading a stray argument as a file-open request, which
        // suppresses the initial window on a bundleless launch (the same misread
        // the other hosts register against).
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
    }

    var body: some SwiftUI.Scene {
        // One window by design, like the gallery: a second generator buys nothing.
        Window("New Ollin Project", id: "main") {
            GeneratorView()
        }
        // Resizable, unlike its sibling hosts: the stage is the reason to open
        // this window rather than type the command, so it should take the slack
        // instead of holding a fixed size.
        .defaultSize(width: 1280, height: 760)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

/// Activation for a bundleless `swift run` executable, and quit on close.
final class GeneratorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
