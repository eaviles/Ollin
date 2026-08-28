/// Where one frame's cost went, and what it asked the GPU to do.
///
/// `FrameStats` answers "how fast is this running". A profile answers "why":
/// the frame's time is split four ways, and the work is counted by the path
/// that drew it, so a slow frame can be traced back to a primitive.
///
/// The four times are measured, not estimated:
///
/// - `cpuDrawMS` is the sketch's own `draw()`, which includes tessellation.
///   This is the documented first bottleneck of an immediate-mode renderer.
/// - `cpuEncodeMS` is turning that recording into GPU commands.
/// - `gpuMS` is what the GPU spent on the frame, from its own timestamps.
/// - `waitMS` is time blocked on the in-flight ring, which is the display's
///   pace rather than any work. A sketch with headroom spends most of its
///   frame here, so a large wait is good news.
///
/// The renderer fills one each frame and hands it over on `FrameInfo`, so an
/// extension reads it exactly like the frame's timing. The counts describe the
/// frame that was just encoded. `gpuMS` describes the most recent frame the GPU
/// finished, which is normally one or two frames back: the number is smoothed
/// for display, so the lag is invisible.
public struct FrameProfile: Sendable, Equatable {

    // MARK: Time (milliseconds)

    /// The sketch's `draw()`: recording primitives and tessellating them.
    public var cpuDrawMS: Double = 0
    /// Building the frame's GPU commands, after `draw()` and before the commit.
    public var cpuEncodeMS: Double = 0
    /// The GPU's own run, from the command buffer's start and end timestamps.
    public var gpuMS: Double = 0
    /// Blocked waiting for a free slot in the triple-buffered ring, which is
    /// the display's pace. Work never happens here.
    public var waitMS: Double = 0

    // MARK: Submitted work

    /// Draw calls issued for the frame, over every pass.
    public var drawCalls: Int = 0
    /// Render passes encoded for the frame: the canvas, plus every effects
    /// target, shadow map, probe bake, filter, and the present.
    public var passes: Int = 0
    /// Compute dispatches encoded for the frame (particles and simulations).
    public var computeDispatches: Int = 0
    /// Call-ordered runs the drawer recorded. A run breaks whenever the
    /// pipeline, blend mode, texture, or clip level changes, so a high count
    /// against few shapes means the sketch is switching state per shape.
    public var batches: Int = 0

    // MARK: Geometry, by the path that drew it

    /// Vertices through the tessellated triangle path (fills).
    public var triangleVertices: Int = 0
    /// Vertices through the fringe stroke path (every stroke).
    public var fringeVertices: Int = 0
    /// Instanced analytic SDF shapes: one quad each, one struct write each.
    public var sdfInstances: Int = 0
    /// Composed SDF fields, 2D and raymarched 3D, each a covering quad whose
    /// fragment walks the node list.
    public var fieldQuads: Int = 0
    /// Vertices through the textured-quad path (images and depth backdrops).
    public var imageVertices: Int = 0
    /// Vertices through the glyph-atlas path (text).
    public var glyphVertices: Int = 0
    /// Vertices of 3D triangle meshes.
    public var meshVertices: Int = 0
    /// Instanced 3D point-cloud splats.
    public var pointSplats: Int = 0
    /// Instanced GPU-particle discs.
    public var particles: Int = 0
    /// Vertices of clip regions, which draw into the stencil rather than the
    /// canvas but still cost tessellation.
    public var clipVertices: Int = 0

    public init() {}

    /// Every vertex the CPU tessellated this frame: fills, strokes, meshes,
    /// images, text, and clip regions. The number that grows when a sketch
    /// slows down on geometry.
    public var tessellatedVertices: Int {
        triangleVertices + fringeVertices + meshVertices
            + imageVertices + glyphVertices + clipVertices
    }

    /// The frame's whole CPU cost: the sketch's draw plus the encode. The wait
    /// is left out, since it is the display's pace rather than work.
    public var cpuMS: Double { cpuDrawMS + cpuEncodeMS }

    /// Whether the profile holds a measured frame yet.
    public var hasData: Bool { drawCalls > 0 || passes > 0 }

    /// Zero the counts, keeping nothing from the previous frame. Timings are
    /// written whole at the end of a frame, so they are not cleared here.
    mutating func resetCounts() {
        drawCalls = 0; passes = 0; computeDispatches = 0; batches = 0
        triangleVertices = 0; fringeVertices = 0; sdfInstances = 0; fieldQuads = 0
        imageVertices = 0; glyphVertices = 0; meshVertices = 0
        pointSplats = 0; particles = 0; clipVertices = 0
    }

    /// Count one draw call and the geometry it carried. Called from the encode
    /// loop, so the counts follow what was really drawn rather than what the
    /// drawer recorded (a batch whose texture failed to build is skipped, and
    /// so is its count).
    mutating func countDraw(_ kind: GeometryKind, _ n: Int) {
        drawCalls += 1
        switch kind {
        case .triangles:  triangleVertices += n
        case .fringe:     fringeVertices += n
        case .sdf:        sdfInstances += n
        case .sdfGroup, .sdfGroup3D: fieldQuads += n
        case .image, .depthScene: imageVertices += n
        case .glyphAtlas: glyphVertices += n
        case .mesh3D:     meshVertices += n
        case .meshInstanced: meshVertices += n   // n = base vertices x copies (total shaded)
        case .meshField:  meshVertices += n      // n = copies placed (the GPU culls; visible count never round-trips)
        case .strands:    meshVertices += n      // n = blades placed (grown in-draw; the GPU culls and grades)
        case .ocean:      meshVertices += n      // n = grid vertices (worked out in-draw from the vertex index)
        case .points3D:   pointSplats += n
        case .particles:  particles += n
        case .clipPush:   clipVertices += n
        case .clipPop:    break        // one synthesized triangle, no geometry
        case .retained:   break        // replayed runs count through their own kinds
        }
    }
}
