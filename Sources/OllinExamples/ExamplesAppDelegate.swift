import AppKit
import OllinRuntime

/// Activation + lifecycle hooks the SwiftUI `App` lifecycle doesn't cover for a
/// bundleless `swift run` executable: force a regular (foreground) activation
/// policy so the window comes forward, and quit when the last window closes.
///
/// `ensureInitialWindow()` is a temporary patch for a macOS 15 Sequoia SwiftUI
/// regression: a `WindowGroup` app launched with a command-line argument never
/// opens its initial window. The gallery takes no argument today, so it isn't
/// affected in practice — but it shares the guarded call so it stays robust if
/// it ever does. See `SequoiaLaunchWindowWorkaround` for the full story.
final class ExamplesAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        SequoiaLaunchWindowWorkaround.ensureInitialWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
