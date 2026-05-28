#if canImport(AppKit)
import AppKit

// ⚠️ TEMPORARY WORKAROUND — delete this whole file (and its two call sites) once
// Apple fixes the regression described below.
//
// macOS 15 (Sequoia) + the Xcode 16 SwiftUI runtime: a bundleless `WindowGroup`
// app launched as a bare binary *with any positional command-line argument*
// never gets its automatic initial window. AppKit reads the argument as a
// file-open request and skips untitled-window creation, so SwiftUI builds zero
// windows and the app sits in the Dock with nothing on screen until a click
// wakes it. The `swift run` hosts hit this: OllinLive always passes a sketch
// path; OllinExamples is fine with no arguments but breaks the moment it is
// given one. (Confirmed with the same binary, arg vs no-arg.)
//
// REMOVAL: when the regression is gone, delete this file and the
// `ensureInitialWindow()` calls in OllinLive's and OllinExamples's app
// delegates. Verify by running `swift run OllinLive <sketch>` and
// `swift run OllinExamples somearg` and confirming each window comes up in
// front on its own, with no Dock click.

/// Recovery for the Sequoia "no initial window when launched with arguments"
/// regression. The host delegates call `ensureInitialWindow()` from
/// `applicationDidFinishLaunching`, after `setActivationPolicy(.regular)` and
/// before `activate(ignoringOtherApps:)`.
public enum SequoiaLaunchWindowWorkaround {
    /// If AppKit suppressed the `WindowGroup`'s automatic window, create one by
    /// firing SwiftUI's New Window command. No-ops once a window exists, so a
    /// normal launch — or a future `.app` double-click — is left untouched.
    @MainActor public static func ensureInitialWindow() {
        guard !NSApp.windows.contains(where: { $0.canBecomeMain }) else { return }
        guard let item = newWindowMenuItem(), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    /// The "New Window" item SwiftUI installs under File. Matched by its ⌘N key
    /// equivalent rather than title so it survives localization (the title is
    /// translated; the shortcut is not, and SwiftUI's menu action is the generic
    /// `menuAction:` so the selector is no help), with the English title as a
    /// last-resort fallback.
    @MainActor private static func newWindowMenuItem() -> NSMenuItem? {
        let submenus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        for submenu in submenus {
            if let item = submenu.items.first(where: {
                $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command
            }) {
                return item
            }
        }
        return submenus.flatMap(\.items).first { $0.title == "New Window" }
    }
}
#endif
