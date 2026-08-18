import Metal
import simd
import COllinShaders   // the shared CPU/GPU structs (OllinCausticsUniforms, OllinPhoton, ...)

// The caustics chain (`caustics()`): adaptive anisotropic photon scattering on a
// ray-tracing device. The pass order per frame, all ahead of the main geometry
// pass in the same command buffer:
//
//   1. G-buffer: re-encode the canvas's solid meshes into world normal +
//      metal/rough + baked albedo + depth (the reflection G-buffer's recipe plus
//      the color the splats shade against).
//   2. Emission plan (compute): update the light-space ray-density map from last
//      frame's feedback (live), turn it into per-texel leaf ray counts normalized
//      to the budget, and build the quadtree task buffer over them.
//   3. Photon trace (compute): one thread per ray; walk the quadtree to an
//      emission cell, trace the photon through glass and polished metal with
//      photon differentials, deposit on the first rough surface, report feedback.
//   4. Splat: draw every photon as an anisotropic elliptical footprint,
//      additively, depth-tested against the G-buffer, shaded with the receiver's
//      own attributes.
//   5. Temporal resolve (live): reproject + clamp + EMA, writing the variance the
//      next frame's photons sample back into the feedback loop. The headless path
//      returns the raw splat layer instead (uniform emission, no history), so an
//      export is a pure function of the frame.
//
// The lit mesh fragments then add the resolved layer by screen position
// (fragment texture 25, `lighting.causticsEnabled`). Everything here is inert
// (and the frame byte-identical) unless `caustics()` is on, the device traces,
// and a punctual light plus a casting material exist.

extension MetalRenderer {

    /// Whether this frame wants the caustics chain at all: the opt-in, a tracing
    /// device, a camera, a punctual light to emit from, and at least one canvas
    /// mesh whose material casts (transmits, or mirrors as a polished metal).
    func causticsWanted(_ drawer: Drawer) -> Bool {
        guard drawer.causticsEnabled, rayTracedShadows, drawer.camera3D != nil,
              drawer.lights.contains(where: {
                  $0.kind == .directional || $0.kind == .point || $0.kind == .spot })
        else { return false }
        return drawer.batches.contains { batch in
            batch.kind == .mesh3D && batch.target == nil
                && !batch.meshWireframe && !batch.meshGrid
                && Self.causticCasterFinish(batch.finish)
        }
    }

    /// Whether a material finish makes its mesh a caustic caster: it transmits
    /// (glass), or it is a mirror-polished metal.
    static func causticCasterFinish(_ f: OllinMaterial) -> Bool {
        f.transmission > 0 || (f.metallic > 0.5 && f.roughness < 0.25)
    }

    /// The emission-map edge for a quality tier. Power of two (the quadtree's grid).
    private func resolveCausticsMapEdge(_ quality: RenderQuality) -> Int {
        switch quality == .default ? automaticQuality : quality {
        case .performance: return 128
        case .default: return 256
        case .detail: return 512
        }
    }

    /// The per-frame ray budget for a quality tier, hardware-relative like the
    /// shadow ray counts (software ray tracing on M1/M2 traces each ray ~5-10x
    /// slower, so its tiers sit one step down).
    private func resolveCausticsBudget(_ quality: RenderQuality) -> Int {
        switch quality == .default ? automaticQuality : quality {
        case .performance: return hasHardwareRayTracing ? 32_768 : 16_384
        case .default: return hasHardwareRayTracing ? 131_072 : 65_536
        case .detail: return hasHardwareRayTracing ? 524_288 : 262_144
        }
    }

    /// EMA history weight for the live temporal resolve (the reflection temporal's tiers).
    private func resolveCausticsAlpha() -> Double {
        switch automaticQuality {
        case .performance: return 0.85
        case .default: return 0.9
        case .detail: return 0.94
        }
    }

