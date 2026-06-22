import Foundation
import AppKit
import SwiftUI
import MetalKit
import QuartzCore
import simd

// MARK: - The continuous draw loop

/// Bridges an `MTKView`'s per-frame callback to a `Sketch`: it advances the
/// temporal state (`frameCount` / `time` / `deltaTime` / `frameRate`), runs the
/// user's `draw()`, and hands the recorded geometry to the renderer.
///
/// The MTKView is configured for continuous redraw (`isPaused = false`,
/// `enableSetNeedsDisplay = false`), so this fires every display refresh — no
/// `loop()` toggling needed to animate.
@MainActor
public final class SketchRunner: NSObject, MTKViewDelegate {

    private(set) var sketch: Sketch
    private let renderer: MetalRenderer
    private weak var view: MTKView?

    /// The built-in stats observer (overlay + inspector), kept here so it can be
    /// re-attached to each freshly reloaded sketch — extensions otherwise reset
    /// with the new instance. Set via `observeStats(into:)`; nil for headless runs.
    private var statsExtension: StatsExtension?

    private var didSetup = false
    private var didReload = false        // call onReload() after the post-reload setup()
    private var pendingSetupRerun = false // re-run setup() in place (e.g. an asset changed)
    private var clockCarry: Double?      // seconds to continue `time` from across a reload
    private var startTime: CFTimeInterval = 0
    private var lastTime: CFTimeInterval = 0
    private var smoothedFrameRate: Double = 0
    private var smoothedCPUMS: Double = 0

    public init(sketch: Sketch, view: MTKView, device: MTLDevice) {
        self.sketch = sketch
        do {
            // The drawable is single-sample (the final present target); MSAA happens
            // in the renderer's float intermediate, so pass the MSAA count directly.
            self.renderer = try MetalRenderer(device: device,
                                              pixelFormat: view.colorPixelFormat,
                                              sampleCount: ollinPreferredSampleCount(device))
        } catch {
            fatalError("Ollin: failed to initialize the Metal renderer: \(error)")
        }
        super.init()
        self.view = view
        wireLoopControl(sketch)
    }

    /// Route a sketch's `noLoop()`/`loop()` to pausing/resuming the view's
    /// display timer. Re-applied to each freshly reloaded sketch.
    private func wireLoopControl(_ sketch: Sketch) {
        sketch.loopStateDidChange = { [weak self] looping in
            self?.view?.isPaused = !looping
        }
    }

    /// Swap in a freshly loaded sketch without tearing down the window or GPU
    /// resources — the heart of live reload. The new instance starts clean:
    /// `setup()` runs again and the clock resets on the next frame. **Call on the
    /// main thread**, since the draw callback runs there and reads `sketch`.
    /// - Parameter keepClock: when `true`, the new sketch keeps the old one's
    ///   `time`/`frameCount` advancing across the swap instead of resetting to
    ///   zero — so an animation's phase doesn't visibly jump on reload. Instance
    ///   state still resets (it's a fresh instance either way).
    public func reload(to newSketch: Sketch, keepClock: Bool = false) {
        newSketch.setCanvasSize(width: sketch.width, height: sketch.height)
        if keepClock {
            newSketch.frameCount = sketch.frameCount
            clockCarry = sketch.time      // continue `time` from here (see draw)
        } else {
            clockCarry = nil
        }
        wireLoopControl(newSketch)
        sketch = newSketch
        if let statsExtension { newSketch.extend(statsExtension) }   // re-attach stats observer
        renderer.resetAccumulation()   // a reloaded sketch starts on a clean canvas
        didSetup = false            // re-run setup() next frame
        didReload = true            // ...then call onReload() once
        view?.isPaused = false      // a prior noLoop() must not freeze the reload
    }

    /// Start feeding per-frame stats into `stats` (for the overlay and the live
    /// inspector). Installs the built-in `StatsExtension` on the current sketch
    /// and remembers it, so `reload(to:)` can re-attach it to each swapped-in
    /// sketch. **Call on the main thread.**
    func observeStats(into stats: FrameStats) {
        let ext = StatsExtension(stats: stats)
        statsExtension = ext
        sketch.extend(ext)
    }

    /// Recompile the shader library from `source` and rebuild the pipelines for
    /// the *running* sketch — live shader reload. Throws (leaving the current
    /// shaders in place) if the source doesn't compile. **Call on the main
    /// thread.**
    public func reloadShaderLibrary(source: String) throws {
        try renderer.reloadLibrary(source: source)
    }

    /// Live shader reload from the framework's split `Shader*.metal` segments in
    /// `directory` (the repo source the user is editing), read and concatenated in
    /// the renderer's fixed order. Throws if a segment is missing or doesn't
    /// compile, leaving the current shaders in place. **Call on the main thread.**
    public func reloadShaderLibrary(fromDirectory directory: String) throws {
        guard let source = MetalRenderer.concatenatedShaderSource(fromDirectory: directory) else {
            throw MetalRenderer.RendererError.shaderLibrary
        }
        try renderer.reloadLibrary(source: source)
    }

    /// Re-run the current sketch's `setup()` on the next frame without swapping
    /// the instance or resetting the clock — for when a co-located asset changes
    /// and `setup()` is where it'd be (re)loaded. **Call on the main thread.**
    public func rerunSetup() {
        pendingSetupRerun = true
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateCanvasSize(from: view, drawableSize: size)
    }

