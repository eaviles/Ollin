import Foundation
import Metal
import simd
import COllinShaders

/// A world of placed meshes the GPU draws and culls by itself.
///
/// `place(_:at:)` scatters copies of any mesh; `drawMeshField(_:)` then draws
/// the whole field with ONE call, every frame, no matter how many meshes and
/// copies it holds. Each frame a compute pass tests every copy against the
/// camera and writes, for each mesh, the draw arguments for its visible copies;
/// the render pass then issues one indirect draw per mesh from them. The CPU
/// never touches a copy again after `place`: no per-copy record or draw call,
/// and everything the camera can't see costs (almost) nothing.
///
/// ```swift
/// let field = MeshField()
///
/// override func setup() {
///     field.place(rock, at: rockSpots)      // [MeshInstance], like drawMesh
///     field.place(pine, at: pineSpots)
///     field.place(grass, at: grassSpots)
/// }
///
/// override func draw() {
///     camera(...)
///     drawMeshField(field)                  // one call for the whole world
/// }
/// ```
///
/// Copies shade like solid meshes (lights, shadows received, image-based
/// lighting, fog) through the current `material(_:)` finish, and they cast into
/// the shadow maps, culled against the light's own frustum rather than the
/// camera's, so a tree behind the camera still throws its shadow into view (a
/// point light's cube map takes every copy). Surface color bakes when a mesh is placed: the mesh
/// material's base color times its per-vertex colors, with each copy's
/// `MeshInstance.color` as the per-copy tint. The draw-time `fill` does not
/// tint a field. Like a `Batch`, a field is persistent: build it in `setup()`
/// and hold it; `place` after the first draw re-uploads the field.
public final class MeshField {

    /// One placed mesh kept CPU-side: the source arrays for the GPU build and
    /// for spatial export (which wants the mesh itself plus each placement).
    struct Placement {
        let mesh: Mesh
        let copies: [MeshInstance]
    }

    private(set) var placements: [Placement] = []
    private(set) var baseVertices: [OllinMeshVertex] = []
    private(set) var instances: [OllinMeshInstance] = []
    private(set) var entries: [OllinFieldEntry] = []

    /// Bumped by `place` so realized GPU resources rebuild on next draw.
    private(set) var generation = 0

    /// Whether copies outside the camera's view are skipped on the GPU (the
    /// default). Turn it off to draw every copy regardless: the A/B switch for
    /// feeling what culling saves, and the picture must not change either way
    /// (a culled copy was off-screen by definition).
    public var isCullingEnabled = true

    /// How many copies this field may put into the ray-traced passes
    /// (reflections, ray-traced shadows, global illumination). A copy there is
    /// not free the way a drawn copy is: the traced scene is rebuilt every
    /// frame, and each copy costs roughly two microseconds of GPU time in it, so
    /// a field of a few hundred thousand would spend the whole frame on it. A
    /// field over the budget stays out of those passes and says so once; the
    /// picture keeps every copy, and the mirrors do not show them.
    ///
    /// Raise it for an offline render, where seconds a frame are fine, or set it
    /// to `0` to keep a field out of the traced passes whatever its size. Camera
    /// culling does not apply here: a reflection sees what the camera cannot, so
    /// the budget counts every copy the field holds.
    public var tracedCopyBudget = 20_000

    /// Whether this field's copies fit inside `tracedCopyBudget`.
    var withinTracedBudget: Bool { copyCount <= tracedCopyBudget }

    /// The same answer, said out loud once when it is no: the note names both
    /// numbers so the budget is findable from the message alone.
    func fitsTracedBudget() -> Bool {
        if withinTracedBudget { return true }
        if !notedTracedBudget {
            notedTracedBudget = true
            let plural = copyCount == 1 ? "copy" : "copies"
            print("Ollin: a MeshField of \(copyCount) \(plural) stays out of the ray-traced passes "
                  + "(reflections, traced shadows, global illumination); the budget is "
                  + "\(tracedCopyBudget) copies. Raise tracedCopyBudget to include them, at "
                  + "roughly two microseconds of GPU time per copy per frame.")
        }
        return false
    }

    private var notedTracedBudget = false

    public init() {}

    /// Total copies across every entry.
    public var copyCount: Int { instances.count }
    /// Distinct placed meshes.
    public var entryCount: Int { entries.count }
    /// Whether nothing has been placed.
    public var isEmpty: Bool { entries.isEmpty }

