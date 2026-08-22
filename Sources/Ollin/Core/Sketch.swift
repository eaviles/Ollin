import Foundation
import CoreGraphics
import Metal
import simd
import COllinShaders   // OllinParticle (the GPU particle struct, shared with the shaders)

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

    /// The center of the canvas, `(width / 2, height / 2)`.
    public var center: Vector2 { Vector2(width / 2, height / 2) }

    /// The canvas as a `Rectangle`, `(0, 0, width, height)` — terse for a physics
    /// `World`'s bounds, clamping, or hit-testing.
    public var bounds: Rectangle { Rectangle(x: 0, y: 0, width: width, height: height) }

    /// The canvas point at normalized coordinates: `uv(0, 0)` is the top-left
    /// corner, `uv(1, 1)` the bottom-right, `uv(0.5, 0.5)` the center. State a
    /// layout as proportions and it never reads `width`/`height` (the same
    /// 0…1, top-left space per-pixel shader code sees). Values outside 0…1
    /// land off-canvas proportionally. Sugar over `bounds.point(u:v:)`, whose
    /// `uv(of:)` inverse normalizes a point back (e.g. the mouse).
    public func uv(_ u: Double, _ v: Double) -> Vector2 {
        Vector2(u * width, v * height)
    }

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

    /// Whether the secondary (right) mouse button is held over the canvas. The
    /// `cameraControl()` rig pans on a right-drag (as well as a modifier-drag);
    /// a sketch can also poll it for its own secondary action.
    public internal(set) var rightMouseIsPressed = false

    /// How hard the pointer is being pressed, `0` (nothing held) to `1` (as hard
    /// as the device reports). On a pressure-sensing device (a Force Touch
    /// trackpad, a pen tablet) it varies continuously through a press, which is
    /// what `StrokeDynamics.pressure(...)` reads to make a mark swell under a
    /// heavier hand. On a device that can't measure pressure it is simply `1`
    /// while a button is down, so a pressure-driven sketch still draws, just at
    /// one weight. Check `pressureIsAvailable` to pick a different driver
    /// (`.speed(...)` works anywhere) when there's nothing to feel.
    public internal(set) var pressure: Double = 0

    /// Whether the device sending pointer events can actually measure pressure.
    /// `false` until the first press says otherwise: the answer comes from the
    /// event rather than the machine, so plugging in a tablet mid-sketch updates
    /// it.
    public internal(set) var pressureIsAvailable = false

    /// How far the scroll wheel (or a trackpad two-finger scroll) moved this frame,
    /// summed since the last frame; `0` when nothing scrolled. Positive is a scroll
    /// up. Read it in `draw()` (it is a per-frame value, like `mouseX`); the
    /// `cameraControl()` rig reads it to dolly. The `mouseWheel()` hook fires per
    /// event for one-shot response.
    public internal(set) var scrollDeltaY: Double = 0

    /// The modifier keys (shift, option, command, control) currently held. Combine
    /// with a drag for a modified gesture, e.g. `if modifiers.contains(.shift) { … }`.
    public internal(set) var modifiers: ModifierKeys = []

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

    /// How far above white the display can currently go, as a multiple of it:
    /// 1 means no headroom (an ordinary screen, or a window that never asked
    /// for any), 2 means values up to 2.0 are shown as highlights brighter than
    /// white. Read it to tell whether an `.extended` sketch is actually getting
    /// the range it asked for, since the system grants headroom and takes it
    /// back as the display's brightness and the surrounding content change.
    ///
    /// Live only: a headless render has no display, so it reads 1.
    public private(set) var displayHeadroom: Double = 1

    /// Where this canvas sits on the desk, in screen points, or `nil` when it
    /// sits nowhere (an export, a headless render).
    ///
    /// It is measured the way the canvas itself is: the origin is the top-left
    /// corner of the main screen, and y grows downward. So two sketches running
    /// side by side describe the same desk in the same numbers, which is what
    /// lets one world show through several windows at once.
    ///
    /// ```swift
    /// guard let mine = canvasOnScreen else { return }
    /// let onCanvas = (worldPoint - mine.corner) * (width / mine.width)
    /// ```
    ///
    /// It follows the window: drag one and the next frame reads the new place.
    /// The rectangle is the canvas's own, not the window's, so a sidebar or a
    /// title bar is already out of it. A piece being warped onto a wall is the
    /// one case where the two part company, since the warp moves the picture
    /// inside the canvas rather than the canvas across the desk.
    ///
    /// See `Examples/Installation/ManyWindows`.
    public private(set) var canvasOnScreen: Rectangle?

    /// The screen that canvas is on, in the same coordinates, or `nil` when
    /// there is no window. The room a piece has to be dragged around in, and
    /// the natural size for a world that several windows look into.
    public private(set) var screenFrame: Rectangle?

    /// Whether the system is set to reduce motion.
    ///
    /// Ollin animates by default, which is the point of `draw()` running every
    /// frame, and for some people that is a problem rather than a feature.
    /// Reading this is how a sketch offers the quieter version of itself: hold a
    /// value still, slow a drift, or drop a flash.
    ///
    /// ```swift
    /// let speed = prefersReducedMotion ? 0.1 : 1.0
    /// ```
    ///
    /// Nothing is applied for you. A sketch decides what less movement means,
    /// because only the sketch knows which of its movements carries the piece
    /// and which is decoration. The setting is read fresh, so turning it on
    /// reaches a running sketch on the next frame.
    ///
    /// A headless render always reads `false`, so an export is the same file on
    /// any machine.
    public var prefersReducedMotion: Bool { OllinAccessibility.prefersReducedMotion }

    /// What the sketch has said about itself, for somebody who cannot see it.
    ///
    /// Filled in by `describe(_:)` and `describe(_:as:in:)`, and read by the
    /// window, which hands it to the platform's accessibility layer. It stays
    /// empty until a sketch says something.
    public internal(set) var accessibleDescription = SketchDescription()

    /// How much color the finished frame carries out of the sketch. Defaults to
    /// `.standard` (8-bit sRGB, what every screen and file handles). Declare
    /// `.wide` to present through Display P3 in a floating-point drawable, so
    /// colors named outside sRGB reach the screen and gradients stop banding, or
    /// `.extended` to also keep values above 1.0 as highlights brighter than
    /// white, with an exported video written as HDR10:
    ///
    /// ```swift
    /// override var colorOutput: ColorOutput { .extended }
    /// ```
    ///
    /// Declared rather than called, because the window's drawable is built from
    /// it once. See `ColorOutput` for what each step changes.
    open var colorOutput: ColorOutput { .standard }

    /// The length of the sketch's loop in seconds, when it has one. A sketch
    /// whose motion repeats exactly (driven by `loopProgress`/`pingPong`,
    /// looping noise, or any phase built from `time`) declares its period here,
    /// and `--export-loop` renders exactly one lap, so the exported GIF or
    /// video cycles seamlessly without hand-matching `--seconds`:
    ///
    /// ```swift
    /// override var loopDuration: Double? { 6 }   // repeats every 6 seconds
    /// ```
    ///
    /// `nil` (the default) declares no loop. See `Docs/Output/Export.md`.
    open var loopDuration: Double? { nil }

    /// The spot inks a print separation splits this sketch into, when it is
    /// made for physical printing (risograph, screen printing). Declaring
    /// them lets `--export-separations` write one grayscale master per ink
    /// plus a registration-marked preview with no further flags:
    ///
    /// ```swift
    /// override var printInks: [Ink]? { [.fluorescentPink, .blue, .yellow] }
    /// ```
    ///
    /// `nil` (the default) declares none; the export then needs `--inks`.
    /// See `Docs/Output/PrintSeparations.md`.
    open var printInks: [Ink]? { nil }

    /// How far apart the two eyes stand when this sketch is exported as spatial
    /// video, and how far away they agree. Both numbers are worked out from the
    /// camera by default, which is usually enough; declare them when the piece
    /// wants a particular depth:
    ///
    /// ```swift
    /// override var stereoGeometry: StereoGeometry {
    ///     StereoGeometry(interocular: 0.1, convergence: 6)
    /// }
    /// ```
    ///
    /// See `Docs/Output/Spatial.md`.
    open var stereoGeometry: StereoGeometry { .automatic }

    /// What this piece needs to run by itself, unattended, for days. Defaults
    /// to `.off`, a sketch run at a desk for a session:
    ///
    /// ```swift
    /// override var installation: Installation { .on }
    /// ```
    ///
    /// `.on` fills the screen, hides the pointer, and keeps the display awake
    /// and the screen saver off. See `Installation` for the parts, and
    /// `Docs/Output/Installation.md` for the whole surface.
    open var installation: Installation { .off }

    /// The clock a shader reads, which is the sketch clock until an
    /// installation asks for it to start over.
    ///
    /// A 32-bit `float` cannot hold a second-accurate clock for long: a day in,
    /// a frame's worth of time is at the limit of what it resolves, and a week
    /// in the number does not change from one frame to the next at all. So a
    /// piece that runs for days hands its shaders a clock that starts over,
    /// while `time` itself keeps counting. See `Installation.Clock`.
    var shaderClock: Double {
        guard let period = installation.clockPeriod(loopDuration: loopDuration),
              period > 0 else { return time }
        return time.truncatingRemainder(dividingBy: period)
    }

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
    /// Called once each time the scroll wheel moves; `scrollDeltaY` holds this
    /// event's movement. Override for one-shot response (a discrete zoom step, a
    /// page); for continuous response poll `scrollDeltaY` in `draw()` instead.
    open func mouseWheel() {}
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

    // MARK: Compute (spatial hash & artificial life)

    /// Make a GPU neighbor-search grid over `bounds` (the full canvas by default) with
    /// cells of `radius` (the query radius your kernel uses), for `count` particles.
    /// The primitive under the particle-interaction sims; drive your own with
    /// `neighborStep(_:over:reading:writing:)`. See `SpatialHash`.
    public func spatialHash(in bounds: Rectangle? = nil, radius: Double, count: Int) -> SpatialHash {
        SpatialHash(bounds: bounds ?? self.bounds, cellSize: radius, count: count)
    }

    /// Build `hash` over `reading`, then run your own `kernel` with the particle
    /// buffers and the hash's neighbor buffers bound at the documented indices
    /// (`reading` 0, `writing` 1, `sortedIndices` 2, `cellStart` 3, `cellCount` 4,
    /// `grid` 5). Walk the neighbors in the kernel with `OLLIN_FOR_NEIGHBORS`. Swap
    /// your ping-pong yourself. See `SpatialHash` for the kernel contract.
    public func neighborStep(_ kernel: ComputeKernel, over hash: SpatialHash,
                             reading: ComputeBuffer<OllinParticle>,
                             writing: ComputeBuffer<OllinParticle>,
                             params: ComputeParams = ComputeParams()) {
        hash.recordBuild(into: drawer, positions: reading)
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: hash.count,
            buffers: [reading, writing, hash.sortedIndices, hash.cellStart,
                      hash.cellCount, hash.gridBuffer], params: params.bytes))
    }

    /// Make a `ParticleLife` system: `count` particles of `kinds` kinds over `bounds`
    /// (the full canvas by default), interacting within `radius`, seeded from `seed`
    /// (this sketch's `variation` by default). Build it in `setup()`, then
    /// `updateParticleLife` + `drawParticles` in `draw()`. See `ParticleLife`.
    public func particleLife(count: Int, kinds: Int, radius: Double,
                             bounds: Rectangle? = nil, seed: UInt64? = nil) -> ParticleLife {
        ParticleLife(count: count, kinds: kinds, bounds: bounds ?? self.bounds,
                     radius: radius, seed: seed ?? UInt64(variation))
    }

    /// Step a `ParticleLife` system one frame (builds its neighbor hash and runs its
    /// force/integration kernel).
    public func updateParticleLife(_ life: ParticleLife) { life.recordStep(into: drawer) }

    /// Draw a `ParticleLife` system's particles as additive discs.
    public func drawParticles(_ life: ParticleLife) {
        drawer.recordParticles(life.current, count: life.count)
    }

    /// Make a `PPS` (Primordial Particle System): `count` particles over `bounds` (the
    /// full canvas by default) interacting within `radius`, seeded from `seed` (this
    /// sketch's `variation` by default). `PPS.suggestedCount(for:in:)` estimates a
    /// good density. See `PPS`.
    public func primordialParticles(count: Int, radius: Double,
                                    bounds: Rectangle? = nil, seed: UInt64? = nil) -> PPS {
        PPS(count: count, bounds: bounds ?? self.bounds, radius: radius,
            seed: seed ?? UInt64(variation))
    }

    /// Step a `PPS` one frame (builds its neighbor hash and runs its turn/move kernel).
    public func updatePPS(_ pps: PPS) { pps.recordStep(into: drawer) }

    /// Draw a `PPS`'s particles as additive discs (colored by local crowd size).
    public func drawParticles(_ pps: PPS) {
        drawer.recordParticles(pps.current, count: pps.count)
    }

    /// Make a `Physarum` slime-mold sim: `agents` agents on a `resolution`×`resolution`
    /// trail map, seeded from `seed` (this sketch's `variation` by default). Build it
    /// in `setup()`, then `updatePhysarum` + `drawImage(sim.image, in:)` in `draw()`.
    /// See `Physarum`.
    public func physarum(agents: Int, resolution: Int, seed: UInt64? = nil) -> Physarum {
        Physarum(agents: agents, resolution: resolution, seed: seed ?? UInt64(variation))
    }

    /// Make a `Physarum` sim on a non-square `width`×`height` trail map.
    public func physarum(agents: Int, width: Int, height: Int, seed: UInt64? = nil) -> Physarum {
        Physarum(agents: agents, width: width, height: height, seed: seed ?? UInt64(variation))
    }

    /// Step a `Physarum` sim one frame (agents sense/steer/move/deposit, then the trail
    /// diffuses, decays, and colorizes).
    public func updatePhysarum(_ physarum: Physarum) { physarum.recordStep(into: drawer) }

    /// Make a `Swarm`: `count` steering agents scattered over `bounds` (the full
    /// canvas by default), each seeing others within `perceptionRadius`, seeded from
    /// `seed` (this sketch's `variation` by default). Every behavior starts at weight
    /// zero, so set the ones you want. Build it in `setup()`, then `updateSwarm` +
    /// `drawParticles` in `draw()`. See `Swarm`.
    public func swarm(count: Int, perceptionRadius: Double, colors: [Color] = [],
                      size: Double = 2.0, bounds: Rectangle? = nil,
                      seed: UInt64? = nil) -> Swarm {
        Swarm(count: count, bounds: bounds ?? self.bounds,
              perceptionRadius: perceptionRadius, colors: colors, size: size,
              seed: seed ?? UInt64(variation))
    }

    /// Step a `Swarm` one frame (builds its neighbor hash, then sums the weighted
    /// steering behaviors and moves every agent).
    public func updateSwarm(_ swarm: Swarm) {
        swarm.recordStep(into: drawer, frameDt: deltaTime)
    }

    /// Draw a `Swarm`'s agents as additive discs.
    public func drawParticles(_ swarm: Swarm) {
        drawer.recordParticles(swarm.current, count: swarm.count)
    }

    /// Make a `ParticleLenia`: `count` particles over `bounds` (the full canvas by
    /// default) with one model unit drawn `spacing` points wide, seeded from `seed`
    /// (this sketch's `variation` by default). They start packed in a disc at the
    /// middle, which is where the structures grow from. Build it in `setup()`, then
    /// `updateParticleLenia` + `drawParticles` in `draw()`. See `ParticleLenia`.
    public func particleLenia(count: Int, spacing: Double, bounds: Rectangle? = nil,
                              seed: UInt64? = nil) -> ParticleLenia {
        ParticleLenia(count: count, bounds: bounds ?? self.bounds, spacing: spacing,
                      seed: seed ?? UInt64(variation))
    }

    /// Step a `ParticleLenia` one frame (a fresh neighbor sort and a walk downhill on
    /// the energy field, as many times as the pace asks for).
    public func updateParticleLenia(_ lenia: ParticleLenia) {
        lenia.recordStep(into: drawer, frameDt: deltaTime)
    }

    /// Draw a `ParticleLenia`'s particles as discs colored by how crowded each one is.
    public func drawParticles(_ lenia: ParticleLenia) {
        drawer.recordParticles(lenia.current, count: lenia.count)
    }

    /// Make a `SwarmChemistry`: `count` particles over `bounds` (the full canvas by
    /// default) sharing `kinds` distinct random recipes between them, seeded from
    /// `seed` (this sketch's `variation` by default). How far a particle can see, how
    /// close counts as a contact, and the conversion out of the recipes' published
    /// units all come from how densely `count` particles fill `bounds`, so there is
    /// nothing else to name. Build it in `setup()`, then `updateSwarmChemistry` +
    /// `drawParticles` in `draw()`. See `SwarmChemistry`.
    public func swarmChemistry(count: Int, kinds: Int = 6, size: Double = 2.6,
                               bounds: Rectangle? = nil,
                               seed: UInt64? = nil) -> SwarmChemistry {
        SwarmChemistry(count: count, bounds: bounds ?? self.bounds, kinds: kinds,
                       size: size, seed: seed ?? UInt64(variation))
    }

    /// Step a `SwarmChemistry` one frame (the kinetic rule each particle's own recipe
    /// describes, and the recipes that change hands on contact).
    public func updateSwarmChemistry(_ chemistry: SwarmChemistry) {
        chemistry.recordStep(into: drawer, frameDt: deltaTime)
    }

    /// Draw a `SwarmChemistry`'s particles, colored by the recipe each one is holding.
    public func drawParticles(_ chemistry: SwarmChemistry) {
        drawer.recordParticles(chemistry.current, count: chemistry.count)
    }

    /// Make an `AttractorFlow`: `count` particles riding `system`, scattered through
    /// the attractor's own neighborhood from `seed` (this sketch's `variation` by
    /// default). Build it in `setup()`, then `updateAttractorFlow` + `drawParticles`
    /// in `draw()`. The flow is 3D, so it needs a camera. See `AttractorFlow`.
    public func attractorFlow(count: Int, _ system: AttractorSystem,
                              seed: UInt64? = nil) -> AttractorFlow {
        AttractorFlow(count: count, system: system, seed: seed ?? UInt64(variation))
    }

    /// Step an `AttractorFlow` one frame (advances every particle along the velocity
    /// field with fourth-order Runge-Kutta and recolors it by the speed it reached).
    public func updateAttractorFlow(_ flow: AttractorFlow) {
        flow.recordStep(into: drawer, frameDt: deltaTime)
    }

    /// Draw an `AttractorFlow`'s particles as camera-facing splats, like a
    /// `PointCloud`. A no-op in a 2D frame: set a `camera` first.
    public func drawParticles(_ flow: AttractorFlow) {
        drawer.recordPointCloud(flow.current, count: flow.count)
    }

    /// Make an `Evolution`: `count` individuals, each carrying `genes` steering
    /// impulses, flying from `from` toward `to` and bred each generation from whoever
    /// came closest. Seeded from `seed` (this sketch's `variation` by default). Build
    /// it in `setup()` (set `obstacles` there too), then `updateEvolution` +
    /// `drawParticles` in `draw()`. See `Evolution`.
    public func evolution(count: Int, genes: Int, from start: Vector2, to target: Vector2,
                          seed: UInt64? = nil) -> Evolution {
        Evolution(count: count, genes: genes, start: start, target: target,
                  seed: seed ?? UInt64(variation))
    }

    /// Step an `Evolution` one frame: another step of the current trial, or, when the
    /// trial is up, the breeding pass that makes the next generation.
    public func updateEvolution(_ evolution: Evolution) {
        evolution.recordStep(into: drawer, frameDt: deltaTime)
    }

    /// Draw an `Evolution`'s population as additive discs, colored by how far along the
    /// way to the target each one has got.
    public func drawParticles(_ evolution: Evolution) {
        drawer.recordParticles(evolution.current, count: evolution.count)
    }

    /// Make a `ParticleFluid`: `count` fluid particles interacting within `radius`
    /// (the fluid's resolution), seeded as a block inside `bounds` (the full canvas
    /// by default) from `seed` (this sketch's `variation` by default). Build it in
    /// `setup()`, then `updateParticleFluid` + `drawParticles` in `draw()`. See
    /// `ParticleFluid`.
    public func particleFluid(count: Int, radius: Double, spacing: Double? = nil,
                              bounds: Rectangle? = nil, seed: UInt64? = nil) -> ParticleFluid {
        ParticleFluid(count: count, bounds: bounds ?? self.bounds, radius: radius,
                      spacing: spacing, seed: seed ?? UInt64(variation))
    }

    /// Step a `ParticleFluid` one frame (its fixed substeps: predict, rebuild the
    /// neighbor hash, measure densities, apply pressure + viscosity, integrate).
    public func updateParticleFluid(_ fluid: ParticleFluid) {
        fluid.recordStep(into: drawer, frameDt: deltaTime)
    }

    /// Draw a `ParticleFluid`'s particles as discs, tinted by speed.
    public func drawParticles(_ fluid: ParticleFluid) {
        drawer.recordParticles(fluid.current, count: fluid.count)
    }

    /// Make a `SoftBodies` system: `count` squishy blobs of roughly `radius`,
    /// scattered inside `bounds` (the full canvas by default) from `seed` (this
    /// sketch's `variation` by default) so they fall into a pile. Build it in
    /// `setup()`, then `updateSoftBodies` + `drawParticles` in `draw()`. See
    /// `SoftBodies`.
    public func softBodies(count: Int, radius: Double, spacing: Double? = nil,
                           bounds: Rectangle? = nil, seed: UInt64? = nil) -> SoftBodies {
        SoftBodies(count: count, bounds: bounds ?? self.bounds, radius: radius,
                   spacing: spacing, seed: seed ?? UInt64(variation))
    }

    /// Step a `SoftBodies` system one frame (its fixed substeps: build the neighbor
    /// hash, fit each body's centroid + rotation, steer, collide, integrate).
    public func updateSoftBodies(_ bodies: SoftBodies) {
        bodies.recordStep(into: drawer, frameDt: deltaTime)
    }

    /// Draw a `SoftBodies` system's particles as discs, colored per body.
    public func drawParticles(_ bodies: SoftBodies) {
        drawer.recordParticles(bodies.current, count: bodies.count)
    }

    /// Set the active 3D camera (see `Camera3D`). Setting one puts this frame into
    /// 3D: the renderer adds a depth buffer and draws 3D geometry (point clouds)
    /// through the camera. Per-frame state — set it in `draw()`, where a 3D sketch
    /// usually animates an orbit; a 2D sketch never calls it and is unaffected.
    public func camera(_ camera: Camera3D) { drawer.camera(camera) }

    /// The 3D camera in effect for this frame, if one has been set this `draw()` (by
    /// `camera`/`perspective`/`ortho`/`cameraMove`/`cameraControl`/`cameraShowcase`),
    /// else `nil`. Read it to find where the camera ended up (e.g. its `eye`) when
    /// an interactive rig (`cameraShowcase`) owns the pose. `nil` in a 2D frame.
    public var activeCamera: Camera3D? { drawer.camera3D }

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

    /// The shared rig behind `cameraControl()`, `cameraMove(_:)`, and `cameraShowcase(_:)`. Created once
    /// and carried across frames so the pose (and a move's clock) persists; a
    /// sketch that never calls those methods never touches it.
    let cameraRig = CameraRig()

    /// Run a ready-made cinematic `move` over the camera and set it for this frame,
    /// instead of keyframing the camera by hand. Each move is a way to look at an
    /// object on a turntable (`.turntable`, `.pushIn`, `.tilt`, `.orbitAndRise`, …),
    /// modulating the orbit pose around `target`. The `target`/`radius`/`elevation`/
    /// `fieldOfView` arguments frame the shot on the first call; after that the move
    /// owns the pose (and a preceding `cameraControl()` frames it instead). Call it
    /// each `draw()`, like `camera(...)`.
    public func cameraMove(_ move: CameraMove, target: Vector3 = .zero, radius: Double = 10,
                           elevation: Double = 0.3, fieldOfView: Double = .pi / 3,
                           near: Double = 0.1, far: Double = 1000) {
        cameraRig.driver = .move
        cameraRig.seed(target: target, radius: radius, elevation: elevation, fieldOfView: fieldOfView)
        cameraRig.updateMove(move, dt: deltaTime)
        cameraRig.applyViewSnap(dt: deltaTime)
        camera(cameraRig.makeCamera(near: near, far: far))
    }

    /// Let the viewer move the camera by hand: drag to orbit the object, scroll to
    /// dolly in and out, and either right-drag or shift/option-drag to pan the
    /// target. The motion is damped, so it settles smoothly and a flick keeps a
    /// little spin. Opt-in, like `lights()`: call it each `draw()` and it sets the
    /// camera for the frame; a sketch that never calls it keeps its own camera.
    ///
    /// The `target`/`radius`/`azimuth`/`elevation`/`fieldOfView` arguments frame the
    /// starting shot on the *first* call only; after that the viewer (or a
    /// `cameraMove(_:)` you switch to) owns the pose, so passing them every frame
    /// does not fight the interaction.
    public func cameraControl(target: Vector3 = .zero, radius: Double = 10,
                              azimuth: Double = 0, elevation: Double = 0.3,
                              fieldOfView: Double = .pi / 3,
                              near: Double = 0.1, far: Double = 1000) {
        cameraRig.driver = .control
        cameraRig.seed(target: target, radius: radius, azimuth: azimuth,
                       elevation: elevation, fieldOfView: fieldOfView)
        let input = CameraInput(mouseX: mouseX, mouseY: mouseY,
                                leftPressed: mouseIsPressed, rightPressed: rightMouseIsPressed,
                                modifiers: modifiers, scrollDeltaY: scrollDeltaY)
        cameraRig.updateControl(input: input, dt: deltaTime, viewportHeight: height)
        cameraRig.applyViewSnap(dt: deltaTime)
        camera(cameraRig.makeCamera(near: near, far: far))
    }

    /// The interactive orbit: play `move` as an auto-orbit the viewer can take over.
    /// The camera orbits on its own; the moment the viewer drags to orbit, scrolls to
    /// dolly, or right/modifier-drags to pan, the automatic motion yields and they
    /// drive. After `idleReturn` seconds of no input the camera eases back over
    /// `returnDuration` seconds to the opening framing and the orbit resumes, so a
    /// sketch is alive on its own yet always explorable. Opt-in, like `cameraMove`/
    /// `cameraControl`: call it each `draw()`; a sketch that never calls it keeps its
    /// own camera.
    ///
    /// The `target`/`radius`/`elevation`/`fieldOfView` arguments frame the opening
    /// shot on the *first* call only, and are where the idle return glides back to.
    /// `move` defaults to `.autoOrbit()`, a gentle slow turntable; pass a tuned
    /// `.turntable`/`.sway`/… to keep a specific motion.
    public func cameraShowcase(_ move: CameraMove = .autoOrbit(),
                            target: Vector3 = .zero, radius: Double = 10,
                            elevation: Double = 0.3, fieldOfView: Double = .pi / 3,
                            near: Double = 0.1, far: Double = 1000,
                            idleReturn: Double = 10, returnDuration: Double = 4) {
        cameraRig.driver = .showcase
        cameraRig.seed(target: target, radius: radius, elevation: elevation, fieldOfView: fieldOfView)
        let input = CameraInput(mouseX: mouseX, mouseY: mouseY,
                                leftPressed: mouseIsPressed, rightPressed: rightMouseIsPressed,
                                modifiers: modifiers, scrollDeltaY: scrollDeltaY)
        cameraRig.updateInteractiveMove(move, input: input, dt: deltaTime,
                                        viewportHeight: height, idleTimeout: idleReturn,
                                        returnDuration: returnDuration)
        cameraRig.applyViewSnap(dt: deltaTime)
        camera(cameraRig.makeCamera(near: near, far: far))
    }

    /// Run a cinematic `move` opening on an authored camera's framing: the shot
    /// starts at `camera`'s own pose (its target, distance, angle, and field of
    /// view, e.g. a loaded scene's `scene.camera`), then the move owns it. Seeds
    /// on the *first* call only, like the plain form's framing arguments.
    /// `near`/`far` default to the camera's own clip range. The rig orbits y-up,
    /// so an authored roll is dropped.
    public func cameraMove(_ move: CameraMove, from camera: Camera3D,
                           near: Double? = nil, far: Double? = nil) {
        seedCameraRig(from: camera)
        cameraMove(move, near: near ?? camera.near, far: far ?? camera.far)
    }

    /// Hand the viewer the camera, opening on an authored camera's framing: the
    /// view starts at `camera`'s own pose (e.g. a loaded scene's `scene.camera`)
    /// and the viewer orbits, dollies, and pans from there. The one-call form of
    /// "open on the authored shot, then let them explore". Seeds on the *first*
    /// call only; `near`/`far` default to the camera's own clip range. The rig
    /// orbits y-up, so an authored roll is dropped.
    public func cameraControl(from camera: Camera3D,
                              near: Double? = nil, far: Double? = nil) {
        seedCameraRig(from: camera)
        cameraControl(near: near ?? camera.near, far: far ?? camera.far)
    }

    /// The interactive orbit, opening on an authored camera's framing: `move`
    /// plays from `camera`'s own pose (e.g. a loaded scene's `scene.camera`),
    /// the viewer can take over any time, and the idle return glides back to
    /// the authored shot. Seeds on the *first* call only; `near`/`far` default
    /// to the camera's own clip range. The rig orbits y-up, so an authored
    /// roll is dropped.
    public func cameraShowcase(_ move: CameraMove = .autoOrbit(), from camera: Camera3D,
                               near: Double? = nil, far: Double? = nil,
                               idleReturn: Double = 10, returnDuration: Double = 4) {
        seedCameraRig(from: camera)
        cameraShowcase(move, near: near ?? camera.near, far: far ?? camera.far,
                       idleReturn: idleReturn, returnDuration: returnDuration)
    }

    /// Seed the rig's opening pose from an authored camera (the first call
    /// wins, matching the plain forms' framing arguments).
    private func seedCameraRig(from camera: Camera3D) {
        let pose = camera.orbitPose
        cameraRig.seed(target: pose.target, radius: pose.radius, azimuth: pose.azimuth,
                       elevation: pose.elevation, fieldOfView: pose.fieldOfView,
                       orthographic: pose.orthographic)
    }

    /// Snap the camera to a canonical inspection angle, the way a modeling tool's
    /// numpad jumps the viewport to a known view. `.reset` returns to the sketch's
    /// opening framing; the six axis views (`.front`/`.back`/`.left`/`.right`/`.top`/
    /// `.bottom`) look straight down each axis; and `.isometric` is the three-quarter
    /// view that shows all three axes at once. The axis and isometric views keep the
    /// current center and distance and only swing the orbit angle.
    ///
    /// Works with the camera rig (`cameraShowcase`/`cameraControl`/`cameraMove`): a
    /// snap glides the rig's pose, then hands back to the running motion from there.
    /// A sketch driving the camera by hand with `camera(...)` overrides the pose
    /// every frame, so a snap has no effect there. By default the camera glides over
    /// `duration` seconds; pass `animated: false` to cut instantly.
    public func cameraView(_ view: CameraView, animated: Bool = true, duration: Double = 0.6) {
        cameraRig.requestView(view, animated: animated, duration: duration)
    }

    /// Return the camera to the sketch's opening framing (its center, distance, and
    /// angle), as set by the first `cameraShowcase`/`cameraControl`/`cameraMove`
    /// call. Sugar for `cameraView(.reset)`.
    public func resetCamera(animated: Bool = true, duration: Double = 0.6) {
        cameraView(.reset, animated: animated, duration: duration)
    }

    // MARK: 3D scene inspection chrome (live-only, never exported)

    /// Show the orientation axis: a small interactive indicator, drawn over the
    /// canvas, of which way the 3D scene is oriented. Click an axis to snap the
    /// camera to look down it; its controls also reset the view, frame an
    /// isometric angle, and switch between perspective and orthographic. It is a
    /// debugging aid for keeping your bearings in a 3D sketch, so it is host chrome
    /// and never appears in an export. No effect in a 2D sketch (there is no camera
    /// to orient to). Read live each frame: set it once in `setup()` for a fixed
    /// choice, or in `draw()` to toggle it (e.g. on a key).
    public func cameraAxis(_ visible: Bool = true) { showsCameraAxis = visible }

    /// Show the ground grid: a faint reference plane of lines at y = 0 that the
    /// scene sits on, for reading scale and placement while building. Like the
    /// orientation axis it is a debugging aid, so it draws only in the live window
    /// and never in an export. No effect in a 2D sketch. Read live each frame.
    public func groundGrid(_ visible: Bool = true) { showsGroundGrid = visible }

    /// Whether the orientation axis / ground grid are showing, read by the host
    /// each frame. Internal; the public surface is `cameraAxis(_:)`/`groundGrid(_:)`.
    var showsCameraAxis = false
    var showsGroundGrid = false

    /// Draw a 3D `PointCloud` as camera-facing disc splats through the active
    /// camera (set one first with `camera`/`perspective`/`ortho`). Splats are sized
    /// in world units, so perspective shrinks distant points; they composite in
    /// draw order and under the active blend mode (`.add` sums them as light). A
    /// no-op without a camera.
    public func drawPointCloud(_ cloud: PointCloud) { drawer.drawPointCloud(cloud) }

    // MARK: 3D — lights & materials

    /// Add a `Light` to this frame's 3D scene. Lights are per-frame, like the
    /// camera — set them each `draw()`. Solid meshes drawn after shade through a
    /// Blinn-Phong material whose surface color is the current `fill`.
    public func light(_ light: Light) { drawer.addLight(light) }

    /// Add a directional light (parallel rays, like the sun). `direction` is the way
    /// the light travels — `Vector3(0, -1, 0)` shines straight down. `specular` (default
    /// `nil` = `color`) tints its highlight; `softness` (`0…1`) wraps the terminator for
    /// a gentler shaded edge.
    public func directionalLight(_ color: Color, direction: Vector3, intensity: Double = 1,
                                 specular: Color? = nil, softness: Double = 0,
                                 castsShadow: Bool = true) {
        drawer.addLight(.directional(color, direction: direction, intensity: intensity,
                                     specular: specular, softness: softness,
                                     castsShadow: castsShadow))
    }

    /// Add a point light: an omnidirectional source at a world position. `specular`
    /// (default `nil` = `color`) tints its highlight; `softness` (`0…1`) softens the
    /// terminator. An IES `profile` shapes the falloff by angle, aimed along `axis`
    /// (the fixture's hanging direction, straight down by default) and spun about
    /// it by `roll`.
    public func pointLight(_ color: Color, at position: Vector3, intensity: Double = 1,
                           specular: Color? = nil, softness: Double = 0,
                           profile: IESProfile? = nil,
                           axis: Vector3 = Vector3(0, -1, 0), roll: Double = 0,
                           castsShadow: Bool = true) {
        drawer.addLight(.point(color, at: position, intensity: intensity,
                               specular: specular, softness: softness,
                               profile: profile, axis: axis, roll: roll,
                               castsShadow: castsShadow))
    }

    /// Add a spot light: a point source at `position` aimed along `direction`,
    /// narrowed to a cone of full angle `angle` (radians) with a `penumbra` soft
    /// edge (`0` hard … `1` very soft). `specular` (default `nil` = `color`) tints its
    /// highlight; `softness` (`0…1`) softens the terminator. An IES `profile`
    /// shapes the throw inside the cone, a `cookie` projects an image through it
    /// (a gobo, a gel), and `roll` spins both about the beam.
    public func spotLight(_ color: Color, at position: Vector3, direction: Vector3,
                          angle: Double = .pi / 6, penumbra: Double = 0.2, intensity: Double = 1,
                          specular: Color? = nil, softness: Double = 0,
                          profile: IESProfile? = nil, cookie: LightCookie? = nil,
                          roll: Double = 0, castsShadow: Bool = true) {
        drawer.addLight(.spot(color, at: position, direction: direction,
                              angle: angle, penumbra: penumbra, intensity: intensity,
                              specular: specular, softness: softness,
                              profile: profile, cookie: cookie, roll: roll,
                              castsShadow: castsShadow))
    }

    /// Add a rect area light: a glowing `width` × `height` panel centered at `position`,
    /// facing along `direction` (its travel direction, like a spot's axis), the height
    /// axis oriented by the `up` hint. A panel shades like studio lighting: highlights
    /// stretch into its reflection, shading softens with its size, and brightness falls
    /// off with distance (`color` × `intensity` is the panel's radiance, so a bigger
    /// panel casts more light). `twoSided` makes both faces emit.
    public func rectLight(_ color: Color, at position: Vector3, direction: Vector3,
                          width: Double, height: Double, up: Vector3 = .unitY,
                          twoSided: Bool = false, intensity: Double = 1,
                          specular: Color? = nil, castsShadow: Bool = true) {
        drawer.addLight(.rect(color, at: position, direction: direction,
                              width: width, height: height, up: up,
                              twoSided: twoSided, intensity: intensity, specular: specular,
                              castsShadow: castsShadow))
    }

    /// Add a disk area light: a glowing circular panel of `radius` centered at
    /// `position`, facing along `direction` (a ring light's face, a recessed ceiling
    /// can). Shades and falls off like the rect panel; `twoSided` makes both faces emit.
    public func diskLight(_ color: Color, at position: Vector3, direction: Vector3,
                          radius: Double, twoSided: Bool = false, intensity: Double = 1,
                          specular: Color? = nil, castsShadow: Bool = true) {
        drawer.addLight(.disk(color, at: position, direction: direction,
                              radius: radius, twoSided: twoSided,
                              intensity: intensity, specular: specular,
                              castsShadow: castsShadow))
    }

    /// Add a tube area light: a glowing cylinder of `radius` running `from` one point
    /// `to` another (a fluorescent or neon tube), emitting radially all around.
    /// `color` × `intensity` is the tube surface's radiance, so a thin tube wants a
    /// high intensity (a real neon is a very bright surface).
    public func tubeLight(_ color: Color, from: Vector3, to: Vector3,
                          radius: Double = 0.1, intensity: Double = 1,
                          specular: Color? = nil) {
        drawer.addLight(.tube(color, from: from, to: to, radius: radius,
                              intensity: intensity, specular: specular))
    }

    /// Set the ambient light — a flat term added to every lit surface, so the side
    /// facing away from the lights isn't pure black. Setting an ambient alone also
    /// counts as lighting the scene (a flat, unshaded fill of the surface color).
    public func ambientLight(_ color: Color) { drawer.ambientLight(color) }

    /// Stamp a `Decal` onto the 3D scene: a projection box centered at `position`,
    /// `width x height` across and `depth` deep along `direction`, and every solid,
    /// textured, or mapped mesh surface inside it receives the picture, composited
    /// over its base color before lighting (the stamp is shaded as paint, taking
    /// the surface's own finish). Per-frame state like a light, so place it each
    /// `draw()`; move `position` and it slides across the scene.
    ///
    /// ```swift
    /// decal(sticker, at: Vector3(0, 120, 0), width: 140)          // stamps down onto the floor
    /// decal(poster, at: wall, direction: Vector3(0, 0, -1), width: 300)
    /// ```
    ///
    /// `height` defaults to the picture's own proportions, `depth` to the smaller
    /// of the two sides; `roll` spins the picture about the projection axis, and a
    /// later decal composites over an earlier one. Surfaces turned edge-on to the
    /// projection fade the stamp out rather than smearing it. Up to 8 decals per
    /// frame; wireframe and matcap surfaces, point clouds, and raymarched fields
    /// don't receive them.
    public func decal(_ decal: Decal, at position: Vector3,
                      direction: Vector3 = Vector3(0, -1, 0),
                      width: Double, height: Double? = nil, depth: Double? = nil,
                      roll: Double = 0, opacity: Double = 1) {
        drawer.placeDecal(decal, at: position, direction: direction, width: width,
                          height: height, depth: depth, roll: roll, opacity: opacity)
    }

    /// Light this frame's scene with a ready-made `LightingPreset` — `.threePoint`,
    /// `.goldenHour`, `.noir`, `.studio`, `.moonlight`, or `.standard` — in one call
    /// instead of placing lights by hand. Per-frame state like the individual light
    /// calls (it replaces the auto-lit default), so call it in `draw()`. Pass your own
    /// `LightingPreset(ambient:lights:)`, or a tweaked copy of a built-in, to extend
    /// the set.
    public func lightingPreset(_ preset: LightingPreset) {
        drawer.ambientLight(preset.ambient)
        for light in preset.lights { drawer.addLight(light) }
    }

    /// Install the default lighting rig explicitly — `LightingPreset.standard`, a soft
    /// ambient plus a key and a dimmer fill. This is the same rig solids get
    /// automatically when no light is set, so you only need it to *restore* the default
    /// after using your own lights, or to make the intent visible in a sketch.
    public func lights() { lightingPreset(.standard) }

    /// Turn off lighting for this frame: solids draw flat in their `fill` color
    /// (unlit), overriding the auto-lit default.
    public func noLights() { drawer.noLights() }

    /// Light this frame through an image-based-lighting `Environment` — a bundled CC0
    /// HDRI (`.studio`, `.sunset`, `.day`, …), your own (`Environment.hdri(path:)`), or a
    /// procedural `.sky()`. Physically-based materials (`material(.metal…)`) gather their
    /// ambient and reflections from it, so metals read as metal. It adds to any
    /// `directionalLight`/`pointLight`/`spotLight` you set; with no other lights, the
    /// environment alone lights the scene. Per-frame state like the lights, so call it in
    /// `draw()`; the renderer bakes its lighting maps once and caches them.
    public func environment(_ environment: Environment) { drawer.environment(environment) }

    /// Clear the image-based-lighting environment for this frame (the default).
    public func noEnvironment() { drawer.noEnvironment() }

    /// Set the material's specular highlight strength (`0` matte, the default;
    /// `~0.5` glossy). Drawing state, saved by `withState`.
    public func specular(_ strength: Double) { drawer.specular(strength) }

    /// Set the material's Blinn-Phong shininess exponent — higher is a tighter,
    /// sharper highlight (default `32`). Drawing state, saved by `withState`.
    public func shininess(_ exponent: Double) { drawer.shininess(exponent) }

    /// Give subsequent meshes a whole `Material` finish at once — its specular,
    /// shininess, and any iridescence — instead of setting those knobs one by one.
    /// The surface *color* stays the current `fill`. Reach for a built-in
    /// (`.clay`, `.plastic`, `.glossy`, `.soapBubble`, …) or build/tweak your own.
    /// Drawing state, saved by `withState`.
    public func material(_ material: Material) { drawer.material(material) }

    /// Draw subsequent meshes as a wireframe (their triangle edges only, the faces
    /// see-through) instead of filled, lit surfaces. The edges take the current
    /// `stroke` color (or `fill` if no stroke) and `strokeWeight`. Pass `false` to go
    /// back to solid. Drawing state, saved by `withState`. Works on any mesh (a
    /// generated primitive or a loaded model).
    public func wireframe(_ on: Bool = true) { drawer.wireframe(on) }

    /// Wrap subsequent meshes in a *matcap* — a sphere texture (`Matcap.chrome`, any
    /// matcap `Image`, or a `Matcap.shaded(…)`) sampled by the view-space normal — so
    /// the whole look comes from the image and the scene lights and `material(_:)` are
    /// bypassed. Tinted by the current `fill` (`.white` shows it as-is). `noMatcap()`
    /// returns to the lit material path. Drawing state, saved by `withState`.
    public func matcap(_ image: Image?) { drawer.matcap(image) }

    /// Wrap subsequent meshes in a built-in or generated `Matcap` — `matcap(.chrome)`,
    /// `matcap(Matcap.shaded(baseColor: .teal))`, … — the same shape as `material(_:)`.
    /// The look comes entirely from the matcap; the scene lights and `material(_:)` are
    /// bypassed. Tinted by the current `fill`. Drawing state, saved by `withState`.
    public func matcap(_ matcap: Matcap) { drawer.matcap(matcap) }

    /// Stop matcap shading — subsequent meshes light through the normal material model.
    public func noMatcap() { drawer.noMatcap() }

    /// Cast shadows this frame from the scene's primary caster, so solids drop shadows
    /// onto a floor and onto one another. The caster is the first directional light or,
    /// if the scene has none, the first spot light. Per-frame state like the lights and
    /// camera, so call it in `draw()`, after setting a camera and at least one directional
    /// or spot light (`directionalLight`/`spotLight`/`lights()`); it's a no-op
    /// otherwise. The shadow frustum auto-fits the scene around the camera target. Pass
    /// `false`, or call `noShadows()`, to turn shadows back off.
    public func castShadows(_ on: Bool = true) { on ? drawer.castShadows() : drawer.noShadows() }

    /// Stop casting shadows (the default).
    public func noShadows() { drawer.noShadows() }

    /// Add contact shadows this frame: a short screen-space ray marched from each mesh
    /// pixel toward the casting light through the scene's own depth, darkening the fine
    /// seam where a shadow map's resolution and bias leave a resting object floating.
    /// A refinement over `castShadows()`, which picks the caster; call both in `draw()`
    /// (a no-op without a caster or a camera). `length` is the ray's reach in world
    /// units; leave it nil to derive a short reach from the scene scale. Works with
    /// every caster kind on any Metal GPU, and only what the camera sees can occlude
    /// (the screen-space envelope). Pass `false`, or call `noContactShadows()`, to
    /// turn it back off.
    public func contactShadows(_ on: Bool = true, length: Double? = nil) {
        on ? drawer.contactShadows(length: length) : drawer.noContactShadows()
    }

    /// Stop adding contact shadows (the default).
    public func noContactShadows() { drawer.noContactShadows() }

    /// Ray-trace reflections of the scene off its physically-based (metallic-roughness)
    /// surfaces this frame, so a metal mirrors the *actual scene around it*: other meshes,
    /// the floor, even geometry off the edge of the screen, instead of only its environment.
    /// This is the clean, artifact-free reflection: it traces the real geometry, so there are
    /// none of screen-space reflection's contact-edge streaks or off-screen cutoffs. Per-frame
    /// state like the lights and camera, so call it in `draw()`. Needs a ray-tracing GPU (Apple
    /// silicon) and an `environment(_:)` (a metal reflects its environment where a ray leaves
    /// the scene); every solid mesh in the frame reflects. A no-op without those: the
    /// environment reflection remains. Pass `false` to turn it back off.
    public func rayTracedReflections(_ on: Bool = true) { drawer.rayTracedReflections(on) }

    /// Gather real-time global illumination this frame, so light *bounces*: a red wall
    /// tints the white floor beside it, a bright floor fills in an overhang's shadow, and
    /// a room lit through a doorway glows with light the sun never touches directly. The
    /// renderer keeps a grid of light probes over the scene, re-traces them every frame
    /// against the actual geometry (so moving shapes and moving lights keep bouncing
    /// correctly), and every lit surface adds the bounce light the probes saw. With an
    /// `environment(_:)` the probes also carry sky light into the scene, occlusion
    /// included. `intensity` scales the bounce (1 = physical; higher is an artistic
    /// crank). Per-frame state like the lights and camera, so call it in `draw()`, after
    /// the camera and lights. Needs a ray-tracing GPU (Apple silicon); a no-op otherwise.
    /// Pass `false`, or call `noGlobalIllumination()`, to turn it back off.
    public func globalIllumination(_ on: Bool = true, intensity: Double = 1) {
        on ? drawer.globalIllumination(true, intensity: intensity) : drawer.noGlobalIllumination()
    }

    /// Stop gathering global illumination (the default).
    public func noGlobalIllumination() { drawer.noGlobalIllumination() }

    /// Render caustics this frame: the focused light a glass or a polished metal
    /// throws onto the surfaces around it (the bright loop under a wine glass, the
    /// dancing net beside a chrome ring, the colored spill through a stained pane).
    /// The renderer traces photons from the light through every transmissive
    /// (`Material.glass`) and mirror-polished metallic surface, follows each one
    /// through up to eight reflections and refractions, and draws where it lands as
    /// a small elliptical spot whose shape comes from how the path focused, so the
    /// patterns stay sharp without noise. Emission adapts frame to frame: photons
    /// concentrate where the pattern is detailed or still flickering, and spread out
    /// where it is smooth. `intensity` scales the brightness (1 = physical);
    /// `dispersion` splits refracted light by wavelength for prism rainbows (0 =
    /// none, 1 = full split). The caster light follows the shadow system's priority
    /// (directional first, then spot, then point). Per-frame state like the lights
    /// and camera, so call it in `draw()` after both. Needs a ray-tracing GPU
    /// (Apple silicon), a camera, and a light; a no-op otherwise, and inert while
    /// no material transmits or mirrors. Call `noCaustics()` to turn it back off.
    public func caustics(intensity: Double = 1, dispersion: Double = 0) {
        drawer.caustics(intensity: intensity, dispersion: dispersion)
    }

    /// Stop rendering caustics (the default).
    public func noCaustics() { drawer.noCaustics() }

    /// Temporally anti-alias the 3D scene this frame, refining edges past what MSAA
    /// alone reaches: the renderer nudges the camera's projection by a sub-pixel
    /// offset that changes every frame and folds the resolved frames into a running
    /// average, so a high-contrast silhouette or a thin bright edge settles into a
    /// clean gradient instead of a fixed stair-step, and the residual shimmer of the
    /// screen-space and traced effects calms with it. Exports and snapshots stay
    /// deterministic: a headless frame renders the scene several times at the same
    /// fixed offsets and averages them within the frame, so a video cannot flicker
    /// and two exports of one frame are byte-identical. Per-frame state like the
    /// lights and camera, so call it in `draw()` after the camera; it applies to the
    /// main canvas (not layers or the accumulation surface) and needs an active 3D
    /// camera (a 2D frame is already analytically anti-aliased). Works on any Metal
    /// GPU. Pass `false`, or call `noTemporalAntialiasing()`, to turn it back off.
    public func temporalAntialiasing(_ on: Bool = true) { drawer.temporalAntialiasing(on) }

    /// Stop temporally anti-aliasing (the default).
    public func noTemporalAntialiasing() { drawer.noTemporalAntialiasing() }

    /// Temporally upscale the 3D scene this frame: the live window renders the
    /// whole canvas at a reduced resolution and reconstructs the full-size frame
    /// from the sub-pixel-jittered history, so a heavy scene keeps its frame rate
    /// (or spends the headroom on richer content) while edges stay temporally
    /// anti-aliased. `quality` picks the render fraction: `.performance` renders
    /// at half size, `.default` at two-thirds, `.detail` at three-quarters, each
    /// clamped to what the GPU supports. Movers declared with `withMotion { }`
    /// reconstruct exactly, like temporal AA. Exports, snapshots, and frame grabs
    /// never upscale: the headless path renders at full resolution with the
    /// deterministic temporal-AA supersample, so what you keep is always full
    /// quality and byte-stable, and what you see live is the fast preview of it.
    /// Per-frame state like the lights and camera, so call it in `draw()` after
    /// the camera; it applies to the main canvas (not layers or the accumulation
    /// surface), needs an active 3D camera, and needs a GPU with temporal-scaling
    /// support (Apple silicon; elsewhere the frame renders normally with a
    /// one-time note). Call `noTemporalUpscaling()` to turn it back off.
    public func temporalUpscaling(_ quality: RenderQuality = .default) {
        drawer.temporalUpscaling(quality)
    }

    /// Stop temporally upscaling (the default).
    public func noTemporalUpscaling() { drawer.noTemporalUpscaling() }

    /// Motion-blur the 3D scene this frame, the cinematic streak a real camera's
    /// open shutter leaves: each pixel smears along its own screen motion, with
    /// camera movement read from the depth buffer (so panning past a still scene
    /// streaks the whole frame) and per-object movement from the same
    /// `withMotion { }` blocks temporal AA uses (so a mesh flying through a still
    /// frame streaks alone, exactly along its path). `shutter` is the fraction of
    /// a frame interval the virtual shutter stays open: the 0.5 default is the
    /// film-standard 180-degree shutter, smaller values are crisper, 1 smears a
    /// full frame of travel, and values past 1 overdrive the streak for effect.
    /// Exports carry it deterministically (frame k reads the motion from frame
    /// k-1's camera and movers, so a video export streaks exactly like the live
    /// window and two exports of one frame are byte-identical). Per-frame state
    /// like the lights and camera, so call it in `draw()` after the camera; it
    /// applies to the main canvas (not layers or the accumulation surface), needs
    /// an active 3D camera, and does nothing on the very first frame (nothing has
    /// moved yet). The environment backdrop and 2D drawing hold still by design.
    /// Works on any Metal GPU. Call `noMotionBlur()` to turn it back off.
    public func motionBlur(shutter: Double = 0.5) { drawer.motionBlur(shutter: shutter) }

    /// Stop motion-blurring (the default).
    public func noMotionBlur() { drawer.noMotionBlur() }

    /// Let the camera flare on the frame's bright lights.
    ///
    /// Everything else the renderer draws is the light and the surface. A flare is
    /// neither: it is the *camera* misbehaving. Some of a bright source reflects off
    /// the lens's own interfaces instead of passing through them and lands on the
    /// sensor in the wrong place, which is what strings ghosts along the line from
    /// the source through the middle of the frame. Which ghosts appear, where they
    /// sit, how big they are and what color they are all follow from the lens, so
    /// this asks for a lens rather than for a look.
    ///
    /// It composites in linear light before the tone map, beside a bloom, because a
    /// flare is light in the camera and not paint on the picture. Its strength
    /// follows how much of each source the camera can actually *see*, so something
    /// passing in front of a light fades its flare rather than switching it off.
    ///
    /// Per-frame state like the lights and camera, so call it in `draw()`. It needs
    /// a perspective 3D camera and at least one light, and it does nothing without
    /// them. `LensFlare.strength` is the honesty dial: a flare is a lens defect, and
    /// a piece may want it in small measure or not at all. Works on any Metal GPU.
    /// Call `noLensFlare()` to turn it back off.
    public func lensFlare(_ flare: LensFlare = LensFlare()) { drawer.lensFlare(flare) }

    /// Flare on the frame's bright lights, naming just the two things most worth
    /// changing: how strong it is, and which lens makes it.
    public func lensFlare(strength: Double, lens: Lens = .heliar) {
        drawer.lensFlare(LensFlare(lens: lens, strength: strength))
    }

    /// Stop flaring (the default).
    public func noLensFlare() { drawer.noLensFlare() }

    /// Set the global-illumination quality (how many rays each light probe traces per
    /// update) as a **hardware-relative** tier, the `shadowQuality` dial's GI sibling:
    /// `.performance` favors frame rate with a grainier, slower-converging bounce,
    /// `.detail` traces more rays for a smoother one, and `.default` is the balanced
    /// choice for the GPU (lifted to `.detail` automatically on `--export`/headless,
    /// where it also deepens the in-frame convergence). The probe grid itself stays the
    /// same size on every tier, so the light field's structure never shifts between
    /// tiers, only how finely it is sampled. A persistent setting; set it once in
    /// `setup()` or `draw()`. Read only while `globalIllumination()` is on.
    public func globalIlluminationQuality(_ quality: RenderQuality = .default) {
        drawer.globalIlluminationQuality(quality)
    }

    /// Set the soft-shadow quality (how many rays the ray-traced point caster traces per
    /// pixel) as a **hardware-relative** tier: the dial to trade frame rate for nicer
    /// shadows. The tier scales with the GPU, like a game's quality presets: `.default` is
    /// the frame-rate-safe choice on a software-ray-tracing GPU (M1/M2) and a richer one on
    /// a hardware-RT GPU (M3 and up), so better hardware lifts your shadows with no code
    /// change; `.detail` shifts up from there, `.performance` down. A persistent setting;
    /// set it once in `setup()` or `draw()`. Only the ray-traced point path reads it;
    /// directional/spot shadows and the non-RT cube fallback are unaffected.
    public func shadowQuality(_ quality: RenderQuality = .default) { drawer.shadowQuality(quality) }

    /// How finely [ray-traced reflections](../../Docs/3D/3D.md#rt-reflections) are traced.
    /// The reflection layer traces one ray per pixel of the drawable, which is most of what
    /// a reflective frame costs. `.performance` halves the layer in each direction, so the
    /// trace does a quarter of the work and the surfaces read it scaled back up. The picture
    /// pays for it twice. A curved mirror quantizes, since one traced ray now serves four
    /// screen pixels facing different ways. And a mirror reads a little weaker, since the
    /// layer's hit coverage smears at every silhouette. `.default` and `.detail` keep the
    /// layer full size. A persistent setting; set it once in `setup()` or `draw()`. An
    /// export resolves `.default` up to `.detail`, so exported art keeps the full-size
    /// layer unless you ask for `.performance` outright.
    public func reflectionQuality(_ quality: RenderQuality = .default) {
        drawer.reflectionQuality(quality)
    }

    /// How many surfaces a [ray-traced reflection](../../Docs/3D/3D.md#rt-reflections)
    /// may shade along one chain. The default of 2 is a mirror and what that mirror sees:
    /// the reflected surface, and *its* own reflection, which ends at the environment.
    /// That is enough for a single mirror, and it is what keeps a polished corner honest.
    /// Two mirrors facing each other need more: at 2 the tunnel of images stops at the
    /// third door and shows the environment instead, and every step you add opens one more
    /// door. Raise it for a hall of mirrors, a mirrored box, or a metal room. Each step
    /// costs another traced ray per reflected pixel, and the images dim quickly, so 3 or 4
    /// is usually all you can see. Clamped to 2…8. A persistent setting; set it once in
    /// `setup()` or `draw()`. Read only where `rayTracedReflections()` is on.
    public func reflectionBounces(_ count: Int = 2) { drawer.reflectionBounces(count) }

    /// Set the soft-shadow ray count to an **exact** value (1…64), the hardware-independent
    /// alternative to `shadowQuality` — for fine control, pushing past the presets on a fast
    /// GPU, or a render that should look identical across machines. Persistent.
    public func shadowSamples(_ count: Int) { drawer.shadowSamples(count) }

    /// Set the caustics quality (how many photons each frame traces, and how finely
    /// the emission map steers them) as a **hardware-relative** tier, the
    /// `shadowQuality` dial's caustics sibling: `.performance` favors frame rate
    /// with a coarser pattern, `.detail` traces more photons for a finer one, and
    /// `.default` is the balanced choice for the GPU (lifted to `.detail`
    /// automatically on `--export`/headless). A persistent setting; set it once in
    /// `setup()` or `draw()`. Read only while `caustics()` is on.
    public func causticsQuality(_ quality: RenderQuality = .default) {
        drawer.causticsQuality(quality)
    }

    /// Set how **soft** a cast shadow's penumbra is, 0…1 (the contact-hardening dial). `0` is a
    /// hard edge (the classic shadow look); the `0.5` default sharpens the shadow where an object
    /// meets a surface and blurs it as it falls away (physically plausible soft shadows); `1` is
    /// very soft. It softens the directional and spot casters (a variable-kernel filter on their
    /// shadow maps) **and** the ray-traced point caster's area light, so one knob controls every
    /// shadow kind. A persistent setting; set it once in `setup()` or `draw()`.
    public func shadowSoftness(_ amount: Double = 0.5) { drawer.shadowSoftness(amount) }

    /// Set the raymarched-SDF (`drawSDF3D`) quality: the dial to trade fidelity for frame rate
    /// on the fullscreen sphere-tracer, whose cost is bound to the pixels the field covers. It
    /// sets the internal resolution the field is traced at (a depth-preserving upsample
    /// composites it back to the window): `.detail` traces at full resolution, `.default` at a
    /// half-resolution **budget** (¼ the pixels, the out-of-the-box choice that keeps a busy
    /// field smooth), `.performance` at a quarter-resolution budget (1/16 the pixels, for the
    /// heaviest fields). The budget is **coverage-adaptive**: it applies in full when the field
    /// fills the screen, and a field covering less of it (a dollied-out camera) is traced
    /// denser, up to full resolution, for the same marched-pixel cost, so zooming out never
    /// dissolves the surface into upsampled blur. With the automatic `.default`, `--export` and
    /// headless renders trace at full resolution, so exported art is never downscaled. A
    /// persistent setting, set once in `setup()` or `draw()`. Only `drawSDF3D` reads it;
    /// rasterized meshes and the 2D path are unaffected.
    public func raymarchQuality(_ quality: RenderQuality = .default) { drawer.raymarchQuality(quality) }

    /// Set the raymarched-SDF camera-march step count to an **exact** value (16…512), the
    /// hardware-independent alternative to `raymarchQuality`: more steps resolve a deeper or
    /// more intricate field, fewer run faster. Always full resolution (the resolution scaling is
    /// the `raymarchQuality` *tiers*). Persistent.
    public func raymarchSteps(_ count: Int) { drawer.raymarchSteps(count) }

    /// Set the raymarched-SDF resolution budget to an **exact fraction** (0.1…1.0): the
    /// custom-percentage alternative to the `raymarchQuality` tiers (which are 1.0 / 0.5 / 0.25),
    /// e.g. `raymarchResolution(0.75)` traces the field at 75% resolution when it fills the
    /// screen. Like the tiers it is **coverage-adaptive**: a field covering less of the screen
    /// is traced denser, up to full resolution, at the same marched-pixel cost, so a
    /// dollied-out field stays crisp. A depth-preserving upsample composites the trace back
    /// (meshes still occlude it). Unlike the automatic tier default, an explicit fraction is
    /// honored on `--export` too. Persistent.
    public func raymarchResolution(_ fraction: Double) { drawer.raymarchResolution(fraction) }

    // MARK: 3D atmosphere (fog & volumetric light)

    /// Wrap this frame's 3D scene in fog: every surface fades toward the fog color with
    /// distance, and the air itself washes over the backdrop, so depth reads at a glance
    /// and far geometry recedes into atmosphere. `density` is how thick the air is (in
    /// inverse world units: at the 0.08 default a surface ~9 units away reads about half
    /// fog; double it for soup, halve it for haze). A `heightFalloff` above 0 thins the
    /// fog with altitude (`density · e^(−falloff·height)`), the low-lying morning-mist
    /// look: ground stays wrapped while peaks rise clear. Per-frame state like the
    /// lights and camera, so call it in `draw()`; `noFog()` turns it back off. 2D
    /// drawing never fogs. Pairs with `volumetricLight()` to make the beams in the air
    /// visible too.
    public func fog(_ color: Color, density: Double = 0.08, heightFalloff: Double = 0) {
        drawer.fog(color, density: density, heightFalloff: heightFalloff)
    }

    /// Clear the fog (the default).
    public func noFog() { drawer.noFog() }

    /// Wrap this frame's 3D scene in **aerial perspective**: fog's physical cousin, the
    /// depth cue that sells scale outdoors. The air's extinction is split by wavelength
    /// (short wavelengths scatter out first, so a far silhouette warms and desaturates)
    /// while the sun's light scatters *into* the view path (blue looking across the
    /// scene, brighter and whiter looking toward the sun), so distant geometry recedes
    /// into the sky instead of into a flat color. `density` is the optical depth per
    /// world unit, like fog's; leave it nil and it derives from the camera framing so a
    /// bare call reads alike at any scene scale. `haziness` (0…1) is how much of the
    /// air is aerosol: 0 the crisp molecular blue-shift, 1 a gray haze with a strong
    /// halo around the sun. `heightFalloff` thins the air with altitude, as in `fog`.
    /// `sun` points **toward** the sun; leave it nil to follow the `.sky` environment
    /// (rotation included), else the first directional light, else a default elevation.
    /// Replaces `fog` (the last call wins); `volumetricLight()` beams ride it the same
    /// way. Per-frame state, so call it in `draw()`; `noAerialPerspective()` turns it
    /// back off. 2D drawing is never touched.
    public func aerialPerspective(density: Double? = nil, haziness: Double = 0.3,
                                  heightFalloff: Double = 0, sun: Vector3? = nil) {
        drawer.aerialPerspective(density: density, haziness: haziness,
                                 heightFalloff: heightFalloff, sun: sun)
    }

    /// Turn aerial perspective back off (the default).
    public func noAerialPerspective() { drawer.noAerialPerspective() }

    /// Make this frame's directional and spot lights visible **in the air**: a per-pixel
    /// march accumulates the light scattered toward the eye, so a spot's cone becomes a
    /// stage beam, a cookie projects lace through the haze, an IES profile's throw shows
    /// its real shape, and (with `castShadows()`) occluders carve crepuscular light
    /// shafts. `amount` scales the glow; `anisotropy` (−1…1) is how strongly the medium
    /// scatters forward: near 1 the beams flare when you look toward the light, 0 glows
    /// evenly from every angle. Works with or without `fog(_:density:heightFalloff:)`:
    /// alone, the air stays clear and only the beams appear (the dark-stage look); with
    /// fog, the beams ride its density and color. Directional and spot lights
    /// participate; point and area lights light surfaces only. Per-frame state, so call
    /// it in `draw()`; `noVolumetricLight()` turns it back off.
    public func volumetricLight(_ amount: Double = 1, anisotropy: Double = 0.5) {
        drawer.volumetricLight(amount, anisotropy: anisotropy)
    }

    /// Turn the volumetric march back off (the default).
    public func noVolumetricLight() { drawer.noVolumetricLight() }

    /// Set the volumetric march's quality tier: the step count along each view ray
    /// (`.performance` 16, `.default` 32, `.detail` 64). With the automatic `.default`,
    /// `--export` and headless renders resolve to `.detail`, so exported beams are never
    /// steppier than the live window. A persistent setting, set once in `setup()` or
    /// `draw()`.
    public func volumetricQuality(_ quality: RenderQuality = .default) { drawer.volumetricQuality(quality) }

    /// Set the volumetric march's step count to an **exact** value (8…128), the
    /// hardware-independent alternative to `volumetricQuality`. Persistent.
    public func volumetricSteps(_ count: Int) { drawer.volumetricSteps(count) }

    // MARK: 3D — solid primitives & meshes

    /// Draw a solid 3D `Mesh` through the active camera with depth testing (set a
    /// camera first with `camera`/`perspective`/`ortho`). The mesh rides the 3D
    /// transform stack — `translate`/`rotate`/`scale` place and orient it — and takes
    /// the current `fill` color: flat (unlit) with no lights, Blinn-Phong shaded once
    /// you add a light (`lights()`, `directionalLight`, …). A no-op without a camera.
    /// The primitive calls below are sugar over this.
    public func drawMesh(_ mesh: Mesh) { drawer.drawMesh(mesh) }

    /// Draw `mesh` once per placement in `instances`, as one instanced GPU draw:
    /// the mesh uploads once and the GPU places every copy, so a field of
    /// thousands costs one draw call. Each `MeshInstance` gives a copy its
    /// position, rotation, scale, and an optional tint; copies shade exactly
    /// like solid meshes (the current `fill` and `material(_:)` finish, lights,
    /// shadows received, image-based lighting, fog) and cast into the shadow
    /// maps. They stand in the ray-traced scene as well, so a mirror shows them
    /// and a traced shadow falls from them. The transform stack moves the whole
    /// field together. Copies draw on the solid lit path: textures, wireframe,
    /// and matcap don't apply to them yet. A no-op without a camera.
    public func drawMesh(_ mesh: Mesh, instances: [MeshInstance]) {
        drawer.drawMeshInstanced(mesh, instances: instances)
    }

    /// The GPU-resident sibling: draw `count` copies (defaulting to the buffer's
    /// element count) whose `OllinMeshInstance` placements live in a compute
    /// buffer a kernel writes, so a simulation can move a hundred thousand
    /// copies without the positions ever visiting the CPU. The matrices are
    /// absolute world space (the kernel owns the placement, so the transform
    /// stack is not composed on top); `color` multiplies the surface color.
    /// These copies stand in the ray-traced scene too, at roughly two
    /// microseconds of GPU time each per frame while a traced pass is on.
    public func drawMesh(_ mesh: Mesh, instances: ComputeBuffer<OllinMeshInstance>,
                         count: Int? = nil) {
        drawer.drawMeshInstanced(mesh, instanceBuffer: instances, count: count ?? instances.count)
    }

    /// Draw a retained `MeshField`: a whole world of placed meshes in ONE call,
    /// every frame, with the GPU deciding per copy what the camera can see.
    /// Build the field in `setup()` (`field.place(mesh, at: copies)`), hold it,
    /// and draw it here; the transform stack moves the whole field, and copies
    /// out of view cost (almost) nothing. A field also stands in the ray-traced
    /// scene, up to its `tracedCopyBudget`. Once per frame per field; a no-op
    /// without a camera.
    public func drawMeshField(_ field: MeshField) { drawer.drawMeshField(field) }

    /// Draw a `StrandField`: a patch of grass-like blades the GPU grows inside
    /// the draw call itself. No geometry exists anywhere (no vertex, index, or
    /// instance buffer); the camera decides per tile what to skip and how much
    /// detail distant blades deserve, and every blade sways on the sketch
    /// clock. Blades shade like solid meshes (lights, shadows received,
    /// image-based lighting, fog) with the current `material(_:)` finish, and
    /// the transform stack places the patch. A no-op without a camera.
    public func drawStrands(_ field: StrandField) { drawer.drawStrands(field) }

    /// Draw a loaded `Scene`: every node's mesh at its authored place, the node
    /// transforms composed down the tree and onto the 3D transform stack (so
    /// `translate`/`rotate`/`scale` before this call move the whole scene). The
    /// scene's authored cameras and lights are data you apply yourself:
    /// `camera(scene.camera ?? .orbiting(radius: 6))`, then `light(_:)` each of
    /// `scene.lights`. Load one with `loadScene`; a no-op without a camera.
    public func drawScene(_ scene: Scene) { drawer.drawScene(scene) }

    /// Draw a box centered at the model origin, `width` (x) × `height` (y) ×
    /// `depth` (z) world units. Position it with the transform stack.
    public func drawBox(width: Double, height: Double, depth: Double) {
        drawer.drawMeshPrimitive(.box(width: width, height: height, depth: depth),
                                 mesh: .box(width: width, height: height, depth: depth))
    }

    /// Draw a cube centered at the model origin, `size` world units on each edge.
    public func drawBox(size: Double = 1) {
        drawer.drawMeshPrimitive(.box(size: size), mesh: .box(size: size))
    }

    /// Draw a sphere centered at the model origin. `segments` divide it around the
    /// equator, `rings` from pole to pole.
    public func drawSphere(radius: Double = 0.5, segments: Int = 32, rings: Int = 16) {
        drawer.drawMeshPrimitive(.sphere(radius: radius),
                                 mesh: .sphere(radius: radius, segments: segments, rings: rings))
    }

    /// Draw a cylinder centered at the model origin, its axis along y. `caps`
    /// closes the two ends (on by default).
    public func drawCylinder(radius: Double = 0.5, height: Double = 1,
                             segments: Int = 32, caps: Bool = true) {
        drawer.drawMeshPrimitive(.cylinder(radius: radius, height: height),
                                 mesh: .cylinder(radius: radius, height: height, segments: segments, caps: caps))
    }

    /// Draw a flat plane centered at the model origin in the x–z ground plane,
    /// `width` (x) × `depth` (z) world units, facing up (+y). Drawn double-sided.
    public func drawPlane(width: Double = 1, depth: Double = 1, segments: Int = 1) {
        drawer.drawMesh(.plane(width: width, depth: depth, segments: segments))
    }

    /// Draw a torus (ring) centered at the model origin in the x–z plane: `radius`
    /// from the center to the tube's center, `tube` the tube's own radius.
    public func drawTorus(radius: Double = 0.5, tube: Double = 0.2,
                          segments: Int = 48, sides: Int = 24) {
        drawer.drawMeshPrimitive(.torus(radius: radius, tube: tube),
                                 mesh: .torus(radius: radius, tube: tube, segments: segments, sides: sides))
    }

    /// Draw a cone centered at the model origin, its axis along y (base down, apex up).
    public func drawCone(radius: Double = 0.5, height: Double = 1, segments: Int = 32) {
        drawer.drawMeshPrimitive(.cone(radius: radius, height: height),
                                 mesh: .cone(radius: radius, height: height, segments: segments))
    }

    /// Draw a square-base pyramid centered at the model origin, `width` (x) ×
    /// `depth` (z) base rising to an apex. Faceted (flat sides).
    public func drawPyramid(width: Double = 1, depth: Double = 1, height: Double = 1) {
        drawer.drawMesh(.pyramid(width: width, depth: depth, height: height))
    }

    /// Draw a helix (coiled tube) centered at the model origin, its axis along y.
    /// `turns` coils over `height`; `radius` is the coil radius, `tube` the tube's.
    public func drawHelix(radius: Double = 0.5, tube: Double = 0.12, turns: Double = 3,
                          height: Double = 1, segments: Int = 240, sides: Int = 12) {
        drawer.drawMesh(.helix(radius: radius, tube: tube, turns: turns,
                               height: height, segments: segments, sides: sides))
    }

    /// Draw a regular icosahedron (20 faces) centered at the model origin, its
    /// vertices on a sphere of `radius`.
    public func drawIcosahedron(radius: Double = 0.5) {
        drawer.drawMesh(.icosahedron(radius: radius))
    }

    /// Draw a regular dodecahedron (12 faces) centered at the model origin, its
    /// vertices on a sphere of `radius`.
    public func drawDodecahedron(radius: Double = 0.5) {
        drawer.drawMesh(.dodecahedron(radius: radius))
    }

    /// Draw a (p, q) torus knot centered at the model origin: a tube winding `p`
    /// times around the axis and `q` times around the hole (coprime for a true knot).
    public func drawTorusKnot(p: Int = 2, q: Int = 3, radius: Double = 0.5, tube: Double = 0.16,
                              segments: Int = 240, sides: Int = 14) {
        drawer.drawMesh(.torusKnot(p: p, q: q, radius: radius, tube: tube,
                                   segments: segments, sides: sides))
    }

    /// Draw a regular tetrahedron (4 faces) centered at the model origin.
    public func drawTetrahedron(radius: Double = 0.5) { drawer.drawMesh(.tetrahedron(radius: radius)) }

    /// Draw a regular octahedron (8 faces) centered at the model origin.
    public func drawOctahedron(radius: Double = 0.5) {
        drawer.drawMeshPrimitive(.octahedron(radius: radius), mesh: .octahedron(radius: radius))
    }

    /// Draw a capsule (cylinder with hemispherical caps) centered at the model
    /// origin, axis along y. `height` is the straight section (total = height + 2·radius).
    public func drawCapsule(radius: Double = 0.4, height: Double = 0.8,
                            segments: Int = 32, rings: Int = 8) {
        drawer.drawMeshPrimitive(.capsule(radius: radius, height: height),
                                 mesh: .capsule(radius: radius, height: height, segments: segments, rings: rings))
    }

    /// Draw a capsule spanning `from` to `to` end to end, its round tips on the
    /// two points (the straight section shortens by the radius at each end), the
    /// solid way to draw a bone or strut between two 3D points.
    public func drawCapsule(from: Vector3, to: Vector3, radius: Double,
                            segments: Int = 32, rings: Int = 8) {
        drawer.drawCapsule(from: from, to: to, radius: radius, segments: segments, rings: rings)
    }

    /// Draw a box with rounded edges centered at the model origin, the edges
    /// filleted by `radius`. `segments` is the per-face grid resolution.
    public func drawRoundedBox(width: Double = 1, height: Double = 1, depth: Double = 1,
                               radius: Double = 0.15, segments: Int = 20) {
        drawer.drawMeshPrimitive(.roundBox(width: width, height: height, depth: depth, radius: radius),
                                 mesh: .roundedBox(width: width, height: height, depth: depth,
                                                   radius: radius, segments: segments))
    }

    /// Draw a rounded cube `size` on each edge, filleted by `radius`.
    public func drawRoundedBox(size: Double, radius: Double = 0.15, segments: Int = 20) {
        drawer.drawMeshPrimitive(.roundBox(size: size, radius: radius),
                                 mesh: .roundedBox(width: size, height: size, depth: size,
                                                   radius: radius, segments: segments))
    }

    /// Draw a geodesic sphere (subdivided icosahedron) centered at the model origin
    /// — evenly sized triangles, no pole pinching. `subdivisions` sets the detail.
    public func drawIcosphere(radius: Double = 0.5, subdivisions: Int = 2) {
        drawer.drawMesh(.icosphere(radius: radius, subdivisions: subdivisions))
    }

    /// Draw a tube of `radius` swept along a 3D `path` (the helix/knot machinery,
    /// open to any curve). `closed` joins the ends into a loop.
    public func drawTube(_ path: [Vector3], radius: Double = 0.1, sides: Int = 12, closed: Bool = false) {
        drawer.drawMesh(.tube(along: path, radius: radius, sides: sides, closed: closed))
    }

    /// Draw a Möbius strip centered at the model origin — a band with a half-twist.
    public func drawMobius(radius: Double = 0.5, width: Double = 0.3,
                           segments: Int = 140, sides: Int = 12) {
        drawer.drawMesh(.mobius(radius: radius, width: width, segments: segments, sides: sides))
    }

    /// Draw a Klein bottle (figure-8 immersion) centered at the model origin.
    public func drawKlein(scale: Double = 0.22, segments: Int = 100, sides: Int = 40) {
        drawer.drawMesh(.klein(scale: scale, segments: segments, sides: sides))
    }

    /// Draw a superellipsoid centered at the model origin: a sphere that morphs
    /// toward a box (`e → 0`) or octahedron (`e → 2`). `e1` shapes pole-to-pole, `e2`
    /// around the equator.
    public func drawSuperellipsoid(radius: Double = 0.5, e1: Double = 0.5, e2: Double = 0.5,
                                   segments: Int = 64, rings: Int = 32) {
        drawer.drawMesh(.superellipsoid(radius: radius, e1: e1, e2: e2, segments: segments, rings: rings))
    }

    /// Draw a 3D supershape (Gielis superformula) centered at the model origin —
    /// `m` sets the lobe count; `n1`/`n2`/`n3` shape the lobes. A parametric toy.
    public func drawSupershape(radius: Double = 0.5, m: Double = 7, n1: Double = 0.2,
                               n2: Double = 1.7, n3: Double = 1.7,
                               segments: Int = 120, rings: Int = 60) {
        drawer.drawMesh(.supershape(radius: radius, m: m, n1: n1, n2: n2, n3: n3,
                                    segments: segments, rings: rings))
    }

    /// Draw a closed 2D `outline` (x–y plane) extruded `depth` deep along z — a flat
    /// shape pushed into 3D. Pair with the `Profile` helpers (rectangle/ellipse/…).
    public func drawExtrude(_ outline: [Vector2], depth: Double = 0.5) {
        drawer.drawMesh(.extrude(outline, depth: depth))
    }

    /// Draw a 2D `Shape` (x–y plane) extruded `depth` deep along z, honoring holes.
    public func drawExtrude(_ shape: Shape, depth: Double = 0.5) {
        drawer.drawMesh(.extrude(shape, depth: depth))
    }

    /// Draw a surface of revolution by revolving a 2D `silhouette` (x = radius from
    /// the y-axis, y = height) around the y-axis — a vase/bowl from its side profile.
    public func drawLathe(_ silhouette: [Vector2], segments: Int = 48) {
        drawer.drawMesh(.lathe(silhouette, segments: segments))
    }

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

    /// Place subsequent 2D drawing at a normalized scene depth `t` (0 = nearest, 1 =
    /// farthest) — the companion to `depth(at:)` for a [`drawDepthScene`] depth-map
    /// scene that has no 3D camera. A mark at `t` is hidden where the scene is nearer
    /// and drawn over where it's farther. Saved by `withState`.
    public func depth(_ t: Double) { drawer.depth(t) }

    /// Draw a depth scene: `color` as the backdrop and `depth` (a gray map, white =
    /// nearest by default) written into the depth buffer, so 2D drawn afterward at a
    /// normalized `depth(_:)` is occluded by the scene — a sprite hidden behind the
    /// nearer subject in a depth feed. Fills the whole canvas by default. The depth
    /// map and color usually come from the same source (a depth model over a camera
    /// frame, an `RGBDFrame`'s depth and color). Set `whiteIsNear: false` if the map
    /// encodes far as white.
    public func drawDepthScene(color: Image, depth: Image, in rect: Rectangle? = nil,
                               whiteIsNear: Bool = true) {
        drawer.drawDepthScene(color: color, depth: depth,
                              in: rect ?? canvasRectangle, whiteIsNear: whiteIsNear)
    }

    /// Draw a **metric** depth scene from an `RGBDFrame` (a LiDAR or depth-camera
    /// feed): `frame.color` is the backdrop and `frame.depth` (meters) is written
    /// into the depth buffer as true clip-space depth. Unlike the gray-map overload,
    /// this shares one *metric* space with the 3D camera — so a `drawPointCloud` or a
    /// 2D mark placed with `depth(at: Vector3)` at real world coordinates occludes,
    /// and is occluded by, the feed in meters.
    ///
    /// Set a matching camera first — `camera(.fromIntrinsics(frame.intrinsics))` is
    /// the one that aligns with the feed — or this is a no-op (it needs the camera's
    /// near/far). The feed is **letterboxed** into the canvas by its own aspect (no
    /// stretch, whatever the `canvasSize`), and the metric camera letterboxes to
    /// match, so placed 3D geometry lands on the picture. Pass `in rect` only to
    /// move the backdrop; for aligned 3D placement keep the default (the full canvas).
    public func drawDepthScene(_ frame: RGBDFrame, in rect: Rectangle? = nil) {
        drawer.drawDepthScene(metricFrame: frame, in: rect ?? canvasRectangle)
    }

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

    /// Declare that the meshes drawn inside the block move together as one thing,
    /// so `temporalAntialiasing()` follows them exactly while they move and
    /// `motionBlur()` streaks them along their own path. Both read per-pixel
    /// motion; camera motion is already followed per pixel, but a mesh that
    /// moves in *world* space (a spun `rotate`, a physics body, an animated
    /// scene) leaves no trail of where it was, so under temporal AA its moving
    /// edges fall back to a conservative blend, and under motion blur it takes
    /// only the camera's streak. Inside the block, Ollin remembers each draw's
    /// placement from frame to frame under the call site's identity and hands
    /// the renderer its exact screen motion. Two same-line blocks (a loop) keep
    /// separate identities by occurrence order; use the named form to pin
    /// identity explicitly when call order varies. Purely additive: with both
    /// features off (or for a still mesh) nothing changes, and wireframes,
    /// point clouds, and raymarched fields keep the default handling.
    public func withMotion(file: String = #fileID, line: Int = #line,
                           _ body: () -> Void) {
        drawer.withMotion(source: "\(file):\(line)", body)
    }

    /// The named form of `withMotion(_:)`: the block's cross-frame identity is
    /// `name` (plus occurrence order among same-name blocks in one frame), so a
    /// mover keeps its history even when the code path that draws it moves.
    public func withMotion(_ name: String, _ body: () -> Void) {
        drawer.withMotion(source: "named:\(name)", body)
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

    /// The live recorder, once `startRecording()` (or an attached
    /// `SessionRecorder`) has claimed the slot. Held by name, not just in
    /// `extensions`, so the runner can carry a running recording across a
    /// live-reload swap, and readable so a host can reach the typed recorder
    /// (`stopAndWait()` on the way out) behind the bare calls.
    public internal(set) var sessionRecorder: SessionRecorder?

    /// The `@Eased` / `@Smoothed` properties on this sketch, discovered once via
    /// reflection (the stored set is fixed at compile time) and advanced each frame.
    private var advancingValues: [FrameAdvancing]?

    /// Backing generator for `random()` / `randomSeed(_:)` (see Random.swift).
    /// Seeded from `variation` at init, so unseeded sketches vary per run but
    /// every run is recoverable by its number.
    var rng: SplitMix64

    /// Backing field for `noise()` / `noiseSeed(_:)` (see Noise.swift).
    var perlin: PerlinNoise

    /// Backing field for `simplexNoise()` (see NoiseVariants.swift). Seeded
    /// with `perlin` so `noiseSeed` reproduces every noise flavor at once.
    var simplex: SimplexNoise

    /// Backing cell field for `worley()` (see NoiseVariants.swift).
    var worleyNoise: WorleyNoise

    /// The seeds last applied through `randomSeed(_:)` / `noiseSeed(_:)` (both
    /// via `seed(_:)`), recorded so exports can embed the reproduction recipe
    /// (see ExportMetadata.swift). Start at `variation`, which seeds both
    /// generators at init.
    var recordedRandomSeed: Int?
    var recordedNoiseSeed: Int?

    /// Cached second sample for `randomGaussian()` — the polar method yields two
    /// normals per pass, so the spare is held for the next call (see Random.swift).
    var gaussianSpare: Double?

    /// Set by the runner so `loop()`/`noLoop()` can pause/resume the MTKView.
    var loopStateDidChange: ((Bool) -> Void)?

    /// Record-and-replay plumbing (see `Take`): at most one of the two is
    /// attached. The recorder writes this run down as it plays; the player
    /// drives this run from a recorded one, overriding the clock and gating
    /// live input off. Both are wired by the runner or `Take.install(on:)`;
    /// a sketch never touches them.
    var takeRecorder: TakeRecorder?
    var takePlayer: TakePlayer?

    /// Keys currently held down, so `isKeyDown(_:)` can answer and `keyIsPressed`
    /// tracks whether any key is down. The view inserts on press and removes on
    /// release (see `handleKey`).
    private var pressedKeys: Set<KeyToken> = []

    /// The seed this run's randomness grew from: the sketch's place in its
    /// variation space. Rolled fresh each run (a friendly five-digit number)
    /// and applied to both `random()` and `noise()` at init, so an unseeded
    /// sketch still varies run to run, yet any run can be brought back by its
    /// number: the exports embed it in their recipe, the host inspectors show
    /// it with previous/next/random controls, and `--seed N` re-renders it.
    /// `seed(n)` sets it; a sketch that calls `seed(42)` in `setup()` pins
    /// itself to that one variation.
    public internal(set) var variation: Int

    /// `required` so `Self()` works in the static `main()` entry point (see
    /// `Sketch.main()`), letting a sketch file be `@main` with no boilerplate.
    public required init() {
        // One entropy roll seeds everything, so the run reproduces from a
        // single number. Kept to five digits for easy reading and retyping;
        // SplitMix64's finalizer decorrelates even adjacent seeds.
        let roll = Int.random(in: 1 ... 99_999)
        variation = roll
        rng = SplitMix64(seed: UInt64(bitPattern: Int64(roll)))
        perlin = PerlinNoise(seed: UInt64(bitPattern: Int64(roll)))
        simplex = SimplexNoise(seed: UInt64(bitPattern: Int64(roll)))
        worleyNoise = WorleyNoise(seed: UInt64(bitPattern: Int64(roll)))
        recordedRandomSeed = roll
        recordedNoiseSeed = roll
    }

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
    /// (arced). Applies to the stroked paths with interior corners — `drawPolyline`,
    /// the `drawPolygon` outline, `drawShape` contours, and the flattened
    /// `drawBezier`. The analytic SDF shapes draw their own outlines, so they have
    /// no joins to style. See `StrokeJoin`.
    public func strokeJoin(_ join: StrokeJoin) { drawer.strokeJoin(join) }
    /// Set how the open ends of a stroked path finish: `.butt` (default, flat at
    /// the endpoint), `.round` (a half-disk tip), or `.square` (a flat extension
    /// half the weight past the end). Applies to the open stroked paths —
    /// `drawLine`, `drawBezier`, `drawPolyline`, and open `drawShape` contours;
    /// closed outlines have no ends to cap. See `StrokeCap`.
    public func strokeCap(_ cap: StrokeCap) { drawer.strokeCap(cap) }
    /// Set how the stroke width varies along a path: `.uniform` (default, one
    /// width the whole way), `.taper(start:end:)` (thin at the ends, full in the
    /// middle), `.ramp(from:to:)` (a straight wedge), `.nib(angle:)` (a flat
    /// calligraphy pen, thick across its edge and thin along it), or `.values(_:)`.
    /// The profile multiplies `strokeWeight` rather than replacing it. Applies to
    /// the stroked paths (`drawLine`, `drawBezier`, `drawPolyline`, `drawCurve`,
    /// and `drawShape` / `drawPolygon` outlines); the analytic shapes keep their
    /// constant width. See `StrokeProfile`.
    public func strokeProfile(_ profile: StrokeProfile) { drawer.strokeProfile(profile) }
    /// Set the stroke's width profile from a closure over the path fraction
    /// (`0` at the start of the path, `1` at its end), returning the fraction of
    /// `strokeWeight` to draw there: `strokeProfile { t in sin(t * .pi) }`.
    ///
    /// The closure runs where the stroke is expanded rather than on the sketch, so
    /// it can't reach `time` or a `@Param` directly. Copy what it needs into a
    /// local first (`let clock = time`) and capture that. The named profiles take
    /// their animation as an argument instead, so `.nib(angle: time)` is fine.
    public func strokeProfile(_ multiplier: @escaping @Sendable (_ t: Double) -> Double) {
        drawer.strokeProfile(StrokeProfile(multiplier))
    }
    /// Return to a constant-width stroke (the default), undoing `strokeProfile(_:)`.
    public func noStrokeProfile() { drawer.noStrokeProfile() }
    /// Repeat a shape along the path instead of expanding it into a continuous
    /// ribbon: `strokeBrush(.spray())` sprays round stamps either side of the
    /// line, `strokeBrush(.chisel())` lays down squares that turn with it.
    ///
    /// The stamp takes its size from `strokeWeight` and its color from `stroke`,
    /// so a brush changes a stroke's texture, not its weight or its color, and an
    /// ambient `strokeProfile` still shapes the size along the path. Applies to
    /// the stroked paths (`drawLine`, `drawBezier`, `drawPolyline`, `drawCurve`,
    /// `drawMark`, and `drawShape` / `drawPolygon` outlines); the analytic shapes
    /// keep their continuous outline. See `Brush`.
    public func strokeBrush(_ brush: Brush) { drawer.strokeBrush(brush) }
    /// Return to a continuous stroke (the default), undoing `strokeBrush(_:)`.
    public func noStrokeBrush() { drawer.noStrokeBrush() }
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
    /// Draw a composed signed-distance field — its shapes merge (smooth union,
    /// subtract, intersect, morph) into one region, filled with the current `fill`
    /// (or each leaf's `.colored`) and stroked along the merged outline. Build the
    /// field with the `SDF` value type, e.g.
    /// `drawSDF(SDF.circle(radius: 120).smoothUnion(.rect(width: 200, height: 80).at(x: 90, y: 0), k: 40))`.
    public func drawSDF(_ sdf: SDF) {
        drawer.drawSDF(sdf)
    }
    /// Draw a composed *3D* signed-distance field — its solids merge (smooth union,
    /// subtract, intersect, morph) into one sphere-traced surface, lit by the scene's
    /// lights and depth-composited with the meshes. Requires an active camera; build
    /// the field with the `SDF3D` value type, e.g.
    /// `drawSDF3D(SDF3D.sphere(radius: 1).smoothUnion(.box(size: 1).at(x: 1.2, y: 0, z: 0), k: 0.5))`.
    public func drawSDF3D(_ sdf: SDF3D) {
        drawer.drawSDF3D(sdf)
    }

    // MARK: SDF-combinator blocks (sugar over `SDF` + `drawSDF`, and `SDF3D` + `drawSDF3D`)
    //
    // Inside a block, the bare draw calls are captured and merged under the block's
    // operator instead of drawn one by one; the merged field is drawn (with the current
    // fill/stroke) when the block closes. In 2D that's the SDF region shapes
    // (`drawCircle`/`drawRect`/`drawNgon`/…); in 3D (with a camera set) it's the SDF-able
    // mesh primitives (`drawSphere`/`drawBox`/`drawCapsule`/`drawCone`/`drawTorus`/
    // `drawCylinder`/`drawRoundedBox`/`drawOctahedron`), which merge as raymarched fields
    // rather than rasterizing as separate solids; the same block serves both. Blocks
    // nest, the transform stack works inside them, and each call's own `fill` becomes that
    // leaf's color (so colors blend at a smooth seam). Non-mergeable draws (2D lines/text/
    // images, or a non-primitive mesh in 3D) inside a block are ignored.

    /// Merge the shapes drawn inside (hard union: the area covered by any of them).
    public func union(_ body: () -> Void) {
        drawer.beginCombine(op: .union, k: 0); body(); drawer.endCombine()
    }
    /// Smoothly merge the shapes drawn inside: they melt together over a blend of `k`.
    public func smoothUnion(k: Double, _ body: () -> Void) {
        drawer.beginCombine(op: .smoothUnion, k: k); body(); drawer.endCombine()
    }
    /// Carve the later shapes out of the first one drawn inside.
    public func subtract(_ body: () -> Void) {
        drawer.beginCombine(op: .subtract, k: 0); body(); drawer.endCombine()
    }
    /// Smoothly carve the later shapes out of the first (blend of radius `k`).
    public func smoothSubtract(k: Double, _ body: () -> Void) {
        drawer.beginCombine(op: .smoothSubtract, k: k); body(); drawer.endCombine()
    }
    /// Keep only where every shape drawn inside overlaps.
    public func intersect(_ body: () -> Void) {
        drawer.beginCombine(op: .intersect, k: 0); body(); drawer.endCombine()
    }
    /// Smooth intersection of the shapes drawn inside (blend of radius `k`).
    public func smoothIntersect(k: Double, _ body: () -> Void) {
        drawer.beginCombine(op: .smoothIntersect, k: k); body(); drawer.endCombine()
    }
    /// Merge the shapes drawn inside with a 45° chamfer of the given size along each seam
    /// (a machined joint; colors stay a crisp pick per side, not a melt).
    public func chamferUnion(radius: Double, _ body: () -> Void) {
        drawer.beginCombine(op: .chamferUnion, k: radius); body(); drawer.endCombine()
    }
    /// Carve the later shapes out of the first, each cut's rim beveled at 45°.
    public func chamferSubtract(radius: Double, _ body: () -> Void) {
        drawer.beginCombine(op: .chamferSubtract, k: radius); body(); drawer.endCombine()
    }
    /// Keep only where every shape drawn inside overlaps, the edge beveled at 45°.
    public func chamferIntersect(radius: Double, _ body: () -> Void) {
        drawer.beginCombine(op: .chamferIntersect, k: radius); body(); drawer.endCombine()
    }
    /// Merge the shapes drawn inside through a staircase of `steps` steps over `radius`
    /// along each seam.
    public func stairsUnion(radius: Double, steps: Int, _ body: () -> Void) {
        drawer.beginCombine(op: .stairsUnion, k: radius, extra: Double(max(steps, 1)))
        body(); drawer.endCombine()
    }
    /// Carve the later shapes out of the first, each cut's rim stepped.
    public func stairsSubtract(radius: Double, steps: Int, _ body: () -> Void) {
        drawer.beginCombine(op: .stairsSubtract, k: radius, extra: Double(max(steps, 1)))
        body(); drawer.endCombine()
    }
    /// Keep only where every shape drawn inside overlaps, the edge stepped.
    public func stairsIntersect(radius: Double, steps: Int, _ body: () -> Void) {
        drawer.beginCombine(op: .stairsIntersect, k: radius, extra: Double(max(steps, 1)))
        body(); drawer.endCombine()
    }
    /// Merge the shapes drawn inside through a row of `count` circular ribs of overall
    /// size `radius` along each seam (a fluted joint).
    public func columnsUnion(radius: Double, count: Int, _ body: () -> Void) {
        drawer.beginCombine(op: .columnsUnion, k: radius, extra: Double(max(count, 1)))
        body(); drawer.endCombine()
    }
    /// Carve the later shapes out of the first, each cut's rim fluted with ribs.
    public func columnsSubtract(radius: Double, count: Int, _ body: () -> Void) {
        drawer.beginCombine(op: .columnsSubtract, k: radius, extra: Double(max(count, 1)))
        body(); drawer.endCombine()
    }
    /// Keep only where every shape drawn inside overlaps, the edge fluted with ribs.
    public func columnsIntersect(radius: Double, count: Int, _ body: () -> Void) {
        drawer.beginCombine(op: .columnsIntersect, k: radius, extra: Double(max(count, 1)))
        body(); drawer.endCombine()
    }

    // MARK: The sculpt block (combine mode and melt as mutable state)
    //
    // Where the blocks above fix one operator for everything inside, `sculpt { }` reads
    // like working clay: shapes `add()` on (the default) or `carve()` away, melting over
    // the current `blend(_:)` radius, and the verbs switch that state mid-block. Built
    // for the live-coding loop, where a form grows a line at a time and one flipped verb
    // turns a bump into a dent. Same capture as the other blocks (2D region shapes, or
    // the SDF-able mesh primitives under a camera; the transform stack works inside).

    /// Sculpt one merged form from the shapes drawn inside. The first shape is the base;
    /// each later one folds under the mode and melt state active when it was drawn:
    /// `add()` (the default) unions on, `carve()` subtracts, and `blend(_:)` sets how far
    /// the seams melt (0 = hard, the opening state). Nested blocks land as one piece
    /// under the state at their close.
    public func sculpt(_ body: () -> Void) {
        drawer.beginSculpt(); body(); drawer.endCombine()
    }
    /// Inside `sculpt { }`: switch to adding, so subsequent shapes union onto the form.
    public func add() { drawer.sculptAdd() }
    /// Inside `sculpt { }`: switch to carving, so subsequent shapes cut away from the form.
    public func carve() { drawer.sculptCarve() }
    /// Inside `sculpt { }`: set the melt radius for subsequent shapes (0 = a hard seam).
    public func blend(_ k: Double) { drawer.sculptBlend(k) }
    /// Mirror the field drawn inside across the x and/or y (and, in 3D, z) plane of the
    /// current frame. The `z` flag only applies to a 3D field.
    public func mirrored(x: Bool = true, y: Bool = false, z: Bool = false, _ body: () -> Void) {
        drawer.beginCombineDomain(.mirror(x: x, y: y), .mirror(x: x, y: y, z: z))
        body(); drawer.endCombine()
    }
    /// Tile the field drawn inside on a grid of `spacing`, `count` copies to each side.
    public func repeated(spacing: Vector2, count: Int, _ body: () -> Void) {
        let n = Float(max(0, count))
        drawer.beginCombineDomain(
            .repeatTiles(spacing: SIMD2(Float(spacing.x), Float(spacing.y)), count: SIMD2(n, n)),
            .repeatTiles(spacing: SIMD3(Float(spacing.x), Float(spacing.y), 0), count: SIMD3(n, n, n)))
        body(); drawer.endCombine()
    }
    /// Tile a 3D field drawn inside on a grid of `spacing`, `count` copies to each side
    /// along each axis (a zero spacing component leaves that axis untiled).
    public func repeated(spacing: Vector3, count: Int, _ body: () -> Void) {
        let n = Float(max(0, count))
        drawer.beginCombineDomain(
            .repeatTiles(spacing: SIMD2(Float(spacing.x), Float(spacing.y)), count: SIMD2(n, n)),
            .repeatTiles(spacing: SIMD3(Float(spacing.x), Float(spacing.y), Float(spacing.z)),
                         count: SIMD3(n, n, n)))
        body(); drawer.endCombine()
    }
    /// Repeat the field drawn inside as `count` evenly spaced copies around a center (2D) or
    /// an axis (3D), folding one built wedge into a radial ring (a mandala in 2D, a rosette or
    /// sunburst in 3D). Draw the wedge off the center/axis (e.g. `translate(r, 0)` in 2D,
    /// `translate(r, 0, 0)` in 3D) so the copies fan out around it. The `axis` only applies in 3D.
    public func repeatedRadially(count: Int, around axis: Vector3 = Vector3(0, 1, 0),
                                 _ body: () -> Void) {
        let n = Float(max(count, 1))
        let len = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
        let unit: SIMD3<Float> = len > 1e-6
            ? SIMD3(Float(axis.x / len), Float(axis.y / len), Float(axis.z / len))
            : SIMD3(0, 1, 0)
        drawer.beginCombineDomain(.polar(count: n), .polar(axis: unit, count: n))
        body(); drawer.endCombine()
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

    /// Stroke a recorded `StrokeMark` at the width and opacity it asked for at
    /// every point along the way. Draws nothing until two points are recorded.
    ///
    /// ```swift
    /// if mouseIsPressed { record(into: &mark) }
    /// drawMark(mark)
    /// ```
    public func drawMark(_ mark: StrokeMark) { drawer.drawMark(mark) }

    /// Record where the pointer is now into `mark`, timed by this frame.
    ///
    /// Sugar for `mark.record(Vector2(mouseX, mouseY), dt: deltaTime, pressure: pressure)`:
    /// it hands the mark the three things it needs to measure a stroke, and using
    /// `deltaTime` is what makes the mark come out the same at any frame rate.
    /// Call it from `draw()` while the pointer is down.
    public func record(into mark: inout StrokeMark) {
        mark.record(Vector2(mouseX, mouseY), dt: deltaTime, pressure: pressure)
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
    /// each point with tangents derived from its neighbors. `closed: false` (the
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

    // MARK: Retained batches

    /// Record everything drawn in `body` into a reusable `Batch` whose geometry
    /// lives on the GPU, so replaying it each frame costs (almost) nothing (see
    /// `Batch`). Record once, in `setup()`, and hold the result; the body records
    /// from an identity transform, and state it changes is restored on exit, like
    /// `withState { }`.
    public func makeBatch(_ body: () -> Void) -> Batch {
        drawer.makeBatch(body)
    }

    /// Replay a recorded `Batch`. The transform in force moves the whole replay
    /// as a unit, so one recording can be stamped at many placements; the active
    /// layer, clip, and `depth(at:)` apply to it like any draw call.
    public func drawBatch(_ batch: Batch) {
        drawer.drawBatch(batch)
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

    // MARK: Layered effects

    /// Make a full-canvas off-screen layer to draw into and then read back or
    /// filter (see `RenderTarget`). `scale` is the layer's internal resolution as a
    /// fraction of the canvas (1 = full); drop it for cheap blur/glow layers.
    /// Create it inside `draw()`; it's a per-frame handle.
    public func renderTarget(scale: Double = 1) -> RenderTarget {
        RenderTarget(width: Int(width.rounded()), height: Int(height.rounded()),
                     scale: scale, drawer: drawer)
    }

    /// Make an off-screen layer of an explicit pixel size (rather than the canvas
    /// size), for a layer that isn't full-canvas.
    public func renderTarget(width: Int, height: Int, scale: Double = 1) -> RenderTarget {
        RenderTarget(width: width, height: height, scale: scale, drawer: drawer)
    }

    /// Redirect everything drawn in `body` into `target` instead of the canvas.
    /// Scoped like `withState { }`: drawing state and transforms carry in, and the
    /// target holds the result for `target.image` / `target.filtered(_:)`.
    /// Call `background(_:)` inside to clear the layer (it clears only this layer).
    public func withTarget(_ target: RenderTarget, _ body: () -> Void) {
        drawer.withTarget(target, body)
    }

    /// Fill a full-canvas layer with a procedural pattern (see `Generator`),
    /// returning it as a `RenderTarget` you can draw (`gen.image`), filter
    /// (`gen.filtered(_:)`), or feed into another effect. Call it inside `draw()`.
    public func generate(_ generator: Generator, scale: Double = 1) -> RenderTarget {
        drawer.generate(generator, width: Int(width.rounded()),
                        height: Int(height.rounded()), scale: scale)
    }

    /// Fill a layer of an explicit size (rather than the canvas size) with a
    /// procedural pattern. The pattern composes for that size (cells stay
    /// square at the layer's own aspect), so a tile or panel gets its own
    /// undistorted pattern instead of a squashed full-canvas one.
    public func generate(_ generator: Generator, width: Int, height: Int,
                         scale: Double = 1) -> RenderTarget {
        drawer.generate(generator, width: width, height: height, scale: scale)
    }

    /// Run a user-supplied `Shader` as a source layer, returning the `RenderTarget`
    /// it filled. Sugar for `generate(.shader(shader))`; draw it with `.image`,
    /// filter it, or feed it into another effect.
    public func generate(_ shader: Shader, scale: Double = 1) -> RenderTarget {
        generate(.shader(shader), scale: scale)
    }

    /// Run a user-supplied `Shader` as a source layer of an explicit size (rather
    /// than the canvas size): the shader's `info.resolution` is that size, so a
    /// tile or panel gets its own undistorted render.
    public func generate(_ shader: Shader, width: Int, height: Int,
                         scale: Double = 1) -> RenderTarget {
        generate(.shader(shader), width: width, height: height, scale: scale)
    }

    /// Make a full-canvas feedback layer: a layer that remembers itself across
    /// frames, for trails, tunnels, and video-feedback looks (see `Feedback`).
    /// Unlike `renderTarget()`, it's **persistent**: create it once in `setup()`
    /// and store it; its identity is what carries state from one frame to the next.
    /// `scale` is its internal resolution as a fraction of the canvas (1 = full).
    public func feedback(scale: Double = 1) -> Feedback {
        Feedback(width: Int(width.rounded()), height: Int(height.rounded()),
                 scale: scale, drawer: drawer)
    }

    /// Make a feedback layer of an explicit pixel size, rather than the canvas size.
    public func feedback(width: Int, height: Int, scale: Double = 1) -> Feedback {
        Feedback(width: width, height: height, scale: scale, drawer: drawer)
    }

    /// Draw into `feedback`, with last frame's content handed in as `prev`. Read,
    /// fade, and transform `prev`, then draw new content on top; the result becomes
    /// next frame's `prev`. Composite the layer onto the canvas with
    /// `drawImage(feedback.image, 0, 0)`. Scoped like `withTarget { }`.
    public func withFeedback(_ feedback: Feedback, _ body: (Image) -> Void) {
        drawer.withFeedback(feedback, body)
    }

    /// Draw into `feedback` without the closure parameter, reading last frame by name
    /// via `feedback.previous` inside. The `withTarget`-shaped form of `withFeedback`.
    public func withTarget(_ feedback: Feedback, _ body: () -> Void) {
        drawer.withTarget(feedback, body)
    }

    /// Make a full-canvas simulation field that evolves by `sim` each frame (see
    /// `SimField`/`Sim`): reaction-diffusion, Game of Life, and other fields. Like
    /// `feedback()`, it's **persistent** — create it once in `setup()` and store it.
    /// `scale` is the field's internal resolution as a fraction of the canvas; lower
    /// it for coarser features and chunkier cells.
    public func simField(_ sim: Sim, scale: Double = 1) -> SimField {
        SimField(sim: sim, width: Int(width.rounded()), height: Int(height.rounded()),
                 scale: scale, drawer: drawer)
    }

    /// Make a simulation field of an explicit pixel size, rather than the canvas size.
    public func simField(_ sim: Sim, width: Int, height: Int, scale: Double = 1) -> SimField {
        SimField(sim: sim, width: width, height: height, scale: scale, drawer: drawer)
    }

    /// Draw into `field` to seed or force its simulation: the marks land on the field's
    /// current state, which then evolves one step. What a mark means is per-sim (white
    /// = alive for Game of Life, injected chemical for reaction-diffusion, the mark's
    /// color as injected dye for a fluid). Composite the field onto the canvas with
    /// `drawImage(field.image, 0, 0)`. Scoped like `withTarget { }`; leave the block
    /// empty to let the field evolve untouched.
    ///
    /// `force` is the velocity impulse a `.fluid` field receives where the block's marks
    /// land — pass the brush's motion (the change in `mouseX`/`mouseY` since last frame)
    /// or an animated vector so the painted color swirls. The single-field sims ignore it.
    public func withField(_ field: SimField, force: Vector2 = .zero, _ body: () -> Void) {
        drawer.withField(field, force: force, body)
    }

    /// Apply `filter` to the whole finished frame, before it's shown: the quick
    /// way to bloom or blur everything without managing a layer. Call it in
    /// `draw()`; multiple calls chain in order.
    public func postProcess(_ filter: Filter) { drawer.postProcess(filter) }
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
    /// Set the base direction a line of text runs in: `.automatic` (default, read
    /// from the text itself), `.leftToRight`, or `.rightToLeft`. It decides where
    /// the neutral characters (spaces, brackets, digits) land on a line that mixes
    /// scripts, and which end the line starts at. Outline fonts only, since bitmap
    /// and stroke fonts have no shaping engine. See `TextDirection`.
    public func textDirection(_ direction: TextDirection) { drawer.textDirection(direction) }
    /// Stretch wrapped text so it runs the full width of its box, both edges flush.
    ///
    /// Justification needs to know how far a line should run, and only the box form
    /// of `drawText` says that, so this applies to `drawText(_:in:)` and nothing
    /// else. The last line of each paragraph is left at its natural width, because
    /// it is short for a reason the box had nothing to do with. `textAlign` then
    /// says which way that last line sits.
    ///
    /// The system's layout engine decides where the extra room goes, which is what
    /// makes this work in any script: between the words in English, between the
    /// characters in Japanese. It works down a column as readily as across a line.
    ///
    /// ```swift
    /// textJustify()
    /// drawText(paragraph, in: Rectangle(x: 80, y: 80, width: 400, height: 600))
    /// ```
    public func textJustify(_ on: Bool = true) { drawer.textJustify(on) }
    /// Leave wrapped text at its natural width, the default. See `textJustify`.
    public func noTextJustify() { drawer.noTextJustify() }
    /// Let a full stop or comma at the end of a line sit past that end.
    ///
    /// Wrapping normally keeps every character inside the box. A stop may not open a
    /// line, so a stop that will not fit takes the character it follows to the next
    /// line with it. This lets that stop hang past the edge instead, which keeps the
    /// line full and the edge even. It is the Japanese ぶら下げ, and the same move
    /// Latin typesetters make to keep a margin looking straight.
    ///
    /// It applies where the wrap happens, so this is a `drawText(_:in:)` setting.
    /// The characters that may hang are the stops and the commas: `。`, `、`, their
    /// full-width and half-width forms, and the Latin `.` and `,`. A hung character
    /// does not count toward the line, so alignment and justification measure the
    /// rest of it.
    ///
    /// ```swift
    /// textHangingPunctuation()
    /// drawText(passage, in: box)
    /// ```
    public func textHangingPunctuation(_ on: Bool = true) { drawer.textHangingPunctuation(on) }
    /// Keep every character inside the box, the default. See `textHangingPunctuation`.
    public func noTextHangingPunctuation() { drawer.noTextHangingPunctuation() }
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
    /// The characters in `string` the current font cannot draw, in the order they
    /// appear. An **outline** font asks the whole system, so this is empty unless no
    /// installed face has the character at all (it then draws as a box rather than
    /// vanishing). A **bitmap** or **stroke** font has only the glyphs in its own
    /// file, and anything else advances the pen and draws nothing, so this is the
    /// way to find out before you draw.
    ///
    /// ```swift
    /// textFont(BitmapFont.builtin)
    /// print(textMissingCharacters("日本語"))     // ["日", "本", "語"]
    /// ```
    public func textMissingCharacters(_ string: String) -> [Character] {
        drawer.textMissingCharacters(string)
    }
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
    /// rainbows, springs — effects with no single built-in call.
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

    /// Replicate everything drawn next into `folds` copies rotated evenly around
    /// the current origin (the kaleidoscope, or mandala, mode). Draw one wedge;
    /// the folds complete the picture. `mirrored: true` adds a reflected copy per
    /// fold (mirrored across the local x-axis), the classic kaleidoscope look.
    ///
    /// ```swift
    /// translate(width / 2, height / 2)   // fold around the canvas center
    /// symmetry(8, mirrored: true)
    /// drawCircle(240, 40, 30)            // appears 16 times
    /// ```
    ///
    /// The fold pivot and mirror axis are the origin and x-axis at this call, so
    /// `translate` first to place the center (and `rotate` to aim the mirror
    /// seam); transforms applied *after* compose inside every fold. Drawing
    /// state like `fill`: it persists until `noSymmetry()`, and `withState { }`
    /// restores it. Replication covers all 2D drawing (shapes, strokes, images,
    /// text, SDF fields) and rides into SVG export; 3D geometry and GPU
    /// particles are untouched.
    public func symmetry(_ folds: Int, mirrored: Bool = false) {
        drawer.symmetry(folds, mirrored: mirrored)
    }

    /// Stop replicating draw calls: back to drawing each one once (the default).
    public func noSymmetry() { drawer.noSymmetry() }

    // MARK: 3D transforms

    // The spatial siblings of the 2D `translate`/`rotate`/`scale` above: these move
    // 3D geometry (a point cloud) inside the active `camera`, in right-handed, y-up
    // world units, composing on a 4×4 model matrix that `withState` saves and restores
    // like the 2D one. They don't affect 2D drawing (shapes/images/text keep using the
    // 2D transform), so both stacks stay live in a 3D frame. A 2D-only sketch ignores
    // them. Set a `camera` first; the cloud rides the model matrix into the scene.

    /// Move subsequent 3D geometry by `offset` in world units.
    public func translate(_ offset: Vector3) { drawer.translate(offset) }
    /// Move subsequent 3D geometry by `(x, y, z)` in world units.
    public func translate(_ x: Double, _ y: Double, _ z: Double) { drawer.translate(x, y, z) }
    /// Rotate subsequent 3D geometry by `radians` about the world x-axis (right-handed).
    public func rotateX(_ radians: Double) { drawer.rotateX(radians) }
    /// Rotate subsequent 3D geometry by `radians` about the world y-axis (right-handed).
    public func rotateY(_ radians: Double) { drawer.rotateY(radians) }
    /// Rotate subsequent 3D geometry by `radians` about the world z-axis (right-handed).
    public func rotateZ(_ radians: Double) { drawer.rotateZ(radians) }
    /// Rotate subsequent 3D geometry by `radians` about an arbitrary `axis`.
    public func rotate(_ radians: Double, axis: Vector3) { drawer.rotate(radians, axis: axis) }
    /// Scale subsequent 3D geometry per axis by `(x, y, z)`.
    public func scale(_ x: Double, _ y: Double, _ z: Double) { drawer.scale(x, y, z) }
    /// Scale subsequent 3D geometry by per-axis `factors`. Uniform scale is
    /// `scale(Vector3(s, s, s))`.
    public func scale(_ factors: Vector3) { drawer.scale(factors) }
    /// Compose an arbitrary 4x4 `matrix` onto subsequent 3D geometry, for a
    /// transform that arrives whole (a streamed body anchor, a joint pose) rather
    /// than as separate translate/rotate/scale steps. Composes like the calls
    /// above and is saved/restored by `withState`.
    public func transform(_ matrix: simd_float4x4) { drawer.transform(matrix) }

    public func pushState() { drawer.pushState() }
    public func popState() { drawer.popState() }

    /// Run `body` with the current transform and style saved, then restored.
    /// Prefer this scoped form over bare `pushState()`/`popState()`.
    public func withState(_ body: () -> Void) {
        drawer.pushState()
        defer { drawer.popState() }
        body()
    }

    /// Run `body` with drawing confined to `shape`'s filled region, restoring the
    /// previous clip (and any drawing state the block changed, like `withState`)
    /// on exit. The region honors the shape's `winding` rule and is fixed where
    /// the current transform places it, like a drawn fill; nesting intersects
    /// regions. Everything drawn inside is clipped: fills, strokes, images, text,
    /// even 3D geometry, with the edge anti-aliased at MSAA resolution. Clipping
    /// is scoped to the current drawing surface, so a `layer { }` opened inside
    /// starts unclipped (clip inside the layer block instead).
    public func withClip(_ shape: Shape, _ body: () -> Void) {
        drawer.withClip(shape, body)
    }

    /// Run `body` with drawing confined to `rect`.
    public func withClip(_ rect: Rectangle, _ body: () -> Void) {
        drawer.withClip(Shape([
            Vector2(rect.x, rect.y),
            Vector2(rect.x + rect.width, rect.y),
            Vector2(rect.x + rect.width, rect.y + rect.height),
            Vector2(rect.x, rect.y + rect.height),
        ]), body)
    }

    /// Run `body` with drawing confined to `circle`. The circle is flattened to a
    /// fine polygon for the clip (like the vector exporters), dense enough that
    /// the edge reads round at canvas resolution.
    public func withClip(_ circle: Circle, _ body: () -> Void) {
        let n = max(48, Int((circle.radius * 0.8).rounded(.up)))
        let points = (0..<n).map { k -> Vector2 in
            let a = 2 * Double.pi * Double(k) / Double(n)
            return circle.center + Vector2(cos(a) * circle.radius, sin(a) * circle.radius)
        }
        drawer.withClip(Shape(points), body)
    }

    // MARK: Runner plumbing (called by SketchRunner)

    func setCanvasSize(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    func setMouse(x: Double, y: Double) {
        takeRecorder?.log(.pointer(x: x, y: y), at: frameCount)
        guard takePlayer == nil else { return }
        ingestMouse(x: x, y: y)
    }

    fileprivate func ingestMouse(x: Double, y: Double) {
        mouseX = x
        mouseY = y
    }

    /// The primary button from the view: the held state plus the
    /// once-per-press hooks.
    func handleMouseButton(pressed: Bool) {
        takeRecorder?.log(.button(pressed: pressed), at: frameCount)
        guard takePlayer == nil else { return }
        ingestMouseButton(pressed: pressed)
    }

    fileprivate func ingestMouseButton(pressed: Bool) {
        mouseIsPressed = pressed
        if pressed { mousePressed() } else { mouseReleased() }
    }

    /// The held state alone, with no hooks: a host widget dragging the camera
    /// feeds the button state without a click the sketch should react to.
    func setMouseButtonState(_ pressed: Bool) {
        takeRecorder?.log(.buttonState(pressed: pressed), at: frameCount)
        guard takePlayer == nil else { return }
        mouseIsPressed = pressed
    }

    /// Where the run sits on the desk this frame. Pushed every frame rather
    /// than on a move, so a window being dragged is current in the frame that
    /// draws during the drag.
    func setPlacement(canvas: Rectangle?, screen: Rectangle?) {
        canvasOnScreen = canvas
        screenFrame = screen
    }

    func setDisplayHeadroom(_ headroom: Double) {
        displayHeadroom = headroom
    }

    func setRightMousePressed(_ pressed: Bool) {
        takeRecorder?.log(.rightButton(pressed: pressed), at: frameCount)
        guard takePlayer == nil else { return }
        rightMouseIsPressed = pressed
    }

    /// Record how hard the pointer is pressed, and whether the device measuring it
    /// can vary at all. `canVary` latches on: a session that has felt real pressure
    /// once keeps reporting the capability even between presses, when the platform
    /// has nothing to tell us.
    func setPressure(_ amount: Double, canVary: Bool) {
        takeRecorder?.log(.pressure(amount: amount, canVary: canVary), at: frameCount)
        guard takePlayer == nil else { return }
        ingestPressure(amount, canVary: canVary)
    }

    fileprivate func ingestPressure(_ amount: Double, canVary: Bool) {
        pressure = min(max(amount, 0), 1)
        if canVary { pressureIsAvailable = true }
    }

    /// Scroll delivered between frames, summed here and surfaced as `scrollDeltaY`
    /// at the start of the next `advance()`, so no wheel movement is lost.
    private var pendingScroll: Double = 0

    /// Record scroll-wheel movement from the view and fire the per-event hook. The
    /// accumulated total becomes `scrollDeltaY` next frame; for the hook itself,
    /// `scrollDeltaY` carries this event's own movement (the documented contract;
    /// without it the hook would read the previous frame's total, usually 0),
    /// and `advance()` overwrites it with the frame total before `draw()` polls it.
    func handleScroll(deltaY: Double) {
        takeRecorder?.log(.scroll(deltaY: deltaY), at: frameCount)
        guard takePlayer == nil else { return }
        ingestScroll(deltaY: deltaY)
    }

    fileprivate func ingestScroll(deltaY: Double) {
        pendingScroll += deltaY
        scrollDeltaY = deltaY
        mouseWheel()
    }

    /// Record the held modifier keys from the view.
    func setModifiers(_ mods: ModifierKeys) {
        takeRecorder?.log(.modifiers(mods), at: frameCount)
        guard takePlayer == nil else { return }
        modifiers = mods
    }

    /// Record a key event from the view and update the held-key set. The view
    /// passes exactly one of `character`/`code` (a printing key vs. a named one);
    /// the other is `nil`. Updates `key`/`keyCode`/`keyIsPressed`, then fires
    /// `keyPressed()`/`keyReleased()`.
    func handleKey(character: Character?, code: KeyCode?, pressed: Bool) {
        takeRecorder?.log(.key(character: character.map(String.init), code: code,
                               pressed: pressed), at: frameCount)
        guard takePlayer == nil else { return }
        ingestKey(character: character, code: code, pressed: pressed)
    }

    fileprivate func ingestKey(character: Character?, code: KeyCode?, pressed: Bool) {
        key = character
        keyCode = code
        let token: KeyToken? = character.map(KeyToken.character) ?? code.map(KeyToken.code)
        if let token {
            if pressed { pressedKeys.insert(token) } else { pressedKeys.remove(token) }
        }
        keyIsPressed = !pressedKeys.isEmpty
        if pressed { keyPressed() } else { keyReleased() }
    }

    /// Drop all held keys — called when the canvas loses keyboard focus, so a key
    /// held while focus leaves (no `keyUp` is delivered then) doesn't stick down.
    func clearHeldKeys() {
        takeRecorder?.log(.keysCleared, at: frameCount)
        guard takePlayer == nil else { return }
        ingestClearHeldKeys()
    }

    fileprivate func ingestClearHeldKeys() {
        pressedKeys.removeAll()
        keyIsPressed = false
    }

    /// Route one replayed event through the same paths live input takes, so
    /// the state changes and the hooks fire exactly as when it was recorded.
    func ingest(_ event: Take.Event) {
        switch event {
        case .pointer(let x, let y):
            ingestMouse(x: x, y: y)
        case .button(let pressed):
            ingestMouseButton(pressed: pressed)
        case .buttonState(let pressed):
            mouseIsPressed = pressed
        case .rightButton(let pressed):
            rightMouseIsPressed = pressed
        case .pressure(let amount, let canVary):
            ingestPressure(amount, canVary: canVary)
        case .scroll(let deltaY):
            ingestScroll(deltaY: deltaY)
        case .modifiers(let mods):
            modifiers = mods
        case .key(let character, let code, let pressed):
            ingestKey(character: character.flatMap { $0.first }, code: code, pressed: pressed)
        case .keysCleared:
            ingestClearHeldKeys()
        }
    }

    func advance(time: Double, deltaTime: Double, frameRate: Double) {
        var time = time, deltaTime = deltaTime, frameRate = frameRate
        // A replay overrides the caller's clock with the recorded one, after
        // applying the frame's recorded events and knob changes; a recording
        // writes down whichever clock is about to apply. Every driver (the
        // live window, each export loop, the benchmark) funnels through here,
        // which is what lets one seam record and replay them all.
        if let takePlayer {
            (time, deltaTime, frameRate) = takePlayer.step(
                self, frame: frameCount,
                fallback: (time: time, deltaTime: deltaTime, frameRate: frameRate))
        }
        takeRecorder?.recordFrame(of: self, time: time, deltaTime: deltaTime,
                                  frameRate: frameRate)
        frameCount += 1
        self.time = time
        self.deltaTime = deltaTime
        self.frameRate = frameRate
        // Surface scroll accumulated since the last frame, then reset the collector
        // so this frame's wheel events are gathered for the next one (nothing lost).
        scrollDeltaY = pendingScroll
        pendingScroll = 0
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
        // The GPU takes the clock as a 32-bit float, which runs out of precision
        // in a run measured in days, so an installation hands it one that starts
        // over (`shaderClock`); every other run passes `time` through unchanged.
        // The frame number truncates rather than traps: at 60 frames a second a
        // `UInt32` fills after a bit over two years, and a piece on a wall must
        // wrap rather than stop.
        drawer.setComputeFrame(resolution: SIMD2(Float(width), Float(height)),
                               mouse: SIMD2(Float(mouseX), Float(mouseY)),
                               time: Float(shaderClock), dt: Float(deltaTime),
                               frameCount: UInt32(truncatingIfNeeded: max(0, frameCount)))
        for e in extensions { e.beforeDraw(self) }
        draw()
        for e in extensions { e.afterDraw(self) }   // before the render — can draw
    }

    /// Fired by the runner after the frame renders, with its timing. Headless
    /// paths (export) don't call this — there's no live frame rate to report.
    func runAfterFrame(_ info: FrameInfo) {
        for e in extensions { e.afterFrame(self, info) }
    }

    /// A GPU frame capture the sketch asked for (see `captureGPUFrame(to:)`),
    /// waiting for the runner to take it on the next frame. One at a time: a
    /// second request before the first is served replaces it.
    var pendingGPUCapture: URL?

    /// Take the pending capture request, if any, leaving none behind. The runner
    /// calls this once per frame.
    func takeGPUCaptureRequest() -> URL? {
        defer { pendingGPUCapture = nil }
        return pendingGPUCapture
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