    public func draw(in view: MTKView) {
        // Make sure the sketch knows its size before the first setup()/draw().
        if sketch.width == 0 || sketch.height == 0 {
            updateCanvasSize(from: view, drawableSize: view.drawableSize)
        }

        let now = CACurrentMediaTime()

        if !didSetup {
            // Offset startTime so `time` continues across a keep-clock reload;
            // otherwise start it now so a fresh reload resets to zero.
            startTime = now - (clockCarry ?? 0)
            clockCarry = nil
            lastTime = now
            // Reflect where the cursor actually is before the first frame, so a
            // mouse-driven sketch isn't stuck reading (0, 0) — and rendering a
            // blank frame — until the pointer first moves over the window.
            (view as? OllinMTKView)?.seedPointer()
            sketch.setup()
            didSetup = true
            if didReload {            // setup() just ran on a hot-swapped sketch
                didReload = false
                sketch.onReload()
            }
        } else if pendingSetupRerun {
            pendingSetupRerun = false
            sketch.setup()            // in-place asset reload; clock keeps running
        }

        let dt = max(0, now - lastTime)
        lastTime = now

        // Exponentially smoothed FPS so the number doesn't jitter frame to frame.
        let instantaneous = dt > 0 ? 1.0 / dt : 0
        if smoothedFrameRate == 0 {
            smoothedFrameRate = instantaneous
        } else {
            smoothedFrameRate += (instantaneous - smoothedFrameRate) * 0.1
        }

        sketch.advance(time: now - startTime, deltaTime: dt, frameRate: smoothedFrameRate)

        // Time only the CPU tessellation (`performDraw`), not the render: the
        // renderer blocks on the triple-buffer semaphore (the vsync wait), which
        // would pin this to 1/fps and tell us nothing. CPU tessellation is the
        // documented first bottleneck, so it's the headroom number worth showing.
        let drawStart = CACurrentMediaTime()
        sketch.performDraw()
        let cpuMS = (CACurrentMediaTime() - drawStart) * 1000
        smoothedCPUMS = smoothedCPUMS == 0 ? cpuMS : smoothedCPUMS + (cpuMS - smoothedCPUMS) * 0.1

        renderer.render(sketch.drawer,
                        viewport: SIMD2<Float>(Float(sketch.width), Float(sketch.height)),
                        in: view)

        // Hand the frame's timing to any extensions (the stats observer, a
        // recorder). Counts are still valid here — the drawer clears next frame.
        sketch.runAfterFrame(FrameInfo(deltaTime: dt, frameRate: smoothedFrameRate,
                                       cpuDrawMS: smoothedCPUMS,
                                       vertexCount: sketch.drawer.vertices.count,
                                       sdfCount: sketch.drawer.sdfInstances.count,
                                       pointCount: sketch.drawer.points.count,
                                       particleCount: sketch.drawer.particleCount))

        // Frame-grab: if any extension asked for the rendered pixels, render the
        // frame off-screen and hand it over. Gated on `wantsRenderedFrames` so a
        // sketch that doesn't record pays nothing. We re-render off-screen (same
        // pipeline/MSAA, so the pixels match `image(of:)`/`--export`) rather than
        // read the on-screen drawable back — the drawable is `framebufferOnly`,
        // and a re-render keeps this off the live present path. The drawer still
        // holds this frame's geometry (it clears at the next `beginFrame`); an
        // async drawable readback is a later optimization.
        if sketch.wantsRenderedFrames {
            let w = Int(sketch.width.rounded()), h = Int(sketch.height.rounded())
            // While accumulating, the on-screen pile is what a recorder wants, so
            // read it back rather than re-rendering (which would double-accumulate).
            let image = sketch.drawer.accumulates
                ? renderer.accumulatedFrameImage(sketch.drawer)
                : renderer.image(of: sketch.drawer,
                                 viewport: SIMD2<Float>(Float(sketch.width), Float(sketch.height)),
                                 width: w, height: h)
            if let image { sketch.runFrameRendered(image) }
        }

        // GPU-texture frame hook: same off-screen re-render, but the texture is
        // handed over without a CPU read-back — for live frame-sharing (Syphon).
        // Gated on `wantsRenderedTextures` so a sketch that isn't sharing pays
        // nothing; armed live, so a sharer can start/stop between frames.
        if sketch.wantsRenderedTextures {
            let w = Int(sketch.width.rounded()), h = Int(sketch.height.rounded())
            // While accumulating, share the on-screen pile directly (a re-render
            // would double-accumulate); otherwise re-render this frame off-screen.
            let texture = sketch.drawer.accumulates
                ? renderer.accumulatedTexture(sketch.drawer)
                : renderer.texture(of: sketch.drawer,
                                   viewport: SIMD2<Float>(Float(sketch.width), Float(sketch.height)),
                                   width: w, height: h)
            if let texture { sketch.runFrameRendered(texture: texture) }
        }
    }

    /// Resolve the sketch's logical canvas, in points. For `.auto`/`.fixed` that's
    /// `canvasSize` itself: the window is only a scaled preview of it, so the canvas
    /// stays stable across displays and matches what `--export` renders. For
    /// `.resizable` the canvas follows the window, so use the view's bounds (already
    /// in points). We deliberately don't derive points from
    /// `drawableSize / backingScale` — that scale is unreliable before the view
    /// joins a window (it reads 1 on a Retina display), which silently doubled the
    /// canvas and left mouse coordinates at half scale.
    private func updateCanvasSize(from view: MTKView, drawableSize _: CGSize) {
        if case .resizable = sketch.windowMode {
            let pts = view.bounds.size
            guard pts.width > 0, pts.height > 0 else { return }
            sketch.setCanvasSize(width: Double(pts.width), height: Double(pts.height))
        } else {
            sketch.setCanvasSize(width: Double(sketch.canvasSize.width),
                                 height: Double(sketch.canvasSize.height))
        }
    }
}

