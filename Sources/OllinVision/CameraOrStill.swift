import AVFoundation
import Foundation
import Ollin
import os

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
    /// On a machine where the camera has never been asked for, the system's
    /// prompt goes up when the window first reads the feed. The picture stands
    /// in while the prompt is up, and the camera takes over at its first frame
    /// with nothing relaunched. A run with no window (an export) never asks,
    /// and draws the picture throughout.
    ///
    /// A refusal, at the prompt or from an earlier run, leaves the picture and
    /// writes one line to stderr saying so and where to allow the camera. The
    /// canvas shows nothing of it.
    ///
    /// `picture` is only built when it is needed, so a machine with a camera
    /// it may use never decodes it.
    static func orStill(_ picture: @autoclosure () -> Image,
                        rate: Double = 4) -> any FrameSource & VideoFeed {
        if !photoOnly {
            let camera = Camera()
            if authorizationStatus() == .notDetermined {
                // Never asked. The prompt stays up for as long as the person
                // takes to answer it, so this hands back one feed that is the
                // picture until the camera's first frame and the camera after.
                let still = StillFrames(picture(), rate: rate)
                still.start()
                return StandInFeed(camera, standIn: still, begin: { _ = try? camera.start() },
                                   whyNot: { camera.whyThePicture }, note: note)
            }
            if (try? camera.start()) != nil, camera.isRunning { return camera }
            // Refused before this run. The sketch gets its picture and has no
            // property to read the reason from, so the developer is told.
            if let line = camera.whyThePicture { note(line) }
        }
        let still = StillFrames(picture(), rate: rate)
        still.start()
        return still
    }
}

extension Camera {
    /// The line for the developer when a sketch that asked for the camera
    /// through `orStill` is showing its picture because the camera said no,
    /// or `nil` while nothing has gone wrong.
    var whyThePicture: String? {
        guard let reason = unavailableReason else { return nil }
        guard isRefused else {
            return "the camera could not start (\(reason)), so the sketch shows its picture instead."
        }
        return "\(reason), so the sketch shows its picture instead. To use the camera, allow the app that launched the sketch (the terminal, under swift run) in System Settings > Privacy & Security > Camera, then relaunch."
    }
}

/// A feed that is not delivering yet, with a still picture standing in until
/// it does. `Camera.orStill` hands one back on a machine where the camera has
/// never been asked for: the sketch draws the picture while the system's
/// prompt is up, and the camera takes over at its first frame.
///
/// It is one object from the first frame to the last, because a tracker finds
/// its analyzer by the identity of the source it was given. Whatever taps this
/// feed is handed the picture until the live feed delivers and the live
/// frames from then on, never both: the two taps share one lock, so no
/// picture is handed over after a live frame has been.
///
/// The live feed is asked to begin the first time a window reads this one,
/// and never while a run with no window drives the sketch: an export has
/// nobody there to answer a prompt.
@MainActor
final class StandInFeed: FrameSource, VideoFeed {

    /// The feed being waited for.
    let live: any FrameSource & VideoFeed
    /// The picture in its place, let go once the live feed has a frame.
    private(set) var standIn: StillFrames?
    /// Starts the live feed; run once, then dropped.
    private var begin: (() -> Void)?
    /// The line for the developer once the live feed has said it will not
    /// come, `nil` until then; asked each frame until it answers, then dropped.
    private var whyNot: (() -> String?)?
    private let note: (String) -> Void
    /// Whether the live feed has delivered, shared by the two taps.
    private let delivered = OSAllocatedUnfairLock(initialState: false)

    init(_ live: any FrameSource & VideoFeed, standIn: StillFrames, begin: @escaping () -> Void,
         whyNot: (() -> String?)? = nil, note: @escaping (String) -> Void = { _ in }) {
        self.live = live
        self.standIn = standIn
        self.begin = begin
        self.whyNot = whyNot
        self.note = note
    }

    /// The analysis tap (`FrameSource`), handed to both feeds: the picture's
    /// side stops forwarding at the live feed's first frame.
    var frameTap: FrameTap? {
        didSet {
            beginInAWindow()
            settle()
            guard let tap = frameTap else {
                live.frameTap = nil
                standIn?.frameTap = nil
                return
            }
            live.frameTap = liveTap(tap, delivered)
            standIn?.frameTap = standInTap(tap, delivered)
        }
    }

    /// The live feed's frame once it has one, and the picture until then
    /// (`VideoFeed`). Never `nil` while the picture stands in.
    var frame: Image? {
        beginInAWindow()
        settle()
        if let line = whyNot?() {
            whyNot = nil
            note(line)
        }
        if let standIn { return standIn.frame }
        return live.frame
    }

    /// The size of whichever feed `frame` last settled on. It does not settle
    /// by itself, so the size and the picture agree within a frame when
    /// `frame` is read first, which is the order `drawFrame` reads them in.
    var frameSize: Vector2? {
        if let standIn { return standIn.frameSize }
        return live.frameSize
    }

    var waitingMessage: String { live.waitingMessage }

    /// Ask the live feed to begin, once, and only where a window is drawing.
    private func beginInAWindow() {
        guard let begin, !OllinApp.isRenderingHeadless else { return }
        self.begin = nil
        begin()
    }

    /// Hand over to the live feed once it has a frame to show.
    private func settle() {
        guard let still = standIn, live.frame != nil else { return }
        delivered.withLock { $0 = true }
        still.frameTap = nil
        standIn = nil
    }
}

/// The picture follows an export's clock the way it does on its own.
extension StandInFeed: @MainActor FrameAdvancing {
    func advance(by dt: Double) { standIn?.advance(by: dt) }
}

// Both taps are formed in free functions, never inside the main-actor class,
// so they carry no actor isolation: a capture queue and the picture's own
// thread call them.

private func liveTap(_ tap: @escaping FrameTap, _ delivered: OSAllocatedUnfairLock<Bool>) -> FrameTap {
    { image in
        delivered.withLock { $0 = true }
        tap(image)
    }
}

private func standInTap(_ tap: @escaping FrameTap, _ delivered: OSAllocatedUnfairLock<Bool>) -> FrameTap {
    { image in
        // Forwarded inside the lock, so the live feed's first frame either
        // waits for this hand-off or stops it, and no picture arrives after.
        delivered.withLockUnchecked { arrived in
            if !arrived { tap(image) }
        }
    }
}
