import Foundation
import Metal
import simd
import COllinShaders

/// The traced scene's GPU-written instance descriptors.
///
/// A copy drawn from a `[MeshInstance]` list has its placement on the CPU, so
/// `buildShadowAccel` writes that copy's instance descriptor and its hit record
/// directly. The two GPU-resident forms cannot work that way: the compute-buffer
/// draw keeps its matrices in a buffer a kernel writes (they never visit the
/// CPU), and a `MeshField` holds far more copies than a frame can afford to hand
/// over one at a time. What both do know CPU-side is the COUNT, which is all the
/// build needs to reserve the slots. A kernel then fills them, reading the same
/// placements the draw itself reads.
///
/// The descriptor layout is Metal's own `MTLAccelerationStructureInstanceDescriptor`
/// (a packed 4x3 transform, then options, mask, function-table offset, and the
/// index of the copy's base structure; 64 bytes). The kernel mirrors that struct
/// rather than including a header, because a compute kernel is composed from
/// source at runtime.
extension MetalRenderer {

    /// One thread per copy: the copy's instance descriptor, and the hit record
    /// that tells a reflection which base mesh it hit and in what color.
    static let rtInstanceKernel = ComputeKernel(entry: "ollin_rt_instance_write", """
    // The layout of MTLAccelerationStructureInstanceDescriptor, 64 bytes.
    struct OllinRTInstanceDesc {
        packed_float3 columns[4];
        uint options;
        uint mask;
        uint functionTableOffset;
        uint structureIndex;
    };

    kernel void ollin_rt_instance_write(device OllinRTInstanceDesc* descs [[buffer(0)]],
                                        device uint* table [[buffer(1)]],
                                        const device OllinMeshInstance* placements [[buffer(2)]],
                                        constant OllinRTInstanceParams& p [[buffer(3)]],
                                        uint tid [[thread_position_in_grid]]) {
        if (tid >= p.count) { return; }
        float4x4 m = p.fieldModel * placements[tid].model;
        uint slot = p.instanceBase + tid;
        descs[slot].columns[0] = m[0].xyz;
        descs[slot].columns[1] = m[1].xyz;
        descs[slot].columns[2] = m[2].xyz;
        descs[slot].columns[3] = m[3].xyz;
        descs[slot].options = p.options;
        descs[slot].mask = p.mask;
        descs[slot].functionTableOffset = 0u;
        descs[slot].structureIndex = p.structureIndex;
        // The hit record for this slot, in the same layout the CPU writes for a
        // list copy: the base mesh's first vertex, then the tint as three floats.
        uint r = 1u + slot * 4u;
        float4 tint = placements[tid].color;
        table[r + 0u] = p.vertexBase;
        table[r + 1u] = as_type<uint>(tint.x);
        table[r + 2u] = as_type<uint>(tint.y);
        table[r + 3u] = as_type<uint>(tint.z);
    }
    """)

    /// One run of copies whose placements live on the GPU: the base mesh's run in
    /// the mesh buffer, the buffer holding the placements, and how many there are.
    struct RTInstanceRun {
        /// The base mesh's first vertex in the frame's mesh buffer.
        var vertexBase: Int
        /// The primitive structure built over that base mesh.
        var structureIndex: Int
        /// The first instance slot of the run.
        var instanceBase: Int
        /// Where the placements live, and at what element offset the run starts.
        var placements: MTLBuffer
        var placementOffset: Int
        /// How many copies the run holds (the dispatch width).
        var count: Int
        /// Composed onto every placement (identity for the compute-buffer form,
        /// the draw-time 3D transform for a field).
        var model: simd_float4x4
    }

    /// Encode the descriptor writes for every GPU-resident run, ahead of the
    /// acceleration-structure builds in the same command buffer. Returns false
    /// when the pipeline will not build, which is the caller's signal to leave
    /// those runs out of the scene rather than trace stale descriptors.
    func encodeRTInstanceWrites(_ runs: [RTInstanceRun], descriptors: MTLBuffer,
                                table: MTLBuffer, into commandBuffer: MTLCommandBuffer) -> Bool {
        guard !runs.isEmpty else { return true }
        guard let state = try? computePipeline(for: MetalRenderer.rtInstanceKernel),
              let compute = commandBuffer.makeComputeCommandEncoder() else { return false }
        let stride = MemoryLayout<OllinMeshInstance>.stride
        let width = state.threadExecutionWidth
        compute.setComputePipelineState(state)
        compute.setBuffer(descriptors, offset: 0, index: 0)
        compute.setBuffer(table, offset: 0, index: 1)
        for run in runs {
            var params = OllinRTInstanceParams()
            params.fieldModel = run.model
            params.count = UInt32(run.count)
            params.instanceBase = UInt32(run.instanceBase)
            params.structureIndex = UInt32(run.structureIndex)
            params.vertexBase = UInt32(run.vertexBase)
            params.options = UInt32(MTLAccelerationStructureInstanceOptions.opaque.rawValue)
            params.mask = 0xFF
            compute.setBuffer(run.placements, offset: run.placementOffset * stride, index: 2)
            compute.setBytes(&params, length: MemoryLayout<OllinRTInstanceParams>.stride, index: 3)
            compute.dispatchThreads(MTLSize(width: run.count, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: min(width, run.count),
                                                                   height: 1, depth: 1))
            profile.computeDispatches += 1
        }
        compute.endEncoding()
        return true
    }
}
