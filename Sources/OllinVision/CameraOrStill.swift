import Foundation
import Ollin

public extension Camera {

    /// A running camera when this machine has one, and a still picture when it
    /// does not, so a sketch that reads the world still has something to read
    /// when the world is not plugged in.
    ///
    /// The trackers, `drawFrame`, and everything else that takes a feed accept
    /// either, so the choice is made once and nothing downstream knows which it
    /// got:
    ///
    /// ```swift
    /// var feed: (any FrameSource & VideoFeed)?
    /// var bodies: BodyTracker?
    ///
    /// override func setup() {
    ///     let feed = Camera.orStill(SamplePhoto.reaching.load())
    ///     self.feed = feed
    ///     bodies = BodyTracker(feed)
    /// }
    /// ```
    ///
    /// Pass `--photo` on launch to take the picture even where a camera would
    /// have worked. That is how a still is made of a sketch that is normally
    /// live: a screenshot, a gallery thumbnail, a figure in the Guide.
    ///
    /// `picture` is only built when it is needed, so a machine with a camera
    /// never decodes it.
    static func orStill(_ picture: @autoclosure () -> Image,
                        rate: Double = 4) -> any FrameSource & VideoFeed {
        if !CommandLine.arguments.contains("--photo") {
            let camera = Camera()
            if (try? camera.start()) != nil, camera.isRunning { return camera }
        }
        let still = StillFrames(picture(), rate: rate)
        still.start()
        return still
    }
}
