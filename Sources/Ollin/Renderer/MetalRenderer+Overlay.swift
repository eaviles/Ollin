import Metal

// The overlay: the runs a `withOverlay` block tagged, drawn over the finished
// frame after everything the frame did to itself.
extension MetalRenderer {
    /// Draw the frame's overlay runs over `resolved`, the finished frame, or hand
    /// `resolved` back untouched when the frame drew none. The pass is a
    /// multisampled geometry pass of its own, at the finished frame's size and
    /// format, that starts by writing that frame into every sample, so a run's
    /// blend mode composites against the picture exactly as a canvas run's does
    /// against the clear; its depth is its own, cleared, and it carries the clip
    /// stencil when the frame clips. `viewport` is the canvas's logical size, as
    /// the geometry pass takes it, and `buffers` the frame's geometry ring slot,
    /// which already holds this frame's data (the encode writes the same bytes
    /// again, which is harmless).
    func applyOverlay(_ drawer: Drawer, resolved: MTLTexture, viewport: SIMD2<Float>,
                      buffers: GeometryBuffers, into cb: MTLCommandBuffer,
                      pooled: Bool) -> MTLTexture {
        overlayDrawnLastFrame = false
        guard drawer.hasOverlay else { return resolved }
        let width = resolved.width, height = resolved.height
        let format = resolved.pixelFormat
        let storage = attachmentStorage(for: drawer, target: nil)
        if overlaySize != (width, height) || overlayFormat != format || overlayMSAATex == nil
            || overlayMSAATex?.storageMode != storage {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: storage, format: format),
                  let depth = makeDepthMSAA(width: width, height: height, storage: storage)
            else { return resolved }
            overlayMSAATex = msaa
            overlayDepthTex = depth
            overlaySize = (width, height)
            overlayFormat = format
        }
        guard let msaa = overlayMSAATex, let depth = overlayDepthTex,
              let output = acquireFilterTexture(width: width, height: height, pooled: pooled,
                                                format: format)
        else { return resolved }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare
        let hasStencil = attachClipStencil(to: pass, active: drawer.usesClipStencil,
                                           width: width, height: height, storage: storage)
        guard let enc = countedEncoder(cb, pass, caller: "overlay") else { return resolved }

        // The finished frame first, into every sample.
        let canvasFormat: MTLPixelFormat? = format == linearFormat ? nil : format
        let copyKey = PipelineKey.effectInPass("ollin_fx_copy", format: canvasFormat,
                                               depthFormat: depthPixelFormat,
                                               stencilFormat: hasStencil ? .stencil8 : nil)
        if let copy = try? pipeline(copyKey) {
            enc.setRenderPipelineState(copy)
            if let state = noDepthState { enc.setDepthStencilState(state) }
            enc.setFragmentTexture(resolved, index: 0)
            enc.setFragmentSamplerState(imageSampler, index: 0)
            var params = SIMD4<Float>(repeating: 0)
            enc.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)),
               into: enc,
               triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
               imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
               pointBuffer: buffers.point, meshBuffer: buffers.mesh, lineBuffer: buffers.line,
               instancedMeshBuffer: buffers.instancedMesh,
               meshInstanceBuffer: buffers.meshInstance,
               sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
               sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
               depthFormat: depthPixelFormat, stencil: hasStencil,
               overlay: true,
               canvasColorFormat: canvasFormat)
        enc.endEncoding()
        overlayDrawnLastFrame = true
        return output
    }
}
