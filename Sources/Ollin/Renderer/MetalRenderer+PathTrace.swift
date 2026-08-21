import Foundation
import Metal
import os
import simd
import COllinShaders   // OllinPathTraceUniforms / OllinLighting, shared with the shaders

// The offline path-traced export (`--path-traced`): the headless drivers set
// `pathTracing`, and the one-frame render then traces the mesh scene in full before
// the frame's own encoding, composites the traced layer in place of the raster mesh
// batches, and leaves every other path (2D, points, strands, raymarched fields, the
// live window) untouched. The trace runs in its own command buffers, committed and
// completed up front, for two reasons: the sample loop must not sit inside the
// frame's single command buffer (a minutes-long buffer risks the GPU watchdog and
// reports no progress), and the accel/offsets rings it fills are re-filled by the
// frame's own shadow pass afterwards, which is only safe once the trace is done.
extension MetalRenderer {

    /// Trace the frame's mesh scene into an accumulation layer (radiance sum + hit
    /// coverage) and a primary-depth texture, fully synchronously. Returns nil when
    /// the mode is off, the device cannot trace, or the frame has no traceable scene
    /// (no camera or no solid meshes); the caller then renders pure raster.
    func encodePathTracePass(_ drawer: Drawer, width: Int, height: Int)
        -> (color: MTLTexture, depth: MTLTexture, invSamples: Float)? {
        guard let settings = pathTracing else { return nil }
        guard rayTracedShadows else {
            Self.warnedNoPathTraceGPU.withLock { warned in
                if !warned {
                    print("Ollin: --path-traced needs a ray-tracing GPU; rendering the raster pipeline instead")
                    warned = true
                }
            }
            return nil
        }
        guard let camera = drawer.camera3D, !drawer.meshVertices.isEmpty,
              let meshBuffer = exportMeshBuffer(for: tracedMeshVertexCount(drawer)) else { return nil }

        // Upload the frame's mesh bytes now; the shadow pass later re-copies the
        // same bytes into the same buffer, which is idempotent.
        drawer.meshVertices.withUnsafeBytes { raw in
            meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }

        // Setup: bake the environment (cache-keyed, so the frame's own resolve
        // afterwards is free), fill the shaping tables, and build the acceleration
        // structure with the per-geometry finish table. One command buffer, waited,
        // so every kernel below samples completed resources.
        guard let setupCB = commandQueue.makeCommandBuffer() else { return nil }
        _ = resolveIBL(for: drawer.environment, commandBuffer: setupCB, blocking: true)
        var lighting = drawer.makeLighting()
        if lighting.enabled != 0, drawer.environment != nil, currentIBL != nil {
            lighting.iblEnabled = 1
            lighting.iblIntensity = Float(drawer.environment?.intensity ?? 1) * currentIBLNormalization
            lighting.iblMaxMip = Float(currentIBLMaxMip)
            lighting.iblRotation = Float(drawer.environment?.rotation ?? 0)
        } else {
            lighting.iblEnabled = 0
        }
        if lighting.enabled != 0, !drawer.usedIESProfiles.isEmpty {
            lighting.iesEnabled = ensureIESArray(drawer.usedIESProfiles) ? 1 : 0
        }
        if lighting.enabled != 0, !drawer.usedLightCookies.isEmpty {
            lighting.cookieEnabled = ensureCookieArray(drawer.usedLightCookies) ? 1 : 0
        }
        guard let built = buildShadowAccel(drawer, into: setupCB, meshBuffer: meshBuffer,
                                           pathTraceMats: true),
              let finishes = built.ptMats, let scene = built.ptScene,
              let pipeline = try? libraryComputePipeline("ollin_pt_trace") else { return nil }
        setupCB.commit()
        setupCB.waitUntilCompleted()

        // The environment-sampling tables (after the setup wait, so the equirect's
        // bake is complete before the reduction reads it). nil with no environment;
        // the kernel then integrates the flat ambient through the lobe strategy
        // alone, which handles a uniform field exactly.
        var envTables: MTLBuffer? = nil
        var envTableLOD: Float = 0
        if lighting.iblEnabled != 0, let equirect = currentIBL?.equirect {
            envTables = envSamplingTables(for: equirect)
            envTableLOD = max(0, log2(Float(equirect.width) / Float(Self.envGridW)))
        }

        let total = max(1, settings.samplesPerPixel)

        // The accumulation (radiance sum, hit count) and primary-depth layers.
        let accumDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        accumDesc.usage = [.shaderRead, .shaderWrite]
        accumDesc.storageMode = .private
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        depthDesc.usage = [.shaderRead, .shaderWrite]
        depthDesc.storageMode = .private
        guard let accum = device.makeTexture(descriptor: accumDesc),
              let depthTex = device.makeTexture(descriptor: depthDesc) else { return nil }

        // The denoiser's guide layers, filled by the trace itself: the first hit's
        // own color plus the running square of each sample's brightness (which is
        // what measures the grain), and the first hit's normal plus its distance.
        // With the filter off they are a single pixel the kernel never writes.
        let wantsGuides = settings.denoise && total > 1
        let guideDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: wantsGuides ? width : 1,
            height: wantsGuides ? height : 1, mipmapped: false)
        guideDesc.usage = [.shaderRead, .shaderWrite]
        guideDesc.storageMode = .private
        guard let guideColor = device.makeTexture(descriptor: guideDesc),
              let guideSurface = device.makeTexture(descriptor: guideDesc) else { return nil }

