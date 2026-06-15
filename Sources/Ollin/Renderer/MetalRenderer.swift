import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics
import COllinShaders   // OllinVertex / Uniforms / SDFInstance, shared with Shaders.metal

/// The Metal back end. Deliberately small: one command queue, an enum-keyed
/// cache of render pipelines (keyed by shader pair × blend mode — solid
/// triangles, SDF quads, image quads, glyph quads), and a reusable vertex buffer.
///
/// You'll be editing this as you add primitives. The shape of the thing:
///
///   1. `Drawer` tessellates every primitive this frame into one flat
///      `[OllinVertex]` array (triangles, in sketch-space points).
///   2. `render(...)` uploads that array into `vertexBuffer`, clears to the
///      background color, and issues a single `drawPrimitives(.triangle)`.
///   3. `Shaders.metal` maps points -> clip space and outputs the vertex color.
///
/// To add a new primitive you usually only touch `Drawer` (more triangles).
/// You only touch this file when you need a *new pipeline* (e.g. instanced or
/// SDF circles, textured quads for images, a new blend mode): add a `Pipeline`
/// case and a branch in `makePipeline(_:)` — don't grow `init`.
///
/// Main-actor isolated: it's created and driven from the main thread (the
/// `MTKViewDelegate` draw callback and the headless export path). The only work
/// that intentionally runs off-actor is the GPU completed-handler, which signals
/// `frameBoundary` (a `Sendable` semaphore) and touches nothing else.
@MainActor
final class MetalRenderer {

    enum RendererError: Error {
        case commandQueue
        case shaderLibrary
        case shaderFunctions
    }

    /// Identifies a render pipeline so it's built once and cached in
    /// `pipelines`. A pipeline is a *combination* of a shader pair, blend mode,
    /// alpha convention, and (for 3D) a depth-attachment format — captured as a
    /// value here rather than one enum case per combination, so a new capability
    /// adds a factory or a field, not a case. The depth axis is the reason this
    /// is a descriptor struct and not an enum (see CLAUDE.md): a pipeline used in
    /// a depth-tested pass must declare its depth format, so it's part of the key.
    /// The `.normal`, no-depth variants are built up front; other combinations (a
    /// combining blend mode, a depth-tested 3D pass) build lazily on first use.
    private struct PipelineKey: Hashable {
        var vertex: String
        var fragment: String
        var blend: BlendMode = .normal
        /// Premultiplied color (the image path) vs straight-alpha (solid/SDF/glyph/points).
        var premultiplied = false
        /// nil for the 2D color-only pass; a depth format when the pass carries a
        /// depth attachment (an active 3D camera). Part of the key because the
        /// descriptor must declare it to be valid in that pass.
        var depthFormat: MTLPixelFormat? = nil
        /// The final tone-map pass is single-sample and targets the display
        /// format, unlike every geometry pipeline; this flag keeps it in the same
        /// cache (so live shader reload rebuilds it too).
        var isPresent = false

        // tessellated triangles (rects, lines, polygons, arcs)
        static func solid(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_vertex", fragment: "ollin_fragment", blend: blend, depthFormat: depth)
        }
        // instanced SDF quads (circles, ellipses, rects, lines, arcs)
        static func sdf(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_sdf_vertex", fragment: "ollin_sdf_fragment", blend: blend, depthFormat: depth)
        }
        // textured quads (images); the texture keeps the CGImage's premultiplied alpha
        static func image(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_image_vertex", fragment: "ollin_image_fragment",
                        blend: blend, premultiplied: true, depthFormat: depth)
        }
        // SDF-atlas text quads, straight-alpha coverage
        static func glyphAtlas(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_image_vertex", fragment: "ollin_glyph_fragment", blend: blend, depthFormat: depth)
        }
        // instanced GPU-particle discs (compute-resident buffer)
        static func points(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_particle_vertex", fragment: "ollin_particle_fragment", blend: blend, depthFormat: depth)
        }
        // instanced 3D point-cloud splats (camera-facing discs, depth-tested)
        static func pointCloud(_ blend: BlendMode, depth: MTLPixelFormat? = nil) -> PipelineKey {
            PipelineKey(vertex: "ollin_point_vertex", fragment: "ollin_point_fragment", blend: blend, depthFormat: depth)
        }
        // final fullscreen tone-map pass, float -> sRGB drawable
        static let present = PipelineKey(vertex: "ollin_present_vertex",
                                         fragment: "ollin_present_fragment", isPresent: true)

