import AppKit
import Metal
import QuartzCore
import SwiftUI

/// One machine driving several displays: a window and a drawable on each of
/// them, all carrying one canvas that is drawn once a frame.
///
/// Host chrome, like the calibrator and the stats panel: it owns windows and
/// never draws into the canvas or reaches an export. The piece itself knows
/// nothing about how many displays it is on. It draws its canvas, and the wall
/// decides which part of that canvas each display carries.
///
/// The display the piece's own window is on is called the primary one. It is the
/// display the frames are drawn in, and it is fitted through the run's own
/// placement, exactly as a piece on one screen always was. Every other display
/// is a window with nothing in it but a layer, handed the same frame in the same
/// command buffer.
@MainActor
final class DisplayWall {

    private let installation: Installation
    private let canvas: Vector2
    /// How many parts to lay out on one desk, for a wall that is not built yet.
    private let rehearsing: Int?

    /// One per display that carries anything, the first of them the primary.
    private(set) var outputs: [DisplayOutput] = []
    private weak var runner: SketchRunner?
    private weak var sketch: Sketch?
    /// Said once: the plan is worked out again every time the displays change,
    /// and a line about the room's corners each time would bury the log.
    private var saidCalibration = false

    init(_ installation: Installation, canvas: Vector2, rehearsing: Int? = nil) {
        self.installation = installation
        self.canvas = canvas
        self.rehearsing = rehearsing
        outputs = build(plan())
    }

    /// One output per part, and never none: a run with no screen at all still
    /// has a piece to fit, and everything downstream reads `primary`.
    private func build(_ parts: [WallPart]) -> [DisplayOutput] {
        let parts = parts.isEmpty
            ? [WallPart(frame: Rectangle(x: 0, y: 0, width: canvas.x, height: canvas.y),
                        key: nil, projection: installation.projection, isPrimary: true)]
            : parts
        return parts.map { DisplayOutput($0, canvas: canvas,
                                         hidesPointer: installation.hidesPointer) }
    }

    /// The display the piece's own window is on, which is the one the frames are
    /// drawn in.
    var primary: DisplayOutput { outputs[0] }

    /// Every calibrator on the wall, so one key opens the handles on all of them
    /// and the arrow keys can be sent to whichever display is being worked on.
    var calibrators: [ProjectionCalibrator] { outputs.map(\.calibrator) }

    /// Whether this is one display after all, which is the ordinary run.
    var isOneDisplay: Bool { outputs.count <= 1 }

    /// Where the piece's own window goes: the primary part's own rectangle.
    var primaryFrame: CGRect? { SketchRunner.screenRect(primary.part.frame) }

    // MARK: Opening

    /// Open a window on every other display and hand them to the run.
    ///
    /// Called once the view has built a runner, which is also when the device
    /// the frames are made on is known: a drawable can only take a frame made on
    /// the same device it came from.
    func open(with runner: SketchRunner, sketch: Sketch) {
        self.runner = runner
        self.sketch = sketch
        primary.driveRunner(runner)
        guard !isOneDisplay else { return }
        for output in outputs.dropFirst() {
            // A still piece draws once. A display that gains its size after that
            // frame asks for another, or it stays black for the rest of the run.
            output.onNeedsFrame = { [weak runner] in runner?.redrawOnce() }
            output.openWindow(device: runner.metalDevice, sketch: sketch,
                              titled: rehearsing != nil)
        }
        runner.setOtherDisplays(Array(outputs.dropFirst()))
        say()
    }

    /// Say what the wall is, once, in the log a run left alone for a week is read
    /// through.
    private func say() {
        let where_ = rehearsing != nil ? "rehearsing" : "on"
        let parts = outputs.map { part -> String in
            let shows = part.part.projection.shows
            return "\(Int(shows.width * 100))x\(Int(shows.height * 100))% at "
                + "\(Int(shows.x * 100)),\(Int(shows.y * 100))%"
        }
        ollinInstallationLog("\(where_) \(outputs.count) displays: \(parts.joined(separator: ", "))")
        if rehearsing != nil {
            ollinInstallationLog("a rehearsal shows the layout, not the light: "
                                 + "two beams sharing a band add up, two windows cannot")
        }
    }

    /// Take the wall down. The piece's own window is not ours to close.
    func close() {
        runner?.setOtherDisplays([])
        for output in outputs.dropFirst() { output.closeWindow() }
    }

    // MARK: When the displays change

