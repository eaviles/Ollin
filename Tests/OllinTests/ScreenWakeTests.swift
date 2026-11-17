@testable import Ollin
import AppKit
import Metal
import Testing

/// A canvas opened while no display is awake gets a frame timer that never
/// fires, so the canvas rebuilds its timer whenever the screen under it can
/// have changed. A test cannot put the display to sleep, so this pins what the
/// rebuild answers to and what it must never do: start a canvas whose loop is
/// held, or keep listening after the canvas leaves its window. The display
/// case itself was proven by hand: with the timer left as made, a window
/// opened in the dark drew nothing, and with it rebuilt it drew about 55
/// frames a second from the wake.
///
/// The canvas decides none of this itself. It tells the runner driving it,
/// which holds the loop for the sleep as one reason among the others
/// (`LoopHold`), so every canvas here has its runner, as every canvas in a
/// window does.
@Suite
@MainActor
struct ScreenWakeTests {
    private struct Canvas {
        let sketch: Sketch
        let view: OllinMTKView
        let runner: SketchRunner
        let window: NSWindow
    }

    private func makeCanvas() throws -> Canvas {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Sketch()
        let view = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64), sketch: sketch)
        view.drawableSize = CGSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        view.delegate = runner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        // The first frame, so the run is set up: until then a sketch is owed
        // that frame whatever it says about its own loop.
        runner.draw(in: view)
        return Canvas(sketch: sketch, view: view, runner: runner, window: window)
    }

    private func putAway(_ canvas: Canvas) {
        canvas.runner.holdLoop(.closed)
        canvas.view.delegate = nil
        canvas.window.contentView = nil
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aScreenChangeRebuildsARunningCanvasTimerAndLeavesAHeldOneAlone() throws {
        let canvas = try makeCanvas()
        defer { putAway(canvas) }
        let view = canvas.view, window = canvas.window
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

        // A canvas whose loop is held stays held through a wake.
        canvas.sketch.noLoop()
        #expect(view.isPaused)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(view.isPaused)
        #expect(view.frameTimerRestarts == start + 4)

        // Out of its window, it no longer listens.
        canvas.sketch.loop()
        #expect(!view.isPaused)
        window.contentView = nil
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(view.frameTimerRestarts == start + 4)
    }

    /// A frame committed as the GPU powers down can come back as a hang blamed
    /// on the sketch, after which the window's queue is refused. So the loop
    /// holds at the will-sleep notice and starts again at the wake, and the
    /// wake starts only a loop nothing else holds: a canvas held before the
    /// sleep, or by something that arrived during it, stays held.
    @Test(.enabled(if: Snapshot.hasMetal))
    func sleepHoldsARunningCanvasAndTheWakeStartsOnlyALoopNothingElseHolds() throws {
        let canvas = try makeCanvas()
        defer { putAway(canvas) }
        let view = canvas.view
        let workspace = NSWorkspace.shared.notificationCenter
        let start = view.frameTimerRestarts
        #expect(!view.isPaused)

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(view.isPaused)
        // The screens waking on their own leaves the hold alone.
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(view.isPaused)
        #expect(view.frameTimerRestarts == start)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!view.isPaused)
        #expect(view.frameTimerRestarts == start + 1)

        // Held by its sketch before the sleep: the wake does not start it.
        canvas.sketch.noLoop()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(view.isPaused)
        #expect(view.frameTimerRestarts == start + 1)

        // The sketch starting its loop during the sleep does not start the
        // timer, and the wake then does.
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        canvas.sketch.loop()
        #expect(view.isPaused, "a frame asked for as the Mac goes down reached the timer")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!view.isPaused)
        #expect(view.frameTimerRestarts == start + 2)

        // Shut for the night while it slept: the wake does not start it.
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        canvas.runner.setShowing(false)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(view.isPaused, "the wake started a piece its schedule had shut")
        #expect(view.frameTimerRestarts == start + 2)
    }
}
