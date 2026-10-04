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

/// The traced layer the geometry pass composites: the radiance sum with its hit
/// count, the primary depth, and how the sum becomes a mean, which is one reciprocal
/// for the whole frame under a fixed count and a per-pixel count (the statistics
/// layer's z channel) under adaptive sampling.
struct PathTracedLayer {
    let color: MTLTexture
    let depth: MTLTexture
    let invSamples: Float
    let counts: MTLTexture?
}

extension MetalRenderer {

    /// Trace the frame's mesh scene into an accumulation layer (radiance sum + hit
    /// coverage) and a primary-depth texture, fully synchronously. Returns nil when
    /// the mode is off, the device cannot trace, or the frame has no traceable scene
    /// (no camera or no solid meshes); the caller then renders pure raster.
    ///
    /// Under adaptive sampling (`PathTracing.noiseThreshold` above 0) the samples
    /// run in rounds at fixed indices: every pixel takes the minimum, then a check
    /// reads each pixel's own statistics and closes the settled ones, a pixel still
    /// open keeps its eight neighbors open, and the open pixels take the next eight
    /// samples, until the count is reached or nothing is open. The decisions are
    /// made at the same sample indices whatever the GPU's timing, and the kernel adds
    /// its samples onto the running sums in sample order, so the frame is the same
    /// bytes however the host cut the rounds into dispatches; `OllinApp.pathTraceChunkSize`
    /// forces one cut for the test that pins it.
    func encodePathTracePass(_ drawer: Drawer, width: Int, height: Int) -> PathTracedLayer? {
        pathTracedCopyBatches = []
        lastPathTraceReport = nil
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
        // A traceable scene is any solid mesh content: meshes drawn on their own, or
        // the copies of an instanced draw or a retained field. A scene made only of
        // copies is traced like any other; `buildShadowAccel` is the one that decides
        // what actually reaches the structure, and returns nil when nothing does.
        let hasCopies = drawer.batches.contains {
            $0.kind == .meshInstanced || $0.kind == .meshField
        }
        guard let camera = drawer.camera3D, !drawer.meshVertices.isEmpty || hasCopies,
              let meshBuffer = exportMeshBuffer(for: tracedMeshVertexCount(drawer)) else { return nil }

        // Upload the frame's mesh bytes now; the shadow pass later re-copies the
        // same bytes into the same buffer, which is idempotent.
        drawer.meshVertices.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            meshBuffer.contents().copyMemory(from: base, byteCount: raw.count)
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
        // Adaptive sampling: the samples every pixel takes before the first check,
        // and the step between checks. A fixed count is one round of the whole.
        let adaptive = settings.isAdaptive
        let minSamples = adaptive ? settings.firstCheck : total
        let checkStep = PathTracing.checkStep
        // The bound on what one bounce may add to a sample; the statistics layer
        // then also sums, per pixel, the light the bound took off.
        let bounded = settings.isBounded

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
        let wantsGuides = settings.denoises && total > 1
        let guideDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: wantsGuides ? width : 1,
            height: wantsGuides ? height : 1, mipmapped: false)
        guideDesc.usage = [.shaderRead, .shaderWrite]
        guideDesc.storageMode = .private
        guard let guideColor = device.makeTexture(descriptor: guideDesc),
              let guideSurface = device.makeTexture(descriptor: guideDesc) else { return nil }

