import AppKit

/// Activation + lifecycle hooks the SwiftUI `App` lifecycle doesn't cover for a
/// bundleless `swift run` executable: force a regular (foreground) activation
/// policy so the window comes forward, and quit when the last window closes.
final class ExamplesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
