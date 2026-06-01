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
            self.renderer = try MetalRenderer(device: device,
                                              pixelFormat: view.colorPixelFormat,
                                              sampleCount: view.sampleCount)
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
                                       sdfCount: sketch.drawer.sdfInstances.count))
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
        reportPointer(event)
        sketch?.mousePressed()
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

@MainActor
private func makeOllinMTKView(device: MTLDevice, size: CGSize, sketch: Sketch) -> MTKView {
    let view = OllinMTKView(frame: CGRect(origin: .zero, size: size), device: device)
    view.sketch = sketch
    view.colorPixelFormat = .bgra8Unorm
    view.sampleCount = 4                     // 4x MSAA -> anti-aliased outlines
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
    private let showsStatsOverlay: Bool
    private let onRunner: (@MainActor (SketchRunner) -> Void)?

    /// Owned stats for standalone/gallery hosts that don't inject their own.
    @State private var ownedStats = FrameStats()
    /// The shared toggle the "Show FPS" command flips.
    @AppStorage(OllinHUD.showStatsKey) private var showStats = false

    /// - Parameter showsStatsOverlay: whether this view honors the "Show FPS"
    ///   toggle with the on-canvas overlay. The live host passes `false` because
    ///   its inspector already shows the same stats, so the overlay would just
    ///   duplicate them; standalone and gallery (no inspector) leave it on.
    public init(_ sketch: Sketch,
                stats: FrameStats? = nil,
                showsStatsOverlay: Bool = true,
                onRunner: (@MainActor (SketchRunner) -> Void)? = nil) {
        self.sketch = sketch
        self.injectedStats = stats
        self.showsStatsOverlay = showsStatsOverlay
        self.onRunner = onRunner
    }

    private var stats: FrameStats { injectedStats ?? ownedStats }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MetalCanvas(sketch: sketch, stats: stats, onRunner: onRunner)
            if showStats && showsStatsOverlay {
                StatsOverlay(stats: stats)
            }
        }
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
        let view = makeOllinMTKView(device: device, size: sketch.canvasSize, sketch: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.observeStats(into: stats)
        view.delegate = runner
        context.coordinator.runner = runner   // retain the runner
        onRunner?(runner)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

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
            return windowSize(fitting: sketch.canvasSize)
        case .fixed(let fraction):
            return CGSize(width: sketch.canvasSize.width * fraction,
                          height: sketch.canvasSize.height * fraction)
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
    public static var defaultWindowSize: CGSize { windowSize(fitting: Sketch.defaultSize) }

    /// Render one frame of `sketch` off-screen and write it as a PNG — no window.
    /// Drives the sketch headlessly: `setup()`, then `draw()` advanced to `frame`
    /// at `fps` (so animated/stateful sketches export the right moment). This is
    /// the frame-grab seam, and the basis for PNG sequences → video.
    public static func export(_ sketch: Sketch, to path: String, frame: Int = 0, fps: Double = 60) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        let renderer: MetalRenderer
        do {
            renderer = try MetalRenderer(device: device, pixelFormat: .bgra8Unorm, sampleCount: 4)
        } catch {
            fatalError("Ollin: failed to initialize the Metal renderer: \(error)")
        }

        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()
        for k in 0...max(0, frame) {                 // advance so frame N is correct
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
        }

        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard let cgImage = renderer.image(of: sketch.drawer,
                                           viewport: SIMD2<Float>(Float(size.width), Float(size.height)),
                                           width: width, height: height) else {
            fatalError("Ollin: failed to render the frame for export")
        }

        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            fatalError("Ollin: failed to encode PNG")
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("Ollin: exported frame \(frame) → \(path) (\(width)×\(height))")
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
    /// For a *reproducible* sequence, seed the sketch (`seed(…)` in `setup()`);
    /// unseeded, it's internally consistent within a run but differs between runs.
    public static func exportSequence(_ sketch: Sketch, to directory: String,
                                      frames: Int, fps: Double = 60, startFrame: Int = 1) {
        guard frames > 0 else { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        let renderer: MetalRenderer
        do {
            renderer = try MetalRenderer(device: device, pixelFormat: .bgra8Unorm, sampleCount: 4)
        } catch {
            fatalError("Ollin: failed to initialize the Metal renderer: \(error)")
        }

        let size = sketch.canvasSize
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Ollin: failed to create \(directory): \(error)")
        }

        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()

        print("Ollin: exporting \(frames) frames at \(Int(fps)) fps → \(directory) (\(width)×\(height))")
        let wallStart = CACurrentMediaTime()
        for k in 0..<frames {
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            guard let cgImage = renderer.image(of: sketch.drawer, viewport: viewport,
                                               width: width, height: height) else {
                fatalError("Ollin: failed to render frame \(k)")
            }
            guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                fatalError("Ollin: failed to encode PNG for frame \(k)")
            }
            let name = String(format: "frame_%05d.png", startFrame + k)
            let path = (directory as NSString).appendingPathComponent(name)
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                fatalError("Ollin: failed to write \(path): \(error)")
            }

            // A single rewriting progress line: pct done · render throughput.
            let done = k + 1
            let elapsed = CACurrentMediaTime() - wallStart
            let renderFPS = elapsed > 0 ? Double(done) / elapsed : 0
            let line = String(format: "\r  rendering %d/%d (%d%%) · %.0f fps    ",
                              done, frames, done * 100 / frames, renderFPS)
            FileHandle.standardError.write(Data(line.utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))

        let elapsed = CACurrentMediaTime() - wallStart
        print(String(format: "Ollin: exported %d frames in %.1fs → %@", frames, elapsed, directory))
        print("Assemble with ffmpeg:")
        print("  ffmpeg -framerate \(Int(fps)) -start_number \(startFrame) \\")
        print("    -i \(directory)/frame_%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 \\")
        print("    \(directory)/out.mp4")
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
            guard let renderer = try? MetalRenderer(device: device, pixelFormat: .bgra8Unorm, sampleCount: 4) else {
                fatalError("Ollin: failed to initialize the Metal renderer.")
            }
            let w = Int(size.width.rounded()), h = Int(size.height.rounded())
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
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-sequence <dir> (--frames N | --seconds S) [--fps F] [--start N]\n".utf8))
                return
            }
            OllinApp.exportSequence(Self(), to: dir, frames: frames, fps: fps, startFrame: start)
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

