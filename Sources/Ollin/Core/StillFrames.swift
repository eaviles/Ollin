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
            tapStore.withLock { $0 = tap }
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

    private let tapStore = OSAllocatedUnfairLock<FrameTap?>(initialState: nil)
    private let cgImage: SendableFrame
    private var isPublishing = false

    /// Publish `picture`, `rate` times a second once `start()` is called.
    public init(_ picture: Image, rate: Double = 4) {
        self.picture = picture
        self.rate = max(0.5, rate)
        self.cgImage = SendableFrame(picture.currentCGImage())
    }

    /// Begin publishing the picture to whatever has tapped this feed. Calling it
    /// again does nothing. There is no stop: a still feed holds one picture and
    /// a thread that sleeps between frames.
    public func start() {
        guard !isPublishing else { return }
        isPublishing = true
        let store = tapStore
        let frame = cgImage
        let interval = 1.0 / rate
        let thread = Thread {
            while true {
                let next = Date(timeIntervalSinceNow: interval)
                store.withLock { $0 }?(frame.cgImage)
                Thread.sleep(until: next)
            }
        }
        thread.name = "co.eavl.ollin.stillframes"
        thread.stackSize = 1 << 20
        thread.start()
    }
}

/// A frame crossing threads; the `CGImage` is immutable once made, the same
/// promise `FrameBox` makes on the camera's own path.
private struct SendableFrame: @unchecked Sendable {
    let cgImage: CGImage
    init(_ cgImage: CGImage) { self.cgImage = cgImage }
}