    /// The deferred caustics pre-pass (main canvas): G-buffer, emission plan,
    /// photon trace, splat, and (live) the temporal resolve. Returns the texture
    /// the lit mesh fragments add by screen position, or nil when the frame has
    /// no active caustics (the caller then leaves `causticsEnabled` 0 and the
    /// carriers' branch untaken, byte-identical).
    ///
    /// `supersample` selects the historyless form (headless/export): uniform
    /// emission at the full budget, no history slot touched, so a single exported
    /// frame is a pure function of the frame and a live recording's off-screen
    /// re-render can't step the on-screen adaptation.
    func encodeCausticsPass(_ drawer: Drawer, into cb: MTLCommandBuffer,
                            meshBuffer: MTLBuffer?,
                            causticAccel: MTLAccelerationStructure?,
                            causticGeoOffsets: MTLBuffer?,
                            causticGeoMats: MTLBuffer?,
                            width: Int, height: Int,
                            supersample: Bool, pooled: Bool,
                            taaJitter: SIMD2<Float> = .zero) -> MTLTexture? {
        guard let camera = drawer.camera3D, let meshBuffer,
              let accel = causticAccel, let geoOffsets = causticGeoOffsets,
              let geoMats = causticGeoMats, causticsWanted(drawer)
        else { return nil }
        var lighting = drawer.makeLighting()
        guard lighting.enabled != 0 else { return nil }

        // Same-frame repeat (live): the history already holds this frame's resolve.
        if !supersample, statefulEncodeIsRepeat,
           let slot = causticsHistory, slot.valid, slot.w == width, slot.h == height {
            return slot.flipped ? slot.b : slot.a
        }

        // The caster light: the shadow caster if it is punctual, else the shadow
        // system's own priority over the packed lights (directional, spot, point).
        let packed = withUnsafeBytes(of: lighting.lights) { raw in
            Array(raw.bindMemory(to: OllinLight.self).prefix(Int(lighting.lightCount)))
        }
        var casterIndex = -1
        if lighting.shadowLight >= 0, Int(lighting.shadowLight) < packed.count,
           packed[Int(lighting.shadowLight)].kind <= 2 {
            casterIndex = Int(lighting.shadowLight)
        } else {
            for wanted: Int32 in [0, 2, 1] {
                if let i = packed.firstIndex(where: { $0.kind == wanted }) {
                    casterIndex = i
                    break
                }
            }
        }
        guard casterIndex >= 0 else { return nil }
        let caster = packed[casterIndex]

        // The specular casters' world bounds, for fitting the emission frame.
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let meshVertices = drawer.meshVertices
        let batches = drawer.batches
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D, batch.target == nil,
                  !batch.meshWireframe, !batch.meshGrid,
                  Self.causticCasterFinish(batch.finish) else { continue }
            let end = i + 1 < batches.count ? batches[i + 1].meshStart : meshVertices.count
            for v in batch.meshStart..<end {
                let p = meshVertices[v].position
                lo = simd_min(lo, SIMD3(p.x, p.y, p.z))
                hi = simd_max(hi, SIMD3(p.x, p.y, p.z))
            }
        }
        guard lo.x <= hi.x else { return nil }
        let center = (lo + hi) * 0.5
        let radius = max(simd_length(hi - lo) * 0.5, 1e-4)

        // Quality, sized state, and the frame's uniforms.
        let quality = drawer.causticsQualitySetting
        let edge = resolveCausticsMapEdge(quality)
        let budget = resolveCausticsBudget(quality)
        let depth = Int(log2(Double(edge)).rounded())
        let treeNodes = ((1 << (2 * depth)) - 1) / 3
        ensureCausticsBuffers(edge: edge, budget: budget, treeNodes: treeNodes, into: cb)
        guard let density = causticsDensity, let feedback = causticsFeedback,
              let totals = causticsTotals, let quadtree = causticsQuadtree,
              let leafCounts = causticsLeafCounts, let photons = causticsPhotons,
              let args = causticsArgs else { return nil }