/// SwiftUI `App` that runs a single `Sketch` in a window — the `swift run
/// Example-X` launcher behind `Sketch.main()` / `OllinApp.run`. One `Window`
/// hosting a `SketchView`, on the same SwiftUI lifecycle the live host and
/// gallery use. The sketch comes from `OllinApp.standaloneSketch` because
/// SwiftUI, not the caller, instantiates the `App`.
@MainActor
struct OllinSketchApp: App {
    @NSApplicationDelegateAdaptor(StandaloneAppDelegate.self) private var delegate
    private let sketch: Sketch

    init() { sketch = OllinApp.standaloneSketch! }

    /// The window's initial size, resolved from the sketch's `windowMode`.
    private var windowSize: CGSize { OllinApp.windowSize(for: sketch) }

    /// `.resizable` sketches get a freely resizable window (canvas follows it);
    /// `.auto`/`.fixed` get a window locked to `windowSize`.
    private var isResizable: Bool {
        if case .resizable = sketch.windowMode { return true }
        return false
    }

    var body: some Scene {
        Window(sketch.title, id: "ollin-sketch") {
            if isResizable {
                // Fill the window; the canvas tracks the resized view.
                SketchView(sketch)
                    .frame(minWidth: 200, maxWidth: .infinity,
                           minHeight: 200, maxHeight: .infinity)
            } else {
                SketchView(sketch)
                    .frame(width: windowSize.width, height: windowSize.height)
            }
        }
        .defaultSize(windowSize)
        // Fixed modes lock the window to its content; `.resizable` allows free
        // resize down to the content's minimum.
        .windowResizability(isResizable ? .contentMinSize : .contentSize)
        .commands { OllinHUDCommands() }
    }
}

/// Bring the bundleless `swift run` window to the front, and quit when it
/// closes so the terminal command returns.
private final class StandaloneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
