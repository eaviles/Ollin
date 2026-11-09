/// Where a publisher of the sketch's frames is in its life: the Syphon server
/// (`SyphonServer.phase`), the virtual camera (`VirtualCameraServer.phase`),
/// the phone's screen (`PhoneScreen.phase`). One vocabulary for the three, so
/// a sketch reads them the same way and a stopped publisher stays stopped.
///
/// A publisher is a `SketchExtension` that asks for each rendered frame, so the
/// only way for `stop()` to hold is for the extension to stop asking: the
/// `wantsRenderedTexture` it answers each frame reads this phase, and a frame
/// that still arrives is refused.
public enum PublisherPhase: Sendable, Equatable {
    /// Started and not yet sending: the first frame has not come, or the
    /// device it feeds is not showing the sketch.
    case waiting
    /// At least one frame has gone out on the current connection.
    case publishing
    /// Cannot publish right now; the publisher's `unavailableReason` says why,
    /// and it keeps trying on its own.
    case unavailable
    /// `stop()` was called. No later frame restarts it; publish again with a
    /// new publisher.
    case stopped
}
