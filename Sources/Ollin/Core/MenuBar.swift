#if canImport(AppKit)

import AppKit
import MetalKit

extension OllinApp {
    /// Run a sketch in the menu bar: a small live canvas among the status
    /// items, on screen for the whole working day.
    ///
    /// ```swift
    /// @main
    /// enum PulseItem {
    ///     @MainActor static func main() {
    ///         if OllinApp.handleCommandLine(makeSketch: { Pulse() }) { return }
    ///         OllinApp.runInMenuBar { Pulse() }
    ///     }
    /// }
    /// ```
    ///
    /// `ollin new --kind menu-bar` writes that file and the wrapper that makes
    /// an app of it. See `Docs/Output/MenuBar.md`.
    ///
    /// `width` is the strip's width in points; the height is the menu bar's
    /// own. A sketch that follows its view draws at exactly that size, and one
    /// that states its own canvas is fitted into the strip at its own
    /// proportions. A click on the strip opens the menu that quits the piece,
    /// and nothing else reaches the sketch: the menu bar is no place to type.
    public static func runInMenuBar(width: Double = 56,
                                    _ makeSketch: @escaping @MainActor () -> Sketch) {
        let app = NSApplication.shared
        // An accessory: the piece is the status item, so there is nothing to
        // put in the Dock or the app switcher.
        app.setActivationPolicy(.accessory)
        let host = MenuBarHost(width: width, makeSketch: makeSketch)
        MenuBarHost.current = host
        app.delegate = host
        app.run()
    }
}

/// The program around a menu-bar run: one status item holding a running
/// canvas, and the menu that quits it.
@MainActor
final class MenuBarHost: NSObject, NSApplicationDelegate {

    /// The host of the run, held so the application's delegate lives as long
    /// as the application does.
    static var current: MenuBarHost?

    private let width: Double
    private let makeSketch: @MainActor () -> Sketch
    private(set) var statusItem: NSStatusItem?
    private(set) var canvas: OllinMTKView?
    private(set) var runner: SketchRunner?
    private var sketch: Sketch?

    init(width: Double, makeSketch: @escaping @MainActor () -> Sketch) {
        // A strip narrower than a few points cannot be clicked, and the click
        // is the way out.
        self.width = max(8, width)
        self.makeSketch = makeSketch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        remove()
    }

    /// Put the strip up. Separate from the application's own lifecycle so a
    /// test can build it, look it over, and take it down again.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: CGFloat(width))
        statusItem = item

        // No device, no picture. The item still goes up with its menu, so the
        // program can be quit the ordinary way rather than found and killed.
        guard let device = MTLCreateSystemDefaultDevice(), let button = item.button else {
            item.menu = surfaceQuitMenu(for: ProcessInfo.processInfo.processName)
            return
        }

        let sketch = makeSketch()
        // The bar has not always laid the button out by now; its own thickness
        // is the height either way.
        let size = button.bounds.isEmpty
            ? CGSize(width: width, height: NSStatusBar.system.thickness)
            : button.bounds.size
        let canvas = makeOllinMTKView(device: device, size: size, sketch: sketch)
        // A click opens the menu, never the sketch, and no key ever arrives:
        // the strip must not take the keyboard from whatever is being typed in.
        canvas.ignoresInput = true
        canvas.claimsKeyboardOnAttach = false
        canvas.frame = CGRect(origin: .zero, size: size)
        canvas.autoresizingMask = [.width, .height]
        // A strip beside the clock is worth a moving picture, not a whole
        // display's worth of frames, on a surface that is up all day. The rate
        // is the strip's own, so the run is never retimed to its display.
        canvas.preferredFramesPerSecond = 30

        let runner = SketchRunner(sketch: sketch, view: canvas, device: device)
        canvas.delegate = runner
        // Fitted into the strip when the sketch states its own shape, drawn
        // at the strip's size when it follows its view.
        if sketchKeepsItsShape(sketch) { runner.setProjection(.direct) }

        button.addSubview(canvas)
        button.toolTip = sketch.title
        item.menu = surfaceQuitMenu(for: sketch.title)

        self.sketch = sketch
        self.canvas = canvas
        self.runner = runner
    }

    func remove() {
        canvas?.isPaused = true
        canvas?.delegate = nil
        canvas?.removeFromSuperview()
        canvas = nil
        runner = nil
        sketch = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}

#endif
