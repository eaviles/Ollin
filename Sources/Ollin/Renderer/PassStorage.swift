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
            case .lines3D:
                if let edges = batch.edgeSet {
                    let copies = batch.particleBuffer != nil ? batch.particleCount : batch.meshInstanceCount
                    total += edges.edges.count * 2 * copies
                } else {
                    total += (batch.lineCoreCount + batch.lineFringeCount) / 3
                }
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

    /// Whether everything drawn onto `target` this frame is particles drawn as
    /// light, or nothing at all: a pass that needs no multisampling, since a
    /// light particle's coverage is its own, and so can be drawn single-sample.
    func drawsOnlyLight(on target: RenderTarget) -> Bool {
        guard !target.needsStencil, !target.needsDepth else { return false }
        for batch in batches where batch.target === target {
            guard batch.kind == .particles, batch.particleStyle == .light else { return false }
        }
        return true
    }
}

// MARK: - What went wrong on the GPU

/// What each finished frame's command buffer says about itself. A command
/// buffer that fails leaves its frame empty and says so nowhere else, so a
/// live frame's failure is written to standard error, once for each different
/// sentence (a frame rate of the same line helps nobody), while a headless
/// frame's goes back to the drive that asked for it, which draws the frame
/// again or throws. The one failure the renderer can answer, a pass that
/// outgrew memoryless attachments, turns every later pass to backed ones. Read
/// from the completed handlers, off the main actor, so its state is guarded by
/// a lock.
///
/// A frame whose command buffer was asked to keep each pass's outcome
/// (`MetalRenderer.makeCommandBuffer(reportingPasses:)`) also says which pass
/// failed, by the name the pass was given when it was made, so one failed frame
/// tells a scene's shadow map from its lit pass from a structure build.
final class GPUFailures: Sendable {
    private struct State: Sendable {
        var overflowed = false
        var said = Set<String>()
        var spent = false
        var spendings = 0
        var failed = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Whether any frame has overflowed memoryless attachments.
    var hasOverflowed: Bool { state.withLock { $0.overflowed } }

    /// Whether the command queue is spent: the system blamed one of its frames
    /// for a hang and reset the GPU, after which it refuses every later
    /// submission on that queue, or it is already refusing them. The live path
    /// replaces the queue before its next frame (`replaceSpentQueue`).
    var queueIsSpent: Bool { state.withLock { $0.spent } }

    /// How many times the queue was found spent, for the tests.
    var spendings: Int { state.withLock { $0.spendings } }

    /// Whether any frame has failed on this renderer. The live path reads it to
    /// decide whether its next frame keeps each pass's outcome: a healthy
    /// window asks for nothing, and one that has failed once names the pass
    /// the next time.
    var hasFailed: Bool { state.withLock { $0.failed } }

    /// Read a live frame's finished command buffer. Nothing happens unless it
    /// failed, or a test planted a hang on this frame, which is read as one.
    func check(_ buffer: MTLCommandBuffer, plantedHang: Bool = false) {
        if plantedHang {
            markSpent("a frame was read as a GPU hang, planted by a test")
            return
        }
        guard let sentence = failure(of: buffer) else { return }
        if GPUFailures.spendsQueue(buffer.error) { spend() }
        note(sentence)
    }

    /// Mark the queue spent and say why.
    func markSpent(_ sentence: String) {
        spend()
        note(sentence)
    }

    /// Forget that the queue was spent: a new one has taken its place.
    func clearSpent() { state.withLock { $0.spent = false } }

    private func spend() {
        state.withLock { $0.spent = true; $0.spendings += 1; $0.failed = true }
    }

    /// Whether a failure leaves the queue that carried it refused from here on.
    /// The system prints its own code beside its sentence, and two of them say
    /// so: 3, "Caused GPU Hang Error", the frame the GPU was reset for, after
    /// which every later submission on the same queue comes back as 4,
    /// "Ignored (for causing prior/excessive GPU errors)". A victim of another
    /// process's reset (5) and a frame cut short for the interface's sake keep
    /// their queue, which answers again at once. Matched by number, since the
    /// names the Swift enum gives these codes do not match the sentences.
    static func spendsQueue(_ error: Error?) -> Bool {
        guard let error = error as NSError?, error.domain == MTLCommandBufferErrorDomain else { return false }
        return error.code == 3 || error.code == 4
    }

