import Foundation
import Metal
import simd
import COllinShaders

// The canvas depth of field (`depthOfField()`): the finished 3D frame blurred by
// its own depth through the camera's thin lens, after the temporal resolve and
// before the motion blur. The shaders are in ShaderCombine.metal beside the
// layer `.defocus`, whose iris shape the gather shares. The hidden layer below is
// the second geometry pass the gather reads under a blurred foreground.

extension MetalRenderer {

    /// Whether the canvas depth of field runs this frame: the sketch asked, a
    /// perspective camera is active, and its lens has an opening. Notes once
    /// for each of the last two when they are why nothing happens.
    func depthOfFieldActive(_ drawer: Drawer) -> Bool {
        guard drawer.depthOfFieldSetting != nil, let camera = drawer.camera3D else { return false }
        if case .orthographic = camera.projection {
            drawer.noteOnce("depthOfField() needs a perspective camera: an orthographic one has no distance for a lens to focus on, so the frame stays sharp.")
            return false
        }
        guard camera.aperture > 0 else {
            drawer.noteOnce("depthOfField() renders the camera's lens, and this camera's aperture is 0 (a pinhole, sharp everywhere); set Camera3D.aperture to a radius in world units, such as 0.05.")
            return false
        }
        return true
    }

    /// The lens as the gather measures it in a texture `height` pixels tall: the
    /// focal length in those pixels and the focus distance along the view axis.
    private func lensInPixels(_ camera: Camera3D, width: Int, height: Int) -> (focalPixels: Double, focus: Double) {
        let aspect = Double(width) / Double(height)
        let focalPixels = Double(camera.projectionMatrix(aspect: aspect).columns.1.y) * Double(height) / 2
        let focus = camera.focusDistance ?? camera.eye.distance(to: camera.target)
        return (focalPixels, focus)
    }

