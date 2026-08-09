import Foundation
import AppKit
import SwiftUI
import MetalKit
import QuartzCore
import simd
import COllinShaders

/// The sketch runner currently drawing, so a host menu command can reach the
/// running sketch without a per-scene reference (the camera-view snaps in
/// `OllinCameraCommands`). Set each frame by the drawing runner; weak, so a closed
/// window's runner is released. The shipping hosts show one sketch window at a
/// time, so the most-recently-drawn runner is the right target.
@MainActor
enum OllinActiveSketch {
    static weak var runner: SketchRunner?
}

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

    /// Called after each frame with the renderer's current user-shader compile error
    /// (`nil` when every shader compiled). The live host shows it in the error
    /// overlay; a standalone run leaves it unset (the message also goes to stderr).
    /// Invoked on the main thread, deduped so it fires only when the error changes.
    public var onUserShaderError: (@MainActor (ShaderCompileError?) -> Void)?
    private var lastForwardedShaderError: String?

    private var didSetup = false
    private var didReload = false        // call onReload() after the post-reload setup()
    private var pendingSetupRerun = false // re-run setup() in place (e.g. an asset changed)
    private var clockCarry: Double?      // seconds to continue `time` from across a reload
    private var startTime: CFTimeInterval = 0
    private var lastTime: CFTimeInterval = 0
    private var smoothedFrameRate: Double = 0
    private var smoothedCPUMS: Double = 0

    /// A camera-view snap requested from the host menu (`OllinCameraCommands`),
    /// applied at the top of the next frame so it rides the rig exactly like a
    /// `cameraView(_:)` call from `draw()`.
    private var pendingCameraView: CameraView?

    /// The orientation holder the axis widget reads, fed each frame by `publishOrientation`.
    private var cameraOrientation: CameraOrientationState?
    /// The sketch mouse position captured when a puck drag begins, so the widget's
    /// drag drives the camera orbit through the same input the canvas would.
    private var widgetDragBase: (x: Double, y: Double)?
    /// The last `cameraAxis()`/`groundGrid()` values pushed to the Camera-menu prefs,
    /// so the push fires only on a change. Reset on reload so a fresh sketch
    /// re-asserts its default (and the viewer's session override resets with it).
    private var lastAxisFlag: Bool?
    private var lastGridFlag: Bool?

    /// True while a camera snap or axis-widget drag has un-paused a `noLoop()`
    /// sketch so the glide can animate. The pause must be handed back once the
    /// camera settles: the sketch itself can't re-pause (its one-shot `noLoop()`
    /// already ran, and `setLooping` only reacts to changes), so without this a
    /// single ⌘-view press would leave a still sketch redrawing at full refresh
    /// forever. `cameraHoldoverPose` is the previous frame's resolved camera; two
    /// equal consecutive poses (with no pending snap or drag) mean settled.
    private var cameraHoldover = false
    private var cameraHoldoverPose: Camera3D?

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

    /// Snap the running sketch's camera to a canonical inspection view, requested
    /// from a host menu command. Applied at the top of the next frame, so it rides
    /// the camera rig like a `cameraView(_:)` call from `draw()`; a sketch that
    /// doesn't use the rig (or is 2D) simply ignores it.
    func requestCameraView(_ view: CameraView) {
        pendingCameraView = view
        if !sketch.isLooping { cameraHoldover = true }   // hand the pause back once settled
        self.view?.isPaused = false   // a noLoop() sketch must still snap on demand
    }

    /// Restart the running sketch at a chosen variation seed, requested from a
    /// host's seed-navigation card. In place, on the same instance: the sketch
    /// reseeds now, the clock and any accumulated canvas reset, and `setup()`
    /// re-runs at the top of the next frame, while `@Param` knob values stay
    /// put (same instance, so every host's parameter surface keeps working).
    /// A sketch whose `setup()` pins its own seed simply reproduces that one
    /// variation. **Call on the main thread.**
    public func restart(variation: Int) {
        sketch.seed(variation)
        sketch.frameCount = 0
        renderer.resetAccumulation()   // a fresh variation starts on a clean canvas
        didSetup = false               // re-run setup() and restart the clock next frame
        clockCarry = nil
        // Restore the running state rather than just unpausing the view: a
        // still sketch's fresh `noLoop()` must be a *change* to fire the pause
        // again, or the restarted still image would redraw forever.
        sketch.loop()
        view?.isPaused = false
    }

    /// Drive the camera orbit from a drag on the axis widget's puck by feeding the
    /// sketch's mouse state the way the canvas would, so a rig-driven sketch
    /// (`cameraShowcase` / `cameraControl`) orbits exactly as if the scene were
    /// dragged. `translation` is the SwiftUI drag translation in points, scaled to
    /// canvas units so the feel matches dragging the scene. A hand-`camera()` or 2D
    /// sketch ignores it.
    func widgetOrbit(began: Bool, ended: Bool, translation: CGSize) {
        let viewWidth = Double(view?.bounds.width ?? 0)
        let scale = viewWidth > 0 ? Double(sketch.width) / viewWidth : 1
        if began {
            widgetDragBase = (sketch.mouseX, sketch.mouseY)
            sketch.mouseIsPressed = true
        }
        if let base = widgetDragBase {
            sketch.setMouse(x: base.x + Double(translation.width) * scale,
                            y: base.y + Double(translation.height) * scale)
        }
        if ended {
            sketch.mouseIsPressed = false
            widgetDragBase = nil
        }
        if !sketch.isLooping { cameraHoldover = true }   // hand the pause back once settled
        view?.isPaused = false
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
        // Size the fresh instance the way `updateCanvasSize` will keep asserting
        // it: a `.resizable` sketch's canvas follows the live view, so carry the
        // current size across the swap; otherwise honor the *new* sketch's
        // declared `canvasSize`, so an edited resolution takes effect on the
        // swap itself rather than waiting for the next drawable resize (which a
        // fixed-size window never delivers).
        if case .resizable = newSketch.windowMode {
            newSketch.setCanvasSize(width: sketch.width, height: sketch.height)
        } else {
            newSketch.setCanvasSize(width: Double(newSketch.canvasSize.width),
                                    height: Double(newSketch.canvasSize.height))
        }
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
        lastAxisFlag = nil          // re-assert the fresh sketch's axis/grid defaults
        lastGridFlag = nil
        cameraHoldover = false      // any camera-snap holdover belonged to the old sketch
        cameraHoldoverPose = nil
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

    /// Start feeding the camera orientation into `cameraState` for the axis widget. Set
    /// once when the view builds; the runner writes it each frame in `publishOrientation`.
    func observeOrientation(into cameraState: CameraOrientationState) {
        cameraOrientation = cameraState
    }

    /// Publish the current camera orientation (and the gate flags) to the axis
    /// widget's holder, after `draw()` set the frame's camera. Published on the main
    /// queue, never inline: mutating an observed value inside the render callback
    /// drives a re-entrant SwiftUI layout pass. Driving the widget from this data
    /// (rather than a `TimelineView`) is what keeps it from freezing when the window
    /// loses focus: SwiftUI pauses a free-running timeline there, but honors a data
    /// update, so the tripod keeps tracking the orbit in the background. Only runs
    /// the per-frame work while the widget is on screen, so a 2D sketch (or a 3D one
    /// not showing the axis) pays nothing.
    private func publishOrientation() {
        guard let cameraState = cameraOrientation else { return }
        let cam = sketch.activeCamera
        let is3D = cam != nil
        let axisVisible = sketch.showsCameraAxis
        let gridVisible = sketch.showsGroundGrid
        let showingAxis = is3D && UserDefaults.standard.bool(forKey: OllinHUD.showAxisKey)

        var rotation: simd_float3x3?
        if showingAxis, let cam {
            let v = cam.viewMatrix
            rotation = simd_float3x3(SIMD3(v.columns.0.x, v.columns.0.y, v.columns.0.z),
                                     SIMD3(v.columns.1.x, v.columns.1.y, v.columns.1.z),
                                     SIMD3(v.columns.2.x, v.columns.2.y, v.columns.2.z))
        }

        let gatesChanged = cameraState.is3D != is3D
            || cameraState.axisVisible != axisVisible
            || cameraState.gridVisible != gridVisible
        guard showingAxis || gatesChanged else { return }
        DispatchQueue.main.async {
            if let rotation { cameraState.orientation = rotation }
            cameraState.is3D = is3D
            cameraState.axisVisible = axisVisible
            cameraState.gridVisible = gridVisible
        }
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

    /// Drop the cached compiled user shaders so a `.metal` resource shader is re-read
    /// and recompiled on the next frame: the live-reload hook for a user's own shader
    /// file. The `Shader` value is unchanged (it holds the file path, not the source),
    /// so a property-initialized shader picks up the edit too. **Call on the main
    /// thread.** Forces one frame if the sketch paused itself with `noLoop()`, so a
    /// still sketch still updates.
    public func invalidateUserShaders() {
        renderer.invalidateUserShaderCaches()
        if view?.isPaused == true { view?.draw() }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateCanvasSize(from: view, drawableSize: size)
    }

    public func draw(in view: MTKView) {
        // The drawing runner is the one a host menu command should reach.
        OllinActiveSketch.runner = self

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

        // A camera-view snap from the host menu: request it before the sketch's
        // draw() runs, so its cameraShowcase/cameraControl/cameraMove call applies
        // it this frame.
        if let view = pendingCameraView {
            pendingCameraView = nil
            sketch.cameraView(view)
        }

        // Projection (orthographic vs perspective) is a Camera-menu toggle; apply it
        // to the rig before draw() so a rig-driven camera flattens accordingly.
        sketch.cameraRig.isOrthographic = UserDefaults.standard.bool(forKey: OllinHUD.orthographicKey)

        // Time only the CPU tessellation (`performDraw`), not the render: the
        // renderer blocks on the triple-buffer semaphore (the vsync wait), which
        // would pin this to 1/fps and tell us nothing. CPU tessellation is the
        // documented first bottleneck, so it's the headroom number worth showing.
        let drawStart = CACurrentMediaTime()
        sketch.performDraw()
        let cpuMS = (CACurrentMediaTime() - drawStart) * 1000
        smoothedCPUMS = smoothedCPUMS == 0 ? cpuMS : smoothedCPUMS + (cpuMS - smoothedCPUMS) * 0.1

        // Bridge the sketch's cameraAxis()/groundGrid() flags to the Camera-menu
        // prefs, but only on a change, so the sketch sets the default and the menu
        // becomes the authority that can override it (a per-frame `cameraAxis()`
        // call no longer fights a viewer's toggle). The prefs reset on reload.
        if lastAxisFlag != sketch.showsCameraAxis {
            lastAxisFlag = sketch.showsCameraAxis
            UserDefaults.standard.set(sketch.showsCameraAxis, forKey: OllinHUD.showAxisKey)
        }
        if lastGridFlag != sketch.showsGroundGrid {
            lastGridFlag = sketch.showsGroundGrid
            UserDefaults.standard.set(sketch.showsGroundGrid, forKey: OllinHUD.showGridKey)
        }

        // Ground grid: a shader-drawn y=0 reference floor, injected after the sketch's
        // draw so it depth-composites with the scene (objects occlude it). Live-only:
        // the headless `image(of:)` drives the sketch on its own loop, so this never
        // reaches an export. The grid pattern, anti-aliasing, colored axes, and distance
        // fade are all computed in `ollin_grid_fragment` from the plane's world XZ, so
        // lines stay crisp and a constant ~1px at any zoom or grazing angle. The plane
        // follows the camera's look-at and is sized to cover the fade, so it reads as
        // infinite; the cell size snaps to a nice step for the current viewing distance.
        // Never inject onto an accumulation surface: `noClear()` composites every
        // frame's geometry into the persistent pile, so the chrome would burn
        // permanent grid lines into the artwork.
        if let cam = sketch.activeCamera, !sketch.drawer.accumulates,
           UserDefaults.standard.bool(forKey: OllinHUD.showGridKey) {
            let eye = cam.eye.simd3
            let eyeDist = max(Double(simd_distance(eye, cam.target.simd3)), 0.001)
            let fadeStart = eyeDist * 2.0, fadeEnd = eyeDist * 11.0
            let params = OllinGridParams(
                cameraPos: SIMD4<Float>(eye, 0),
                lineColor:  SIMD4<Float>(0.52, 0.52, 0.56, 0.20),   // faint minor lines
                majorColor: SIMD4<Float>(0.72, 0.72, 0.76, 0.52),   // brighter every-10th
                xAxisColor: SIMD4<Float>(0.80, 0.30, 0.32, 0.85),   // red X axis
                zAxisColor: SIMD4<Float>(0.30, 0.50, 0.85, 0.85),   // blue Z axis
                cellSize: 1.0,                                       // base division = 1 world unit; shader picks the LOD
                lineWidthPixels: 1.0,
                fadeStart: Float(fadeStart), fadeEnd: Float(fadeEnd))
            // The grid composites straight over the frame; reset blend in case the sketch
            // left a non-normal mode at the end of its draw.
            sketch.withState {
                sketch.blendMode(.normal)
                sketch.drawer.drawGroundGrid(params, center: cam.target, halfExtent: fadeEnd * 1.15)
            }
        }

        renderer.render(sketch.drawer,
                        viewport: SIMD2<Float>(Float(sketch.width), Float(sketch.height)),
                        in: view)

        // The grid is host chrome for the live window only. It was appended after the
        // sketch's own draw, so pop it back off before anything re-consumes the drawer:
        // the frame-grab and Syphon paths below re-render the same drawer, and a
        // recorder or a shared feed must never capture the debug grid.
        sketch.drawer.removeGridChrome()

        // Hand the frame's camera orientation to the axis widget (no-op if unused).
        publishOrientation()

        // Surface any user-shader compile error to the host (deduped) for the error
        // overlay. The draw callback runs on the main thread, so the handler does too.
        if let handler = onUserShaderError {
            let current = renderer.currentUserShaderError
            if current?.message != lastForwardedShaderError {
                lastForwardedShaderError = current?.message
                MainActor.assumeIsolated { handler(current) }
            }
        }

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

        // Hand the pause back to a `noLoop()` sketch once the camera work that
        // un-paused it has settled (see `cameraHoldover`). A 2D or hand-`camera()`
        // sketch has no rig-resolved camera, so it settles right away; a glide or
        // release momentum keeps the pose changing frame to frame and holds the
        // view running until it comes to rest.
        if cameraHoldover {
            if sketch.isLooping {
                cameraHoldover = false          // the sketch runs continuously anyway
                cameraHoldoverPose = nil
            } else if pendingCameraView == nil, widgetDragBase == nil {
                let pose = sketch.activeCamera
                let settled = pose == nil || (cameraHoldoverPose.map { poseSettled($0, pose!) } ?? false)
                cameraHoldoverPose = pose
                if settled {
                    cameraHoldover = false
                    cameraHoldoverPose = nil
                    view.isPaused = true
                }
            } else {
                cameraHoldoverPose = sketch.activeCamera
            }
        }
    }

    /// Whether two consecutive frames' camera poses are close enough to call the
    /// motion finished. The rig's easing converges asymptotically, so exact
    /// equality would keep a flicked `noLoop()` camera running long after the
    /// motion stopped being visible; the tolerance is relative to the viewing
    /// distance, far below a pixel.
    private func poseSettled(_ a: Camera3D, _ b: Camera3D) -> Bool {
        let tolerance = max((a.eye - a.target).length, 1e-3) * 1e-6
        return (a.eye - b.eye).length <= tolerance
            && (a.target - b.target).length <= tolerance
            && a.projection == b.projection
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

    /// Whether the view claims keyboard focus the moment it lands in a window
    /// (`KeyboardFocus.automatic`). The gallery turns this off so its example
    /// list keeps arrow-key navigation until the viewer clicks the canvas.
    var claimsKeyboardOnAttach = true
    /// Reports first-responder changes up to the SwiftUI layer, which shows the
    /// click-to-focus keyboard hint while the canvas doesn't hold the keys.
    var onKeyboardFocusChange: ((Bool) -> Void)?

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
    override func mouseDragged(with event: NSEvent) {
        reportPointer(event)
        // While a pressure-event stream is live, drag events must stay quiet: a
        // pressure-sensing trackpad's drag events carry the legacy constant 1 in
        // `pressure`, and reporting it would flap the sketch's value between the
        // true press and 1.0 on alternating events. Devices that never send
        // pressure events (tablet points, plain mice) keep this path.
        if !pressureStreamLive { reportPressure(event) }
    }
    override func mouseDown(with event: NSEvent) {
        // A click reclaims keyboard focus (e.g. after a click on an inspector
        // control moved first responder away), so the canvas keeps the keys.
        window?.makeFirstResponder(self)
        // The hosting layer's gesture recognizers install their own deep-click
        // pressure configuration, which takes precedence over the view property
        // for the press that is starting: re-claim the drawing gesture for this
        // stream (one stage, smooth 0…1, no force-click firing mid-stroke).
        pressureStreamLive = false
        pressureConfiguration?.set()
        reportPointer(event)
        reportPressure(event)
        sketch?.mouseIsPressed = true
        sketch?.mousePressed()
    }
    override func mouseUp(with event: NSEvent) {
        reportPointer(event)
        sketch?.setPressure(0, canVary: false)
        sketch?.mouseIsPressed = false
        sketch?.mouseReleased()
    }

    /// A pressure-sensing device keeps sending pressure while the press deepens
    /// without the pointer moving, so a still hand still swells the mark. Inside
    /// the SwiftUI hosts this never fires (see the monitor in
    /// `viewDidMoveToWindow`); it stays for plain AppKit embeddings.
    override func pressureChange(with event: NSEvent) {
        pressureStreamLive = true
        reportPressure(event)
    }

    /// Hand the sketch the press force, and whether this device can vary it at all.
    /// `associatedEventsMask` reports which other events this input could also send,
    /// so a pressure bit in it is what separates a trackpad reporting a real 0.4
    /// from a plain mouse reporting a flat 1.
    ///
    /// Only valid on mouse down/up/drag, tablet-point, and pressure events: reading
    /// `pressure` on anything else (a plain `mouseMoved`) raises.
    private func reportPressure(_ event: NSEvent) {
        // A pressure event is its own capability proof: only a device that can
        // vary sends them. It must also be the only path that trusts the value,
        // and `associatedEventsMask` must never be read here: on a pressure
        // event that access raises, and AppKit's dispatch swallows the raise,
        // silently abandoning the report (verified by hand).
        if event.type == .pressure {
            sketch?.setPressure(Double(event.pressure), canVary: true)
            return
        }
        // A mouse event from a pressure-sensing device (the mask's pressure
        // bit) carries the legacy constant 1 in `pressure`; the truth arrives
        // on the pressure-event stream, whose curve starts near zero. Seed
        // zero until that stream speaks, so a stroke never opens on a
        // one-frame full-force blip. A plain mouse keeps its honest flat 1.
        let canVary = event.associatedEventsMask.contains(.pressure)
        sketch?.setPressure(canVary ? 0 : Double(event.pressure), canVary: canVary)
    }

    // The secondary (right) button drives the camera-control pan (alongside a
    // modifier-drag). Report the pointer on a right-drag too, since AppKit sends
    // `rightMouseDragged` (not `mouseDragged`) while it's held.
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        reportPointer(event)
        sketch?.setRightMousePressed(true)
    }
    override func rightMouseDragged(with event: NSEvent) { reportPointer(event) }
    override func rightMouseUp(with event: NSEvent) {
        reportPointer(event)
        sketch?.setRightMousePressed(false)
    }

    override func scrollWheel(with event: NSEvent) {
        sketch?.handleScroll(deltaY: Double(event.scrollingDeltaY))
    }

    /// Modifier keys (shift / option / command / control) changed: map AppKit's
    /// flags onto Ollin's platform-neutral set.
    override func flagsChanged(with event: NSEvent) {
        sketch?.setModifiers(ModifierKeys(event.modifierFlags))
    }

    // MARK: Keyboard

    /// Required for the view to receive `keyDown`/`keyUp`.
    override var acceptsFirstResponder: Bool { true }

    /// Whether the current drag has a live pressure-event stream. Set by the
    /// first pressure event after a mouse down; while true, drag events stop
    /// reporting pressure (see `mouseDragged`).
    private var pressureStreamLive = false

    /// Pressure events reach the app but the SwiftUI hosting layer's gesture
    /// plumbing consumes them before responder dispatch, so `pressureChange`
    /// never fires inside the hosts (verified by hand: every event visible at
    /// the app level, none delivered to the view). A local monitor feeds them
    /// to the sketch instead; the `pressureChange` override stays for plain
    /// AppKit embeddings, where delivery works and the monitor double-reports
    /// the same value harmlessly.
    private var pressureMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if pressureMonitor == nil {
            pressureMonitor = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] event in
                guard let self, event.window === self.window,
                      self.sketch?.mouseIsPressed == true else { return event }
                self.pressureStreamLive = true
                self.reportPressure(event)
                return event
            }
        }
        // Take keyboard focus once we're in a window, so a sketch reacts to keys
        // without the user clicking the canvas first. A host whose window has its
        // own keyboard surface (the gallery's example list) opts out; there a
        // click claims the keys instead (see `mouseDown`).
        if claimsKeyboardOnAttach {
            window?.makeFirstResponder(self)
        }
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
        // The pressure monitor's teardown lives here (not deinit, which is
        // nonisolated and can't touch main-actor state); leaving the window
        // uninstalls it, and `viewDidMoveToWindow` reinstalls on re-attach.
        if newWindow == nil, let pressureMonitor {
            NSEvent.removeMonitor(pressureMonitor)
            self.pressureMonitor = nil
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

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onKeyboardFocusChange?(true) }
        return became
    }

    /// Drop held keys and modifiers when focus leaves; without a matching `keyUp` /
    /// `flagsChanged` a key or modifier held across a focus change would otherwise
    /// stay stuck down.
    override func resignFirstResponder() -> Bool {
        sketch?.clearHeldKeys()
        sketch?.setModifiers([])
        sketch?.setRightMousePressed(false)
        onKeyboardFocusChange?(false)
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

/// Maps AppKit's modifier flags onto Ollin's platform-neutral `ModifierKeys`.
/// Lives on the AppKit side of the seam so `ModifierKeys` stays free of AppKit for
/// the eventual UIKit path.
private extension ModifierKeys {
    init(_ flags: NSEvent.ModifierFlags) {
        var mods: ModifierKeys = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.control) { mods.insert(.control) }
        self = mods
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

/// When a hosted sketch takes keyboard focus.
public enum KeyboardFocus: Sendable {
    /// The canvas claims the keyboard as soon as it appears, so a sketch reacts
    /// to keys without a click first. The default, right for a window that *is*
    /// the sketch (standalone runs, the live host).
    case automatic
    /// The canvas never takes the keyboard on its own; clicking the sketch
    /// claims it. For hosts whose window has another keyboard surface (the
    /// gallery's example list keeps its arrow-key navigation this way).
    case onClick
}

/// Whether the canvas currently holds keyboard focus: the first-responder
/// signal the click-to-focus hint reads.
@Observable @MainActor
private final class CanvasKeyFocus {
    var isFocused = false
}

@MainActor
private func makeOllinMTKView(device: MTLDevice, size: CGSize, sketch: Sketch) -> OllinMTKView {
    let view = OllinMTKView(frame: CGRect(origin: .zero, size: size), device: device)
    view.sketch = sketch
    view.colorPixelFormat = ollinColorPixelFormat
    // The drawable is the present target: single-sample. MSAA is done in the
    // renderer's float intermediate, then resolved before the present pass.
    view.sampleCount = 1
    view.isPaused = false                    // run continuously...
    view.enableSetNeedsDisplay = false       // ...driven by the display timer
    // Ask a Force Touch trackpad for the drawing gesture rather than the default
    // one: a single stage over the full 0...1 range, so a press reads as a smooth
    // amount instead of arming the force-click that fires look-up mid-stroke.
    view.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
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
    private let keyboardFocus: KeyboardFocus
    private let showsKeyboardHint: Bool
    private let onRunner: (@MainActor (SketchRunner) -> Void)?

    /// Whether the canvas holds the keys right now, driving the hint.
    @State private var keyFocus = CanvasKeyFocus()

    /// Owned stats for standalone/gallery hosts that don't inject their own.
    @State private var ownedStats = FrameStats()
    /// The floating "Show FPS" inspector panel, summoned by the menu toggle.
    @State private var statsPanel = StatsPanelController()
    /// The shared toggle the "Show FPS" command flips.
    @AppStorage(OllinHUD.showStatsKey) private var showStats = false

    /// The live camera orientation feeding the axis widget. Its observed gate flags
    /// (`is3D` / `axisVisible`) decide whether the widget mounts, so a 2D sketch
    /// never creates it.
    @State private var cameraState = CameraOrientationState()
    /// The shared toggle the "Show Axis" command flips, OR-ed with the sketch's own
    /// `cameraAxis(_:)` flag.
    @AppStorage(OllinHUD.showAxisKey) private var showAxis = false

    /// - Parameters:
    ///   - showsInspectorPanel: whether this view honors the "Show Inspector"
    ///     toggle by summoning the detached inspector panel. A host with its own
    ///     inspector surface (the live host's sidebar, the gallery's) passes
    ///     `false` so the panel doesn't duplicate it; standalone runs leave it on.
    ///   - keyboardFocus: when the canvas takes the keyboard. `.automatic`
    ///     claims it on appear (the default); `.onClick` only when clicked, so
    ///     the host window's own keyboard surface keeps working.
    ///   - showsKeyboardHint: under `.onClick`, whether to float the
    ///     "Click the sketch to use the keyboard" prompt while the canvas is
    ///     unfocused. Pass `true` only for sketches that actually read keys.
    public init(_ sketch: Sketch,
                stats: FrameStats? = nil,
                showsInspectorPanel: Bool = true,
                keyboardFocus: KeyboardFocus = .automatic,
                showsKeyboardHint: Bool = false,
                onRunner: (@MainActor (SketchRunner) -> Void)? = nil) {
        self.sketch = sketch
        self.injectedStats = stats
        self.showsInspectorPanel = showsInspectorPanel
        self.keyboardFocus = keyboardFocus
        self.showsKeyboardHint = showsKeyboardHint
        self.onRunner = onRunner
    }

    private var stats: FrameStats { injectedStats ?? ownedStats }

    public var body: some View {
        ZStack(alignment: .bottom) {
            MetalCanvas(sketch: sketch, stats: stats, cameraState: cameraState,
                        keyboardFocus: keyboardFocus, keyFocus: keyFocus, onRunner: onRunner)
            // Mounted only for a 3D frame the sketch or the menu asked to annotate,
            // so a 2D sketch never builds the widget or its animation timeline. The
            // widget is its own size, so it intercepts clicks only over itself.
            if cameraState.is3D && showAxis {
                AxisWidget(cameraState: cameraState)
                    .padding(.bottom, 26)
                    .transition(.opacity)
            }
            // The click-to-focus prompt: only for keyboard-reading sketches in an
            // `.onClick` host, only while the canvas doesn't hold the keys. It
            // never intercepts the click; the canvas claims focus on mouse-down.
            if showsKeyboardHint && keyboardFocus == .onClick && !keyFocus.isFocused {
                KeyboardFocusHint()
                    // Clear the axis widget when both are on screen.
                    .padding(.bottom, cameraState.is3D && showAxis ? 118 : 18)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: cameraState.is3D)
        .animation(.easeOut(duration: 0.2), value: keyFocus.isFocused)
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
    let cameraState: CameraOrientationState
    let keyboardFocus: KeyboardFocus
    let keyFocus: CanvasKeyFocus
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
        view.claimsKeyboardOnAttach = (keyboardFocus == .automatic)
        view.onKeyboardFocusChange = { [weak keyFocus] focused in
            keyFocus?.isFocused = focused
        }
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.observeStats(into: stats)
        runner.observeOrientation(into: cameraState)
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

/// The click-to-focus prompt: a small glass capsule floated over the bottom of
/// the canvas telling the viewer the sketch wants their keyboard. Transient
/// chrome in the reload-toast idiom; it clears the moment the canvas takes
/// focus, and it never intercepts the click itself.
private struct KeyboardFocusHint: View {
    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            SwiftUI.Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Click the sketch to use the keyboard")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        // The reload toast's lift, gentler in light mode where the dark-tuned
        // radius reads as a smudge.
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 16, y: 7)
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

    /// True while a headless driver (the frame grab, the sequence/video/GIF/SVG
    /// exporters, the benchmark loop) is driving the sketch clock: fixed
    /// timestep, no window, no runloop servicing between frames. Sources that
    /// normally follow a real clock (a playing video) read this to switch to a
    /// deterministic pull that follows the sketch clock instead.
    package static var isRenderingHeadless = false

    /// True for the *whole* of a vector-export drive (`recordVectorFrame`),
    /// setup and warmup frames included, not just the recorded frame. Vector
    /// export replaces GPU emission per draw call, so a `Batch` recorded any
    /// time during the run must capture vector commands rather than geometry;
    /// `Drawer.makeBatch` reads this to pick the representation. The drive is
    /// synchronous on one thread (set, drive, clear), and the nonisolated
    /// `Drawer` reads it mid-drive, hence `nonisolated(unsafe)`.
    package nonisolated(unsafe) static var isVectorExporting = false

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
    ///
    /// `quality` is the **automatic** render-quality fallback for features the sketch left at
    /// `.default`: it defaults to `.detail` (best quality; export has no frame-rate pressure),
    /// the `--render-quality` flag overrides it, and a feature the sketch dialled explicitly is
    /// always honoured regardless.
    public static func image(of sketch: Sketch, frame: Int = 0, fps: Double = 60,
                             quality: RenderQuality = .detail) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                                sampleCount: ollinPreferredSampleCount(device)) else {
            return nil
        }
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        renderer.automaticQuality = quality
        return renderImage(of: sketch, frame: frame, fps: fps, renderer: renderer)
    }

    /// The one-frame headless drive behind `image(of:)`, against a caller-owned
    /// renderer: the contact sheet reuses one renderer (and its compiled
    /// pipelines) across every tile instead of rebuilding per seed. The caller
    /// owns `isRenderingHeadless` and the renderer's quality fallback.
    static func renderImage(of sketch: Sketch, frame: Int, fps: Double,
                            renderer: MetalRenderer) -> CGImage? {
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        let width = size.width, height = size.height
        // In accumulation mode (`noClear`) each frame piles onto the persistent
        // surface, so render every frame into it — the captured frame N is the
        // built-up canvas, not a fresh draw of frame N alone.
        var accumulated: CGImage?
        var fedBack: CGImage?
        let target = max(0, frame)
        for k in 0...target {                        // advance so frame N is correct
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            if sketch.drawer.accumulates {
                accumulated = renderer.accumulatedImage(of: sketch.drawer, viewport: viewport,
                                                        width: width, height: height)
            } else if sketch.drawer.usesFeedback {
                // Feedback state lives in render-pass-filled ping-pong textures, so
                // (like accumulation) every intermediate frame must render (which also
                // steps compute) for the layer to evolve; only the last frame is kept.
                fedBack = renderer.image(of: sketch.drawer, viewport: viewport,
                                         width: width, height: height)
            } else if k < target {
                // A stateful compute sim must run on the GPU every frame to evolve;
                // the intermediate frames we don't capture still need their steps
                // executed (only the final frame is rendered + read back below).
                renderer.stepCompute(sketch.drawer)
            }
        }
        if sketch.drawer.accumulates { return accumulated }
        if sketch.drawer.usesFeedback { return fedBack }
        return renderer.image(of: sketch.drawer, viewport: viewport, width: width, height: height)
    }

    /// Render one frame of `sketch` off-screen and write it as a PNG — no window.
    /// Drives the sketch headlessly: `setup()`, then `draw()` advanced to `frame`
    /// at `fps` (so animated/stateful sketches export the right moment). The
    /// headless frame-grab (`image(of:)`) plus a PNG write, and the basis for PNG
    /// sequences → video.
    public static func export(_ sketch: Sketch, to path: String, frame: Int = 0, fps: Double = 60,
                              quality: RenderQuality = .detail) {
        guard let cgImage = image(of: sketch, frame: frame, fps: fps, quality: quality) else {
            fatalError("Ollin: failed to render the frame for export (no Metal device?)")
        }
        let recipe = ExportMetadata.capture(from: sketch, frame: frame, fps: fps).recipe
        guard writePNG(cgImage, to: path, recipe: recipe) else {
            fatalError("Ollin: failed to write \(path)")
        }
        print("Ollin: exported frame \(frame) → \(path) (\(cgImage.width)×\(cgImage.height))")
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
                                      startFrame: Int = 1, skipSeconds: Double = 0,
                                      quality: RenderQuality = .detail) {
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

        let elapsed = renderFrames(sketch, frames: frames, fps: fps, skipSeconds: skipSeconds,
                                   quality: quality) { cgImage, index in
            // Captured per frame (cheap: the git lookup is cached) so each
            // file's recipe names the sketch-clock frame it shows.
            let recipe = ExportMetadata.capture(from: sketch, frame: skipFrames + index, fps: fps).recipe
            let name = String(format: "frame-%05d.png", startFrame + index)
            let path = (directory as NSString).appendingPathComponent(name)
            guard writePNG(cgImage, to: path, recipe: recipe) else {
                fatalError("Ollin: failed to write \(path)")
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
                             skipSeconds: Double, quality: RenderQuality = .detail,
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
        renderer.automaticQuality = quality   // the fallback for features the sketch left at .default
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }

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
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        let n = max(1, frames)
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()
        // One warm-up frame so first-time buffer growth doesn't skew the average.
        sketch.advance(time: 0, deltaTime: 1 / fps, frameRate: fps)
        sketch.performDraw()

        // Optional GPU timing. Three numbers, because they answer different questions:
        //   • CPU draw   : the per-frame `performDraw()` tessellation cost alone.
        //   • GPU        : the *pure* per-frame GPU cost from command-buffer timestamps
        //                  (vsync- and readback-independent, the real live render cost),
        //                  the same measurement the `.defocus`/shadow benchmarks report.
        //   • end-to-end : CPU + GPU + a full read-back, run fully serially; conservative
        //                  (the live path triple-buffers, so live ≈ max(CPU, GPU)).
        // The live frame rate is bounded by max(CPU, GPU), printed as the estimate.
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
            // Warm up: render several real frames so first-time buffer growth is paid and
            // any stateful layer (feedback, a sim field) settles into its steady-state cost.
            for k in 0..<8 {
                sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
                sketch.performDraw()
                _ = renderer.image(of: sketch.drawer, viewport: viewport, width: w, height: h)
            }

            // CPU draw cost and the end-to-end (serial CPU + GPU + readback) cost, one loop.
            let start = CACurrentMediaTime()
            var cpuTotal = 0.0
            for k in 1...n {
                sketch.advance(time: Double(n + k) / fps, deltaTime: 1 / fps, frameRate: fps)
                let drawStart = CACurrentMediaTime()
                sketch.performDraw()
                cpuTotal += CACurrentMediaTime() - drawStart
                _ = renderer.image(of: sketch.drawer, viewport: viewport, width: w, height: h)
            }
            let endToEnd = (CACurrentMediaTime() - start) / Double(n) * 1000
            let cpuMs = cpuTotal / Double(n) * 1000
            // Pure per-frame GPU cost on the last drawn frame (vsync- and readback-free).
            let gpuMs = renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                          width: w, height: h, iterations: max(8, n / 4))
            let liveMs = max(cpuMs, gpuMs)
            print(String(format: "Ollin bench: %d frames @ %d×%d · CPU %.2f ms · GPU %.2f ms · end-to-end %.2f ms",
                         n, w, h, cpuMs, gpuMs, endToEnd))
            print(String(format: "  → live ~%.0f fps (bound by %@) · end-to-end ~%.0f fps",
                         liveMs > 0 ? 1000 / liveMs : 0, cpuMs >= gpuMs ? "CPU" : "GPU",
                         endToEnd > 0 ? 1000 / endToEnd : 0))
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
        if OllinApp.handleCommandLine(makeSketch: { Self() }) { return }
        OllinApp.run(Self())
    }
}

public extension OllinApp {
    /// Handle the shared headless command-line surface (the export flags
    /// `--export`, `--export-sequence`, `--export-video`, `--export-gif`,
    /// `--export-loop`, `--export-svg`, `--export-pdf`, `--export-usdz`,
    /// `--export-grid`, `--export-sweep`, `--export-separations` with their
    /// options, `--seed` on any of them,
    /// plus `--bench`) against a sketch supplied on demand.
    ///
    /// Returns `true` when a headless flag was recognized (the work ran, or a
    /// usage message was printed), meaning the caller should exit rather than
    /// open a window; `false` when the arguments ask for no headless work.
    /// `makeSketch` is called only when a flag matches, so a host may pass an
    /// expensive factory at no cost to the windowed path: OllinLive hands in a
    /// closure that compiles a loose sketch file, which is how any watched
    /// sketch gains the same export surface as a standalone `@main` sketch.
    /// `Sketch.main()` routes every `@main` sketch through here.
    @MainActor
    @discardableResult
    static func handleCommandLine(_ args: [String] = CommandLine.arguments,
                                  makeSketch: () -> Sketch) -> Bool {
        // `--render-quality <performance|default|detail>` sets the render-quality fallback for
        // the export paths, applied to any feature the sketch left at `.default` (an explicit
        // sketch dial still wins). Defaults to `.detail`: exported art is full quality unless
        // asked otherwise. (Distinct from `--quality`, the video *encoding* quality.)
        let renderQuality: RenderQuality = {
            guard let i = args.firstIndex(of: "--render-quality"), i + 1 < args.count,
                  let q = RenderQuality(name: args[i + 1]) else { return .detail }
            return q
        }()
        // `--seed N` reseeds the sketch before its `setup()` on every export
        // path, so a variation found in the inspector or on a contact sheet
        // re-renders exactly (a sketch that pins its own seed in `setup()`
        // still wins, as anywhere). For `--export-grid` it is the first seed
        // of the sheet.
        let seedOverride: Int? = {
            guard let i = args.firstIndex(of: "--seed"), i + 1 < args.count else { return nil }
            return Int(args[i + 1])
        }()
        func make() -> Sketch {
            let sketch = makeSketch()
            if let seedOverride { sketch.seed(seedOverride) }
            return sketch
        }
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
                return true
            }
            OllinApp.exportSequence(make(), to: dir, frames: frames, fps: fps,
                                    startFrame: start, skipSeconds: skip, quality: renderQuality)
            return true
        }
        // `--export-loop <path> [--fps F] [--skip S] [--gif-width PX] [--codec C]
        // [--bitrate MBPS] [--quality 0..1]` renders exactly one period of a
        // sketch that declares `loopDuration`, as a seamlessly looping GIF or
        // video (picked by the file extension), and exits.
        if let i = args.firstIndex(of: "--export-loop"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let path = args[i + 1]
            let isGIF = path.lowercased().hasSuffix(".gif")
            let fps = value("--fps").flatMap(Double.init) ?? (isGIF ? 25 : 60)
            let skip = value("--skip").flatMap(Double.init) ?? 0
            let sketch = make()
            guard let duration = sketch.loopDuration, duration > 0 else {
                FileHandle.standardError.write(Data("""
                    --export-loop renders one period of a sketch that declares its loop:
                        override var loopDuration: Double? { 6 }   // seconds per lap
                    usage: --export-loop <path.gif|.mp4|.mov> [--fps F] [--skip S] [--gif-width PX] [--codec C] [--bitrate MBPS] [--quality 0..1]

                    """.utf8))
                return true
            }
            // GIF stores whole-centisecond frame delays, so exportGIF quantizes
            // the rate; compute the lap against the rate that will actually
            // play, or the frame count drifts off one period.
            let loopFPS = isGIF ? 100 / Double(max(2, Int((100 / fps).rounded()))) : fps
            let exact = duration * loopFPS
            let frames = max(1, Int(exact.rounded()))
            if abs(exact - exact.rounded()) > 1e-6 {
                FileHandle.standardError.write(Data(
                    "note: a \(duration)s loop at \(loopFPS) fps is not a whole number of frames; the loop won't close exactly (pick an fps that divides the loop).\n".utf8))
            }
            if isGIF {
                let width = value("--gif-width").flatMap(Int.init)
                OllinApp.exportGIF(sketch, to: path, frames: frames, fps: loopFPS,
                                   width: width, skipSeconds: skip, renderQuality: renderQuality)
            } else {
                var codec = VideoCodec.h264
                if let name = value("--codec") {
                    guard let parsed = VideoCodec(rawValue: name) else {
                        FileHandle.standardError.write(Data(
                            "unknown codec '\(name)': expected one of \(VideoCodec.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                        return true
                    }
                    codec = parsed
                }
                let bitrate = value("--bitrate").flatMap(Double.init).map { Int($0 * 1_000_000) }
                let quality = value("--quality").flatMap(Double.init)
                OllinApp.exportVideo(sketch, to: path, frames: frames, fps: fps,
                                     codec: codec, bitsPerSecond: bitrate, quality: quality,
                                     renderQuality: renderQuality, skipSeconds: skip)
            }
            return true
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
                        "unknown codec '\(name)': expected one of \(VideoCodec.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                    return true
                }
                codec = parsed
            }
            let bitrate = value("--bitrate").flatMap(Double.init).map { Int($0 * 1_000_000) }
            let quality = value("--quality").flatMap(Double.init)
            guard frames > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-video <path> (--frames N | --seconds S) [--fps F] [--skip S] [--codec C] [--bitrate MBPS] [--quality 0..1]\n".utf8))
                return true
            }
            OllinApp.exportVideo(make(), to: args[i + 1], frames: frames, fps: fps,
                                 codec: codec, bitsPerSecond: bitrate, quality: quality,
                                 renderQuality: renderQuality, skipSeconds: skip)
            return true
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
                return true
            }
            OllinApp.exportGIF(make(), to: args[i + 1], frames: frames, fps: fps,
                               width: width, skipSeconds: skip, renderQuality: renderQuality)
            return true
        }
        // `--export-grid <path.png> [--seeds N] [--columns C] [--tile PX]
        // [--frame N] [--fps F]` renders a contact sheet of variations, one
        // labeled tile per seed, and exits. Seeds run consecutively from
        // `--seed` (default 1); re-render a keeper at full resolution with
        // `--export <path> --seed N`.
        if let i = args.firstIndex(of: "--export-grid"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let count = value("--seeds").flatMap(Int.init) ?? 16
            guard count > 0 else {
                FileHandle.standardError.write(Data(
                    "usage: --export-grid <path.png> [--seeds N] [--columns C] [--tile PX] [--frame N] [--fps F] [--seed FIRST]\n".utf8))
                return true
            }
            let start = seedOverride ?? 1
            let seeds = Array(start ..< start + count)
            let columns = value("--columns").flatMap(Int.init)
            let tile = value("--tile").flatMap(Int.init) ?? 320
            let frame = value("--frame").flatMap(Int.init) ?? 0
            let fps = value("--fps").flatMap(Double.init) ?? 60
            OllinApp.exportContactSheet(makeSketch, to: args[i + 1], seeds: seeds,
                                        frame: frame, fps: fps, columns: columns,
                                        tileWidth: tile, quality: renderQuality)
            return true
        }
        // `--export-sweep <path.png> --param <name> (--values "a,b,c" | --from A
        // --to B [--steps N]) [--columns C] [--tile PX] [--frame N] [--fps F]`
        // renders a contact sheet sweeping one `@Param` across a range, one
        // labeled tile per value, every tile pinned to the same seed (`--seed`,
        // or one rolled and recorded in the sheet's recipe), and exits.
        if let i = args.firstIndex(of: "--export-sweep"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let usage = "usage: --export-sweep <path.png> --param <name> (--values \"a,b,c\" | --from A --to B [--steps N]) [--columns C] [--tile PX] [--frame N] [--fps F] [--seed N]\n"
            guard let name = value("--param") else {
                FileHandle.standardError.write(Data(usage.utf8))
                return true
            }
            var values: [Double] = []
            if let list = value("--values") {
                values = list.split(separator: ",").compactMap {
                    Double($0.trimmingCharacters(in: .whitespaces))
                }
            } else if let from = value("--from").flatMap(Double.init),
                      let to = value("--to").flatMap(Double.init) {
                let steps = max(value("--steps").flatMap(Int.init) ?? 9, 1)
                values = steps == 1 ? [from] : (0 ..< steps).map {
                    from + (to - from) * Double($0) / Double(steps - 1)
                }
            }
            guard !values.isEmpty else {
                FileHandle.standardError.write(Data(usage.utf8))
                return true
            }
            let columns = value("--columns").flatMap(Int.init)
            let tile = value("--tile").flatMap(Int.init) ?? 320
            let frame = value("--frame").flatMap(Int.init) ?? 0
            let fps = value("--fps").flatMap(Double.init) ?? 60
            OllinApp.exportContactSheet(makeSketch, to: args[i + 1],
                                        sweeping: name, values: values,
                                        seed: seedOverride,
                                        frame: frame, fps: fps, columns: columns,
                                        tileWidth: tile, quality: renderQuality)
            return true
        }
        // `--export-separations <path.png> [--frame N] [--inks "black, fluorescent pink"]
        // [--paper HEX] [--screen dither|halftone] [--pitch PX] [--no-marks]` splits
        // one frame into per-ink grayscale printing masters plus an overprint
        // preview and exits. Inks come from the sketch's declared `printInks` unless
        // `--inks` names catalog inks; `--screen` reduces the masters to 1-bit.
        if let i = args.firstIndex(of: "--export-separations"), i + 1 < args.count {
            func value(_ flag: String) -> String? {
                guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
                return args[j + 1]
            }
            let frame = value("--frame").flatMap(Int.init) ?? 0
            var inks: [Ink]?
            if let list = value("--inks") {
                var parsed: [Ink] = []
                for entry in list.split(separator: ",") {
                    let name = entry.trimmingCharacters(in: .whitespaces)
                    guard let ink = Ink.named(name) else {
                        FileHandle.standardError.write(Data(
                            "unknown ink '\(name)': names match the built-in catalog (Ink.catalog), e.g. \"black\", \"fluorescent pink\", \"medium blue\"\n".utf8))
                        return true
                    }
                    parsed.append(ink)
                }
                inks = parsed
            }
            var paper = Color.white
            if let hex = value("--paper") {
                guard let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else {
                    FileHandle.standardError.write(Data("--paper expects a hex color, e.g. FFF7E8\n".utf8))
                    return true
                }
                paper = Color(hex: value)
            }
            let pitch = value("--pitch").flatMap(Double.init) ?? 8
            let screen: (PrintSeparation) -> PrintSeparation
            switch value("--screen") ?? "none" {
            case "none": screen = { $0 }
            case "dither": screen = { $0.dithered() }
            case "halftone": screen = { $0.halftoned(pitch: pitch) }
            default:
                FileHandle.standardError.write(Data(
                    "usage: --export-separations <path.png> [--frame N] [--inks \"a, b\"] [--paper HEX] [--screen dither|halftone] [--pitch PX] [--no-marks]\n".utf8))
                return true
            }
            OllinApp.exportSeparations(make(), to: args[i + 1], inks: inks, paper: paper,
                                       frame: frame, registrationMarks: !args.contains("--no-marks"),
                                       quality: renderQuality, screen: screen)
            return true
        }
        if let i = args.firstIndex(of: "--export"), i + 1 < args.count {
            var frame = 0
            if let f = args.firstIndex(of: "--frame"), f + 1 < args.count {
                frame = Int(args[f + 1]) ?? 0
            }
            OllinApp.export(make(), to: args[i + 1], frame: frame, quality: renderQuality)
            return true
        }
        // `swift run Example-X --export-svg <path> [--frame N]` writes a vector SVG
        // of one frame and exits (no window, no GPU); `--export-pdf <path>` writes
        // the same recorded frame as a single-page PDF (both may be passed at
        // once). Add `--hatch` (or `--cross-hatch`) to plot solid fills as pen
        // line work: `--hatch-spacing N` and `--hatch-angle DEG` tune it.
        let svgFlag = args.firstIndex(of: "--export-svg")
        let pdfFlag = args.firstIndex(of: "--export-pdf")
        if svgFlag != nil || pdfFlag != nil {
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
            var handled = false
            if let i = svgFlag, i + 1 < args.count {
                OllinApp.exportSVG(make(), to: args[i + 1], frame: frame, hatching: hatching)
                handled = true
            }
            if let i = pdfFlag, i + 1 < args.count {
                OllinApp.exportPDF(make(), to: args[i + 1], frame: frame, hatching: hatching)
                handled = true
            }
            if !handled {
                FileHandle.standardError.write(Data(
                    "usage: --export-svg <path.svg> | --export-pdf <path.pdf> [--frame N] [--hatch | --cross-hatch] [--hatch-spacing N] [--hatch-angle DEG]\n".utf8))
            }
            return true
        }
        // `swift run Example-X --export-usdz <path> [--frame N] [--meters-per-unit U]`
        // writes one frame's 3D geometry as a spatial model and exits (no window,
        // no GPU). `.usda` in the path writes the readable text layer instead of
        // the package.
        if let i = args.firstIndex(of: "--export-usdz") {
            guard i + 1 < args.count else {
                FileHandle.standardError.write(Data(
                    "usage: --export-usdz <path.usdz | path.usda> [--frame N] [--meters-per-unit U]\n".utf8))
                return true
            }
            var frame = 0
            if let f = args.firstIndex(of: "--frame"), f + 1 < args.count {
                frame = Int(args[f + 1]) ?? 0
            }
            var metersPerUnit = 1.0
            if let m = args.firstIndex(of: "--meters-per-unit"), m + 1 < args.count {
                metersPerUnit = Double(args[m + 1]) ?? 1
            }
            OllinApp.exportSpatial(make(), to: args[i + 1], frame: frame,
                                   metersPerUnit: metersPerUnit)
            return true
        }
        if let i = args.firstIndex(of: "--bench") {
            var frames = 600
            if i + 1 < args.count, let f = Int(args[i + 1]) { frames = f }
            OllinApp.benchmark(make(), frames: frames, gpu: args.contains("--gpu"))
            return true
        }
        return false
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

    var body: some SwiftUI.Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {}
                OllinHUDCommands()
                OllinCameraCommands()
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
