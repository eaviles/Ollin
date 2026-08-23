import Foundation

/// The pan-and-zoom state one sketch carries for ``Sketch/viewControl(center:zoom:in:)``.
///
/// Held per sketch and advanced once a frame. The view is a similarity: a
/// content point `p` lands on screen at `(p - center) * zoom + canvasCenter`, so
/// `center` is the content point the middle of the canvas is looking at and
/// `zoom` is how many screen pixels one content unit covers.
struct View2D {
    var center: Vector2 = .zero
    var zoom: Double = 1
    /// The opening framing is applied once. After that the viewer owns the view,
    /// so passing the same arguments every frame does not fight the dragging.
    var seeded = false
    /// Where the pointer was on the previous frame while a drag was running.
    var dragFrom: Vector2?

    /// How much one unit of scroll multiplies the zoom by. The 3D dolly uses the
    /// same shape at 0.97 per unit, so a scroll feels the same in both.
    static let zoomPerScrollUnit = 1.0 / 0.97

    mutating func seed(center: Vector2, zoom: Double) {
        guard !seeded else { return }
        seeded = true
        self.center = center
        self.zoom = zoom
    }

    /// Where `content` lands on a canvas of `canvasCenter`.
    func screenPoint(_ content: Vector2, canvasCenter: Vector2) -> Vector2 {
        (content - center) * zoom + canvasCenter
    }

    /// Which content point `screen` is over. The inverse of `screenPoint`.
    func contentPoint(_ screen: Vector2, canvasCenter: Vector2) -> Vector2 {
        guard zoom != 0 else { return center }
        return (screen - canvasCenter) / zoom + center
    }

    /// Take one frame of pointer and scroll input.
    ///
    /// Zoom is anchored on the pointer, so the content under it does not move
    /// while the view grows around it, and a drag moves the content exactly as
    /// far as the pointer went. Neither is damped, on purpose: an orbit gains
    /// from a little inertia, and a flat plane under a finger does not.
    mutating func update(pointer: Vector2, dragging: Bool, scroll: Double,
                         canvasCenter: Vector2, range: ClosedRange<Double>) {
        if scroll != 0 {
            let anchored = contentPoint(pointer, canvasCenter: canvasCenter)
            let wanted = zoom * pow(View2D.zoomPerScrollUnit, scroll)
            zoom = Swift.min(Swift.max(wanted, range.lowerBound), range.upperBound)
            center = anchored - (pointer - canvasCenter) / zoom
        }
        if dragging {
            if let from = dragFrom, zoom != 0 { center -= (pointer - from) / zoom }
            dragFrom = pointer
        } else {
            dragFrom = nil
        }
    }
}
