import Foundation
import Metal
import simd
import COllinShaders

/// A world of placed meshes the GPU draws and culls by itself.
///
/// `place(_:at:)` scatters copies of any mesh; `drawMeshField(_:)` then draws
/// the whole field with ONE call, every frame, no matter how many meshes and
/// copies it holds. Each frame a compute pass tests every copy against the
/// camera and writes a draw command for each mesh's visible copies into an
/// indirect command buffer; the render pass executes that buffer whole. The CPU
/// never touches a copy again after `place`: no per-copy record, no per-mesh
/// draw call, and everything the camera can't see costs (almost) nothing.
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
/// the shadow maps (uncculled there: a tree behind the camera still throws its
/// shadow into view). Surface color bakes when a mesh is placed: the mesh
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
    public var cullingEnabled = true

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
        let bounds = mesh.bounds
        let center = SIMD3<Float>(Float((bounds.min.x + bounds.max.x) / 2),
                                  Float((bounds.min.y + bounds.max.y) / 2),
                                  Float((bounds.min.z + bounds.max.z) / 2))
        var radius: Float = 0
        for p in mesh.positions {
            let d = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)) - center
            radius = max(radius, simd_length(d))
        }
        return (center, radius)
    }

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
                                                      options: .storageModePrivate)
        else { return nil }
        let resources = GPUResources(vertices: vertices, instances: instanceBuffer,
                                     entries: entryBuffer, counts: counts,
                                     compacted: compacted, drawArguments: drawArguments,
                                     shadowCounts: shadowCounts,
                                     shadowCompacted: shadowCompacted,
                                     shadowArguments: shadowArguments,
                                     entryCount: entries.count)
        gpu = resources
        gpuDevice = ObjectIdentifier(device)
        gpuGeneration = generation
        return resources
    }

    // MARK: The GPU passes

    /// The cull kernel: one thread per copy, a sphere-vs-frustum test in world
    /// space (the entry's local bounding sphere through the copy's matrix and
    /// the field's draw-time matrix), appending survivors into the entry's own
    /// region of the compacted-index buffer.
    static let cullKernel = ComputeKernel(entry: "ollin_field_cull", """
    kernel void ollin_field_cull(const device OllinMeshInstance* instances [[buffer(0)]],
                                 const device OllinFieldEntry* entries [[buffer(1)]],
                                 device atomic_uint* counts [[buffer(2)]],
                                 device uint* compacted [[buffer(3)]],
                                 constant OllinFieldCullParams& p [[buffer(4)]],
                                 uint tid [[thread_position_in_grid]]) {
        if (tid >= p.copyCount) { return; }
        // The copy's entry, by range walk (entries are few; copies are contiguous
        // per entry, so a short scan beats carrying a per-copy entry index).
        uint entry = 0;
        for (uint e = 0; e < p.entryCount; e += 1) {
            if (tid >= entries[e].copyStart && tid < entries[e].copyStart + entries[e].copyCount) {
                entry = e; break;
            }
        }
        OllinFieldEntry en = entries[entry];
        if (p.cullEnabled != 0) {
            float4x4 m = p.fieldModel * instances[tid].model;
            float4 wc = m * float4(en.center.xyz, 1.0);
            // Conservative world radius: the local radius times the matrix's
            // largest column scale.
            float sx = length(m[0].xyz), sy = length(m[1].xyz), sz = length(m[2].xyz);
            float wr = en.radius * max(sx, max(sy, sz));
            for (uint i = 0; i < 6; i += 1) {
                if (dot(p.planes[i].xyz, wc.xyz) + p.planes[i].w < -wr) { return; }
            }
        }
        uint slot = atomic_fetch_add_explicit(&counts[entry], 1, memory_order_relaxed);
        compacted[en.compactOffset + slot] = tid;
    }
    """)

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