    /// The sentence for a finished command buffer that failed, or nil when it
    /// ran. Says nothing itself; an overflow still turns later passes to
    /// backed attachments.
    func failure(of buffer: MTLCommandBuffer) -> String? {
        guard buffer.status == .error else { return nil }
        let (sentence, overflow) = GPUFailures.describe(buffer.error)
        state.withLock { $0.failed = true; if overflow { $0.overflowed = true } }
        return sentence
    }

    /// Write `sentence` to standard error the first time it comes up.
    func note(_ sentence: String) {
        let isNew = state.withLock { $0.said.insert(sentence).inserted }
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
        return ("a frame failed on the GPU and came back empty: \(error.localizedDescription)"
                + passReport(error), false)
    }

    /// What a failed command buffer says about its passes, as the tail of the
    /// failure's sentence, or nothing when it kept no record of them.
    ///
    /// Metal marks each pass of a reporting command buffer completed, pending,
    /// faulted, or affected. A faulted pass is the one the failure began in, so
    /// it is named alone. With none faulted, the affected ones were running
    /// when the GPU stopped and any of them may be the cause (the system makes
    /// the same hedge, since a fault in one process reaches passes in others),
    /// so they are listed as that. A pass is named by its label and by its
    /// place in the frame, which finds it even when nothing labeled it.
    static func passReport(_ error: NSError) -> String {
        guard let passes = error.userInfo[MTLCommandBufferEncoderInfoErrorKey]
                as? [any MTLCommandBufferEncoderInfo], !passes.isEmpty else { return "" }
        func name(_ index: Int) -> String {
            let label = passes[index].label
            return (label.isEmpty ? "an unnamed pass" : "\"\(label)\"")
                + " (\(index + 1) of \(passes.count))"
        }
        let faulted = passes.indices.filter { passes[$0].errorState == .faulted }
        if !faulted.isEmpty {
            return "; the pass that failed: " + faulted.map(name).joined(separator: ", ")
        }
        let completed = passes.filter { $0.errorState == .completed }.count
        let affected = passes.indices.filter { passes[$0].errorState == .affected }
        guard !affected.isEmpty else {
            return "; the GPU names no pass as the cause (\(completed) of \(passes.count) had finished)"
        }
        let shown = affected.prefix(passListLimit).map(name).joined(separator: ", ")
        let rest = affected.count - passListLimit
        return "; the GPU names no pass as the cause, and these were running: " + shown
            + (rest > 0 ? ", and \(rest) more" : "")
    }

    /// How many running passes a sentence lists before it counts the rest.
    static let passListLimit = 4

    /// The name a pass carries in a failure's sentence. A pass made without one
    /// takes the function that made it, which arrives as a whole signature; the
    /// name before its parenthesis says the same thing in a line a person reads.
    /// A name with a space before the parenthesis was written by hand
    /// ("canvas (headless)") and is kept whole.
    static func passName(_ caller: String) -> String {
        guard let open = caller.firstIndex(of: "("), open > caller.startIndex,
              caller[caller.index(before: open)] != " " else { return caller }
        return String(caller[..<open])
    }
}

// MARK: - Naming a frame's passes

extension MTLCommandBuffer {
    /// Whether this command buffer keeps each pass's outcome, which is when a
    /// pass is worth naming: the label is read only out of a failure.
    var reportsPasses: Bool { errorOptions.contains(.encoderExecutionStatus) }

    /// A compute pass, named after the function that made it when this command
    /// buffer reports its passes.
    func namedComputeEncoder(_ name: String = #function) -> MTLComputeCommandEncoder? {
        let encoder = makeComputeCommandEncoder()
        if reportsPasses { encoder?.label = GPUFailures.passName(name) }
        return encoder
    }

    /// A blit pass, named the same way.
    func namedBlitEncoder(_ name: String = #function) -> MTLBlitCommandEncoder? {
        let encoder = makeBlitCommandEncoder()
        if reportsPasses { encoder?.label = GPUFailures.passName(name) }
        return encoder
    }

    /// A pass that builds acceleration structures, named the same way.
    func namedStructureEncoder(_ name: String = #function) -> MTLAccelerationStructureCommandEncoder? {
        let encoder = makeAccelerationStructureCommandEncoder()
        if reportsPasses { encoder?.label = GPUFailures.passName(name) }
        return encoder
    }

    /// A render pass made outside the counted helper, named the same way.
    func namedRenderEncoder(descriptor: MTLRenderPassDescriptor,
                            _ name: String = #function) -> MTLRenderCommandEncoder? {
        let encoder = makeRenderCommandEncoder(descriptor: descriptor)
        if reportsPasses { encoder?.label = GPUFailures.passName(name) }
        return encoder
    }
}