// MARK: - Shared MTKView configuration

/// An `MTKView` that reports the cursor position to its `Sketch` as
/// `mouseX`/`mouseY`, in sketch coordinates (points, top-left origin). AppKit's
/// view space is y-up, so y is flipped.
private final class OllinMTKView: MTKView {
    weak var sketch: Sketch?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.inVisibleRect` keeps the area sized to the view; `.mouseMoved`
        // delivers moves even when no button is held.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { reportPointer(event) }
    override func mouseDragged(with event: NSEvent) { reportPointer(event) }
    override func mouseDown(with event: NSEvent) {
        // A click reclaims keyboard focus (e.g. after a click on an inspector
        // control moved first responder away), so the canvas keeps the keys.
        window?.makeFirstResponder(self)
        reportPointer(event)
        sketch?.mouseIsPressed = true
        sketch?.mousePressed()
    }
    override func mouseUp(with event: NSEvent) {
        reportPointer(event)
        sketch?.mouseIsPressed = false
        sketch?.mouseReleased()
    }

    // MARK: Keyboard

    /// Required for the view to receive `keyDown`/`keyUp`.
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Take keyboard focus once we're in a window, so a sketch reacts to keys
        // without the user clicking the canvas first.
        window?.makeFirstResponder(self)
    }

    /// Hand first-responder status back to the window before we leave it, so a
    /// torn-down canvas can't linger in the window's responder chain. Without this,
    /// switching sketches (the gallery rebuilds the canvas per example) frees a view
    /// that's still the window's first responder, and the next responder-chain walk
    /// — e.g. clicking another example in the sidebar — dereferences the freed view
    /// and crashes (EXC_BAD_ACCESS in `-[NSResponder nextResponder]`).
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Auto-repeat fires keyDown over and over while held; the hook is
        // once-per-press, so ignore repeats (held-key response polls isKeyDown).
        guard !event.isARepeat else { return }
        dispatchKey(event, pressed: true)
    }

    override func keyUp(with event: NSEvent) {
        dispatchKey(event, pressed: false)
    }

    /// Drop held keys when focus leaves; without a matching `keyUp` a key held
    /// across a focus change would otherwise stay stuck down.
    override func resignFirstResponder() -> Bool {
        sketch?.clearHeldKeys()
        return super.resignFirstResponder()
    }

    private func dispatchKey(_ event: NSEvent, pressed: Bool) {
        guard let sketch else { return }
        let (character, code) = Self.interpret(event)
        sketch.handleKey(character: character, code: code, pressed: pressed)
        if pressed { sketch.keyPressed() } else { sketch.keyReleased() }
    }

    /// Resolve an AppKit key event to Ollin's model: a named `KeyCode` for keys
    /// with no useful character (arrows, the function row), otherwise the typed
    /// character. Exactly one of the two is non-`nil`.
    private static func interpret(_ event: NSEvent) -> (Character?, KeyCode?) {
        if let code = KeyCode(event: event) { return (nil, code) }
        if let character = event.charactersIgnoringModifiers?.first { return (character, nil) }
        return (nil, nil)
    }

    /// Seed `mouseX`/`mouseY` from the cursor's current location, so a
    /// mouse-driven sketch reflects where the pointer actually is on the first
    /// frame instead of reading (0, 0) until the first move. Uses the real
    /// cursor position even if it's currently outside the window; it
    /// self-corrects the instant the pointer moves over the canvas.
    func seedPointer() {
        guard let window else { return }
        report(windowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func reportPointer(_ event: NSEvent) {
        report(windowPoint: event.locationInWindow)
    }

    /// Convert a point in window coordinates to sketch space and hand it to the
    /// sketch. The view's bounds are in points, but the logical canvas
    /// (`sketch.width`/`height`) may be larger — e.g. a 1080 canvas shown in an
    /// 810-pt preview window — so normalize by the bounds and rescale into canvas
    /// space. AppKit is y-up, so y is flipped to the sketch's top-left origin.
    private func report(windowPoint: NSPoint) {
        guard let sketch else { return }
        let p = convert(windowPoint, from: nil)
        let bw = Double(bounds.width), bh = Double(bounds.height)
        let x = bw > 0 ? Double(p.x) / bw * sketch.width : Double(p.x)
        let y = bh > 0 ? (bh - Double(p.y)) / bh * sketch.height : bh - Double(p.y)
        sketch.setMouse(x: x, y: y)
    }
}

/// Maps an AppKit key event to a named `KeyCode`, or `nil` for an ordinary
/// character key (which the view reports through `key` instead). Lives here, on
/// the AppKit side of the seam, so the `KeyCode` type itself stays free of
/// AppKit for the eventual UIKit path.
private extension KeyCode {
    init?(event: NSEvent) {
        if let special = event.specialKey {
            switch special {
            case .upArrow: self = .upArrow
            case .downArrow: self = .downArrow
            case .leftArrow: self = .leftArrow
            case .rightArrow: self = .rightArrow
            case .carriageReturn, .newline: self = .return
            case .enter: self = .enter
            case .tab: self = .tab
            case .delete: self = .delete            // the Backspace key
            case .deleteForward: self = .forwardDelete
            case .home: self = .home
            case .end: self = .end
            case .pageUp: self = .pageUp
            case .pageDown: self = .pageDown
            default:
                // The function row (F1…F35) sits in a contiguous block, so derive
                // its number rather than enumerate every case.
                let first = NSEvent.SpecialKey.f1.rawValue
                let last = NSEvent.SpecialKey.f35.rawValue
                guard (first...last).contains(special.rawValue) else { return nil }
                self = .function(special.rawValue - first + 1)
            }
            return
        }
        // Escape isn't an NSEvent.SpecialKey; catch it by its hardware key code.
        if event.keyCode == 53 { self = .escape; return }
        return nil
    }
}

/// The color format every render target uses: 8-bit BGRA, **sRGB-encoded**, so
/// the GPU blends and resolves MSAA in linear light (the shaders output linear
/// color and the target encodes on store). Shared by the live view and the
/// off-screen export paths so their pixels match.
let ollinColorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

/// MSAA sample count for the triangle path — 8× where the device supports it (it
/// sharpens thin strokes, polygon/curve outlines, and tessellated text), else
/// the universally-supported 4×. The SDF path is analytically anti-aliased and
/// doesn't depend on this. It's the sample count of the renderer's float
/// intermediate, not of the drawable (which is single-sample — see below).
func ollinPreferredSampleCount(_ device: MTLDevice) -> Int {
    device.supportsTextureSampleCount(8) ? 8 : 4
}

@MainActor
private func makeOllinMTKView(device: MTLDevice, size: CGSize, sketch: Sketch) -> MTKView {
    let view = OllinMTKView(frame: CGRect(origin: .zero, size: size), device: device)
    view.sketch = sketch
    view.colorPixelFormat = ollinColorPixelFormat
    // The drawable is the present target: single-sample. MSAA is done in the
    // renderer's float intermediate, then resolved before the present pass.
    view.sampleCount = 1
    view.isPaused = false                    // run continuously...
    view.enableSetNeedsDisplay = false       // ...driven by the display timer
    view.preferredFramesPerSecond = NSScreen.main?.maximumFramesPerSecond ?? 60
    return view
}

// MARK: - SwiftUI host

/// A SwiftUI view that hosts a running `Sketch`. Handy if you want to embed a
/// sketch in a SwiftUI app; standalone `swift run` sketches use `OllinApp.run`
/// (via `Sketch.main()`) instead.
///
/// ```swift
/// SketchView(HelloCircle())
///     .frame(width: 1080, height: 1080)
/// ```
///
/// Pass `onRunner` to receive the `SketchRunner` once the view is created — for
/// hosts that need to drive it (live reload via `reload(to:)`, toggle
/// `loop()`/`noLoop()`). Plain embedders can ignore it.
///
/// Pass `stats` to share the live `FrameStats` with another view (the live
/// host's inspector does this so its readout and the overlay are one source of
/// truth). Left nil, the view owns its own — enough for the on-canvas overlay.
public struct SketchView: View {
    private let sketch: Sketch
    private let injectedStats: FrameStats?
    private let showsInspectorPanel: Bool
    private let onRunner: (@MainActor (SketchRunner) -> Void)?

