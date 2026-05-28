import AppKit

/// Activation + lifecycle hooks for the bundleless `swift run` executable: adopt
/// a regular (foreground) activation policy and activate, and quit when the
/// window closes.
///
/// Note: launched via `swift run` (no `.app` bundle) the window currently comes
/// up behind the terminal and needs a Dock click to surface — a known launch
/// quirk tracked for a later fix; the app is otherwise fully functional.
final class LiveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
