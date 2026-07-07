/// The receiving end of an audio source's tap: called with each block of
/// decoded audio as the source plays it, on the source's audio thread, not the
/// main thread. `samples` is mono PCM in `-1...1` (channels averaged down),
/// valid only for the duration of the call; `sampleRate` is in Hz. A consumer
/// hands the samples across to wherever it does its work; it must not touch
/// main-thread state directly.
public typealias AudioTap = @Sendable (_ samples: UnsafeBufferPointer<Float>, _ sampleRate: Double) -> Void

/// A producer of sound a consumer can tap: a playing video's soundtrack, or
/// any future sound-carrying feed. The audio sibling of `FrameSource`, and the
/// seam that lets audio *analysis* run over any source of sound without
/// knowing which one it is.
///
/// A source keeps playing its audio regardless of the tap; the tap is a side
/// feed. Installing a consumer is setting `audioTap`; setting it again
/// replaces the previous consumer, and `nil` removes it. One tap per source;
/// a consumer that needs to fan out owns the slot.
@MainActor
public protocol AudioTapSource: AnyObject {
    /// The installed audio consumer, or `nil` when nothing is tapping this
    /// source. Called on the source's audio thread with each block of samples.
    var audioTap: AudioTap? { get set }
}
