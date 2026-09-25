@testable import Ollin
import AppKit
import Metal
import Testing

/// A canvas opened while no display is awake gets a frame timer that never
/// fires, so the canvas rebuilds its timer whenever the screen under it can
/// have changed. A test cannot put the display to sleep, so this pins what the
/// rebuild answers to and what it must never do: start a canvas its runner
/// paused, or keep listening after the canvas leaves its window. The display
/// case itself was proven by hand: with the timer left as made, a window
/// opened in the dark drew nothing, and with it rebuilt it drew about 55
/// frames a second from the wake.
@Suite
@MainActor
struct ScreenWakeTests {
    @Test(.enabled(if: Snapshot.hasMetal))
    func aScreenChangeRebuildsARunningCanvasTimerAndLeavesAPausedOneAlone() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: Sketch())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let workspace = NSWorkspace.shared.notificationCenter

        // Each way the screen under it can change rebuilds the timer, and the
        // canvas keeps running.
        let start = view.frameTimerRestarts
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        #expect(view.frameTimerRestarts == start + 4)
        #expect(!view.isPaused)

        // A canvas its runner paused stays paused through a wake.
        view.isPaused = true
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(view.isPaused)
        #expect(view.frameTimerRestarts == start + 4)

        // Out of its window, it no longer listens.
        view.isPaused = false
        window.contentView = nil
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(view.frameTimerRestarts == start + 4)
    }
}
