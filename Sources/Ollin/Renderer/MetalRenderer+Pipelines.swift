// MetalRenderer, the pipeline and shader-library half: the enum-keyed pipeline
// cache and factory, the vertex-buffer ring accessor, and the shader-segment
// concatenation + runtime compile (loadLibrary, composeShaderSource, the
// user-shader wrapper compile, and diagnostic cleanup).

import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics
import COllinShaders

extension MetalRenderer {
    // MARK: Pipelines

    /// Return the cached pipeline for `kind`, building and caching it on first
    /// use.
    func pipeline(_ key: PipelineKey) throws -> MTLRenderPipelineState {
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
    func computePipeline(for kernel: ComputeKernel) throws -> MTLComputePipelineState {
        let composed = MetalRenderer.composeComputeSource(kernel.source,
                                                          sourcePath: kernel.sourcePath)
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
        let newLibrary = try device.makeLibrary(
            source: MetalRenderer.composeShaderSource(source, rayTracing: rayTracedShadows), options: nil)
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
        // Main-library kernels (the caustics chain) rebuild from the new library.
        libComputePipelines.removeAll()
        invalidateUserShaderCaches()
    }

    /// The compiled compute pipeline for a kernel that lives in the *main* shader
    /// library (the caustics chain), cached by entry name. Distinct from
    /// `computePipeline(for:)`, which compiles user kernels from their own source.
    func libraryComputePipeline(_ entry: String) throws -> MTLComputePipelineState {
        if let existing = libComputePipelines[entry] { return existing }
        guard let function = library.makeFunction(name: entry) else {
            throw RendererError.shaderFunctions
        }
        let state = try device.makeComputePipelineState(function: function)
        libComputePipelines[entry] = state
        return state
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
            return try makePresentPipeline(key, using: library)
        }
        if key.isEffect {
            return try makeEffectPipeline(key, using: library)
        }
        if key.isShadow {
            return try makeShadowPipeline(key, using: library)
        }
        if key.isIBL {
            guard let v = library.makeFunction(name: key.vertex),
                  let f = library.makeFunction(name: key.fragment) else {
                throw RendererError.shaderFunctions
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = f
            d.rasterSampleCount = 1
            d.colorAttachments[0].pixelFormat = key.iblColorFormat
            return try device.makeRenderPipelineState(descriptor: d)
        }
        if key.isScatterMask {
            // The subsurface-scatter mask: one float attachment, blending off (the
            // fragment's alpha carries a profile index, which alpha blending would
            // corrupt), single-sample, depth-tested + writing into its own depth.
            guard let v = library.makeFunction(name: key.vertex),
                  let f = library.makeFunction(name: key.fragment) else {
                throw RendererError.shaderFunctions
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = f
            d.rasterSampleCount = 1
            d.colorAttachments[0].pixelFormat = linearFormat
            if let depthFormat = key.depthFormat {
                d.depthAttachmentPixelFormat = depthFormat
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        if key.isVelocity {
            // The mover-velocity pass: one rg16Float attachment (a signed pixel
            // delta, so blending stays off and the write replaces the sentinel
            // clear), single-sample, depth-tested + writing into its own depth.
            // The occluder phase is the same pass with no fragment: Metal requires
            // every color write mask empty when the fragment function is nil, which
            // is exactly the depth-only behavior it exists for.
            guard let v = library.makeFunction(name: key.vertex) else {
                throw RendererError.shaderFunctions
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            if key.isVelocityOccluder {
                d.colorAttachments[0].writeMask = []
            } else {
                guard let f = library.makeFunction(name: key.fragment) else {
                    throw RendererError.shaderFunctions
                }
                d.fragmentFunction = f
            }
            d.rasterSampleCount = 1
            d.colorAttachments[0].pixelFormat = .rg16Float
            if let depthFormat = key.depthFormat {
                d.depthAttachmentPixelFormat = depthFormat
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        if key.isGBuffer {
            // The reflection G-buffer: the one MRT pipeline; two float attachments
            // (world normal + coverage, metalness/roughness), blending off (the
            // fragment's output replaces over the cleared zero), single-sample (the
            // reflection layer is jitter-supersampled temporally, not spatially),
            // depth-tested + writing into its own depth.
            guard let v = library.makeFunction(name: key.vertex),
                  let f = library.makeFunction(name: key.fragment) else {
                throw RendererError.shaderFunctions
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = f
            d.rasterSampleCount = 1
            for i in 0..<key.gBufferAttachments {
                d.colorAttachments[i].pixelFormat = linearFormat
            }
            if let depthFormat = key.depthFormat {
                d.depthAttachmentPixelFormat = depthFormat
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        if key.isCausticSplat {
            // The caustics splat: instanced photon footprints additively blended
            // (one + one) into the single-sample float caustics layer; no depth
            // attachment (the fragment compares against the G-buffer's depth itself).
            guard let v = library.makeFunction(name: key.vertex),
                  let f = library.makeFunction(name: key.fragment) else {
                throw RendererError.shaderFunctions
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v
            d.fragmentFunction = f
            d.rasterSampleCount = 1
            let color = d.colorAttachments[0]!
            color.pixelFormat = linearFormat
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .one
            return try device.makeRenderPipelineState(descriptor: d)
        }
        if !key.mesh.isEmpty { return try makeMeshPipeline(key, using: library) }
        return try makePipeline(vertex: key.vertex, fragment: key.fragment, using: library,
                                premultiplied: key.premultiplied, blend: key.blend,
                                depthFormat: key.depthFormat, singleSample: key.singleSample,
                                stencilFormat: key.stencilFormat, clipWrite: key.isClipWrite)
    }

    /// A shadow pass pipeline. Two shapes share this factory: the **2D map**
    /// (directional/spot, `ollin_mesh_shadow_vertex`) is depth-only — no fragment, no
    /// color attachment, the stored value is the rasterized depth. The **point cube**
    /// (`ollin_mesh_point_shadow_vertex`) is layered (all six faces via
    /// `render_target_array_index`, so it needs the triangle input topology) and writes
    /// the distance to the light into an `rg32Float` color cube for mid-point shadow
    /// mapping: `pointShadowOp` 1 MIN-blends into R (nearest), 2 MAX-blends into G
    /// (farthest), each writing only its channel. Single-sample either way.
    private func makeShadowPipeline(_ key: PipelineKey, using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: key.vertex) else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = key.fragment.isEmpty ? nil : library.makeFunction(name: key.fragment)
        descriptor.rasterSampleCount = 1
        if key.pointShadowOp != 0 {
            // Point cube: a color attachment (rg32Float), no depth. One channel per
            // pass, MIN/MAX-blended, so the two draws build nearest (R) + farthest (G).
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = MetalRenderer.pointShadowColorFormat
            color.isBlendingEnabled = true
            color.rgbBlendOperation = key.pointShadowOp == 1 ? .min : .max
            color.alphaBlendOperation = key.pointShadowOp == 1 ? .min : .max
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .one
            color.writeMask = key.pointShadowOp == 1 ? .red : .green
        } else {
            descriptor.depthAttachmentPixelFormat = depthPixelFormat
        }
        // The cube pass routes each instance to a cube face from the vertex stage
        // (both the plain and the instanced point-shadow vertices write
        // `render_target_array_index`), so the pipeline must declare a layered
        // (triangle) input topology.
        if key.pointShadowOp != 0 {
            descriptor.inputPrimitiveTopology = .triangle
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The final tone-map pass: a fullscreen triangle sampling the resolved
    /// linear-float frame and writing the sRGB drawable. Single-sample (it runs
    /// after the MSAA resolve), blending disabled (it overwrites the drawable),
    /// and it targets the display format rather than the float intermediate.
    private func makePresentPipeline(_ key: PipelineKey,
                                     using library: MTLLibrary) throws -> MTLRenderPipelineState {
        // The 8-bit path runs the shipped fragment; a float destination (wide
        // gamut or HDR) runs its twin, which converts primaries instead of
        // dithering and sRGB-encoding. One or the other for the renderer's whole
        // life, so this is not a per-frame branch. A piece fitted to a wall runs
        // the projected twin of whichever of those it is (see
        // `Installation.Projection`), which is a per-*key* branch: the plain pass
        // is still what an export and a desk window run.
        let base = presentEncoding == .srgb8 ? "ollin_present" : "ollin_present_wide"
        let fragmentName = key.isProjected ? "\(base)_projected_fragment" : "\(base)_fragment"
        guard let vertexFunction = library.makeFunction(name: "ollin_present_vertex"),
              let fragmentFunction = library.makeFunction(name: fragmentName) else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// An effects filter pass: a fullscreen-triangle fragment writing the
    /// linear-float intermediate, single-sample (it runs between resolves, not in an
    /// MSAA pass) with blending off, since the filter shader produces the final texel.
    private func makeEffectPipeline(_ key: PipelineKey, using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: key.vertex),
              let fragmentFunction = library.makeFunction(name: key.fragment) else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = key.effectFormat ?? linearFormat
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
                              depthFormat: MTLPixelFormat? = nil,
                              singleSample: Bool = false,
                              stencilFormat: MTLPixelFormat? = nil,
                              clipWrite: Bool = false) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            throw RendererError.shaderFunctions
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        // Must match the pass's sample count or pipeline creation fails: the view's MSAA count
        // for the geometry pass, or 1 for the single-sample half-res raymarch pass.
        descriptor.rasterSampleCount = singleSample ? 1 : sampleCount
        // A depth-tested pass (an active 3D camera) needs the pipeline to declare
        // its depth format; 2D leaves it unset (.invalid), so 2D pipelines stay
        // byte-identical to before this descriptor migration.
        if let depthFormat {
            descriptor.depthAttachmentPixelFormat = depthFormat
        }
        // A stencil-carrying pass (clipping active) needs *every* pipeline drawn into
        // it to declare the stencil format; a pass without one leaves it unset.
        if let stencilFormat {
            descriptor.stencilAttachmentPixelFormat = stencilFormat
        }

        let state = blend.blendState(premultiplied: premultiplied)
        let attachment = descriptor.colorAttachments[0]!
        // Geometry composites into the linear-float intermediate, not the drawable.
        attachment.pixelFormat = linearFormat
        if clipWrite {
            // The clip push/pop draw only into the stencil: color fully masked off,
            // blending irrelevant (and disabled).
            attachment.writeMask = []
            attachment.isBlendingEnabled = false
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = state.colorOperation
        attachment.alphaBlendOperation = state.alphaOperation
        attachment.sourceRGBBlendFactor = state.sourceColor
        attachment.sourceAlphaBlendFactor = state.sourceAlpha
        attachment.destinationRGBBlendFactor = state.destinationColor
        attachment.destinationAlphaBlendFactor = state.destinationAlpha

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// A mesh pipeline (Metal 3 [[object]]/[[mesh]] stages): the strand fields'
    /// factory. Shaped like the generic geometry pipeline (linear-float target,
    /// the pass's MSAA count, blend from the key) with the two mesh stages in
    /// place of a vertex function; the fragment is the ordinary lit one.
    private func makeMeshPipeline(_ key: PipelineKey,
                                  using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let objectFunction = library.makeFunction(name: key.object),
              let meshFunction = library.makeFunction(name: key.mesh),
              let fragmentFunction = library.makeFunction(name: key.fragment) else {
            throw RendererError.shaderFunctions
        }
        let descriptor = MTLMeshRenderPipelineDescriptor()
        descriptor.objectFunction = objectFunction
        descriptor.meshFunction = meshFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.payloadMemoryLength = key.payloadLength
        descriptor.maxTotalThreadsPerObjectThreadgroup = 32
        descriptor.maxTotalThreadsPerMeshThreadgroup = Int(OLLIN_STRAND_BUNDLE)
        descriptor.rasterSampleCount = key.singleSample ? 1 : sampleCount
        if let depthFormat = key.depthFormat {
            descriptor.depthAttachmentPixelFormat = depthFormat
        }
        if let stencilFormat = key.stencilFormat {
            descriptor.stencilAttachmentPixelFormat = stencilFormat
        }
        let state = key.blend.blendState(premultiplied: key.premultiplied)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = linearFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = state.colorOperation
        attachment.alphaBlendOperation = state.alphaOperation
        attachment.sourceRGBBlendFactor = state.sourceColor
        attachment.sourceAlphaBlendFactor = state.sourceAlpha
        attachment.destinationRGBBlendFactor = state.destinationColor
        attachment.destinationAlphaBlendFactor = state.destinationAlpha
        let (pipeline, _) = try device.makeRenderPipelineState(descriptor: descriptor,
                                                               options: [])
        return pipeline
    }

    // MARK: Helpers

    /// Return the ring's vertex buffer at `index`, large enough for `count`
    /// vertices, growing it (and rounding up) only when a frame needs more room.
    func vertexBuffer(at index: Int, for count: Int) -> MTLBuffer? {
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
    func exportVertexBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = exportBuffer, buffer.length >= needed { return buffer }
        exportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return exportBuffer
    }

    /// Return the SDF instance ring buffer at `index`, large enough for `count`
    /// instances, grown on demand. Mirrors `vertexBuffer(at:for:)`.
    func sdfBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        sdfBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return sdfBuffers[index]
    }

    /// The off-screen export buffer for SDF instances, grown on demand.
    func exportSDFBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfExportBuffer, buffer.length >= needed { return buffer }
        sdfExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfExportBuffer
    }

    /// Ring + export buffers for the SDF-combinator group instances and node
    /// programs, grown on demand. Mirror `sdfBuffer(at:for:)`/`exportSDFBuffer(for:)`.
    func sdfGroupBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFGroupInstance>.stride
        if let buffer = sdfGroupBuffers[index], buffer.length >= needed { return buffer }
        sdfGroupBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfGroupBuffers[index]
    }
    func exportSDFGroupBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFGroupInstance>.stride
        if let buffer = sdfGroupExportBuffer, buffer.length >= needed { return buffer }
        sdfGroupExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfGroupExportBuffer
    }
    func sdfNodeBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode>.stride
        if let buffer = sdfNodeBuffers[index], buffer.length >= needed { return buffer }
        sdfNodeBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfNodeBuffers[index]
    }
    func exportSDFNodeBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode>.stride
        if let buffer = sdfNodeExportBuffer, buffer.length >= needed { return buffer }
        sdfNodeExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfNodeExportBuffer
    }

    /// Ring + export buffers for the *3D* SDF-combinator field instances and node
    /// programs (the raymarch path). Mirror the 2D `sdfGroupBuffer`/`sdfNodeBuffer` pair.
    func sdf3DGroupBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDF3DGroupInstance>.stride
        if let buffer = sdf3DGroupBuffers[index], buffer.length >= needed { return buffer }
        sdf3DGroupBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DGroupBuffers[index]
    }
    func exportSDF3DGroupBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDF3DGroupInstance>.stride
        if let buffer = sdf3DGroupExportBuffer, buffer.length >= needed { return buffer }
        sdf3DGroupExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DGroupExportBuffer
    }
    func sdf3DNodeBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode3D>.stride
        if let buffer = sdf3DNodeBuffers[index], buffer.length >= needed { return buffer }
        sdf3DNodeBuffers[index] = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DNodeBuffers[index]
    }
    func exportSDF3DNodeBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFNode3D>.stride
        if let buffer = sdf3DNodeExportBuffer, buffer.length >= needed { return buffer }
        sdf3DNodeExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdf3DNodeExportBuffer
    }

    /// Return the image-vertex ring buffer at `index`, grown on demand. Mirrors
    /// `vertexBuffer(at:for:)`.
    func imageBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = imageBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        imageBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return imageBuffers[index]
    }

    /// The off-screen export buffer for image vertices, grown on demand.
    func exportImageBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = imageExportBuffer, buffer.length >= needed { return buffer }
        imageExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return imageExportBuffer
    }

    /// Return the glyph-vertex ring buffer at `index`, grown on demand. Mirrors
    /// `imageBuffer(at:for:)` (glyph quads reuse `OllinImageVertex`).
    func glyphBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = glyphBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        glyphBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return glyphBuffers[index]
    }

