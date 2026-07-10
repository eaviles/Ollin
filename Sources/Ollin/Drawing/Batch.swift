import Foundation
import Metal
import simd
import COllinShaders

/// A drawing recorded once and replayed for free.
///
/// Everything drawn inside `makeBatch { }` is captured (shapes, strokes, curves,
/// text, images, SDF combinators, point clouds) and `drawBatch(_:)` replays it
/// each frame from geometry that lives on the GPU. The per-frame cost of the
/// recorded content drops to (almost) zero: no per-shape recording, no
/// tessellation, no upload. That's the tool for *static, heavy* geometry (a
/// fixed point cloud, a dense generative background, a long traced orbit) and
/// for stamping one complex motif many times:
///
/// ```swift
/// var stars: Batch!
///
/// override func setup() {
///     stars = makeBatch {
///         for _ in 0 ..< 200_000 { drawCircle(random(width), random(height), 1.2) }
///     }
/// }
///
/// override func draw() {
///     background(.black)
///     drawBatch(stars)                 // replays at full speed
/// }
/// ```
///
/// A batch records in its own canvas-space frame (the transform starts at
/// identity inside the block), and the transform in force at `drawBatch` time
/// moves the whole recording as a unit: `translate`/`rotate`/`scale` place,
/// spin, or resize the replay, and one recording can be stamped many times at
/// different placements. Drawing state set inside the block (fill, stroke, blend)
/// is honored by the replay and restored on exit, like `withState { }`.
///
/// Like a `Feedback` layer, a `Batch` is **persistent**: record it once in
/// `setup()` (or whenever the content actually changes) and hold it. Re-recording
/// every frame just rebuilds the geometry and buys nothing. Contents are
/// immutable once recorded; record a new batch to change them.
///
/// Not recordable (skipped with a one-time note): meshes and raymarched 3D
/// fields, GPU particles, layers (`withTarget` and friends), clipping, and
/// `background(_:)`. Point clouds record and replay through the camera each
/// frame; the draw-time transform applies to the 2D content only. Symmetry
/// *inside* the block bakes into the recording; symmetry active at `drawBatch`
/// time does not fold the replay.
public final class Batch {

    // The recorded geometry, immutable after recording: the same arrays the
    // per-frame recorder fills, captured whole, plus the call-ordered runs that
    // index into them. `gradientRows` are handle-relative (recording swaps the
    // frame's row table), so instances' baked row indices resolve against this
    // batch's own strip texture, never the frame's.
    let vertices: [OllinVertex]
    let sdfInstances: [SDFInstance]
    let imageVertices: [OllinImageVertex]
    let glyphVertices: [OllinImageVertex]
    let points: [OllinPoint]
    let sdfGroups: [SDFGroupInstance]
    let sdfNodes: [SDFNode]
    let gradientRows: [[UInt8]]
    let innerBatches: [GeometryBatch]

    /// The vector capture, recorded instead of GPU geometry when the whole run is
    /// a vector export (`OllinApp.isVectorExporting`); `drawBatch` splices these
    /// into the active recorder under the draw-time CTM. Empty on the raster path.
    let svgCommands: [SVGCommand]

    /// Whether the recording captured nothing drawable.
    public var isEmpty: Bool { innerBatches.isEmpty && svgCommands.isEmpty }

    /// Whether the recording holds 3D point-cloud content (needs a camera and a
    /// depth-carrying pass to replay, like a live `drawPointCloud`).
    var hasPointContent: Bool { !points.isEmpty }

    init(vertices: [OllinVertex] = [], sdfInstances: [SDFInstance] = [],
         imageVertices: [OllinImageVertex] = [], glyphVertices: [OllinImageVertex] = [],
         points: [OllinPoint] = [], sdfGroups: [SDFGroupInstance] = [],
         sdfNodes: [SDFNode] = [], gradientRows: [[UInt8]] = [],
         innerBatches: [GeometryBatch] = [], svgCommands: [SVGCommand] = []) {
        self.vertices = vertices
        self.sdfInstances = sdfInstances
        self.imageVertices = imageVertices
        self.glyphVertices = glyphVertices
        self.points = points
        self.sdfGroups = sdfGroups
        self.sdfNodes = sdfNodes
        self.gradientRows = gradientRows
        self.innerBatches = innerBatches
        self.svgCommands = svgCommands
    }

    // MARK: GPU residence

    /// The batch's persistent GPU buffers (plus its own gradient strip). Unlike
    /// the per-frame ring, these are written once from the recorded arrays and
    /// never mutated, so there is no in-flight frame to guard against and no
    /// in-place replacement to avoid.
    struct GPUResources {
        var triangle: MTLBuffer?
        var sdf: MTLBuffer?
        var image: MTLBuffer?
        var glyph: MTLBuffer?
        var point: MTLBuffer?
        var sdfGroup: MTLBuffer?
        var sdfNode: MTLBuffer?
        var strip: MTLTexture?
    }

    private var gpu: GPUResources?
    private var gpuDevice: ObjectIdentifier?

    /// The GPU-resident copy of the recording, made on first use and cached on
    /// the batch (the per-device caching an `Image`'s texture uses). Rebuilt only
    /// if a different device asks.
    func gpuResources(for device: MTLDevice) -> GPUResources {
        if let gpu, gpuDevice == ObjectIdentifier(device) { return gpu }
        func buffer<T>(_ array: [T]) -> MTLBuffer? {
            guard !array.isEmpty else { return nil }
            return array.withUnsafeBytes { raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: raw.count,
                                  options: .storageModeShared)
            }
        }
        var resources = GPUResources(
            triangle: buffer(vertices), sdf: buffer(sdfInstances),
            image: buffer(imageVertices), glyph: buffer(glyphVertices),
            point: buffer(points), sdfGroup: buffer(sdfGroups),
            sdfNode: buffer(sdfNodes))
        // The SDF pipelines reference the gradient strip even for all-solid
        // content, so any SDF presence bakes one (a single black row when the
        // recording used no gradients).
        if !sdfInstances.isEmpty || !sdfGroups.isEmpty {
            resources.strip = MetalRenderer.makeGradientStrip(device: device, rows: gradientRows)
        }
        gpu = resources
        gpuDevice = ObjectIdentifier(device)
        return resources
    }
}
