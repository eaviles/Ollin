#if os(macOS)
#if canImport(ScreenSaver)

import AppKit
import MetalKit
import ScreenSaver

/// Runs a sketch as the machine's screen saver.
///
/// A screen saver is a plug-in: a `.saver` folder holding one binary, dropped in
/// `~/Library/Screen Savers`, which the system loads and asks for the class named
/// in its `Info.plist`. Subclass this, name the sketch, and pin the class name
/// for the Objective-C runtime the plug-in is read through:
///
/// ```swift
/// @objc(DriftSaverView)
/// final class DriftSaverView: SketchSaverView {
///     override func makeSketch() -> Sketch { Drift() }
/// }
/// ```
///
/// `ollin new --kind screen-saver` writes that file, the property list, and the
/// script that puts the folder together. See `Docs/Output/ScreenSaver.md`.
///
/// The sketch runs exactly as it runs in a window, with two differences the
/// setting makes necessary. It takes no input, because the contract of a screen
/// saver is that a key or a click gives the machine back, and a canvas that
/// answered the click would eat it. And a canvas that is not `.resizable` is
/// centered at its own proportions on black, the way a piece is fitted to a wall,
/// because a display is almost never the shape of the canvas.
open class SketchSaverView: ScreenSaverView {

    /// The sketch this saver draws. Override it. It is called once, the first
    /// time the saver starts.
    ///
    /// The default is a sketch that draws nothing. A screen saver is the worst
    /// place to stop a program, so a subclass that forgets this shows black
    /// rather than taking the machine down with it.
    open func makeSketch() -> Sketch { Sketch() }

    private var sketch: Sketch?
    private var canvas: OllinMTKView?
    /// What drives the frames. Nil until the system starts the saver, and nil
    /// again once it is over.
    private(set) var runner: SketchRunner?

    /// Whether a sketch is fitted into the display or drawn across the whole of
    /// it. A sketch that follows its view already fills what it is put on; one
    /// that states a size of its own keeps those proportions, centered on black,
    /// since a display is almost never the shape of a canvas.
    static func fitsIntoTheDisplay(_ sketch: Sketch) -> Bool {
        if case .resizable = sketch.windowMode { return false }
        return true
    }

    /// The undocumented word the system sends when the saver is really over.
    /// `stopAnimation()` is not it: that one arrives for the small preview in
    /// System Settings and stays quiet when somebody wakes the machine, which is
    /// how a saver is left running against a screen nobody is looking at.
    private static let willStop = Notification.Name("com.apple.screensaver.willstop")

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // The canvas keeps its own clock off the display link, so nothing is
        // asked of the base timer. It cannot be turned off, so it is turned down.
        animationTimeInterval = 1
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(screenSaverWillStop),
            name: Self.willStop, object: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }

    // MARK: Lifecycle

    open override func startAnimation() {
        super.startAnimation()
        if canvas == nil { build() }
        canvas?.isPaused = false
    }

    open override func stopAnimation() {
        super.stopAnimation()
        canvas?.isPaused = true
    }

    open override func layout() {
        super.layout()
        canvas?.frame = bounds
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Out of the window is over for this copy. The system builds a fresh
        // view every time the saver comes up and lets go of none of them, so a
        // copy that does not put itself away goes on drawing frames nobody sees,
        // on a GPU the next copy wants.
        if window == nil {
            release()
        } else {
            runner?.displayChanged(to: window?.screen)
        }
    }

    @objc private func screenSaverWillStop(_ notification: Notification) {
        release()
    }

    // MARK: Building and putting away

    private func build() {
        // No device, no picture. Every other host stops the program here, and
        // none of them is the thing standing between somebody and their desktop.
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let sketch = makeSketch()
        let canvas = makeOllinMTKView(device: device, size: sketch.canvasSize.cgSize, sketch: sketch)
        canvas.ignoresInput = true
        canvas.claimsKeyboardOnAttach = false
        canvas.frame = bounds
        let runner = SketchRunner(sketch: sketch, view: canvas, device: device)
        canvas.delegate = runner
        // Same present pass a projector goes through, with nothing dragged out
        // of true.
        if Self.fitsIntoTheDisplay(sketch) { runner.setProjection(.direct) }
        // The preview pane in System Settings is a thumbnail beside a list of
        // other savers. It is worth a picture, not a whole display's worth of
        // frames.
        if isPreview { canvas.preferredFramesPerSecond = 30 }
        addSubview(canvas)
        self.sketch = sketch
        self.canvas = canvas
        self.runner = runner
        runner.displayChanged(to: window?.screen)
    }

    private func release() {
        canvas?.isPaused = true
        canvas?.delegate = nil
        canvas?.removeFromSuperview()
        canvas = nil
        runner = nil
        sketch = nil
    }
}

#endif

#endif