        var cu = OllinCausticsUniforms()
        let aspect = height > 0 ? Double(width) / Double(height) : 1
        let u3 = makeUniforms3D(drawer, camera: camera,
                                viewport: SIMD2(Float(width), Float(height)),
                                jitter: taaJitter)
        cu.viewProjection = u3.projection * u3.view
        func xyz(_ v: simd_float4) -> SIMD3<Float> { SIMD3(v.x, v.y, v.z) }
        if caster.kind == 0 {
            // Directional: an orthographic patch fitted around the casters,
            // upstream of them along the light's travel direction. The packed
            // direction points *to* the light, so the photons travel opposite it.
            let dir = simd_normalize(-xyz(caster.direction))
            let refUp: SIMD3<Float> = abs(dir.y) > 0.95 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
            let right = simd_normalize(simd_cross(refUp, dir))
            let up = simd_cross(dir, right)
            let ext = radius * 1.1
            let origin = center - dir * (radius * 2 + 1) - right * ext - up * ext
            cu.emitOrigin = SIMD4(origin, 0)
            cu.emitRight = SIMD4(right, ext * 2)
            cu.emitUp = SIMD4(up, ext * 2)
            cu.emitDir = SIMD4(dir, 0)
        } else {
            // Point / spot: a cone of directions from the light's position. A spot
            // emits over its own cone; a point over the cone subtending the
            // casters' bounds (padded), so no ray is wasted on empty sky.
            let pos = xyz(caster.position)
            var axis: SIMD3<Float>
            var halfAngle: Float
            if caster.kind == 2 {
                axis = simd_normalize(xyz(caster.direction))
                halfAngle = acos(min(max(caster.cosOuter, -1), 1))
            } else {
                let toCenter = center - pos
                let dist = simd_length(toCenter)
                axis = dist > 1e-4 ? toCenter / dist : SIMD3(0, -1, 0)
                halfAngle = dist > radius ? asin(min(radius / dist, 1)) * 1.15
                                          : Float.pi * 0.5
            }
            let refUp: SIMD3<Float> = abs(axis.y) > 0.95 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
            let right = simd_normalize(simd_cross(refUp, axis))
            let up = simd_cross(axis, right)
            cu.emitOrigin = SIMD4(pos, Float(caster.kind == 2 ? 2 : 1))
            cu.emitRight = SIMD4(right, 0)
            cu.emitUp = SIMD4(up, 0)
            cu.emitDir = SIMD4(axis, min(halfAngle, Float.pi * 0.5))
        }
        cu.lightColor = SIMD4(caster.color.x, caster.color.y, caster.color.z,
                              caster.kind == 2 ? caster.cosInner : 0)
        let eps = max(lighting.rtReflectionBias, lighting.sceneScale * 5e-4, 1e-4)
        // z = the footprint half-axis cap in screen pixels (a stretched-thin
        // footprint past it is culled, not clamped); w = the min width, px.
        cu.lightParams = SIMD4(caster.kind == 2 ? caster.cosOuter : 0, eps, 48, 1)
        cu.feedback = SIMD4(48, 4, 0.35, 0)
        cu.params = SIMD4(Float(drawer.causticsIntensity), Float(drawer.causticsDispersion),
                          0, 0.004)
        cu.counts = SIMD4(UInt32(edge), UInt32(depth), UInt32(budget), 8)
        let uniformEmission = supersample || !causticsDensityValid
        cu.counts2 = SIMD4(UInt32(budget), frameComputeUniforms.frameCount,
                           uniformEmission ? 1 : 0, UInt32(treeNodes))
        cu.screen = SIMD4(Float(width), Float(height), 1 / Float(width), 1 / Float(height))

        // 1. The G-buffer (normal + metal/rough + albedo + depth), the reflection
        // G-buffer's batch walk with the extra attachment.
        if causticsGBuf == nil || causticsGBuf!.w != width || causticsGBuf!.h != height {
            guard let normal = makeFilterTexture(width: width, height: height),
                  let material = makeFilterTexture(width: width, height: height),
                  let albedo = makeFilterTexture(width: width, height: height),
                  let gdepth = makeDepthResolve(width: width, height: height) else { return nil }
            causticsGBuf = (normal, material, albedo, gdepth, width, height)
        }
        guard let gbuf = causticsGBuf,
              let gbufPipe = try? pipeline(.causticsGBuffer(depth: depthPixelFormat)),
              let splatPipe = try? pipeline(.causticsSplat),
              let target = acquireFilterTexture(width: width, height: height, pooled: pooled)
        else { return nil }

