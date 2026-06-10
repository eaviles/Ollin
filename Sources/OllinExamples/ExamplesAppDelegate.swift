import AppKit

/// Activation + lifecycle hooks the SwiftUI `App` lifecycle doesn't cover for a
/// bundleless `swift run` executable: force a regular (foreground) activation
/// policy so the window comes forward, and quit when the last window closes.
///
/// The initial window needs no recovery here: a launch argument used to
/// suppress it (AppKit read the argument as a file-open request), but
/// `OllinExamplesApp.init` registers `NSTreatUnknownArgumentsAsOpen = NO`,
/// which removes the misread at its root.
final class ExamplesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