    /// Owned stats for standalone/gallery hosts that don't inject their own.
    @State private var ownedStats = FrameStats()
    /// The floating "Show FPS" inspector panel, summoned by the menu toggle.
    @State private var statsPanel = StatsPanelController()
    /// The shared toggle the "Show FPS" command flips.
    @AppStorage(OllinHUD.showStatsKey) private var showStats = false

    /// - Parameter showsInspectorPanel: whether this view honors the "Show FPS"
    ///   toggle by summoning the detached inspector panel. The live host passes
    ///   `false` because its sidebar already shows the same content, so the panel
    ///   would just duplicate it; standalone and gallery (no sidebar) leave it on.
    public init(_ sketch: Sketch,
                stats: FrameStats? = nil,
                showsInspectorPanel: Bool = true,
                onRunner: (@MainActor (SketchRunner) -> Void)? = nil) {
        self.sketch = sketch
        self.injectedStats = stats
        self.showsInspectorPanel = showsInspectorPanel
        self.onRunner = onRunner
    }

    private var stats: FrameStats { injectedStats ?? ownedStats }

    public var body: some View {
        MetalCanvas(sketch: sketch, stats: stats, onRunner: onRunner)
            .onAppear { syncPanel() }
            .onChange(of: showStats) { _, _ in syncPanel() }
            .onDisappear { statsPanel.close() }
    }

    /// Reflect the "Show FPS" toggle onto the floating panel. A no-op for hosts
    /// that opt out (the live host), which have their own inspector.
    private func syncPanel() {
        guard showsInspectorPanel else { return }
        statsPanel.sync(visible: showStats, sketch: sketch, stats: stats)
    }
}

/// The `MTKView`-backed half of `SketchView`: it builds the renderer + runner and
/// drives the per-frame loop. Kept private so the public surface is the SwiftUI
/// `View` above (which layers the overlay on top); this stays the
/// AppKit/UIKit-portability seam.
private struct MetalCanvas: NSViewRepresentable {
    let sketch: Sketch
    let stats: FrameStats
    let onRunner: (@MainActor (SketchRunner) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        // Initial size only; SwiftUI resizes the view to its frame on layout.
        let view = makeOllinMTKView(device: device, size: sketch.canvasSize.cgSize, sketch: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.observeStats(into: stats)
        view.delegate = runner
        context.coordinator.runner = runner   // retain the runner
        onRunner?(runner)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    /// Stop the old view's loop when SwiftUI removes it — notably when the gallery
    /// swaps one example for another (the detail pane is keyed by example `id`, so
    /// each switch dismantles the previous `MetalCanvas`). Pausing the display
    /// timer and dropping the delegate keeps an abandoned view from ticking after
    /// it leaves the hierarchy, and releases the runner (and its renderer).
    static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
        nsView.isPaused = true
        nsView.delegate = nil
        coordinator.runner = nil
    }

    final class Coordinator {
        var runner: SketchRunner?
    }
}

// MARK: - Standalone app boot (for `swift run`-ing a sketch)

/// Boots a minimal AppKit app that runs a single sketch in a window. This is
/// the path each `Examples/` target uses (via `Sketch.main()`), and it works
/// from the terminal with `swift run` — no Xcode or app bundle required.
///
/// Main-actor isolated: it owns `NSApplication`/`NSWindow`/`MTKView`, all of
/// which are main-actor types.
@MainActor
public enum OllinApp {

