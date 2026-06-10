import AppKit

/// Activation + lifecycle hooks for the bundleless `swift run` executable: adopt
/// a regular (foreground) activation policy, then activate.
///
/// The initial window needs no recovery here: launching with the sketch-path
/// argument used to suppress it (AppKit read the argument as a file-open
/// request), but `OllinLiveApp.init` now registers
/// `NSTreatUnknownArgumentsAsOpen = NO`, which removes the misread at its root.
final class LiveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
