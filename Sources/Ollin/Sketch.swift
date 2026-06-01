import Foundation
import CoreGraphics

/// How a sketch's preview window behaves and is sized, relative to its
/// `canvasSize`. `.auto` and `.fixed` are fixed-size (export-first): the window
/// is locked and the canvas matches it. `.resizable` is screen-first: the window
/// is freely resizable and the canvas follows it.
public enum WindowMode: Sendable {
    /// Shrink `canvasSize` by the largest clean fraction (1, ¾, ½, …) that fits the
    /// screen: 1:1 on a roomy display, smaller on a laptop. Not resizable. The default.
    case auto
    /// A fixed fraction of `canvasSize` (1 = actual size, 0.5 = half), regardless of
    /// the screen. Not resizable. Use for a specific preview zoom.
    case fixed(Double)
    /// A freely resizable window; the canvas follows the window size live (drive it
    /// with `scale` / `width` / `height`). Opens at the auto-fit size. For sketches
    /// designed for the screen rather than a fixed export.
    case resizable
}

/// Base class for an Ollin sketch.
///
/// Subclass it, override `setup()` (once) and `draw()` (every frame), and call
/// the bare drawing functions (`background`, `stroke`, `circle`, …):
///
/// ```swift
/// final class HelloCircle: Sketch {
///     override func draw() {
///         background(.white)
///         noFill()
///         stroke(.black)
///         strokeWeight(3)
///         drawCircle(width / 2, height / 2, 120)
///     }
/// }
/// ```
///
/// **Motion is the default.** `draw()` is called continuously at the display's
/// refresh rate — you don't opt in to animation. Useful temporal state is ready
/// to use without any setup: `frameCount`, `time`, `deltaTime`, `frameRate`.
/// Swap `radius: 120` for `radius: 120 + sin(time) * 40` and it just animates.
/// Use `noLoop()` for the rare still-image case.
///
/// Main-actor isolated: `setup()`/`draw()`/`mousePressed()` run on the main
/// thread (the display-driven draw callback), so subclasses' overrides are
/// main-actor too — which is what a sketch wants anyway.
@MainActor
open class Sketch {

    // MARK: Canvas size (logical points)

    /// Current canvas width in points. Updates live on window resize.
    public internal(set) var width: Double = 0
    /// Current canvas height in points. Updates live on window resize.
    public internal(set) var height: Double = 0

    /// A resolution-relative scale factor, `min(width, height) / 1000`. Multiply
    /// sizes by it so a sketch authored against a ~1000pt reference keeps its
    /// proportions at any canvas size (and scales up cleanly for hi-res export).
    public var scale: Double { Swift.min(width, height) / 1000 }

    // MARK: Temporal state (motion is first-class)

    /// Number of frames drawn so far (1 during the first `draw()`).
    public internal(set) var frameCount: Int = 0
    /// Seconds elapsed since the sketch started.
    public internal(set) var time: Double = 0
    /// Seconds elapsed since the previous frame.
    public internal(set) var deltaTime: Double = 0
    /// Smoothed frames-per-second estimate.
    public internal(set) var frameRate: Double = 0

    // MARK: Pointer (input)

    /// Cursor x in sketch coordinates (points, top-left origin). Seeded from the
    /// cursor's actual position when the sketch opens, then updated as the
    /// pointer moves over the canvas.
    public internal(set) var mouseX: Double = 0
    /// Cursor y in sketch coordinates (points, top-left origin, y-down).
    public internal(set) var mouseY: Double = 0

    // MARK: Configuration (override in subclasses)

    /// Window title used when booting via `OllinApp.run`. Defaults to
    /// `"Ollin - <SketchType>"` (e.g. "Ollin - HelloCircle") so the window names
    /// the running sketch; override for a custom title.
    open var title: String {
        let typeName = String(describing: type(of: self))
        return typeName == "Sketch" ? "Ollin" : "Ollin - \(typeName)"
    }
    /// The default export resolution: 1080×1080 — a 1:1 square at the 1080-pixel
    /// target common to square social/video export. The on-screen preview window
    /// scales down from this to fit the screen (the *host* computes that, not the
    /// sketch — see `OllinApp.windowSize(fitting:)`).
    public static let defaultSize = CGSize.square1080

    /// The render / single-frame PNG export size in pixels — the canonical
    /// resolution the sketch is authored at. Defaults to `Sketch.defaultSize`
    /// (1080² / square). **Override it** for higher-res masters at the standard
    /// square tiers — 1440² ("2K"), 2160² ("4K"), 2880² ("5K") — or a non-square
    /// aspect (e.g. 1080×1350 for a 4:5 portrait).
    open var canvasSize: CGSize { Sketch.defaultSize }

    /// How the preview window is sized, relative to `canvasSize`. Defaults to
    /// `.auto`: it opens at 1:1 when the screen has room for the full `canvasSize`
    /// and steps down to fit otherwise, so it always fits. Override with `.fixed(_)`
    /// to pin a preview zoom. The window is never user-resizable. The screen-fit
    /// itself lives in the host, so this stays pure data with no screen dependency.
    open var windowMode: WindowMode { .auto }

