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
    /// Set by `OllinApp.boot` so `reload(to:)` can refresh the window title on a
    /// live swap. Nil when embedded via `SketchView`.
    weak var window: NSWindow?

    /// Optional hook for a host to observe the smoothed frame rate. Called a few
    /// times a second (not every frame) so a live-FPS readout updates without
    /// thrashing SwiftUI. Nil for standalone runs.
    public var onFrameRate: (@MainActor (Double) -> Void)?

    private var didSetup = false
    private var didReload = false        // call onReload() after the post-reload setup()
    private var pendingSetupRerun = false // re-run setup() in place (e.g. an asset changed)
    private var clockCarry: Double?      // seconds to continue `time` from across a reload
    private var startTime: CFTimeInterval = 0
    private var lastTime: CFTimeInterval = 0
    private var smoothedFrameRate: Double = 0

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
        didSetup = false            // re-run setup() next frame
        didReload = true            // ...then call onReload() once
        view?.isPaused = false      // a prior noLoop() must not freeze the reload
        window?.title = newSketch.title
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
        if sketch.frameCount % 15 == 0 { onFrameRate?(smoothedFrameRate) }   // ~a few Hz
        sketch.performDraw()

        renderer.render(sketch.drawer,
                        viewport: SIMD2<Float>(Float(sketch.width), Float(sketch.height)),
                        in: view)
    }

    /// Convert the drawable's pixel size into logical points (sketch space).
    private func updateCanvasSize(from view: MTKView, drawableSize: CGSize) {
        let scale = view.window?.backingScaleFactor
            ?? view.layer?.contentsScale
            ?? 1
        let safeScale = scale == 0 ? 1 : scale
        sketch.setCanvasSize(width: Double(drawableSize.width) / Double(safeScale),
                             height: Double(drawableSize.height) / Double(safeScale))
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

    /// Convert a point in window coordinates to sketch space (points, top-left
    /// origin; AppKit is y-up, so y is flipped) and hand it to the sketch.
    private func report(windowPoint: NSPoint) {
        let p = convert(windowPoint, from: nil)
        sketch?.setMouse(x: Double(p.x), y: Double(bounds.height - p.y))
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
///     .frame(width: 800, height: 800)
/// ```
///
/// Pass `onRunner` to receive the `SketchRunner` once the view is created — for
/// hosts that need to drive it (live reload via `reload(to:)`, read its stats,
/// toggle `loop()`/`noLoop()`). Plain embedders can ignore it.
public struct SketchView: NSViewRepresentable {
    private let sketch: Sketch
    private let onRunner: (@MainActor (SketchRunner) -> Void)?

    public init(_ sketch: Sketch, onRunner: (@MainActor (SketchRunner) -> Void)? = nil) {
        self.sketch = sketch
        self.onRunner = onRunner
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        let view = makeOllinMTKView(device: device, size: sketch.preferredSize, sketch: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        view.delegate = runner
        context.coordinator.runner = runner   // retain the runner
        onRunner?(runner)
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {}

    public final class Coordinator {
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

    public static func run(_ sketch: Sketch) {
        _ = boot(sketch)
        NSApplication.shared.run()
    }

    /// Build the window, view, and runner for `sketch` and wire up the app, but
    /// *don't* start the run loop — the caller does that. `run` is just
    /// `boot` + `NSApplication.shared.run()`; the live host (OllinLive) calls
    /// `boot`, wires a file watcher to the returned runner's `reload(to:)`, and
    /// then starts the run loop itself. Returns the runner so the caller can
    /// drive live swaps.
    @discardableResult
    public static func boot(_ sketch: Sketch) -> SketchRunner {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }

        let size = sketch.preferredSize
        let view = makeOllinMTKView(device: device, size: size, sketch: sketch)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        view.delegate = runner

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = sketch.title
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        runner.window = window      // so reload(to:) can refresh the title

        // A tiny menu so Cmd-Q quits, and a delegate so closing the window ends
        // the process (and returns from `swift run`).
        app.mainMenu = makeMenu(quitTitle: "Quit Ollin")
        let delegate = OllinAppDelegate()
        app.delegate = delegate

        // Keep strong references alive for the lifetime of the app: the
        // MTKView delegate is weak, and the window/delegate would otherwise be
        // released as soon as the run loop starts.
        Retained.shared.runner = runner
        Retained.shared.window = window
        Retained.shared.delegate = delegate

        app.activate(ignoringOtherApps: true)
        return runner
    }

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

        let size = sketch.preferredSize
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

    private static func makeMenu(quitTitle: String) -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: quitTitle,
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        return mainMenu
    }

    /// Holds the few objects that must outlive `run()`.
    @MainActor
    private final class Retained {
        static let shared = Retained()
        var runner: SketchRunner?
        var window: NSWindow?
        var delegate: NSApplicationDelegate?
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
        if let i = args.firstIndex(of: "--export"), i + 1 < args.count {
            var frame = 0
            if let f = args.firstIndex(of: "--frame"), f + 1 < args.count {
                frame = Int(args[f + 1]) ?? 0
            }
            OllinApp.export(Self(), to: args[i + 1], frame: frame)
            return
        }
        OllinApp.run(Self())
    }
}

private final class OllinAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
