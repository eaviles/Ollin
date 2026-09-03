import Foundation
import CoreGraphics
import Metal

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
    /// Instanced 3D point-cloud splats and GPU-particle discs emitted this frame —
    /// the GPU-resident paths, which aren't in any CPU vertex array.
    public let pointCount: Int
    public let particleCount: Int
    /// The frame's cost breakdown: the four-way time split and the work each
    /// drawing path did (see `FrameProfile`). The four times arrive smoothed,
    /// like `frameRate` and `cpuDrawMS`; the counts are this frame's exactly.
    public let profile: FrameProfile
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
/// - `frameRendered` hands over the *rendered pixels* of the frame, as a
///   `CGImage` or a Metal texture, once the GPU has finished it: for a recorder,
///   a live snapshot, a shared feed. It is the frame the window shows, brought to
///   the canvas size, and it arrives a refresh or so after `afterFrame`, in frame
///   order. Grabbing a frame costs a tone-map pass and a copy, so it's off unless
///   the extension opts in by returning `true` from `wantsRenderedFrame` or
///   `wantsRenderedTexture` (read once each frame, so an extension can arm and
///   disarm capture on the fly).
///
/// Extensions are per-instance: a fresh sketch — including each live-reload swap
/// — starts with none, which is why a sketch registers its own in `setup()`.
@MainActor
public protocol SketchExtension: AnyObject {
    func setup(_ sketch: Sketch)
    func beforeDraw(_ sketch: Sketch)
    func afterDraw(_ sketch: Sketch)
    func afterFrame(_ sketch: Sketch, _ info: FrameInfo)

    /// Whether this extension wants the rendered frame delivered to
    /// `frameRendered(_:image:)`. Read once every frame, before the frame is
    /// drawn, so it can change at runtime (arm one capture, then disarm), and a
    /// frame asked for is a frame delivered, a refresh or so later. Defaults to
    /// `false`: no grab unless something asks. When *any* registered extension
    /// returns `true`, the loop grabs the frame and calls `frameRendered` on each
    /// that asked.
    var wantsRenderedFrame: Bool { get }
    /// The rendered frame, as a `CGImage` at the canvas size, once the GPU has
    /// finished it: the frame the window shows. Only delivered when
    /// `wantsRenderedFrame` was `true` for that frame. Use it to save a
    /// snapshot, feed a video encoder, or compare against a reference.
    func frameRendered(_ sketch: Sketch, image: CGImage)

    /// Whether this extension wants the rendered frame delivered as a Metal
    /// *texture* to `frameRendered(_:texture:)`. The GPU-side companion to
    /// `wantsRenderedFrame`: read once every frame (so it can arm/disarm),
    /// defaults to `false`. When `true`, the loop hands over the frame's texture
    /// with no round trip through the CPU, for sharing the live frame on the GPU
    /// (Syphon, the virtual camera, an LED map). Independent of
    /// `wantsRenderedFrame`; an extension can want either, both, or neither.
    var wantsRenderedTexture: Bool { get }
    /// The rendered frame as a Metal texture (the display pixels, sRGB, at the
    /// canvas size), once the GPU has finished it. Only delivered when
    /// `wantsRenderedTexture` was `true` for that frame. The texture is the
    /// loop's to reuse after this call returns, so copy from it (e.g. publish
    /// it) rather than retaining it across frames.
    func frameRendered(_ sketch: Sketch, texture: MTLTexture)
}

public extension SketchExtension {
    func setup(_ sketch: Sketch) {}
    func beforeDraw(_ sketch: Sketch) {}
    func afterDraw(_ sketch: Sketch) {}
    func afterFrame(_ sketch: Sketch, _ info: FrameInfo) {}
    var wantsRenderedFrame: Bool { false }
    func frameRendered(_ sketch: Sketch, image: CGImage) {}
    var wantsRenderedTexture: Bool { false }
    func frameRendered(_ sketch: Sketch, texture: MTLTexture) {}
}
