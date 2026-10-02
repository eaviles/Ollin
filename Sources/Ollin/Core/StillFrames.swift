import CoreGraphics
import Foundation
import os

/// A still picture published as a feed, so anything built to read moving
/// pictures can read a photograph instead. It is both a `VideoFeed`, which is
/// what `drawFrame` draws, and a `FrameSource`, which is what a frame analyzer
/// taps, so it stands in wherever a camera or a video player would go.
///
/// The use it was written for is a sketch that would otherwise have nothing to
/// show: no camera attached, or a machine that has one but no permission to use
/// it. Falling back to a bundled photograph gives the sketch a picture to work
/// on, and gives a gallery something to render.
///
/// ```swift
/// let camera = Camera()
/// let sample = StillFrames(SamplePhoto.reaching.load())
/// lazy var feed: any FrameSource & VideoFeed = camera.isRunning ? camera : sample
/// lazy var bodies = BodyTracker(feed)
///
/// override func setup() {
///     do { try camera.start() } catch { sample.start() }
/// }
///
/// override func draw() {
///     guard let rect = drawFrame(feed) else { return }
///     for body in bodies.bodies { … }
/// }
/// ```
///
/// The picture is published over and over rather than once, because an analyzer
/// drops frames it is too busy to take, and a source that published a single
/// frame could have that one frame dropped and never be read at all. A few
/// times a second is far below what a camera asks of the same analyzer.
///
/// During an export the picture is published on the export's clock instead,
/// `rate` times a second of the sketch's `time`, from the thread that drives
/// the export, so a tracker reading it answers on the same frames in every
/// run. That needs the feed stored on the sketch (as a property, optional or
/// not), which is where `drawFrame` reads it from anyway.
@MainActor
public final class StillFrames: FrameSource, VideoFeed {

    /// The picture this feed publishes.
    public let picture: Image

    /// How many times a second the picture is published. Low on purpose: the
    /// picture never changes, so this only has to be often enough that a busy
    /// analyzer takes one of them.
    public let rate: Double

    /// The analysis tap (`FrameSource`). The publishing thread reads it every
    /// time round, so the live value crosses through a locked box.
    public var frameTap: FrameTap? {
        didSet {
            let tap = frameTap
            // Tapped by an exporting sketch (a tracker made in its `setup()`):
            // the export's clock publishes from here on, and the thread falls
            // silent before it can hand the new tap a frame of its own.
            if Thread.isMainThread && OllinApp.isExporting && !followsExport {
                followExportClock(true)
            }
            publishing.withLock { $0.tap = tap }
            // Hand the picture over at once rather than waiting for the next
            // turn of the publishing thread. A still has its frame ready before
            // anything asks, so an analyzer installed later should not have to
            // wait a quarter second to be told what it is looking at.
            tap?(cgImage.cgImage)
        }
    }

    /// The picture, for drawing (`VideoFeed`). Never `nil`, so `drawFrame`
    /// never shows a waiting notice for a still.
    public var frame: Image? { picture }

    /// The picture's pixel dimensions (`VideoFeed`).
    public var frameSize: Vector2? { picture.size }

    /// What the publishing thread reads each time round: the tap, and whether
    /// an export's clock has taken the publishing over.
    private struct Publishing {
        var tap: FrameTap?
        var followsExport = false
    }
    private let publishing = OSAllocatedUnfairLock(initialState: Publishing())
    private let cgImage: SendableFrame
    private var isPublishing = false

    /// The export's clock as this feed has counted it, and how many times
    /// the picture has been published on it.
    private var exportClock = 0.0
    private var exportPublishes = 0
    private var followsExport = false

    /// Publish `picture`, `rate` times a second once `start()` is called.
    public init(_ picture: Image, rate: Double = 4) {
        self.picture = picture
        self.rate = max(0.5, rate)
        self.cgImage = SendableFrame(picture.currentCGImage())
    }

    /// Begin publishing the picture to whatever has tapped this feed. Calling it
    /// again does nothing. There is no stop: a still feed holds one picture and
    /// a thread that sleeps between frames, and the thread ends once the feed
    /// is gone.
    public func start() {
        guard !isPublishing else { return }
        isPublishing = true
        // Started by an exporting sketch's `setup()`: the export's clock
        // publishes from its first frame, and the thread starts silent.
        if Thread.isMainThread && OllinApp.isExporting { followExportClock(true) }
        let store = publishing
        let frame = cgImage
        let interval = 1.0 / rate
        // Weak, so the thread does not keep the feed, or through its tap an
        // analyzer and its trackers, alive once the sketch has let it go.
        let thread = Thread { [weak self] in
            while self != nil {
                let next = Date(timeIntervalSinceNow: interval)
                // The tap is called inside the lock, so an export taking the
                // publishing over either waits for this frame's hand-off or
                // stops it, and never has one arrive after it took over.
                store.withLockUnchecked { state in
                    if !state.followsExport { state.tap?(frame.cgImage) }
                }
                Thread.sleep(until: next)
            }
        }
        thread.name = "co.eavl.ollin.stillframes"
        thread.stackSize = 1 << 20
        thread.start()
    }
}

// MARK: Export clock

/// The per-frame pass that steps `@Eased` and a video's virtual playhead also
/// publishes the picture while an export runs, `rate` times a second of the
/// sketch's clock, starting on the first frame. A held clock (a settle draw)
/// publishes nothing, so the frames an analyzer reads are a function of the
/// clock alone. In a window the pass hands the publishing back to the thread.
extension StillFrames: @MainActor FrameAdvancing {
    package func advance(by dt: Double) {
        guard OllinApp.isExporting else {
            if followsExport { followExportClock(false) }
            return
        }
        if !followsExport { followExportClock(true) }
        // A sum of frame steps falls a hair short of the moment it should
        // reach (fifteen sixtieths add up to just under a quarter), so the
        // moment is reached within a nanosecond rather than past it, or every
        // publish would land a frame late.
        if exportClock >= Double(exportPublishes) / rate - 1e-9 {
            exportPublishes += 1
            publishing.withLock { $0.tap }?(cgImage.cgImage)
        }
        exportClock += dt
    }

    /// Hand the publishing to the export's clock, or back to the thread. The
    /// count starts over each way, so an export that follows a window starts
    /// on its own first frame.
    private func followExportClock(_ follows: Bool) {
        followsExport = follows
        exportClock = 0
        exportPublishes = 0
        publishing.withLock { $0.followsExport = follows }
    }
}

/// A frame crossing threads; the `CGImage` is immutable once made, the same
/// promise `FrameBox` makes on the camera's own path.
private struct SendableFrame: @unchecked Sendable {
    let cgImage: CGImage
    init(_ cgImage: CGImage) { self.cgImage = cgImage }
}