    /// A display was plugged in, unplugged, or re-resolved. The parts are worked
    /// out again and the extra windows rebuilt, because which display carries
    /// what has just changed.
    ///
    /// A rehearsal is left alone: its windows stand for displays that are not
    /// here, so a real one arriving says nothing about them.
    func displaysChanged() {
        guard rehearsing == nil, let runner, let sketch else { return }
        let rebuilt = plan()
        guard rebuilt != outputs.map(\.part) else { return }
        for output in outputs.dropFirst() { output.closeWindow() }
        runner.setOtherDisplays([])
        outputs = build(rebuilt)
        open(with: runner, sketch: sketch)
    }

    // MARK: The plan

    /// The parts, with the corners this room has already been lined up with in
    /// them. The declaration says what each display carries; the file says how
    /// each display is out of true, which belongs to the room rather than to the
    /// work.
    private func plan() -> [WallPart] {
        var parts = WallPlan.parts(installation.displays, base: installation.projection,
                                   canvas: canvas, screens: DisplayWall.screens(),
                                   rehearsing: rehearsing)
        var kept = 0
        for index in parts.indices {
            guard let key = parts[index].key,
                  let saved = ProjectionCalibration.corners(forDisplay: key) else { continue }
            parts[index].projection.corners = saved
            kept += 1
        }
        if kept > 0, !saidCalibration {
            saidCalibration = true
            ollinInstallationLog("lined up already: corners kept for "
                                 + (kept == 1 ? "this display" : "\(kept) displays"))
        }
        // The primary first, so the run's own display is always outputs[0] and
        // the window has one rectangle to be moved to.
        if let primary = parts.firstIndex(where: \.isPrimary), primary != 0 {
            parts.swapAt(0, primary)
        }
        return parts
    }

    /// The displays, measured the way the canvas is: from the top left of the
    /// primary display, y downwards.
    static func screens() -> [WallScreen] {
        let main = NSScreen.main
        return NSScreen.screens.compactMap { screen in
            guard let frame = SketchRunner.desktopRect(screen.frame),
                  let visible = SketchRunner.desktopRect(screen.visibleFrame) else { return nil }
            return WallScreen(frame: frame, visible: visible,
                              key: ProjectionCalibration.key(for: screen),
                              isPrimary: screen == main)
        }
    }
}

// MARK: - One display of the wall

/// One display a piece is put on: what it carries, the window it fills, and the
/// handles for lining it up.
@MainActor
final class DisplayOutput: CanvasOutput {

    private(set) var part: WallPart
    let calibrator: ProjectionCalibrator
    private let canvas: Vector2

    private var window: OllinDisplayWindow?
    private var view: OllinDisplayView?
    /// The last placement that had an inside. A hand dragging one corner past
    /// another makes a shape with no map through it for a moment, and a picture
    /// that vanishes under the hand is a picture nobody can drag.
    private var lastGood: ProjectionPlacement?
    /// Set for the display the frames are drawn in, whose fitting is the run's
    /// own rather than this object's.
    private weak var runner: SketchRunner?

    init(_ part: WallPart, canvas: Vector2, hidesPointer: Bool) {
        self.part = part
        self.canvas = canvas
        calibrator = ProjectionCalibrator(projection: part.projection, canvas: canvas,
                                          displayKey: part.key, hidesPointer: hidesPointer)
        calibrator.onChange = { [weak self] projection in
            guard let self else { return }
            self.part.projection = projection
            self.runner?.setProjection(projection)
        }
    }

    /// An output for the run that has no wall at all, so nothing has to unwrap.
    static func placeholder(canvas: Vector2) -> DisplayOutput {
        DisplayOutput(WallPart(frame: Rectangle(x: 0, y: 0, width: 1, height: 1),
                               key: nil, projection: .direct, isPrimary: true),
                      canvas: canvas, hidesPointer: false)
    }

    /// Make this the display the frames are drawn in: its fitting is the run's
    /// own placement, which the renderer already carries.
    func driveRunner(_ runner: SketchRunner) {
        self.runner = runner
        runner.setProjection(part.projection)
    }

    // MARK: The window

    func openWindow(device: MTLDevice, sketch: Sketch, titled: Bool) {
        guard window == nil, let frame = SketchRunner.screenRect(part.frame) else { return }
        let style: NSWindow.StyleMask = titled ? [.titled, .closable] : [.borderless]
        let window = OllinDisplayWindow(contentRect: frame, styleMask: style,
                                        backing: .buffered, defer: false)
        window.title = sketch.title
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.hasShadow = false
        // A wall belongs to every space: a piece must not go away because
        // somebody swiped to another desktop on the machine driving it.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]

        window.takesKeys = calibrator.isOpen
        let canvasView = OllinDisplayView(device: device, output: sketch.colorOutput)
        canvasView.onSized = { [weak self] in self?.onNeedsFrame?() }
        canvasView.autoresizingMask = [.width, .height]
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        canvasView.frame = container.bounds
        container.addSubview(canvasView)

        // The same handles as the piece's own display, over this one's picture.
        let overlay = NSHostingView(rootView: CalibrationOverlay(calibrator: calibrator))
        overlay.frame = container.bounds
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)