        /// The pipeline a recorded batch needs, from its geometry kind, blend, and
        /// the active depth format (nil in 2D).
        static func forBatch(_ kind: GeometryKind, _ blend: BlendMode,
                             depth: MTLPixelFormat? = nil) -> PipelineKey {
            switch kind {
            case .triangles:  return .solid(blend, depth: depth)
            case .sdf:        return .sdf(blend, depth: depth)
            case .image:      return .image(blend, depth: depth)
            case .glyphAtlas: return .glyphAtlas(blend, depth: depth)
            case .particles:  return .points(blend, depth: depth)
            case .points3D:   return .pointCloud(blend, depth: depth)
            }
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library: MTLLibrary
    /// The display/drawable format — sRGB 8-bit. The final present pass writes
    /// here; it's never a geometry render target anymore.
    private let pixelFormat: MTLPixelFormat
    /// The compositing substrate: a linear `rgba16Float` intermediate every
    /// geometry pipeline renders into, so values can exceed 1.0 (additive light)
    /// and many translucent blends don't band the way an 8-bit target would. The
    /// present pass tone-maps + encodes it down to `pixelFormat`.
    private let linearFormat: MTLPixelFormat = .rgba16Float
    /// MSAA sample count for the float geometry targets (the drawable itself is
    /// single-sample — MSAA happens in the intermediate, then resolves before the
    /// present pass tone-maps).
    private let sampleCount: Int
    /// Depth format for 3D passes (an active `Camera3D`). 2D passes carry no depth
    /// attachment, so a 2D sketch allocates none of this.
    private let depthPixelFormat: MTLPixelFormat = .depth32Float

    /// Render pipelines, built on first use and reused. Keyed by `Pipeline` so
    /// a new capability is a new case + a branch in `makePipeline(_:)`, never
    /// more inline construction in `init` (see CLAUDE.md).
    private var pipelines: [PipelineKey: MTLRenderPipelineState] = [:]

    /// Compute kernels are open-ended (one per user source), so they can't be a
    /// fixed enum like the render pipelines. They're cached separately, keyed by a
    /// hash of the composed source + the entry name. The composed *library* is
    /// cached per source too, so several entries in one source share one compile.
    private struct ComputeKey: Hashable { let sourceHash: UInt64; let entry: String }
    private var computePipelines: [ComputeKey: MTLComputePipelineState] = [:]
    private var computeLibraries: [UInt64: MTLLibrary] = [:]

    /// Triple-buffered vertex storage, gated by a semaphore so the CPU never
    /// overwrites vertices the GPU is still reading. Writing one shared buffer
    /// every frame with no synchronization tears the on-screen geometry (e.g.
    /// gaps in a stroked ring) because the next frame stomps it mid-draw. Each
    /// slot is grown on demand to keep steady-state frames allocation-free.
    private static let maxFramesInFlight = 3
    private let frameBoundary = DispatchSemaphore(value: MetalRenderer.maxFramesInFlight)
    private var vertexBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    /// Parallel ring for SDF instance data, advanced with `frameIndex` alongside
    /// `vertexBuffers` (one semaphore gates both — they're written and read
    /// together each frame).
    private var sdfBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var frameIndex = 0

    /// A separate vertex buffer for off-screen `image(of:)` renders, so headless
    /// export never shares a slot with the on-screen ring. Export is synchronous
    /// (it waits for the GPU before reading back), so one reusable buffer is
    /// enough — no ring needed — but it must not be a ring slot the live loop
    /// could still be reading for an in-flight frame.
    private var exportBuffer: MTLBuffer?
    private var sdfExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for textured-quad (image) vertices, advanced
    /// with `frameIndex` like the others.
    private var imageBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var imageExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for SDF-atlas text quads (also
    /// `OllinImageVertex`), advanced with `frameIndex` like the others.
    private var glyphBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var glyphExportBuffer: MTLBuffer?

    /// Parallel ring + export buffer for 3D point-cloud splats (`OllinPoint`),
    /// advanced with `frameIndex` like the others.
    private var pointBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var pointExportBuffer: MTLBuffer?

    /// Depth-stencil states for the 3D path, built once. 3D geometry z-tests
    /// (less-equal) and writes depth; 2D batches in a 3D pass leave depth alone
    /// (always-pass, no write) so they composite over in draw order.
    private lazy var depthTestState: MTLDepthStencilState? = {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .lessEqual
        d.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: d)
    }()
    private lazy var noDepthState: MTLDepthStencilState? = {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .always
        d.isDepthWriteEnabled = false
        return device.makeDepthStencilState(descriptor: d)
    }()

    /// The on-screen geometry targets: this frame's geometry composites into a
    /// linear-float MSAA target (`mainMSAA`, `.memoryless` — it lives only in tile
    /// memory since the frame clears each time and the samples aren't needed after
    /// the resolve), resolves into a single-sample float texture (`mainResolve`),
    /// and the present pass then tone-maps that into the drawable. Reused across
    /// frames; rebuilt on a size change.
    private var mainMSAA: MTLTexture?
    private var mainResolve: MTLTexture?
    private var mainSize = (width: 0, height: 0)

    /// The depth target for the live 3D path, paired with `mainMSAA` (same size +
    /// sample count). Allocated lazily only when a 3D camera is active — a 2D
    /// sketch never makes one. Memoryless: depth lives only in tile memory.
    private var mainDepth: MTLTexture?

    /// Off-screen targets for the GPU-texture frame hook (`texture(of:)`), kept and
    /// reused across frames — rebuilt only when the canvas size changes, so live
    /// frame-sharing (Syphon) doesn't allocate a texture every frame. Geometry
    /// composites into the float MSAA target (`textureTargetMSAA`, `.memoryless`),
    /// resolves into `textureFloatResolve`, and the present pass tone-maps that into
    /// `textureResolve` — the single-sample sRGB texture handed out (`.shaderRead`
    /// so a consumer can sample/copy it, `.pixelFormatView` for Syphon's byte-pass).
    private var textureTargetMSAA: MTLTexture?
    private var textureFloatResolve: MTLTexture?
    private var textureResolve: MTLTexture?
    private var textureTargetSize = (width: 0, height: 0)

    /// The persistent accumulation surface (`Drawer.accumulates` / `noClear`): a
    /// render target the frame *doesn't* clear, so additive samples pile up across
    /// frames. `accumTarget` is an MSAA target kept private (so its samples persist
    /// — never `.memoryless`); each frame loads it, draws this frame's geometry,
    /// and resolves into `accumResolve` (single-sample, `.shaderRead`+blit) for
    /// presentation and read-back. Kept at the active draw size and reset (the next
    /// frame clears) when the size changes or the sketch calls `background(_:)`.
    /// Reusing the same MSAA target keeps the existing pipelines (no new sample-count
    /// variant) and preserves edge anti-aliasing while accumulating. The targets are
    /// linear-float, so faint additive samples (below 1/255) sum correctly instead of
    /// quantizing away — the precision the light-accumulation look needs. `accumResolve`
    /// holds the raw linear pile; presentation/read-back tone-maps it through
    /// `accumDisplay` (a single-sample sRGB texture) so a consumer gets display-ready
    /// bytes, never the raw HDR float.
    private var accumTarget: MTLTexture?
    private var accumResolve: MTLTexture?
    private var accumDisplay: MTLTexture?
    private var accumSize = (width: 0, height: 0)
    private var accumNeedsClear = true

    /// Sampler for the image pipeline: linear filtering, clamp to edge. Built once.
    /// Also samples the gradient strip (the same filtering is exactly what a LUT
    /// row wants).
    private let imageSampler: MTLSamplerState?

    /// The gradient strip: one row per distinct gradient ramp this frame, baked
    /// on the CPU (see `BakedGradient`) and sampled by the SDF fragment. Reused
    /// while the frame's rows are unchanged (the common case — a steady sketch
    /// uploads nothing); a *new* texture is made when they change, because the
    /// old one may still be read by an in-flight frame (the command buffer
    /// retains it until completion, so swapping the reference is safe where
    /// rewriting the contents is not).
    private var gradientStrip: MTLTexture?
    private var gradientStripRows: [[UInt8]] = []

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, sampleCount: Int) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.sampleCount = sampleCount

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueue
        }
        self.commandQueue = queue

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.imageSampler = device.makeSamplerState(descriptor: samplerDesc)

        self.library = try MetalRenderer.loadLibrary(device: device)

        // Build the pipelines we know we need now; `pipeline(_:)` builds any
        // added later on first use. Building here surfaces shader errors at
        // startup rather than mid-frame.
        _ = try pipeline(.solid(.normal))
        _ = try pipeline(.sdf(.normal))
        _ = try pipeline(.image(.normal))
        _ = try pipeline(.glyphAtlas(.normal))
        _ = try pipeline(.present)
    }

    /// Encode and present one frame's worth of recorded geometry: composite into
    /// the linear-float intermediate, then run the present pass to tone-map it into
    /// the drawable.
    func render(_ drawer: Drawer, viewport: SIMD2<Float>, in view: MTKView) {
        if drawer.accumulates {
            renderAccumulating(drawer, viewport: viewport, in: view)
            return
        }
        let width = Int(view.drawableSize.width.rounded())
        let height = Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0, let drawable = view.currentDrawable else { return }

        // (Re)allocate the cached float geometry targets on a size change. The MSAA
        // target is memoryless (tile-only); the resolve is sampled by the present pass.
        if mainSize != (width, height) || mainMSAA == nil || mainResolve == nil {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
                  let resolve = makeFloatResolve(width: width, height: height) else { return }
            mainMSAA = msaa; mainResolve = resolve; mainSize = (width, height)
        }
        guard let msaa = mainMSAA, let resolve = mainResolve else { return }

        // Block until a vertex-buffer slot frees up, then advance to the next one
        // in the ring — so this frame's upload can't stomp a buffer the GPU is
        // still reading for an in-flight frame.
        frameBoundary.wait()
        frameIndex = (frameIndex + 1) % MetalRenderer.maxFramesInFlight

        let geomPass = MTLRenderPassDescriptor()
        geomPass.colorAttachments[0].texture = msaa
        geomPass.colorAttachments[0].resolveTexture = resolve
        geomPass.colorAttachments[0].loadAction = .clear
        geomPass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        geomPass.colorAttachments[0].storeAction = .multisampleResolve

        // A 3D camera adds a depth attachment, paired to mainMSAA (allocated lazily;
        // a 2D sketch never allocates one). Memoryless, cleared to the far plane.
        var passDepthFormat: MTLPixelFormat? = nil
        if drawer.camera3D != nil {
            if mainDepth?.width != width || mainDepth?.height != height {
                mainDepth = makeDepthMSAA(width: width, height: height)
            }
            if let depth = mainDepth {
                geomPass.depthAttachment.texture = depth
                geomPass.depthAttachment.loadAction = .clear
                geomPass.depthAttachment.clearDepth = 1.0
                geomPass.depthAttachment.storeAction = .dontCare
                passDepthFormat = depthPixelFormat
            }
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameBoundary.signal()   // nothing encoded; hand the slot back
            return
        }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let geomEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: geomPass) else {
            frameBoundary.signal()   // nothing encoded; hand the slot back
            return
        }
        commandBuffer.addCompletedHandler { [frameBoundary] _ in frameBoundary.signal() }

        encode(drawer, viewport: viewport, into: geomEncoder,
               triangleBuffer: vertexBuffer(at: frameIndex, for: drawer.vertices.count),
               sdfBuffer: sdfBuffer(at: frameIndex, for: drawer.sdfInstances.count),
               imageBuffer: imageBuffer(at: frameIndex, for: drawer.imageVertices.count),
               glyphBuffer: glyphBuffer(at: frameIndex, for: drawer.glyphVertices.count),
               pointBuffer: pointBuffer(at: frameIndex, for: drawer.points.count),
               depthFormat: passDepthFormat)
        geomEncoder.endEncoding()

        if let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: drawable.texture)) {
            encodePresent(from: resolve, drawer: drawer, into: presentEncoder)
            presentEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Accumulation surface (noClear)

    /// Live accumulation path: render this frame's geometry onto the persistent
    /// accumulation surface — loading the prior pile unless this frame resets — then
    /// blit the resolved canvas to the drawable to present it. Reuses the
    /// triple-buffer vertex ring and its semaphore exactly like `render`, so the
    /// upload still can't stomp a buffer an in-flight frame is reading.
    private func renderAccumulating(_ drawer: Drawer, viewport: SIMD2<Float>, in view: MTKView) {
        let width = Int(view.drawableSize.width.rounded())
        let height = Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0, let drawable = view.currentDrawable else { return }

        frameBoundary.wait()
        frameIndex = (frameIndex + 1) % MetalRenderer.maxFramesInFlight

        guard let pass = accumulationPass(drawer, width: width, height: height),
              let resolve = accumResolve,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameBoundary.signal()      // nothing encoded; hand the slot back
            return
        }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            frameBoundary.signal()      // nothing encoded; hand the slot back
            return
        }
        commandBuffer.addCompletedHandler { [frameBoundary] _ in frameBoundary.signal() }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: vertexBuffer(at: frameIndex, for: drawer.vertices.count),
               sdfBuffer: sdfBuffer(at: frameIndex, for: drawer.sdfInstances.count),
               imageBuffer: imageBuffer(at: frameIndex, for: drawer.imageVertices.count),
               glyphBuffer: glyphBuffer(at: frameIndex, for: drawer.glyphVertices.count),
               pointBuffer: pointBuffer(at: frameIndex, for: drawer.points.count),
               depthFormat: nil)   // 3D + accumulation isn't supported in M1
        encoder.endEncoding()

        // Present: tone-map the resolved float pile into the drawable. (The pile
        // itself stays in linear float, so faint samples keep summing next frame.)
        if let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: drawable.texture)) {
            encodePresent(from: resolve, drawer: drawer, into: presentEncoder)
            presentEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Headless accumulation: render this frame's geometry onto the persistent
    /// accumulation surface (load/clear per the drawer) and read the resolved
    /// canvas back as a `CGImage`. The off-screen companion to
    /// `renderAccumulating`, used by the export drivers (still / sequence / video /
    /// GIF) — call it once per frame in order and the pile builds across the run.
    /// Synchronous: waits for the GPU before reading back.
    func accumulatedImage(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0,
              let pass = accumulationPass(drawer, width: width, height: height),
              let resolve = accumResolve, let display = accumDisplay,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
               sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count),
               imageBuffer: exportImageBuffer(for: drawer.imageVertices.count),
               glyphBuffer: exportGlyphBuffer(for: drawer.glyphVertices.count),
               pointBuffer: exportPointBuffer(for: drawer.points.count),
               depthFormat: nil)   // 3D + accumulation isn't supported in M1
        encoder.endEncoding()

        // Tone-map the float pile into the sRGB display texture, then read that back.
        if let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: display)) {
            encodePresent(from: resolve, drawer: drawer, into: presentEncoder)
            presentEncoder.endEncoding()
        }

        let bytesPerRow = width * 4, byteCount = bytesPerRow * height
        guard let readbackBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: display, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readbackBuffer, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return MetalRenderer.cgImage(fromBGRA8: readbackBuffer, width: width, height: height)
    }

    /// Read the current accumulated canvas back as a `CGImage` without re-rendering
    /// the geometry — for the live frame-grab hook (a recorder/Syphon consumer)
    /// while accumulating, since the on-screen pile is exactly what it wants. Runs
    /// the tone-map present pass over the existing float pile first (it can't hand
    /// back the raw HDR float). Nil before the first accumulating frame.
    func accumulatedFrameImage(_ drawer: Drawer) -> CGImage? {
        guard let display = accumulatedDisplayTexture(drawer) else { return nil }
        return readback(display, width: accumSize.width, height: accumSize.height)
    }

    /// The current accumulated canvas as a tone-mapped sRGB texture, for the
    /// GPU-texture frame hook while accumulating — handed straight to a consumer
    /// that stays on the GPU. Nil before the first accumulating frame.
    func accumulatedTexture(_ drawer: Drawer) -> MTLTexture? {
        accumulatedDisplayTexture(drawer)
    }

    /// Tone-map the existing float accumulation pile into `accumDisplay` (no
    /// geometry re-render) and return it. Synchronous: waits for the GPU so the
    /// display texture is complete on return.
    private func accumulatedDisplayTexture(_ drawer: Drawer) -> MTLTexture? {
        guard let resolve = accumResolve, let display = accumDisplay,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: display)) else {
            return nil
        }
        encodePresent(from: resolve, drawer: drawer, into: presentEncoder)
        presentEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return display
    }

    /// Wipe the accumulated canvas on the next accumulating frame — for a live
    /// reload, so a freshly swapped-in sketch starts from a clean surface rather
    /// than inheriting the previous sketch's pile (the fresh-restart reload model).
    func resetAccumulation() { accumNeedsClear = true }

    /// Build the render pass for one accumulation frame, (re)allocating the
    /// persistent target on a size change and choosing load vs clear. The frame
    /// clears (to the background color) only when the target was just (re)allocated
    /// or the sketch called `background(_:)` this frame; otherwise it loads the
    /// accumulated pile. Always resolves to `accumResolve` and stores the samples
    /// back so they persist to the next frame.
    private func accumulationPass(_ drawer: Drawer, width: Int, height: Int) -> MTLRenderPassDescriptor? {
        if accumSize != (width, height) || accumTarget == nil || accumResolve == nil {
            // The MSAA target is `.private` (never memoryless) so its samples
            // persist across frames; both it and the resolve are linear float so
            // faint additive samples accumulate without quantizing away.
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .private),
                  let resolve = makeFloatResolve(width: width, height: height),
                  let display = makeDisplayTexture(width: width, height: height) else { return nil }
            accumTarget = msaa
            accumResolve = resolve
            accumDisplay = display         // tone-mapped output for hand-off / read-back
            accumSize = (width, height)
            accumNeedsClear = true         // fresh memory: clear before the first load
        }
        guard let msaa = accumTarget, let resolve = accumResolve else { return nil }

        let reset = accumNeedsClear || drawer.backgroundSetThisFrame
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = resolve
        pass.colorAttachments[0].loadAction = reset ? .clear : .load
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .storeAndMultisampleResolve
        accumNeedsClear = false
        return pass
    }

    /// Blit `texture` into a CPU-readable buffer and build a `CGImage`. A
    /// standalone command buffer (commits + waits) for reading a texture an earlier
    /// command buffer already produced (the live accumulation grab).
    private func readback(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4, byteCount = bytesPerRow * height
        guard let buffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return MetalRenderer.cgImage(fromBGRA8: buffer, width: width, height: height)
    }

    /// Build an opaque BGRA8 `CGImage` from a shared buffer of `width*height*4`
    /// bytes (the resolved-texture read-back layout). Shared by `image(of:)` and
    /// the accumulation read-back paths.
    private static func cgImage(fromBGRA8 buffer: MTLBuffer, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4, byteCount = bytesPerRow * height
        let data = Data(bytes: buffer.contents(), count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Render `drawer`'s geometry off-screen to a `CGImage` of `width`×`height`
    /// pixels — same pipeline, MSAA, and blending as on-screen — for frame export
    /// (PNG, and later PNG sequences for video). Headless: needs no view or
    /// window. Synchronous: waits for the GPU before reading back.
    func image(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        // Float MSAA target + float resolve for the geometry, plus an sRGB display
        // texture the present pass tone-maps into and we read back.
        guard let msaaTexture = makeFloatMSAA(width: width, height: height, storage: .memoryless),
              let resolveTexture = makeFloatResolve(width: width, height: height),
              let displayTexture = makeDisplayTexture(width: width, height: height) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaTexture
        pass.colorAttachments[0].resolveTexture = resolveTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve

        // A 3D camera adds a (freshly allocated, memoryless) depth attachment so the
        // headless/snapshot path z-tests exactly like the live window.
        var passDepthFormat: MTLPixelFormat? = nil
        if drawer.camera3D != nil, let depth = makeDepthMSAA(width: width, height: height) {
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .dontCare
            passDepthFormat = depthPixelFormat
        }

        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height

        guard let readback = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
               sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count),
               imageBuffer: exportImageBuffer(for: drawer.imageVertices.count),
               glyphBuffer: exportGlyphBuffer(for: drawer.glyphVertices.count),
               pointBuffer: exportPointBuffer(for: drawer.points.count),
               depthFormat: passDepthFormat)
        encoder.endEncoding()

        // Tone-map the resolved float frame into the sRGB display texture.
        guard let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: displayTexture)) else { return nil }
        encodePresent(from: resolveTexture, drawer: drawer, into: presentEncoder)
        presentEncoder.endEncoding()

        // Copy the display texture into a CPU-readable buffer (works on every
        // Mac GPU, unlike texture.getBytes on discrete cards).
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: displayTexture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // BGRA8 bytes -> CGImage. Frames are opaque, so skip the alpha channel.
        return MetalRenderer.cgImage(fromBGRA8: readback, width: width, height: height)
    }

    /// Render `drawer`'s geometry off-screen and return the resolved color texture
    /// (single-sample, sRGB, `.shaderRead`) — same pipeline, MSAA, and blending as
    /// on-screen and as `image(of:)`, but **without** the CPU read-back. The
    /// GPU-only companion to `image(of:)`, for handing the live frame to a consumer
    /// that stays on the GPU (Syphon publishing; later the effects graph).
    ///
    /// The returned texture is reused on the next call (the target is cached and
    /// only rebuilt on a size change), so a consumer must *copy* from it during the
    /// call, not retain it across frames. Synchronous: waits for the GPU so the
    /// texture is complete on return.
    func texture(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }

        if textureTargetSize != (width, height) || textureTargetMSAA == nil
            || textureFloatResolve == nil || textureResolve == nil {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: .memoryless),
                  let floatResolve = makeFloatResolve(width: width, height: height),
                  let display = makeDisplayTexture(width: width, height: height) else { return nil }
            textureTargetMSAA = msaa
            textureFloatResolve = floatResolve
            textureResolve = display
            textureTargetSize = (width, height)
        }
        guard let msaaTexture = textureTargetMSAA,
              let floatResolve = textureFloatResolve,
              let displayTexture = textureResolve else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaTexture
        pass.colorAttachments[0].resolveTexture = floatResolve
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        encodeCompute(drawer, into: commandBuffer)   // sim steps before the render pass
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
               sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count),
               imageBuffer: exportImageBuffer(for: drawer.imageVertices.count),
               glyphBuffer: exportGlyphBuffer(for: drawer.glyphVertices.count),
               pointBuffer: exportPointBuffer(for: drawer.points.count),
               depthFormat: nil)   // 3D over the texture/Syphon hand-off isn't supported in M1
        encoder.endEncoding()

        // Tone-map the resolved float frame into the sRGB display texture handed out.
        guard let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass(into: displayTexture)) else { return nil }
        encodePresent(from: floatResolve, drawer: drawer, into: presentEncoder)
        presentEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return displayTexture
    }

    /// Upload `drawer`'s recorded geometry and issue its draws into `encoder`,
    /// one per batch in call order so triangles and SDF shapes composite
    /// front-to-back as the sketch drew them. Shared by the on-screen and
    /// off-screen (export) paths.
    private func encode(_ drawer: Drawer, viewport: SIMD2<Float>,
                        into encoder: MTLRenderCommandEncoder,
                        triangleBuffer: MTLBuffer?, sdfBuffer: MTLBuffer?,
                        imageBuffer: MTLBuffer?, glyphBuffer: MTLBuffer?,
                        pointBuffer: MTLBuffer?, depthFormat: MTLPixelFormat?) {
        let vertices = drawer.vertices
        let instances = drawer.sdfInstances
        let imageVertices = drawer.imageVertices
        let glyphVertices = drawer.glyphVertices
        let points = drawer.points
        let batches = drawer.batches
        guard !batches.isEmpty else { return }

        if !vertices.isEmpty, let triangleBuffer {
            vertices.withUnsafeBytes { raw in
                triangleBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !instances.isEmpty, let sdfBuffer {
            instances.withUnsafeBytes { raw in
                sdfBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !imageVertices.isEmpty, let imageBuffer {
            imageVertices.withUnsafeBytes { raw in
                imageBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !glyphVertices.isEmpty, let glyphBuffer {
            glyphVertices.withUnsafeBytes { raw in
                glyphBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !points.isEmpty, let pointBuffer {
            points.withUnsafeBytes { raw in
                pointBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }

        var uniforms = Uniforms(viewport: viewport)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // 3D camera constants for the points3D batches, bound once at index 2 —
        // distinct from the 2D Uniforms at index 1, so the 2D batches around a 3D
        // one are undisturbed. Built from the camera and the viewport's aspect.
        if let camera = drawer.camera3D {
            let aspect = viewport.y > 0 ? Double(viewport.x / viewport.y) : 1
            var u3 = Uniforms3D(view: camera.viewMatrix,
                                projection: camera.projectionMatrix(aspect: aspect),
                                viewport: viewport)
            encoder.setVertexBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        }

        // The strip must be bound whenever the SDF fragment runs (it references
        // the texture even for all-solid frames), so resolve it once per encode.
        let strip = gradientStripTexture(for: drawer.gradientRows)

        let vertexStride = MemoryLayout<OllinVertex>.stride
        let instanceStride = MemoryLayout<SDFInstance>.stride
        let imageStride = MemoryLayout<OllinImageVertex>.stride
        let pointStride = MemoryLayout<OllinPoint>.stride
        for i in batches.indices {
            let batch = batches[i]
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            // The pipeline for this batch's geometry kind, blend mode, *and* the
            // pass's depth format; built on first use of a combination. Skip the
            // batch if it can't be built (never expected — same shaders).
            guard let state = try? pipeline(.forBatch(batch.kind, batch.blendMode, depth: depthFormat)) else { continue }
            // In a depth pass (active camera): 3D batches z-test + write depth, 2D
            // batches around them leave depth alone so they composite over in draw
            // order. With no depth attachment the encoder keeps its default state,
            // so 2D-only frames are byte-identical to before.
            if depthFormat != nil {
                encoder.setDepthStencilState(batch.kind == .points3D ? depthTestState : noDepthState)
            }
            switch batch.kind {
            case .triangles:
                let end = next?.vertexStart ?? vertices.count
                let count = end - batch.vertexStart
                guard count > 0, let triangleBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(triangleBuffer, offset: batch.vertexStart * vertexStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .sdf:
                let end = next?.instanceStart ?? instances.count
                let count = end - batch.instanceStart
                guard count > 0, let sdfBuffer else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(sdfBuffer, offset: batch.instanceStart * instanceStride, index: 0)
                // Rebind per batch — an image/glyph batch in between binds its own
                // texture at the same index.
                encoder.setFragmentTexture(strip, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            case .image:
                let end = next?.imageStart ?? imageVertices.count
                let count = end - batch.imageStart
                guard count > 0, let imageBuffer, let source = batch.image,
                      let texture = source.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(imageBuffer, offset: batch.imageStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .glyphAtlas:
                let end = next?.glyphStart ?? glyphVertices.count
                let count = end - batch.glyphStart
                guard count > 0, let glyphBuffer, let atlas = batch.atlas,
                      let texture = atlas.texture(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(glyphBuffer, offset: batch.glyphStart * imageStride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(imageSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .particles:
                // GPU-resident particle buffer (written by a compute dispatch this
                // frame), drawn as one instanced disc per particle. Uniforms are
                // already bound at index 1; the particle struct is read at index 0.
                guard batch.particleCount > 0,
                      let buffer = batch.particleBuffer?.metalBuffer(for: device) else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                       instanceCount: batch.particleCount)
            case .points3D:
                // 3D point-cloud splats: one instanced camera-facing quad per point,
                // projected by the camera constants bound at index 2 above. Each draw
                // is a run in the per-frame `points` array (count from the next
                // batch's start), like the SDF/triangle paths.
                let end = next?.pointStart ?? points.count
                let count = end - batch.pointStart
                guard count > 0, let pointBuffer, drawer.camera3D != nil else { continue }
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(pointBuffer, offset: batch.pointStart * pointStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            }
        }
    }

    /// Encode the frame's recorded compute dispatches into one compute encoder,
    /// ahead of the geometry render pass in the *same* command buffer — so a
    /// simulation step and the draw that reads its output stay ordered within the
    /// frame (Metal's intra-command-buffer hazard tracking inserts the dependency).
    /// The standard `OllinComputeUniforms` are bound at index 10 (with this
    /// dispatch's thread count as `particleCount`) and the custom params, if any, at
    /// index 11; the kernel's own buffers bind at 0…9. Threadgroup size comes from
    /// the pipeline, dispatched non-uniformly so the count needn't be a multiple.
    private func encodeCompute(_ drawer: Drawer, into commandBuffer: MTLCommandBuffer) {
        guard !drawer.dispatches.isEmpty,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        for dispatch in drawer.dispatches {
            guard dispatch.threadCount > 0,
                  let state = try? computePipeline(for: dispatch.kernel) else { continue }
            encoder.setComputePipelineState(state)
            for (index, bindable) in dispatch.buffers.enumerated() {
                encoder.setBuffer(bindable?.metalBuffer(for: device), offset: 0, index: index)
            }
            for (index, bindable) in dispatch.textures.enumerated() {
                encoder.setTexture(bindable?.metalTexture(for: device), index: index)
            }
            var uniforms = drawer.computeUniforms
            uniforms.particleCount = UInt32(dispatch.threadCount)
            encoder.setBytes(&uniforms, length: MemoryLayout<OllinComputeUniforms>.stride, index: 10)
            if !dispatch.params.isEmpty {
                dispatch.params.withUnsafeBytes {
                    encoder.setBytes($0.baseAddress!, length: $0.count, index: 11)
                }
            }
            // Threadgroup shaped to the grid: the execution width along x, the rest
            // of the budget along y. A 1-D buffer dispatch (height 1) collapses to
            // the old `width × 1`; a 2-D texture dispatch tiles in both axes.
            // `dispatchThreads` handles a grid that isn't a multiple of the group.
            let tew = state.threadExecutionWidth
            let groupWidth = max(1, min(dispatch.gridWidth, tew))
            let groupHeight = max(1, min(dispatch.gridHeight, state.maxTotalThreadsPerThreadgroup / tew))
            encoder.dispatchThreads(
                MTLSize(width: dispatch.gridWidth, height: dispatch.gridHeight, depth: 1),
                threadsPerThreadgroup: MTLSize(width: groupWidth, height: groupHeight, depth: 1))
        }
        encoder.endEncoding()
    }

    /// Execute this frame's recorded compute dispatches *without* rendering geometry —
    /// for headless drivers advancing a stateful sim (a `Simulation`, a ping-pong
    /// `ComputeTexture`) through frames they don't capture: the frames before the one
    /// being grabbed, and `--skip` warmup. The live window and a captured frame run
    /// the steps as part of their full render, but an *un*-captured frame otherwise
    /// records its dispatches and drops them, so the sim never evolves on the GPU.
    /// This runs just the compute, in its own command buffer (no geometry pass, no
    /// readback), so the GPU-resident state carries forward to the next frame at a
    /// fraction of a full render's cost. A no-op when nothing was recorded.
    func stepCompute(_ drawer: Drawer) {
        guard !drawer.dispatches.isEmpty,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        encodeCompute(drawer, into: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// The gradient strip texture holding `rows` (one baked ramp per row),
    /// reused while the rows are unchanged and rebuilt — as a fresh texture, see
    /// `gradientStrip` — when they differ. With no gradients in the frame a
    /// 1-row placeholder keeps the SDF fragment's texture argument valid.
    private func gradientStripTexture(for rows: [[UInt8]]) -> MTLTexture? {
        if let existing = gradientStrip, rows == gradientStripRows { return existing }

        let height = max(rows.count, 1)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb, width: BakedGradient.width,
            height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = BakedGradient.width * 4
        var flat: [UInt8] = []
        flat.reserveCapacity(bytesPerRow * height)
        for row in rows { flat.append(contentsOf: row) }
        if rows.isEmpty { flat = [UInt8](repeating: 0, count: bytesPerRow) }
        flat.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, BakedGradient.width, height),
                            mipmapLevel: 0, withBytes: raw.baseAddress!,
                            bytesPerRow: bytesPerRow)
        }
        gradientStrip = texture
        gradientStripRows = rows
        return texture
    }

    // MARK: Render targets

    /// A linear-float MSAA color target. `storageMode` is `.memoryless` for the
    /// transient per-frame targets (the samples live only in tile memory, never
    /// backed by DRAM, since the frame clears each time) and `.private` for the
    /// accumulation target (its samples must persist across frames).
    private func makeFloatMSAA(width: Int, height: Int, storage: MTLStorageMode) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = .renderTarget
        desc.storageMode = storage
        return device.makeTexture(descriptor: desc)
    }

    /// A multisample depth target for a 3D pass, matching the geometry MSAA target's
    /// size and sample count. Memoryless — depth is consumed within the pass
    /// (storeAction `.dontCare`), never backed by DRAM.
    private func makeDepthMSAA(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        desc.textureType = .type2DMultisample
        desc.sampleCount = sampleCount
        desc.usage = .renderTarget
        desc.storageMode = .memoryless
        return device.makeTexture(descriptor: desc)
    }

    /// The single-sample linear-float resolve target: the MSAA resolve destination
    /// (`.renderTarget`) that the present pass then samples (`.shaderRead`).
    private func makeFloatResolve(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A single-sample sRGB display texture: the present pass's tone-mapped output,
    /// for the off-screen paths (export read-back, Syphon/grab hand-off).
    /// `.pixelFormatView` lets a consumer (Syphon) reinterpret its sRGB bytes.
    private func makeDisplayTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead, .pixelFormatView]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    /// A render-pass descriptor that tone-maps the resolved float frame into
    /// `destination` (the drawable or a display texture). The present pass
    /// overwrites every pixel, so the load action doesn't matter.
    private func presentPass(into destination: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    /// Encode the final tone-map pass: a fullscreen triangle sampling `source` (the
    /// resolved linear-float frame) with the drawer's exposure + tone-map mode,
    /// dithering and sRGB-encoding to the bound display attachment. Shared by every
    /// output path (on-screen drawable, export texture, Syphon/grab texture).
    private func encodePresent(from source: MTLTexture, drawer: Drawer,
                               into encoder: MTLRenderCommandEncoder) {
        guard let state = try? pipeline(.present) else { return }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(imageSampler, index: 0)
        var present = OllinPresentUniforms(toneMapMode: drawer.toneMapMode.shaderIndex,
                                           exposure: Float(drawer.toneMapExposure))
        encoder.setFragmentBytes(&present, length: MemoryLayout<OllinPresentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: Pipelines

    /// Return the cached pipeline for `kind`, building and caching it on first
    /// use.
    private func pipeline(_ key: PipelineKey) throws -> MTLRenderPipelineState {
        if let existing = pipelines[key] { return existing }
        let built = try makePipeline(key)
        pipelines[key] = built
        return built
    }

    /// The compiled compute pipeline for `kernel`, built and cached on first use.
    /// Keyed by a hash of the *composed* source (prelude + shared types + user
    /// source) plus the entry name, so re-creating the same kernel value each frame
    /// is free, and the composed library is cached per source so several entries in
    /// one source share one compile.
    private func computePipeline(for kernel: ComputeKernel) throws -> MTLComputePipelineState {
        let composed = MetalRenderer.composeComputeSource(kernel.source)
        let hash = MetalRenderer.fnv1a(composed)
        let key = ComputeKey(sourceHash: hash, entry: kernel.entry)
        if let existing = computePipelines[key] { return existing }
        let lib: MTLLibrary
        if let cached = computeLibraries[hash] {
            lib = cached
        } else {
            lib = try device.makeLibrary(source: composed, options: nil)
            computeLibraries[hash] = lib
        }
        guard let function = lib.makeFunction(name: kernel.entry) else {
            throw RendererError.shaderFunctions
        }
        let state = try device.makeComputePipelineState(function: function)
        computePipelines[key] = state
        return state
    }

    /// Recompile the shader library from `source` and rebuild the cached
    /// pipelines against it — the renderer side of live shader reload. Builds the
    /// replacements *before* committing, so a compile/link error leaves the
    /// current library and pipelines untouched (it throws, and the caller reports
    /// it); a bad shader edit never blanks or crashes the running sketch.
    func reloadLibrary(source: String) throws {
        let newLibrary = try device.makeLibrary(source: MetalRenderer.composeShaderSource(source), options: nil)
        let kinds = pipelines.isEmpty ? [PipelineKey.solid(.normal)] : Array(pipelines.keys)
        var rebuilt: [PipelineKey: MTLRenderPipelineState] = [:]
        for kind in kinds {
            rebuilt[kind] = try makePipeline(kind, using: newLibrary)
        }
        library = newLibrary           // commit atomically once all rebuilt
        pipelines = rebuilt
        // User compute kernels compile from their own source, but drop their caches
        // too so they rebuild against any edited shared types/prelude on next use.
        computePipelines.removeAll()
        computeLibraries.removeAll()
    }

    /// The single place pipeline descriptors are constructed. Add a `case` here
    /// when you add a `Pipeline` — e.g. instanced/SDF circles get their own
    /// vertex/fragment functions and (for instancing) a per-instance buffer.
    private func makePipeline(_ key: PipelineKey) throws -> MTLRenderPipelineState {
        try makePipeline(key, using: library)
    }

    private func makePipeline(_ key: PipelineKey, using library: MTLLibrary) throws -> MTLRenderPipelineState {
        // The present pass is the one pipeline that targets the display format at
        // single-sample with blending off; every other key is a geometry pipeline
        // into the float intermediate, fully described by its shader pair + blend +
        // alpha convention + depth format.
        if key.isPresent {
            return try makePresentPipeline(using: library)
        }
        return try makePipeline(vertex: key.vertex, fragment: key.fragment, using: library,
                                premultiplied: key.premultiplied, blend: key.blend,
                                depthFormat: key.depthFormat)
    }

    /// The final tone-map pass: a fullscreen triangle sampling the resolved
    /// linear-float frame and writing the sRGB drawable. Single-sample (it runs
    /// after the MSAA resolve), blending disabled (it overwrites the drawable),
    /// and it targets the display format rather than the float intermediate.
    private func makePresentPipeline(using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "ollin_present_vertex"),
              let fragmentFunction = library.makeFunction(name: "ollin_present_fragment") else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Build a render pipeline from the named vertex/fragment functions with the
    /// shared config: the view's MSAA sample count, the target pixel format, and
    /// the `blend` mode's factors (resolved against the fragment's alpha
    /// convention). `premultiplied` is true for premultiplied color (the image
    /// path), false for straight-alpha color (solid + SDF + glyph). The default
    /// `blend` (`.normal`) reproduces ordinary source-over compositing.
    private func makePipeline(vertex: String, fragment: String,
                              using library: MTLLibrary,
                              premultiplied: Bool = false,
                              blend: BlendMode = .normal,
                              depthFormat: MTLPixelFormat? = nil) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            throw RendererError.shaderFunctions
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        // Must match the MTKView's MSAA sample count or pipeline creation fails.
        descriptor.rasterSampleCount = sampleCount
        // A depth-tested pass (an active 3D camera) needs the pipeline to declare
        // its depth format; 2D leaves it unset (.invalid), so 2D pipelines stay
        // byte-identical to before this descriptor migration.
        if let depthFormat {
            descriptor.depthAttachmentPixelFormat = depthFormat
        }

        let state = blend.blendState(premultiplied: premultiplied)
        let attachment = descriptor.colorAttachments[0]!
        // Geometry composites into the linear-float intermediate, not the drawable.
        attachment.pixelFormat = linearFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = state.colorOperation
        attachment.alphaBlendOperation = state.alphaOperation
        attachment.sourceRGBBlendFactor = state.sourceColor
        attachment.sourceAlphaBlendFactor = state.sourceAlpha
        attachment.destinationRGBBlendFactor = state.destinationColor
        attachment.destinationAlphaBlendFactor = state.destinationAlpha

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: Helpers

    /// Return the ring's vertex buffer at `index`, large enough for `count`
    /// vertices, growing it (and rounding up) only when a frame needs more room.
    private func vertexBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = vertexBuffers[index], buffer.length >= needed {
            return buffer
        }
        // Over-allocate a little so steady-state frames stop reallocating.
        let capacity = needed + needed / 2
        vertexBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return vertexBuffers[index]
    }

    /// The off-screen export buffer, grown on demand. Kept distinct from the
    /// on-screen ring so a headless render can't stomp a buffer an in-flight
    /// frame is still reading.
    private func exportVertexBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = exportBuffer, buffer.length >= needed { return buffer }
        exportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return exportBuffer
    }

    /// Return the SDF instance ring buffer at `index`, large enough for `count`
    /// instances, grown on demand. Mirrors `vertexBuffer(at:for:)`.
    private func sdfBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        sdfBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return sdfBuffers[index]
    }

    /// The off-screen export buffer for SDF instances, grown on demand.
    private func exportSDFBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfExportBuffer, buffer.length >= needed { return buffer }
        sdfExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfExportBuffer
    }

    /// Return the image-vertex ring buffer at `index`, grown on demand. Mirrors
    /// `vertexBuffer(at:for:)`.
    private func imageBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = imageBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        imageBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return imageBuffers[index]
    }

    /// The off-screen export buffer for image vertices, grown on demand.
    private func exportImageBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = imageExportBuffer, buffer.length >= needed { return buffer }
        imageExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return imageExportBuffer
    }

    /// Return the glyph-vertex ring buffer at `index`, grown on demand. Mirrors
    /// `imageBuffer(at:for:)` (glyph quads reuse `OllinImageVertex`).
    private func glyphBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = glyphBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        glyphBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return glyphBuffers[index]
    }

    /// The off-screen export buffer for glyph vertices, grown on demand.
    private func exportGlyphBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = glyphExportBuffer, buffer.length >= needed { return buffer }
        glyphExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return glyphExportBuffer
    }

    /// Return the point-cloud ring buffer at `index`, grown on demand. Mirrors
    /// `vertexBuffer(at:for:)`.
    private func pointBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinPoint>.stride
        if let buffer = pointBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        pointBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return pointBuffers[index]
    }

    /// The off-screen export buffer for point-cloud splats, grown on demand.
    private func exportPointBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinPoint>.stride
        if let buffer = pointExportBuffer, buffer.length >= needed { return buffer }
        pointExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return pointExportBuffer
    }

    /// Splice the shared CPU/GPU type header into shader source for runtime
    /// compilation. `makeLibrary(source:)` has no include search path, so the
    /// `#include "OllinShaderTypes.h"` directive in `Shaders.metal` can't be
    /// resolved the normal way; we replace it with the header's text (the header
    /// ships beside the shader as a resource). A precompiled metallib resolves
    /// the include at build time and never reaches this path.
    ///
    /// If the header resource is missing we leave the source untouched and let
    /// the compiler report the undefined types — louder than a silent fallback.
    static func composeShaderSource(_ source: String) -> String {
        guard let url = Bundle.module.url(forResource: "OllinShaderTypes", withExtension: "h"),
              let header = try? String(contentsOf: url, encoding: .utf8) else {
            return source
        }
        return source.replacingOccurrences(of: "#include \"OllinShaderTypes.h\"", with: header)
    }

    /// Build the full MSL source for a user compute kernel: the `metal_stdlib`
    /// preamble, the shared CPU↔GPU types (`OllinParticle`/`OllinComputeUniforms`),
    /// and the compute prelude (`OllinCompute.h` — hash/noise/curl/disc), then the
    /// user's source. So a kernel writes no `#include`s and can use those directly.
    /// Both headers ship beside the shaders as resources (the runtime compiler has
    /// no include search path, the same reason `composeShaderSource` splices).
    static func composeComputeSource(_ userSource: String) -> String {
        var source = "#include <metal_stdlib>\nusing namespace metal;\n"
        if let url = Bundle.module.url(forResource: "OllinShaderTypes", withExtension: "h"),
           let header = try? String(contentsOf: url, encoding: .utf8) {
            source += header + "\n"
        }
        if let url = Bundle.module.url(forResource: "OllinCompute", withExtension: "h"),
           let prelude = try? String(contentsOf: url, encoding: .utf8) {
            source += prelude + "\n"
        }
        return source + userSource
    }

    /// FNV-1a hash of a string's UTF-8, for the compute-pipeline cache key.
    /// (`Hasher` is per-process-seeded, so it can't key a stable cache; FNV is
    /// stable — the same lesson the model-tracker cache learned.)
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    /// Load the shader library for `Shaders.metal`.
    ///
    /// SwiftPM's resource rule copies `Shaders.metal` into `Bundle.module` as
    /// *source* — it does not produce a precompiled `default.metallib`. So the
    /// reliable path is to read that source and compile it at runtime. We still
    /// try a precompiled `default.metallib` first in case a future build step
    /// (e.g. a build-tool plugin) produces one.
    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
        }
        if let url = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            // Let compile errors propagate: a bad shader should fail loudly here.
            return try device.makeLibrary(source: composeShaderSource(source), options: nil)
        }
        if let library = device.makeDefaultLibrary() {
            return library
        }
        throw RendererError.shaderLibrary
    }
}

extension Color {
    /// Background/clear-color representation for a render pass. The render targets
    /// are sRGB-encoded and Metal treats a clear value as *linear* (encoding it on
    /// store), so the RGB is linearized here to land the author's sRGB tone in the
    /// framebuffer — matching the shaders, which linearize their colors too. Alpha
    /// isn't gamma-encoded, so it passes through.
    var mtlClearColor: MTLClearColor {
        MTLClearColorMake(Color.srgbToLinear(red), Color.srgbToLinear(green),
                          Color.srgbToLinear(blue), alpha)
    }
}
