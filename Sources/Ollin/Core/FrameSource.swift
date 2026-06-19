import CoreGraphics

/// The receiving end of a frame source's tap: called with each new frame as
/// the source produces it, on the source's own background thread or queue —
/// not the main thread. A consumer hands the frame across to wherever it does
/// its work; it must not touch main-thread state directly.
public typealias FrameTap = @Sendable (CGImage) -> Void

/// A producer of CPU image frames a consumer can tap — the live camera, a
/// playing video, or any future feed. The seam that lets frame *analysis*
/// (most notably the vision trackers) run over any source of moving pictures
/// without knowing which one it is.
///
/// A source keeps publishing its frames to its own readers (the camera's
/// `frame`, the video player's GPU textures) regardless of the tap; the tap is
/// a side feed. Installing a consumer is setting `frameTap`; setting it again
/// replaces the previous consumer, and `nil` removes it. One tap per source —
/// a multiplexing consumer (the vision analyzer fanning out to its trackers)
/// owns the slot.
///
/// Conformers deliver frames at their natural cadence (the camera's capture
/// rate, the video's playback rate) and may deliver nothing while idle
/// (permission pending, playback paused).
@MainActor
public protocol FrameSource: AnyObject {
    /// The installed frame consumer, or `nil` when nothing is tapping this
    /// source. Called on the source's own thread with each new frame.
    var frameTap: FrameTap? { get set }
}