        // The adaptive layers: each pixel's statistics (the sum of the squared
        // brightness it showed, the backdrop luma behind its misses, its own count),
        // the open flags the check writes, and the compacted list of open pixels the
        // dilation fills for the next dispatches to run over. Under a fixed count the
        // textures are a single pixel and the list a single entry, none of it touched.
        let statsDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: adaptive || bounded ? width : 1,
            height: adaptive || bounded ? height : 1, mipmapped: false)
        statsDesc.usage = [.shaderRead, .shaderWrite]
        statsDesc.storageMode = .private
        let flagDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint, width: adaptive ? width : 1,
            height: adaptive ? height : 1, mipmapped: false)
        flagDesc.usage = [.shaderRead, .shaderWrite]
        flagDesc.storageMode = .private
        guard let stats = device.makeTexture(descriptor: statsDesc),
              let openFlags = device.makeTexture(descriptor: flagDesc),
              let openList = device.makeBuffer(
                  length: MemoryLayout<UInt32>.stride * (adaptive ? width * height : 1),
                  options: .storageModePrivate),
              let openCount = device.makeBuffer(length: MemoryLayout<UInt32>.stride,
                                                options: .storageModeShared) else { return nil }
        var converge: MTLComputePipelineState? = nil
        var dilate: MTLComputePipelineState? = nil
        if adaptive {
            guard let c = try? libraryComputePipeline("ollin_pt_converge"),
                  let d = try? libraryComputePipeline("ollin_pt_dilate") else { return nil }
            converge = c
            dilate = d
        }

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
        var orthographic: Float = 0
        if case .orthographic = camera.projection { orthographic = 1 }
        pt.lens = SIMD4<Float>(Float(camera.aperture), Float(max(focus, 1e-3)),
                               Float(max(0, camera.apertureBlades)), orthographic)
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
        pt.cone = SIMD4<Float>(simd_length(o1 - o0), simd_length(d1 - d0),
                               bounded ? Float(settings.maxBounceLight) : 0, 0)
        pt.meshLights = SIMD4<Float>(Float(scene.emissiveCount),
                                     max(scene.emissivePower, 1e-6),
                                     scene.anyTransmission ? 1 : 0,
                                     wantsGuides ? 1 : 0)
        // The adaptive stop measures the brightness the viewer sees, so behind a
        // primary miss it needs the backdrop the composite leaves showing: the
        // environment along the ray when it draws as the skybox, else the clear
        // color (linear luma; the fragment reads the environment itself).
        let drawsSkybox = lighting.iblEnabled != 0 && (drawer.environment?.showsBackground ?? false)
        pt.adaptive = SIMD4<Float>(adaptive ? Float(settings.noiseThreshold) : 0,
                                   Float(minSamples),
                                   Float(drawer.backgroundColor.luminance),
                                   drawsSkybox ? 1 : 0)

        let envTexture = (lighting.iblEnabled != 0 ? currentIBL?.equirect : nil) ?? whiteStandIn()
        let shapingArray = shapingStandIn()

        // The sample loop: one command buffer per chunk, waited, so a long render
        // reports progress and no single buffer runs long enough to trip the GPU
        // watchdog. The chunk size adapts toward roughly a second of GPU work.
        // The BRDF LUT feeds the kernel's multiple-scattering energy compensation,
        // so it must be real before the first dispatch. The queue runs command
        // buffers in commit order, so a bake committed here is visible to every
        // trace chunk below without a wait.
        if iblBRDFLUT == nil, let lutCB = commandQueue.makeCommandBuffer() {
            ensureBRDFLUT(commandBuffer: lutCB)
            lutCB.commit()
        }
        // Under adaptive sampling the loop also runs in rounds: the first ends at the
        // minimum and each later one `checkStep` on, a check between rounds closes
        // the settled pixels and lists the open ones, and from then on a dispatch
        // runs over that list (one thread per open pixel) rather than the grid, so a
        // settled pixel costs nothing. The round's samples are still cut into
        // dispatches by GPU time. The sum of open pixels times the samples each round
        // adds is the frame's total, so the mean count needs no readback of the layer.
        let forcedChunk = OllinApp.pathTraceChunkSize
        var done = 0
        var chunk = forcedChunk ?? 2
        var roundEnd = minSamples
        var openPixels = width * height
        var compacted = false
        var samplesTaken = 0.0
        let grid = MTLSize(width: width, height: height, depth: 1)
        let group = MTLSize(width: 8, height: 8, depth: 1)
        while done < total {
            let n = min(chunk, roundEnd - done)
            guard let cb = commandQueue.makeCommandBuffer(),
                  let enc = cb.makeComputeCommandEncoder() else { return nil }
            pt.window = SIMD4<UInt32>(UInt32(width), UInt32(height), UInt32(done), UInt32(n))
            pt.open = SIMD4<UInt32>(compacted ? UInt32(openPixels) : 0, 0, 0, 0)
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
            enc.setTexture(iblBRDFLUT, index: 7)
            enc.setTexture(stats, index: 8)
            enc.setBuffer(openList, offset: 0, index: 13)
            if compacted {
                enc.dispatchThreads(MTLSize(width: openPixels, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            } else {
                enc.dispatchThreads(grid, threadsPerThreadgroup: group)
            }
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            done += n
            samplesTaken += Double(openPixels) * Double(n)
            let gpuTime = cb.gpuEndTime - cb.gpuStartTime
            if forcedChunk == nil, gpuTime > 0 {
                chunk = max(1, min(64, Int(Double(n) * 1.0 / gpuTime + 0.5)))
            }
            if pathTraceReportsProgress {
                let settled = adaptive
                    ? String(format: ", %d%% of pixels settled", 100 - openPixels * 100 / max(1, width * height))
                    : ""
                let line = String(format: "\r  path tracing %d/%d samples (%d%%)%@    ",
                                  done, total, done * 100 / total, settled)
                FileHandle.standardError.write(Data(line.utf8))
            }
            // The end of a round: read every pixel's statistics, close the settled
            // ones, keep an open pixel's neighbors open, list and count what is
            // left. Nothing open ends the frame here; the pixels all hold their
            // counts.
            if adaptive, done == roundEnd, done < total,
               let converge, let dilate {
                guard let checkCB = commandQueue.makeCommandBuffer(),
                      let check = checkCB.makeComputeCommandEncoder() else { return nil }
                openCount.contents().storeBytes(of: UInt32(0), as: UInt32.self)
                var threshold = SIMD4<Float>(Float(settings.noiseThreshold), 0, 0, 0)
                check.setComputePipelineState(converge)
                check.setBytes(&threshold, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                check.setTexture(accum, index: 0)
                check.setTexture(stats, index: 1)
                check.setTexture(openFlags, index: 2)
                check.dispatchThreads(grid, threadsPerThreadgroup: group)
                check.setComputePipelineState(dilate)
                check.setBuffer(openList, offset: 0, index: 0)
                check.setBuffer(openCount, offset: 0, index: 1)
                check.setTexture(openFlags, index: 0)
                check.dispatchThreads(grid, threadsPerThreadgroup: group)
                check.endEncoding()
                checkCB.commit()
                checkCB.waitUntilCompleted()
                openPixels = min(width * height, Int(openCount.contents().load(as: UInt32.self)))
                compacted = true
                if openPixels == 0 { break }
                roundEnd = min(total, roundEnd + checkStep)
            }
        }
        if pathTraceReportsProgress {
            FileHandle.standardError.write(Data("\n".utf8))
        }
        // What the bound took, read before the filter rewrites the accumulation.
        let lightDropped = bounded
            ? boundedLightShare(accum: accum, stats: stats, width: width, height: height) : nil
        if wantsGuides {
            encodePathTraceDenoise(accum: accum, guideColor: guideColor,
                                   guideSurface: guideSurface, width: width, height: height)
        }
        lastPathTraceReport = PathTraceReport(
            settings: settings, minSamplesPerPixel: minSamples,
            meanSamplesPerPixel: adaptive ? samplesTaken / Double(max(1, width * height)) : nil,
            lightDropped: lightDropped)
        return PathTracedLayer(color: accum, depth: depthTex, invSamples: 1 / Float(total),
                               counts: adaptive ? stats : nil)
    }

    /// The share of the frame's light the bounce bound took off: the luma the kernel
    /// summed per pixel as it bounded each sample (the statistics layer's fourth
    /// channel) against the luma the accumulation kept, both read back once the
    /// trace is done. nil when the readback cannot be made.
    private func boundedLightShare(accum: MTLTexture, stats: MTLTexture,
                                   width: Int, height: Int) -> Double? {
        let bytesPerRow = width * MemoryLayout<SIMD4<Float>>.stride
        let length = bytesPerRow * height
        guard let kept = device.makeBuffer(length: length, options: .storageModeShared),
              let taken = device.makeBuffer(length: length, options: .storageModeShared),
              let cb = commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        let size = MTLSize(width: width, height: height, depth: 1)
        let origin = MTLOrigin(x: 0, y: 0, z: 0)
        blit.copy(from: accum, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size,
                  to: kept, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: length)
        blit.copy(from: stats, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size,
                  to: taken, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: length)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        let n = width * height
        let k = kept.contents().bindMemory(to: SIMD4<Float>.self, capacity: n)
        let t = taken.contents().bindMemory(to: SIMD4<Float>.self, capacity: n)
        var keptLuma = 0.0, droppedLuma = 0.0
        for i in 0 ..< n {
            keptLuma += Double(0.2126 * k[i].x + 0.7152 * k[i].y + 0.0722 * k[i].z)
            droppedLuma += Double(t[i].w)
        }
        let total = keptLuma + droppedLuma
        return total > 0 ? droppedLuma / total : 0
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
    func encodePathTraceComposite(_ layer: PathTracedLayer,
                                  into encoder: MTLRenderCommandEncoder,
                                  uniforms3D: Uniforms3D?,
                                  depthFormat: MTLPixelFormat?, hasStencil: Bool) {
        var key = PipelineKey.pathTraceComposite(depth: depthFormat)
        if hasStencil { key.stencilFormat = .stencil8 }
        guard var u3 = uniforms3D, let pipe = try? pipeline(key) else { return }
        encoder.setRenderPipelineState(pipe)
        encoder.setDepthStencilState(depthTestState)
        encoder.setFragmentBytes(&u3, length: MemoryLayout<Uniforms3D>.stride, index: 0)
        // Under a fixed count every pixel divides by the same reciprocal; under
        // adaptive sampling each divides by its own count, read from the layer.
        var params = SIMD4<Float>(layer.invSamples, layer.counts != nil ? 1 : 0, 0, 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setFragmentTexture(layer.color, index: 0)
        encoder.setFragmentTexture(layer.depth, index: 1)
        encoder.setFragmentTexture(layer.counts ?? whiteStandIn(), index: 2)
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
        if let cached = ptEnvTableCache[key] { return cached.tables }
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
        if let buffer {
            if ptEnvTableCache.count >= Self.maxEnvironmentTables { ptEnvTableCache.removeAll() }
            ptEnvTableCache[key] = (texture: equirect, tables: buffer)
        }
        return buffer
    }

    /// One printed note per process when `--path-traced` runs on a GPU that cannot
    /// trace, so a sequence export says it once rather than once per frame.
    private static let warnedNoPathTraceGPU = OSAllocatedUnfairLock(initialState: false)
}