        let pass = MTLRenderPassDescriptor()
        for (i, tex) in [gbuf.normal, gbuf.material, gbuf.albedo].enumerated() {
            pass.colorAttachments[i].texture = tex
            pass.colorAttachments[i].loadAction = .clear
            pass.colorAttachments[i].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[i].storeAction = .store
        }
        pass.depthAttachment.texture = gbuf.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .store
        guard let enc = countedEncoder(cb, pass) else { return nil }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(width),
                                    height: Double(height), znear: 0, zfar: 1))
        enc.setRenderPipelineState(gbufPipe)
        enc.setDepthStencilState(depthTestState)
        var u3v = u3
        enc.setVertexBytes(&u3v, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        let meshStride = MemoryLayout<OllinMeshVertex>.stride
        for i in batches.indices {
            let batch = batches[i]
            guard batch.kind == .mesh3D, batch.target == nil,
                  !batch.meshWireframe, !batch.meshGrid else { continue }
            let end = i + 1 < batches.count ? batches[i + 1].meshStart : meshVertices.count
            let count = end - batch.meshStart
            guard count > 0 else { continue }
            enc.setVertexBuffer(meshBuffer, offset: batch.meshStart * meshStride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
        enc.endEncoding()

        // 2 + 3. The emission plan and the photon trace (compute).
        guard let resetPipe = try? libraryComputePipeline("ollin_caustics_reset_args"),
              let leafPipe = try? libraryComputePipeline("ollin_caustics_leafcounts"),
              let treePipe = try? libraryComputePipeline("ollin_caustics_quadtree"),
              let tracePipe = try? libraryComputePipeline("ollin_caustics_trace"),
              let clampPipe = try? libraryComputePipeline("ollin_caustics_clamp_args"),
              let compute = cb.makeComputeCommandEncoder() else { return nil }
        // Last frame's resolved layer, whose alpha the photons read as the
        // temporal variance. Before any history exists the splat target stands in
        // (a valid texture; the first frame's variance read is noise the density
        // clamp bounds and the loop corrects on the next frame).
        let prevResolved: MTLTexture = {
            if let slot = causticsHistory, slot.valid, slot.w == width, slot.h == height {
                return slot.flipped ? slot.b : slot.a
            }
            return target
        }()
        compute.setComputePipelineState(resetPipe)
        compute.setBuffer(args, offset: 0, index: 0)
        compute.setBuffer(totals, offset: 0, index: 2)
        compute.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        withUnsafeBytes(of: &cu) { raw in
            compute.setBytes(raw.baseAddress!, length: raw.count, index: 3)
        }
        let mapGroup = MTLSize(width: 8, height: 8, depth: 1)
        if !uniformEmission, let densityPipe = try? libraryComputePipeline("ollin_caustics_density") {
            compute.setComputePipelineState(densityPipe)
            compute.setBuffer(density, offset: 0, index: 0)
            compute.setBuffer(feedback, offset: 0, index: 1)
            compute.setBuffer(totals, offset: 0, index: 2)
            compute.dispatchThreads(MTLSize(width: edge, height: edge, depth: 1),
                                    threadsPerThreadgroup: mapGroup)
        }
        compute.setComputePipelineState(leafPipe)
        compute.setBuffer(density, offset: 0, index: 0)
        compute.setBuffer(leafCounts, offset: 0, index: 1)
        compute.setBuffer(totals, offset: 0, index: 2)
        compute.dispatchThreads(MTLSize(width: edge, height: edge, depth: 1),
                                threadsPerThreadgroup: mapGroup)
        compute.setComputePipelineState(treePipe)
        compute.setBuffer(quadtree, offset: 0, index: 0)
        compute.setBuffer(leafCounts, offset: 0, index: 1)
        withUnsafeBytes(of: &cu) { raw in
            compute.setBytes(raw.baseAddress!, length: raw.count, index: 2)
        }
        for level in stride(from: depth - 1, through: 0, by: -1) {
            var l = UInt32(level)
            compute.setBytes(&l, length: MemoryLayout<UInt32>.stride, index: 4)
            let levelEdge = 1 << level
            compute.dispatchThreads(MTLSize(width: levelEdge, height: levelEdge, depth: 1),
                                    threadsPerThreadgroup: mapGroup)
        }
        compute.setComputePipelineState(tracePipe)
        withUnsafeBytes(of: &cu) { raw in
            compute.setBytes(raw.baseAddress!, length: raw.count, index: 0)
        }
        compute.setBuffer(quadtree, offset: 0, index: 1)
        compute.setBuffer(leafCounts, offset: 0, index: 2)
        compute.setBuffer(photons, offset: 0, index: 3)
        compute.setBuffer(args, offset: 0, index: 4)
        compute.setBuffer(feedback, offset: 0, index: 5)
        compute.setBuffer(meshBuffer, offset: 0, index: 6)
        compute.setBuffer(geoOffsets, offset: 0, index: 7)
        compute.useResource(accel, usage: .read)
        compute.setAccelerationStructure(accel, bufferIndex: 8)
        compute.setBuffer(geoMats, offset: 0, index: 9)
        compute.setTexture(prevResolved, index: 0)
        compute.dispatchThreads(MTLSize(width: budget, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        compute.setComputePipelineState(clampPipe)
        compute.setBuffer(args, offset: 0, index: 0)
        withUnsafeBytes(of: &cu) { raw in
            compute.setBytes(raw.baseAddress!, length: raw.count, index: 3)
        }
        compute.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        compute.endEncoding()
        causticsDensityValid = !supersample

        // 4. The splat: every photon as an additive elliptical footprint.
        let splatPass = MTLRenderPassDescriptor()
        splatPass.colorAttachments[0].texture = target
        splatPass.colorAttachments[0].loadAction = .clear
        splatPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        splatPass.colorAttachments[0].storeAction = .store
        guard let splat = countedEncoder(cb, splatPass) else { return nil }
        splat.setRenderPipelineState(splatPipe)
        splat.setVertexBuffer(photons, offset: 0, index: 0)
        withUnsafeBytes(of: &cu) { raw in
            splat.setVertexBytes(raw.baseAddress!, length: raw.count, index: 1)
            splat.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 1)
        }
        splat.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 2)
        splat.setFragmentTexture(gbuf.normal, index: 0)
        splat.setFragmentTexture(gbuf.material, index: 1)
        splat.setFragmentTexture(gbuf.albedo, index: 2)
        splat.setFragmentTexture(gbuf.depth, index: 3)
        splat.drawPrimitives(type: .triangleStrip, indirectBuffer: args, indirectBufferOffset: 0)
        splat.endEncoding()

        // Headless/export: the raw layer IS the frame's caustics (no history).
        if supersample { return target }

        // 5. The temporal resolve (live): reproject + clamp + EMA into the back,
        // writing the variance the next frame's photons read (the loop's close).
        let slot: SSRHistorySlot
        if let existing = causticsHistory, existing.w == width, existing.h == height {
            slot = existing
        } else {
            guard let a = makeFloatResolve(width: width, height: height),
                  let b = makeFloatResolve(width: width, height: height) else { return target }
            let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            clearFloatTexture(a, color: clear, into: cb)
            clearFloatTexture(b, color: clear, into: cb)
            slot = SSRHistorySlot(a: a, b: b, w: width, h: height)
            causticsHistory = slot
        }
        let front = slot.flipped ? slot.b : slot.a
        let back = slot.flipped ? slot.a : slot.b
        let viewProjection = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix
        let invVP = simd_inverse(viewProjection)
        let alpha = slot.valid ? Float(resolveCausticsAlpha()) : 0
        var params = [SIMD4<Float>](repeating: .zero, count: 12)
        params[0] = SIMD4(1 / Float(width), 1 / Float(height), alpha, slot.valid ? 1 : 0)
        params[4] = invVP.columns.0; params[5] = invVP.columns.1
        params[6] = invVP.columns.2; params[7] = invVP.columns.3
        let pv = slot.previousViewProjection
        params[8] = pv.columns.0; params[9] = pv.columns.1
        params[10] = pv.columns.2; params[11] = pv.columns.3
        encodeEffectFragment("ollin_caustics_temporal", inputs: [target, gbuf.depth, front],
                             output: back, params: params, into: cb)
        slot.previousViewProjection = viewProjection
        slot.valid = true
        slot.flipped.toggle()
        return back
    }

    /// (Re)allocate the caustics buffers for an emission-map size and ray budget,
    /// zero-filling the stateful ones. GPU-private throughout: every producer and
    /// consumer is on the one queue, so frames serialize and nothing rides the ring.
    private func ensureCausticsBuffers(edge: Int, budget: Int, treeNodes: Int,
                                       into cb: MTLCommandBuffer) {
        let texels = edge * edge
        if causticsMapEdge == edge, causticsPhotonCapacity == budget,
           causticsDensity != nil, causticsPhotons != nil { return }
        causticsMapEdge = edge
        causticsPhotonCapacity = budget
        causticsDensityValid = false
        causticsDensity = device.makeBuffer(length: texels * 4, options: .storageModePrivate)
        causticsFeedback = device.makeBuffer(length: texels * 16, options: .storageModePrivate)
        causticsTotals = device.makeBuffer(length: 16, options: .storageModePrivate)
        causticsQuadtree = device.makeBuffer(length: max(1, treeNodes) * 16,
                                             options: .storageModePrivate)
        causticsLeafCounts = device.makeBuffer(length: texels * 4, options: .storageModePrivate)
        causticsPhotons = device.makeBuffer(length: budget * MemoryLayout<OllinPhoton>.stride,
                                            options: .storageModePrivate)
        causticsArgs = device.makeBuffer(length: 16, options: .storageModePrivate)
        if let blit = cb.makeBlitCommandEncoder() {
            for buffer in [causticsDensity, causticsFeedback, causticsTotals] {
                if let buffer { blit.fill(buffer: buffer, range: 0..<buffer.length, value: 0) }
            }
            blit.endEncoding()
        }
    }
}
