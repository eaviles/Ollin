import AppKit
import OllinRuntime

/// Activation + lifecycle hooks for the bundleless `swift run` executable: adopt
/// a regular (foreground) activation policy, then activate.
///
/// `ensureInitialWindow()` works around a macOS 15 Sequoia SwiftUI regression
/// where a `WindowGroup` app launched with a command-line argument (OllinLive
/// always passes the sketch path) never opens its initial window. It's a
/// temporary patch — see `SequoiaLaunchWindowWorkaround` for the full story and
/// removal steps.
final class LiveAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        SequoiaLaunchWindowWorkaround.ensureInitialWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
