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
/// - `frameRendered` hands over the *rendered pixels* of the frame as a
///   `CGImage`, after the render — for a recorder or a live snapshot. Grabbing
///   the frame costs a GPU→CPU readback, so it's off unless the extension opts
///   in by returning `true` from `wantsRenderedFrame` (which the loop reads each
///   frame, so an extension can arm and disarm capture on the fly).
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
    /// `frameRendered(_:_:)`. Read every frame, so it can change at runtime
    /// (arm one capture, then disarm). Defaults to `false`: no readback cost
    /// unless something asks. When *any* registered extension returns `true`,
    /// the loop grabs the frame and calls `frameRendered` on each that asked.
    var wantsRenderedFrame: Bool { get }
    /// The rendered frame, as a `CGImage`, after it's drawn. Only delivered when
    /// `wantsRenderedFrame` is `true`. Use it to save a snapshot, feed a video
    /// encoder, or compare against a reference.
    func frameRendered(_ sketch: Sketch, _ image: CGImage)

    /// Whether this extension wants the rendered frame delivered as a Metal
    /// *texture* to `frameRendered(_:texture:)`. The GPU-side companion to
    /// `wantsRenderedFrame`: read every frame (so it can arm/disarm), defaults to
    /// `false`. When `true`, the loop re-renders the frame off-screen and hands
    /// over the texture — for sharing the live frame on the GPU (Syphon) with no
    /// CPU round-trip. Independent of `wantsRenderedFrame`; an extension can want
    /// either, both, or neither.
    var wantsRenderedTexture: Bool { get }
    /// The rendered frame as a Metal texture (the resolved canvas pixels, sRGB),
    /// after it's drawn. Only delivered when `wantsRenderedTexture` is `true`. The
    /// texture is the loop's to reuse after this call returns, so copy from it
    /// (e.g. publish it) rather than retaining it across frames.
    func frameRendered(_ sketch: Sketch, texture: MTLTexture)
}

public extension SketchExtension {
    func setup(_ sketch: Sketch) {}
    func beforeDraw(_ sketch: Sketch) {}
    func afterDraw(_ sketch: Sketch) {}
    func afterFrame(_ sketch: Sketch, _ info: FrameInfo) {}
    var wantsRenderedFrame: Bool { false }
    func frameRendered(_ sketch: Sketch, _ image: CGImage) {}
    var wantsRenderedTexture: Bool { false }
    func frameRendered(_ sketch: Sketch, texture: MTLTexture) {}
}