    // MARK: Lifecycle (override in subclasses)

    /// Called once, after the canvas size is known, before the first `draw()`.
    open func setup() {}
    /// Called every frame. Do your drawing here.
    open func draw() {}
    /// Called once each time a mouse button is pressed over the canvas. Override
    /// to respond to clicks; `mouseX`/`mouseY` hold the press location.
    open func mousePressed() {}
    /// Called once after this sketch is hot-swapped in by the live-reload host,
    /// right after its `setup()`. Override to do reload-specific work (the
    /// default does nothing). Not called on the first launch — only on reloads.
    open func onReload() {}

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

    /// Backing generator for `random()` / `randomSeed(_:)` (see Random.swift).
    /// Entropy-seeded by default, so unseeded sketches vary per run.
    var rng = SplitMix64(seed: .random(in: .min ... .max))

    /// Backing field for `noise()` / `noiseSeed(_:)` (see Noise.swift).
    var perlin = PerlinNoise(seed: .random(in: .min ... .max))

    /// Cached second sample for `randomGaussian()` — the polar method yields two
    /// normals per pass, so the spare is held for the next call (see Random.swift).
    var gaussianSpare: Double?

    /// Set by the runner so `loop()`/`noLoop()` can pause/resume the MTKView.
    var loopStateDidChange: ((Bool) -> Void)?

    /// `required` so `Self()` works in the static `main()` entry point (see
    /// `Sketch.main()`), letting a sketch file be `@main` with no boilerplate.
    public required init() {}

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
    public func pointSize(_ size: Double) { drawer.pointSize(size) }
    public func drawPoint(_ x: Double, _ y: Double) { drawer.drawPoint(x, y) }
    public func drawPoint(_ x: Double, _ y: Double, _ size: Double) { drawer.drawPoint(x, y, size) }
    public func drawPoint(_ p: Vector2) { drawer.drawPoint(p.x, p.y) }
    public func drawPoint(_ p: Vector2, size: Double) { drawer.drawPoint(p.x, p.y, size) }
    public func drawCircle(_ x: Double, _ y: Double, _ radius: Double) {
        drawer.drawCircle(x, y, radius)
    }
    public func drawCircle(center: Vector2, radius: Double) {
        drawer.drawCircle(center.x, center.y, radius)
    }
    public func drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        drawer.drawEllipse(x, y, rx, ry)
    }
    public func drawEllipse(center: Vector2, rx: Double, ry: Double) {
        drawer.drawEllipse(center.x, center.y, rx, ry)
    }
    public func drawArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double,
                        start: Double, stop: Double, mode: ArcMode = .open) {
        drawer.drawArc(x, y, rx, ry, start: start, stop: stop, mode: mode)
    }
    public func drawArc(center: Vector2, rx: Double, ry: Double,
                        start: Double, stop: Double, mode: ArcMode = .open) {
        drawer.drawArc(center.x, center.y, rx, ry, start: start, stop: stop, mode: mode)
    }
    public func drawPolyline(_ points: [Vector2]) { drawer.drawPolyline(points) }
    public func drawPolygon(_ points: [Vector2]) { drawer.drawPolygon(points) }
    public func drawShape(_ shape: Shape) { drawer.drawShape(shape) }
    public func drawRect(_ rectangle: Rectangle, cornerRadius: Double = 0) {
        drawer.drawRect(rectangle, cornerRadius: cornerRadius)
    }
    public func drawRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        drawer.drawRect(Rectangle(x: x, y: y, width: width, height: height), cornerRadius: cornerRadius)
    }
    public func drawRect(corner: Vector2, width: Double, height: Double, cornerRadius: Double = 0) {
        drawer.drawRect(Rectangle(corner: corner, width: width, height: height), cornerRadius: cornerRadius)
    }
    public func drawRect(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0) {
        drawer.drawRect(Rectangle(center: center, width: width, height: height), cornerRadius: cornerRadius)
    }
    public func translate(_ offset: Vector2) { drawer.translate(offset) }
    public func translate(_ x: Double, _ y: Double) { drawer.translate(Vector2(x, y)) }
    public func drawLine(_ a: Vector2, _ b: Vector2) { drawer.drawLine(a, b) }
    public func drawLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        drawer.drawLine(Vector2(x1, y1), Vector2(x2, y2))
    }
    public func rotate(_ radians: Double) { drawer.rotate(radians) }
    public func scale(_ amount: Double) { drawer.scale(amount, amount) }
    public func scale(_ x: Double, _ y: Double) { drawer.scale(x, y) }
    public func pushState() { drawer.pushState() }
    public func popState() { drawer.popState() }

    /// Run `body` with the current transform and style saved, then restored.
    /// Prefer this scoped form over bare `pushState()`/`popState()`.
    public func withState(_ body: () -> Void) {
        drawer.pushState()
        defer { drawer.popState() }
        body()
    }

    // MARK: Runner plumbing (called by SketchRunner)

    func setCanvasSize(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    func setMouse(x: Double, y: Double) {
        mouseX = x
        mouseY = y
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