    /// The pixels of a `width` by `height` pass the hidden layer has to cover, or
    /// nil when nothing drawn reaches into the near field, where the lens blurs
    /// by half a pixel or more in front of the focus (or its band). A mesh batch
    /// and a list-placed instanced batch carry a world box: its nearest corner
    /// along the view axis says whether it reaches, and its corners projected say
    /// where. A kind with no box (copies a kernel placed, a field, strands, water,
    /// points, lines, a marched field, a depth scene, a replay holding a point
    /// cloud) counts as near and everywhere, since the pass cannot know better and a layer drawn
    /// for nothing costs a frame's geometry where a layer missing costs the
    /// picture. A box with a corner behind the eye covers the whole pass too.
    func hiddenLayerExtent(_ drawer: Drawer, camera: Camera3D, setting: Drawer.DepthOfFieldSetting,
                           width: Int, height: Int) -> MTLScissorRect? {
        let (focalPixels, focus) = lensInPixels(camera, width: width, height: height)
        // Half a pixel of blur in front of the focus (or the band's near edge):
        // R F (1/edge - 1/d) >= 1/2, so d <= 1 / (1/edge + 1/(2 R F)).
        let edge = max(focus - setting.focusRange, 1e-4)
        let lensScale = camera.aperture * focalPixels
        guard lensScale > 0 else { return nil }
        let nearField = 1 / (1 / edge + 0.5 / lensScale)
        let eye = camera.eye
        let forward = (camera.target - eye).normalized
        let viewProjection = camera.viewProjectionMatrix(aspect: Double(width) / Double(height))
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        var any = false
        let whole = MTLScissorRect(x: 0, y: 0, width: width, height: height)
        for batch in drawer.batches where batch.target == nil && !batch.overlay {
            switch batch.kind {
            case .mesh3D:
                if batch.meshWireframe || batch.meshGrid { continue }
            case .retained:
                // A replay's only 3D content is a point cloud; a 2D replay stands nowhere.
                if batch.retained?.hasPointContent != true { continue }
            case .meshInstanced, .meshField, .strands, .ocean, .points3D, .lines3D, .sdfGroup3D,
                 .depthScene:
                break
            default:
                continue
            }
            guard let box = batch.worldBounds else { return whole }
            var nearest = Double.infinity
            var cornersX = [Double](), cornersY = [Double]()
            cornersX.reserveCapacity(8); cornersY.reserveCapacity(8)
            var behindTheEye = false
            for i in 0 ..< 8 {
                let c = Vector3(i & 1 == 0 ? box.min.x : box.max.x,
                                i & 2 == 0 ? box.min.y : box.max.y,
                                i & 4 == 0 ? box.min.z : box.max.z)
                nearest = min(nearest, (c - eye).dot(forward))
                let clip = viewProjection * SIMD4<Float>(Float(c.x), Float(c.y), Float(c.z), 1)
                if clip.w <= 1e-6 { behindTheEye = true; continue }
                cornersX.append(Double(clip.x / clip.w + 1) * 0.5 * Double(width))
                cornersY.append(Double(1 - clip.y / clip.w) * 0.5 * Double(height))
            }
            guard nearest < nearField else { continue }
            if behindTheEye { return whole }
            any = true
            minX = min(minX, cornersX.min() ?? 0); maxX = max(maxX, cornersX.max() ?? 0)
            minY = min(minY, cornersY.min() ?? 0); maxY = max(maxY, cornersY.max() ?? 0)
        }
        guard any else { return nil }
        // Two pixels either side, for the jitter and the edge's own anti-aliasing.
        let x0 = max(0, Int(floor(minX)) - 2), y0 = max(0, Int(floor(minY)) - 2)
        let x1 = min(width, Int(ceil(maxX)) + 2), y1 = min(height, Int(ceil(maxY)) + 2)
        guard x1 > x0, y1 > y0 else { return nil }
        return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The hidden layer: the 3D scene drawn once more keeping only what lies behind
    /// the first layer (`firstDepth`, the main pass's resolved depth), the second
    /// image a depth of field with partial occlusion is built from. Under a blurred
    /// foreground the gather then reads what the foreground hides instead of
    /// guessing it from what shows beside it. Drawn only when a near-field blur is on screen, and only over the
    /// pixels the near field's meshes cover (`hiddenLayerExtent`); the pass is
    /// cleared whole first, so outside that the layer is the backdrop at the far
    /// plane, which is what stands behind nothing.
    ///
    /// The pass mirrors the main geometry pass (same size, sample count, depth
    /// format, clear, jitter, and every shading input), which is what lets it share
    /// the main pass's pipelines through their peel variants and what lines the two
    /// pictures up pixel for pixel; the jitter is the main pass's own, so the peel
    /// tests each fragment against the depth the first layer really resolved. Its
    /// depth resolves to the nearest sample, the main pass's rule, and the gather
    /// turns it into the layer's blur sizes with the same prepass.
    ///
    /// Returns nil, and the gather keeps its guess, when the depth of field is not
    /// running, when the frame has no first-layer depth, or when nothing reaches
    /// into the near field.
    func encodeHiddenLayerPass(_ drawer: Drawer, into cb: MTLCommandBuffer,
                               viewport: SIMD2<Float>,
                               buffers: GeometryBuffers,
                               width: Int, height: Int,
                               firstDepth: MTLTexture?,
                               shadowMap: MTLTexture?,
                               shadowCube: MTLTexture?,
                               shadowAccel: MTLAccelerationStructure?,
                               reflectAccel: MTLAccelerationStructure?,
                               reflectGeoOffsets: MTLBuffer?,
                               halfResField: (color: MTLTexture, depth: MTLTexture,
                                              region: SIMD4<Float>)? = nil,
                               halfResFieldShadow: MTLTexture? = nil,
                               deferredReflection: (texture: MTLTexture, guide: MTLTexture,
                                                    scale: Float)? = nil,
                               contactShadow: MTLTexture? = nil,
                               gi: GIResolved? = nil,
                               caustics: MTLTexture? = nil,
                               pathTraced: (color: MTLTexture, depth: MTLTexture,
                                            invSamples: Float)? = nil,
                               sceneBehind: (texture: MTLTexture, depth: MTLTexture,
                                             viewProjection: simd_float4x4,
                                             inverseViewProjection: simd_float4x4)? = nil,
                               taaJitter: SIMD2<Float> = .zero)
        -> (color: MTLTexture, depth: MTLTexture)? {
        hiddenLayerDrawnLastFrame = false
        guard depthOfFieldActive(drawer), let setting = drawer.depthOfFieldSetting,
              let camera = drawer.camera3D, let firstDepth, width > 0, height > 0,
              Float(setting.maxBlur) >= 0.5 else { return nil }
        guard let extent = hiddenLayerExtent(drawer, camera: camera, setting: setting,
                                             width: width, height: height) else { return nil }

        let storage = attachmentStorage(for: drawer, target: nil)
        if hiddenLayerSize != (width, height) || hiddenLayerResolveTex == nil
            || hiddenLayerMSAATex?.storageMode != storage {
            guard let msaa = makeFloatMSAA(width: width, height: height, storage: storage),
                  let depth = makeDepthMSAA(width: width, height: height, storage: storage),
                  let depthResolve = makeDepthResolve(width: width, height: height),
                  let resolve = makeFloatResolve(width: width, height: height)
            else { return nil }
            hiddenLayerMSAATex = msaa
            hiddenLayerDepthTex = depth
            hiddenLayerDepthResolveTex = depthResolve
            hiddenLayerResolveTex = resolve
            hiddenLayerSize = (width, height)
        }
        guard let msaa = hiddenLayerMSAATex, let depth = hiddenLayerDepthTex,
              let depthResolve = hiddenLayerDepthResolveTex,
              let resolve = hiddenLayerResolveTex else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = resolve
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.resolveTexture = depthResolve
        pass.depthAttachment.storeAction = .multisampleResolve
        pass.depthAttachment.depthResolveFilter = .min
        let hasStencil = attachClipStencil(to: pass, active: drawer.usesClipStencil,
                                           width: width, height: height, storage: storage)
        guard let enc = countedEncoder(cb, pass, caller: "hidden layer") else { return nil }
        enc.setScissorRect(extent)
        // The peel's rule: the lens in this pass's pixels, a hundredth of the
        // distance as the same surface (the gather's own tolerance), and a pixel
        // and a half for a surface's own slope.
        let (focalPixels, _) = lensInPixels(camera, width: width, height: height)
        var rule = OllinPeel()
        rule.lens = SIMD4<Float>(Float(camera.near), Float(camera.far), Float(focalPixels), 0.01)
        rule.rule = SIMD4<Float>(1.5, 1, 0, 0)
        // The geometry buffers already hold this frame's data (the main pass filled
        // them), and re-copying them is harmless: `encode` writes the same bytes
        // into the same buffers before it draws.
        encode(drawer, viewport: viewport, attachment: SIMD2<Float>(Float(width), Float(height)), into: enc,
               triangleBuffer: buffers.triangle, sdfBuffer: buffers.sdf,
               imageBuffer: buffers.image, glyphBuffer: buffers.glyph,
               pointBuffer: buffers.point, meshBuffer: buffers.mesh, lineBuffer: buffers.line,
               instancedMeshBuffer: buffers.instancedMesh,
               meshInstanceBuffer: buffers.meshInstance,
               sdfGroupBuffer: buffers.sdfGroup, sdfNodeBuffer: buffers.sdfNode,
               sdf3DGroupBuffer: buffers.sdf3DGroup, sdf3DNodeBuffer: buffers.sdf3DNode,
               depthFormat: depthPixelFormat, stencil: hasStencil,
               shadowMap: shadowMap, shadowCube: shadowCube,
               shadowAccel: shadowAccel,
               reflectAccel: reflectAccel, reflectGeoOffsets: reflectGeoOffsets,
               halfResField: halfResField, halfResFieldShadow: halfResFieldShadow,
               deferredReflection: deferredReflection,
               contactShadow: contactShadow, gi: gi, caustics: caustics,
               pathTraced: pathTraced,
               sceneBehind: sceneBehind,
               taaJitter: taaJitter,
               peel: (firstDepth, rule))
        enc.endEncoding()
        hiddenLayerDrawnLastFrame = true
        hiddenLayerExtentLastFrame = extent
        return (resolve, depthResolve)
    }

    /// Blur `resolved` by the canvas depth through the camera's lens, or hand
    /// it back untouched when the pass does not run. `depth` is the frame's
    /// resolved depth (sampled by normalized coordinates, so it may be a
    /// different size than the color); `hidden` is the hidden layer and its
    /// depth (`encodeHiddenLayerPass`), read the same way, or nil when the frame
    /// drew none; `pointScale` turns canvas points into this texture's pixels,
    /// for the `maxBlur` cap. The blur's own size needs no scale: the focal
    /// length is measured in this texture's pixels.
    func applyDepthOfField(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                           hidden: (color: MTLTexture, depth: MTLTexture)? = nil,
                           into cb: MTLCommandBuffer, width: Int, height: Int,
                           pointScale: Float, pooled: Bool) -> MTLTexture {
        guard depthOfFieldActive(drawer), let setting = drawer.depthOfFieldSetting,
              let camera = drawer.camera3D, let depth, width > 0, height > 0 else { return resolved }
        let (focalPixels, focus) = lensInPixels(camera, width: width, height: height)
        let maxBlur = Float(setting.maxBlur) * pointScale
        guard maxBlur >= 0.5 else { return resolved }
        // A tile is as wide as the gather's widest reach (the widest blur and a
        // pixel, stretched to the corners of a bladed iris), so the 3x3
        // neighborhood of tiles holds every pixel a tap can read.
        let blades = Double(max(0, camera.apertureBlades))
        let irisReach = blades >= 3 ? (Double.pi / (blades * sin(.pi / blades) * cos(.pi / blades))).squareRoot() : 1
        let k = max(8, Int((Double(maxBlur + 1) * irisReach).rounded(.up)) + 1)
        let tilesW = (width + k - 1) / k, tilesH = (height + k - 1) / k
        let taps = Float(resolveDofTaps(setting.quality))
        let lens = SIMD4<Float>(Float(camera.near), Float(camera.far), Float(focalPixels), Float(camera.aperture))
        let band = SIMD4<Float>(Float(focus), Float(setting.focusRange), maxBlur, Float(k))
        let shape = SIMD4<Float>(1 / Float(width), 1 / Float(height), taps, Float(max(0, camera.apertureBlades)))
        let layers = SIMD4<Float>(hidden != nil ? 1 : 0, 0, 0, 0)
        guard let coc = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let tileMax = acquireFilterTexture(width: tilesW, height: tilesH, pooled: pooled),
              let reach = acquireFilterTexture(width: tilesW, height: tilesH, pooled: pooled),
              let gathered = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let output = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return resolved }
        encodeEffectFragment("ollin_fx_lens_dof_prepass", inputs: [depth], output: coc,
                             params: [lens, band, shape], into: cb)
        // The hidden layer's blur sizes, from its own depth through the same
        // prepass; without a layer the frame stands in for it, and every hidden
        // tap reads as unknown.
        var hiddenColor = resolved, hiddenCoc = coc
        if let hidden, let layerCoc = acquireFilterTexture(width: width, height: height, pooled: pooled) {
            encodeEffectFragment("ollin_fx_lens_dof_prepass", inputs: [hidden.depth], output: layerCoc,
                                 params: [lens, band, shape], into: cb)
            hiddenColor = hidden.color
            hiddenCoc = layerCoc
        }
        // Small bright sources come out of the gather's input and are drawn after
        // it as discs of their own (`ollin_lens_sprites_collect`): one slot per
        // 2x2 block, in block order. The gather reads the flattened frame.
        let sprites = lensSpritesEnabled
            ? encodeLensSpriteCollect(resolved: resolved, coc: coc, width: width, height: height,
                                      params: [lens, band, shape], iris: .zero, into: cb, pooled: pooled)
            : nil
        let gatherBase = sprites?.flattened ?? resolved
        encodeEffectFragment("ollin_fx_lens_dof_tilemax", inputs: [coc, gatherBase], output: tileMax,
                             params: [lens, band], into: cb)
        encodeEffectFragment("ollin_fx_lens_dof_neighbormax", inputs: [tileMax], output: reach,
                             params: [band], into: cb)
        encodeEffectFragment("ollin_fx_lens_depth_of_field",
                             inputs: [gatherBase, coc, reach, hiddenColor, hiddenCoc], output: gathered,
                             params: [lens, band, shape, hidden != nil ? layers : layers], into: cb)
        encodeEffectFragment("ollin_fx_lens_dof_median", inputs: [gathered, coc], output: output,
                             params: [lens, band, shape], into: cb)
        if let sprites {
            encodeLensSprites(sprites, coc: coc, reach: reach, output: output,
                              params: [lens, band, shape], into: cb)
        }
        return output
    }

