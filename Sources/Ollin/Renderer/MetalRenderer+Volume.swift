import Metal
import simd
import COllinShaders

// Volumes (`drawVolume`): density grids composited over a pass's finished
// geometry. The march (ShaderVolume.metal) needs the depth of every solid in
// the frame, and the geometry pass cannot read its own depth attachment, so a
// volume is not a batch in the call-ordered list: it draws after the pass ends,
// over the pass's resolved color, reading the resolved depth. That is also the
// order a translucent medium wants: a solid drawn after the volume in code still
// sits inside it, veiled by what lies in front of it.

/// What the geometry pass resolved for the volumes that follow it: the lighting
/// every light set shades against, the shadow map it was rendered with, and the
/// camera (with the pass's own sub-pixel jitter), so the march lines up with
/// the depth it reads and lights exactly as the solids did.
struct VolumePassLight {
    var lighting: [Int: OllinLighting]
    var shadowMap: MTLTexture?
    var uniforms3D: Uniforms3D
}

/// A light-transmittance grid's identity: the samples, where they sit, the
/// medium's thickness, and the light. A change to any of them is a new grid
/// (computed into a new texture, never over one a frame in flight may read).
struct VolumeLightKey: Hashable {
    var content: UInt64
    var model: [Float]
    var density: Float
    var lightRay: SIMD4<Float>
}

extension MetalRenderer {
    /// The step budget per view ray: enough for a 128-sample grid crossed
    /// corner to corner at two steps a sample, with room to spare.
    static let volumeMaxSteps: Float = 768
    /// The finest light-transmittance grid per axis; a finer density grid is
    /// read at this resolution for its self-shadow (a shadow is smoother than
    /// the medium casting it).
    static let volumeLightMaxSamples = 128

    /// Note what this pass resolved, for the volumes drawn into it. Called from
    /// `encode` once its lighting is packed; a pass with no volume keeps nothing.
    func keepVolumeLight(_ drawer: Drawer, target: RenderTarget?, lighting: OllinLighting,
                         sets: [Int: OllinLighting], shadowMap: MTLTexture?,
                         uniforms3D: Uniforms3D?) {
        guard let uniforms3D, drawer.hasVolumes(for: target) else { return }
        var all = sets
        all[0] = lighting
        volumePassLights[target.map { ObjectIdentifier($0) }] =
            VolumePassLight(lighting: all, shadowMap: shadowMap, uniforms3D: uniforms3D)
    }

