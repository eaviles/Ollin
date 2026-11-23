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
        or(shown: "its picture") {
            let still = StillFrames(picture(), rate: rate)
            still.start()
            return still
        }
    }

    /// A running camera when this machine has one, and a feed of your own
    /// when it does not: a film, a screen, a feed the sketch draws itself.
    /// The same choice `orStill` makes, with anything that is both a
    /// `FrameSource` and a `VideoFeed` standing in.
    ///
    /// ```swift
    /// let feed = Camera.or {
    ///     let film = try! VideoPlayer(path: "dance.mp4")
    ///     film.loops = true
    ///     film.isMuted = true
    ///     film.play()
    ///     return film
    /// }
    /// lazy var flow = FlowTracker(feed)
    /// ```
    ///
    /// The closure builds the stand-in and sets it going, and it runs only
    /// when the stand-in is needed, so a machine with a camera it may use
    /// never opens the film. Build it there rather than holding it in a
    /// property of the sketch as well: the feed handed back is what follows
    /// an export's clock, and a stand-in the sketch also holds is stepped
    /// twice a frame.
    ///
    /// Everything `orStill` says of its picture holds for the stand-in:
    /// `--photo` takes it where a camera would have worked; on a machine never
    /// asked it plays while the system's prompt is up and the camera takes
    /// over at its first frame, at which point the stand-in is let go; a run
    /// with no window never asks; and a refusal leaves it playing with one
    /// line on stderr.
    ///
    /// `isLive` on the feed handed back says which of the two a frame is
    /// reading: `false` while the stand-in plays and `true` once the camera
    /// has a frame, so a sketch that treats footage and the room differently
    /// asks each frame rather than once.
    static func or(_ standIn: () -> any FrameSource & VideoFeed) -> any FrameSource & VideoFeed {
        or(shown: "its stand-in", standIn)
    }

    /// The choice both doors make. `shown` names what the sketch is left
    /// showing, for the line a refusal writes.
    private static func or(shown: String,
                           _ standIn: () -> any FrameSource & VideoFeed) -> any FrameSource & VideoFeed {
        if !photoOnly {
            let camera = Camera()
            if authorizationStatus() == .notDetermined {
                // Never asked. The prompt stays up for as long as the person
                // takes to answer it, so this hands back one feed that is the
                // stand-in until the camera's first frame and the camera after.
                return StandInFeed(camera, standIn: standIn(), begin: { _ = try? camera.start() },
                                   whyNot: { camera.whyNot(shown: shown) }, note: note)
            }
            if (try? camera.start()) != nil, camera.isRunning { return camera }
            // Refused before this run. The sketch gets its stand-in and has no
            // property to read the reason from, so the developer is told.
            if let line = camera.whyNot(shown: shown) { note(line) }
        }
        return standIn()
    }
}

extension Camera {
    /// The line for the developer when a sketch that asked for the camera
    /// through `orStill` or `or` is showing its stand-in because the camera
    /// said no, or `nil` while nothing has gone wrong. `shown` names the
    /// stand-in ("its picture").
    func whyNot(shown: String) -> String? {
        guard let reason = unavailableReason else { return nil }
        guard isRefused else {
            return "the camera could not start (\(reason)), so the sketch shows \(shown) instead."
        }
        return "\(reason), so the sketch shows \(shown) instead. To use the camera, allow the app that launched the sketch (the terminal, under swift run) in System Settings > Privacy & Security > Camera, then relaunch."
    }
}

/// A feed that is not delivering yet, with another standing in until it does:
/// a still picture, a film, any feed. `Camera.orStill` and `Camera.or` hand
/// one back on a machine where the camera has never been asked for: the
/// sketch draws the stand-in while the system's prompt is up, and the camera
/// takes over at its first frame.
///
/// It is one object from the first frame to the last, because a tracker finds
/// its analyzer by the identity of the source it was given. Whatever taps this
/// feed is handed the stand-in's frames until the live feed delivers and the
/// live frames from then on, never both: the two taps share one lock, so no
/// stand-in frame is handed over after a live frame has been.
///
/// The live feed is asked to begin the first time a window reads this one,
/// and never while a run with no window drives the sketch: an export has
/// nobody there to answer a prompt.
@MainActor
final class StandInFeed: FrameSource, VideoFeed {

    /// The feed being waited for.
    let live: any FrameSource & VideoFeed
    /// The feed in its place, let go once the live feed has a frame.
    private(set) var standIn: (any FrameSource & VideoFeed)?
    /// Starts the live feed; run once, then dropped.
    private var begin: (() -> Void)?
    /// The line for the developer once the live feed has said it will not
    /// come, `nil` until then; asked each frame until it answers, then dropped.
    private var whyNot: (() -> String?)?
    private let note: (String) -> Void
    /// Whether the live feed has delivered, shared by the two taps.
    private let delivered = OSAllocatedUnfairLock(initialState: false)

    init(_ live: any FrameSource & VideoFeed, standIn: any FrameSource & VideoFeed, begin: @escaping () -> Void,
         whyNot: (() -> String?)? = nil, note: @escaping (String) -> Void = { _ in }) {
        self.live = live
        self.standIn = standIn
        self.begin = begin
        self.whyNot = whyNot
        self.note = note
    }

    /// The analysis tap (`FrameSource`), handed to both feeds: the stand-in's
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

    /// The live feed's frame once it has one, and the stand-in's until then
    /// (`VideoFeed`).
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

    /// The stand-in's notice while it has no frame of its own yet (a film
    /// still opening), and the live feed's after the hand-over.
    var waitingMessage: String { (standIn ?? live).waitingMessage }

    /// Which of the two a frame is reading: the stand-in's answer until the
    /// live feed has delivered, and the live feed's from then on.
    var isLive: Bool { (standIn ?? live).isLive }

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

/// The stand-in follows an export's clock the way it does on its own.
extension StandInFeed: @MainActor FrameAdvancing {
    func advance(by dt: Double) { (standIn as? any FrameAdvancing)?.advance(by: dt) }
    func advance(to time: Double) { (standIn as? any FrameAdvancing)?.advance(to: time) }
}

// Both taps are formed in free functions, never inside the main-actor class,
// so they carry no actor isolation: a capture queue and the stand-in's own
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
        // waits for this hand-off or stops it, and no stand-in frame arrives
        // after.
        delivered.withLockUnchecked { arrived in
            if !arrived { tap(image) }
        }
    }
}