    /// The off-screen export buffer for glyph vertices, grown on demand.
    func exportGlyphBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinImageVertex>.stride
        if let buffer = glyphExportBuffer, buffer.length >= needed { return buffer }
        glyphExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return glyphExportBuffer
    }

    /// Return the point-cloud ring buffer at `index`, grown on demand. Mirrors
    /// `vertexBuffer(at:for:)`.
    func pointBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinPoint>.stride
        if let buffer = pointBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        pointBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return pointBuffers[index]
    }

    /// The off-screen export buffer for point-cloud splats, grown on demand.
    func exportPointBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinPoint>.stride
        if let buffer = pointExportBuffer, buffer.length >= needed { return buffer }
        pointExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return pointExportBuffer
    }

    /// How many mesh vertices a frame's buffer has to hold: the plain meshes, plus the
    /// base meshes of the instanced draws, plus the base meshes of every drawn field.
    /// The traced build appends those after the plain ones so that a single pointer
    /// still serves the hit fetch, so the room for them is reserved wherever the
    /// buffer is asked for. A field's base meshes are one expansion per distinct mesh,
    /// never per copy, so the room is the field's mesh set rather than its world.
    func tracedMeshVertexCount(_ drawer: Drawer) -> Int {
        var fields = 0
        for batch in drawer.batches where batch.kind == .meshField {
            guard let field = batch.field, field.withinTracedBudget else { continue }
            fields += field.baseVertices.count
        }
        return drawer.meshVertices.count + drawer.instancedMeshVertices.count + fields
    }

    /// Return the solid-mesh ring buffer at `index`, grown on demand. Mirrors
    /// `pointBuffer(at:for:)`.
    func meshBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshVertex>.stride
        if let buffer = meshBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        meshBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return meshBuffers[index]
    }

    /// The off-screen export buffer for solid-mesh vertices, grown on demand.
    func exportMeshBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshVertex>.stride
        if let buffer = meshExportBuffer, buffer.length >= needed { return buffer }
        meshExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return meshExportBuffer
    }

    /// Ring + export buffers for the instanced-mesh path: the local-space base
    /// vertices and the per-copy placements. Mirror `meshBuffer(at:for:)`.
    func instancedMeshBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshVertex>.stride
        if let buffer = instancedMeshBuffers[index], buffer.length >= needed { return buffer }
        instancedMeshBuffers[index] = device.makeBuffer(length: needed + needed / 2,
                                                        options: .storageModeShared)
        return instancedMeshBuffers[index]
    }
    func exportInstancedMeshBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshVertex>.stride
        if let buffer = instancedMeshExportBuffer, buffer.length >= needed { return buffer }
        instancedMeshExportBuffer = device.makeBuffer(length: needed + needed / 2,
                                                      options: .storageModeShared)
        return instancedMeshExportBuffer
    }
    func meshInstanceBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshInstance>.stride
        if let buffer = meshInstanceBuffers[index], buffer.length >= needed { return buffer }
        meshInstanceBuffers[index] = device.makeBuffer(length: needed + needed / 2,
                                                       options: .storageModeShared)
        return meshInstanceBuffers[index]
    }
    func exportMeshInstanceBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinMeshInstance>.stride
        if let buffer = meshInstanceExportBuffer, buffer.length >= needed { return buffer }
        meshInstanceExportBuffer = device.makeBuffer(length: needed + needed / 2,
                                                     options: .storageModeShared)
        return meshInstanceExportBuffer
    }

    /// Resolve the quoted `#include`s in shader source for runtime compilation.
    /// `makeLibrary(source:)` has no include search path, so a directive naming
    /// another file (the shared `OllinShaderTypes.h`, or one segment naming another)
    /// can't be resolved the normal way; `ShaderIncludes` reads the named file out of
    /// Ollin's resource bundle and splices its text in place. A precompiled metallib
    /// resolves the same directives at build time and skips this path.
    ///
    /// A file that can't be found leaves a blank line and lets the compiler report the
    /// undefined types that follow, which is louder than a silent fallback.
    static func composeShaderSource(_ source: String, rayTracing: Bool = false) -> String {
        // Gate the inline-RT mesh-shadow path on device capability (the symbol the
        // `#if OLLIN_RT_SHADOWS` blocks in Shader3D.metal read). A device without
        // render-stage ray tracing compiles it out entirely, so the cube path stays.
        rayTracingDefine(rayTracing) + ShaderIncludes.resolve(source, name: "Ollin",
                                                             load: bundleShaderFile).source
    }

    /// The one-line preamble that gates the inline-ray-tracing blocks, prepended to
    /// every runtime compile of the built-in library.
    static func rayTracingDefine(_ rayTracing: Bool) -> String {
        "#define OLLIN_RT_SHADOWS \(rayTracing ? 1 : 0)\n"
    }

    /// Find a shader file by the spelling inside an `#include`, in Ollin's own resource
    /// bundle: the built-in `.metal` segments and the shared CPU/GPU `.h` header all
    /// ship there. `askedBy` is unused, because a bundle is flat: every spelling is a
    /// plain resource name however deep the chain that asked for it.
    static func bundleShaderFile(_ spelling: String, _ askedBy: String) -> ShaderIncludes.Source? {
        let stem = (spelling as NSString).deletingPathExtension
        let ext = (spelling as NSString).pathExtension
        guard let url = OllinResources.bundle.url(forResource: stem,
                                                  withExtension: ext.isEmpty ? nil : ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return ShaderIncludes.Source(key: url.path, name: url.path, text: text)
    }

    /// Build the full MSL source for a user compute kernel: the shared shader
    /// library (`OllinShaderLib`, the same helper set user fragment shaders get:
    /// hash/noise/curl/disc, palettes and OKLab, the `sd*` catalog, domain
    /// operators), with the library's own `metal_stdlib` preamble kept and the
    /// shared CPU↔GPU types spliced in place of its `#include`, then the user's
    /// source. So a kernel writes no `#include`s, and a helper learned in a
    /// fragment shader works the same in a kernel. Resources are read as text
    /// because the runtime compiler has no include search path (same reason
    /// `composeShaderSource` splices).
    static func composeComputeSource(_ userSource: String, sourcePath: String = "") -> String {
        var lib = "#include <metal_stdlib>\nusing namespace metal;\n#include \"OllinShaderTypes.h\"\n"
        if let url = OllinResources.bundle.url(forResource: "OllinShaderLib", withExtension: "metal"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            lib = text
        }
        lib = ShaderIncludes.resolve(lib, name: "OllinShaderLib.metal", load: bundleShaderFile).source
        // A kernel may pull in a file of its own, the same way a fragment shader does,
        // so one helper file can serve both. It resolves against the folder the kernel's
        // source came from.
        let user = sourcePath.isEmpty ? userSource
            : ShaderIncludes.resolveFromFilesystem(userSource, name: sourcePath).source
        return lib + "\n" + user
    }

    /// FNV-1a hash of a string's UTF-8, for the compute-pipeline cache key.
    /// (`Hasher` is per-process-seeded, so it can't key a stable cache; FNV is
    /// stable — the same lesson the model-tracker cache learned.)
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    /// Build the full MSL source for a user-supplied `Shader`: the OllinShaderLib
    /// segment (preamble + shared types + helpers, with the file it includes read in by
    /// `ShaderIncludes`, since the runtime compiler has no include path), then the wrapper
    /// (the fullscreen vertex, the `ShaderInfo` struct, the `param`/`sample` helpers),
    /// then the user's source tagged with a `#line` directive naming the file it came
    /// from (`sourceName`, the sketch's own `.swift` or the `.metal` resource) at the
    /// line it starts on (`sourceStartLine`), so the compiler reports errors at a real,
    /// IDE-clickable `file:line`, then the generated `ollin_user_fragment` that calls
    /// their `shade(uv, info)`. Returns the source and the number of lines that
    /// precede the user's source (the fallback rebase offset for a toolchain that
    /// ignores `#line`).
    static func composeUserShaderSource(userSource: String, modules: Shader.Modules,
                                        variant: UserShaderVariant,
                                        sourceName: String = "Shader",
                                        sourceStartLine: Int = 1) -> (source: String, userLineOffset: Int) {
        let lib = userShaderLibraryText(modules)
        let name = sourceName.isEmpty ? "Shader" : sourceName
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let directive = "\n#line \(max(1, sourceStartLine)) \"\(escaped)\"\n"
        let head = lib + "\n" + userShaderWrapperHead(variant) + directive
        let offset = head.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
        let tail = "\n#line 1 \"ollin-wrapper\"\n" + userShaderWrapperTail(variant)
        return (head + userSource + tail, offset)
    }

    /// The shader library a user shader is compiled against: the `OllinShaderLib`
    /// segment trimmed to `modules`, with its own `#include` of the shared CPU/GPU
    /// header already read in.
    ///
    /// Kept in memory per module set, because this runs once per user shader per frame
    /// (the composed source is what the pipeline cache is keyed on) and the bundled
    /// library cannot change while the process runs. `dropUserShaderLibraryText` empties
    /// it where that stops being true.
    static func userShaderLibraryText(_ modules: Shader.Modules) -> String {
        if let cached = userShaderLibraryTexts[modules.rawValue] { return cached }
        var lib = ""
        if let url = OllinResources.bundle.url(forResource: "OllinShaderLib", withExtension: "metal"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            lib = filterLibModules(text, modules)
        }
        lib = ShaderIncludes.resolve(lib, name: "OllinShaderLib.metal", load: bundleShaderFile).source
        userShaderLibraryTexts[modules.rawValue] = lib
        return lib
    }

    /// Forget the composed library text, so the next user shader reads it again.
    static func dropUserShaderLibraryText() {
        userShaderLibraryTexts.removeAll()
    }

    private static var userShaderLibraryTexts: [Int: String] = [:]

    /// Keep only the requested sections of the shader library, by the
    /// `// OLLIN_LIB_BEGIN <module>` / `// OLLIN_LIB_END <module>` markers. Unmarked
    /// lines (the preamble and the always-on `base` section) are always kept; a
    /// section whose module isn't requested is dropped, trimming compile time. The
    /// dependency `noise → hash` is resolved so a noise-only request still compiles.
    private static func filterLibModules(_ lib: String, _ modules: Shader.Modules) -> String {
        if modules == .all { return lib }   // the common case: splice everything
        var mods = modules
        if mods.contains(.noise) { mods.insert(.hash) }
        if mods.contains(.visual) { mods.insert(.hash); mods.insert(.noise) }
        let nameToModule: [String: Shader.Modules] = [
            "hash": .hash, "noise": .noise, "color": .color, "sdf": .sdf, "domain": .domain,
            "visual": .visual]
        var out: [Substring] = []
        var skipping = false
        for line in lib.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// OLLIN_LIB_BEGIN ") {
                let name = String(trimmed.dropFirst("// OLLIN_LIB_BEGIN ".count))
                skipping = nameToModule[name].map { !mods.contains($0) } ?? false
                continue
            }
            if trimmed.hasPrefix("// OLLIN_LIB_END ") { skipping = false; continue }
            if !skipping { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    /// The wrapper preamble: the fullscreen vertex, the user-facing `ShaderInfo`
    /// struct, and the `param`/`sample` accessors. The struct carries the input
    /// layer(s) for the filter (one) and combine (two) variants, so the user reads
    /// them with `sample(info, uv)` / `sampleAux(info, uv)`, or with the `…Raw` pair
    /// when the layer holds data rather than a picture.
    ///
    /// **The readers are functions, and that is load-bearing.** They were macros once,
    /// which spelled the same thing but obeyed no scope: `sample` is a member function
    /// on every Metal texture type (Ollin's own segments call it 497 times), so a
    /// function-like `#define sample(info, p)` rewrote `t.sample(s, uv)` in anything
    /// the shader pulled in, into a member that does not exist, and reported it as
    /// three errors naming symbols the author never wrote. A different argument count
    /// failed in the preprocessor instead, and a helper of the author's own named
    /// `sample` could not be declared at all. As free functions the same spellings
    /// resolve by overload, so a member call is never a candidate and a helper of any
    /// other signature is simply another overload. `info` is taken by reference
    /// because the struct carries the whole parameter block.
    private static func userShaderWrapperHead(_ variant: UserShaderVariant) -> String {
        let layerFields: String
        let sampleReaders: String
        switch variant {
        case .generator:
            layerFields = ""
            sampleReaders = ""
        case .filter:
            layerFields = "    texture2d<float> in0; sampler in0samp;\n"
            sampleReaders = """
            inline float4 sample(thread const ShaderInfo &info, float2 p) {
                return ollin_layer_sample(info.in0, info.in0samp, p);
            }
            inline float4 sampleRaw(thread const ShaderInfo &info, float2 p) {
                return ollin_layer_read(info.in0, info.in0samp, p);
            }

            """
        case .combine:
            layerFields = "    texture2d<float> in0; sampler in0samp;\n    texture2d<float> in1; sampler in1samp;\n"
            sampleReaders = """
            inline float4 sample(thread const ShaderInfo &info, float2 p) {
                return ollin_layer_sample(info.in0, info.in0samp, p);
            }
            inline float4 sampleAux(thread const ShaderInfo &info, float2 p) {
                return ollin_layer_sample(info.in1, info.in1samp, p);
            }
            inline float4 sampleRaw(thread const ShaderInfo &info, float2 p) {
                return ollin_layer_read(info.in0, info.in0samp, p);
            }
            inline float4 sampleAuxRaw(thread const ShaderInfo &info, float2 p) {
                return ollin_layer_read(info.in1, info.in1samp, p);
            }

            """
        }
        return """
        struct OllinUserVertexOut { float4 position [[position]]; float2 uv; };
        vertex OllinUserVertexOut ollin_user_vertex(uint vid [[vertex_id]]) {
            float2 p = float2((vid << 1) & 2, vid & 2);
            OllinUserVertexOut o;
            o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
            o.uv = float2(p.x, 1.0 - p.y);
            return o;
        }
        // Read an input layer as straight sRGB (it's stored premultiplied linear), so
        // a shader works in the same color space it returns.
        inline float4 ollin_layer_sample(texture2d<float> t, sampler s, float2 uv) {
            float4 c = t.sample(s, clamp(uv, 0.0, 1.0));
            return float4(linearToSrgb(ollin_unpremul(c)), c.a);
        }
        // Read an input layer exactly as it is stored, with no color conversion at all:
        // what a layer holding *data* rather than a picture wants. A measured distance
        // field is the one to reach for it: its red is a distance in pixels and can be
        // negative, and its green and blue are the two halves of a direction, none of
        // which survives being treated as a color.
        inline float4 ollin_layer_read(texture2d<float> t, sampler s, float2 uv) {
            return t.sample(s, clamp(uv, 0.0, 1.0));
        }
        struct ShaderInfo {
            float2 resolution;
            float2 mouse;
            float time;
            float deltaTime;
            uint frame;
            uint paramCount;
            float4 params[OLLIN_SHADER_PARAM_ROWS];
        \(layerFields)};
        inline float param(thread const ShaderInfo &info, int i) {
            return info.params[i >> 2][i & 3];
        }
        inline float param(thread const ShaderInfo &info, uint i) {
            return info.params[i >> 2][i & 3];
        }
        \(sampleReaders)
        """
    }

    /// The generated fragment: bind the input layer(s) for the variant, assemble
    /// `ShaderInfo` from the uniforms, call the user's `shade`, and convert its
    /// straight sRGB result to the premultiplied linear an Ollin layer composites in.
    private static func userShaderWrapperTail(_ variant: UserShaderVariant) -> String {
        let textureParams: String
        let layerAssign: String
        switch variant {
        case .generator:
            textureParams = ""
            layerAssign = ""
        case .filter:
            textureParams = "                                    texture2d<float> ollin_src0 [[texture(0)]],\n"
                + "                                    sampler ollin_samp [[sampler(0)]],\n"
            layerAssign = "    info.in0 = ollin_src0; info.in0samp = ollin_samp;\n"
        case .combine:
            textureParams = "                                    texture2d<float> ollin_src0 [[texture(0)]],\n"
                + "                                    texture2d<float> ollin_src1 [[texture(1)]],\n"
                + "                                    sampler ollin_samp [[sampler(0)]],\n"
            layerAssign = "    info.in0 = ollin_src0; info.in0samp = ollin_samp;\n"
                + "    info.in1 = ollin_src1; info.in1samp = ollin_samp;\n"
        }
        return """
        fragment float4 ollin_user_fragment(OllinUserVertexOut in [[stage_in]],
        \(textureParams)                                    constant float4 *ollin_params [[buffer(0)]],
                                            constant OllinShaderUniforms &ollin_u [[buffer(1)]]) {
            ShaderInfo info;
            info.resolution = ollin_u.resolution;
            info.mouse = ollin_u.mouse;
            info.time = ollin_u.time;
            info.deltaTime = ollin_u.deltaTime;
            info.frame = ollin_u.frame;
            info.paramCount = ollin_u.paramCount;
            for (uint i = 0u; i < OLLIN_SHADER_PARAM_ROWS; ++i) info.params[i] = ollin_params[i];
        \(layerAssign)    float4 c = shade(in.uv, info);
            return float4(srgbToLinear(c.rgb) * c.a, c.a);
        }
        """
    }

    /// Tidy a Metal compiler diagnostic for a user shader: relabel and rebase the
    /// composed-source line numbers (`program_source:N`) to the user's own source
    /// (`sourceName:N-offset+start-1`), so a reported line matches what they wrote,
    /// and drop the boilerplate header. When the compiler honors `#line` it already
    /// reports `sourceName:N`, which passes through unchanged.
    static func cleanShaderDiagnostics(_ raw: String, userLineOffset: Int,
                                       sourceName: String = "Shader",
                                       sourceStartLine: Int = 1) -> String {
        let text = raw
            .replacingOccurrences(of: "Compilation failed: \n", with: "")
            .replacingOccurrences(of: "Compilation failed:\n", with: "")
        guard let rx = try? NSRegularExpression(pattern: #"program_source:(\d+):(\d+):"#) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let ns = text as NSString
        var out = ""
        var last = 0
        rx.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let lineNo = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let col = ns.substring(with: m.range(at: 2))
            out += "\(sourceName):\(max(1, lineNo - userLineOffset + sourceStartLine - 1)):\(col):"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        // Drop compiler-internal notes that point at system framework headers (e.g. a
        // "did you mean" suggestion from the Metal standard library): they reference
        // absolute paths a sketch author can't act on and only clutter the message.
        // A dropped diagnostic takes its continuation lines (the code excerpt and
        // caret under it) along, so no orphaned snippet leaks through; a line naming
        // the user's own file is always kept, wherever that file lives.
        let headerRx = try? NSRegularExpression(pattern: #"^\S.*:\d+:\d+:"#)
        func pointsAtSystem(_ line: Substring) -> Bool {
            !line.contains(sourceName)
                && (line.contains("/System/") || line.contains("GPUCompiler.framework")
                    || line.contains("/Applications/") || line.contains("/usr/"))
        }
        var kept: [Substring] = []
        var dropping = false
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            let isHeader = headerRx.map {
                $0.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
            } ?? false
            if isHeader { dropping = pointsAtSystem(line) }
            if !dropping && !pointsAtSystem(line) { kept.append(line) }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The shader source segments. They're compiled as one library, and Metal needs a
    /// declaration before its use, so they have to reach the compiler in dependency
    /// order. That order is **not** this list: each segment names what it needs with an
    /// `#include` at its top, and `ShaderIncludes.resolveAll` pulls a named file in
    /// ahead of the file that asked for it and splices each one exactly once. So this
    /// is a set kept in alphabetical order, and adding a segment means adding its name
    /// here and declaring its dependencies in the file itself, rather than working out
    /// which slot in a hand-kept sequence it belongs in. The single `Shaders.metal`
    /// split into these once it crossed ~2,000 lines; the renderer never assumes one file.
    static let shaderSourceNames = ["OllinShaderLib", "Shader3D", "ShaderCaustics", "ShaderCombinator", "ShaderCombine", "ShaderCore", "ShaderEffects", "ShaderFlare", "ShaderGI", "ShaderIBL", "ShaderPathTrace", "ShaderPatterns", "ShaderRadiance", "ShaderRaymarch", "ShaderShapes", "ShaderSim", "ShaderStrands"]

    /// Assemble the built-in library out of `roots`, resolving each segment's declared
    /// includes through `load`. The result holds every file once, each after everything
    /// it names, whatever order the roots arrive in.
    static func assembleShaderSource(roots: [ShaderIncludes.Source],
                                     load: (String, String) -> ShaderIncludes.Source?)
        -> ShaderIncludes.Result {
        ShaderIncludes.resolveAll(roots, load: load)
    }

    /// Read and assemble the shader segments from a filesystem `directory`. This is the
    /// source live shader reload feeds back in (the bundled copy is built, not the file
    /// being edited), so a segment's `#include` resolves against that same directory.
    /// `nil` if any segment is unreadable.
    static func concatenatedShaderSource(fromDirectory directory: String) -> String? {
        var roots: [ShaderIncludes.Source] = []
        for name in shaderSourceNames {
            let path = (directory as NSString).appendingPathComponent("\(name).metal")
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            let key = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            roots.append(ShaderIncludes.Source(key: key, name: key, text: text))
        }
        return assembleShaderSource(roots: roots) { spelling, askedBy in
            let folder = (askedBy as NSString).deletingLastPathComponent
            let path = (folder.isEmpty ? directory : folder as String)
            let full = (path as NSString).appendingPathComponent(spelling)
            guard let text = try? String(contentsOfFile: full, encoding: .utf8) else { return nil }
            let key = URL(fileURLWithPath: full).resolvingSymlinksInPath().path
            return ShaderIncludes.Source(key: key, name: key, text: text)
        }.source
    }

    /// Load the built-in shader library.
    ///
    /// SwiftPM's resource rule copies the `Shader*.metal` segments into the
    /// resource bundle as *source*; it does not produce a precompiled
    /// `default.metallib`. So the reliable path is to read those segments, splice
    /// the shared header, and compile at runtime. We still try a precompiled
    /// `default.metallib` first in case a future build step produces one.
    static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        let rt = MetalRenderer.rayTracingAvailable(on: device)
        // A precompiled `default.metallib` is built without the device-conditional
        // `OLLIN_RT_SHADOWS` define (it can hold only one variant — the *non*-RT
        // mesh-shadow path). Use it only on a device without render-stage ray tracing;
        // an RT device compiles from source with the define set, which is Ollin's
        // standard runtime-compile path (and what live shader reload already uses).
        if !rt, let library = try? device.makeDefaultLibrary(bundle: OllinResources.bundle) {
            return library
        }
        // Read every segment from the bundle and assemble one compile unit, each
        // segment's declared `#include`s (its dependencies, and the shared CPU/GPU
        // header) resolved out of the same bundle. Require all of them, so a missing
        // segment fails loudly rather than compiling an incomplete library.
        let roots = shaderSourceNames.map { bundleShaderFile("\($0).metal", "") }
        if roots.allSatisfy({ $0 != nil }) {
            let assembled = assembleShaderSource(roots: roots.compactMap { $0 },
                                                 load: bundleShaderFile)
            // Let compile errors propagate: a bad shader should fail loudly here.
            return try device.makeLibrary(source: rayTracingDefine(rt) + assembled.source,
                                          options: nil)
        }
        if !rt, let library = device.makeDefaultLibrary() {
            return library
        }
        throw RendererError.shaderLibrary
    }
}
