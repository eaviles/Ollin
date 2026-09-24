import Foundation
import Metal
import os

// MARK: - Where a pass's samples live

// A tile-based GPU bins a render pass's geometry into a parameter buffer before
// it shades any tile. When a pass holds more than that buffer does, the GPU
// renders what it has binned, stores the attachments, and loads them back to
// go on: a partial render. A memoryless attachment has no memory to be stored
// into, so the GPU refuses the whole command buffer instead ("Too much geometry
// to support memoryless render pass attachments") and the frame comes back
// empty. Measured on the M2 with 4x MSAA in half float: one-pixel marks fail
// from 7.7 million in a pass on a 4096-pixel canvas to 10.6 million on a
// 64-pixel one, forty-pixel marks from 3.6 million, two-hundred-pixel ones from
// 0.56 million; a depth attachment barely moves it. The same passes on
// private attachments draw 40 million marks. A partial render stores nothing
// otherwise, so private storage costs the memory behind the samples and no
// bandwidth until the pass needs it, and the pixels are the same.

extension MetalRenderer {

    /// The most triangles a geometry pass holds while its multisample
    /// attachments stay memoryless. Past it the pass takes `.private` ones. Well
    /// under every overflow measured, since what a triangle costs the parameter
    /// buffer grows with the tiles it covers; a pass nobody could count (GPU
    /// grown geometry) is caught by the failure it causes instead.
    static let backedAttachmentPrimitives = 1_000_000

    /// The storage a geometry pass's MSAA color, depth, and stencil attachments
    /// take: memoryless while the pass drawing onto `target` (nil for the
    /// canvas) is small enough to bin whole, private once it is not, and private
    /// for every pass once any frame has overflowed.
    func attachmentStorage(for drawer: Drawer, target: RenderTarget?) -> MTLStorageMode {
        if gpuFailures.hasOverflowed { return .private }
        return drawer.primitiveCount(on: target) > MetalRenderer.backedAttachmentPrimitives
            ? .private : .memoryless
    }
}

extension Drawer {

    /// About how many triangles the pass drawing onto `target` (nil for the
    /// canvas) rasterizes, counted from what the frame recorded the way the
    /// encoder sizes each draw: a quad per SDF shape, particle, or splat, a
    /// third of every vertex list, the copies of an instanced mesh. Geometry the
    /// GPU grows for itself (a mesh field's culled copies, strands, the ocean's
    /// grid) is not counted.
    func primitiveCount(on target: RenderTarget?) -> Int {
        var total = 0
        for i in batches.indices where batches[i].target === target {
            let batch = batches[i]
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            switch batch.kind {
            case .triangles, .fringe, .clipPush:
                total += ((next?.vertexStart ?? vertices.count) - batch.vertexStart) / 3
            case .sdf:
                total += ((next?.instanceStart ?? sdfInstances.count) - batch.instanceStart) * 2
            case .image, .depthScene:
                total += ((next?.imageStart ?? imageVertices.count) - batch.imageStart) / 3
            case .glyphAtlas:
                total += ((next?.glyphStart ?? glyphVertices.count) - batch.glyphStart) / 3
            case .particles:
                total += batch.particleCount * 2
            case .points3D:
                total += batch.particleBuffer != nil
                    ? batch.particleCount * 2
                    : ((next?.pointStart ?? points.count) - batch.pointStart) * 2
            case .mesh3D:
                total += ((next?.meshStart ?? meshVertices.count) - batch.meshStart) / 3
            case .meshInstanced:
                let copies = batch.particleBuffer != nil ? batch.particleCount : batch.meshInstanceCount
                total += batch.instancedVertexCount / 3 * copies
            case .retained:
                if let handle = batch.retained {
                    total += handle.vertices.count / 3 + handle.sdfInstances.count * 2
                        + (handle.imageVertices.count + handle.glyphVertices.count) / 3
                        + handle.points.count * 2
                }
            case .sdfGroup, .sdfGroup3D, .clipPop, .meshField, .strands, .ocean:
                break
            }
        }
        return total
    }
}

// MARK: - What went wrong on the GPU

/// What each finished frame's command buffer says about itself. A command
/// buffer that fails leaves its frame empty and says so nowhere else, so a
/// failure is written to standard error, once for each different sentence (a
/// frame rate of the same line helps nobody), and the one failure the renderer
/// can answer, a pass that outgrew memoryless attachments, turns every later
/// pass to backed ones. Read from the completed handlers, off the main actor,
/// so its state rides a lock.
final class GPUFailures: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (overflowed: false, said: Set<String>()))

    /// Whether any frame has overflowed memoryless attachments.
    var hasOverflowed: Bool { state.withLock { $0.overflowed } }

    /// Read a finished command buffer. Nothing happens unless it failed.
    func check(_ buffer: MTLCommandBuffer) {
        guard buffer.status == .error else { return }
        let (sentence, overflow) = GPUFailures.describe(buffer.error)
        let isNew = state.withLock { state -> Bool in
            if overflow { state.overflowed = true }
            return state.said.insert(sentence).inserted
        }
        if isNew { FileHandle.standardError.write(Data(("Ollin: " + sentence + "\n").utf8)) }
    }

    /// The sentence for a failed frame, and whether the failure is the
    /// geometry overflow that backed attachments answer.
    static func describe(_ error: Error?) -> (sentence: String, overflow: Bool) {
        guard let error = error as NSError? else {
            return ("a frame failed on the GPU and came back empty, with no reason given", false)
        }
        if error.domain == MTLCommandBufferErrorDomain,
           error.code == MTLCommandBufferError.Code.memoryless.rawValue {
            return ("a frame held more geometry in one pass than memoryless attachments can take, "
                    + "so the GPU drew none of it; every pass from here on draws on backed ones "
                    + "(\(error.localizedDescription))", true)
        }
        return ("a frame failed on the GPU and came back empty: \(error.localizedDescription)", false)
    }
}
