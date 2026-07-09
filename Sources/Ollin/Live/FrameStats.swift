import Observation
import Dispatch

/// Shared keys for the detached stats/inspector panel.
public enum OllinHUD {
    /// `UserDefaults`/`@AppStorage` key the "Show FPS" command and the detached
    /// panel both bind to, so toggling the menu summons the panel in any run mode
    /// and the choice persists across launches.
    public static let showStatsKey = "ollin.hud.showStats"
    /// `@AppStorage` key the "Show Axis" camera-menu command and the axis widget
    /// both bind to, so the menu can summon the orientation widget in any host and
    /// the choice persists. OR-ed with the sketch's own `cameraAxis(_:)` flag.
    public static let showAxisKey = "ollin.hud.showAxis"
    /// `@AppStorage` key for the "Show Ground Grid" command, paired with the
    /// sketch's `groundGrid(_:)` flag the same way.
    public static let showGridKey = "ollin.hud.showGrid"
    /// `@AppStorage` key for the "Orthographic" camera-menu toggle, read each frame
    /// by the runner and applied to the rig (perspective when off).
    public static let orthographicKey = "ollin.hud.orthographic"
    /// Window identifier for the floating stats panel, so the standalone app
    /// delegate can tell it apart from the sketch window (and not quit when only
    /// the panel is closed).
    public static let statsPanelID = "ollin.stats.panel"
}

/// A live snapshot of how the running sketch is performing: frame rate, the CPU
/// cost of a frame, the geometry it emitted, and where the clock is. The runner
/// refreshes it a few times a second (not every frame, so SwiftUI doesn't
/// thrash). One instance feeds both the on-canvas overlay and the live host's
/// inspector, so the two never compute the numbers twice.
@Observable
public final class FrameStats {
    /// Smoothed frames per second.
    public internal(set) var fps: Double = 0
    /// Smoothed CPU time to tessellate and encode a frame, in milliseconds —
    /// the headroom against the frame budget, and the real signal when a sketch
    /// can't keep up (FPS alone saturates at the display rate).
    public internal(set) var frameTimeMS: Double = 0
    /// The sketch clock, mirrored for display.
    public internal(set) var frameCount: Int = 0
    public internal(set) var time: Double = 0
    /// Geometry emitted this frame — the "why is it slow" breakdown: tessellated
    /// vertices, instanced SDF shapes, 3D point-cloud splats, and GPU-particle discs
    /// (the last two are GPU-resident, so they're not in any CPU vertex array).
    public internal(set) var vertexCount: Int = 0
    public internal(set) var sdfCount: Int = 0
    public internal(set) var pointCount: Int = 0
    public internal(set) var particleCount: Int = 0
    /// The logical canvas size, for context.
    public internal(set) var canvasWidth: Double = 0
    public internal(set) var canvasHeight: Double = 0
    /// The sketch's current variation seed, mirrored for the seed-navigation
    /// card (`nil` until the first refresh).
    public internal(set) var variation: Int?

    public init() {}

    /// Whether any frames have drawn yet — the overlay/inspector show "—" until
    /// then rather than a misleading zero.
    public var hasData: Bool { fps > 0 }

    func update(fps: Double, frameTimeMS: Double, frameCount: Int, time: Double,
                vertexCount: Int, sdfCount: Int, pointCount: Int, particleCount: Int,
                canvasWidth: Double, canvasHeight: Double, variation: Int) {
        self.fps = fps
        self.frameTimeMS = frameTimeMS
        self.frameCount = frameCount
        self.time = time
        self.vertexCount = vertexCount
        self.sdfCount = sdfCount
        self.pointCount = pointCount
        self.particleCount = particleCount
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.variation = variation
    }
}

/// The built-in extension behind the stats overlay and the live inspector: it
/// copies each frame's `FrameInfo` into a `FrameStats`, throttled to a few times
/// a second so SwiftUI doesn't thrash. The runner owns it and re-attaches it
/// across live-reload swaps, so the readout survives a reload even though a
/// sketch's own extensions reset with the fresh instance — the seam's first
/// customer, replacing the old inline `statsSink`.
final class StatsExtension: SketchExtension {
    let stats: FrameStats

    init(stats: FrameStats) { self.stats = stats }

    func afterFrame(_ sketch: Sketch, _ info: FrameInfo) {
        guard sketch.frameCount % 6 == 0 else { return }   // ~10 Hz at 60fps (frame-count based, so it scales with the refresh rate)
        // Snapshot the numbers now, but publish them to the `@Observable` on the
        // next main-loop turn rather than here. This runs inline in the MTKView
        // draw — inside AppKit's display cycle — and mutating an observed value
        // there drives a *re-entrant* SwiftUI layout pass (the overlay/inspector
        // react synchronously), which can throw a constraint-update exception that
        // unwinds through Swift frames and crashes. Hopping off the render call
        // stack lets the observers update at a safe time.
        let stats = stats
        let fps = info.frameRate, frameTimeMS = info.cpuDrawMS
        let frameCount = sketch.frameCount, time = sketch.time
        let vertexCount = info.vertexCount, sdfCount = info.sdfCount
        let pointCount = info.pointCount, particleCount = info.particleCount
        let canvasWidth = sketch.width, canvasHeight = sketch.height
        let variation = sketch.variation
        DispatchQueue.main.async {
            stats.update(fps: fps, frameTimeMS: frameTimeMS, frameCount: frameCount,
                         time: time, vertexCount: vertexCount, sdfCount: sdfCount,
                         pointCount: pointCount, particleCount: particleCount,
                         canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                         variation: variation)
        }
    }
}
