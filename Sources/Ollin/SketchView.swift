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
public final class SketchRunner: NSObject, MTKViewDelegate {

    private let sketch: Sketch
    private let renderer: MetalRenderer

    private var didSetup = false
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

        // noLoop()/loop() pause and resume the view's display timer.
        sketch.loopStateDidChange = { [weak view] looping in
            view?.isPaused = !looping
        }
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
            startTime = now
            lastTime = now
            sketch.setup()
            didSetup = true
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

private func makeOllinMTKView(device: MTLDevice, size: CGSize) -> MTKView {
    let view = MTKView(frame: CGRect(origin: .zero, size: size), device: device)
    view.colorPixelFormat = .bgra8Unorm
    view.sampleCount = 4                     // 4x MSAA -> anti-aliased outlines
    view.isPaused = false                    // run continuously...
    view.enableSetNeedsDisplay = false       // ...driven by the display timer
    view.preferredFramesPerSecond = NSScreen.main?.maximumFramesPerSecond ?? 60
    return view
}

// MARK: - SwiftUI host

/// A SwiftUI view that hosts a running `Sketch`. Handy if you want to embed a
/// sketch in a SwiftUI app; the `OllinSketch` demo uses `OllinApp.run` instead.
///
/// ```swift
/// SketchView(HelloCircle())
///     .frame(width: 800, height: 800)
/// ```
public struct SketchView: NSViewRepresentable {
    private let sketch: Sketch

    public init(_ sketch: Sketch) {
        self.sketch = sketch
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }
        let view = makeOllinMTKView(device: device, size: sketch.preferredSize)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        view.delegate = runner
        context.coordinator.runner = runner   // retain the runner
        return view
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {}

    public final class Coordinator {
        var runner: SketchRunner?
    }
}

// MARK: - Standalone app boot (for `swift run OllinSketch`)

/// Boots a minimal AppKit app that runs a single sketch in a window. This is
/// the path the `OllinSketch` executable uses, and it works from the terminal
/// with `swift run OllinSketch` — no Xcode or app bundle required.
public enum OllinApp {

    public static func run(_ sketch: Sketch) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Ollin requires a Metal-capable GPU.")
        }

        let size = sketch.preferredSize
        let view = makeOllinMTKView(device: device, size: size)
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

        // A tiny menu so Cmd-Q quits, and a delegate so closing the window ends
        // the process (and returns from `swift run`).
        app.mainMenu = makeMenu(quitTitle: "Quit \(sketch.title)")
        let delegate = OllinAppDelegate()
        app.delegate = delegate

        // Keep strong references alive for the lifetime of the app: the
        // MTKView delegate is weak, and the window/delegate would otherwise be
        // released as soon as `run()` is called.
        Retained.shared.runner = runner
        Retained.shared.window = window
        Retained.shared.delegate = delegate

        app.activate(ignoringOtherApps: true)
        app.run()
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
    private final class Retained {
        static let shared = Retained()
        var runner: SketchRunner?
        var window: NSWindow?
        var delegate: NSApplicationDelegate?
    }
}

private final class OllinAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