    /// Composite this pass's volumes over `color`, ending each march at `depth`
    /// (the pass's resolved depth). `phase` shifts every march's start offset;
    /// a frame taking several temporal samples gives each its own, so their
    /// average resolves the jitter instead of keeping one fixed grain. A pass
    /// with no volume (or no depth to read) leaves `color` untouched.
    func encodeVolumes(_ drawer: Drawer, target: RenderTarget?, color: MTLTexture,
                       depth: MTLTexture?, phase: Float, into cb: MTLCommandBuffer) {
        let key = target.map { ObjectIdentifier($0) }
        guard let depth, let pass = volumePassLights[key] else { return }
        volumePassLights[key] = nil
        let draws = drawer.volumeDraws.filter { $0.target === target }
        guard !draws.isEmpty else { return }
        volumeLightGeneration &+= 1

        // Farthest first, so nearer volumes composite over farther ones (by the
        // boxes' centers; two volumes that interpenetrate order as wholes).
        let eye = pass.lighting[0].map { SIMD3<Float>($0.cameraPosition.x, $0.cameraPosition.y,
                                                       $0.cameraPosition.z) } ?? .zero
        let ordered = draws.sorted { a, b in
            simd_distance(a.model.columns.3.xyz, eye) > simd_distance(b.model.columns.3.xyz, eye)
        }

        // The grids and their light transmittance first, in a compute pass ahead
        // of the composite.
        struct Prepared {
            var draw: OllinVolumeDraw
            var grid: MTLTexture
            var lit: [MTLTexture?]
            var lighting: OllinLighting
            var scissor: MTLScissorRect?
        }
        var prepared: [Prepared] = []
        var pending: [(texture: MTLTexture, grid: MTLTexture, draw: OllinVolumeDraw, ray: SIMD4<Float>)] = []
        for item in ordered {
            guard let grid = item.volume.texture(for: device) else { continue }
            let lighting = pass.lighting[item.lightSet] ?? pass.lighting[0]!
            var gpu = makeVolumeDraw(item, phase: phase)
            var lit: [MTLTexture?] = []
            var litIndices = SIMD4<Float>(repeating: -1)
            if gpu.scatter.w > 0, lighting.enabled != 0 {
                let count = min(Int(lighting.lightCount), Int(OLLIN_MAX_LIGHTS))
                for index in 0 ..< count where lit.count < Int(OLLIN_VOLUME_MAX_LIT) {
                    let light = lightAt(lighting, index)
                    let ray: SIMD4<Float>
                    switch light.kind {
                    case 0: ray = SIMD4(light.direction.x, light.direction.y, light.direction.z, 0)
                    case 1, 2: ray = SIMD4(light.position.x, light.position.y, light.position.z, 1)
                    default: continue
                    }
                    let lightKey = VolumeLightKey(content: item.volume.contentID,
                                                  model: item.model.flatArray,
                                                  density: gpu.medium.x, lightRay: ray)
                    if let cached = volumeLightCache[lightKey] {
                        volumeLightCache[lightKey]?.used = volumeLightGeneration
                        lit.append(cached.texture)
                    } else if let texture = makeVolumeLightTexture(for: item.volume) {
                        volumeLightCache[lightKey] = (texture, volumeLightGeneration)
                        pending.append((texture, grid, gpu, ray))
                        lit.append(texture)
                    } else {
                        continue
                    }
                    litIndices[lit.count - 1] = Float(index)
                }
            }
            gpu.litLights = litIndices
            prepared.append(Prepared(draw: gpu, grid: grid, lit: lit, lighting: lighting,
                                     scissor: volumeScissor(item.model, uniforms: pass.uniforms3D,
                                                            width: color.width, height: color.height)))
        }
        // A transmittance grid no volume has asked for in a few passes goes.
        volumeLightCache = volumeLightCache.filter { volumeLightGeneration &- $0.value.used < 8 }
        guard !prepared.isEmpty else { return }

        if !pending.isEmpty, let kernel = try? libraryComputePipeline("ollin_volume_light_kernel"),
           let encoder = cb.makeComputeCommandEncoder() {
            encoder.label = "Ollin volume light"
            encoder.setComputePipelineState(kernel)
            for job in pending {
                var draw = job.draw
                var ray = job.ray
                encoder.setTexture(job.texture, index: 0)
                encoder.setTexture(job.grid, index: 1)
                encoder.setBytes(&draw, length: MemoryLayout<OllinVolumeDraw>.stride, index: 0)
                encoder.setBytes(&ray, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
                encoder.dispatchThreads(MTLSize(width: job.texture.width, height: job.texture.height,
                                                depth: job.texture.depth),
                                        threadsPerThreadgroup: MTLSize(width: 4, height: 4, depth: 4))
            }
            encoder.endEncoding()
        }

        let colorFormat: MTLPixelFormat? = color.pixelFormat == linearFormat ? nil : color.pixelFormat
        guard let state = try? pipeline(.volume(color: colorFormat)) else { return }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = countedEncoder(cb, descriptor, caller: "volumes") else { return }
        encoder.setRenderPipelineState(state)
        var uniforms = pass.uniforms3D
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms3D>.stride, index: 2)
        encoder.setFragmentTexture(depth, index: 1)
        encoder.setFragmentTexture(pass.shadowMap ?? ensureDummyShadowMap(), index: 2)
        if let shadowSampler { encoder.setFragmentSamplerState(shadowSampler, index: 0) }
        if iblPlaceholderCube == nil { iblPlaceholderCube = makeCubeTexture(face: 1, mipped: false) }
        encoder.setFragmentTexture(currentIBLIrradiance ?? iblPlaceholderCube, index: 8)
        encoder.setFragmentTexture(iesArrayTexture ?? shapingStandIn(), index: 10)
        encoder.setFragmentTexture(cookieArrayTexture ?? shapingStandIn(), index: 11)
        let standIn = volumeStandIn()
        for item in prepared {
            var draw = item.draw
            var lighting = item.lighting
            encoder.setFragmentBytes(&draw, length: MemoryLayout<OllinVolumeDraw>.stride, index: 0)
            encoder.setFragmentBytes(&lighting, length: MemoryLayout<OllinLighting>.stride, index: 1)
            encoder.setFragmentTexture(item.grid, index: 0)
            for slot in 0 ..< Int(OLLIN_VOLUME_MAX_LIT) {
                let texture = slot < item.lit.count ? item.lit[slot] : nil
                encoder.setFragmentTexture(texture ?? standIn, index: 4 + slot)
            }
            let scissor = item.scissor ?? MTLScissorRect(x: 0, y: 0, width: color.width,
                                                         height: color.height)
            guard scissor.width > 0, scissor.height > 0 else { continue }
            encoder.setScissorRect(scissor)
            profile.drawCalls += 1
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    /// The march's start-offset shift for temporal sample `index`: golden-ratio
    /// steps, so any run of samples spreads its offsets evenly over a step.
    func volumeJitterPhase(_ index: Int) -> Float {
        let phase = Double(index) * 0.618_033_988_749_895
        return Float(phase - phase.rounded(.down))
    }

    /// The draw's GPU record: placement, step, and the medium in linear light.
    func makeVolumeDraw(_ item: VolumeDraw, phase: Float) -> OllinVolumeDraw {
        let volume = item.volume
        let finest = 1 / Float(max(volume.width, volume.height, volume.depth) - 1)
        let medium = item.medium
        let density = Float(max(0, medium.density))
        let scatter = medium.color.linearRGBA
        let glow = medium.glow.linearRGBA * Float(max(0, medium.glowIntensity))
        let scatters: Float = density > 0 && max(scatter.x, scatter.y, scatter.z) > 0 ? 1 : 0
        return OllinVolumeDraw(
            model: item.model,
            inverseModel: item.model.inverse,
            grid: SIMD4(Float(volume.width), Float(volume.height), Float(volume.depth), 0.5 * finest),
            medium: SIMD4(density, Float(min(0.95, max(-0.95, medium.anisotropy))),
                          phase, MetalRenderer.volumeMaxSteps),
            scatter: SIMD4(scatter.x, scatter.y, scatter.z, scatters),
            glow: SIMD4(glow.x, glow.y, glow.z, 0),
            litLights: SIMD4(repeating: -1))
    }

    /// A light-transmittance grid sized for `volume` (its own resolution, up to
    /// `volumeLightMaxSamples` a side), written by the light kernel.
    private func makeVolumeLightTexture(for volume: Volume) -> MTLTexture? {
        let cap = MetalRenderer.volumeLightMaxSamples
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Float
        descriptor.width = min(volume.width, cap)
        descriptor.height = min(volume.height, cap)
        descriptor.depth = min(volume.depth, cap)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Ollin volume light"
        return texture
    }

    /// The fully lit transmittance grid an unused light slot reads (never
    /// sampled, since no light index names the slot; bound so every argument is).
    private func volumeStandIn() -> MTLTexture? {
        if let volumeLightStandIn { return volumeLightStandIn }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r16Float
        descriptor.width = 2
        descriptor.height = 2
        descriptor.depth = 2
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let ones = [Float16](repeating: 1, count: 8)
        ones.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake3D(0, 0, 0, 2, 2, 2), mipmapLevel: 0, slice: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: 4, bytesPerImage: 8)
        }
        volumeLightStandIn = texture
        return texture
    }

