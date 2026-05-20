import Foundation
import CoreGraphics

/// Base class for an Ollin sketch.
///
/// Subclass it, override `setup()` (once) and `draw()` (every frame), and call
/// the bare drawing functions (`background`, `stroke`, `circle`, …) just like
/// you would in p5.js or Processing:
///
/// ```swift
/// final class HelloCircle: Sketch {
///     override func draw() {
///         background(.white)
///         noFill()
///         stroke(.black)
///         strokeWeight(3)
///         circle(x: width / 2, y: height / 2, radius: 120)
///     }
/// }
/// ```
///
/// **Motion is the default.** `draw()` is called continuously at the display's
/// refresh rate — you don't opt in to animation. Useful temporal state is ready
/// to use without any setup: `frameCount`, `time`, `deltaTime`, `frameRate`.
/// Swap `radius: 120` for `radius: 120 + sin(time) * 40` and it just animates.
/// Use `noLoop()` for the rare still-image case.
open class Sketch {

    // MARK: Canvas size (logical points)

    /// Current canvas width in points. Updates live on window resize.
    public internal(set) var width: Double = 0
    /// Current canvas height in points. Updates live on window resize.
    public internal(set) var height: Double = 0

    // MARK: Temporal state (motion is first-class)

    /// Number of frames drawn so far (1 during the first `draw()`).
    public internal(set) var frameCount: Int = 0
    /// Seconds elapsed since the sketch started.
    public internal(set) var time: Double = 0
    /// Seconds elapsed since the previous frame.
    public internal(set) var deltaTime: Double = 0
    /// Smoothed frames-per-second estimate.
    public internal(set) var frameRate: Double = 0

    // MARK: Configuration (override in subclasses)

    /// Window title used when booting via `OllinApp.run`.
    open var title: String { "Ollin" }
    /// Initial window size used when booting via `OllinApp.run`.
    open var preferredSize: CGSize { CGSize(width: 800, height: 800) }

    // MARK: Lifecycle (override in subclasses)

    /// Called once, after the canvas size is known, before the first `draw()`.
    open func setup() {}
    /// Called every frame. Do your drawing here.
    open func draw() {}

    // MARK: Loop control

    /// Whether the draw loop is currently running.
    public internal(set) var isLooping = true

    /// Stop the continuous draw loop (still-image escape hatch).
    public func noLoop() { setLooping(false) }
    /// Resume the continuous draw loop.
    public func loop() { setLooping(true) }

    // MARK: - Internals

    /// The state machine + per-frame geometry recorder the bare API forwards to.
    let drawer = Drawer()

    /// Set by the runner so `loop()`/`noLoop()` can pause/resume the MTKView.
    var loopStateDidChange: ((Bool) -> Void)?

    public init() {}

    private func setLooping(_ value: Bool) {
        guard isLooping != value else { return }
        isLooping = value
        loopStateDidChange?(value)
    }

    // MARK: Bare drawing API (forwards to the Drawer)

    public func background(_ color: Color) { drawer.background(color) }
    public func fill(_ color: Color) { drawer.fill(color) }
    public func noFill() { drawer.noFill() }
    public func stroke(_ color: Color) { drawer.stroke(color) }
    public func noStroke() { drawer.noStroke() }
    public func strokeWeight(_ weight: Double) { drawer.strokeWeight(weight) }
    public func circle(x: Double, y: Double, radius: Double) {
        drawer.circle(x: x, y: y, radius: radius)
    }

    // MARK: Runner plumbing (called by SketchRunner)

    func setCanvasSize(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    func advance(time: Double, deltaTime: Double, frameRate: Double) {
        frameCount += 1
        self.time = time
        self.deltaTime = deltaTime
        self.frameRate = frameRate
    }

    func performDraw() {
        drawer.beginFrame()
        draw()
    }
}
