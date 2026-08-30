/// A live picture a sketch can draw — the camera, a playing video, an incoming
/// frame share. Where `FrameSource` is the *analysis* seam (a CPU tap the vision
/// trackers consume), `VideoFeed` is the *display* seam: the latest frame as a
/// drawable `Image`, plus the frame size that letterboxes it.
///
/// Conformers publish `nil` from `frame` until the feed is actually producing
/// pictures (permission pending, file still opening, nothing connected yet);
/// `Sketch.drawFrame(_:)` turns that state into a standard on-canvas notice.
@MainActor
public protocol VideoFeed: AnyObject {
    /// The latest frame as a drawable `Image`, or `nil` before the first one
    /// arrives.
    var frame: Image? { get }

    /// The pixel dimensions of the feed's frames, or `nil` before they're known.
    var frameSize: Vector2? { get }

    /// The standard notice `drawFrame` shows before the first frame. Conformers
    /// override it to name themselves ("Waiting for camera…"); the default is
    /// "Waiting for video…".
    var waitingMessage: String { get }
}

extension VideoFeed {
    public var waitingMessage: String { "Waiting for video…" }

    /// The letterboxed rectangle that fits this feed's frame inside `container`
    /// without stretching — draw the frame into it and map any analysis results
    /// into the *same* rectangle so overlays line up with the picture. `nil`
    /// until the frame size is known.
    public func fittedRectangle(in container: Rectangle) -> Rectangle? {
        frameSize.map { Rectangle(fitting: $0, in: container) }
    }
}

extension Sketch {
    /// Draw the latest frame from `feed`, letterboxed into `container` (the whole
    /// canvas by default), and return the rectangle it landed in — map tracker
    /// results into the same rectangle so overlays glue to the picture. Before
    /// the first frame arrives it draws the feed's standard waiting notice
    /// instead (pass `waiting:` to change the message) and returns `nil`, so a
    /// feed-driven sketch opens with one line:
    ///
    /// ```swift
    /// guard let rect = drawFrame(camera) else { return }
    /// ```
    ///
    /// To draw your own waiting state (or the frame in a non-fitted rectangle),
    /// use the typed surface directly: `feed.frame` and `feed.fittedRectangle(in:)`.
    @discardableResult
    public func drawFrame(_ feed: some VideoFeed, in container: Rectangle? = nil,
                          waiting: String? = nil) -> Rectangle? {
        let box = container ?? bounds
        guard let frame = feed.frame else {
            drawStatus(waiting ?? feed.waitingMessage, in: box)
            return nil
        }
        let rect = feed.fittedRectangle(in: box) ?? box
        drawImage(frame, in: rect)
        return rect
    }
}