    /// The box's footprint on the target, from its eight corners through the
    /// pass's view-projection, padded a pixel; nil (the whole target) when a
    /// corner lies behind the camera, where a projected bound means nothing.
    private func volumeScissor(_ model: simd_float4x4, uniforms: Uniforms3D,
                               width: Int, height: Int) -> MTLScissorRect? {
        let viewProjection = uniforms.projection * uniforms.view
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for corner in 0 ..< 8 {
            let p = SIMD4<Float>(corner & 1 == 0 ? -0.5 : 0.5, corner & 2 == 0 ? -0.5 : 0.5,
                                 corner & 4 == 0 ? -0.5 : 0.5, 1)
            let clip = viewProjection * (model * p)
            if clip.w <= 1e-4 { return nil }
            let ndc = SIMD2(clip.x, clip.y) / clip.w
            lo = simd_min(lo, ndc)
            hi = simd_max(hi, ndc)
        }
        let x0 = Int(((lo.x + 1) * 0.5 * Float(width)).rounded(.down)) - 1
        let x1 = Int(((hi.x + 1) * 0.5 * Float(width)).rounded(.up)) + 1
        let y0 = Int(((1 - hi.y) * 0.5 * Float(height)).rounded(.down)) - 1
        let y1 = Int(((1 - lo.y) * 0.5 * Float(height)).rounded(.up)) + 1
        let left = max(0, min(width, x0)), right = max(0, min(width, x1))
        let top = max(0, min(height, y0)), bottom = max(0, min(height, y1))
        return MTLScissorRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }

    /// Light `index` of a lighting uniform's fixed-size inline list.
    private func lightAt(_ lighting: OllinLighting, _ index: Int) -> OllinLight {
        withUnsafeBytes(of: lighting.lights) { raw in
            raw.bindMemory(to: OllinLight.self)[index]
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

private extension simd_float4x4 {
    var flatArray: [Float] {
        [columns.0, columns.1, columns.2, columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
}