        window.contentView = container
        if titled {
            window.setFrame(window.frameRect(forContentRect: frame), display: true)
        } else {
            window.setFrame(frame, display: true)
        }
        window.orderFront(nil)
        self.window = window
        self.view = canvasView
    }

    func closeWindow() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        view = nil
    }

    /// Whether this window is allowed the keyboard, which it is only while
    /// somebody is lining the wall up. It is not made key here: the piece's own
    /// window keeps the keys until somebody clicks a display to work on it.
    func takeKeys(_ takes: Bool) {
        window?.takesKeys = takes
    }

    /// Whether this display has the keyboard, which is how the keys that move a
    /// corner find the display somebody is working on.
    var isKeyWindow: Bool { window?.isKeyWindow ?? false }

    /// Take the picture away for the night, leaving the window's own black. A
    /// window ordered out would show the desktop, which is the one thing a wall
    /// must never do.
    func setShowing(_ showing: Bool) {
        view?.isHidden = !showing
    }

    /// Asked for when this display has a size to draw at, so a still piece that
    /// has already drawn its one frame puts it up here too.
    var onNeedsFrame: (() -> Void)?

    // MARK: What the runner asks for

    func nextDisplay(canvas: Vector2) -> MetalRenderer.ExtraDisplay? {
        guard let view, !view.isHidden else { return nil }
        let layer = view.metalLayer
        let size = layer.drawableSize
        guard size.width > 0, size.height > 0 else { return nil }
        let placement = ProjectionPlacement(part.projection, canvas: canvas,
                                            output: Vector2(Double(size.width),
                                                            Double(size.height))) ?? lastGood
        lastGood = placement
        // A display with no drawable free sits this frame out rather than
        // holding up every other display on the wall.
        guard let drawable = layer.nextDrawable() else { return nil }
        return MetalRenderer.ExtraDisplay(drawable: drawable, placement: placement)
    }

    func canvasDemand(canvas: Vector2) -> (size: CGSize, part: Rectangle)? {
        guard let layer = view?.metalLayer else { return nil }
        let size = layer.drawableSize
        guard size.width > 0, size.height > 0 else { return nil }
        return (size, part.projection.shows)
    }
}

// MARK: - The window and the layer

/// A window for a display of a wall.
///
/// It takes the keyboard only while the handles are up. A wall is not something
/// anybody types at, and a window on it stealing the keys would leave a
/// key-reading piece deaf on the display it is actually drawn in.
final class OllinDisplayWindow: NSWindow {
    var takesKeys = false
    override var canBecomeKey: Bool { takesKeys }
    override var canBecomeMain: Bool { takesKeys }
}

/// A view that is nothing but a layer to put a frame on.
///
/// The piece's own display is an `MTKView` with a draw loop, a pointer, and a
/// keyboard. A wall display has none of that: the frame arrives from the display
/// that is drawing, so all this has to do is hold a layer of the right shape, in
/// the right format, at the right scale.
final class OllinDisplayView: NSView {

    let metalLayer = CAMetalLayer()

    /// Told when the layer has a size to draw at, so a still piece can be asked
    /// for the one frame this display has never been given.
    var onSized: (() -> Void)?

    init(device: MTLDevice, output: ColorOutput) {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        metalLayer.device = device
        // The same format, space and headroom the piece's own display uses, or
        // one display of a wall would answer the same numbers differently.
        metalLayer.pixelFormat = output.drawablePixelFormat
        if let space = output.displayColorSpace { metalLayer.colorspace = space }
        metalLayer.wantsExtendedDynamicRangeContent = output.wantsExtendedDynamicRange
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.allowsNextDrawableTimeout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override func makeBackingLayer() -> CALayer { metalLayer }

    override func layout() {
        super.layout()
        resize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resize()
    }

    /// Keep the drawable the size of the display in pixels. A display of a wall
    /// can be a different scale from the one being drawn in, so this is read
    /// from the window it is actually on.
    private func resize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width > 0, size.height > 0, size != metalLayer.drawableSize else { return }
        metalLayer.drawableSize = size
        onSized?()
    }
}