        // Per-dispatch constants. The camera frame comes from the same uniforms
        // builder the raster pass uses (unjittered), so the traced framing matches
        // the raster framing exactly for every projection kind.
        let viewport = SIMD2<Float>(Float(width), Float(height))
        let u3 = makeUniforms3D(drawer, camera: camera, viewport: viewport)
        var pt = OllinPathTraceUniforms()
        pt.inverseViewProjection = u3.inverseViewProjection
        pt.viewProjection = u3.projection * u3.view
        let eye = SIMD3<Float>(Float(camera.eye.x), Float(camera.eye.y), Float(camera.eye.z))
        pt.cameraPosition = SIMD4<Float>(eye, max(lighting.rtReflectionBias, 1e-4))
        let focus = camera.focusDistance ?? camera.eye.distance(to: camera.target)
        pt.lens = SIMD4<Float>(Float(camera.aperture), Float(max(focus, 1e-3)),
                               Float(max(0, camera.apertureBlades)), 0)
        pt.miss = SIMD4<Float>(lighting.ambient.x, lighting.ambient.y, lighting.ambient.z,
                               envTableLOD)
        pt.counts = SIMD4<UInt32>(UInt32(total), UInt32(max(1, settings.maxDepth)),
                                  envTables != nil ? UInt32(Self.envGridW) : 0,
                                  envTables != nil ? UInt32(Self.envGridH) : 0)
        // The texture-LOD ray cone: unproject the center pixel and its neighbor and
        // measure how far apart their rays start (the orthographic pixel footprint)
        // and how much their directions diverge per unit of travel (the perspective
        // pixel angle). Projection-agnostic, so every camera kind reads right.
        func unproject(_ px: Double, _ py: Double, _ z: Float) -> SIMD3<Float> {
            let ndc = SIMD4<Float>(Float(px / Double(width)) * 2 - 1,
                                   1 - Float(py / Double(height)) * 2, z, 1)
            let h = pt.inverseViewProjection * ndc
            return SIMD3(h.x, h.y, h.z) / h.w
        }
        let cx = Double(width) * 0.5, cy = Double(height) * 0.5
        let o0 = unproject(cx, cy, 0), o1 = unproject(cx + 1, cy, 0)
        let d0 = simd_normalize(unproject(cx, cy, 1) - o0)
        let d1 = simd_normalize(unproject(cx + 1, cy, 1) - o1)
        pt.cone = SIMD4<Float>(simd_length(o1 - o0), simd_length(d1 - d0), 0, 0)
        pt.meshLights = SIMD4<Float>(Float(scene.emissiveCount),
                                     max(scene.emissivePower, 1e-6),
                                     scene.anyTransmission ? 1 : 0,
                                     wantsGuides ? 1 : 0)

        let envTexture = (lighting.iblEnabled != 0 ? currentIBL?.equirect : nil) ?? whiteStandIn()
        let shapingArray = shapingStandIn()

