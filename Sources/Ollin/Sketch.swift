import Foundation
import CoreGraphics
import Metal
import COllinShaders   // OllinParticle (the GPU particle struct, shared with Shaders.metal)

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

    /// The centre of the canvas, `(width / 2, height / 2)`.
    public var center: Vector2 { Vector2(width / 2, height / 2) }

    /// The canvas as a `Rectangle`, `(0, 0, width, height)` — terse for a physics
    /// `World`'s bounds, clamping, or hit-testing.
    public var bounds: Rectangle { Rectangle(x: 0, y: 0, width: width, height: height) }

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
    /// Whether a mouse button is currently held down over the canvas. Poll it
    /// in `draw()` for continuous response while the button is held — dragging,
    /// painting, steering — alongside `mouseX`/`mouseY`, which keep updating
    /// through the drag; the `mousePressed()`/`mouseReleased()` hooks fire once
    /// per press, not continuously.
    public internal(set) var mouseIsPressed = false

    // MARK: Keyboard (input)

    /// The character of the most recent key event — `"a"`, `" "`, `"5"` — or
    /// `nil` for a key with no printing character (an arrow, a function key),
    /// whose identity is in `keyCode` instead. Set on both press and release, so
    /// `keyPressed()`/`keyReleased()` can read which key fired.
    public internal(set) var key: Character?
    /// The named key of the most recent key event for keys that don't produce a
    /// character (`.leftArrow`, `.return`, `.escape`, …), or `nil` when the event
    /// was an ordinary character key (read `key` then).
    public internal(set) var keyCode: KeyCode?
    /// Whether any key is currently held down. Poll it in `draw()` for
    /// continuous response while a key is held (alongside `isKeyDown(_:)` for a
    /// specific key); the `keyPressed()`/`keyReleased()` hooks fire once per
    /// press, not continuously.
    public internal(set) var keyIsPressed = false

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
    public static let defaultSize = CanvasSize.square1080

    /// The render / single-frame PNG export size in pixels — the canonical
    /// resolution the sketch is authored at. Defaults to `Sketch.defaultSize`
    /// (1080² / square). **Override it** with `.square(n)`, an explicit
    /// `.size(width, height)`, or a named preset (`.uhd4K`, `.portrait1080`, …):
    ///
    /// ```swift
    /// override var canvasSize: CanvasSize { .size(1000, 600) }
    /// ```
    open var canvasSize: CanvasSize { Sketch.defaultSize }

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
    /// to respond to clicks; `mouseX`/`mouseY` hold the press location. For
    /// continuous response while the button is held, poll `mouseIsPressed` in
    /// `draw()` instead.
    open func mousePressed() {}
    /// Called once each time a mouse button is released over the canvas;
    /// `mouseX`/`mouseY` hold the release location — the natural moment to act
    /// on a finished drag or stroke.
    open func mouseReleased() {}
    /// Called once each time a key is pressed (auto-repeat doesn't re-fire it).
    /// Override to respond to keys; `key`/`keyCode` hold the key. For movement
    /// while a key is held, poll `isKeyDown(_:)` in `draw()` instead.
    open func keyPressed() {}
    /// Called once each time a key is released; `key`/`keyCode` hold the released
    /// key.
    open func keyReleased() {}
    /// Called once after this sketch is hot-swapped in by the live-reload host,
    /// right after its `setup()`. Override to do reload-specific work (the
    /// default does nothing). Not called on the first launch — only on reloads.
    open func onReload() {}

    // MARK: Extensions (the extend(...) seam)

    /// Register a lifecycle extension. Its hooks fire around each frame (see
    /// `SketchExtension`): before/after your `draw()`, and after the render with
    /// timing. The usual place is `setup()`; registering later runs the
    /// extension's `setup` immediately so it doesn't miss it.
    public func extend(_ ext: SketchExtension) {
        extensions.append(ext)
        if extensionsDidSetup { ext.setup(self) }
    }

    // MARK: Loop control

    /// Whether the draw loop is currently running.
    public internal(set) var isLooping = true

    /// Stop the continuous draw loop (still-image escape hatch).
    public func noLoop() { setLooping(false) }
    /// Resume the continuous draw loop.
    public func loop() { setLooping(true) }

    // MARK: Accumulation

    /// Stop clearing the canvas each frame: from now on drawing piles up on a
    /// persistent surface across frames instead of starting blank. Use it for
    /// progressive refinement, long-exposure stills, and paint-on-canvas sketches;
    /// paired with `blendMode(.add)` it's the basis of light-accumulation
    /// ("sandpainting") rendering, where a frame contributes a haze of faint
    /// samples that sum over time. Call `background(_:)` to wipe the accumulated
    /// canvas (the long-exposure reset), or `clearEachFrame()` to return to the
    /// default of a fresh frame each time. Typically called once in `setup()`.
    public func noClear() { drawer.noClear() }

    /// Return to clearing the canvas every frame (the default), undoing `noClear()`.
    public func clearEachFrame() { drawer.clearEachFrame() }

    // MARK: Tone-mapping

    /// Choose how the frame's high-dynamic-range color is mapped to the screen.
    ///
    /// The canvas composites in linear floating-point, so color can exceed full
    /// brightness — additive light building up on a `noClear` surface, a glow, a
    /// bright gradient. By default (`.clamp`) those values clip to white. Calling
    /// `toneMap()` opts into a curve that rolls highlights off smoothly instead,
    /// the photographic falloff light-accumulation ("sandpainting") and bloom
    /// looks want; `exposure` scales the image first, like a brightness dial — turn
    /// it up to lift faint accumulation into view. It's a frame-wide setting (one
    /// mapping over the finished frame), so it isn't saved by `withState`; set it
    /// once in `setup()`. See `ToneMap`.
    public func toneMap(_ map: ToneMap = .reinhard, exposure: Double = 1) {
        drawer.toneMap(map, exposure: exposure)
    }

    // MARK: Compute & GPU particles

    /// Run a compute `kernel` over `buffer` in place — one thread per element,
    /// reading and writing the same buffer (bound at index 0). The dispatch is
    /// encoded ahead of this frame's drawing. `count` defaults to the buffer's
    /// element count. Standard constants are at index 10 (`u.time`/`u.dt`/…) and
    /// any `params` bytes at index 11. For a buffer the render path also reads each
    /// frame, prefer the ping-pong `compute(_:reading:writing:)` form.
    public func compute<T>(_ kernel: ComputeKernel, over buffer: ComputeBuffer<T>,
                           count: Int? = nil, params: ComputeParams = ComputeParams()) {
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: count ?? buffer.count,
            buffers: [buffer], params: params.bytes))
    }

    /// Run a compute `kernel` reading `reading` (index 0) and writing `writing`
    /// (index 1) — the ping-pong form for a sim whose output the render path also
    /// reads, so the GPU can overlap this frame's render with the next step. Swap
    /// the two buffers yourself between frames. `count` defaults to `reading`'s
    /// element count.
    public func compute<T>(_ kernel: ComputeKernel, reading: ComputeBuffer<T>,
                           writing: ComputeBuffer<T>, count: Int? = nil,
                           params: ComputeParams = ComputeParams()) {
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: count ?? reading.count,
            buffers: [reading, writing], params: params.bytes))
    }

    /// Draw a GPU particle `buffer` as additive sub-pixel discs (the area-conserving
    /// disc coverage `drawCircle` uses, so a million jittered marks fade by area
    /// rather than flicker). Composites under the active blend mode (`.add` sums
    /// them as light) and in draw order with everything else. `count` defaults to
    /// the buffer's element count.
    public func drawParticles(_ buffer: ComputeBuffer<OllinParticle>, count: Int? = nil) {
        drawer.recordParticles(buffer, count: count ?? buffer.count)
    }

    /// Step a `Particles` system one frame (records its compute dispatch and swaps
    /// its ping-pong buffers). `custom` passes up to four live floats the kernel
    /// reads as `custom.x…w`.
    public func updateParticles(_ particles: Particles, custom: SIMD4<Float> = .zero) {
        particles.recordStep(into: drawer, custom: custom)
    }

    /// Draw a `Particles` system's current state as additive discs (see
    /// `drawParticles(_ buffer:)`).
    public func drawParticles(_ particles: Particles) {
        drawer.recordParticles(particles.current, count: particles.count)
    }

    // MARK: 3D — camera & point clouds

    /// Set the active 3D camera (see `Camera3D`). Setting one puts this frame into
    /// 3D: the renderer adds a depth buffer and draws 3D geometry (point clouds)
    /// through the camera. Per-frame state — set it in `draw()`, where a 3D sketch
    /// usually animates an orbit; a 2D sketch never calls it and is unaffected.
    public func camera(_ camera: Camera3D) { drawer.camera(camera) }

    /// A perspective 3D camera looking from `eye` at `target` (sugar over `camera`);
    /// `fieldOfView` is the vertical angle in radians.
    public func perspective(eye: Vector3, target: Vector3 = .zero, up: Vector3 = .unitY,
                            fieldOfView: Double = .pi / 3, near: Double = 0.1, far: Double = 1000) {
        drawer.perspective(eye: eye, target: target, up: up,
                           fieldOfView: fieldOfView, near: near, far: far)
    }

    /// An orthographic 3D camera looking from `eye` at `target`, framing `height`
    /// world units top-to-bottom (sugar over `camera`).
    public func ortho(eye: Vector3, target: Vector3 = .zero, up: Vector3 = .unitY,
                      height: Double, near: Double = 0.1, far: Double = 1000) {
        drawer.ortho(eye: eye, target: target, up: up, height: height, near: near, far: far)
    }

    /// Draw a 3D `PointCloud` as camera-facing disc splats through the active
    /// camera (set one first with `camera`/`perspective`/`ortho`). Splats are sized
    /// in world units, so perspective shrinks distant points; they composite in
    /// draw order and under the active blend mode (`.add` sums them as light). A
    /// no-op without a camera.
    public func drawPointCloud(_ cloud: PointCloud) { drawer.drawPointCloud(cloud) }

    // MARK: 3D — depth-aware compositing

    /// Place subsequent 2D drawing at the depth of `worldPoint` in the active 3D
    /// scene, so it occludes — and is occluded by — 3D geometry: a 2D mark behind a
    /// point in the cloud is hidden, in front of it is drawn over. Pair it with
    /// `project(_:)` to put the mark at the point's screen position too (or use
    /// `withBillboard(at:)`, which does both). A no-op without a camera (drawing
    /// returns to "over"); saved by `withState`, and reset each frame like the camera.
    public func depth(at worldPoint: Vector3) { drawer.depth(at: worldPoint) }

    /// Return subsequent 2D drawing to compositing *over* the 3D scene in draw order
    /// (the default), ignoring the depth buffer.
    public func noDepth() { drawer.noDepth() }

    /// Project a world point through the active camera to its position on the canvas
    /// (top-left origin, points), or `nil` if there's no camera or the point is
    /// behind it. The screen place to draw a 2D billboard for a 3D point.
    public func project(_ worldPoint: Vector3) -> Vector2? {
        drawer.project(worldPoint, viewport: SIMD2<Float>(Float(width), Float(height)))
    }

    /// Draw a 2D billboard anchored to a world point: the origin is moved to the
    /// point's projected canvas position and the depth set to its depth, so 2D drawn
    /// inside `body` (in local coordinates around the origin) lands at the point and
    /// composites with correct occlusion against the 3D scene. Skipped if the point
    /// is behind the camera. Sugar over `project` + `translate` + `depth(at:)`,
    /// scoped by `withState`.
    public func withBillboard(at worldPoint: Vector3, _ body: () -> Void) {
        guard let screen = project(worldPoint) else { return }
        withState {
            depth(at: worldPoint)
            translate(screen)
            body()
        }
    }

    /// Run a compute `kernel` that writes `texture` — one thread per texel, over a
    /// 2-D grid. The write texture binds at **texture index 0**; the kernel takes
    /// `texture2d<float, access::write> [[texture(0)]]` and a `uint2 gid
    /// [[thread_position_in_grid]]`. Standard constants are at buffer index 10
    /// (`u.time`/…) and any `params` at buffer index 11. Use this to **seed** a
    /// simulation's initial state on the first frame, or for a generative image
    /// kernel that writes from `gid` alone.
    public func compute(_ kernel: ComputeKernel, writing texture: ComputeTexture,
                        params: ComputeParams = ComputeParams()) {
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, gridWidth: texture.width, gridHeight: texture.height,
            textures: [texture], params: params.bytes))
    }

    /// Run a compute `kernel` reading `reading` (texture index 0) and writing
    /// `writing` (texture index 1) — the texture ping-pong form. The kernel takes
    /// `texture2d<float, access::read> [[texture(0)]]`, `texture2d<float,
    /// access::write> [[texture(1)]]`, and a `uint2 gid`. The grid covers `writing`.
    /// For a self-evolving field the render path also reads each frame, drive it
    /// through a `PingPongTexture` (or the `Simulation` convenience) so a step never
    /// reads a texture it's mid-write into.
    public func compute(_ kernel: ComputeKernel, reading: ComputeTexture,
                        writing: ComputeTexture, params: ComputeParams = ComputeParams()) {
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, gridWidth: writing.width, gridHeight: writing.height,
            textures: [reading, writing], params: params.bytes))
    }

    /// Step a `Simulation` one frame — records its `subSteps` kernel dispatches and
    /// swaps its ping-pong textures so `current`/`image` end on the freshly written
    /// field. `custom` passes up to four live floats the step reads as `custom.x…w`.
    public func updateSimulation(_ simulation: Simulation, custom: SIMD4<Float> = .zero) {
        simulation.recordUpdate(into: drawer, custom: custom)
    }

    // MARK: Keyboard queries

    /// Whether `character` is currently held down — for continuous response while
    /// a key is held (`if isKeyDown("w") { … }` in `draw()`), where the one-shot
    /// `keyPressed()` hook won't do. Case-sensitive: `isKeyDown("w")` and
    /// `isKeyDown("W")` differ by the Shift state at the time of the press.
    public func isKeyDown(_ character: Character) -> Bool {
        pressedKeys.contains(.character(character))
    }

    /// Whether the named `code` (an arrow, `.return`, …) is currently held down.
    /// The space bar is a character, so poll it with `isKeyDown(" ")`.
    public func isKeyDown(_ code: KeyCode) -> Bool {
        pressedKeys.contains(.code(code))
    }

    // MARK: - Internals

    /// The state machine + per-frame geometry recorder the bare API forwards to.
    let drawer = Drawer()

    /// Registered lifecycle extensions (the `extend(...)` seam), and whether
    /// their one-time `setup` has run yet (lazily, on the first `performDraw`).
    private var extensions: [SketchExtension] = []
    private var extensionsDidSetup = false

    /// The `@Eased` / `@Smoothed` properties on this sketch, discovered once via
    /// reflection (the stored set is fixed at compile time) and advanced each frame.
    private var advancingValues: [FrameAdvancing]?

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

    /// Keys currently held down, so `isKeyDown(_:)` can answer and `keyIsPressed`
    /// tracks whether any key is down. The view inserts on press and removes on
    /// release (see `handleKey`).
    private var pressedKeys: Set<KeyToken> = []

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
    /// Fill with a gradient instead of a flat color: linear, radial, or
    /// along-path (see `Gradient`). Every shape takes it — the analytic SDF
    /// shapes evaluate it per pixel; the tessellated paths (`drawPolygon`,
    /// `drawShape`, curves) shade it across their vertices.
    public func fill(_ gradient: Gradient) { drawer.fill(gradient) }
    /// Fill with a `Paint` — a flat color or a gradient carried as one value.
    public func fill(_ paint: Paint) { drawer.fill(paint) }
    public func noFill() { drawer.noFill() }
    public func stroke(_ color: Color) { drawer.stroke(color) }
    /// Stroke with a gradient (see `Gradient`). An `.alongPath` gradient runs
    /// start-to-end along lines, curves, and stroked paths, and sweeps around
    /// region shapes' outlines.
    public func stroke(_ gradient: Gradient) { drawer.stroke(gradient) }
    /// Stroke with a `Paint` — a flat color or a gradient carried as one value.
    public func stroke(_ paint: Paint) { drawer.stroke(paint) }
    public func noStroke() { drawer.noStroke() }
    public func strokeWeight(_ weight: Double) { drawer.strokeWeight(weight) }
    /// Draw region shapes as a constant-width band along their outline instead of
    /// a solid interior (the `fill` color paints the band; an active `stroke`
    /// borders both edges). `width` is the band thickness, centered on the edge.
    /// Call `solid()` to return to filled shapes. Points, lines, and rings ignore it.
    public func hollow(_ width: Double) { drawer.hollow(width) }
    /// Return to solid fills (the default), undoing `hollow(_:)`.
    public func solid() { drawer.solid() }
    /// Set how following shapes combine with the canvas: `.normal` (default, lay
    /// over) or a combining mode like `.add` (sum colors as light, so overlapping
    /// marks brighten — best on a dark background), `.screen`, `.multiply`,
    /// `.subtract`, `.lightest`, or `.darkest`. Applies to every primitive — SDF
    /// shapes, tessellated paths, images, and text — and, like other state, is
    /// saved and restored by `withState { }`. See `BlendMode`.
    public func blendMode(_ mode: BlendMode) { drawer.blendMode(mode) }
    /// Set where a shape's stroke sits on its outline: `.center` (default, half
    /// inside / half outside), `.inside`, or `.outside`. Inside keeps the shape's
    /// footprint fixed; outside grows it by the stroke weight. Applies to the
    /// analytic SDF shapes; lines, point markers, and the tessellated paths
    /// (`drawPolyline`/`drawPolygon`/`drawShape`) stay centered. See `StrokeAlign`.
    public func strokeAlign(_ align: StrokeAlign) { drawer.strokeAlign(align) }
    /// Set how a stroked path turns its corners: `.miter` (default, a sharp point
    /// that bevels off past the miter limit), `.bevel` (always flat), or `.round`
    /// (arced). Applies to the tessellated stroked paths — `drawPolyline`, the
    /// `drawPolygon` outline, and `drawShape` contours. See `StrokeJoin`.
    public func strokeJoin(_ join: StrokeJoin) { drawer.strokeJoin(join) }
    /// Set how the open ends of a stroked path finish: `.butt` (default, flat at
    /// the endpoint), `.round` (a half-disk tip), or `.square` (a flat extension
    /// half the weight past the end). Applies to open tessellated paths
    /// (`drawPolyline`, open `drawShape` contours); closed outlines and the
    /// round-capped `drawLine` / `drawBezier` aren't affected. See `StrokeCap`.
    public func strokeCap(_ cap: StrokeCap) { drawer.strokeCap(cap) }
    public func pointSize(_ size: Double) { drawer.pointSize(size) }
    public func pointMarker(_ marker: PointMarker) { drawer.pointMarker(marker) }
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
    public func drawCircle(_ circle: Circle) {
        drawer.drawCircle(circle)
    }
    public func drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        drawer.drawEllipse(x, y, rx, ry)
    }
    public func drawEllipse(center: Vector2, rx: Double, ry: Double) {
        drawer.drawEllipse(center.x, center.y, rx, ry)
    }
    public func drawTriangle(_ x: Double, _ y: Double, _ radius: Double) {
        drawer.drawTriangle(x, y, radius)
    }
    public func drawTriangle(center: Vector2, radius: Double) {
        drawer.drawTriangle(center.x, center.y, radius)
    }
    public func drawTriangle(_ x: Double, _ y: Double, _ base: Double, _ height: Double) {
        drawer.drawTriangle(x, y, base, height)
    }
    public func drawTriangle(apex: Vector2, base: Double, height: Double) {
        drawer.drawTriangle(apex.x, apex.y, base, height)
    }
    public func drawTriangle(_ a: Vector2, _ b: Vector2, _ c: Vector2) {
        drawer.drawTriangle(a, b, c)
    }
    public func drawTriangle(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                             _ x3: Double, _ y3: Double) {
        drawer.drawTriangle(x1, y1, x2, y2, x3, y3)
    }
    public func drawNgon(_ x: Double, _ y: Double, _ radius: Double, sides: Int) {
        drawer.drawNgon(x, y, radius, sides: sides)
    }
    public func drawNgon(center: Vector2, radius: Double, sides: Int) {
        drawer.drawNgon(center.x, center.y, radius, sides: sides)
    }
    public func drawStar(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, points: Int) {
        drawer.drawStar(x, y, outerRadius, innerRadius, points: points)
    }
    public func drawStar(center: Vector2, outerRadius: Double, innerRadius: Double, points: Int) {
        drawer.drawStar(center.x, center.y, outerRadius, innerRadius, points: points)
    }
    public func drawPentagon(_ x: Double, _ y: Double, _ radius: Double) {
        drawer.drawPentagon(x, y, radius)
    }
    public func drawPentagon(center: Vector2, radius: Double) {
        drawer.drawPentagon(center.x, center.y, radius)
    }
    public func drawHexagon(_ x: Double, _ y: Double, _ radius: Double) {
        drawer.drawHexagon(x, y, radius)
    }
    public func drawHexagon(center: Vector2, radius: Double) {
        drawer.drawHexagon(center.x, center.y, radius)
    }
    public func drawHeptagon(_ x: Double, _ y: Double, _ radius: Double) {
        drawer.drawHeptagon(x, y, radius)
    }
    public func drawHeptagon(center: Vector2, radius: Double) {
        drawer.drawHeptagon(center.x, center.y, radius)
    }
    public func drawOctagon(_ x: Double, _ y: Double, _ radius: Double) {
        drawer.drawOctagon(x, y, radius)
    }
    public func drawOctagon(center: Vector2, radius: Double) {
        drawer.drawOctagon(center.x, center.y, radius)
    }
    public func drawRhombus(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        drawer.drawRhombus(x, y, width, height, cornerRadius: cornerRadius)
    }
    public func drawRhombus(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0) {
        drawer.drawRhombus(center.x, center.y, width, height, cornerRadius: cornerRadius)
    }
    public func drawVesica(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        drawer.drawVesica(x, y, width, height, cornerRadius: cornerRadius)
    }
    public func drawVesica(center: Vector2, width: Double, height: Double, cornerRadius: Double = 0) {
        drawer.drawVesica(center.x, center.y, width, height, cornerRadius: cornerRadius)
    }
    public func drawMoon(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double,
                         _ offset: Double, cornerRadius: Double = 0) {
        drawer.drawMoon(x, y, outerRadius, innerRadius, offset, cornerRadius: cornerRadius)
    }
    public func drawMoon(center: Vector2, outerRadius: Double, innerRadius: Double,
                         offset: Double, cornerRadius: Double = 0) {
        drawer.drawMoon(center.x, center.y, outerRadius, innerRadius, offset, cornerRadius: cornerRadius)
    }
    public func drawCross(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double, cornerRadius: Double = 0) {
        drawer.drawCross(x, y, length, thickness, cornerRadius: cornerRadius)
    }
    public func drawCross(center: Vector2, length: Double, thickness: Double, cornerRadius: Double = 0) {
        drawer.drawCross(center.x, center.y, length, thickness, cornerRadius: cornerRadius)
    }
    /// A filled ring (annulus) between `innerRadius` and `outerRadius`. Unlike the
    /// other region shapes it's **fill-only**: it takes the current `fill` and
    /// ignores `stroke`. For an outlined ring, draw two `drawCircle`s with `noFill()`.
    public func drawRing(_ x: Double, _ y: Double, _ innerRadius: Double, _ outerRadius: Double) {
        drawer.drawRing(x, y, innerRadius, outerRadius)
    }
    /// A filled ring (annulus). **Fill-only** — takes `fill`, ignores `stroke`; for
    /// an outlined ring, draw two `drawCircle`s with `noFill()`.
    public func drawRing(center: Vector2, innerRadius: Double, outerRadius: Double) {
        drawer.drawRing(center.x, center.y, innerRadius, outerRadius)
    }
    public func drawTrapezoid(_ x: Double, _ y: Double, _ topWidth: Double, _ bottomWidth: Double, _ height: Double) {
        drawer.drawTrapezoid(x, y, topWidth, bottomWidth, height)
    }
    public func drawTrapezoid(center: Vector2, topWidth: Double, bottomWidth: Double, height: Double) {
        drawer.drawTrapezoid(center.x, center.y, topWidth, bottomWidth, height)
    }
    public func drawParallelogram(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ skew: Double) {
        drawer.drawParallelogram(x, y, width, height, skew)
    }
    public func drawParallelogram(center: Vector2, width: Double, height: Double, skew: Double) {
        drawer.drawParallelogram(center.x, center.y, width, height, skew)
    }
    public func drawEgg(_ x: Double, _ y: Double, _ bottomRadius: Double, _ topRadius: Double) {
        drawer.drawEgg(x, y, bottomRadius, topRadius)
    }
    public func drawEgg(center: Vector2, bottomRadius: Double, topRadius: Double) {
        drawer.drawEgg(center.x, center.y, bottomRadius, topRadius)
    }
    public func drawHeart(_ x: Double, _ y: Double, _ size: Double) {
        drawer.drawHeart(x, y, size)
    }
    public func drawHeart(center: Vector2, size: Double) {
        drawer.drawHeart(center.x, center.y, size)
    }
    public func drawCutDisk(_ x: Double, _ y: Double, _ radius: Double, _ cut: Double) {
        drawer.drawCutDisk(x, y, radius, cut)
    }
    public func drawCutDisk(center: Vector2, radius: Double, cut: Double) {
        drawer.drawCutDisk(center.x, center.y, radius, cut)
    }
    public func drawUnevenCapsule(_ a: Vector2, _ b: Vector2, _ ra: Double, _ rb: Double) {
        drawer.drawUnevenCapsule(a, b, ra, rb)
    }
    public func drawUnevenCapsule(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ ra: Double, _ rb: Double) {
        drawer.drawUnevenCapsule(Vector2(x1, y1), Vector2(x2, y2), ra, rb)
    }
    public func drawHorseshoe(_ x: Double, _ y: Double, _ radius: Double, _ thickness: Double, gap: Double) {
        drawer.drawHorseshoe(x, y, radius, thickness, gap: gap)
    }
    public func drawHorseshoe(center: Vector2, radius: Double, thickness: Double, gap: Double) {
        drawer.drawHorseshoe(center.x, center.y, radius, thickness, gap: gap)
    }
    public func drawParabola(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        drawer.drawParabola(x, y, width, height)
    }
    public func drawParabola(center: Vector2, width: Double, height: Double) {
        drawer.drawParabola(center.x, center.y, width, height)
    }
    public func drawRoundedX(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double) {
        drawer.drawRoundedX(x, y, length, thickness)
    }
    public func drawRoundedX(center: Vector2, length: Double, thickness: Double) {
        drawer.drawRoundedX(center.x, center.y, length, thickness)
    }
    public func drawBlobbyCross(_ x: Double, _ y: Double, _ radius: Double, blobbiness: Double = 0.5) {
        drawer.drawBlobbyCross(x, y, radius, blobbiness: blobbiness)
    }
    public func drawBlobbyCross(center: Vector2, radius: Double, blobbiness: Double = 0.5) {
        drawer.drawBlobbyCross(center.x, center.y, radius, blobbiness: blobbiness)
    }
    public func drawTunnel(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        drawer.drawTunnel(x, y, width, height)
    }
    public func drawTunnel(center: Vector2, width: Double, height: Double) {
        drawer.drawTunnel(center.x, center.y, width, height)
    }
    public func drawStairs(_ x: Double, _ y: Double, _ stepWidth: Double, _ stepHeight: Double, steps: Int) {
        drawer.drawStairs(x, y, stepWidth, stepHeight, steps: steps)
    }
    public func drawStairs(center: Vector2, stepWidth: Double, stepHeight: Double, steps: Int) {
        drawer.drawStairs(center.x, center.y, stepWidth, stepHeight, steps: steps)
    }
    public func drawCoolS(_ x: Double, _ y: Double, _ size: Double) {
        drawer.drawCoolS(x, y, size)
    }
    public func drawCoolS(center: Vector2, size: Double) {
        drawer.drawCoolS(center.x, center.y, size)
    }
    public func drawArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double,
                        start: Double, stop: Double, mode: ArcMode = .open) {
        drawer.drawArc(x, y, rx, ry, start: start, stop: stop, mode: mode)
    }
    public func drawArc(center: Vector2, rx: Double, ry: Double,
                        start: Double, stop: Double, mode: ArcMode = .open) {
        drawer.drawArc(center.x, center.y, rx, ry, start: start, stop: stop, mode: mode)
    }
    public func drawPolyline(_ points: [Vector2], closed: Bool = false) {
        drawer.drawPolyline(points, closed: closed)
    }
    public func drawPolygon(_ points: [Vector2]) { drawer.drawPolygon(points) }
    public func drawShape(_ shape: Shape) { drawer.drawShape(shape) }

    /// Build a curved or straight outline inline and draw it: trace it with the
    /// pen methods on `Path` (`move`/`line`/`curve`/`quadCurve`/`cubicCurve`/`close`),
    /// then it fills (if closed) and strokes like any `Shape`.
    ///
    /// ```swift
    /// drawShape { p in
    ///     p.move(to: Vector2(200, 300))
    ///     p.curve(to: Vector2(400, 200))   // smooth through the points
    ///     p.curve(to: Vector2(600, 360))
    ///     p.close()
    /// }
    /// ```
    public func drawShape(_ build: (inout Path) -> Void) {
        var path = Path()
        build(&path)
        drawer.drawShape(path.shape)
    }

    /// A smooth curve through `points` — a Catmull-Rom spline that passes through
    /// each point with tangents derived from its neighbours. `closed: false` (the
    /// default) draws an open, stroked "wiggle"; `closed: true` makes a closed,
    /// fillable loop. Sugar over `Path` + `curve(to:)`.
    public func drawCurve(_ points: [Vector2], closed: Bool = false) {
        guard points.count >= 2 else { return }
        drawer.drawShape(Shape(curveThrough: points, closed: closed))
    }
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

    /// Draw every circle in `circles` in one call (all share the current
    /// fill/stroke/transform; each is still its own instanced quad).
    public func drawCircles(_ circles: [Circle]) { drawer.drawCircles(circles) }
    /// Draw a circle of the same `radius` at each center in `centers`.
    public func drawCircles(_ centers: [Vector2], radius: Double) {
        drawer.drawCircles(centers, radius: radius)
    }
    /// Draw a `pointSize` marker at each point in `points`.
    public func drawPoints(_ points: [Vector2]) { drawer.drawPoints(points) }
    /// Draw a marker of the same `size` at each point in `points`.
    public func drawPoints(_ points: [Vector2], size: Double) { drawer.drawPoints(points, size: size) }
    /// Draw every rectangle in `rectangles`, each with the same `cornerRadius`.
    public func drawRects(_ rectangles: [Rectangle], cornerRadius: Double = 0) {
        drawer.drawRects(rectangles, cornerRadius: cornerRadius)
    }

    /// Draw `image` at its native pixel size with its top-left corner at `(x, y)`.
    /// Load it once with `loadImage` (in `setup()`); it rides the transform stack,
    /// so `translate`/`rotate`/`scale` move and warp it, and composites in draw order.
    public func drawImage(_ image: Image, _ x: Double, _ y: Double) {
        drawer.drawImage(image, in: Rectangle(x: x, y: y,
                                              width: Double(image.width), height: Double(image.height)))
    }
    /// Draw `image` scaled to fill a `width`×`height` box with its top-left at `(x, y)`.
    public func drawImage(_ image: Image, _ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        drawer.drawImage(image, in: Rectangle(x: x, y: y, width: width, height: height))
    }
    /// Draw `image` stretched into `rect` — the `Rectangle` form of `drawImage`.
    public func drawImage(_ image: Image, in rect: Rectangle) {
        drawer.drawImage(image, in: rect)
    }
    /// Tint every following `drawImage`: each texel is multiplied by `color`, so
    /// its RGB recolors the image and its alpha fades it. White at full alpha (the
    /// default) leaves the image unchanged. Like other state, it's saved and
    /// restored by `withState { }`.
    public func tint(_ color: Color) { drawer.tint(color) }
    /// Stop tinting images — draw them unchanged again (the default), undoing `tint(_:)`.
    public func noTint() { drawer.noTint() }
    /// Set the active text font for `drawText` to a bitmap (pixel-grid) font —
    /// `.builtin` (Ollin's bundled Cozette pixel font), a loaded BDF/`.fnt`, or
    /// a sprite grid.
    public func textFont(_ font: BitmapFont) { drawer.textFont(font) }
    /// Set the active text font for `drawText` to an outline (vector `.ttf`/`.otf`)
    /// font — `OutlineFont(name:)`, `.system`, a file, or bundled data. One load
    /// draws at any `textSize`, and each glyph is a `Shape` (fill *and* stroke).
    /// The default font is `OutlineFont.systemMedium`, so text works with no setup.
    public func textFont(_ font: OutlineFont) { drawer.textFont(font) }
    /// Set the active text font for `drawText` to a stroke (single-line / plotter)
    /// font — `StrokeFont.builtin` (Hershey Sans) or a loaded `.jhf`. Glyphs are
    /// open pen paths drawn with the current `stroke`; `fill` is ignored.
    public func textFont(_ font: StrokeFont) { drawer.textFont(font) }
    /// Set the rendered text height in points — the height one line of glyphs
    /// occupies on screen. Defaults to 24.
    public func textSize(_ size: Double) { drawer.textSize(size) }
    /// Set how `drawText` anchors text to its position: horizontal
    /// `.left`/`.center`/`.right` and vertical `.top`/`.middle`/`.baseline`/`.bottom`
    /// (default `.left`, `.baseline`). See `TextAlignH` / `TextAlignV`.
    public func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        drawer.textAlign(horizontal, vertical)
    }
    /// Set how outline text is rendered: `.outline` (default, per-glyph vector fill
    /// — takes `fill` *and* `stroke`) or `.atlas` (the SDF-atlas scale path for
    /// paragraphs and large glyph counts — far cheaper per glyph, still crisp under
    /// magnification, fill-only). A no-op for bitmap and stroke fonts. See `TextMode`.
    public func textMode(_ mode: TextMode) { drawer.textMode(mode) }
    /// Draw `string` at `(x, y)` using the active `textFont`/`textSize`/`textAlign`.
    /// How it paints follows the font kind: an **outline** (`.ttf`/`.otf`) font
    /// (the default, `OutlineFont.systemMedium`) takes `fill` *and* `stroke`; a
    /// **bitmap** font uses `fill` only (it ignores `stroke`); a **stroke**
    /// (single-line) font uses `stroke` only.
    /// `\n` starts a new line; text rides the transform stack (so it rotates/scales).
    public func drawText(_ string: String, _ x: Double, _ y: Double) {
        drawer.drawText(string, x, y)
    }
    /// Draw `string` anchored at `position` — the `Vector2` form of `drawText`.
    public func drawText(_ string: String, at position: Vector2) {
        drawer.drawText(string, position.x, position.y)
    }
    /// The on-screen width of `string`'s widest line, in points, at the current
    /// `textFont`/`textSize` — for laying text out.
    public func textWidth(_ string: String) -> Double { drawer.textWidth(string) }
    /// The glyphs of `string` as vector `Shape`s positioned at `(x, y)` with the
    /// current `textFont`/`textSize`/`textAlign` — text as first-class geometry to
    /// fill, stroke, warp, sample, or animate. An outline font returns one `Shape`
    /// per glyph; a bitmap font returns its lit pixels as squares.
    public func textToShapes(_ string: String, _ x: Double, _ y: Double) -> [Shape] {
        drawer.textToShapes(string, x, y)
    }
    /// `textToShapes` anchored at `position` — the `Vector2` form.
    public func textToShapes(_ string: String, at position: Vector2) -> [Shape] {
        drawer.textToShapes(string, position.x, position.y)
    }
    /// Distance from the baseline to the top of the tallest glyphs, in points, at
    /// the current `textFont`/`textSize`.
    public func textAscent() -> Double { drawer.textAscent() }
    /// Distance from the baseline to the bottom of the lowest descenders, in
    /// points, at the current `textFont`/`textSize`.
    public func textDescent() -> Double { drawer.textDescent() }
    /// The baseline-to-baseline distance a new line advances by, in points, at the
    /// current `textFont`/`textSize`.
    public func textLeading() -> Double { drawer.textLeading() }
    /// The bounding box `string` occupies if drawn at `(x, y)` with the current
    /// text state (widest line by full block height).
    public func textBounds(_ string: String, _ x: Double, _ y: Double) -> Rectangle {
        drawer.textBounds(string, x, y)
    }
    /// `textBounds` anchored at `position` — the `Vector2` form.
    public func textBounds(_ string: String, at position: Vector2) -> Rectangle {
        drawer.textBounds(string, position.x, position.y)
    }
    /// Draw `string` wrapped into `rect`: words break at the box width and
    /// `textAlign` positions the block within the box. Explicit `\n`s start new
    /// paragraphs. Works for bitmap and outline fonts.
    public func drawText(_ string: String, in rect: Rectangle) {
        drawer.drawText(string, in: rect)
    }
    /// Draw `string` glyph by glyph, handing each glyph to `perGlyph` for its own
    /// transform or color before you stamp it with `TextGlyph.draw()`. Single line,
    /// using the current `textFont`/`textSize`/`textAlign`. Per-letter waves,
    /// rainbows, springs — effects p5/oF have no direct hook for.
    public func drawText(_ string: String, _ x: Double, _ y: Double, perGlyph: (TextGlyph) -> Void) {
        drawer.drawText(string, x, y, perGlyph: perGlyph)
    }
    /// `drawText(perGlyph:)` anchored at `position` — the `Vector2` form.
    public func drawText(_ string: String, at position: Vector2, perGlyph: (TextGlyph) -> Void) {
        drawer.drawText(string, position.x, position.y, perGlyph: perGlyph)
    }
    /// Draw `string` with its glyphs riding `path` — each glyph centered on the
    /// curve at its distance along the run (plus `offset`) and rotated to the
    /// tangent. Animate `offset` to flow the text along the path. Single line,
    /// takes `fill`/`stroke` like `drawText`.
    public func drawText(_ string: String, along path: Path, offset: Double = 0) {
        drawer.drawText(string, along: path, offset: offset)
    }
    public func translate(_ offset: Vector2) { drawer.translate(offset) }
    public func translate(_ x: Double, _ y: Double) { drawer.translate(Vector2(x, y)) }
    public func drawLine(_ a: Vector2, _ b: Vector2) { drawer.drawLine(a, b) }
    public func drawLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        drawer.drawLine(Vector2(x1, y1), Vector2(x2, y2))
    }
    public func drawOrientedBox(_ a: Vector2, _ b: Vector2, thickness: Double) {
        drawer.drawOrientedBox(a, b, thickness: thickness)
    }
    public func drawOrientedBox(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, thickness: Double) {
        drawer.drawOrientedBox(x1, y1, x2, y2, thickness: thickness)
    }
    public func drawOrientedVesica(_ a: Vector2, _ b: Vector2, width: Double) {
        drawer.drawOrientedVesica(a, b, width: width)
    }
    public func drawOrientedVesica(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, width: Double) {
        drawer.drawOrientedVesica(x1, y1, x2, y2, width: width)
    }
    public func drawBezier(_ start: Vector2, _ control: Vector2, _ end: Vector2) {
        drawer.drawBezier(start, control, end)
    }
    public func drawBezier(_ x1: Double, _ y1: Double, _ cx: Double, _ cy: Double,
                           _ x2: Double, _ y2: Double) {
        drawer.drawBezier(x1, y1, cx, cy, x2, y2)
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

    /// Record a key event from the view and update the held-key set. The view
    /// passes exactly one of `character`/`code` (a printing key vs. a named one);
    /// the other is `nil`. Updates `key`/`keyCode`/`keyIsPressed`, then the view
    /// calls `keyPressed()`/`keyReleased()`.
    func handleKey(character: Character?, code: KeyCode?, pressed: Bool) {
        key = character
        keyCode = code
        let token: KeyToken? = character.map(KeyToken.character) ?? code.map(KeyToken.code)
        if let token {
            if pressed { pressedKeys.insert(token) } else { pressedKeys.remove(token) }
        }
        keyIsPressed = !pressedKeys.isEmpty
    }

    /// Drop all held keys — called when the canvas loses keyboard focus, so a key
    /// held while focus leaves (no `keyUp` is delivered then) doesn't stick down.
    func clearHeldKeys() {
        pressedKeys.removeAll()
        keyIsPressed = false
    }

    func advance(time: Double, deltaTime: Double, frameRate: Double) {
        frameCount += 1
        self.time = time
        self.deltaTime = deltaTime
        self.frameRate = frameRate
        for value in collectAdvancingValues() { value.advance(by: deltaTime) }
    }

    /// The `@Eased` / `@Smoothed` properties on this sketch, collected once (the
    /// stored set is fixed) by walking the mirror up the class hierarchy, then
    /// cached.
    private func collectAdvancingValues() -> [FrameAdvancing] {
        if let cached = advancingValues { return cached }
        var found: [FrameAdvancing] = []
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                if let advancing = child.value as? FrameAdvancing { found.append(advancing) }
            }
            mirror = current.superclassMirror
        }
        advancingValues = found
        return found
    }

    func performDraw() {
        if !extensionsDidSetup {                 // run extension setup once, lazily
            extensionsDidSetup = true
            for e in extensions { e.setup(self) }
        }
        drawer.beginFrame()
        drawer.setComputeFrame(resolution: SIMD2(Float(width), Float(height)),
                               mouse: SIMD2(Float(mouseX), Float(mouseY)),
                               time: Float(time), dt: Float(deltaTime),
                               frameCount: UInt32(max(0, frameCount)))
        for e in extensions { e.beforeDraw(self) }
        draw()
        for e in extensions { e.afterDraw(self) }   // before the render — can draw
    }

    /// Fired by the runner after the frame renders, with its timing. Headless
    /// paths (export) don't call this — there's no live frame rate to report.
    func runAfterFrame(_ info: FrameInfo) {
        for e in extensions { e.afterFrame(self, info) }
    }

    /// Whether any registered extension currently wants the rendered frame.
    /// Computed live (not cached), so an extension can arm/disarm capture
    /// between frames; the runner reads it each frame and only pays the
    /// GPU→CPU readback when it's `true`.
    var wantsRenderedFrames: Bool { extensions.contains { $0.wantsRenderedFrame } }

    /// Fired by the runner after the render, handing the rendered frame to each
    /// extension that asked for it (via `wantsRenderedFrame`).
    func runFrameRendered(_ image: CGImage) {
        for e in extensions where e.wantsRenderedFrame { e.frameRendered(self, image) }
    }

    /// Whether any registered extension currently wants the rendered frame as a
    /// GPU texture (via `wantsRenderedTexture`). Computed live like
    /// `wantsRenderedFrames`, so a recorder/sharer can arm/disarm between frames;
    /// the runner only pays the off-screen re-render when it's `true`.
    var wantsRenderedTextures: Bool { extensions.contains { $0.wantsRenderedTexture } }

    /// Fired by the runner after the render, handing the rendered frame as a Metal
    /// texture to each extension that asked (via `wantsRenderedTexture`). The
    /// GPU-side companion to `runFrameRendered(_:)` — for sharing the live frame
    /// without a CPU round-trip (Syphon, and later the effects graph).
    func runFrameRendered(texture: MTLTexture) {
        for e in extensions where e.wantsRenderedTexture { e.frameRendered(self, texture: texture) }
    }
}