    /// The instance handed to `run`, read back by `OllinSketchApp` once SwiftUI
    /// instantiates it. (SwiftUI builds the `App` itself, so the sketch is passed
    /// out-of-band rather than through an initializer.)
    fileprivate static var standaloneSketch: Sketch?

    /// Boot a window running `sketch` and start the app; does not return. Hosts
    /// the sketch in a `SketchView` inside a SwiftUI `App` (`OllinSketchApp`) —
    /// the same lifecycle the live host and gallery use. This is the
    /// `swift run Example-X` path, reached via `Sketch.main()`.
    public static func run(_ sketch: Sketch) {
        standaloneSketch = sketch
        OllinSketchApp.main()
    }

    /// The window size for `sketch`, resolved from its `windowMode`. `.auto` and
    /// `.resizable` open at the screen-fit size (`.resizable` can then be dragged
    /// from there); `.fixed(f)` is an explicit fraction of `canvasSize`.
    public static func windowSize(for sketch: Sketch) -> CGSize {
        switch sketch.windowMode {
        case .auto, .resizable:
            return windowSize(fitting: sketch.canvasSize.cgSize)
        case .fixed(let fraction):
            let canvas = sketch.canvasSize.cgSize
            return CGSize(width: canvas.width * fraction, height: canvas.height * fraction)
        }
    }

    /// The auto-fit window size for an `export` resolution: 1:1 when the screen has
    /// room, otherwise the largest clean fraction (¾, ½, …) that fits within ~90%
    /// of the main screen, and an exact shrink-to-fit if even those are too big, so
    /// it always fits. A 1080² sketch opens at 1080 on a large display and 810 on a
    /// 14"/16" laptop. Falls back to ¾ when no screen is readable (e.g. headless).
    public static func windowSize(fitting export: CGSize) -> CGSize {
        guard let available = NSScreen.main?.visibleFrame.size else {
            return CGSize(width: export.width * 0.75, height: export.height * 0.75)
        }
        let maxWidth = available.width * 0.9, maxHeight = available.height * 0.9
        func fits(_ f: Double) -> Bool {
            export.width * f <= maxWidth && export.height * f <= maxHeight
        }
        // Largest clean fraction that fits (1:1 when there's room, a comfortable
        // step down otherwise); if none fit, an exact shrink so it always fits.
        let fraction = [1.0, 0.75, 0.5, 0.375, 0.25].first(where: fits)
            ?? min(maxWidth / export.width, maxHeight / export.height)
        return CGSize(width: export.width * fraction, height: export.height * fraction)
    }

    /// The window size for a default (un-overridden) sketch — `Sketch.defaultSize`
    /// fitted to the screen. Hosts with their own chrome (the gallery, the live
    /// host) size their sketch pane to this.
    public static var defaultWindowSize: CGSize { windowSize(fitting: Sketch.defaultSize.cgSize) }

    /// Render one frame of `sketch` off-screen and return it as a `CGImage` — no
    /// window, no display loop. Drives the sketch headlessly: `setup()`, then
    /// `draw()` advanced to `frame` at `fps` (so an animated or stateful sketch
    /// renders the right moment). Same pipeline, MSAA, and blending as the live
    /// view and `--export`, so the pixels match.
    ///
    /// This is the headless frame-grab: `export` is this plus a PNG write, and
    /// snapshot tests compare its result against a committed reference. Returns
    /// `nil` if there's no Metal device or the render fails (a library-friendly
    /// soft failure, unlike `export`'s hard exit).
    public static func image(of sketch: Sketch, frame: Int = 0, fps: Double = 60) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                                sampleCount: ollinPreferredSampleCount(device)) else {
            return nil
        }
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        let width = size.width, height = size.height
        // In accumulation mode (`noClear`) each frame piles onto the persistent
        // surface, so render every frame into it — the captured frame N is the
        // built-up canvas, not a fresh draw of frame N alone.
        var accumulated: CGImage?
        let target = max(0, frame)
        for k in 0...target {                        // advance so frame N is correct
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            if sketch.drawer.accumulates {
                accumulated = renderer.accumulatedImage(of: sketch.drawer, viewport: viewport,
                                                        width: width, height: height)
            } else if k < target {
                // A stateful compute sim must run on the GPU every frame to evolve;
                // the intermediate frames we don't capture still need their steps
                // executed (only the final frame is rendered + read back below).
                renderer.stepCompute(sketch.drawer)
            }
        }
        if sketch.drawer.accumulates { return accumulated }
        return renderer.image(of: sketch.drawer, viewport: viewport, width: width, height: height)
    }

    /// Render one frame of `sketch` off-screen and write it as a PNG — no window.
    /// Drives the sketch headlessly: `setup()`, then `draw()` advanced to `frame`
    /// at `fps` (so animated/stateful sketches export the right moment). The
    /// headless frame-grab (`image(of:)`) plus a PNG write, and the basis for PNG
    /// sequences → video.
    public static func export(_ sketch: Sketch, to path: String, frame: Int = 0, fps: Double = 60) {
        guard let cgImage = image(of: sketch, frame: frame, fps: fps) else {
            fatalError("Ollin: failed to render the frame for export (no Metal device?)")
        }
        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            fatalError("Ollin: failed to encode PNG")
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Ollin: exported frame \(frame) → \(path) (\(cgImage.width)×\(cgImage.height))")
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
    }