        // The sample loop: one command buffer per chunk, waited, so a long render
        // reports progress and no single buffer runs long enough to trip the GPU
        // watchdog. The chunk size adapts toward roughly a second of GPU work.
        var done = 0
        var chunk = 2
        while done < total {
            let n = min(chunk, total - done)
            guard let cb = commandQueue.makeCommandBuffer(),
                  let enc = cb.makeComputeCommandEncoder() else { return nil }
            pt.window = SIMD4<UInt32>(UInt32(width), UInt32(height), UInt32(done), UInt32(n))
            enc.setComputePipelineState(pipeline)
            enc.setBytes(&pt, length: MemoryLayout<OllinPathTraceUniforms>.stride, index: 0)
            enc.setBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
            useTracedScene(enc, built.accel)
            enc.setAccelerationStructure(built.accel, bufferIndex: 3)
            enc.setBuffer(meshBuffer, offset: 0, index: 6)
            enc.setBuffer(built.offsets, offset: 0, index: 7)
            enc.setBuffer(finishes, offset: 0, index: 9)
            // The declared tables argument always binds something; the kernel only
            // reads it while `counts.z > 0` (real tables built).
            enc.setBuffer(envTables ?? ensureDummyGeoOffsets(), offset: 0, index: 10)
            enc.setBuffer(scene.emissive, offset: 0, index: 11)
            enc.setBuffer(scene.textures, offset: 0, index: 12)
            enc.useResources(scene.textureList, usage: .read)
            enc.setTexture(accum, index: 0)
            enc.setTexture(depthTex, index: 1)
            enc.setTexture(envTexture, index: 2)
            enc.setTexture(iesArrayTexture ?? shapingArray, index: 3)
            enc.setTexture(cookieArrayTexture ?? shapingArray, index: 4)
            enc.setTexture(guideColor, index: 5)
            enc.setTexture(guideSurface, index: 6)
            enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            done += n
            let gpuTime = cb.gpuEndTime - cb.gpuStartTime
            if gpuTime > 0 {
                chunk = max(1, min(64, Int(Double(n) * 1.0 / gpuTime + 0.5)))
            }
            if pathTraceReportsProgress {
                let line = String(format: "\r  path tracing %d/%d samples (%d%%)    ",
                                  done, total, done * 100 / total)
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
        if pathTraceReportsProgress {
            FileHandle.standardError.write(Data("\n".utf8))
        }
        if wantsGuides {
            encodePathTraceDenoise(accum: accum, guideColor: guideColor,
                                   guideSurface: guideSurface, width: width, height: height)
        }
        return (accum, depthTex, 1 / Float(total))
    }

    /// Filter the grain out of the finished accumulation, in place, so the composite
    /// reads exactly what it always did. The trace has already written what the
    /// filter needs to keep its edges: the first hit's own color and normal, its
    /// distance, and the spread of the samples at that pixel.
    ///
    /// The light is divided by the surface color first and multiplied back at the
    /// end, so nothing painted on a surface is ever blurred, only the light on it.
    /// Between the two, one wavelet pass runs five times over a pair of textures in
    /// turn, doubling the gap between the pixels it reads each time, which is what
    /// buys a wide reach for 25 reads. Every pass weighs each read by how well its
    /// normal, its distance, and its brightness agree with the middle pixel's, and
    /// the brightness width is the measured variance, so the whole filter fades out
    /// by itself as a render converges.
    private func encodePathTraceDenoise(accum: MTLTexture, guideColor: MTLTexture,
                                        guideSurface: MTLTexture, width: Int, height: Int) {
        guard let prepare = try? libraryComputePipeline("ollin_pt_denoise_prepare"),
              let atrous = try? libraryComputePipeline("ollin_pt_denoise_atrous"),
              let finish = try? libraryComputePipeline("ollin_pt_denoise_finish") else { return }
        let lightDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        lightDesc.usage = [.shaderRead, .shaderWrite]
        lightDesc.storageMode = .private
        // The two guide layers are read far more often than they are written, and
        // half precision is plenty for a direction and a distance that are only
        // ever compared against a neighbor's.
        let guideOutDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        guideOutDesc.usage = [.shaderRead, .shaderWrite]
        guideOutDesc.storageMode = .private
        guard let lightA = device.makeTexture(descriptor: lightDesc),
              let lightB = device.makeTexture(descriptor: lightDesc),
              let albedo = device.makeTexture(descriptor: guideOutDesc),
              let surface = device.makeTexture(descriptor: guideOutDesc),
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return }
        let grid = MTLSize(width: width, height: height, depth: 1)
        let group = MTLSize(width: 8, height: 8, depth: 1)

        enc.setComputePipelineState(prepare)
        enc.setTexture(accum, index: 0)
        enc.setTexture(guideColor, index: 1)
        enc.setTexture(guideSurface, index: 2)
        enc.setTexture(lightA, index: 3)
        enc.setTexture(albedo, index: 4)
        enc.setTexture(surface, index: 5)
        enc.dispatchThreads(grid, threadsPerThreadgroup: group)

        // Five passes reach 32 pixels out. The widths are the published defaults for
        // this filter: a brightness width of four standard deviations, a distance
        // width of a fiftieth of the distance itself (opened by the gap, since a
        // wider reach crosses more real depth), and a normal agreement raised to
        // 128, which holds the blur to one flat face.
        var source = lightA, target = lightB
        for pass in 0..<5 {
            enc.setComputePipelineState(atrous)
            var params = SIMD4<Float>(Float(1 << pass), 4, 0.02, 128)
            enc.setBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            enc.setTexture(source, index: 0)
            enc.setTexture(albedo, index: 1)
            enc.setTexture(surface, index: 2)
            enc.setTexture(target, index: 3)
            enc.dispatchThreads(grid, threadsPerThreadgroup: group)
            swap(&source, &target)
        }

        enc.setComputePipelineState(finish)
        enc.setTexture(source, index: 0)
        enc.setTexture(albedo, index: 1)
        enc.setTexture(accum, index: 2)
        enc.dispatchThreads(grid, threadsPerThreadgroup: group)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }

