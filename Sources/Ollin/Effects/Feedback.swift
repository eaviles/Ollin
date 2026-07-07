import Metal

/// A layer that remembers itself across frames: the substrate of previous-frame
/// feedback. Each frame you read last frame's content (`previous`), transform it
/// (fade, zoom, rotate, offset), and draw new content on top; the result becomes
/// next frame's `previous`. That read-transform-write loop is what makes trails,
/// tunnels, and video-feedback looks, and it's what an off-screen `RenderTarget`
/// can't do alone: a target is a per-frame handle, while a feedback layer keeps a
/// ping-pong pair of textures the renderer carries from one frame to the next.
///
/// ```swift
/// var trail: Feedback!
/// override func setup() { trail = feedback() }   // make once, store it
///
/// override func draw() {
///     background(.black)
///     withFeedback(trail) { prev in              // prev = last frame's content
///         scale(1.01); rotate(0.003)             // zoom + spin the old frame
///         tint(.init(white: 1, alpha: 0.96))     // gentle decay
///         drawImage(prev, 0, 0)
///         noTint()
///         fill(.white); drawCircle(mouseX, mouseY, 12)
///     }
///     drawImage(trail.image, 0, 0)               // composite the result to canvas
/// }
/// ```
///
/// Unlike `renderTarget()` (a per-frame handle), a `Feedback` is **persistent**:
/// create it once in `setup()` and hold it. Its identity is what ties this frame's
/// write to last frame's read: make a fresh one each `draw()` and it never builds
/// up. A reference type, for the same reason `RenderTarget` is: it names GPU
/// resources the renderer fills.
public final class Feedback {

    /// The layer's logical size in canvas points: the size `image`/`previous` draw
    /// at and the coordinate space a `withFeedback` block uses.
    public let width: Int
    public let height: Int

    /// Internal resolution as a fraction of the logical size (1 = full), like
    /// `RenderTarget.scale`: drop it below 1 for a cheaper, softer feedback layer.
    /// Clamped to a sane range.
    public let scale: Double

    /// The drawer that owns the recording, so a `withFeedback` block records against
    /// it. Weak: the drawer outlives per-frame work; the sketch owns the `Feedback`.
    weak var drawer: Drawer?

    /// This frame's write surface: a `RenderTarget` whose `texture` the renderer sets
    /// to the **back** buffer each frame (where the block's geometry lands). Reused
    /// across frames (stable identity), so `image` is a steady handle. Tagged
    /// `.feedback(self)` so the renderer routes it to persistent ping-pong storage.
    let writeLayer: RenderTarget

    /// A read-only texture carrier whose `texture` the renderer sets to the **front**
    /// buffer (last frame's content) each frame. Not drawn into and not in the
    /// drawer's `renderTargets` list; it only resolves `previous` to a sampleable
    /// image. Reused across frames so `previous` is a steady handle.
    let previousLayer: RenderTarget

    /// Pixel dimensions of the backing textures (logical size × `scale`, ≥ 1): the
    /// size the renderer allocates the ping-pong pair at.
    var pixelWidth: Int { max(1, Int((Double(width) * scale).rounded())) }
    var pixelHeight: Int { max(1, Int((Double(height) * scale).rounded())) }

    init(width: Int, height: Int, scale: Double, drawer: Drawer?) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.scale = min(4, max(0.05, scale))
        self.drawer = drawer
        self.writeLayer = RenderTarget(width: self.width, height: self.height,
                                       scale: self.scale, drawer: drawer)
        self.previousLayer = RenderTarget(width: self.width, height: self.height,
                                          scale: self.scale, drawer: drawer)
        // Stamp the write layer now that `self` exists, so the renderer can recover
        // this `Feedback` (and its persistent textures) from the recorded target.
        self.writeLayer.origin = .feedback(self)
    }

    /// Last frame's content, as a drawable/transformable `Image`. The image you read,
    /// fade, and move inside the block; also what `withFeedback` hands in as `prev`.
    /// Resolves the renderer's front texture lazily at draw time.
    public var previous: Image { previousLayer.image }

    /// This frame's written content, as an `Image`, to composite onto the canvas
    /// with `drawImage`. Resolves the renderer's back texture lazily at draw time.
    public var image: Image { writeLayer.image }

    /// This frame's written content through a `Filter`, returning a new layer to
    /// composite: bloom the trails, recolor them through a gradient map, the same
    /// effects substrate every layer uses. The filter reads the written result; the
    /// persistent state the loop carries forward stays untouched.
    public func filtered(_ filter: Filter) -> RenderTarget { writeLayer.filtered(filter) }
}