    /// Add `copies` of `mesh` to the field. Each `MeshInstance` places one copy
    /// (position, rotation, scale, tint), exactly as `drawMesh(_:instances:)`
    /// reads them. The mesh's triangles expand once, here; the copies' matrices
    /// upload once and the GPU does the rest.
    public func place(_ mesh: Mesh, at copies: [MeshInstance]) {
        guard !mesh.isEmpty, !copies.isEmpty else { return }
        let surface = mesh.material?.baseColor.simd4 ?? SIMD4<Float>(1, 1, 1, 1)
        let vertexStart = baseVertices.count
        Drawer.expandBaseMesh(mesh, surface: surface, posW: 1, metalW: 0, into: &baseVertices)
        let (center, radius) = MeshField.boundingSphere(of: mesh)
        entries.append(OllinFieldEntry(
            center: SIMD4<Float>(center.x, center.y, center.z, 0),
            vertexStart: UInt32(vertexStart),
            vertexCount: UInt32(baseVertices.count - vertexStart),
            copyStart: UInt32(instances.count),
            copyCount: UInt32(copies.count),
            compactOffset: UInt32(instances.count),
            radius: radius, _fe0: 0, _fe1: 0))
        instances.reserveCapacity(instances.count + copies.count)
        for copy in copies {
            instances.append(OllinMeshInstance(model: copy.matrix,
                                               color: copy.color?.simd4 ?? SIMD4<Float>(1, 1, 1, 1)))
        }
        placements.append(Placement(mesh: mesh, copies: copies))
        generation += 1
    }