    /// Draw the traced layer into the geometry pass at the point the first solid
    /// mesh batch would have drawn: premultiplied source-over (silhouette edges
    /// blend; uncovered pixels leave the backdrop), depth-tested and writing the
    /// primary depth so the un-traced 3D kinds still occlude correctly. The batch
    /// loop re-sets pipeline and depth state per batch, so nothing leaks.
    func encodePathTraceComposite(_ layer: (color: MTLTexture, depth: MTLTexture, invSamples: Float),
                                  into encoder: MTLRenderCommandEncoder,
                                  uniforms3D: Uniforms3D?,
                                  depthFormat: MTLPixelFormat?, hasStencil: Bool) {
        var key = PipelineKey.pathTraceComposite(depth: depthFormat)
        if hasStencil { key.stencilFormat = .stencil8 }
        guard var u3 = uniforms3D, let pipe = try? pipeline(key) else { return }
        encoder.setRenderPipelineState(pipe)
        encoder.setDepthStencilState(depthTestState)
        encoder.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 0)
        var params = SIMD4<Float>(layer.invSamples, 0, 0, 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setFragmentTexture(layer.color, index: 0)
        encoder.setFragmentTexture(layer.depth, index: 1)
        profile.drawCalls += 1
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// The environment-sampling grid: coarse enough to build in a blink, fine
    /// enough that a sun spanning a couple of degrees still gets its own cells.
    private static let envGridW = 512
    private static let envGridH = 256

    /// Build (or fetch) the environment-sampling tables for one equirect: reduce it
    /// to a latitude-weighted luminance grid on the GPU, then lay out the row
    /// marginal CDF, the per-row conditional CDFs, and the solid-angle pdf per cell
    /// in one float buffer (the layout `ollin_pt_env_sample`/`_pdf` read). Cached by
    /// texture identity, so a sequence export pays the build once per environment.
    private func envSamplingTables(for equirect: MTLTexture) -> MTLBuffer? {
        let key = ObjectIdentifier(equirect)
        if let cached = ptEnvTableCache[key] { return cached }
        let W = Self.envGridW, H = Self.envGridH
        guard let reducePipe = try? libraryComputePipeline("ollin_pt_env_reduce"),
              let lumBuffer = device.makeBuffer(length: W * H * MemoryLayout<Float>.stride,
                                                options: .storageModeShared),
              let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return nil }
        var dims = SIMD4<UInt32>(UInt32(W), UInt32(H), 0, 0)
        enc.setComputePipelineState(reducePipe)
        enc.setBytes(&dims, length: MemoryLayout<SIMD4<UInt32>>.stride, index: 0)
        enc.setBuffer(lumBuffer, offset: 0, index: 1)
        enc.setTexture(equirect, index: 0)
        enc.dispatchThreads(MTLSize(width: W, height: H, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        let lum = lumBuffer.contents().bindMemory(to: Float.self, capacity: W * H)
        var tables = [Float](repeating: 0, count: H + 2 * H * W)
        var rowSums = [Double](repeating: 0, count: H)
        var total = 0.0
        for j in 0..<H {
            var s = 0.0
            for i in 0..<W { s += Double(lum[j * W + i]) }
            rowSums[j] = s
            total += s
        }
        guard total > 0 else { return nil }
        var cum = 0.0
        for j in 0..<H {
            cum += rowSums[j] / total
            tables[j] = Float(cum)
            var rowCum = 0.0
            for i in 0..<W {
                rowCum += Double(lum[j * W + i]) / rowSums[j]
                tables[H + j * W + i] = Float(rowCum)
            }
            // The grid's own solid-angle pdf: cell probability over the cell's
            // solid angle (the equirect area element, hence the sin latitude).
            let sinT = max(sin(.pi * (Double(j) + 0.5) / Double(H)), 1e-4)
            for i in 0..<W {
                let p = Double(lum[j * W + i]) / total
                tables[H + H * W + j * W + i] =
                    Float(p * Double(W * H) / (2 * Double.pi * Double.pi * sinT))
            }
        }
        // Guard both searches' top ends against float rounding.
        tables[H - 1] = 1
        for j in 0..<H { tables[H + j * W + W - 1] = 1 }
        let buffer = tables.withUnsafeBytes { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count,
                              options: .storageModeShared)
        }
        ptEnvTableCache[key] = buffer
        return buffer
    }

    /// One printed note per process when `--path-traced` runs on a GPU that cannot
    /// trace, so a sequence export says it once rather than once per frame.
    private static let warnedNoPathTraceGPU = OSAllocatedUnfairLock(initialState: false)
}