    /// Render a deterministic PNG sequence of `sketch` into `directory` — no
    /// window. Drives the sketch headlessly at a **fixed timestep**
    /// (`deltaTime = 1/fps`, `time = frame/fps`), decoupled from wall-clock, so
    /// every frame renders the exact moment it should no matter how long it takes
    /// — a ten-minute render still assembles into a smooth `fps` video. Frames are
    /// written as `frame_00001.png`, `frame_00002.png`, … (zero-padded from
    /// `startFrame`), ready for `ffmpeg`. One sketch instance and renderer are
    /// reused across the run, so stateful sketches evolve frame to frame.
    ///
    /// `skipSeconds` runs the sketch (clock + `draw()`) for that long *before*
    /// capturing, without writing — so a stateful sketch settles into motion
    /// first; the captured clock then continues from `skipSeconds` onward, and
    /// the written frames still number from `startFrame`.
    ///
    /// For a *reproducible* sequence, seed the sketch (`seed(…)` in `setup()`);
    /// unseeded, it's internally consistent within a run but differs between runs.
    public static func exportSequence(_ sketch: Sketch, to directory: String,
                                      frames: Int, fps: Double = 60,
                                      startFrame: Int = 1, skipSeconds: Double = 0) {
        guard frames > 0 else { return }
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Ollin: failed to create \(directory): \(error)")
        }

        let size = sketch.canvasSize
        let skipFrames = max(0, Int((skipSeconds * fps).rounded()))
        let skipNote = skipFrames > 0 ? String(format: " (after %gs warmup)", skipSeconds) : ""
        print("Ollin: exporting \(frames) frames at \(Int(fps)) fps\(skipNote) → \(directory) (\(size.width)×\(size.height))")

        let elapsed = renderFrames(sketch, frames: frames, fps: fps, skipSeconds: skipSeconds) { cgImage, index in
            guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                fatalError("Ollin: failed to encode PNG for frame \(index)")
            }
            let name = String(format: "frame-%05d.png", startFrame + index)
            let path = (directory as NSString).appendingPathComponent(name)
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                fatalError("Ollin: failed to write \(path): \(error)")
            }
        }

        print(String(format: "Ollin: exported %d frames in %.1fs → %@", frames, elapsed, directory))
        print("Assemble with ffmpeg (or use --export-video / --export-gif directly):")
        print("  ffmpeg -framerate \(Int(fps)) -start_number \(startFrame) \\")
        print("    -i \(directory)/frame-%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 \\")
        print("    \(directory)/out.mp4")
    }

    /// Drive `sketch` headlessly at a **fixed timestep** (`time = frame/fps`,
    /// `deltaTime = 1/fps` — never wall-clock) and hand each rendered frame to
    /// `write` with its 0-based index. The shared engine behind the
    /// PNG-sequence, video, and GIF exports: one sketch instance and renderer
    /// are reused across the run (stateful sketches evolve frame to frame),
    /// `skipSeconds` runs the sketch that long *before* capturing (the captured
    /// clock continues from there), and a single rewriting progress line shows
    /// pct done · render throughput. Returns the elapsed wall-clock seconds.
    @discardableResult
    static func renderFrames(_ sketch: Sketch, frames: Int, fps: Double,
                             skipSeconds: Double,
                             write: (CGImage, Int) -> Void) -> Double {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        let renderer: MetalRenderer
        do {
            renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        } catch {
            fatalError("Ollin: failed to initialize the Metal renderer: \(error)")
        }

        let size = sketch.canvasSize
        let width = size.width, height = size.height
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()

        let skipFrames = max(0, Int((skipSeconds * fps).rounded()))
        let wallStart = CACurrentMediaTime()
        for k in 0..<(skipFrames + frames) {
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()                          // run every frame so state settles

            // In accumulation mode (`noClear`) the persistent pile must build every
            // frame — including warmup — so render into it always; otherwise warmup
            // frames skip the render entirely.
            let accumulates = sketch.drawer.accumulates
            var rendered: CGImage?
            if accumulates || k >= skipFrames {
                rendered = accumulates
                    ? renderer.accumulatedImage(of: sketch.drawer, viewport: viewport, width: width, height: height)
                    : renderer.image(of: sketch.drawer, viewport: viewport, width: width, height: height)
            } else {
                // Non-accumulating warmup frame: not captured, but a stateful compute
                // sim still needs its steps run on the GPU so the field evolves into
                // the first captured frame.
                renderer.stepCompute(sketch.drawer)
            }

            if k < skipFrames {                           // warmup: built the pile, don't write
                FileHandle.standardError.write(Data(
                    String(format: "\r  warming up %d/%d    ", k + 1, skipFrames).utf8))
                continue
            }

            guard let cgImage = rendered else {
                fatalError("Ollin: failed to render frame \(k)")
            }
            let done = k - skipFrames + 1                  // 1-based count of written frames
            write(cgImage, done - 1)

            // A single rewriting progress line: pct done · render throughput.
            let elapsed = CACurrentMediaTime() - wallStart
            let renderFPS = elapsed > 0 ? Double(done) / elapsed : 0
            let line = String(format: "\r  rendering %d/%d (%d%%) · %.0f fps    ",
                              done, frames, done * 100 / frames, renderFPS)
            FileHandle.standardError.write(Data(line.utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))
        return CACurrentMediaTime() - wallStart
    }

    /// Run `sketch`'s draw loop headlessly for `frames` frames — no window, no
    /// GPU, no vsync — timing only the CPU cost of `setup()` + per-frame
    /// `performDraw()` (the tessellation that builds `drawer.vertices`). Prints
    /// ms/frame, vertices/frame, and the implied CPU-bound FPS ceiling, so a
    /// rendering-performance change can be measured deterministically.
    static func benchmark(_ sketch: Sketch, frames: Int = 600, fps: Double = 60, gpu: Bool = false) {
        let n = max(1, frames)
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()
        // One warm-up frame so first-time buffer growth doesn't skew the average.
        sketch.advance(time: 0, deltaTime: 1 / fps, frameRate: fps)
        sketch.performDraw()

        // Optional end-to-end timing: render each frame off-screen on the GPU.
        // Conservative — it also pays per-frame MSAA texture allocation and a
        // full readback the live path doesn't — so the real headroom is higher.
        if gpu {
            guard let device = MTLCreateSystemDefaultDevice() else {
                fatalError("Ollin requires a Metal-capable GPU.")
            }
            guard let renderer = try? MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                                    sampleCount: ollinPreferredSampleCount(device)) else {
                fatalError("Ollin: failed to initialize the Metal renderer.")
            }
            let w = size.width, h = size.height
            let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
            _ = renderer.image(of: sketch.drawer, viewport: viewport, width: w, height: h)  // warm GPU

            let start = CACurrentMediaTime()
            for k in 1...n {
                sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
                sketch.performDraw()
                _ = renderer.image(of: sketch.drawer, viewport: viewport, width: w, height: h)
            }
            let ms = (CACurrentMediaTime() - start) / Double(n) * 1000
            print(String(format: "Ollin bench: %d frames · %.3f ms/frame (CPU+GPU, incl. readback) · ~%.0f fps",
                         n, ms, ms > 0 ? 1000 / ms : 0))
            return
        }

        let start = CACurrentMediaTime()
        var vertexTotal = 0
        var instanceTotal = 0
        for k in 1...n {
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            vertexTotal += sketch.drawer.vertices.count
            instanceTotal += sketch.drawer.sdfInstances.count
        }
        let elapsed = CACurrentMediaTime() - start
        let msPerFrame = elapsed / Double(n) * 1000
        let ceiling = msPerFrame > 0 ? 1000 / msPerFrame : 0
        print(String(format: "Ollin bench: %d frames · %.0f verts + %.0f sdf/frame · %.3f ms/frame (CPU) · ~%.0f fps CPU ceiling",
                     n, Double(vertexTotal) / Double(n), Double(instanceTotal) / Double(n), msPerFrame, ceiling))
    }

}

