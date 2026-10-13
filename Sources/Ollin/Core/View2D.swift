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
    /// The opening framing is applied once. After that the arguments are the
    /// view's home: a changed one moves the view while the viewer has not taken
    /// it, and passing the same arguments every frame changes nothing, so a
    /// constant framing never fights the dragging.
    var seeded = false
    /// Where the pointer was on the previous frame while a drag was running.
    var dragFrom: Vector2?

    /// The framing the sketch's last call passed: where a changed argument
    /// takes the view, and what the next `resetView()` opens on.
    private(set) var homeCenter: Vector2 = .zero
    private(set) var homeZoom: Double = 1
    /// Whether the view is still the home it was framed at: true from the first
    /// call and after a reset, false once the viewer drags or scrolls. While it
    /// holds, a changed framing glides the view there; after that a changed
    /// framing moves only the home, and the viewer keeps what they took.
    private(set) var restsAtHome = true
    /// Where a changed framing is taking the view, cleared on landing.
    private var goalCenter: Vector2?
    private var goalZoom: Double?

    /// How fast the view follows a changed framing (1/s): under a percent off
    /// in about 0.6 s, the rate the 3D camera's home uses. An exponential
    /// approach rather than an eased glide, because a parameter dragged in the
    /// inspector changes the framing every frame, and an eased glide restarted
    /// every frame never leaves its flat start.
    static let homeGlideRate = 8.0

    /// How much one unit of scroll multiplies the zoom by. The 3D dolly uses the
    /// same shape at 0.97 per unit, so a scroll feels the same in both.
    static let zoomPerScrollUnit = 1.0 / 0.97

    /// Take this frame's framing from the sketch's call. The first call opens
    /// the view on it. After that it is the view's home, and an argument that
    /// changed moves the home there and, while the viewer has not taken the
    /// view, the view itself (gliding, in `update`). Arguments that stay the
    /// same change nothing.
    mutating func frame(center: Vector2, zoom: Double) {
        guard seeded else {
            seeded = true
            self.center = center
            self.zoom = zoom
            homeCenter = center
            homeZoom = zoom
            return
        }
        if center != homeCenter {
            homeCenter = center
            if restsAtHome { goalCenter = center }
        }
        if zoom != homeZoom {
            homeZoom = zoom
            if restsAtHome { goalZoom = zoom }
        }
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

    /// Take one frame of pointer and scroll input, after one step of the glide
    /// a changed framing asked for (`dt` is the frame's step).
    ///
    /// Zoom is anchored on the pointer, so the content under it does not move
    /// while the view grows around it, and a drag moves the content exactly as
    /// far as the pointer went. Neither is damped, on purpose: an orbit gains
    /// from a little inertia, and a flat plane under a finger does not. The
    /// glide toward a changed home is the one eased motion here, and the
    /// viewer's first drag or scroll ends it.
    mutating func update(pointer: Vector2, dragging: Bool, scroll: Double,
                         canvasCenter: Vector2, range: ClosedRange<Double>, dt: Double = 0) {
        if dragging || scroll != 0 {
            restsAtHome = false
            goalCenter = nil
            goalZoom = nil
        }
        let share = 1 - exp(-View2D.homeGlideRate * max(0, dt))
        if let goal = goalZoom {
            zoom += (goal - zoom) * share
            if abs(goal - zoom) <= 1e-9 * Swift.max(1, abs(goal)) { zoom = goal; goalZoom = nil }
        }
        if let goal = goalCenter {
            center = center.lerp(to: goal, share)
            if (goal - center).length <= 1e-9 * Swift.max(1, goal.length) { center = goal; goalCenter = nil }
        }
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
