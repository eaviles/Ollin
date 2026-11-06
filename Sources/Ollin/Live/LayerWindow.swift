#if os(macOS)
#if canImport(AppKit)

import AppKit
import Metal

/// The window a `SketchWindow` is shown in: a titled window the shape of its
/// layer, holding a view that is a layer to put a frame on and a pointer to
/// report. The frame arrives from the run that draws the sketch's own window
/// (`SketchRunner` asks each pane for its next drawable and presents the layer
/// into it from the same command buffer), so the two windows are never a frame
/// apart.
@MainActor
final class LayerWindowPane: NSObject, NSWindowDelegate {

    let sketchWindow: SketchWindow
    let window: OllinDisplayWindow
    let view: LayerWindowView

    /// - Parameter anchor: the sketch's own window, which this one opens beside.
    init(showing sketchWindow: SketchWindow, device: MTLDevice, output: ColorOutput,
         beside anchor: NSWindow?) {
        self.sketchWindow = sketchWindow
        let layer = sketchWindow.layer
        let shape = CGSize(width: max(1, layer.width), height: max(1, layer.height))
        let size = OllinApp.windowSize(fitting: shape)
        // A step down and to the right of the sketch's own window, on its
        // screen; the middle of the main screen when there is none to stand by.
        var origin = CGPoint(x: 120, y: 120)
        if let anchor {
            origin = CGPoint(x: anchor.frame.maxX + 24, y: anchor.frame.maxY - size.height - 28)
            if let visible = anchor.screen?.visibleFrame {
                origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
                origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height - 28))
            }
        }
        let window = OllinDisplayWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Ollin - \(sketchWindow.title)"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        // The layer's shape at any size, and a green button that fills the
        // display the window was dragged to (a projector's, say).
        window.contentAspectRatio = shape
        window.collectionBehavior = [.fullScreenPrimary]

        let view = LayerWindowView(device: device, output: output)
        view.frame = CGRect(origin: .zero, size: size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        self.window = window
        self.view = view
        super.init()

        window.delegate = self
        view.onPointer = { [weak sketchWindow] across, down, pressed in
            guard let sketchWindow else { return }
            sketchWindow.setPointer(acrossFraction: across, downFraction: down)
            if let pressed { sketchWindow.mouseIsPressed = pressed }
        }
        sketchWindow.onClose = { [weak self] in self?.tearDown() }
    }

    /// Put the window on screen. Apart from making it, so a test can look a
    /// pane over without putting windows on the machine the tests run on.
    func show() {
        window.orderFront(nil)
        sketchWindow.isOpen = true
    }

    /// What the run presents this frame's layer into, or nil when the window
    /// has no size to draw at yet or no drawable free (it then sits the frame
    /// out rather than hold the sketch's own window up).
    func nextDisplay() -> MetalRenderer.ExtraDisplay? {
        let layer = view.metalLayer
        let size = layer.drawableSize
        guard size.width > 0, size.height > 0, let drawable = layer.nextDrawable() else { return nil }
        return MetalRenderer.ExtraDisplay(drawable: drawable, placement: nil, layer: sketchWindow.layer)
    }

    /// The run is done with this window (the sketch was replaced, or its own
    /// window went away): take it down and say so on the value the sketch holds.
    func close() {
        sketchWindow.onClose = nil
        sketchWindow.isOpen = false
        tearDown()
    }

    private func tearDown() {
        window.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
    }

    /// The person closed the window: it is not opened again for this sketch.
    func windowWillClose(_ notification: Notification) {
        sketchWindow.onClose = nil
        sketchWindow.isDismissed = true
        sketchWindow.isOpen = false
        sketchWindow.mouseIsPressed = false
    }
}

/// A layer to put a frame on that also says where the pointer is over it, as
/// fractions of its own size, so the answer holds at any window size.
final class LayerWindowView: OllinDisplayView {

    /// The pointer moved or a button changed: across (0 to 1 from the left),
    /// down (0 to 1 from the top), and the button's new state when it changed.
    var onPointer: ((Double, Double, Bool?) -> Void)?

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    /// A click in a window that is not the key one still lands, since this
    /// window never takes the keys from the sketch's own.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Report a place given in the window's own coordinates (points up from the
    /// bottom left, as events carry it).
    func report(_ location: CGPoint, pressed: Bool? = nil) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let across = Double(location.x / bounds.width)
        let down = 1 - Double(location.y / bounds.height)
        onPointer?(min(max(across, 0), 1), min(max(down, 0), 1), pressed)
    }

    private func report(_ event: NSEvent, pressed: Bool? = nil) {
        report(convert(event.locationInWindow, from: nil), pressed: pressed)
    }

    override func mouseMoved(with event: NSEvent) { report(event) }
    override func mouseDragged(with event: NSEvent) { report(event) }
    override func mouseDown(with event: NSEvent) { report(event, pressed: true) }
    override func mouseUp(with event: NSEvent) { report(event, pressed: false) }
}

#endif
#endif