    /// The sprite collect: the frame's small bright sources taken out of a copy of
    /// the frame (`flattened`, what the gather then reads) and listed one slot per
    /// `block` x `block` pixels. `params` are the gather's first three rows; the
    /// fourth is the rule (the least blur a source needs, the ratio to its ring, the
    /// floor under the ring, the block) and the fifth, `iris`, what the draw needs
    /// of the law and the opening (the ramp law, the iris's turn, its cat's eye;
    /// zero for the canvas). nil when the pass cannot run, and the gather reads the
    /// frame itself.
    func encodeLensSpriteCollect(resolved: MTLTexture, coc: MTLTexture, width: Int, height: Int,
                                 params: [SIMD4<Float>], iris: SIMD4<Float>,
                                 into cb: MTLCommandBuffer, pooled: Bool)
        -> (flattened: MTLTexture, list: MTLBuffer, slots: Int, params: [SIMD4<Float>])? {
        let block = 2
        let blocksW = (width + block - 1) / block, blocksH = (height + block - 1) / block
        let slots = blocksW * blocksH
        let rule = SIMD4<Float>(3, 3, 0.05, Float(block))
        guard let flattened = acquireFilterTexture(width: width, height: height, pooled: pooled),
              let list = acquireLensSpriteBuffer(slots: slots, pooled: pooled),
              let collect = try? libraryComputePipeline("ollin_lens_sprites_collect"),
              let encoder = cb.makeComputeCommandEncoder() else { return nil }
        let all = params + [rule, iris]
        encoder.setComputePipelineState(collect)
        encoder.setTexture(resolved, index: 0)
        encoder.setTexture(coc, index: 1)
        encoder.setTexture(flattened, index: 2)
        encoder.setBuffer(list, offset: 0, index: 0)
        all.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 1) }
        let tew = collect.threadExecutionWidth
        let groupWidth = max(1, min(blocksW, tew))
        let groupHeight = max(1, min(blocksH, collect.maxTotalThreadsPerThreadgroup / tew))
        profile.computeDispatches += 1
        encoder.dispatchThreads(MTLSize(width: blocksW, height: blocksH, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: groupWidth, height: groupHeight, depth: 1))
        encoder.endEncoding()
        lastLensSprites = (list, slots, blocksW)
        return (flattened, list, slots, all)
    }

    /// The sprites drawn over the finished blur, one additive quad per slot (the
    /// empty ones clipped away), the disc cut by whatever stands nearer than its
    /// source (`ollin_lens_sprites_fragment` reads the blur map and the tiles).
    func encodeLensSprites(_ sprites: (flattened: MTLTexture, list: MTLBuffer, slots: Int, params: [SIMD4<Float>]),
                           coc: MTLTexture, reach: MTLTexture, output: MTLTexture,
                           params: [SIMD4<Float>], into cb: MTLCommandBuffer) {
        let format: MTLPixelFormat? = output.pixelFormat == linearFormat ? nil : output.pixelFormat
        guard let state = try? pipeline(.lensSprites(format: format)) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let enc = countedEncoder(cb, pass, caller: "lens sprites") else { return }
        enc.setRenderPipelineState(state)
        enc.setVertexBuffer(sprites.list, offset: 0, index: 0)
        sprites.params.withUnsafeBytes {
            enc.setVertexBytes($0.baseAddress!, length: $0.count, index: 1)
            enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1)
        }
        enc.setFragmentTexture(coc, index: 0)
        enc.setFragmentTexture(reach, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: sprites.slots)
        enc.endEncoding()
    }

    /// A sprite list of at least `slots` entries, from this frame's ring slot when
    /// pooled (grown on demand, never shrunk) or fresh for a headless frame.
    func acquireLensSpriteBuffer(slots: Int, pooled: Bool) -> MTLBuffer? {
        let length = max(1, slots) * MemoryLayout<OllinLensSprite>.stride
        guard pooled else { return device.makeBuffer(length: length, options: .storageModeShared) }
        if let entry = lensSpritePool[frameIndex], entry.slots >= slots { return entry.buffer }
        guard let buffer = device.makeBuffer(length: length, options: .storageModePrivate) else { return nil }
        lensSpritePool[frameIndex] = (buffer, slots)
        return buffer
    }
}