public extension Sketch {
    /// Entry point that lets a single sketch file be `@main` with no
    /// boilerplate:
    ///
    /// ```swift
    /// @main
    /// final class HelloCircle: Sketch {
    ///     override func draw() { /* ... */ }
    /// }
    /// ```
    ///
    /// `@main` invokes this inherited `main()` with `Self` bound to the
    /// concrete subclass, so `Self()` builds *that* sketch (which is why
    /// `Sketch.init()` is `required`) and `OllinApp.run` boots it. Each
    /// `Examples/` target uses this.
    @MainActor
    static func main() {
        // `swift run Example-X --export <path> [--frame N]` writes a PNG and
        // exits (no window); otherwise the sketch runs in a window as usual.
        let args = CommandLine.arguments
        // `--export-sequence <dir> (--frames N | --seconds S) [--fps F] [--start N]`
        // renders a deterministic numbered PNG sequence and exits.
        if let i = args.firstIndex(of: "--export-sequence"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let dir = args[i + 1]
            let fps = value("--fps").flatMap(Double.init) ?? 60
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                frames = Int((seconds * fps).rounded())
            }
            let start = value("--start").flatMap(Int.init) ?? 1
            let skip = value("--skip").flatMap(Double.init) ?? 0
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-sequence <dir> (--frames N | --seconds S) [--fps F] [--skip S] [--start N]\n".utf8))
                return
            }
            OllinApp.exportSequence(Self(), to: dir, frames: frames, fps: fps,
                                    startFrame: start, skipSeconds: skip)
            return
        }
        // `--export-video <path> (--frames N | --seconds S) [--fps F] [--skip S]
        // [--codec h264|hevc|prores422|prores4444] [--bitrate MBPS] [--quality 0..1]`
        // encodes a video (.mp4/.mov) and exits.
        if let i = args.firstIndex(of: "--export-video"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let fps = value("--fps").flatMap(Double.init) ?? 60
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                frames = Int((seconds * fps).rounded())
            }
            let skip = value("--skip").flatMap(Double.init) ?? 0
            var codec = VideoCodec.h264
            if let name = value("--codec") {
                guard let parsed = VideoCodec(rawValue: name) else {
                    FileHandle.standardError.write(Data(
                        "unknown codec '\(name)' — one of: \(VideoCodec.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                    return
                }
                codec = parsed
            }
            let bitrate = value("--bitrate").flatMap(Double.init).map { Int($0 * 1_000_000) }
            let quality = value("--quality").flatMap(Double.init)
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-video <path> (--frames N | --seconds S) [--fps F] [--skip S] [--codec C] [--bitrate MBPS] [--quality 0..1]\n".utf8))
                return
            }
            OllinApp.exportVideo(Self(), to: args[i + 1], frames: frames, fps: fps,
                                 codec: codec, bitsPerSecond: bitrate, quality: quality,
                                 skipSeconds: skip)
            return
        }
        // `--export-gif <path> (--frames N | --seconds S) [--fps F] [--skip S]
        // [--gif-width PX]` writes a looping animated GIF and exits.
        if let i = args.firstIndex(of: "--export-gif"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let fps = value("--fps").flatMap(Double.init) ?? 25
            var frames = value("--frames").flatMap(Int.init) ?? 0
            if frames <= 0, let seconds = value("--seconds").flatMap(Double.init) {
                frames = Int((seconds * fps).rounded())
            }
            let skip = value("--skip").flatMap(Double.init) ?? 0
            let width = value("--gif-width").flatMap(Int.init)
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-gif <path> (--frames N | --seconds S) [--fps F] [--skip S] [--gif-width PX]\n".utf8))
                return
            }
            OllinApp.exportGIF(Self(), to: args[i + 1], frames: frames, fps: fps,
                               width: width, skipSeconds: skip)
            return
        }
        if let i = args.firstIndex(of: "--export"), i + 1 < args.count {
            var frame = 0
            if let f = args.firstIndex(of: "--frame"), f + 1 < args.count {
                frame = Int(args[f + 1]) ?? 0
            }
            OllinApp.export(Self(), to: args[i + 1], frame: frame)
            return
        }
        // `swift run Example-X --export-svg <path> [--frame N]` writes a vector SVG
        // of one frame and exits (no window, no GPU). Add `--hatch` (or
        // `--cross-hatch`) to plot solid fills as pen line work:
        // `--hatch-spacing N` and `--hatch-angle DEG` tune it.
        if let i = args.firstIndex(of: "--export-svg"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            var frame = 0
            if let f = value("--frame").flatMap(Int.init) { frame = f }
            var hatching: Hatching?
            if args.contains("--hatch") || args.contains("--cross-hatch") {
                var h = Hatching()
                if let s = value("--hatch-spacing").flatMap(Double.init) { h.spacing = s }
                if let a = value("--hatch-angle").flatMap(Double.init) { h.angle = a * .pi / 180 }
                if args.contains("--cross-hatch") { h.crossHatch = true }
                hatching = h
            }
            OllinApp.exportSVG(Self(), to: args[i + 1], frame: frame, hatching: hatching)
            return
        }
        if let i = args.firstIndex(of: "--bench") {
            var frames = 600
            if i + 1 < args.count, let f = Int(args[i + 1]) { frames = f }
            OllinApp.benchmark(Self(), frames: frames, gpu: args.contains("--gpu"))
            return
        }
        OllinApp.run(Self())
    }
}

