import Foundation

/// Per-frame timing handed to an extension's `afterFrame(_:_:)` — the wall-clock
/// numbers the runner measures *around* a frame, which the in-frame hooks can't
/// see (fps and CPU cost aren't known until the frame is done).
public struct FrameInfo: Sendable {
    /// Seconds since the previous frame, in real time.
    public let deltaTime: Double
    /// Smoothed frames per second.
    public let frameRate: Double
    /// Smoothed CPU time spent building the frame (`performDraw`), in milliseconds.
    public let cpuDrawMS: Double
    /// Geometry emitted this frame: tessellated vertices and instanced SDF shapes.
    public let vertexCount: Int
    public let sdfCount: Int
}

/// A pluggable lifecycle participant — Ollin's `extend(...)` seam. Register one
/// with `Sketch.extend(_:)` and the runner calls its hooks around each frame.
/// Every method is optional (defaults below do nothing), so an extension
/// implements only the moments it cares about:
///
/// - `setup` runs once, after the sketch's own `setup()`.
/// - `beforeDraw` / `afterDraw` run *inside* the frame, around your `draw()`.
///   `afterDraw` lands before the render, so an extension can draw over the
///   sketch through the bare API (guides, a border, a watermark).
/// - `afterFrame` runs after the render, with the frame's timing — for observers
///   that read rather than draw (a performance readout, a recorder).
///
/// Extensions are per-instance: a fresh sketch — including each live-reload swap
/// — starts with none, which is why a sketch registers its own in `setup()`.
@MainActor
public protocol SketchExtension: AnyObject {
    func setup(_ sketch: Sketch)
    func beforeDraw(_ sketch: Sketch)
    func afterDraw(_ sketch: Sketch)
    func afterFrame(_ sketch: Sketch, _ info: FrameInfo)
}

public extension SketchExtension {
    func setup(_ sketch: Sketch) {}
    func beforeDraw(_ sketch: Sketch) {}
    func afterDraw(_ sketch: Sketch) {}
    func afterFrame(_ sketch: Sketch, _ info: FrameInfo) {}
}
