import Foundation

/// A window of its own for one of a sketch's layers: a second view of the same
/// piece. The sketch draws the layer inside `draw()` as it draws any layer, with
/// whatever camera and size it likes, and the window shows that layer, frame for
/// frame with the sketch's own window.
///
/// ```swift
/// final class Stage: Sketch {
///     var monitor: RenderTarget!
///     var controls: SketchWindow!
///
///     override func setup() {
///         monitor = makeRenderTarget(width: 640, height: 360)
///         controls = makeWindow(showing: monitor, title: "Controls")
///     }
///
///     override func draw() {
///         background(.black)
///         drawCircle(width / 2, height / 2, 200)              // the piece
///
///         withTarget(monitor) {                                // the second view
///             background(Color(white: 0.1))
///             drawCircle(controls.mouseX, controls.mouseY, 12)
///         }
///     }
/// }
/// ```
///
/// The window is the layer's shape and keeps it when resized, and it can be
/// dragged to another display and made full screen there. It reports its own
/// pointer in the layer's coordinates, so a view of controls can be clicked
/// while the piece's own window reads `mouseX` and `mouseY` as before. The keys
/// stay with the sketch's own window.
///
/// A window opens where the sketch runs in a window. In an export, and on a
/// surface that takes no input (a wallpaper, a menu-bar strip), none opens:
/// `isOpen` stays false, the layer is drawn all the same, and the pointer reads
/// zero. See `Docs/Output/Windows.md`.
@MainActor
public final class SketchWindow {

    /// The layer this window shows.
    public let layer: RenderTarget

    /// The window's title.
    public let title: String

    /// Whether the window is on screen: true from the frame the host opens it
    /// until `close()`, or until the person closes it.
    public internal(set) var isOpen = false

    /// The pointer's x over this window, in the layer's coordinates (points
    /// from the layer's left edge). Zero until the pointer has been over it.
    public internal(set) var mouseX: Double = 0

    /// The pointer's y over this window, in the layer's coordinates (points
    /// down from the layer's top edge).
    public internal(set) var mouseY: Double = 0

    /// Whether the mouse button is down over this window.
    public internal(set) var mouseIsPressed = false

    /// The pointer over this window as one point, `(mouseX, mouseY)`.
    public var mouse: Vector2 { Vector2(mouseX, mouseY) }

    /// Set by `close()` and by the person closing the window: the host opens it
    /// no more.
    var isDismissed = false

    /// The host's own teardown for the window it opened, run once by `close()`.
    var onClose: (() -> Void)?

    init(layer: RenderTarget, title: String) {
        self.layer = layer
        self.title = title
    }

    /// Close the window. The layer goes on being drawn; nothing shows it.
    public func close() {
        isDismissed = true
        isOpen = false
        let teardown = onClose
        onClose = nil
        teardown?()
    }

    /// Put the pointer at a place given as fractions of the window's content
    /// (0 to 1 across, 0 to 1 down), which is how the window's view reports it
    /// whatever size the window has been dragged to.
    func setPointer(acrossFraction x: Double, downFraction y: Double) {
        mouseX = x * Double(layer.width)
        mouseY = y * Double(layer.height)
    }
}

public extension Sketch {

    /// Open a window of its own that shows `layer`: a second view of the piece
    /// (a projector's picture beside a view of controls, two cameras on one
    /// world). Call it once, in `setup()`, with a layer made there too, and draw
    /// that layer every frame with `withTarget`.
    ///
    /// - Parameters:
    ///   - layer: the layer to show. The window is its shape.
    ///   - title: the window's title.
    /// - Returns: the window, which reports whether it is open and where its
    ///   own pointer is, and can be closed.
    @discardableResult
    func makeWindow(showing layer: RenderTarget, title: String) -> SketchWindow {
        let window = SketchWindow(layer: layer, title: title)
        layerWindows.append(window)
        return window
    }
}