// MARK: - Standalone SwiftUI launcher

/// SwiftUI `App` that runs a single `Sketch` — the `swift run Example-X`
/// launcher behind `Sketch.main()` / `OllinApp.run`. The app *lifecycle* stays
/// SwiftUI (it owns the main menu, so `OllinHUDCommands` plugs in), but the
/// sketch window itself is an AppKit `NSWindow` hosting the SwiftUI
/// `SketchView` through `NSHostingView`, built by the delegate below.
///
/// The AppKit window is deliberate: on macOS 26, windows owned by SwiftUI
/// window scenes that host a Metal layer intermittently flicker between 100%
/// and 98% of their frame size while being dragged — a WindowServer bug (the
/// oscillation shows in `CGWindowListCopyWindowInfo` bounds while the app-side
/// geometry stays constant). AppKit-owned windows with identical content have
/// not shown it. The placeholder `Settings` scene satisfies SwiftUI's scene
/// requirement without opening a window, and the empty `.appSettings` command
/// group removes the dangling "Settings…" menu item it would otherwise add.
@MainActor
struct OllinSketchApp: App {
    @NSApplicationDelegateAdaptor(StandaloneAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {}
                OllinHUDCommands()
            }
    }
}

/// Builds and owns the AppKit sketch window, brings the bundleless `swift run`
/// process to the front, and quits when the window closes so the terminal
/// command returns. A standalone example is a single window run from the
/// terminal, so a stray Cmd+W (Close) should end the run like Cmd+Q — the full
/// `OllinLive` host and examples gallery are actual apps and keep the normal
/// close-doesn't-quit behavior.
private final class StandaloneAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        openSketchWindow()
        NSApp.activate(ignoringOtherApps: true)
        // Quit explicitly when the sketch window closes — Cmd+W then ends the
        // run like Cmd+Q. Quit only when no real window is left: the floating
        // "Show Inspector" panel is an `NSPanel` (closing *it* mustn't quit),
        // and opening it spins up and tears down transient helper windows whose
        // close must be ignored too. So react after the close settles and check
        // what's still on screen.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let realWindowsLeft = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
                if !realWindowsLeft { NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Create the sketch window: AppKit shell, SwiftUI content.
    @MainActor
    private func openSketchWindow() {
        guard let sketch = OllinApp.standaloneSketch else { return }
        let contentSize = OllinApp.windowSize(for: sketch)
        let isResizable: Bool = {
            if case .resizable = sketch.windowMode { return true }
            return false
        }()

        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if isResizable { style.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = sketch.title
        window.isReleasedWhenClosed = false

        // `.resizable` follows the user's drag down to a sane floor (the canvas
        // tracks the view); fixed modes pin the content size exactly, which
        // also clamps any stale autosaved frame restored below.
        if isResizable {
            window.contentMinSize = NSSize(width: 200, height: 200)
        } else {
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
        }

        let root: AnyView = isResizable
            ? AnyView(SketchView(sketch)
                .frame(minWidth: 200, maxWidth: .infinity,
                       minHeight: 200, maxHeight: .infinity))
            : AnyView(SketchView(sketch)
                .frame(width: contentSize.width, height: contentSize.height))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        window.center()
        // Same autosave name the previous SwiftUI window scene wrote, so an
        // existing saved position carries over.
        window.setFrameAutosaveName("ollin-sketch")
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
