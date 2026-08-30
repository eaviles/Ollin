import Ollin
import CoreGraphics

/// Bridges the coordinate space results come back in to the one a sketch draws
/// in.
///
/// The recognizers report geometry in **normalized** coordinates: every point is
/// `0…1` across the frame, with the origin at the **lower-left** and y pointing
/// up. Ollin's canvas is the opposite — **pixels**, origin at the **top-left**,
/// y pointing down — so a point has to be flipped in y and scaled to wherever the
/// frame was drawn.
///
/// ```
///   normalized (what Vision returns)        canvas (what you draw in)
///   (0,1) ───────────── (1,1)               (0,0) ───────────── (w,0)
///     │                   │                    │                   │
///     │        · (x,y)    │        ──▶         │                   │
///     │                   │                    │        · maps to  │
///   (0,0) ───────────── (1,0)               (0,h) ───────────── (w,h)
///       y up, lower-left                        y down, top-left
/// ```
///
/// You don't usually call this directly — the result types do it for you
/// (`face.bounds(in:)`, `face.landmarks(_:in:)`). It's public for mapping points
/// from a source the built-in trackers don't cover (say, a custom Core ML model).
/// Always map into the **same rectangle you drew the frame into**, so the overlay
/// lines up with the picture.
public enum VisionSpace {

    /// Map a normalized point (`0…1`, lower-left origin) into `rect` (canvas
    /// space). Set `mirrored` when the frame is drawn flipped left-to-right, the
    /// natural "selfie" orientation for a front camera.
    public static func point(_ x: Double, _ y: Double, in rect: Rectangle,
                             mirrored: Bool = false) -> Vector2 {
        let nx = mirrored ? 1 - x : x
        let ny = 1 - y                       // lower-left origin → top-left
        return Vector2(rect.x + nx * rect.width, rect.y + ny * rect.height)
    }

    /// Map a normalized point value into `rect`.
    public static func point(_ p: Vector2, in rect: Rectangle,
                             mirrored: Bool = false) -> Vector2 {
        point(p.x, p.y, in: rect, mirrored: mirrored)
    }

    /// Map a normalized rectangle (lower-left origin) into `rect`. Mapping two
    /// opposite corners and taking their extent keeps the result correct whether
    /// or not it's mirrored.
    public static func rectangle(_ normalized: Rectangle, in rect: Rectangle,
                                 mirrored: Bool = false) -> Rectangle {
        let a = point(normalized.x, normalized.y, in: rect, mirrored: mirrored)
        let b = point(normalized.x + normalized.width, normalized.y + normalized.height,
                      in: rect, mirrored: mirrored)
        return Rectangle(x: min(a.x, b.x), y: min(a.y, b.y),
                         width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The inverse of `point(_:in:mirrored:)`: take a point you drew (canvas
    /// space, inside `rect`) back to normalized coordinates (`0…1`, lower-left
    /// origin) — what a tracker wants when you seed it from where something is on
    /// the canvas. Pass the **same rect** you drew the frame into.
    public static func normalizedPoint(_ canvasPoint: Vector2, in rect: Rectangle,
                                       mirrored: Bool = false) -> Vector2 {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        let u = (canvasPoint.x - rect.x) / rect.width   // 0…1 left→right
        let v = (canvasPoint.y - rect.y) / rect.height  // 0…1 top→bottom
        return Vector2(mirrored ? 1 - u : u, 1 - v)     // top-left → lower-left
    }

    /// The inverse of `rectangle(_:in:mirrored:)`: take a canvas rectangle back to
    /// normalized coordinates (lower-left origin). Mapping two opposite corners and
    /// taking their extent keeps it correct whether or not it's mirrored — handy to
    /// seed an `ObjectTracker` from a box you drew (or from another detection's
    /// `bounds(in:)`).
    public static func normalizedRectangle(_ canvasRect: Rectangle, in rect: Rectangle,
                                           mirrored: Bool = false) -> Rectangle {
        let a = normalizedPoint(canvasRect.corner, in: rect, mirrored: mirrored)
        let b = normalizedPoint(Vector2(canvasRect.x + canvasRect.width,
                                        canvasRect.y + canvasRect.height),
                                in: rect, mirrored: mirrored)
        return Rectangle(x: min(a.x, b.x), y: min(a.y, b.y),
                         width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The largest rectangle of `imageSize`'s aspect ratio centered inside
    /// `container` — the letterboxed box to draw a frame into (and map results
    /// into) when you don't want it stretched. Returns `container` unchanged for a
    /// degenerate size.
    public static func fittedRectangle(imageSize: Vector2, in container: Rectangle) -> Rectangle {
        Rectangle(fitting: imageSize, in: container)
    }
}
