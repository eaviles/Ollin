import Observation

/// Shared keys for the on-canvas stats overlay.
public enum OllinHUD {
    /// `UserDefaults`/`@AppStorage` key the "Show FPS" command and the overlay
    /// both bind to, so toggling the menu shows the overlay in any run mode and
    /// the choice persists across launches.
    public static let showStatsKey = "ollin.hud.showStats"
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
    /// Geometry emitted this frame: tessellated vertices and instanced SDF
    /// shapes — the "why is it slow" breakdown.
    public internal(set) var vertexCount: Int = 0
    public internal(set) var sdfCount: Int = 0
    /// The logical canvas size, for context.
    public internal(set) var canvasWidth: Double = 0
    public internal(set) var canvasHeight: Double = 0

    public init() {}

    /// Whether any frames have drawn yet — the overlay/inspector show "—" until
    /// then rather than a misleading zero.
    public var hasData: Bool { fps > 0 }

    func update(fps: Double, frameTimeMS: Double, frameCount: Int, time: Double,
                vertexCount: Int, sdfCount: Int,
                canvasWidth: Double, canvasHeight: Double) {
        self.fps = fps
        self.frameTimeMS = frameTimeMS
        self.frameCount = frameCount
        self.time = time
        self.vertexCount = vertexCount
        self.sdfCount = sdfCount
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }
}