    /// The mesh's local bounding sphere (center + radius over its positions),
    /// the conservative volume the cull kernel tests per copy.
    static func boundingSphere(of mesh: Mesh) -> (SIMD3<Float>, Float) {
        let mid = mesh.bounds.center
        let center = SIMD3<Float>(Float(mid.x), Float(mid.y), Float(mid.z))
        var radius: Float = 0
        for p in mesh.positions {
            let d = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)) - center
            radius = max(radius, simd_length(d))
        }
        return (center, radius)
    }

    /// The box every copy in this field fits inside, in the field's own space
    /// (before the draw-time transform). Each copy's bounding sphere goes
    /// through its own matrix the same conservative way the cull kernel takes
    /// it, so the box answers for the copies without reading a vertex. Cached
    /// against `generation`: a retained field works this out once, however many
    /// copies it holds and however often a frame asks. `nil` when the field is
    /// empty. The point-shadow pass reads it to fit its cube far plane around
    /// copies no CPU-side vertex scan can see.
    func localBounds() -> (lo: SIMD3<Float>, hi: SIMD3<Float>)? {
        if boundsGeneration == generation { return cachedBounds }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for entry in entries {
            let center = SIMD3<Float>(entry.center.x, entry.center.y, entry.center.z)
            let first = Int(entry.copyStart)
            for i in first ..< first + Int(entry.copyCount) {
                let model = instances[i].model
                let placed = model * SIMD4<Float>(center.x, center.y, center.z, 1)
                let world = SIMD3<Float>(placed.x, placed.y, placed.z)
                let radius = entry.radius * model.largestColumnScale
                lo = simd_min(lo, world - radius)
                hi = simd_max(hi, world + radius)
            }
        }
        cachedBounds = lo.x <= hi.x ? (lo, hi) : nil
        boundsGeneration = generation
        return cachedBounds
    }

    private var boundsGeneration = -1
    private var cachedBounds: (lo: SIMD3<Float>, hi: SIMD3<Float>)?

    // MARK: GPU residence

    /// The field's persistent GPU state: the once-written geometry (base
    /// vertices, copies, the entry table) plus the per-frame-rewritten cull
    /// products (visible counts, compacted copy indices, and one GPU-written
    /// `MTLDrawPrimitivesIndirectArguments` per entry). The rewritten pieces are
    /// written by GPU passes inside the frame's own command buffer, so the
    /// triple-buffer hazard the CPU rings guard against does not arise.
    ///
    /// The draws are GPU-authored but issued as per-entry INDIRECT draws rather
    /// than through an `MTLIndirectCommandBuffer`: the lit mesh fragment carries
    /// the ray-tracing intersector on an RT device, and Metal refuses that
    /// fragment inside an ICB pipeline ("Fragment shader cannot be used with
    /// indirect command buffers"). Indirect draws carry the identical payload
    /// (vertexStart, vertexCount, instanceCount, baseInstance) with no fragment
    /// restriction, so copies keep the FULL solid shading everywhere; the CPU
    /// cost stays one draw per distinct mesh, never per copy.
    struct GPUResources {
        var vertices: MTLBuffer
        var instances: MTLBuffer
        var entries: MTLBuffer
        var counts: MTLBuffer
        var compacted: MTLBuffer
        var drawArguments: MTLBuffer
        /// The shadow pass's own cull products: the same shapes culled against
        /// the LIGHT's frustum (the 2D map's box), so a directional or spot
        /// shadow pass also skips what its map cannot hold. Casters outside the
        /// camera frustum but inside the light's still cast, exactly as before.
        var shadowCounts: MTLBuffer
        var shadowCompacted: MTLBuffer
        var shadowArguments: MTLBuffer
        /// The in-order compaction's scratch (a frame whose clock can repeat):
        /// one visible count per SIMD group of copies, scanned in place into
        /// offsets, and one visible-copy base per entry.
        var blockOffsets: MTLBuffer
        var entryBases: MTLBuffer
        var entryCount: Int
    }

    private var gpu: GPUResources?
    private var gpuDevice: ObjectIdentifier?
    private var gpuGeneration = -1

    /// Realize (or reuse) the field's GPU state on `device`. Rebuilt when the
    /// field changed (`generation`) or a different device asks.
    func gpuResources(for device: MTLDevice) -> GPUResources? {
        if let gpu, gpuDevice == ObjectIdentifier(device), gpuGeneration == generation {
            return gpu
        }
        guard !entries.isEmpty else { return nil }
        func buffer<T>(_ array: [T]) -> MTLBuffer? {
            array.withUnsafeBytes { raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: raw.count,
                                  options: .storageModeShared)
            }
        }
        let argsLength = max(1, entries.count) * MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride
        guard let vertices = buffer(baseVertices),
              let instanceBuffer = buffer(instances),
              let entryBuffer = buffer(entries),
              let counts = device.makeBuffer(length: max(1, entries.count) * 4,
                                             options: .storageModeShared),
              let compacted = device.makeBuffer(length: max(1, instances.count) * 4,
                                                options: .storageModePrivate),
              let drawArguments = device.makeBuffer(length: argsLength,
                                                    options: .storageModePrivate),
              let shadowCounts = device.makeBuffer(length: max(1, entries.count) * 4,
                                                   options: .storageModeShared),
              let shadowCompacted = device.makeBuffer(length: max(1, instances.count) * 4,
                                                      options: .storageModePrivate),
              let shadowArguments = device.makeBuffer(length: argsLength,
                                                      options: .storageModePrivate),
              // One count per SIMD group of copies, 32 wide at the narrowest,
              // plus the total the scan leaves in the last entry.
              let blockOffsets = device.makeBuffer(length: (instances.count / 32 + 2) * 4,
                                                   options: .storageModePrivate),
              let entryBases = device.makeBuffer(length: max(1, entries.count) * 4,
                                                 options: .storageModePrivate)
        else { return nil }
        let resources = GPUResources(vertices: vertices, instances: instanceBuffer,
                                     entries: entryBuffer, counts: counts,
                                     compacted: compacted, drawArguments: drawArguments,
                                     shadowCounts: shadowCounts,
                                     shadowCompacted: shadowCompacted,
                                     shadowArguments: shadowArguments,
                                     blockOffsets: blockOffsets, entryBases: entryBases,
                                     entryCount: entries.count)
        gpu = resources
        gpuDevice = ObjectIdentifier(device)
        gpuGeneration = generation
        return resources
    }

    // MARK: The GPU passes

    /// The visibility test every cull shares, as source spliced ahead of each
    /// kernel that needs it: a sphere-vs-frustum test in world space (the
    /// entry's local bounding sphere through the copy's matrix and the field's
    /// draw-time matrix). The copy's entry comes from a range walk (entries are
    /// few; copies are contiguous per entry, so a short scan beats carrying a
    /// per-copy entry index).
    static let visibilitySource = """
    static uint ollin_field_entry(uint tid, const device OllinFieldEntry* entries,
                                  constant OllinFieldCullParams& p) {
        for (uint e = 0; e < p.entryCount; e += 1) {
            if (tid >= entries[e].copyStart && tid < entries[e].copyStart + entries[e].copyCount) {
                return e;
            }
        }
        return 0;
    }

    static bool ollin_field_visible(uint tid, uint entry,
                                    const device OllinMeshInstance* instances,
                                    const device OllinFieldEntry* entries,
                                    constant OllinFieldCullParams& p) {
        if (p.cullEnabled == 0) { return true; }
        OllinFieldEntry en = entries[entry];
        float4x4 m = p.fieldModel * instances[tid].model;
        float4 wc = m * float4(en.center.xyz, 1.0);
        // Conservative world radius: the local radius times the matrix's
        // largest column scale.
        float sx = length(m[0].xyz), sy = length(m[1].xyz), sz = length(m[2].xyz);
        float wr = en.radius * max(sx, max(sy, sz));
        for (uint i = 0; i < 6; i += 1) {
            if (dot(p.planes[i].xyz, wc.xyz) + p.planes[i].w < -wr) { return false; }
        }
        return true;
    }
    """

    /// The cull kernel: one thread per copy, appending survivors into the
    /// entry's own region of the compacted-index buffer. The append order is
    /// whichever order the threads reach the counter, which is the fast form and
    /// the one a live frame uses; a frame whose clock can repeat compacts in
    /// copy order instead (the three kernels below), since copies at equal depth
    /// draw the one that lands first.
    static let cullKernel = ComputeKernel(entry: "ollin_field_cull", visibilitySource + """
    kernel void ollin_field_cull(const device OllinMeshInstance* instances [[buffer(0)]],
                                 const device OllinFieldEntry* entries [[buffer(1)]],
                                 device atomic_uint* counts [[buffer(2)]],
                                 device uint* compacted [[buffer(3)]],
                                 constant OllinFieldCullParams& p [[buffer(4)]],
                                 uint tid [[thread_position_in_grid]]) {
        if (tid >= p.copyCount) { return; }
        uint entry = ollin_field_entry(tid, entries, p);
        if (!ollin_field_visible(tid, entry, instances, entries, p)) { return; }
        OllinFieldEntry en = entries[entry];
        uint slot = atomic_fetch_add_explicit(&counts[entry], 1, memory_order_relaxed);
        compacted[en.compactOffset + slot] = tid;
    }
    """)

    /// The in-order compaction, for a frame whose clock can repeat, in three
    /// kernels sharing one source (so they compile together):
    ///
    /// - `ollin_field_count`, one thread per copy: each SIMD group writes how
    ///   many of its copies are visible. The groups are the dispatch's
    ///   threadgroups (one execution width wide), so copy `tid` is in group
    ///   `tid / width` in every pass.
    /// - `ollin_field_scan`, one thread: scans the group counts into offsets
    ///   (the last entry the total), then gives every entry its base (the
    ///   visible copies before its first) and its count. A base falls inside a
    ///   group, so the copies before it in that group are tested again there.
    /// - `ollin_field_place`, one thread per copy: a visible copy writes itself
    ///   at its place among the visible copies of its entry.
    static let orderedSource = visibilitySource + """
    kernel void ollin_field_count(const device OllinMeshInstance* instances [[buffer(0)]],
                                  const device OllinFieldEntry* entries [[buffer(1)]],
                                  device uint* blocks [[buffer(5)]],
                                  constant OllinFieldCullParams& p [[buffer(4)]],
                                  uint tid [[thread_position_in_grid]],
                                  uint lane [[thread_index_in_simdgroup]],
                                  uint width [[threads_per_simdgroup]]) {
        bool visible = tid < p.copyCount
            && ollin_field_visible(tid, ollin_field_entry(tid, entries, p), instances, entries, p);
        uint total = simd_sum(visible ? 1u : 0u);
        if (lane == 0 && tid < p.copyCount) { blocks[tid / width] = total; }
    }

    static uint ollin_field_visible_before(uint copy, uint width, const device uint* blocks,
                                           const device OllinMeshInstance* instances,
                                           const device OllinFieldEntry* entries,
                                           constant OllinFieldCullParams& p) {
        uint first = (copy / width) * width;
        uint n = blocks[copy / width];
        for (uint i = first; i < copy; i += 1) {
            n += ollin_field_visible(i, ollin_field_entry(i, entries, p), instances, entries, p) ? 1u : 0u;
        }
        return n;
    }

    kernel void ollin_field_scan(const device OllinMeshInstance* instances [[buffer(0)]],
                                 const device OllinFieldEntry* entries [[buffer(1)]],
                                 device uint* counts [[buffer(2)]],
                                 constant OllinFieldCullParams& p [[buffer(4)]],
                                 device uint* blocks [[buffer(5)]],
                                 device uint* bases [[buffer(6)]],
                                 constant uint& width [[buffer(7)]],
                                 uint tid [[thread_position_in_grid]]) {
        if (tid != 0) { return; }
        uint groups = (p.copyCount + width - 1) / width;
        uint acc = 0;
        for (uint g = 0; g < groups; g += 1) {
            uint n = blocks[g];
            blocks[g] = acc;
            acc += n;
        }
        blocks[groups] = acc;
        for (uint e = 0; e < p.entryCount; e += 1) {
            OllinFieldEntry en = entries[e];
            uint base = ollin_field_visible_before(en.copyStart, width, blocks, instances, entries, p);
            uint end = ollin_field_visible_before(en.copyStart + en.copyCount, width, blocks,
                                                  instances, entries, p);
            bases[e] = base;
            counts[e] = end - base;
        }
    }

    kernel void ollin_field_place(const device OllinMeshInstance* instances [[buffer(0)]],
                                  const device OllinFieldEntry* entries [[buffer(1)]],
                                  device uint* compacted [[buffer(3)]],
                                  constant OllinFieldCullParams& p [[buffer(4)]],
                                  const device uint* blocks [[buffer(5)]],
                                  const device uint* bases [[buffer(6)]],
                                  uint tid [[thread_position_in_grid]],
                                  uint width [[threads_per_simdgroup]]) {
        uint entry = tid < p.copyCount ? ollin_field_entry(tid, entries, p) : 0;
        bool visible = tid < p.copyCount
            && ollin_field_visible(tid, entry, instances, entries, p);
        uint before = simd_prefix_exclusive_sum(visible ? 1u : 0u);
        if (!visible) { return; }
        uint place = blocks[tid / width] + before - bases[entry];
        compacted[entries[entry].compactOffset + place] = tid;
    }
    """

    static let countKernel = ComputeKernel(entry: "ollin_field_count", orderedSource)
    static let scanKernel = ComputeKernel(entry: "ollin_field_scan", orderedSource)
    static let placeKernel = ComputeKernel(entry: "ollin_field_place", orderedSource)

    /// The encode kernel: one thread per entry, writing that entry's single
    /// instanced draw as `MTLDrawPrimitivesIndirectArguments` (instanceCount 0
    /// for an entry with no visible copies, which the GPU draws as nothing).
    static let encodeKernel = ComputeKernel(entry: "ollin_field_encode", """
    // The layout of MTLDrawPrimitivesIndirectArguments.
    struct OllinFieldDrawArgs {
        uint vertexCount;
        uint instanceCount;
        uint vertexStart;
        uint baseInstance;
    };

    kernel void ollin_field_encode(device OllinFieldDrawArgs* draws [[buffer(0)]],
                                   const device OllinFieldEntry* entries [[buffer(1)]],
                                   device const uint* counts [[buffer(2)]],
                                   constant OllinFieldCullParams& p [[buffer(4)]],
                                   uint tid [[thread_position_in_grid]]) {
        if (tid >= p.entryCount) { return; }
        OllinFieldEntry en = entries[tid];
        draws[tid].vertexCount = en.vertexCount;
        draws[tid].instanceCount = counts[tid];
        draws[tid].vertexStart = en.vertexStart;
        draws[tid].baseInstance = en.compactOffset;
    }
    """)

    /// The six inward world-space frustum planes of `viewProjection`
    /// (Gribb-Hartmann row combinations, normalized).
    static func frustumPlanes(of vp: simd_float4x4) -> [SIMD4<Float>] {
        // Rows of the matrix (simd stores columns).
        let r0 = SIMD4<Float>(vp.columns.0.x, vp.columns.1.x, vp.columns.2.x, vp.columns.3.x)
        let r1 = SIMD4<Float>(vp.columns.0.y, vp.columns.1.y, vp.columns.2.y, vp.columns.3.y)
        let r2 = SIMD4<Float>(vp.columns.0.z, vp.columns.1.z, vp.columns.2.z, vp.columns.3.z)
        let r3 = SIMD4<Float>(vp.columns.0.w, vp.columns.1.w, vp.columns.2.w, vp.columns.3.w)
        // Metal clip space: x,y in [-w, w], z in [0, w].
        var planes = [r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2, r3 - r2]
        for i in planes.indices {
            let n = simd_length(SIMD3<Float>(planes[i].x, planes[i].y, planes[i].z))
            if n > 0 { planes[i] /= n }
        }
        return planes
    }
}
